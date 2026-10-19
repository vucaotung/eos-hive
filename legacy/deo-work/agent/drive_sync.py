#!/usr/bin/env python3
"""Agent quét thư mục Drive cá nhân của nhân viên → ghi SIÊU DỮ LIỆU vào Dẹo Work.

Chạy bằng tài khoản Workspace riêng của agent (vd hermes-bot@enterpriseos.bond), mà nhân viên đã chia sẻ thư mục
với quyền Người chỉnh sửa. Không tải nội dung tệp, không sao chép tệp về máy chủ: chỉ đọc tên, loại, link, ngày sửa.

Việc của script, mỗi lần chạy (cron 15 phút trên VPS 173, cạnh Hermes):
  1. Lấy hàng đợi thư mục cần kiểm tra: POST /rpc/agent_drive_queue
  2. Với mỗi người: kiểm tra thư mục tồn tại, tên đúng mẫu "DEO - <công ty> - <phòng> - <Họ tên>",
     tài khoản agent có quyền writer/organizer/owner → ghi kết quả agent_drive_result
  3. Liệt kê tệp (đệ quy tối đa 3 cấp, tối đa 2000 tệp) → agent_drive_files.
     Tệp có tên bắt đầu "T-123" được tự gắn vào việc T-123.

Biến môi trường (đọc từ .env của profile Hermes, không đưa vào ngữ cảnh LLM):
  DEO_API              https://work.enterpriseos.bond/api   (hoặc http://100.70.174.54:3000 qua Tailscale)
  DEO_AGENT_TOKEN      JWT role=agent (mint_jwt.py agent agent hermes:drive 90)
  GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_REFRESH_TOKEN
                       OAuth của tài khoản agent, scope https://www.googleapis.com/auth/drive.readonly
                       (lấy một lần bằng: python3 drive_sync.py --auth)
"""
import json, os, sys, time, unicodedata, urllib.parse, urllib.request

API = os.environ.get("DEO_API", "").rstrip("/")
TOKEN = os.environ.get("DEO_AGENT_TOKEN", "")
CID, CSECRET, REFRESH = (os.environ.get(k, "") for k in ("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GOOGLE_REFRESH_TOKEN"))
SCOPE = "https://www.googleapis.com/auth/drive.readonly"
FOLDER = "application/vnd.google-apps.folder"
MAX_FILES, MAX_DEPTH = 2000, 3


