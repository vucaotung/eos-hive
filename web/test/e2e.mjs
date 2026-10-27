// Kiểm thử đầu–cuối máy chủ web (API + giao diện tĩnh): server thật + Postgres thật + Google giả lập (kèm kiểm PKCE).
import http from 'node:http';
import net from 'node:net';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import pg from 'pg';

const freePort = () => new Promise((ok) => { const s = net.createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => ok(p)); }); });
const b64u = (x) => Buffer.from(x).toString('base64url');
const CID = 'cid-123.apps.googleusercontent.test';

// ---------- Google giả lập: chỉ điểm cuối token; kiểm PKCE và client_secret ----------
let google = { claims: null, challenge: null, calls: 0, lastRedirect: null };
const gsrv = http.createServer((req, res) => {
  let b = ''; req.on('data', (d) => (b += d)); req.on('end', () => {
    google.calls++;
    const p = new URLSearchParams(b);
    const pkceOk = p.get('code_verifier') && b64u(crypto.createHash('sha256').update(p.get('code_verifier')).digest()) === google.challenge;
    google.lastRedirect = p.get('redirect_uri');
    if (req.url !== '/token' || p.get('grant_type') !== 'authorization_code' || p.get('client_secret') !== 'secret-xyz' || p.get('client_id') !== CID || !pkceOk) {
      res.writeHead(400, { 'content-type': 'application/json' }); return res.end('{"error":"invalid_grant"}');
    }
    const c = { iss: 'https://accounts.google.com', aud: CID, exp: Math.floor(Date.now() / 1000) + 600, email_verified: true, ...google.claims };
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ id_token: `${b64u('{"alg":"RS256"}')}.${b64u(JSON.stringify(c))}.sig`, access_token: 'x' }));
  });
});
await new Promise((ok) => gsrv.listen(0, '127.0.0.1', ok));
const gport = gsrv.address().port;
const port = await freePort();
const origin = `http://127.0.0.1:${port}`;
Object.assign(process.env, {
  PORT: String(port), HOST: '127.0.0.1', PUBLIC_URL: origin, SESSION_SECRET: crypto.randomBytes(32).toString('hex'),
  GOOGLE_LOGIN_CLIENT_ID: CID, GOOGLE_LOGIN_CLIENT_SECRET: 'secret-xyz',
  LOGIN_RATE_PER_MIN: '1000', GOOGLE_AUTH_URL: `http://127.0.0.1:${gport}/authorize`, GOOGLE_TOKEN_URL: `http://127.0.0.1:${gport}/token`,
});
const { buildApp } = await import('../src/server.mjs');
const app = buildApp();
const srv = await new Promise((ok) => { const s = app.listen(port, '127.0.0.1', () => ok(s)); });
const admin = new pg.Client({ connectionString: process.env.ADMIN_DSN }); await admin.connect();
const sql = async (q, p) => (await admin.query(q, p)).rows;

// ---------- "trình duyệt" tối giản có hũ cookie ----------
class Browser {
  constructor() { this.jar = new Map(); this.csrfToken = ''; }
  send(method, path, { json, host, headers = {} } = {}) {
    return new Promise((ok, no) => {
      const body = json !== undefined ? JSON.stringify(json) : null;
      const h = { host: host || `127.0.0.1:${port}`, ...headers };
      if (this.jar.size) h.cookie = [...this.jar].map(([k, v]) => `${k}=${v}`).join('; ');
      if (body !== null) { h['content-type'] = h['content-type'] ?? 'application/json'; h['content-length'] = Buffer.byteLength(body); }
      const rq = http.request({ host: '127.0.0.1', port, method, path, headers: h }, (res) => {
        let t = ''; res.setEncoding('utf8'); res.on('data', (d) => (t += d));
        res.on('end', () => {
          for (const sc of [].concat(res.headers['set-cookie'] || [])) {
            const [kv] = sc.split(';'); const i = kv.indexOf('='); const k = kv.slice(0, i);
            if (/Max-Age=0/i.test(sc)) this.jar.delete(k); else this.jar.set(k, kv.slice(i + 1));
          }
          let j = null; try { j = JSON.parse(t); } catch { /* không phải JSON */ }
          ok({ status: res.statusCode, headers: res.headers, text: t, json: j, setCookie: [].concat(res.headers['set-cookie'] || []) });
        });
      });
      rq.on('error', no); if (body !== null) rq.write(body); rq.end();
    });
  }
  get(p, o) { return this.send('GET', p, o); }
  async me() { const r = await this.get('/app/api/me'); if (r.status === 200) this.csrfToken = r.json.csrf; return r; }
  // gọi một thao tác CSDL qua API, có CSRF
  async rpc(fn, body = {}, o = {}) {
    if (!this.csrfToken) await this.me();
    return this.send('POST', `/app/api/rpc/${encodeURIComponent(fn)}`, { json: body, headers: { 'x-csrf-token': this.csrfToken, 'x-requested-with': 'eos', ...(o.headers || {}) }, ...o });
  }
  // gọi và bắt buộc thành công, trả dữ liệu
  async ok(fn, body = {}) { const r = await this.rpc(fn, body); assert.equal(r.status, 200, `${fn}: HTTP ${r.status} ${r.text.slice(0, 200)}`); return r.json; }
}

// Đăng nhập qua Google giả lập; claims ghi đè được để thử các ca xấu
async function login(br, claims, { state, mutate, invite } = {}) {
  const start = await br.get(`/app/auth/google${invite ? `?invite=${invite}` : ''}`);
  assert.equal(start.status, 303);
  const loc = new URL(start.headers.location);
  const q = Object.fromEntries(loc.searchParams);
  google.challenge = q.code_challenge;
  google.claims = { sub: 'g-' + claims.email.toLowerCase(), nonce: q.nonce, name: claims.name || 'Tên Google', ...claims };
  if (mutate) mutate(google.claims, q);
  const cb = await br.get(`/app/auth/callback?code=abc&state=${encodeURIComponent(state ?? q.state)}`);
  br.csrfToken = '';
  return { start, q, loc, cb };
}
const as = async (email) => { const b = new Browser(); const r = await login(b, { email }); assert.equal(r.cb.status, 303); assert.equal(r.cb.headers.location, '/app/#/today', email); await b.me(); return b; };

let passed = 0;
const step = async (name, fn) => { await fn(); passed++; console.log('  ✓', name); };
const ID = { minh: 'cccccccc-0000-0000-0000-000000000001', adm: 'cccccccc-0000-0000-0000-000000000002', mgr: 'cccccccc-0000-0000-0000-000000000005', kt: 'cccccccc-0000-0000-0000-000000000006' };
const CO = '33333333-3333-3333-3333-333333333333', HC = 'dddddddd-0000-0000-0000-0000000000d1', KT = 'dddddddd-0000-0000-0000-0000000000d3';

