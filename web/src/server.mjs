// Máy chủ web Tổ Ong (Dẹo Work): Express, chỉ nghe localhost, Caddy chuyển tiếp /app vào đây.
// Phục vụ giao diện React đã dựng sẵn (web/public) và API JSON /app/api.
import express from 'express';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { loadConfig } from './config.mjs';
import { createDb } from './db.mjs';
import { createAuth } from './auth.mjs';
import { createRoutes } from './routes.mjs';
import { securityHeaders, hostGuard, noStore, rateLimiter } from './security.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const pub = path.join(here, '../public');

export function buildApp(env = process.env) {
  const cfg = loadConfig(env);
  const db = createDb(cfg.databaseUrl);
  const auth = createAuth(cfg, db);
  const app = express();
  app.disable('x-powered-by');
  if (cfg.trustProxy) app.set('trust proxy', 1);
  app.use(securityHeaders(cfg));
  app.use(hostGuard(cfg));
  const limiter = rateLimiter({ max: cfg.loginRatePerMin, windowMs: 60_000 });                    // đăng nhập, nhập mã mời: theo IP
  const apiLimit = rateLimiter({ max: cfg.apiRatePerMin, windowMs: 60_000 })((q) => `api:${q.session?.sub || q.ip}`);   // lệnh gọi API: theo người

  // tệp tĩnh có băm tên (assets/*) cache dài; còn lại luôn kiểm lại
  app.use('/app', express.static(pub, { index: false, dotfiles: 'ignore', redirect: false, setHeaders: (res, file) => {
    res.setHeader('Cache-Control', file.includes(`${path.sep}assets${path.sep}`) ? 'public, max-age=31536000, immutable' : 'no-cache');
  } }));
  app.use('/app', noStore, createRoutes({ cfg, db, auth, limiter, apiLimit }));
  app.get(['/app', '/app/'], (req, res) => res.sendFile(path.join(pub, 'index.html')));
  app.get('/', (req, res) => res.redirect(302, '/app/'));
  app.use((req, res) => res.status(404).type('text/plain').send('Không tìm thấy'));
  app.use((err, req, res, next) => {                              // lỗi không lường trước: ghi nhật ký có mã, trả câu chung, không lộ chi tiết
    const ref = crypto.randomBytes(4).toString('hex');
    console.error(JSON.stringify({ evt: 'error', ref, path: req.path, msg: String(err?.message || err).slice(0, 300) }));
    if (res.headersSent) return next(err);
    const code = err?.type === 'entity.too.large' ? 413 : err?.type?.startsWith?.('entity.') ? 400 : 500;
    res.status(code).json({ error: code === 500 ? `Có lỗi xảy ra. Mã tham chiếu: ${ref}` : 'Dữ liệu gửi lên không hợp lệ' });
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
