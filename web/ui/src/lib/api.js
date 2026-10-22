// Gọi máy chủ web (BFF) cùng nguồn gốc. Phiên nằm trong cookie HttpOnly; mã CSRF lấy từ /app/api/me và gửi kèm mọi lệnh gọi.
let csrf = "";
const listeners = new Set();
export const onUnauthorized = (fn) => { listeners.add(fn); return () => listeners.delete(fn); };

export class ApiError extends Error {
  constructor(message, status, code) { super(message); this.status = status; this.code = code; }
}

async function send(method, path, body) {
  let res;
  try {
    res = await fetch(`/app/api/${path}`, {
      method, credentials: "same-origin",
      headers: { accept: "application/json", ...(method === "POST" ? { "content-type": "application/json", "x-csrf-token": csrf, "x-requested-with": "eos" } : {}) },
      body: method === "POST" ? JSON.stringify(body ?? {}) : undefined,
    });
  } catch { throw new ApiError("Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.", 0); }
  let data = null;
  try { data = await res.json(); } catch { /* không phải JSON */ }
  if (res.status === 401) { listeners.forEach((f) => f()); throw new ApiError(data?.error || "Phiên đăng nhập đã hết hạn", 401, "UNAUTHENTICATED"); }
  if (!res.ok) throw new ApiError(data?.error || `Lỗi ${res.status}`, res.status, data?.code);
  return data;
}

export const rpc = (fn, params = {}) => send("POST", `rpc/${fn}`, params);
export const getConfig = () => send("GET", "config");
export async function getMe() { const m = await send("GET", "me"); csrf = m.csrf || ""; return m; }
export const logout = () => send("POST", "logout", {});
export const join = (code) => send("POST", "join", { code });
