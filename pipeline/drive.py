"""Máy khách Google Drive API v3 (OAuth refresh token, như `mcp/src/drive.mjs`). Chỉ dùng thư viện chuẩn.

Khóa lấy từ biến môi trường GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_REFRESH_TOKEN; không bao giờ in ra.
`http` có thể thay bằng hàm giả khi test: http(method, url, headers, body) -> (status, headers, bytes).
"""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = os.environ.get('DRIVE_API_BASE', 'https://www.googleapis.com')
TOKEN_URL = os.environ.get('GOOGLE_TOKEN_URL', 'https://oauth2.googleapis.com/token')
FOLDER = 'application/vnd.google-apps.folder'
SHORTCUT = 'application/vnd.google-apps.shortcut'
# Tệp Google gốc không tải trực tiếp được: xuất sang định dạng Office rồi chuyển Markdown
EXPORT = {
    'application/vnd.google-apps.document': ('application/vnd.openxmlformats-officedocument.wordprocessingml.document', '.docx'),
    'application/vnd.google-apps.spreadsheet': ('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.xlsx'),
    'application/vnd.google-apps.presentation': ('application/vnd.openxmlformats-officedocument.presentationml.presentation', '.pptx'),
}


class DriveError(RuntimeError):
    def __init__(self, status, msg):
        super().__init__(f'Drive {status}: {msg}')
        self.status = status


def _urlopen(method, url, headers, body):
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, dict(r.headers), r.read()
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers), e.read()


def q(s):
    return s.replace('\\', '\\\\').replace("'", "\\'")


class Drive:
    def __init__(self, client_id, client_secret, refresh_token, http=_urlopen, sleep=time.sleep):
        self._c = (client_id, client_secret, refresh_token)
        self.http, self.sleep = http, sleep
        self._tok, self._exp = None, 0.0

    @classmethod
    def from_env(cls, **kw):
        miss = [k for k in ('GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_REFRESH_TOKEN') if not os.environ.get(k)]
        if miss:
            raise DriveError(0, 'thiếu biến môi trường ' + ', '.join(miss))
        return cls(os.environ['GOOGLE_CLIENT_ID'], os.environ['GOOGLE_CLIENT_SECRET'], os.environ['GOOGLE_REFRESH_TOKEN'], **kw)

    def token(self):
        if self._tok and time.time() < self._exp - 60:
            return self._tok
        body = urllib.parse.urlencode({'client_id': self._c[0], 'client_secret': self._c[1], 'refresh_token': self._c[2],
                                       'grant_type': 'refresh_token'}).encode()
        st, _, data = self.http('POST', TOKEN_URL, {'Content-Type': 'application/x-www-form-urlencoded'}, body)
        if st != 200:
            raise DriveError(st, 'không lấy được access token')       # không đưa nội dung phản hồi vào lỗi
        j = json.loads(data)
        self._tok, self._exp = j['access_token'], time.time() + int(j.get('expires_in', 3600))
        return self._tok

    def _req(self, method, path, body=None, headers=None, retries=4):
        h = {'Authorization': f'Bearer {self.token()}', **(headers or {})}
        for i in range(retries):
            st, rh, data = self.http(method, API + path, h, body)
            if st in (429, 500, 502, 503, 504) and i < retries - 1:
                self.sleep(2 ** i)
                continue
            if st == 401 and i < retries - 1:
                self._tok = None
                h['Authorization'] = f'Bearer {self.token()}'
                continue
            if st >= 400:
                raise DriveError(st, data[:200].decode('utf-8', 'replace'))
            return rh, data
        raise DriveError(0, 'hết số lần thử')

    def _json(self, method, path, body=None, headers=None):
        _, data = self._req(method, path, body, headers)
        return json.loads(data) if data else {}

    # ---------- đọc ----------
    def children(self, folder_id):
        """Liệt kê mọi mục con (có phân trang)."""
        fields = 'nextPageToken,files(id,name,mimeType,size,md5Checksum,modifiedTime,shortcutDetails)'
        tok = None
        while True:
            p = {'q': f"'{q(folder_id)}' in parents and trashed = false", 'pageSize': '200', 'orderBy': 'folder,name', 'fields': fields,
                 'supportsAllDrives': 'true', 'includeItemsFromAllDrives': 'true'}
            if tok:
                p['pageToken'] = tok
            j = self._json('GET', '/drive/v3/files?' + urllib.parse.urlencode(p))
            yield from j.get('files', [])
            tok = j.get('nextPageToken')
            if not tok:
                return

    def download(self, file_id, dest, export_mime=None):
        """Tải về `dest` (Path). Tệp Google gốc dùng export_mime."""
        if export_mime:
            path = f'/drive/v3/files/{urllib.parse.quote(file_id)}/export?mimeType={urllib.parse.quote(export_mime)}'
        else:
            path = f'/drive/v3/files/{urllib.parse.quote(file_id)}?alt=media&supportsAllDrives=true'
        _, data = self._req('GET', path)
        dest = Path(dest)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        return len(data)

    # ---------- ghi (chỉ vào thư mục _md_deo do pipeline tạo) ----------
    def find(self, parent, name, mime=None):
        cond = f"'{q(parent)}' in parents and name = '{q(name)}' and trashed = false"
        if mime:
            cond += f" and mimeType = '{mime}'"
        j = self._json('GET', '/drive/v3/files?' + urllib.parse.urlencode(
            {'q': cond, 'fields': 'files(id,name)', 'supportsAllDrives': 'true', 'includeItemsFromAllDrives': 'true'}))
        return (j.get('files') or [None])[0]

    def ensure_folder(self, parent, name):
        f = self.find(parent, name, FOLDER)
        if f:
            return f['id']
        made = self._json('POST', '/drive/v3/files?fields=id&supportsAllDrives=true', json.dumps(
            {'name': name, 'mimeType': FOLDER, 'parents': [parent]}).encode(), {'Content-Type': 'application/json'})
        return made['id']

    def upload(self, parent, name, data, mime):
        """Tạo mới, hoặc cập nhật nội dung nếu thư mục đã có tệp cùng tên (tránh tệp trùng khi chạy lại)."""
        existing = self.find(parent, name)
        b = 'eos' + os.urandom(6).hex()
        meta = {'name': name} if existing else {'name': name, 'parents': [parent]}
        body = b''.join([f'--{b}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{json.dumps(meta)}\r\n--{b}\r\nContent-Type: {mime}\r\n\r\n'.encode(),
                         data, f'\r\n--{b}--'.encode()])
        h = {'Content-Type': f'multipart/related; boundary={b}'}
        fields = 'id,name,mimeType,size'
        if existing:
            return self._json('PATCH', f"/upload/drive/v3/files/{existing['id']}?uploadType=multipart&supportsAllDrives=true&fields={fields}", body, h)
        return self._json('POST', f'/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields={fields}', body, h)
