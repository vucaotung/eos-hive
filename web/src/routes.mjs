// Máy chủ API cho giao diện (SPA): mọi dữ liệu và thao tác đi qua hàm CSDL agent.app_* / agent.web_* mang danh tính người đăng nhập.
// Danh sách lệnh gọi được là bảng trắng cố định bên dưới; máy chủ không ghép SQL từ dữ liệu người dùng.
import express from 'express';
import crypto from 'node:crypto';
import { DbError } from './db.mjs';

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);

// Hàm nhận một tham số jsonb (app_*): danh sách tên
const JSON_FNS = ['app_org', 'app_notifications', 'app_notifications_read', 'app_recurrences', 'app_recurrence_save', 'app_recurrence_set', 'app_checklist_save', 'app_checklist_templates', 'app_checklist_template_save', 'app_checklist_template_delete', 'app_checklist_apply', 'app_watchers_set', 'app_members', 'app_agent_set', 'app_tasks', 'app_task', 'app_task_save', 'app_submit', 'app_decide', 'app_answer', 'app_comment', 'app_link_add', 'app_link_remove',
  'app_accept', 'app_reject', 'app_my_approvals', 'app_report', 'app_dept_save', 'app_member_set', 'app_invite_create', 'app_invites', 'app_invite_revoke',
  'app_flow_save', 'app_flow_archive', 'app_project_save', 'app_project_member_set', 'app_project_member_remove', 'app_project_delete', 'app_workflow_start', 'app_workflow_runs', 'app_project_results', 'app_drive_names', 'app_drive_set'];
// Hàm có tham số định kiểu (mã MCP, quản trị agent): [SQL, hàm dựng tham số từ body]
const bad = (m) => Object.assign(new Error(m), { client: true });
const TYPED = {
  web_my_tokens: ['SELECT agent.web_my_tokens() AS r', () => []],
  web_token_issue: ['SELECT agent.web_token_issue($1,$2,$3::text[],$4) AS r', (b) => {
    if (!Array.isArray(b.scopes) || b.scopes.length > 10 || !b.scopes.every((x) => typeof x === 'string' && x.length < 20)) throw bad('Quyền không hợp lệ');
    return [String(b.name ?? ''), String(b.client ?? 'other'), b.scopes, Number(b.days) || 30];
  }],
  web_token_revoke: ['SELECT agent.web_token_revoke($1::uuid) AS r', (b) => { if (!UUID.test(String(b.id))) throw bad('Mã không hợp lệ'); return [b.id]; }],
  web_admin_overview: ['SELECT agent.web_admin_overview() AS r', () => []],
  web_admin_tokens: ['SELECT agent.web_admin_tokens() AS r', () => []],
  web_admin_calls: ['SELECT agent.web_admin_calls($1,$2) AS r', (b) => [Math.min(Math.max(Number(b.limit) || 100, 1), 500), b.denied === true]],
};

export function createRoutes({ cfg, db, auth, limiter, apiLimit }) {
  const r = express.Router();
  const ref = () => crypto.randomBytes(4).toString('hex');

  // Lỗi CSDL -> JSON: câu nghiệp vụ (P0001) và quyền (42501) do hàm của ta viết bằng tiếng Việt nên hiển thị được; mã khác chỉ trả câu chung.
  const fail = (res, req, e) => {
    if (e?.client) return res.status(400).json({ error: e.message });
    if (e instanceof DbError) {
      if (e.forbidden && /^Chưa đăng nhập|tài khoản bị khóa/.test(e.message)) { res.append('Set-Cookie', 'eos_s=; Path=/app; Max-Age=0; HttpOnly; SameSite=Lax'); return res.status(401).json({ error: 'Phiên đăng nhập không còn hiệu lực', code: 'UNAUTHENTICATED' }); }
      if (e.forbidden) return res.status(403).json({ error: e.message });
      if (e.business) return res.status(400).json({ error: e.message });
      if (/^(22|23)/.test(e.code)) return res.status(400).json({ error: 'Dữ liệu không hợp lệ' });
    }
    const id = ref();
    console.error(JSON.stringify({ evt: 'error', ref: id, path: req.path, msg: String(e?.message || e).slice(0, 300) }));
    return res.status(500).json({ error: `Có lỗi xảy ra. Mã tham chiếu: ${id}` });
  };
  const handler = (fn) => async (req, res) => { try { await fn(req, res); } catch (e) { fail(res, req, e); } };

  r.get('/healthz', (req, res) => res.json({ ok: true }));
  r.get('/api/config', (req, res) => res.json({ google: cfg.googleEnabled, agent_email: cfg.agentDriveEmail, mcp_url: cfg.mcpUrl || `${cfg.publicUrl}/mcp` }));

  // ----- đăng nhập -----
  r.get('/auth/google', limiter((q) => `login:${q.ip}`), auth.begin);
  r.get('/auth/callback', limiter((q) => `login:${q.ip}`), handler(auth.callback));
  r.post('/api/join', limiter((q) => `join:${q.ip}`), express.json({ limit: '2kb' }), auth.xhrOnly, handler(auth.join));

  // ----- cần phiên -----
  const api = express.Router();
  api.use(auth.requireSession, express.json({ limit: '100kb' }));
  api.get('/me', handler(async (req, res) => {
    const m = await db.asUser(req.session.sub, (c) => db.one(c, "SELECT agent.app_me('{}'::jsonb) AS r"));
    res.json({ ...m, csrf: req.session.csrf });
  }));
  api.use(auth.csrfCheck, apiLimit);
  api.post('/logout', auth.logout);
  api.post('/rpc/:fn', handler(async (req, res) => {
    const fn = req.params.fn, body = req.body ?? {};
    if (!isObj(body)) throw bad('Dữ liệu gửi lên không hợp lệ');
    let sql, params;
    if (JSON_FNS.includes(fn)) { sql = `SELECT agent.${fn}($1::jsonb) AS r`; params = [JSON.stringify(body)]; }
    else if (Object.hasOwn(TYPED, fn)) { sql = TYPED[fn][0]; params = TYPED[fn][1](body); }
    else return res.status(404).json({ error: 'Không có thao tác này' });
    const out = await db.asUser(req.session.sub, (c) => db.one(c, sql, params));
    res.json(out ?? null);
  }));
  r.use('/api', api);
  r.use('/api', (req, res) => res.status(404).json({ error: 'Không tìm thấy' }));
  return r;
}
