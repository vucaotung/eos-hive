// Máy chủ web Tổ Ong: Express, chỉ nghe localhost, Caddy chuyển tiếp /app vào đây.
import express from 'express';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { loadConfig } from './config.mjs';
import { createDb } from './db.mjs';
import { createAuth } from './auth.mjs';
import { createRoutes } from './routes.mjs';
import { securityHeaders, hostGuard, noStore, rateLimiter } from './security.mjs';
import { errorPage } from './views.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));

export function buildApp(env = process.env) {
  const cfg = loadConfig(env);
  const db = createDb(cfg.databaseUrl);
  const auth = createAuth(cfg, db);
  const app = express();
  app.disable('x-powered-by');
  if (cfg.trustProxy) app.set('trust proxy', 1);
  app.use(securityHeaders(cfg));
  app.use(hostGuard(cfg));
  const limiter = rateLimiter({ max: cfg.loginRatePerMin, windowMs: 60_000 });   // đăng nhập, theo IP
  const writes = rateLimiter({ max: cfg.writeRatePerMin, windowMs: 60_000 })((q) => `w:${auth.readSession(q)?.sub || q.ip}`);   // thao tác ghi: 120 lượt/phút/người
  app.use('/app/static', express.static(path.join(here, '../public'), { maxAge: '1h', index: false, dotfiles: 'ignore' }));
  app.use('/app', noStore, express.urlencoded({ extended: false, limit: '100kb' }),
    // giới hạn thao tác ghi theo người dùng (hoặc IP khi chưa đăng nhập)
    (req, res, next) => (req.method === 'POST' ? writes(req, res, next) : next()),
    createRoutes({ cfg, db, auth, limiter }));
  app.get('/', (req, res) => res.redirect(302, '/app/'));
  app.use((err, req, res, next) => {                              // lỗi không lường trước: ghi nhật ký có mã, trả trang chung, không lộ chi tiết
    const ref = crypto.randomBytes(4).toString('hex');
    console.error(JSON.stringify({ evt: 'error', ref, path: req.path, msg: String(err?.message || err).slice(0, 300) }));
    if (res.headersSent) return next(err);
    res.status(500).type('html').send(String(errorPage({ title: 'Có lỗi xảy ra', message: `Thử lại sau. Mã tham chiếu: ${ref}`, me: res.locals.me, csrf: res.locals.csrf })));
  });
  app.locals.db = db; app.locals.cfg = cfg;
  return app;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const app = buildApp();
  const { port, host } = app.locals.cfg;
  const srv = app.listen(port, host, () => console.log(`eos-web lắng nghe ${host}:${port}`));
  const stop = () => { srv.close(() => app.locals.db.close().then(() => process.exit(0))); setTimeout(() => process.exit(0), 5000).unref(); };
  process.on('SIGTERM', stop); process.on('SIGINT', stop);
}
