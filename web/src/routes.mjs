// Các tuyến của giao diện web. Mọi dữ liệu và thao tác đi qua hàm CSDL mang danh tính người đăng nhập.
import express from 'express';
import { html } from './html.mjs';
import { DbError } from './db.mjs';
import * as V from './views.mjs';

const TASK_ID = /^(?:T-)?(\d{1,12})$/i;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const BOXES = new Set(['assigned', 'created', 'review', 'agent_questions', 'watching']);
const MSG = { created: 'Đã tạo việc.', accepted: 'Đã chấp nhận kết quả, việc đã xong.', rejected: 'Đã trả lại, agent sẽ làm lại.', answered: 'Đã gửi câu trả lời cho agent.',
  noted: 'Đã gửi.', cancelled: 'Đã hủy việc.', revoked: 'Đã thu hồi mã.', already: 'Việc này đã được xử lý trước đó, không có gì thay đổi.' };
const flash = (req) => MSG[req.query.ok] || '';

export function createRoutes({ cfg, db, auth, limiter }) {
  const r = express.Router();
  const call = (req, res, fn) => db.asUser(req.session.sub, fn);
  const one = (sql, params) => (c) => db.one(c, sql, params);
  const page = (res, status, view) => res.status(status).type('html').send(String(view));
  const bad = (res, req, e, render) => {                       // lỗi nghiệp vụ -> hiện lại biểu mẫu; lỗi quyền -> 403; còn lại ném lên xử lý chung
    if (e instanceof DbError && e.business) return render(e.message.replace(/^.*?:\s*/, ''));
    if (e instanceof DbError && e.forbidden) return page(res, 403, V.errorPage({ title: 'Không có quyền', message: 'Bạn không có quyền với thao tác hoặc việc này.', me: res.locals.me, csrf: res.locals.csrf }));
    throw e;
  };
  const id = (req, res, next) => { const m = TASK_ID.exec(req.params.id); if (!m) return res.status(404).type('text/plain').send('Không tìm thấy'); req.taskId = Number(m[1]); next(); };

  // ----- công khai -----
  r.get('/healthz', (req, res) => res.json({ ok: true }));
  r.get('/login', (req, res) => {
    const s = auth.readSession(req);
    if (s) return res.redirect(303, auth.safeNext(req.query.next));
    page(res, 200, V.loginPage({ enabled: cfg.googleEnabled, next: auth.safeNext(req.query.next), notice: req.query.out ? 'Bạn đã đăng xuất.' : '' }));
  });
  r.get('/auth/google', limiter((q) => `login:${q.ip}`), auth.begin);
  r.get('/auth/callback', limiter((q) => `login:${q.ip}`), auth.callback);

  // ----- cần đăng nhập -----
  r.use(auth.requireLogin);
  r.post('/logout', auth.csrfCheck, auth.logout);

  r.get('/', async (req, res) => {
    const [day, open] = await call(req, res, async (c) => [await db.one(c, 'SELECT agent.mcp_my_day() AS r'), await db.one(c, "SELECT agent.mcp_my_tasks('assigned','open',100) AS r")]);
    page(res, 200, V.inboxPage({ me: res.locals.me, csrf: res.locals.csrf, day, open, msg: flash(req) }));
  });

  r.get('/tasks', async (req, res) => {
    const box = BOXES.has(req.query.box) ? req.query.box : 'assigned';
    const status = req.query.status === 'all' ? 'all' : 'open';
    const tasks = await call(req, res, one('SELECT agent.mcp_my_tasks($1,$2,100) AS r', [box, status]));
    page(res, 200, V.tasksPage({ me: res.locals.me, csrf: res.locals.csrf, box, status, tasks }));
  });

  r.get('/tasks/new', (req, res) => page(res, 200, V.newTaskPage({ me: res.locals.me, csrf: res.locals.csrf })));
  r.post('/tasks', auth.csrfCheck, async (req, res) => {
    const b = req.body, form = { title: b.title, description: b.description, agent: b.agent, due: b.due, priority: b.priority };
    const due = /^\d{4}-\d{2}-\d{2}$/.test(b.due || '') ? b.due : null;
    try {
      const t = await call(req, res, one('SELECT agent.web_create_task($1,$2,$3,$4,$5) AS r', [b.title ?? '', b.description ?? '', b.agent || null, due, b.priority || 'medium']));
      res.redirect(303, `${V.taskHref(t.id)}?ok=created`);
    } catch (e) { bad(res, req, e, (m) => page(res, 400, V.newTaskPage({ me: res.locals.me, csrf: res.locals.csrf, error: m, form }))); }
  });

  const showTask = async (req, res, extra = {}, status = 200) => {
    let t;
    try { t = await call(req, res, one('SELECT agent.web_task($1) AS r', [req.taskId])); }
    catch (e) { if (e instanceof DbError && e.forbidden) return page(res, 404, V.errorPage({ title: 'Không tìm thấy', message: 'Việc không tồn tại hoặc bạn không có quyền xem.', me: res.locals.me, csrf: res.locals.csrf })); throw e; }
    page(res, status, V.taskPage({ me: res.locals.me, csrf: res.locals.csrf, t, msg: flash(req), ...extra }));
  };
  r.get('/tasks/:id', id, (req, res) => showTask(req, res));
  // Mọi thao tác trên một việc: kiểm quyền xem trước (web_task ném 42501 nếu không xem được), rồi chạy hàm nghiệp vụ.
  // Hàm nghiệp vụ có thể trả 'not_in_review' / 'already_closed' mà không báo lỗi: nói đúng điều đã xảy ra, không báo thành công giả.
  const NOOP = new Set(['not_in_review', 'already_closed', 'returned_to_human']);
  const act = (path, okKey, fn) => r.post(`/tasks/:id/${path}`, id, auth.csrfCheck, async (req, res) => {
    try {
      const out = await call(req, res, async (c) => { await db.one(c, 'SELECT agent.web_task($1) AS r', [req.taskId]); return fn(c, req); });
      res.redirect(303, `/app/tasks/${req.taskId}?ok=${NOOP.has(out) && out !== 'returned_to_human' ? 'already' : okKey}`);
    } catch (e) { bad(res, req, e, (m) => showTask(req, res, { error: m }, 400)); }
  });
  act('accept', 'accepted', (c, q) => db.one(c, 'SELECT agent.accept_result($1,$2) AS r', [q.taskId, (q.body.note || '').slice(0, 500) || null]));
  act('reject', 'rejected', (c, q) => db.one(c, 'SELECT agent.reject_result($1,$2) AS r', [q.taskId, q.body.reason || '']));
  act('cancel', 'cancelled', (c, q) => db.one(c, 'SELECT agent.web_cancel_task($1,$2) AS r', [q.taskId, (q.body.reason || '').slice(0, 500) || null]));
  r.post('/tasks/:id/comment', id, auth.csrfCheck, async (req, res) => {
    const kind = req.body.kind === 'answer' ? 'answer' : 'note';
    try { await call(req, res, async (c) => { await db.one(c, 'SELECT agent.web_task($1) AS r', [req.taskId]); return db.one(c, 'SELECT agent.mcp_comment($1,$2,$3) AS r', [req.taskId, req.body.body || '', kind]); }); res.redirect(303, `/app/tasks/${req.taskId}?ok=${kind === 'answer' ? 'answered' : 'noted'}`); }
    catch (e) { bad(res, req, e, (m) => showTask(req, res, { error: m }, 400)); }
  });

  // ----- mã MCP của tôi -----
  const tokensView = async (req, res, extra = {}, status = 200) => {
    const tokens = await call(req, res, one('SELECT agent.web_my_tokens() AS r'));
    page(res, status, V.tokensPage({ me: res.locals.me, csrf: res.locals.csrf, tokens, msg: flash(req), ...extra }));
  };
  r.get('/tokens', (req, res) => tokensView(req, res));
  r.post('/tokens', auth.csrfCheck, async (req, res) => {
    const scopes = [].concat(req.body.scopes || []).map(String);
    try {
      const out = await call(req, res, one('SELECT agent.web_token_issue($1,$2,$3,$4) AS r', [req.body.name || '', req.body.client || 'other', scopes, Number(req.body.days) || 30]));
      res.setHeader('Cache-Control', 'no-store');
      page(res, 200, V.tokenCreatedPage({ me: res.locals.me, csrf: res.locals.csrf, token: out.token, name: String(req.body.name).slice(0, 60) }));
    } catch (e) { bad(res, req, e, (m) => tokensView(req, res, { error: m }, 400)); }
  });
  r.post('/tokens/:tid/revoke', auth.csrfCheck, async (req, res) => {
    if (!UUID.test(req.params.tid)) return res.status(404).type('text/plain').send('Không tìm thấy');
    await call(req, res, one('SELECT agent.web_token_revoke($1) AS r', [req.params.tid]));
    res.redirect(303, '/app/tokens?ok=revoked');
  });

  // ----- quản trị -----
  const admin = express.Router();
  admin.use(auth.requireAdmin);
  admin.get('/', async (req, res) => page(res, 200, V.adminPage({ me: res.locals.me, csrf: res.locals.csrf, ov: await call(req, res, one('SELECT agent.web_admin_overview() AS r')) })));
  admin.get('/tokens', async (req, res) => page(res, 200, V.adminTokensPage({ me: res.locals.me, csrf: res.locals.csrf, tokens: await call(req, res, one('SELECT agent.web_admin_tokens() AS r')), msg: flash(req) })));
  admin.post('/tokens/:tid/revoke', auth.csrfCheck, async (req, res) => {
    if (!UUID.test(req.params.tid)) return res.status(404).type('text/plain').send('Không tìm thấy');
    await call(req, res, one('SELECT agent.web_token_revoke($1) AS r', [req.params.tid]));
    res.redirect(303, '/app/admin/tokens?ok=revoked');
  });
  admin.get('/calls', async (req, res) => {
    const denied = req.query.denied === '1';
    page(res, 200, V.adminCallsPage({ me: res.locals.me, csrf: res.locals.csrf, denied, calls: await call(req, res, one('SELECT agent.web_admin_calls(150,$1) AS r', [denied])) }));
  });
  r.use('/admin', admin);

  r.use((req, res) => page(res, 404, V.errorPage({ title: 'Không tìm thấy', message: 'Trang này không tồn tại.', me: res.locals.me, csrf: res.locals.csrf })));
  return r;
}
