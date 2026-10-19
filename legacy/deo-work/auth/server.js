// Dẹo Work — dịch vụ đăng nhập.
// Xác minh Google ID token (chỉ scope openid/email/profile), đổi mã mời, cấp JWT cho PostgREST.
// Không lưu gì ngoài bảng users/memberships trong Postgres (qua hàm app.auth_login).
import http from "node:http";
import { OAuth2Client } from "google-auth-library";
import { SignJWT, jwtVerify } from "jose";
import pg from "pg";

const env = (k, d) => process.env[k] ?? d;
const PORT = Number(env("PORT", 8090));
const GOOGLE_CLIENT_ID = env("GOOGLE_CLIENT_ID", "");
const SECRET = new TextEncoder().encode(env("PGRST_JWT_SECRET", ""));
const TTL_DAYS = Number(env("SESSION_DAYS", 7));
const AGENT_EMAIL = env("AGENT_EMAIL", "");
const DEV_LOGIN = env("DEV_LOGIN", "0") === "1";
const PROD = env("NODE_ENV", "development") === "production";

if (SECRET.length < 32) throw new Error("PGRST_JWT_SECRET phải dài ít nhất 32 ký tự");
if (PROD && DEV_LOGIN) throw new Error("DEV_LOGIN không được bật khi NODE_ENV=production");
if (!GOOGLE_CLIENT_ID && !DEV_LOGIN) throw new Error("Thiếu GOOGLE_CLIENT_ID");

const pool = new pg.Pool({ connectionString: env("DATABASE_URL"), max: 4 });
const google = new OAuth2Client(GOOGLE_CLIENT_ID);

// Giới hạn đơn giản: 30 yêu cầu/phút/IP
const hits = new Map();
function limited(ip) {
  const now = Date.now(), w = hits.get(ip) || [];
  const recent = w.filter((t) => now - t < 60_000);
  recent.push(now); hits.set(ip, recent);
  return recent.length > 30;
}
setInterval(() => { const now = Date.now(); for (const [k, v] of hits) if (!v.some((t) => now - t < 60_000)) hits.delete(k); }, 60_000).unref();

async function issue(userId, email, name) {
  const exp = Math.floor(Date.now() / 1000) + TTL_DAYS * 86400;
  const token = await new SignJWT({ role: "app_user", email, name })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" }).setSubject(userId).setIssuedAt().setExpirationTime(exp).sign(SECRET);
  return { token, expires_at: new Date(exp * 1000).toISOString() };
}

async function identity(credential) {
  if (DEV_LOGIN && credential.startsWith("dev:")) {
    // Chỉ để thử nghiệm cục bộ: "dev:<email>:<tên>"
    const [, email, name] = credential.split(":");
    return { sub: "dev-" + email, email, name: name || email, picture: null };
  }
  const ticket = await google.verifyIdToken({ idToken: credential, audience: GOOGLE_CLIENT_ID });
  const p = ticket.getPayload();
  if (!p?.email_verified) throw Object.assign(new Error("Email Google chưa được xác minh"), { status: 400 });
  return { sub: p.sub, email: p.email, name: p.name || p.email, picture: p.picture || null };
}

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify(body));
}
async function readJson(req) {
  let s = ""; for await (const c of req) { s += c; if (s.length > 16_384) throw Object.assign(new Error("Yêu cầu quá lớn"), { status: 413 }); }
  try { return s ? JSON.parse(s) : {}; } catch { throw Object.assign(new Error("JSON không hợp lệ"), { status: 400 }); }
}
function dbError(e) {
  if (e.code === "28000") return { status: 403, body: { code: "INVITE_REQUIRED", message: "Tài khoản này chưa có trong hệ thống. Nhập mã mời quản trị gửi cho bạn." } };
  if (e.code === "22023") return { status: 400, body: { code: "INVALID", message: e.message } };
  if (e.code === "42501") return { status: 403, body: { code: "FORBIDDEN", message: e.message } };
  return null;
}

const server = http.createServer(async (req, res) => {
  const ip = req.headers["cf-connecting-ip"] || req.headers["x-forwarded-for"]?.split(",")[0] || req.socket.remoteAddress;
  const url = new URL(req.url, "http://x");
  try {
    if (req.method === "GET" && url.pathname === "/auth/health") return send(res, 200, { ok: true });
    if (req.method === "GET" && url.pathname === "/auth/config")
      return send(res, 200, { google_client_id: GOOGLE_CLIENT_ID, agent_email: AGENT_EMAIL, dev_login: DEV_LOGIN });
    if (req.method !== "POST") return send(res, 404, { message: "Không có" });
    if (limited(ip)) return send(res, 429, { message: "Thử quá nhiều lần. Đợi một phút rồi thử lại." });

    if (url.pathname === "/auth/google") {
      const { credential, invite } = await readJson(req);
      if (typeof credential !== "string" || credential.length < 10) return send(res, 400, { message: "Thiếu thông tin đăng nhập Google" });
      let who;
      try { who = await identity(credential); }
      catch (e) { return send(res, e.status || 401, { message: e.status ? e.message : "Không xác minh được tài khoản Google. Đăng nhập lại." }); }
      try {
        const { rows } = await pool.query("select app.auth_login($1,$2,$3,$4,$5) as id",
          [who.sub, who.email, who.name, who.picture, typeof invite === "string" ? invite : null]);
        return send(res, 200, { ...(await issue(rows[0].id, who.email, who.name)), email: who.email });
      } catch (e) {
        const m = dbError(e); if (m) return send(res, m.status, { ...m.body, email: who.email });
        throw e;
      }
    }

    if (url.pathname === "/auth/refresh") {
      const tok = (req.headers.authorization || "").replace(/^Bearer\s+/i, "");
      let claims;
      try { ({ payload: claims } = await jwtVerify(tok, SECRET, { algorithms: ["HS256"] })); }
      catch { return send(res, 401, { message: "Phiên đã hết hạn. Đăng nhập lại." }); }
      if (claims.role !== "app_user") return send(res, 403, { message: "Không làm mới được mã này" });
      const { rows } = await pool.query("select app.auth_check($1) as ok", [claims.sub]);
      if (!rows[0].ok) return send(res, 403, { message: "Tài khoản đã bị khóa" });
      return send(res, 200, await issue(claims.sub, claims.email, claims.name));
    }
    return send(res, 404, { message: "Không có" });
  } catch (e) {
    console.error(new Date().toISOString(), req.method, url.pathname, e.message);
    return send(res, e.status || 500, { message: e.status ? e.message : "Lỗi máy chủ. Thử lại sau." });
  }
});
server.listen(PORT, () => console.log(`deo-auth nghe cổng ${PORT}${DEV_LOGIN ? " (DEV_LOGIN bật)" : ""}`));
