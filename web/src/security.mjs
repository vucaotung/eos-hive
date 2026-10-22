// Tiêu đề bảo mật, kiểm tra Host/Origin, giới hạn tốc độ.
import crypto from 'node:crypto';

export function securityHeaders(cfg) {
  return (req, res, next) => {
    res.setHeader('Content-Security-Policy',
      "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' https://*.googleusercontent.com data:; font-src 'self'; connect-src 'self'; " +
      "manifest-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'");   // style 'unsafe-inline': thư viện giao diện đặt style theo phần tử; script vẫn chỉ 'self'
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Referrer-Policy', 'same-origin');
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=(), payment=()');
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    if (cfg.secureCookies) res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    next();
  };
}
export const noStore = (req, res, next) => { res.setHeader('Cache-Control', 'no-store'); next(); };

// Chặn Host lạ (tấn công Host header) và yêu cầu ghi từ origin khác
export function hostGuard(cfg) {
  return (req, res, next) => {
    if (req.get('host') !== cfg.host_header) return res.status(421).type('text/plain').send('Sai tên miền');
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      const origin = req.get('origin');
      if (origin && origin !== new URL(cfg.publicUrl).origin) return res.status(403).type('text/plain').send('Nguồn yêu cầu không hợp lệ');
      const site = req.get('sec-fetch-site');
      if (site && !['same-origin', 'none'].includes(site)) return res.status(403).type('text/plain').send('Yêu cầu chéo trang bị chặn');
    }
    next();
  };
}

export function rateLimiter({ max, windowMs }) {
  const hits = new Map();
  setInterval(() => { const now = Date.now(); for (const [k, v] of hits) if (v.reset < now) hits.delete(k); }, windowMs).unref();
  return (keyFn) => (req, res, next) => {
    const key = keyFn(req); const now = Date.now();
    const h = hits.get(key) || { n: 0, reset: now + windowMs };
    if (h.reset < now) { h.n = 0; h.reset = now + windowMs; }
    h.n++; hits.set(key, h);
    if (h.n > max) { res.setHeader('Retry-After', Math.ceil((h.reset - now) / 1000)); return res.status(429).type('text/plain').send('Thao tác quá nhanh, thử lại sau ít phút'); }
    next();
  };
}

export const eq = (a, b) => { const x = Buffer.from(String(a)); const y = Buffer.from(String(b)); return x.length === y.length && crypto.timingSafeEqual(x, y); };
