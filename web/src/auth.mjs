// Đăng nhập Google (OIDC, code flow + PKCE), phiên bằng cookie ký HMAC, CSRF, mã mời.
// Không có bảng phiên: cookie chứa {sub, csrf, exp} đã ký; MỖI lệnh gọi đều qua hàm CSDL kiểm tài khoản nên khóa trong core.users có hiệu lực ngay.
import crypto from 'node:crypto';
import { eq } from './security.mjs';

const b64u = (buf) => Buffer.from(buf).toString('base64url');
const rnd = (n = 32) => b64u(crypto.randomBytes(n));
const INVITE = /^[A-Z0-9]{8}$/;

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
  const nowSec = () => Math.floor(Date.now() / 1000);

  // ----- phiên -----
  const startSession = (res, sub) => setCookie(res, 'eos_s', sign({ sub, csrf: rnd(24), exp: nowSec() + cfg.sessionTtlSec }), { maxAge: cfg.sessionTtlSec });
  const readSession = (req) => unsign(cookies(req).eos_s);

  // API: gắn req.session; chưa đăng nhập -> 401 JSON (giao diện tự chuyển sang màn đăng nhập)
  const requireSession = (req, res, next) => {
    const s = readSession(req);
    if (!s) { clearCookie(res, 'eos_s'); return res.status(401).json({ error: 'Chưa đăng nhập', code: 'UNAUTHENTICATED' }); }
    req.session = s; next();
  };
  const csrfCheck = (req, res, next) => {
    if (!req.session || !eq(req.get('x-csrf-token') ?? '', req.session.csrf)) return res.status(403).json({ error: 'Phiên làm việc hết hạn hoặc yêu cầu không hợp lệ. Tải lại trang rồi thử lại.', code: 'CSRF' });
    next();
  };
  // Tiêu đề tùy chỉnh: trình duyệt không cho trang khác nguồn tự đặt mà không qua CORS (chúng ta không bật CORS)
  const xhrOnly = (req, res, next) => (req.get('x-requested-with') === 'eos' && req.is('application/json')
    ? next() : res.status(400).json({ error: 'Yêu cầu không hợp lệ' }));

  // ----- Google OIDC -----
  const redirectUri = `${cfg.publicUrl}/app/auth/callback`;
  const toLogin = (res, e) => res.redirect(303, `/app/#/login?e=${e}`);

  const begin = (req, res) => {
    if (!cfg.googleEnabled) return toLogin(res, 'config');
    const invite = INVITE.test(String(req.query.invite || '').toUpperCase()) ? String(req.query.invite).toUpperCase() : '';
    const state = rnd(16), nonce = rnd(16), verifier = rnd(32);
    const challenge = b64u(crypto.createHash('sha256').update(verifier).digest());
    setCookie(res, 'eos_o', sign({ state, nonce, verifier, invite, exp: nowSec() + 600 }), { maxAge: 600, path: '/app/auth' });
    const q = new URLSearchParams({ client_id: cfg.google.clientId, redirect_uri: redirectUri, response_type: 'code', scope: 'openid email profile',
      state, nonce, code_challenge: challenge, code_challenge_method: 'S256', prompt: 'select_account' });
    res.redirect(303, `${cfg.google.authUrl}?${q}`);
  };

  const login = (who, invite) => db.asAnon((c) => db.one(c, 'SELECT agent.app_login($1::jsonb) AS r', [JSON.stringify({ ...who, invite })]));

  const callback = async (req, res) => {
    const o = unsign(cookies(req).eos_o);
    clearCookie(res, 'eos_o', '/app/auth');
    const fail = (why, e = 'denied') => { console.log(JSON.stringify({ evt: 'login_denied', why })); toLogin(res, e); };
    if (!o || !req.query.state || !eq(req.query.state, o.state)) return fail('state', 'state');
    if (req.query.error || !req.query.code) return fail(`google:${String(req.query.error || 'no_code').slice(0, 40)}`, 'google');
    let tok;
    try {
      const r = await fetch(cfg.google.tokenUrl, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ code: String(req.query.code), client_id: cfg.google.clientId, client_secret: cfg.google.clientSecret,
          redirect_uri: redirectUri, grant_type: 'authorization_code', code_verifier: o.verifier }) });
      if (!r.ok) return fail(`token_http_${r.status}`, 'google');
      tok = await r.json();
    } catch { return fail('token_network', 'google'); }
    // id_token nhận trực tiếp từ điểm cuối token của Google qua TLS: kiểm iss, aud, exp, nonce (OIDC Core 3.1.3.7)
    let p;
    try { p = JSON.parse(Buffer.from(String(tok.id_token).split('.')[1], 'base64url').toString('utf8')); } catch { return fail('id_token', 'google'); }
    const okIss = p.iss === 'https://accounts.google.com' || p.iss === 'accounts.google.com';
    if (!okIss || p.aud !== cfg.google.clientId || !(p.exp > nowSec()) || !eq(p.nonce ?? '', o.nonce)) return fail('claims', 'google');
    if (p.email_verified !== true || !p.email || !p.sub) return fail('email_not_verified');
    const who = { email: p.email, sub: p.sub, name: p.name || '', avatar: p.picture || '' };
    const r = await login(who, o.invite || '');
    if (r?.ok) { console.log(JSON.stringify({ evt: 'login_ok', user: r.user_id })); startSession(res, r.user_id); return res.redirect(303, '/app/#/today'); }
    if (r?.reason === 'invite_required' || r?.reason === 'invite_invalid') {
      // danh tính Google đã xác thực nhưng chưa vào được công ty: giữ 10 phút để nhập (lại) mã mời
      setCookie(res, 'eos_p', sign({ ...who, exp: nowSec() + 600 }), { maxAge: 600, path: '/app/api' });
      return fail(`invite:${r.reason}`, r.reason);
    }
    return fail(`app_login:${r?.reason}`);
  };

  // Nhập mã mời sau khi đã xác thực Google
  const join = async (req, res) => {
    const pend = unsign(cookies(req).eos_p);
    const code = String(req.body?.code || '').toUpperCase();
    if (!pend) return res.status(401).json({ error: 'Phiên đăng nhập Google đã hết hạn. Đăng nhập lại rồi nhập mã.', code: 'UNAUTHENTICATED' });
    if (!INVITE.test(code)) return res.status(400).json({ error: 'Mã mời gồm 8 ký tự chữ và số' });
    const r = await login({ email: pend.email, sub: pend.sub, name: pend.name, avatar: pend.avatar }, code);
    if (!r?.ok) {
      console.log(JSON.stringify({ evt: 'join_denied', why: r?.reason }));
      return res.status(r?.reason === 'invite_invalid' ? 400 : 403).json({ error: r?.message || 'Không vào được. Liên hệ quản trị công ty.' });
    }
    console.log(JSON.stringify({ evt: 'login_ok', user: r.user_id, via: 'invite' }));
    clearCookie(res, 'eos_p', '/app/api');
    startSession(res, r.user_id);
    res.json({ ok: true });
  };

  const logout = (req, res) => { clearCookie(res, 'eos_s'); res.json({ ok: true }); };
  return { requireSession, csrfCheck, xhrOnly, begin, callback, join, logout, readSession, sign, unsign, startSession };
}
