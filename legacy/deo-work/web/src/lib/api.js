// Gọi PostgREST (/api) và dịch vụ đăng nhập (/auth). Mã phiên lưu trong localStorage.
const KEY = "deo.session";

export const session = {
  get() { try { const s = JSON.parse(localStorage.getItem(KEY) || "null"); return s && new Date(s.expires_at) > new Date() ? s : null; } catch { return null; } },
  set(s) { try { s ? localStorage.setItem(KEY, JSON.stringify(s)) : localStorage.removeItem(KEY); } catch { /* bỏ qua */ } },
};

export class ApiError extends Error {
  constructor(message, status, code) { super(message); this.status = status; this.code = code; }
}

const listeners = new Set();
export const onUnauthorized = (fn) => { listeners.add(fn); return () => listeners.delete(fn); };

// Thông báo lỗi PostgreSQL/PostgREST sang câu người dùng hiểu
function humanize(status, body) {
  const m = body?.message || "";
  if (status === 401 || /JWT expired|JWSError/i.test(m)) return "Phiên đăng nhập đã hết hạn. Đăng nhập lại.";
  if (/permission denied/i.test(m)) return "Anh không có quyền làm việc này.";
  if (/violates check constraint/i.test(m)) return "Dữ liệu chưa hợp lệ. Kiểm tra lại các ô đã nhập.";
  if (/duplicate key/i.test(m)) return "Đã có mục trùng mã hoặc trùng tên.";
  return m || `Máy chủ trả lỗi ${status}`;
}

export async function api(path, { method = "GET", body, single = false, signal } = {}) {
  const s = session.get();
  const headers = { Accept: single ? "application/vnd.pgrst.object+json" : "application/json" };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (s) headers.Authorization = `Bearer ${s.token}`;
  let r;
  try { r = await fetch(`/api${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal }); }
  catch (e) { if (e.name === "AbortError") throw e; throw new ApiError("Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.", 0); }
  const text = await r.text();
  let data = null; try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  if (!r.ok) {
    if (r.status === 401) listeners.forEach((fn) => fn());
    throw new ApiError(humanize(r.status, data), r.status, data?.code);
  }
  return data;
}

export const rpc = (fn, args = {}, single = true) => api(`/rpc/${fn}`, { method: "POST", body: args, single });

export async function authCall(path, body, token) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  let r;
  try { r = await fetch(`/auth${path}`, { method: body ? "POST" : "GET", headers, body: body ? JSON.stringify(body) : undefined }); }
  catch { throw new ApiError("Không kết nối được máy chủ đăng nhập.", 0); }
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new ApiError(data.message || "Đăng nhập không thành công", r.status, data.code);
  return data;
}

// Làm mới phiên khi còn dưới 2 ngày
export async function maybeRefresh() {
  const s = session.get();
  if (!s) return;
  if (new Date(s.expires_at) - Date.now() > 2 * 86400e3) return;
  try { const n = await authCall("/refresh", {}, s.token); session.set({ ...s, ...n }); } catch { /* để lần sau */ }
}

// Dựng query PostgREST
export function qs(params) {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== null && v !== "") p.append(k, v);
  const s = p.toString();
  return s ? `?${s}` : "";
}
