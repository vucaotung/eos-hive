// Ghi kết quả vào thư mục Drive cá nhân của người dùng.
// Dùng tài khoản agent của Workspace (đã được chia sẻ quyền Người chỉnh sửa trên thư mục mỗi người).
// Nội dung đi thẳng từ agent cá nhân lên Drive; máy chủ không ghi tệp xuống đĩa.
const API = process.env.DRIVE_API_BASE || 'https://www.googleapis.com';
const TOKEN_URL = process.env.GOOGLE_TOKEN_URL || 'https://oauth2.googleapis.com/token';
const FOLDER = 'application/vnd.google-apps.folder';
export const MAX_BYTES = 10 * 1024 * 1024;

let cached = { token: null, exp: 0 };

async function accessToken() {
  if (cached.token && Date.now() < cached.exp - 60_000) return cached.token;
  const body = new URLSearchParams({
    client_id: process.env.GOOGLE_CLIENT_ID,
    client_secret: process.env.GOOGLE_CLIENT_SECRET,
    refresh_token: process.env.GOOGLE_REFRESH_TOKEN,
    grant_type: 'refresh_token',
  });
  const r = await fetch(TOKEN_URL, { method: 'POST', body });
  if (!r.ok) throw new Error(`Google token: ${r.status}`);
  const j = await r.json();
  cached = { token: j.access_token, exp: Date.now() + j.expires_in * 1000 };
  return cached.token;
}

async function gapi(path, init = {}) {
  const r = await fetch(API + path, {
    ...init,
    headers: { Authorization: `Bearer ${await accessToken()}`, ...(init.headers || {}) },
  });
  if (!r.ok) {
    const text = await r.text().catch(() => '');
    const err = new Error(`Drive ${r.status}: ${text.slice(0, 200)}`);
    err.status = r.status;
    throw err;
  }
  return r.json();
}

const q = (s) => s.replace(/\\/g, '\\\\').replace(/'/g, "\\'");

async function ensureFolder(parentId, name) {
  const found = await gapi(`/drive/v3/files?q=${encodeURIComponent(
    `'${q(parentId)}' in parents and name = '${q(name)}' and mimeType = '${FOLDER}' and trashed = false`)}&fields=files(id)&supportsAllDrives=true&includeItemsFromAllDrives=true`);
  if (found.files?.length) return found.files[0].id;
  const made = await gapi('/drive/v3/files?fields=id&supportsAllDrives=true', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, mimeType: FOLDER, parents: [parentId] }),
  });
  return made.id;
}

// Tên tệp an toàn: bỏ ký tự cấm, thêm tiền tố T-<số> để drive_sync và người đọc nhận ra
export function resultName(taskId, filename) {
  const clean = String(filename).replace(/[\\/:*?"<>|\u0000-\u001f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 120) || 'ket-qua.md';
  return clean.startsWith(`T-${taskId}`) ? clean : `T-${taskId} - ${clean}`;
}

// Tải lên: <thư mục người dùng>/Kết quả/<YYYY-MM>/T-<số> - <tên>
export async function uploadResult({ userFolderId, taskId, filename, mime, bytes, now = new Date() }) {
  if (bytes.length > MAX_BYTES) throw new Error(`Tệp quá ${MAX_BYTES / 1048576} MB`);
  const month = new Date(now.getTime() + 7 * 3600_000).toISOString().slice(0, 7);   // theo giờ Việt Nam
  const resultsId = await ensureFolder(userFolderId, 'Kết quả');
  const monthId = await ensureFolder(resultsId, month);
  const name = resultName(taskId, filename);
  const boundary = 'eos' + Math.random().toString(16).slice(2);
  const meta = JSON.stringify({ name, parents: [monthId], description: `Enterprise OS · T-${taskId}` });
  const body = Buffer.concat([
    Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${meta}\r\n--${boundary}\r\nContent-Type: ${mime}\r\n\r\n`),
    bytes,
    Buffer.from(`\r\n--${boundary}--`),
  ]);
  const f = await gapi('/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id,name,mimeType,size,webViewLink', {
    method: 'POST',
    headers: { 'Content-Type': `multipart/related; boundary=${boundary}` },
    body,
  });
  return { driveId: f.id, name: f.name, mime: f.mimeType || mime, size: Number(f.size || bytes.length), url: f.webViewLink, folder: `Kết quả/${month}` };
}

// Kiểm tra một tệp có nằm trong thư mục của người dùng không (đi ngược tối đa 6 cấp thư mục cha)
export async function fileInsideFolder(fileId, userFolderId) {
  let meta = await gapi(`/drive/v3/files/${encodeURIComponent(fileId)}?fields=id,name,mimeType,size,webViewLink,parents&supportsAllDrives=true`);
  const file = meta;
  const path = [];
  for (let depth = 0; depth < 6; depth++) {
    const parent = meta.parents?.[0];
    if (!parent) return { inside: false, file };
    if (parent === userFolderId) return { inside: true, file, folder: path.reverse().join('/') || '.' };
    meta = await gapi(`/drive/v3/files/${encodeURIComponent(parent)}?fields=id,name,parents&supportsAllDrives=true`);
    path.push(meta.name);
  }
  return { inside: false, file };
}

export function driveIdFromUrl(url) {
  const m = String(url).match(/\/d\/([A-Za-z0-9_-]{10,})/) || String(url).match(/[?&]id=([A-Za-z0-9_-]{10,})/);
  return m ? m[1] : null;
}