try {
  const anon = new Browser();
  await step('healthz và giao diện không cần đăng nhập; API cần đăng nhập (401 JSON)', async () => {
    const h = await anon.get('/app/healthz'); assert.equal(h.status, 200); assert.equal(h.json.ok, true);
    const idx = await anon.get('/app/'); assert.equal(idx.status, 200); assert.match(idx.headers['content-type'], /html/); assert.ok(idx.text.includes('<div id="root">'));
    assert.match(idx.text, /\/app\/assets\/index-[\w-]+\.js/);
    assert.equal((await anon.get('/app')).status, 200);
    const root = await anon.get('/'); assert.equal(root.status, 302); assert.equal(root.headers.location, '/app/');
    for (const p of ['/app/api/me']) { const r = await anon.get(p); assert.equal(r.status, 401); assert.equal(r.json.code, 'UNAUTHENTICATED'); }
    const r = await anon.send('POST', '/app/api/rpc/app_tasks', { json: {}, headers: { 'x-requested-with': 'eos' } }); assert.equal(r.status, 401);
    const c = await anon.get('/app/api/config'); assert.equal(c.status, 200); assert.equal(c.json.google, true); assert.ok(!('client_secret' in c.json) && !c.text.includes('secret-xyz'));
  });
  await step('tiêu đề bảo mật: CSP chặt (script chỉ self, không eval), chống nhúng khung, không lưu đệm trang, ẩn X-Powered-By', async () => {
    const r = await anon.get('/app/');
    const csp = r.headers['content-security-policy'];
    assert.match(csp, /default-src 'none'.*script-src 'self'.*frame-ancestors 'none'/); assert.doesNotMatch(csp, /script-src[^;]*unsafe/); assert.doesNotMatch(csp, /unsafe-eval/);
    assert.match(csp, /connect-src 'self'/); assert.match(csp, /base-uri 'none'/);
    assert.equal(r.headers['x-content-type-options'], 'nosniff'); assert.equal(r.headers['x-frame-options'], 'DENY');
    assert.match(r.headers['cache-control'], /no-store|no-cache|max-age=0/); assert.equal(r.headers['x-powered-by'], undefined);
    assert.equal(r.headers['referrer-policy'], 'same-origin');
    assert.equal((await anon.get('/app/api/me')).headers['cache-control'], 'no-store');
  });
  await step('Host lạ bị từ chối (421)', async () => { assert.equal((await anon.get('/app/', { host: 'evil.example' })).status, 421); });
  await step('tệp tĩnh: assets có băm cache dài; không đi ngược thư mục; không lộ mã nguồn', async () => {
    const idx = (await anon.get('/app/')).text; const js = /\/app\/assets\/[\w.-]+\.js/.exec(idx)[0];
    const r = await anon.get(js); assert.equal(r.status, 200); assert.match(r.headers['content-type'], /javascript/); assert.match(r.headers['cache-control'], /immutable/);
    assert.equal((await anon.get('/app/manifest.webmanifest')).status, 200);
    for (const p of ['/app/../src/config.mjs', '/app/%2e%2e/src/config.mjs', '/app/..%2fsrc%2fconfig.mjs', '/app/assets/../../src/config.mjs', '/app/src/config.mjs', '/app/.env', '/app/package.json']) {
      const x = await new Browser().get(p); assert.notEqual(x.status, 200, p); assert.ok(!/loadConfig|sessionSecret/.test(x.text), p);
    }
  });

  // ---- đăng nhập ----
  await step('bước 1 tới Google: PKCE S256, state, nonce, redirect_uri đúng, cookie hẹp; phiên khóa tài khoản có hiệu lực ngay', async () => {
    const b = new Browser(); const { start, q, cb } = await login(b, { email: 'minh@demo.vn' });
    assert.equal(start.setCookie.length, 1); assert.match(start.setCookie[0], /^eos_o=.*Path=\/app\/auth.*HttpOnly.*SameSite=Lax/i);
    assert.equal(q.response_type, 'code'); assert.equal(q.code_challenge_method, 'S256'); assert.equal(q.client_id, CID);
    assert.equal(q.redirect_uri, `${origin}/app/auth/callback`); assert.match(q.scope, /openid email/); assert.ok(q.state.length >= 16 && q.nonce.length >= 16);
    assert.equal(google.lastRedirect, `${origin}/app/auth/callback`);
    assert.equal(cb.status, 303); assert.equal(cb.headers.location, '/app/#/today');
    assert.match(cb.setCookie.join(';'), /eos_s=.*Path=\/app.*HttpOnly.*SameSite=Lax/i);
    const me = await b.me(); assert.equal(me.status, 200); assert.equal(me.json.user.email, 'minh@demo.vn'); assert.equal(me.json.memberships[0].role, 'member'); assert.ok(me.json.csrf.length >= 20);
    assert.ok(!me.text.includes('google_sub') && !me.text.includes('token_hash'));
    await sql("UPDATE core.users SET active=false WHERE email='minh@demo.vn'");
    assert.equal((await b.me()).status, 401, 'khóa tài khoản có hiệu lực ngay'); assert.equal((await b.rpc('app_tasks', { company_id: CO })).status, 401);
    await sql("UPDATE core.users SET active=true WHERE email='minh@demo.vn'");
  });
  await step('đăng nhập bị từ chối: state sai, claims sai, email chưa xác minh, Google báo lỗi, tài khoản agent/khóa (chuyển về màn đăng nhập, không lộ lý do)', async () => {
    const cases = [
      ['state', (b) => login(b, { email: 'minh@demo.vn' }, { state: 'sai' }), 'state'],
      ['aud', (b) => login(b, { email: 'minh@demo.vn' }, { mutate: (c) => { c.aud = 'khac'; } }), 'google'],
      ['nonce', (b) => login(b, { email: 'minh@demo.vn' }, { mutate: (c) => { c.nonce = 'khac'; } }), 'google'],
      ['hết hạn', (b) => login(b, { email: 'minh@demo.vn' }, { mutate: (c) => { c.exp = 1; } }), 'google'],
      ['chưa xác minh', (b) => login(b, { email: 'minh@demo.vn' }, { mutate: (c) => { c.email_verified = false; } }), 'denied'],
      ['sub khác', (b) => login(b, { email: 'minh@demo.vn', sub: 'g-ke-gia-mao' }), 'denied'],
      ['agent', (b) => login(b, { email: 'van-thu@agent' }), 'denied'],
      ['khóa', (b) => login(b, { email: 'khoa@demo.vn' }), 'denied'],
    ];
    for (const [name, run, e] of cases) {
      const b = new Browser(); const { cb } = await run(b);
      assert.equal(cb.status, 303, name); assert.ok(cb.headers.location.startsWith('/app/#/login?e=' + e), `${name}: ${cb.headers.location}`);
      assert.ok(!b.jar.has('eos_s'), name); assert.equal((await b.me()).status, 401, name);
    }
    const noCode = new Browser(); await noCode.get('/app/auth/google'); assert.equal((await noCode.get('/app/auth/callback?state=x')).headers.location.startsWith('/app/#/login?e='), true);
    const replay = new Browser(); const { start } = await login(replay, { email: 'minh@demo.vn' }); // dùng lại state cũ không có cookie
    const b2 = new Browser(); const r2 = await b2.get(`/app/auth/callback?code=abc&state=${new URL(start.headers.location).searchParams.get('state')}`); assert.ok(r2.headers.location.includes('e=state'));
  });

  // ---- CSRF và biên API ----
  await step('CSRF và nguồn yêu cầu: thiếu/sai mã, Origin lạ, Sec-Fetch-Site chéo, thiếu JSON; hàm lạ không gọi được', async () => {
    const b = await as('minh@demo.vn');
    const post = (fn, headers, json = { company_id: CO }) => b.send('POST', `/app/api/rpc/${fn}`, { json, headers: { 'x-requested-with': 'eos', ...headers } });
    assert.equal((await post('app_tasks', {})).status, 403);
    assert.equal((await post('app_tasks', { 'x-csrf-token': 'sai' })).status, 403);
    assert.equal((await post('app_tasks', { 'x-csrf-token': b.csrfToken, origin: 'https://evil.example' })).status, 403);
    assert.equal((await post('app_tasks', { 'x-csrf-token': b.csrfToken, 'sec-fetch-site': 'cross-site' })).status, 403);
    assert.equal((await post('app_tasks', { 'x-csrf-token': b.csrfToken, origin })).status, 200);
    assert.equal((await b.send('POST', '/app/api/logout', { json: {}, headers: { 'x-requested-with': 'eos' } })).status, 403, 'đăng xuất cũng cần CSRF');
    for (const fn of ['agent.app_tasks', 'app_tasks; DROP TABLE core.users', 'web_login', 'mcp_token_issue_agent', 'outbox_pull', '__proto__', 'constructor', 'accept_result']) {
      assert.equal((await b.rpc(fn, {})).status, 404, fn);
    }
    assert.equal((await b.rpc('app_tasks', [1, 2])).status, 400, 'thân không phải đối tượng');
    const big = await b.send('POST', '/app/api/rpc/app_comment', { json: { task: 1, body: 'x'.repeat(200_000) }, headers: { 'x-csrf-token': b.csrfToken, 'x-requested-with': 'eos' } });
    assert.ok([400, 413].includes(big.status), `thân quá lớn: ${big.status}`);
    assert.ok([403, 404].includes((await b.send('GET', '/app/api/rpc/app_tasks')).status), 'GET không gọi được rpc');
  });
  await step('thông báo lỗi không lộ SQL/chi tiết hệ thống', async () => {
    const b = await as('minh@demo.vn');
    const r1 = await b.rpc('app_task', { id: 'abc' }); assert.equal(r1.status, 400); assert.ok(!/invalid input|bigint|syntax|pg_|agent\./i.test(r1.text), r1.text);
    const r2 = await b.rpc('app_task', { id: 605 }); assert.equal(r2.status, 403); assert.ok(!r2.text.includes('bí mật'));
    const r3 = await b.rpc('app_task_save', { company_id: CO, title: 'a' }); assert.equal(r3.status, 400); assert.match(r3.json.error, /2 đến 300/);
    const r4 = await b.rpc('app_tasks', { company_id: '44444444-4444-4444-4444-444444444444' }); assert.equal(r4.status, 403);
  });

  // ---- vòng đời việc ----
  await step('giao việc → danh sách → chi tiết → nộp → duyệt 2 bước (trưởng phòng, giám đốc) → Xong; trả lại rồi nộp lại', async () => {
    const minh = await as('minh@demo.vn'), mgr = await as('truongphong@demo.vn'), adm = await as('admin@demo.vn');
    const flow = await adm.ok('app_flow_save', { company_id: CO, name: 'Công văn đi', steps: [{ name: 'Trưởng phòng duyệt', approver_role: 'manager' }, { name: 'Giám đốc duyệt', approver_role: 'owner' }] });
    const org = await minh.ok('app_org', { company_id: CO }); assert.ok(org.flows.some((f) => f.id === flow.id && f.steps.length === 2)); assert.ok(org.departments.length >= 2);
    const t = await minh.ok('app_task_save', { company_id: CO, title: 'Soạn <b>công văn</b> gia hạn', description: 'Gửi sở', priority: 'high', approval_flow_id: flow.id, due_date: '2030-01-31' });
    const open = await minh.ok('app_tasks', { company_id: CO }); const row = open.find((x) => x.id === t.id);
    assert.ok(row && row.title === 'Soạn <b>công văn</b> gia hạn', 'tiêu đề giữ nguyên (giao diện React tự thoát HTML)'); assert.equal(row.status, 'todo');
    assert.ok(!open.some((x) => x.id === 605), 'không thấy việc của công ty khác');
    let d = await minh.ok('app_task', { id: t.id }); assert.equal(d.can_edit, true); assert.equal(d.can_submit, true); assert.equal(d.flow_steps, 2);
    await minh.ok('app_comment', { task: t.id, body: 'Ghi chú đầu' });
    const bad = await minh.rpc('app_link_add', { task: t.id, url: 'javascript:alert(1)' }); assert.equal(bad.status, 400);
    await minh.ok('app_link_add', { task: t.id, url: 'https://drive.google.com/file/d/xyz', title: 'Bản nháp' });
    assert.equal((await minh.ok('app_submit', { task: t.id, note: 'Bản v1' })).status, 'in_review');
    const inbox = await mgr.ok('app_my_approvals'); const it = inbox.items.find((x) => x.task_id === t.id);
    assert.ok(it && it.kind === 'approval' && it.step_no === 1 && it.steps === 2 && it.result.body === 'Bản v1' && it.links.length === 1, JSON.stringify(it));
    assert.equal((await minh.rpc('app_decide', { task: t.id, approve: true })).status, 403, 'người làm không tự duyệt');
    assert.equal((await mgr.rpc('app_decide', { task: t.id, approve: false })).status, 400, 'trả lại phải có lý do');
    await mgr.ok('app_decide', { task: t.id, approve: false, note: 'Thiếu căn cứ' });
    d = await minh.ok('app_task', { id: t.id }); assert.equal(d.task.status, 'in_progress'); assert.equal(d.task.attempts, 1);
    assert.ok(d.comments.some((c) => c.kind === 'reject' && c.body.includes('Thiếu căn cứ')));
    await minh.ok('app_submit', { task: t.id, note: 'Bản v2' });
    assert.equal((await mgr.ok('app_decide', { task: t.id, approve: true })).step, 2);
    assert.equal((await mgr.rpc('app_decide', { task: t.id, approve: true })).status, 403, 'trưởng phòng không duyệt bước giám đốc');
    d = await adm.ok('app_task', { id: t.id }); assert.equal(d.can_approve, true); assert.equal(d.approvals.length, 2);
    assert.equal((await adm.ok('app_decide', { task: t.id, approve: true })).status, 'done');
    d = await minh.ok('app_task', { id: t.id }); assert.equal(d.task.status, 'done'); assert.ok(d.approvals.every((a) => a.decision === 'approved'));
    const rep = await adm.ok('app_report', { company_id: CO }); assert.ok(rep.depts.some((x) => x.done_30d >= 1) && Array.isArray(rep.people));
  });
  await step('kết quả agent: người giao xem trước; chấp nhận → Xong; trả lại → agent làm lại (hàng đợi cầu nối)', async () => {
    const minh = await as('minh@demo.vn');
    const inbox = await minh.ok('app_my_approvals'); const ids = inbox.items.filter((x) => x.kind === 'review').map((x) => x.task_id);
    assert.ok(ids.includes(601) && ids.includes(602), ids.join());
    const d = await minh.ok('app_task', { id: 601 }); assert.equal(d.can_review, true); assert.match(d.reports[0].summary, /dự thảo công văn/);
    assert.equal((await minh.ok('app_accept', { task: 601 })).status, 'done');
    assert.equal((await minh.rpc('app_reject', { task: 602, reason: 'x' })).status, 400, 'lý do quá ngắn');
    assert.equal((await minh.ok('app_reject', { task: 602, reason: 'Sai thể thức, soạn lại theo NĐ 30' })).status, 'rework');
    assert.ok((await sql("SELECT 1 FROM agent.outbox WHERE task_id=602 AND kind='dispatch' AND done_at IS NULL")).length === 1, 'có thẻ làm lại chờ đẩy');
    const q = await minh.ok('app_task', { id: 603 }); assert.equal(q.can_answer, true);
    await minh.ok('app_answer', { task: 603, body: 'Nghỉ từ 30/4 đến 1/5' });
    assert.ok((await sql("SELECT 1 FROM agent.outbox WHERE task_id=603 AND kind='answer'")).length === 1, 'câu trả lời chuyển cho agent');
    assert.equal((await minh.rpc('app_answer', { task: 604, body: 'x' })).status, 400, 'việc không có agent hỏi');
  });
  await step('quyền xem: Kế toán không thấy việc phòng Hành chính; khách công ty khác bị chặn; người không phải thành viên không dùng được API công ty', async () => {
    const kt = await as('ketoan@demo.vn'), khach = await as('khach@khac.vn');
    assert.ok(!(await kt.ok('app_tasks', { company_id: CO })).some((x) => x.id === 604));
    assert.equal((await kt.rpc('app_task', { id: 604 })).status, 403);
    assert.equal((await kt.rpc('app_comment', { task: 604, body: 'xâm nhập' })).status, 403);
    assert.equal((await kt.rpc('app_task_save', { id: 604, title: 'Bị sửa' })).status, 403);
    assert.equal((await khach.rpc('app_tasks', { company_id: CO })).status, 403);
    assert.equal((await khach.rpc('app_org', { company_id: CO })).status, 403);
    assert.equal((await khach.rpc('app_task', { id: 601 })).status, 403);
    assert.equal((await kt.rpc('app_dept_save', { company_id: CO, code: 'X', name: 'Xxx' })).status, 403, 'thành viên không tạo phòng');
    assert.equal((await kt.rpc('app_invite_create', { company_id: CO, role: 'member' })).status, 403);
    assert.equal((await kt.rpc('web_admin_overview', {})).status, 403, 'chỉ quản trị hệ thống');
  });

  // ---- mã mời ----
  await step('mã mời: người mới đăng nhập Google → chờ mã → nhập mã vào công ty; mã dùng hết/sai bị từ chối; link mời điền sẵn mã', async () => {
    const adm = await as('admin@demo.vn');
    const inv = await adm.ok('app_invite_create', { company_id: CO, role: 'member', department_id: KT, max_uses: 1, days: 7, note: 'NV mới' });
    assert.match(inv.code, /^[A-Z0-9]{8}$/);
    const nb = new Browser(); const r = await login(nb, { email: 'moi@demo.vn', name: 'Người Mới' });
    assert.equal(r.cb.headers.location, '/app/#/login?e=invite_required'); assert.ok(!nb.jar.has('eos_s')); assert.ok(nb.jar.has('eos_p'));
    assert.match(r.cb.setCookie.find((c) => c.startsWith('eos_p')), /Path=\/app\/api.*HttpOnly.*SameSite=Lax/i);
    assert.equal((await nb.me()).status, 401, 'chưa có phiên khi chưa nhập mã');
    const join = (code, b = nb, h = {}) => b.send('POST', '/app/api/join', { json: { code }, headers: { 'x-requested-with': 'eos', ...h } });
    assert.equal((await join('KHONGCO1')).status, 400); assert.equal((await join('abc')).status, 400);
    assert.equal((await join(inv.code, nb, { origin: 'https://evil.example' })).status, 403);
    assert.equal((await nb.send('POST', '/app/api/join', { json: { code: inv.code } })).status, 400, 'thiếu tiêu đề X-Requested-With');
    const ok = await join(inv.code.toLowerCase()); assert.equal(ok.status, 200);
    assert.ok(nb.jar.has('eos_s') && !nb.jar.has('eos_p'));
    const me = await nb.me(); assert.equal(me.json.memberships[0].role, 'member'); assert.equal(me.json.memberships[0].department_code, 'KT');
    // mã đã hết lượt
    const b2 = new Browser(); await login(b2, { email: 'khac2@demo.vn' }); assert.equal((await join(inv.code, b2)).status, 400);
    // không có phiên Google đang chờ → không nhập mã được
    assert.equal((await join(inv.code, new Browser())).status, 401);
    // link mời có mã sẵn: đi thẳng qua Google
    const inv2 = await adm.ok('app_invite_create', { company_id: CO, role: 'member', email: 'Rieng@Demo.vn' });
    const b3 = new Browser(); const r3 = await login(b3, { email: 'rieng@demo.vn' }, { invite: inv2.code }); assert.equal(r3.cb.headers.location, '/app/#/today');
    const b4 = new Browser(); const r4 = await login(b4, { email: 'ai-do@demo.vn' }, { invite: inv2.code }); assert.ok(r4.cb.headers.location.includes('e='), 'mã gắn email không dùng cho người khác');
    await adm.ok('app_invite_revoke', { code: inv2.code });
    const list = await adm.ok('app_invites', { company_id: CO }); assert.ok(list.some((i) => i.code === inv.code && i.uses === 1) && list.find((i) => i.code === inv2.code).revoked);
    assert.equal((await new Browser().get('/app/#/login?code=' + inv.code)).status, 200);
  });

  // ---- quản trị ----
  await step('quản trị: phòng ban, thành viên (không tự hạ, giữ chủ sở hữu), dự án, Drive', async () => {
    const adm = await as('admin@demo.vn'), minh = await as('minh@demo.vn');
    const d = await adm.ok('app_dept_save', { company_id: CO, code: 'ph', name: 'Pháp chế' }); assert.ok(d.id);
    assert.equal((await adm.rpc('app_dept_save', { company_id: CO, code: 'PH', name: 'Trùng' })).status, 400);
    assert.equal((await adm.rpc('app_member_set', { company_id: CO, user_id: ID.adm, role: 'member' })).status, 400, 'không tự hạ vai trò');
    await adm.ok('app_member_set', { company_id: CO, user_id: ID.minh, role: 'member', department_id: HC, title: 'Chuyên viên' });
    const org = await adm.ok('app_org', { company_id: CO }); assert.equal(org.members.find((m) => m.user_id === ID.minh).title, 'Chuyên viên');
    const pr = await adm.ok('app_project_save', { company_id: CO, slug: 'du-an-a', name: 'Dự án A', drive_url: 'https://drive.google.com/drive/folders/abcdefghij' }); assert.ok(pr.id);
    assert.equal((await adm.rpc('app_project_save', { company_id: CO, slug: 'Sai Slug', name: 'x' })).status, 400);
    assert.equal((await minh.rpc('app_drive_set', { url: 'https://evil.example/drive/folders/1AbCdEfGhIjK' })).status, 400);
    await minh.ok('app_drive_set', { url: 'https://drive.google.com/drive/u/0/folders/1AbCdEfGhIjKlM?usp=sharing' });
    const me = await minh.me(); assert.equal(me.json.user.drive_status, 'pending'); assert.equal(me.json.user.drive_folder_url, 'https://drive.google.com/drive/folders/1AbCdEfGhIjKlM');
    assert.match((await minh.ok('app_drive_names'))[0], /^DEO - demo - HC - /);
  });
  await step('thành viên gồm người và AI agent: admin thấy cột kỹ thuật, thành viên thường không; tắt agent đổi trạng thái; agent không lọt vào ô chọn người', async () => {
    const adm = await as('admin@demo.vn'), minh = await as('minh@demo.vn');
    const AGENT_USERS = ['cccccccc-0000-0000-0000-0000000000a2', 'cccccccc-0000-0000-0000-0000000000a3'];
    const full = await adm.ok('app_members', { company_id: CO });
    assert.equal(full.tech, true); assert.ok(full.people.length >= 3 && full.people.every((x) => x.kind === 'person'));
    const vt = full.agents.find((a) => a.code === 'van-thu'), dp = full.agents.find((a) => a.code === 'dieu-phoi');
    assert.ok(vt && dp, 'có cả hai agent'); assert.equal(vt.hermes_profile, 'eos-van-thu'); assert.equal(vt.status, 'no_token'); assert.equal(vt.token_count, 0);
    // thành viên thường: thấy tên/mô tả/trạng thái, không thấy cột kỹ thuật, không lộ mã
    const lite = await minh.ok('app_members', { company_id: CO });
    assert.equal(lite.tech, false);
    const lvt = lite.agents.find((a) => a.code === 'van-thu');
    assert.ok(lvt.name && lvt.status);
    for (const k of ['hermes_profile', 'max_level', 'executor', 'skills', 'token_count', 'token_expires', 'token_scopes', 'last_active', 'running', 'can_delegate', 'accepts_cards']) assert.ok(!(k in lvt), `thành viên không thấy ${k}`);
    assert.ok(!/eos_[0-9a-f]{48}|token_hash/.test(JSON.stringify(lite)), 'không lộ mã');
    assert.equal((await minh.rpc('app_agent_set', { company_id: CO, code: 'van-thu', enabled: false })).status, 403, 'thành viên thường không sửa agent');
    // admin tắt agent + đặt người phụ trách: trạng thái đổi; max_level không đổi được
    await adm.ok('app_agent_set', { company_id: CO, code: 'van-thu', enabled: false, owner_user_id: ID.minh, title: 'Soạn công văn', max_level: 3 });
    const after = (await adm.ok('app_members', { company_id: CO })).agents.find((a) => a.code === 'van-thu');
    assert.equal(after.status, 'off'); assert.equal(after.owner.id, ID.minh); assert.equal(after.title, 'Soạn công văn'); assert.ok(after.max_level < 3, 'max_level không sửa được từ giao diện');
    assert.equal((await adm.rpc('app_agent_set', { company_id: CO, code: 'van-thu', owner_user_id: '99999999-9999-9999-9999-999999999999' })).status, 400, 'người phụ trách phải là thành viên');
    await adm.ok('app_agent_set', { company_id: CO, code: 'van-thu', enabled: true });
    // agent không vào danh sách người: app_org vẫn chỉ trả người, giao việc cho agent như một người bị từ chối
    const org = await adm.ok('app_org', { company_id: CO });
    assert.ok(!org.members.some((m) => AGENT_USERS.includes(m.user_id)), 'org.members không có agent');
    const bad = await adm.rpc('app_task_save', { company_id: CO, title: 'Giao thử cho agent như người', assignee_id: AGENT_USERS[0] }); assert.equal(bad.status, 400);
    assert.equal((await sql('SELECT count(*)::int n FROM core.memberships WHERE user_id = ANY($1::uuid[])', [AGENT_USERS]))[0].n, 0);
  });
  await step('cờ Eisenhower và ngày bắt đầu: tạo, đổi từng cờ (kéo thả), giữ khi sửa trường khác; hạn trước ngày bắt đầu bị từ chối; người không sửa được thì bị chặn', async () => {
    const adm = await as('admin@demo.vn'), kt = await as('ketoan@demo.vn');
    const made = await adm.ok('app_task_save', { company_id: CO, title: 'Việc Eisenhower', important: true, start_date: '2030-03-01', due_date: '2030-03-05', department_id: HC });
    const row = async () => (await adm.ok('app_tasks', { company_id: CO, days: 1 })).find((x) => x.id === made.id);
    let r = await row(); assert.equal(r.important, true); assert.equal(r.urgent, false); assert.equal(r.start_date, '2030-03-01');
    await adm.ok('app_task_save', { id: made.id, urgent: true }); r = await row(); assert.equal(r.important, true); assert.equal(r.urgent, true);
    await adm.ok('app_task_save', { id: made.id, important: false }); r = await row(); assert.equal(r.important, false); assert.equal(r.urgent, true);
    await adm.ok('app_task_save', { id: made.id, title: 'Đổi tên' }); r = await row(); assert.equal(r.urgent, true); assert.equal(r.start_date, '2030-03-01');
    assert.equal((await adm.rpc('app_task_save', { id: made.id, due_date: '2030-02-01' })).status, 400, 'hạn trước ngày bắt đầu');
    const denied = await kt.rpc('app_task_save', { id: made.id, important: true }); assert.ok([400, 403].includes(denied.status), `người không sửa được: HTTP ${denied.status}`);
    r = await row(); assert.equal(r.important, false, 'cờ không đổi khi bị chặn');
  });
  await step('thông báo: giao việc và nhắc tên tạo thông báo cho người nhận, lọc, đánh dấu đã đọc; người khác không đọc/đánh dấu hộ', async () => {
    const adm = await as('admin@demo.vn'), minh = await as('minh@demo.vn');
    const base = (await minh.ok('app_notifications', { company_id: CO })).unread;
    const made = await adm.ok('app_task_save', { company_id: CO, title: 'Việc thử thông báo web', assignee_id: ID.minh, department_id: HC });
    await adm.ok('app_comment', { task: made.id, body: 'Nhờ @Trần Minh kiểm tra giúp' });
    const nm = await minh.ok('app_notifications', { company_id: CO });
    assert.equal(nm.unread, base + 2, JSON.stringify(nm.items.slice(0, 2)));
    assert.ok(nm.items.some((n) => n.kind === 'task_assigned' && n.task === made.id && n.who));
    const mention = (await minh.ok('app_notifications', { company_id: CO, filter: 'mention' })).items; assert.ok(mention.length >= 1 && mention.every((n) => n.kind === 'mention'));
    assert.equal((await adm.ok('app_notifications_read', { company_id: CO, ids: nm.items.map((n) => n.id) })).marked, 0, 'không đánh dấu hộ người khác');
    await minh.ok('app_notifications_read', { company_id: CO, ids: [nm.items[0].id] });
    assert.equal((await minh.ok('app_notifications', { company_id: CO })).unread, base + 1);
    await minh.ok('app_notifications_read', { company_id: CO, all: true });
    assert.equal((await minh.ok('app_notifications', { company_id: CO })).unread, 0);
    assert.equal((await minh.rpc('app_notifications', { company_id: CO, filter: 'bậy' })).status, 400);
  });
  await step('việc định kỳ: tạo (đến hạn thì sinh việc ngay), danh sách theo vai trò, tạm dừng/xóa chỉ người tạo hoặc quản trị', async () => {
    const adm = await as('admin@demo.vn'), minh = await as('minh@demo.vn'), kt = await as('ketoan@demo.vn');
    const today = new Date(Date.now() + 7 * 3600e3).toISOString().slice(0, 10);   // ngày theo giờ Việt Nam (+07), cùng cách tính của máy chủ
    const r = await adm.ok('app_recurrence_save', { company_id: CO, title: 'Báo cáo định kỳ web', freq: 'daily', start: today, assignee_id: ID.minh, department_id: HC, due_offset: 1 });
    assert.ok(r.id && r.created_task, 'đến hạn nên có việc đầu tiên');
    const list = await minh.ok('app_recurrences', { company_id: CO }); const mine = list.find((x) => x.id === r.id);
    assert.ok(mine, 'người được giao thấy mẫu'); assert.equal(mine.can_edit, false); assert.equal(new Date(mine.next_run) > new Date(today), true, 'next_run đã tiến sang ngày sau');
    const tk = (await minh.ok('app_tasks', { company_id: CO, days: 1 })).find((x) => x.id === r.created_task);
    assert.ok(tk && tk.recurrence_id === r.id && tk.assignee_id === ID.minh && tk.title === 'Báo cáo định kỳ web', 'việc sinh ra mang recurrence_id');
    assert.equal((await kt.ok('app_recurrences', { company_id: CO })).some((x) => x.id === r.id), false, 'người không liên quan không thấy');
    assert.equal((await minh.rpc('app_recurrence_set', { id: r.id, active: false })).status, 403, 'người chỉ được giao thì không đổi mẫu');
    await adm.ok('app_recurrence_set', { id: r.id, active: false });
    assert.equal((await adm.ok('app_recurrences', { company_id: CO })).find((x) => x.id === r.id).active, false);
    assert.equal((await adm.rpc('app_recurrence_save', { company_id: CO, title: 'Sai', freq: 'weekly', weekdays: [9] })).status, 400);
    await adm.ok('app_recurrence_set', { id: r.id, delete: true });
    assert.equal((await adm.ok('app_recurrences', { company_id: CO })).some((x) => x.id === r.id), false);
  });
  await step('chi tiết việc: checklist (người làm sửa được), mẫu, người theo dõi, nhật ký đổi gì, thời lượng; người không liên quan bị chặn', async () => {
    const adm = await as('admin@demo.vn'), minh = await as('minh@demo.vn'), kt = await as('ketoan@demo.vn');
    const made = await adm.ok('app_task_save', { company_id: CO, title: 'Việc có checklist web', assignee_id: ID.minh, department_id: HC, est_minutes: 150 });
    await adm.ok('app_task_save', { id: made.id, status: 'in_progress', due_date: '2030-06-01' });
    const d0 = await adm.ok('app_task', { id: made.id });
    assert.equal(d0.task.est_minutes, 150); assert.match(d0.activity[0].summary, /trạng thái Chờ làm → Đang làm/); assert.equal(d0.activity[0].who, 'Quản Trị');
    await minh.ok('app_checklist_save', { task: made.id, items: [{ title: 'Bước 1', done: true }, { title: 'Bước 2', done: false }] });
    const d1 = await adm.ok('app_task', { id: made.id }); assert.deepEqual(d1.checklist.map((x) => [x.title, x.done]), [['Bước 1', true], ['Bước 2', false]]);
    assert.ok([400, 403].includes((await kt.rpc('app_checklist_save', { task: made.id, items: [] })).status), 'người không liên quan bị chặn');
    const tpl = await adm.ok('app_checklist_template_save', { company_id: CO, name: 'Hồ sơ đất đai web', items: ['Giấy chứng nhận', 'Bản đồ địa chính'] });
    assert.equal((await minh.rpc('app_checklist_template_save', { company_id: CO, name: 'Mẫu lậu', items: ['x'] })).status, 403, 'thành viên thường không tạo mẫu');
    assert.equal((await minh.ok('app_checklist_apply', { task: made.id, template_id: tpl.id })).added, 2);
    assert.equal((await adm.ok('app_task', { id: made.id })).checklist.length, 4);
    assert.equal((await adm.ok('app_checklist_templates', { company_id: CO })).find((x) => x.id === tpl.id).uses, 1);
    await adm.ok('app_watchers_set', { task: made.id, user_ids: [ID.mgr] });
    assert.deepEqual((await adm.ok('app_task', { id: made.id })).watchers, [ID.mgr]);
    assert.equal((await adm.rpc('app_watchers_set', { task: made.id, user_ids: ['99999999-9999-9999-9999-999999999999'] })).status, 400);
    await adm.ok('app_checklist_template_delete', { id: tpl.id });
  });
  await step('tạo việc bằng AI qua web: gửi yêu cầu → Mai đề xuất (giả lập bằng SQL agent) → người dùng xem, sửa, xác nhận → việc tạo bằng quyền người dùng; người khác không đụng được; web không gọi được công cụ của Mai', async () => {
    await sql("INSERT INTO core.users (id, email, name, kind) VALUES ('cccccccc-0000-0000-0000-0000000000a9', 'mai@agent', 'Mai - Trợ lý AI', 'agent') ON CONFLICT DO NOTHING");
    await sql("INSERT INTO agent.agents (id, user_id, code, name, kind, module, hermes_profile, token_scopes, max_level) VALUES ('a2222222-0000-0000-0000-0000000000a9', 'cccccccc-0000-0000-0000-0000000000a9', 'mai', 'Mai - Trợ lý AI', 'specialist', 'work', 'team_admin', '{read,task_create}', 1) ON CONFLICT DO NOTHING");
    await sql("INSERT INTO agent.company_agents (company_id, agent_id, enabled, auto_done, config) VALUES ($1, 'a2222222-0000-0000-0000-0000000000a9', true, true, '{\"internal\": true}') ON CONFLICT DO NOTHING", [CO]);
    const minh = await as('minh@demo.vn'), adm = await as('admin@demo.vn');
    assert.ok(!(await minh.me()).json.agents.some((a) => a.code === 'mai'), 'Mai nội bộ không hiện trong ô chọn agent');
    const req = await minh.ok('app_ai_request', { company_id: CO, description: 'Giao anh Minh soạn báo cáo tuần trước thứ Sáu' });
    assert.equal((await minh.ok('app_ai_request_get', { id: req.id })).state, 'pending');
    assert.equal((await adm.ok('app_ai_request_get', { id: req.id })).state, 'pending');
    assert.equal((await minh.rpc('mcp_task_propose', { request_id: req.id, tasks: [] })).status, 404, 'web không gọi được hàm của Mai (không nằm trong bảng trắng)');
    await admin.query('BEGIN'); await admin.query(`SELECT set_config('request.jwt.claims', '{"sub":"cccccccc-0000-0000-0000-0000000000a9","role":"agent","agent":"a2222222-0000-0000-0000-0000000000a9","via":"agent:mai"}', true)`);
    await admin.query('SELECT agent.mcp_task_propose($1::jsonb)', [JSON.stringify({ request_id: req.id, summary: 'Một việc, một việc con', tasks: [{ title: 'Soạn báo cáo tuần (AI)', assignee_email: 'minh@demo.vn', due_date: '2030-08-02', priority: 'high', subtasks: [{ title: 'Đối chiếu số liệu' }] }] })]); await admin.query('COMMIT');
    const got = await minh.ok('app_ai_request_get', { id: req.id }); assert.equal(got.state, 'proposed'); assert.equal(got.proposal.tasks[0].assignee_id, ID.minh);
    assert.ok((await minh.ok('app_notifications', { company_id: CO })).items.some((n) => n.kind === 'ai_proposal' && n.request === req.id && n.ai), 'thông báo có nhãn AI trỏ tới yêu cầu');
    assert.equal((await adm.rpc('app_ai_confirm', { id: req.id, tasks: got.proposal.tasks })).status, 403, 'người khác không xác nhận hộ');
    const tasks = got.proposal.tasks.map((x) => ({ ...x, title: 'Soạn báo cáo tuần (đã sửa)' }));
    const done = await minh.ok('app_ai_confirm', { id: req.id, tasks }); assert.equal(done.created.length, 2);
    const rows = await sql('SELECT title, created_by, parent_id, source FROM work.tasks WHERE id = ANY($1::bigint[]) ORDER BY id', [done.created]);
    assert.equal(rows[0].title, 'Soạn báo cáo tuần (đã sửa)'); assert.equal(rows[0].created_by, ID.minh); assert.equal(Number(rows[1].parent_id), done.created[0]); assert.equal(rows[0].source, 'manual');
    assert.equal((await minh.ok('app_tasks', { company_id: CO, days: 1 })).some((x) => (x.title || '').startsWith('Phân tích yêu cầu giao việc')), false, 'việc phân tích của Mai không hiện trong danh sách');
    assert.equal((await minh.rpc('app_ai_confirm', { id: req.id, tasks })).status, 400, 'không xác nhận hai lần');
  });
  await step('dự án: tạo, cài đặt, thành viên, quyền người thường, xóa (việc còn nhưng mất liên kết)', async () => {
    const adm = await as('admin@demo.vn'), kt = await as('ketoan@demo.vn');
    const pr = await adm.ok('app_project_save', { company_id: CO, slug: 'cong-trinh-x', name: 'Công trình X', department_id: HC, status: 'planned', description: 'Mô tả', start_date: '2030-01-01', end_date: '2030-06-30' });
    const org = await adm.ok('app_org', { company_id: CO }); const p = org.projects.find((x) => x.id === pr.id);
    assert.equal(p.status, 'planned'); assert.equal(p.can_manage, true); assert.ok(org.project_members.some((m) => m.project_id === pr.id && m.role === 'manager'));
    assert.equal((await adm.rpc('app_project_save', { id: pr.id, status: 'sai' })).status, 400);
    await adm.ok('app_project_member_set', { project_id: pr.id, user_id: ID.kt, role: 'member' });
    assert.equal((await kt.rpc('app_project_save', { id: pr.id, name: 'Chiếm' })).status, 403);
    assert.equal((await kt.rpc('app_project_delete', { id: pr.id })).status, 403);
    assert.equal((await kt.rpc('app_project_member_set', { project_id: pr.id, user_id: ID.kt, role: 'viewer' })).status, 403);
    assert.equal((await (await as('khach@khac.vn')).rpc('app_project_member_set', { project_id: pr.id, user_id: ID.kt, role: 'member' })).status, 403);
    const t = await adm.ok('app_task_save', { company_id: CO, title: 'Việc của công trình X', project_id: pr.id });
    assert.equal((await adm.ok('app_project_delete', { id: pr.id })).tasks_unlinked, 1);
    assert.equal((await adm.ok('app_task', { id: t.id })).task.project_id, null);
  });
  await step('phải duyệt: quy trình dựng sẵn có ngay; nộp → Chờ duyệt; người giao duyệt mới Xong (không tự duyệt, không Xong tắt)', async () => {
    const mgr = await as('truongphong@demo.vn'), minh = await as('minh@demo.vn');
    const org = await minh.ok('app_org', { company_id: CO });
    const names = org.flows.map((f) => f.name); for (const n of ['Người giao duyệt', 'Trưởng phòng duyệt', 'Quản trị công ty duyệt']) assert.ok(names.includes(n), n);
    const fl = org.flows.find((f) => f.name === 'Người giao duyệt'); assert.equal(fl.steps[0].approver_role, 'creator');
    const t = await mgr.ok('app_task_save', { company_id: CO, title: 'Việc bắt buộc duyệt', assignee_id: ID.minh, approval_flow_id: fl.id, department_id: HC });
    assert.equal((await minh.ok('app_task', { id: t.id })).task.approval_status, 'none');
    await minh.ok('app_submit', { task: t.id, note: 'Đã làm' });
    let d = await minh.ok('app_task', { id: t.id }); assert.equal(d.task.status, 'in_review'); assert.equal(d.task.approval_status, 'pending'); assert.equal(d.can_approve, false);
    assert.equal((await minh.rpc('app_task_save', { id: t.id, status: 'cancelled' })).status, 400, 'đang chờ duyệt không đổi trạng thái tay');
    assert.equal((await minh.rpc('app_decide', { task: t.id, approve: true })).status, 403, 'người nộp không tự duyệt');
    d = await mgr.ok('app_task', { id: t.id }); assert.equal(d.can_approve, true);
    await mgr.ok('app_decide', { task: t.id, approve: true });
    d = await minh.ok('app_task', { id: t.id }); assert.equal(d.task.status, 'done'); assert.equal(d.task.approval_status, 'approved');
  });
  await step('nạp hồ sơ dự án: chỉ chủ sở hữu/quản trị bắt đầu; việc gốc giao điều phối, người theo dõi phụ trách; phạm vi hiện trong chi tiết', async () => {
    const adm = await as('admin@demo.vn'), minh = await as('minh@demo.vn');
    const body = { company_id: CO, project_name: 'Khu đô thị thử', drive_url: 'https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOp', supervisor_id: ID.minh, note: 'Ưu tiên pháp lý' };
    assert.equal((await minh.rpc('app_workflow_start', body)).status, 403);
    assert.equal((await adm.rpc('app_workflow_start', { ...body, drive_url: 'https://evil.example/folders/1AbCdEfGhIjKlMnOp' })).status, 400);
    assert.equal((await adm.rpc('app_workflow_start', { ...body, supervisor_id: ID.adm.replace(/2$/, 'a') })).status, 400, 'người theo dõi phải là thành viên');
    const r = await adm.ok('app_workflow_start', body);
    assert.ok(r.run_id && r.root_task && r.project_id);
    const d = await minh.ok('app_task', { id: r.root_task });
    assert.equal(d.task.agent_role, 'dieu-phoi'); assert.equal(d.workflow.skill, 'dieu-phoi-du-an'); assert.equal(d.task.assignee_id, ID.minh); assert.equal(d.workflow.scope.stage, 'orchestrate'); assert.equal(d.workflow.scope.note, 'Ưu tiên pháp lý');
    assert.equal((await adm.rpc('app_workflow_start', { ...body, project_name: undefined, project_id: r.project_id })).status, 400, 'đang có lần chạy chưa xong');
    const res = await minh.ok('app_project_results', { project_id: r.project_id }); assert.equal(res.run.root_task, r.root_task); assert.equal(res.tasks.length, 1); assert.deepEqual(res.records, []); assert.equal(res.kb.ready, false);
    assert.equal((await (await as('ketoan@demo.vn')).rpc('app_project_results', { project_id: r.project_id })).status, 403, 'người không liên quan không xem kết quả');
    const runs = await adm.ok('app_workflow_runs', { company_id: CO }); assert.equal(runs.length, 1); assert.equal(runs[0].root_task, r.root_task);
    assert.equal((await minh.ok('app_workflow_runs', { company_id: CO })).length, 1, 'người theo dõi thấy lần chạy của mình');
    assert.equal((await (await as('ketoan@demo.vn')).ok('app_workflow_runs', { company_id: CO })).length, 0);
  });
  await step('kết nối AI: cấp mã MCP (hiện một lần, không lộ băm), liệt kê, thu hồi; quản trị hệ thống xem tổng quan', async () => {
    const minh = await as('minh@demo.vn'), adm = await as('admin@demo.vn');
    const t = await minh.ok('web_token_issue', { name: 'Claude laptop', client: 'claude', scopes: ['read', 'write'], days: 30 });
    assert.match(t.token, /^eos_[0-9a-f]{48}$/);
    assert.equal((await minh.rpc('web_token_issue', { name: 'x', client: 'claude', scopes: ['delegate'], days: 30 })).status, 400);
    assert.equal((await minh.rpc('web_token_issue', { name: 'xx', client: 'claude', scopes: 'read', days: 30 })).status, 400);
    const list = await minh.ok('web_my_tokens'); assert.equal(list.length, 1); assert.ok(!JSON.stringify(list).includes(t.token) && !JSON.stringify(list).includes('token_hash'));
    assert.equal((await minh.rpc('web_token_revoke', { id: 'khong-phai-uuid' })).status, 400);
    await minh.ok('web_token_revoke', { id: list[0].id }); assert.equal((await minh.ok('web_my_tokens'))[0].active, false);
    const ov = await adm.ok('web_admin_overview'); assert.ok(ov.agents.length >= 1 && ov.bridge && ov.mcp);
    assert.ok(Array.isArray(await adm.ok('web_admin_tokens'))); assert.ok(Array.isArray(await adm.ok('web_admin_calls', { limit: 20, denied: true })));
    assert.ok(!JSON.stringify(await adm.ok('web_admin_tokens')).includes('token_hash'));
  });
  await step('đăng xuất xóa phiên; cookie cũ vẫn là chữ ký hợp lệ nhưng tài khoản khóa thì mất hiệu lực', async () => {
    const b = await as('minh@demo.vn'); const saved = b.jar.get('eos_s');
    const out = await b.send('POST', '/app/api/logout', { json: {}, headers: { 'x-csrf-token': b.csrfToken, 'x-requested-with': 'eos' } }); assert.equal(out.status, 200);
    assert.ok(!b.jar.has('eos_s')); assert.equal((await b.me()).status, 401);
    b.jar.set('eos_s', saved + 'x'); assert.equal((await b.me()).status, 401, 'chữ ký sai');
    const [p] = saved.split('.'); b.jar.set('eos_s', `${p}.${'A'.repeat(43)}`); assert.equal((await b.me()).status, 401, 'chữ ký giả');
  });
  await step('cookie Secure khi PUBLIC_URL là https', async () => {
    const saved = { ...process.env }; process.env.PUBLIC_URL = 'https://work.example.test';
    const { buildApp: build2 } = await import('../src/server.mjs?https'); const a2 = build2();
    const s2 = await new Promise((ok) => { const s = a2.listen(0, '127.0.0.1', () => ok(s)); });
    const p2 = s2.address().port;
    const r = await new Promise((ok) => http.get({ host: '127.0.0.1', port: p2, path: '/app/auth/google', headers: { host: 'work.example.test' } }, (res) => { res.resume(); ok(res); }));
    assert.match([].concat(r.headers['set-cookie']).join(';'), /Secure/); assert.ok(r.headers['strict-transport-security']);
    s2.close(); await a2.locals.db.close(); Object.assign(process.env, saved);
  });
  await step('giới hạn tốc độ: đăng nhập và lệnh gọi API vượt ngưỡng nhận 429', async () => {
    const saved = { ...process.env }; Object.assign(process.env, { LOGIN_RATE_PER_MIN: '5', API_RATE_PER_MIN: '4' });
    const { buildApp: build3 } = await import('../src/server.mjs?ratelimit'); const a3 = build3();
    const s3 = await new Promise((ok) => { const s = a3.listen(0, '127.0.0.1', () => ok(s)); });
    const hit = (path, method = 'GET', ph = {}) => new Promise((ok) => { const r = http.request({ host: '127.0.0.1', port: s3.address().port, path, method, headers: { host: `127.0.0.1:${port}`, ...ph } }, (res) => { res.resume(); ok(res.statusCode); }); r.end(); });
    const codes = []; for (let i = 0; i < 9; i++) codes.push(await hit('/app/auth/google')); assert.ok(codes.slice(0, 5).every((c) => c === 303) && codes.slice(5).every((c) => c === 429), codes.join(','));
    s3.close(); await a3.locals.db.close(); Object.assign(process.env, saved);
    // giới hạn theo người: dựng máy chủ thứ ba dùng chung phiên (cùng SESSION_SECRET của máy chủ chính)
    const saved2 = { ...process.env }; Object.assign(process.env, { API_RATE_PER_MIN: '4' });
    const { buildApp: build4 } = await import('../src/server.mjs?ratelimit2'); const a4 = build4();
    const s4 = await new Promise((ok) => { const s = a4.listen(0, '127.0.0.1', () => ok(s)); });
    const minh = await as('minh@demo.vn'); const cookie = `eos_s=${minh.jar.get('eos_s')}`;
    const rpc4 = () => new Promise((ok) => { const body = JSON.stringify({ company_id: CO }); const r = http.request({ host: '127.0.0.1', port: s4.address().port, path: '/app/api/rpc/app_tasks', method: 'POST',
      headers: { host: `127.0.0.1:${port}`, cookie, 'content-type': 'application/json', 'content-length': Buffer.byteLength(body), 'x-csrf-token': minh.csrfToken, 'x-requested-with': 'eos' } }, (res) => { res.resume(); ok(res.statusCode); }); r.end(body); });
    const w = []; for (let i = 0; i < 7; i++) w.push(await rpc4()); assert.deepEqual(w.slice(0, 4), [200, 200, 200, 200], w.join()); assert.ok(w.slice(4).every((c) => c === 429), w.join());
    s4.close(); await a4.locals.db.close(); Object.assign(process.env, saved2);
  });

  console.log(`web e2e: ${passed} bước đạt`);
} finally {
  srv.close(); gsrv.close(); await app.locals.db.close(); await admin.end();
}