def http(method, url, body=None, headers=None, form=False):
    h = dict(headers or {})
    data = None
    if body is not None:
        if form:
            data = urllib.parse.urlencode(body).encode(); h["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(body).encode(); h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            t = r.read().decode()
            return r.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        try: return e.code, json.loads(t)
        except Exception: return e.code, {"message": t}


def deo(fn, **args):
    code, data = http("POST", f"{API}/rpc/{fn}", args, {"Authorization": f"Bearer {TOKEN}", "Accept": "application/json"})
    if code >= 300: raise RuntimeError(f"{fn}: {code} {data}")
    return data


_access = {"token": None, "exp": 0}
def gtoken():
    if _access["token"] and _access["exp"] > time.time() + 60: return _access["token"]
    code, data = http("POST", "https://oauth2.googleapis.com/token",
                      {"client_id": CID, "client_secret": CSECRET, "refresh_token": REFRESH, "grant_type": "refresh_token"}, form=True)
    if code != 200: raise RuntimeError(f"Không lấy được access token Google: {data}")
    _access.update(token=data["access_token"], exp=time.time() + data.get("expires_in", 3600))
    return _access["token"]


def drive(path, **params):
    params.setdefault("supportsAllDrives", "true")
    url = f"https://www.googleapis.com/drive/v3/{path}?{urllib.parse.urlencode(params)}"
    for attempt in range(4):
        code, data = http("GET", url, headers={"Authorization": f"Bearer {gtoken()}"})
        if code in (429, 500, 502, 503) and attempt < 3: time.sleep(2 ** attempt); continue
        return code, data


def norm(s):
    s = unicodedata.normalize("NFC", s or "").strip()
    return " ".join(s.split()).casefold()


def check_folder(item):
    """Trả (ok, ghi chú)."""
    code, f = drive(f"files/{item['folder_id']}", fields="id,name,mimeType,trashed,capabilities(canEdit),owners(emailAddress)")
    if code == 404: return False, "Agent không mở được thư mục. Kiểm tra link và đã chia sẻ cho tài khoản agent chưa."
    if code >= 300: return False, f"Drive trả lỗi {code}"
    if f.get("mimeType") != FOLDER: return False, "Link không phải thư mục."
    if f.get("trashed"): return False, "Thư mục đã bị chuyển vào thùng rác."
    if not f.get("capabilities", {}).get("canEdit"): return False, "Agent mới có quyền xem. Chia sẻ lại với quyền Người chỉnh sửa."
    want = [norm(n) for n in item["expected_names"] if n]
    if norm(f["name"]) not in want:
        return False, f"Tên thư mục là \"{f['name']}\", cần đổi thành \"{item['expected_names'][0]}\"."
    return True, "Tên thư mục và quyền chỉnh sửa đúng"


def list_files(folder_id):
    out, queue = [], [(folder_id, 0)]
    while queue and len(out) < MAX_FILES:
        fid, depth = queue.pop(0)
        token = None
        while True:
            params = {"q": f"'{fid}' in parents and trashed = false", "pageSize": 500,
                      "fields": "nextPageToken,files(id,name,mimeType,webViewLink,size,modifiedTime)", "includeItemsFromAllDrives": "true"}
            if token: params["pageToken"] = token
            code, data = drive("files", **params)
            if code >= 300: raise RuntimeError(f"Liệt kê tệp lỗi {code}: {data}")
            for f in data.get("files", []):
                if f["mimeType"] == FOLDER:
                    if depth + 1 < MAX_DEPTH: queue.append((f["id"], depth + 1))
                    continue
                out.append({"file_id": f["id"], "name": f["name"], "mime_type": f["mimeType"], "web_url": f.get("webViewLink") or f"https://drive.google.com/file/d/{f['id']}",
                            "size_bytes": int(f["size"]) if f.get("size") else None, "modified_at": f.get("modifiedTime")})
            token = data.get("nextPageToken")
            if not token or len(out) >= MAX_FILES: break
    return out[:MAX_FILES]


def run():
    if not (API and TOKEN and CID and CSECRET and REFRESH): sys.exit("Thiếu biến môi trường, xem đầu tệp.")
    queue = deo("agent_drive_queue") or []
    print(f"{len(queue)} thư mục cần kiểm tra")
    for item in queue:
        try:
            ok, note = check_folder(item)
            deo("agent_drive_result", p_user=item["user_id"], p_ok=ok, p_note=note)
            if ok:
                files = list_files(item["folder_id"])
                n = deo("agent_drive_files", p_user=item["user_id"], p_files=files)
                print(f"  {item['email']}: đúng, {n} tệp")
            else:
                print(f"  {item['email']}: {note}")
        except Exception as e:  # một người lỗi không làm dừng cả lượt
            print(f"  {item['email']}: lỗi {e}", file=sys.stderr)


def auth_once():
    """Lấy refresh token cho tài khoản agent (chạy một lần trên máy có trình duyệt)."""
    if not (CID and CSECRET): sys.exit("Đặt GOOGLE_CLIENT_ID và GOOGLE_CLIENT_SECRET (OAuth client loại Desktop) trước.")
    url = "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode({
        "client_id": CID, "redirect_uri": "http://127.0.0.1:8765", "response_type": "code", "scope": SCOPE,
        "access_type": "offline", "prompt": "consent", "login_hint": os.environ.get("AGENT_EMAIL", "")})
    print("1. Mở link sau, đăng nhập BẰNG TÀI KHOẢN AGENT, bấm Cho phép:\n", url)
    print("2. Trình duyệt chuyển tới http://127.0.0.1:8765/?code=... (trang lỗi là bình thường). Dán cả địa chỉ đó vào đây:")
    code = urllib.parse.parse_qs(urllib.parse.urlparse(input("> ").strip()).query)["code"][0]
    st, data = http("POST", "https://oauth2.googleapis.com/token", {"client_id": CID, "client_secret": CSECRET, "code": code,
                    "grant_type": "authorization_code", "redirect_uri": "http://127.0.0.1:8765"}, form=True)
    if st != 200: sys.exit(f"Lỗi: {data}")
    print("\nGOOGLE_REFRESH_TOKEN=" + data["refresh_token"] + "\nLưu dòng trên vào .env của profile Hermes (chmod 600). Không dán vào chat.")


if __name__ == "__main__":
    auth_once() if "--auth" in sys.argv else run()
