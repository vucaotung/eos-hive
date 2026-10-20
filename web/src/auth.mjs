// Đăng nhập Google (OIDC, code flow + PKCE), phiên bằng cookie ký HMAC, CSRF.
// Không có bảng phiên: cookie chứa {sub, csrf, exp} đã ký; MỖI yêu cầu đều gọi web_me() nên khóa tài khoản trong core.users có hiệu lực ngay.
import crypto from 'node:crypto';
import { eq } from './security.mjs';

const b64u = (buf) => Buffer.from(buf).toString('base64url');
const rnd = (n = 32) => b64u(crypto.randomBytes(n));

export function createAuth(cfg, db) {
  const mac = (s) => b64u(crypto.createHmac('sha256', cfg.sessionSecret).update(s).digest());
  const sign = (obj) => { const p = b64u(JSON.stringify(obj)); return `${p}.${mac(p)}`; };
  const unsign = (tok) => {
    if (typeof tok !== 'string' || !tok.includes('.')) return null;
    const [p, m] = tok.split('.');
    if (!eq(mac(p), m)) return null;
    try { const o = JSON.parse(Buffer.from(p, 'base64url').toString('utf8')); return o.exp > Date.now() / 1000 ? o : null; } catch { return null; }
  };
  const cookies = (req) => Object.fromEntries((req.headers.cookie || '').split(/;\s*/).filter(Boolean).map((c) => { const i = c.indexOf('='); return [c.slice(0, i), c.slice(i + 1)]; }));
  const setCookie = (res, name, value, { maxAge, path = '/app' } = {}) => {
    const parts = [`${name}=${value}`, `Path=${path}`, 'HttpOnly', 'SameSite=Lax'];
    if (maxAge !== undefined) parts.push(`Max-Age=${maxAge}`);
    if (cfg.secureCookies) parts.push('Secure');
    res.append('Set-Cookie', parts.join('; '));
  };
  const clearCookie = (res, name, path = '/app') => setCookie(res, name, '', { maxAge: 0, path });

  // ----- phiên -----
  const startSession = (res, sub) => {
    const exp = Math.floor(Date.now() / 1000) + cfg.sessionTtlSec;
    setCookie(res, 'eos_s', sign({ sub, csrf: rnd(24), exp }), { maxAge: cfg.sessionTtlSec });
  };
  const readSession = (req) => unsign(cookies(req).eos_s);

  // Gắn req.session + res.locals.me (từ CSDL). Chưa đăng nhập hoặc bị khóa -> chuyển về trang đăng nhập.
  const requireLogin = async (req, res, next) => {
    const s = readSession(req);
    const nextUrl = req.method === 'GET' ? req.originalUrl : '/app/';
    const toLogin = () => { clearCookie(res, 'eos_s'); res.redirect(303, `/app/login?next=${encodeURIComponent(nextUrl)}`); };
    if (!s) return toLogin();
    try {
      res.locals.me = await db.asUser(s.sub, (c) => db.one(c, 'SELECT agent.web_me() AS r'));
    } catch (e) { if (e.forbidden) return toLogin(); throw e; }
    req.session = s; res.locals.csrf = s.csrf;
    next();
  };
  const requireAdmin = (req, res, next) => (res.locals.me?.is_admin ? next() : res.status(403).type('text/plain').send('Chỉ quản trị hệ thống'));
  const csrfCheck = (req, res, next) => {
    if (!req.session || !eq(req.body?._csrf ?? '', req.session.csrf)) return res.status(403).type('text/plain').send('Phiên làm việc hết hạn hoặc yêu cầu không hợp lệ. Tải lại trang rồi thử lại.');
    next();
  };

  // ----- Google OIDC -----
  const safeNext = (n) => (typeof n === 'string' && /^\/app(\/[A-Za-z0-9_\-./?=&%]*)?$/.test(n) && !n.includes('//') && !n.includes('..') ? n : '/app/');
  const redirectUri = `${cfg.publicUrl}/app/auth/callback`;

  const begin = (req, res) => {
    if (!cfg.googleEnabled) return res.status(503).type('text/plain').send('Đăng nhập Google chưa được cấu hình.');
    const state = rnd(16), nonce = rnd(16), verifier = rnd(32);
    const challenge = b64u(crypto.createHash('sha256').update(verifier).digest());
    setCookie(res, 'eos_o', sign({ state, nonce, verifier, next: safeNext(req.query.next), exp: Math.floor(Date.now() / 1000) + 600 }), { maxAge: 600, path: '/app/auth' });
    const q = new URLSearchParams({ client_id: cfg.google.clientId, redirect_uri: redirectUri, response_type: 'code', scope: 'openid email profile',
      state, nonce, code_challenge: challenge, code_challenge_method: 'S256', prompt: 'select_account' });
    res.redirect(303, `${cfg.google.authUrl}?${q}`);
  };

  const callback = async (req, res) => {
    const o = unsign(cookies(req).eos_o);
    clearCookie(res, 'eos_o', '/app/auth');
    const fail = (code, why) => { console.log(JSON.stringify({ evt: 'login_denied', why })); res.status(code).type('text/html').send(deniedPage()); };
    if (!o || !req.query.state || !eq(req.query.state, o.state)) return fail(400, 'state');
    if (req.query.error || !req.query.code) return fail(400, `google:${String(req.query.error || 'no_code').slice(0, 40)}`);
    let tok;
    try {
      const r = await fetch(cfg.google.tokenUrl, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ code: String(req.query.code), client_id: cfg.google.clientId, client_secret: cfg.google.clientSecret,
          redirect_uri: redirectUri, grant_type: 'authorization_code', code_verifier: o.verifier }) });
      if (!r.ok) return fail(502, `token_http_${r.status}`);
      tok = await r.json();
    } catch { return fail(502, 'token_network'); }
    // id_token nhận trực tiếp từ điểm cuối token của Google qua TLS: kiểm iss, aud, exp, nonce (OIDC Core 3.1.3.7)
    let p;
    try { p = JSON.parse(Buffer.from(String(tok.id_token).split('.')[1], 'base64url').toString('utf8')); } catch { return fail(502, 'id_token'); }
    const okIss = p.iss === 'https://accounts.google.com' || p.iss === 'accounts.google.com';
    if (!okIss || p.aud !== cfg.google.clientId || !(p.exp > Date.now() / 1000) || !eq(p.nonce ?? '', o.nonce)) return fail(400, 'claims');
    if (p.email_verified !== true || !p.email || !p.sub) return fail(403, 'email_not_verified');
    const r = await db.asAnon((c) => db.one(c, 'SELECT agent.web_login($1,$2,$3,$4) AS r', [p.email, p.sub, p.name || '', p.picture || '']));
    if (!r?.ok) return fail(403, `web_login:${r?.reason}`);
    console.log(JSON.stringify({ evt: 'login_ok', user: r.user_id }));
    startSession(res, r.user_id);
    res.redirect(303, o.next || '/app/');
  };

  const logout = (req, res) => { clearCookie(res, 'eos_s'); res.redirect(303, '/app/login'); };
  return { requireLogin, requireAdmin, csrfCheck, begin, callback, logout, readSession, safeNext, sign, unsign, startSession };
}

// Trang từ chối dùng chung một câu cho mọi lý do: không tiết lộ email nào có trong hệ thống
export const deniedPage = () => `<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Không đăng nhập được</title><link rel="stylesheet" href="/app/static/app.css"></head><body class="center"><main class="card narrow"><h1>Không đăng nhập được</h1><p>Tài khoản Google này chưa được cấp quyền vào Tổ Ong, hoặc phiên đăng nhập đã hết hạn.</p><p><a class="btn" href="/app/login">Thử lại</a></p></main></body></html>`;
