// Kiểm thử đầu–cuối giao diện web: server thật + Postgres thật + Google giả lập (kèm kiểm PKCE).
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
  constructor() { this.jar = new Map(); }
  send(method, path, { form, host, headers = {} } = {}) {
    return new Promise((ok, no) => {
      const toForm = (o) => { const u = new URLSearchParams(); for (const [k, v] of Object.entries(o)) for (const x of [].concat(v)) u.append(k, x); return u.toString(); };   // mảng -> khóa lặp, như trình duyệt
      const body = form ? toForm(form) : null;
      const h = { host: host || `127.0.0.1:${port}`, ...headers };
      if (this.jar.size) h.cookie = [...this.jar].map(([k, v]) => `${k}=${v}`).join('; ');
      if (body) { h['content-type'] = 'application/x-www-form-urlencoded'; h['content-length'] = Buffer.byteLength(body); }
      const rq = http.request({ host: '127.0.0.1', port, method, path, headers: h }, (res) => {
        let t = ''; res.setEncoding('utf8'); res.on('data', (d) => (t += d));
        res.on('end', () => {
          for (const sc of [].concat(res.headers['set-cookie'] || [])) {
            const [kv] = sc.split(';'); const i = kv.indexOf('='); const k = kv.slice(0, i);
            if (/Max-Age=0/i.test(sc)) this.jar.delete(k); else this.jar.set(k, kv.slice(i + 1));
          }
          ok({ status: res.statusCode, headers: res.headers, text: t, setCookie: [].concat(res.headers['set-cookie'] || []) });
        });
      });
      rq.on('error', no); if (body) rq.write(body); rq.end();
    });
  }
  get(p, o) { return this.send('GET', p, o); }
  post(p, form, o) { return this.send('POST', p, { ...o, form }); }
  async csrf(path = '/app/') { const r = await this.get(path); const m = /name="_csrf" value="([^"]+)"/.exec(r.text); assert.ok(m, `không có _csrf ở ${path}`); return m[1]; }
}

// Đăng nhập qua Google giả lập; claims ghi đè được để thử các ca xấu
async function login(br, claims, { state, mutate } = {}) {
  const start = await br.get('/app/auth/google?next=%2Fapp%2Ftasks');
  assert.equal(start.status, 303);
  const loc = new URL(start.headers.location);
  const q = Object.fromEntries(loc.searchParams);
  google.challenge = q.code_challenge;
  google.claims = { sub: 'g-' + claims.email.toLowerCase(), nonce: q.nonce, name: claims.name || 'Tên Google', ...claims };
  if (mutate) mutate(google.claims, q);
  const cb = await br.get(`/app/auth/callback?code=abc&state=${encodeURIComponent(state ?? q.state)}`);
  return { start, q, loc, cb };
}

let passed = 0;
const step = async (name, fn) => { await fn(); passed++; console.log('  ✓', name); };
const has = (r, s) => assert.ok(r.text.includes(s), `thiếu "${s}" trong trang (HTTP ${r.status})`);
const lacks = (r, s) => assert.ok(!r.text.includes(s), `không được có "${s}" trong trang`);

try {
  const anon = new Browser();
  await step('healthz không cần đăng nhập; trang khác chuyển về đăng nhập', async () => {
    const h = await anon.get('/app/healthz'); assert.equal(h.status, 200); assert.equal(JSON.parse(h.text).ok, true);
    for (const p of ['/app/', '/app/tasks', '/app/tasks/601', '/app/admin', '/app/tokens']) {
      const r = await new Browser().get(p); assert.equal(r.status, 303, p); assert.match(r.headers.location, /^\/app\/login/);
    }
  });
  await step('tiêu đề bảo mật: CSP chặt, chống nhúng khung, không lưu đệm, ẩn X-Powered-By', async () => {
    const r = await anon.get('/app/login');
    assert.match(r.headers['content-security-policy'], /default-src 'none'.*script-src 'self'.*frame-ancestors 'none'/);
    assert.doesNotMatch(r.headers['content-security-policy'], /unsafe-inline|unsafe-eval/);
    assert.equal(r.headers['x-content-type-options'], 'nosniff'); assert.equal(r.headers['x-frame-options'], 'DENY');
    assert.equal(r.headers['cache-control'], 'no-store'); assert.equal(r.headers['x-powered-by'], undefined);
    assert.equal(r.headers['referrer-policy'], 'same-origin');
  });
  await step('Host lạ bị từ chối (421)', async () => { assert.equal((await anon.get('/app/login', { host: 'evil.example' })).status, 421); });
  await step('tệp tĩnh có; không đi ngược thư mục', async () => {
    const css = await anon.get('/app/static/app.css'); assert.equal(css.status, 200); assert.match(css.headers['content-type'], /css/);
    assert.equal((await anon.get('/app/static/app.js')).status, 200);
    for (const p of ['/app/static/../src/config.mjs', '/app/static/%2e%2e/src/config.mjs', '/app/static/..%2fsrc%2fconfig.mjs']) {
      const r = await new Browser().get(p); assert.notEqual(r.status, 200, p); assert.ok(!/loadConfig/.test(r.text), p);
    }
  });

  // ---- đăng nhập ----
  await step('bước 1 tới Google: PKCE S256, state, nonce, redirect_uri đúng, cookie hẹp', async () => {
    const b = new Browser(); const { start, q } = await login(b, { email: 'minh@demo.vn' });
    assert.equal(start.setCookie.length, 1); assert.match(start.setCookie[0], /^eos_o=.*Path=\/app\/auth.*HttpOnly.*SameSite=Lax/i);
    assert.equal(q.response_type, 'code'); assert.equal(q.code_challenge_method, 'S256'); assert.equal(q.client_id, CID);
    assert.equal(q.redirect_uri, `${origin}/app/auth/callback`); assert.match(q.scope, /openid email/); assert.ok(q.state.length >= 16 && q.nonce.length >= 16);
    assert.equal(google.lastRedirect, `${origin}/app/auth/callback`);
  });
  const minh = new Browser();
  await step('người được phép đăng nhập; chuyển tới trang đích an toàn; cookie phiên HttpOnly/SameSite', async () => {
    const { cb } = await login(minh, { email: 'Minh@Demo.vn', name: 'Tên Google' });
    assert.equal(cb.status, 303); assert.equal(cb.headers.location, '/app/tasks');
    const s = cb.setCookie.find((c) => c.startsWith('eos_s=')); assert.ok(s); assert.match(s, /HttpOnly/i); assert.match(s, /SameSite=Lax/i); assert.match(s, /Path=\/app/);
    assert.doesNotMatch(s, /Secure/i, 'http thử nghiệm: không Secure');
    assert.ok(cb.setCookie.some((c) => /^eos_o=;.*Max-Age=0/i.test(c)), 'cookie OAuth tạm bị xóa');
    const rows = await sql("SELECT google_sub, last_login_at FROM core.users WHERE email='minh@demo.vn'"); assert.equal(rows[0].google_sub, 'g-minh@demo.vn'); assert.ok(rows[0].last_login_at);
    assert.ok(Number((await sql("SELECT count(*) FROM core.audit_log WHERE module='web' AND action='login' AND user_id='cccccccc-0000-0000-0000-000000000001'"))[0].count) >= 1, 'đăng nhập được ghi nhật ký');
  });
  await step('các ca đăng nhập xấu đều bị từ chối bằng cùng một trang, không lộ lý do', async () => {
    const bad = [
      ['email lạ', { email: 'la@nowhere.vn' }], ['tài khoản khóa', { email: 'khoa@demo.vn' }], ['tài khoản agent', { email: 'van-thu@agent' }],
      ['sub khác (giả mạo)', { email: 'minh@demo.vn', sub: 'g-ke-tan-cong' }], ['email chưa xác minh', { email: 'minh@demo.vn', email_verified: false }],
      ['sai aud', { email: 'minh@demo.vn', aud: 'client-khac' }], ['sai nonce', { email: 'minh@demo.vn', nonce: 'nonce-sai' }],
      ['hết hạn', { email: 'minh@demo.vn', exp: Math.floor(Date.now() / 1000) - 10 }], ['sai iss', { email: 'minh@demo.vn', iss: 'https://evil.example' }],
    ];
    const pages = new Set();
    for (const [why, claims] of bad) {
      const b = new Browser(); const { cb } = await login(b, claims);
      assert.ok([400, 403].includes(cb.status), `${why}: HTTP ${cb.status}`); assert.ok(!b.jar.has('eos_s'), `${why}: không được cấp phiên`);
      assert.doesNotMatch(cb.text, /minh@demo|không có trong|sub|nonce|email/i, `${why}: lộ thông tin`); pages.add(cb.text);
    }
    const { cb: c2 } = await login(new Browser(), { email: 'minh@demo.vn' }, { state: 'state-sai' }); assert.equal(c2.status, 400);
    const { cb: c3 } = await login(new Browser(), { email: 'minh@demo.vn' }, { mutate: () => { google.challenge = 'khac'; } }); assert.equal(c3.status, 502, 'PKCE sai bị Google từ chối');
    const b4 = new Browser(); const r4 = await b4.get('/app/auth/callback?code=x&state=y'); assert.equal(r4.status, 400, 'không có cookie OAuth');
    assert.equal(pages.size, 1, 'mọi lý do từ chối dùng đúng một trang');
  });
  await step('không chuyển hướng mở (open redirect)', async () => {
    for (const evil of ['//evil.com', 'https://evil.com', '/\\evil.com', '/app/../etc']) {
      const b = new Browser(); const s = await b.get(`/app/auth/google?next=${encodeURIComponent(evil)}`); const q = Object.fromEntries(new URL(s.headers.location).searchParams);
      google.challenge = q.code_challenge; google.claims = { email: 'minh@demo.vn', sub: 'g-minh@demo.vn', nonce: q.nonce };
      const cb = await b.get(`/app/auth/callback?code=a&state=${q.state}`); assert.equal(cb.headers.location, '/app/', evil);
    }
  });

  // ---- hộp việc ----
  await step('hộp việc: số liệu, danh sách chờ xem, agent đang hỏi, việc quá hạn', async () => {
    const r = await minh.get('/app/'); assert.equal(r.status, 200);
    has(r, 'Xin chào Tên Google'.replace('Tên Google', 'Trần Minh')); has(r, 'Kết quả chờ bạn xem'); has(r, 'Agent đang hỏi bạn');
    has(r, 'T-601'); has(r, 'T-602'); has(r, 'T-603'); has(r, 'Việc thường đã quá hạn'); has(r, 'Quá hạn');
    lacks(r, 'Việc bí mật của công ty khác'); has(r, 'data-refresh="30"');
  });
  await step('danh sách việc: các hộp lọc; không thấy việc công ty khác', async () => {
    const all = await minh.get('/app/tasks?box=assigned&status=all'); has(all, 'T-604'); lacks(all, 'T-605');
    const rv = await minh.get('/app/tasks?box=review'); has(rv, 'T-601'); lacks(rv, 'T-604');
    const q = await minh.get('/app/tasks?box=agent_questions'); has(q, 'T-603');
    const junk = await minh.get('/app/tasks?box=<script>&status=x'); assert.equal(junk.status, 200); lacks(junk, '<script>');
  });

  // ---- chi tiết, XSS, cách ly ----
  await step('chi tiết việc chờ duyệt: báo cáo đầy đủ, tệp Drive là liên kết, nút duyệt có', async () => {
    const r = await minh.get('/app/tasks/601'); assert.equal(r.status, 200);
    has(r, 'Kết quả chờ bạn duyệt'); has(r, 'Tin cậy: Cao'); has(r, 'Rủi ro còn lại'); has(r, 'Chưa rõ người ký'); has(r, 'Đúng thể thức NĐ30');
    has(r, 'href="https://drive.google.com/file/d/D601/view"'); has(r, 'rel="noopener noreferrer"'); has(r, 'Chấp nhận, đóng việc'); has(r, 'Trả lại để làm lại');
    assert.equal((await minh.get('/app/tasks/T-601')).status, 200, 'chấp nhận tiền tố T-');
  });
  await step('XSS: nội dung do agent/người nhập luôn bị thoát; URL javascript: không thành liên kết', async () => {
    const r2 = await minh.get('/app/tasks/602'); has(r2, '&lt;b&gt;độc hại&lt;/b&gt;'); lacks(r2, '<b>độc hại</b>'); lacks(r2, 'href="javascript:'); has(r2, 'href="https://drive.google.com/file/d/D602/view"');
    has(r2, 'Tin cậy: Cao'); // 'high' đã được chuẩn hóa thành 'cao' ở CSDL
    const r3 = await minh.get('/app/tasks/603'); has(r3, '&lt;script&gt;alert(1)&lt;/script&gt;'); lacks(r3, '<script>alert(1)</script>');
    const csrf = await minh.csrf('/app/tasks/new');
    const t = await minh.post('/app/tasks', { _csrf: csrf, title: '<img src=x onerror=alert(1)> việc XSS', description: '"><script>alert(2)</script>', agent: '', due: '', priority: 'medium' });
    assert.equal(t.status, 303); const d = await minh.get(t.headers.location);
    has(d, '&lt;img src=x onerror=alert(1)&gt;'); lacks(d, '<img src=x'); lacks(d, '<script>alert(2)');
    const err = await minh.post('/app/tasks', { _csrf: csrf, title: '"><script>x</script>', description: '', agent: 'khong-co', priority: 'medium' });
    assert.equal(err.status, 400); lacks(err, '<script>x</script>'); has(err, 'Agent');
  });
  await step('cách ly công ty: không xem, không duyệt, không hủy việc của người khác (không lộ tồn tại)', async () => {
    const csrf = await minh.csrf('/app/tasks/new');
    const r = await minh.get('/app/tasks/605'); assert.equal(r.status, 404); lacks(r, 'bí mật');
    for (const a of ['accept', 'cancel']) { const p = await minh.post(`/app/tasks/605/${a}`, { _csrf: csrf }); assert.ok([403, 404].includes(p.status), a); }
    assert.equal((await sql('SELECT status FROM work.tasks WHERE id=605'))[0].status, 'todo');
    for (const bad of ['abc', '1;DROP', '99999999999999', '0x1']) assert.equal((await minh.get(`/app/tasks/${bad}`)).status, 404, bad);
    const khach = new Browser(); await login(khach, { email: 'khach@khac.vn' });
    assert.equal((await khach.get('/app/tasks/601')).status, 404);
    const kc = await khach.csrf('/app/tokens'); assert.ok([403, 404].includes((await khach.post('/app/tasks/601/accept', { _csrf: kc })).status));
    has(await khach.get('/app/'), 'Xin chào Khách Công Ty Khác'); lacks(await khach.get('/app/'), 'T-601');
  });

  // ---- CSRF ----
  await step('CSRF: thiếu/sai mã bị chặn; Origin lạ bị chặn; không đổi dữ liệu', async () => {
    for (const form of [{}, { _csrf: 'sai' }]) { const r = await minh.post('/app/tasks/601/accept', form); assert.equal(r.status, 403); }
    const csrf = await minh.csrf();
    const o = await minh.post('/app/tasks/601/accept', { _csrf: csrf }, { headers: { origin: 'https://evil.example' } }); assert.equal(o.status, 403);
    const s = await minh.post('/app/tasks/601/accept', { _csrf: csrf }, { headers: { 'sec-fetch-site': 'cross-site' } }); assert.equal(s.status, 403);
    assert.equal((await sql('SELECT status FROM work.tasks WHERE id=601'))[0].status, 'in_review');
    const other = new Browser(); await login(other, { email: 'admin@demo.vn' });
    assert.equal((await other.post('/app/tasks/601/accept', { _csrf: csrf })).status, 403, 'CSRF của người khác không dùng được');
    assert.equal((await minh.post('/app/logout', {})).status, 403, 'đăng xuất cũng cần CSRF');
  });

  // ---- luồng nghiệp vụ ----
  await step('trả lời agent đang hỏi → bình luận kind=answer, việc chuyển Đang làm', async () => {
    const csrf = await minh.csrf('/app/tasks/603');
    const r = await minh.post('/app/tasks/603/comment', { _csrf: csrf, kind: 'answer', body: 'Nghỉ từ 30/4 đến 3/5.' }); assert.equal(r.status, 303); assert.match(r.headers.location, /ok=answered/);
    assert.equal((await sql("SELECT count(*) FROM work.comments WHERE task_id=603 AND kind='answer'"))[0].count, '1');
    assert.equal((await sql('SELECT waiting_on_human FROM work.tasks WHERE id=603'))[0].waiting_on_human, false);
    assert.equal((await sql("SELECT count(*) FROM agent.outbox WHERE task_id=603 AND kind='answer'"))[0].count, '1', 'đẩy câu trả lời sang Hermes');
    const rr = await minh.get('/app/tasks/603?ok=answered'); has(rr, 'Đã gửi câu trả lời cho agent'); has(rr, 'Nghỉ từ 30/4 đến 3/5.');
  });
  await step('chấp nhận kết quả → Xong; báo cáo ghi accepted', async () => {
    const csrf = await minh.csrf('/app/tasks/601');
    const r = await minh.post('/app/tasks/601/accept', { _csrf: csrf, note: 'Tốt' }); assert.equal(r.status, 303);
    assert.equal((await sql('SELECT status FROM work.tasks WHERE id=601'))[0].status, 'done');
    assert.equal((await sql('SELECT verdict FROM agent.reports WHERE task_id=601'))[0].verdict, 'accepted');
    const again = await minh.post('/app/tasks/601/accept', { _csrf: csrf }); assert.equal(again.status, 303, 'chấp nhận lần hai không lỗi');
    lacks(await minh.get('/app/tasks/601'), 'Chấp nhận, đóng việc');
  });
  await step('trả lại: lý do bắt buộc; sau đó sinh thẻ làm lại kèm lý do', async () => {
    const csrf = await minh.csrf('/app/tasks/602');
    const short = await minh.post('/app/tasks/602/reject', { _csrf: csrf, reason: 'x' }); assert.equal(short.status, 400); has(short, 'lý do');
    const r = await minh.post('/app/tasks/602/reject', { _csrf: csrf, reason: 'Thiếu người nhận, làm lại cho đủ.' }); assert.equal(r.status, 303);
    assert.equal((await sql("SELECT count(*) FROM agent.cards WHERE task_id=602 AND kind='rework'"))[0].count, '1');
    assert.equal((await sql("SELECT count(*) FROM agent.outbox WHERE task_id=602 AND kind='dispatch' AND payload ? 'rework_reason'"))[0].count, '1');
  });
  await step('tạo việc giao agent → có lệnh dispatch; mô tả và ưu tiên được lưu; người phụ trách là mình', async () => {
    const csrf = await minh.csrf('/app/tasks/new');
    const form = await minh.get('/app/tasks/new'); has(form, 'Văn thư AI');
    const r = await minh.post('/app/tasks', { _csrf: csrf, title: 'Soạn công văn gửi đối tác', description: 'Nội dung chi tiết', agent: 'van-thu', due: '2026-12-31', priority: 'high' });
    assert.equal(r.status, 303); assert.match(r.headers.location, /^\/app\/tasks\/\d+\?ok=created$/);
    const id = r.headers.location.match(/tasks\/(\d+)/)[1];
    const t = (await sql('SELECT priority, due_date::text, assignee_id, created_by, agent_id FROM work.tasks WHERE id=$1', [id]))[0];
    assert.equal(t.priority, 'high'); assert.equal(t.due_date, '2026-12-31'); assert.equal(t.assignee_id, t.created_by); assert.ok(t.agent_id);
    assert.equal((await sql("SELECT count(*) FROM agent.outbox WHERE task_id=$1 AND kind='dispatch'", [id]))[0].count, '1');
    const bad = await minh.post('/app/tasks', { _csrf: csrf, title: 'ab', description: '', priority: 'medium' }); assert.equal(bad.status, 400); has(bad, 'Tiêu đề');
    assert.equal((await minh.post('/app/tasks', { _csrf: csrf, title: 'Việc hạn xấu', due: 'khong-phai-ngay', priority: 'medium' })).status, 303, 'ngày sai bị bỏ qua, không làm hỏng');
  });
  await step('hủy việc: ghi bình luận; việc đã hủy không hủy lại; thẻ agent bị dừng (migration 0001)', async () => {
    const csrf = await minh.csrf('/app/tasks/604');
    const r = await minh.post('/app/tasks/604/cancel', { _csrf: csrf, reason: 'Không cần nữa' }); assert.equal(r.status, 303);
    assert.equal((await sql('SELECT status, kpi_counted FROM work.tasks WHERE id=604'))[0].status, 'cancelled');
    assert.match((await sql("SELECT body FROM work.comments WHERE task_id=604 ORDER BY id DESC LIMIT 1"))[0].body, /^Hủy việc: Không cần nữa/);
    const t603 = (await sql("SELECT id FROM work.tasks WHERE title LIKE 'Soạn công văn gửi đối tác'"))[0].id;
    const c2 = await minh.csrf(`/app/tasks/${t603}`); await minh.post(`/app/tasks/${t603}/cancel`, { _csrf: c2, reason: '' });
    assert.equal((await sql("SELECT done_at IS NOT NULL AS d FROM agent.outbox WHERE task_id=$1 AND kind='dispatch'", [t603]))[0].d, true, 'lệnh dispatch chờ bị hủy');
  });

  // ---- mã MCP ----
  await step('tạo mã MCP: hiện đúng một lần, không lưu đệm; danh sách chỉ có tiền tố; quyền không hợp lệ bị từ chối', async () => {
    const csrf = await minh.csrf('/app/tokens');
    const r = await minh.post('/app/tokens', { _csrf: csrf, name: 'Claude laptop', client: 'claude', days: '30', scopes: ['read', 'write'] });
    assert.equal(r.status, 200); assert.equal(r.headers['cache-control'], 'no-store');
    const tok = /value="(eos_[0-9a-f]{48})"/.exec(r.text)?.[1]; assert.ok(tok, 'có mã trên trang');
    const list = await minh.get('/app/tokens'); lacks(list, tok); has(list, `eos_${tok.slice(4, 12)}…`); has(list, 'read, write');
    assert.equal((await sql('SELECT scopes::text, user_id FROM agent.mcp_tokens WHERE prefix=$1', [tok.slice(4, 12)]))[0].scopes, '{read,write}');
    for (const [form, why] of [[{ name: 'Delegate', scopes: ['read', 'delegate'], days: '30' }, 'delegate'], [{ name: 'Draft', scopes: ['draft'], days: '30' }, 'draft'], [{ name: 'Quá hạn', scopes: ['read'], days: '365' }, '365'], [{ name: 'Rỗng', days: '30' }, 'rỗng'], [{ name: 'x', scopes: ['read'], days: '30' }, 'tên ngắn']]) {
      const b = await minh.post('/app/tokens', { _csrf: csrf, client: 'other', ...form }); assert.equal(b.status, 400, why);
    }
    const id = (await sql('SELECT id FROM agent.mcp_tokens WHERE prefix=$1', [tok.slice(4, 12)]))[0].id;
    const khach = new Browser(); await login(khach, { email: 'khach@khac.vn' }); const kc = await khach.csrf('/app/tokens');
    await khach.post(`/app/tokens/${id}/revoke`, { _csrf: kc }); assert.equal((await sql('SELECT revoked_at FROM agent.mcp_tokens WHERE id=$1', [id]))[0].revoked_at, null, 'người khác không thu hồi được');
    const rv = await minh.post(`/app/tokens/${id}/revoke`, { _csrf: csrf }); assert.equal(rv.status, 303);
    assert.notEqual((await sql('SELECT revoked_at FROM agent.mcp_tokens WHERE id=$1', [id]))[0].revoked_at, null);
    assert.equal((await minh.post('/app/tokens/khong-phai-uuid/revoke', { _csrf: csrf })).status, 404);
  });

  // ---- quản trị ----
  const adm = new Browser();
  await step('quản trị: người thường bị chặn; quản trị thấy agent, cầu nối, mã, nhật ký MCP', async () => {
    for (const p of ['/app/admin', '/app/admin/tokens', '/app/admin/calls']) assert.equal((await minh.get(p)).status, 403, p);
    lacks(await minh.get('/app/'), 'href="/app/admin"');
    await login(adm, { email: 'admin@demo.vn' });
    const o = await adm.get('/app/admin'); assert.equal(o.status, 200); has(o, 'Cầu nối Hermes'); has(o, 'van-thu'); has(o, 'eos-van-thu'); has(o, 'Lệnh chờ đẩy sang Kanban'); has(o, 'href="/app/admin"');
    const t = await adm.get('/app/admin/tokens'); assert.equal(t.status, 200); has(t, 'minh@demo.vn'); lacks(t, 'token_hash');
    assert.equal((await adm.get('/app/admin/calls?denied=1')).status, 200);
    const csrf = await adm.csrf('/app/admin');
    const id = (await sql("SELECT id FROM agent.mcp_tokens WHERE revoked_at IS NULL AND name='Claude laptop' LIMIT 1"));
    assert.equal(id.length, 0, 'mã trước đã thu hồi');
    const mk = await adm.post('/app/tokens', { _csrf: csrf, name: 'Mã quản trị', client: 'other', days: '7', scopes: ['read'] }); assert.equal(mk.status, 200);
    const mid = (await sql("SELECT id FROM agent.mcp_tokens WHERE name='Mã quản trị'"))[0].id;
    const rv = await adm.post(`/app/admin/tokens/${mid}/revoke`, { _csrf: csrf }); assert.equal(rv.status, 303);
    assert.notEqual((await sql('SELECT revoked_at FROM agent.mcp_tokens WHERE id=$1', [mid]))[0].revoked_at, null);
    assert.equal((await minh.post(`/app/admin/tokens/${mid}/revoke`, { _csrf: await minh.csrf() })).status, 403, 'người thường không dùng đường quản trị');
  });

  // ---- phiên ----
  await step('phiên: cookie giả/sai chữ ký/hết hạn bị bác; khóa tài khoản có hiệu lực ngay; đăng xuất xóa phiên', async () => {
    const forged = new Browser(); forged.jar.set('eos_s', b64u(JSON.stringify({ sub: 'cccccccc-0000-0000-0000-000000000002', csrf: 'x', exp: 9999999999 })) + '.chuky-gia');
    assert.equal((await forged.get('/app/admin')).status, 303);
    const cookie = minh.jar.get('eos_s'); const [p, m] = cookie.split('.');
    const tampered = new Browser(); tampered.jar.set('eos_s', b64u(JSON.stringify({ ...JSON.parse(Buffer.from(p, 'base64url')), sub: 'cccccccc-0000-0000-0000-000000000002' })) + '.' + m);
    assert.equal((await tampered.get('/app/admin')).status, 303, 'sửa nội dung cookie làm hỏng chữ ký');
    const expired = new Browser(); const { createAuth } = await import('../src/auth.mjs');
    const au = createAuth(app.locals.cfg, app.locals.db);
    expired.jar.set('eos_s', au.sign({ sub: 'cccccccc-0000-0000-0000-000000000001', csrf: 'c', exp: Math.floor(Date.now() / 1000) - 5 }));
    assert.equal((await expired.get('/app/')).status, 303);
    const victim = new Browser(); await login(victim, { email: 'admin@demo.vn' }); assert.equal((await victim.get('/app/admin')).status, 200);
    await sql("UPDATE core.users SET active=false WHERE email='admin@demo.vn'");
    const after = await victim.get('/app/admin'); assert.equal(after.status, 303, 'khóa tài khoản có hiệu lực ngay'); assert.match(after.headers.location, /\/app\/login/);
    await sql("UPDATE core.users SET active=true WHERE email='admin@demo.vn'");
    const csrf = await minh.csrf(); const out = await minh.post('/app/logout', { _csrf: csrf }); assert.equal(out.status, 303);
    assert.ok(!minh.jar.has('eos_s')); assert.equal((await minh.get('/app/')).status, 303);
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
  await step('giới hạn tốc độ: đăng nhập và thao tác ghi vượt ngưỡng nhận 429', async () => {
    const saved = { ...process.env }; Object.assign(process.env, { LOGIN_RATE_PER_MIN: '5', WRITE_RATE_PER_MIN: '4' });
    const { buildApp: build3 } = await import('../src/server.mjs?ratelimit'); const a3 = build3();
    const s3 = await new Promise((ok) => { const s = a3.listen(0, '127.0.0.1', () => ok(s)); });
    const hit = (path, method = 'GET', ph = {}) => new Promise((ok) => { const r = http.request({ host: '127.0.0.1', port: s3.address().port, path, method, headers: { host: `127.0.0.1:${port}`, ...ph } }, (res) => { res.resume(); ok(res.statusCode); }); r.end(); });
    const codes = []; for (let i = 0; i < 9; i++) codes.push(await hit('/app/auth/google')); assert.ok(codes.slice(0, 5).every((c) => c === 303) && codes.slice(5).every((c) => c === 429), codes.join(','));
    const w = []; for (let i = 0; i < 7; i++) w.push(await hit('/app/tasks', 'POST', { origin })); assert.ok(w.includes(429), `thao tác ghi không bị giới hạn: ${w}`);
    s3.close(); await a3.locals.db.close(); Object.assign(process.env, saved);
  });

  console.log(`web e2e: ${passed} bước đạt`);
} finally {
  srv.close(); gsrv.close(); await app.locals.db.close(); await admin.end();
}
