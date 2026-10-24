// Kiểm thử đầu–cuối: máy chủ MCP thật + Postgres thật + Google Drive giả lập, gọi bằng MCP client của SDK.
// Chạy: DATABASE_URL=... TOKEN_FULL=... TOKEN_READ=... TOKEN_OTHER=... node test/e2e.mjs
import assert from 'node:assert/strict';
import express from 'express';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

// ---------- Drive giả lập ----------
const files = new Map([['FOLDER_MINH', { id: 'FOLDER_MINH', name: 'DEO - Demo - KT - Trần Minh', mimeType: 'application/vnd.google-apps.folder', parents: [] }],
                       ['OUTSIDE1234567', { id: 'OUTSIDE1234567', name: 'la.docx', mimeType: 'x', parents: ['SOMEONE_ELSE'] }],
                       ['SOMEONE_ELSE', { id: 'SOMEONE_ELSE', name: 'Thư mục khác', parents: [] }],
                       // thư mục Markdown của lần chạy dự án: gốc → HD-01.md, thư mục con → QD-02.md; một tệp md nằm ngoài
                       ['MDROOT0000001', { id: 'MDROOT0000001', name: 'md', mimeType: 'application/vnd.google-apps.folder', parents: ['SRCFOLDER0000001'] }],
                       ['MDFILE0000001', { id: 'MDFILE0000001', name: 'HD-01.md', mimeType: 'text/markdown', parents: ['MDROOT0000001'], content: '# Hợp đồng 01\n' + 'Điều khoản. '.repeat(4000) }],
                       ['MDSUB00000001', { id: 'MDSUB00000001', name: 'phap-ly', mimeType: 'application/vnd.google-apps.folder', parents: ['MDROOT0000001'] }],
                       ['MDFILE0000002', { id: 'MDFILE0000002', name: 'QD-02.md', mimeType: 'text/markdown', parents: ['MDSUB00000001'], content: '# Quyết định 02\nPhê duyệt dự án.' }],
                       ['MDIDX0000001', { id: 'MDIDX0000001', name: '00_MUC_LUC.md', mimeType: 'text/markdown', parents: ['MDROOT0000001'], content: '# Mục lục\nbảng mục lục dài hơn hai mươi ký tự' }],
                       ['MDFILE0000003', { id: 'MDFILE0000003', name: 'FM.md', mimeType: 'text/markdown', parents: ['MDSUB00000001'], content: '---\nsha256: abc123\nsource_path: A/B/gốc.pdf\npages: 7\n---\n\nNội dung thật của văn bản, đủ dài để nạp vào kho.' }],
                       ['OUTMD00000001', { id: 'OUTMD00000001', name: 'ngoai.md', mimeType: 'text/markdown', parents: ['SOMEONE_ELSE'], content: 'bí mật ngoài phạm vi' }]]);
let seq = 0;
const drive = express();
drive.post('/token', express.urlencoded({ extended: false }), (req, res) => {
  assert.equal(req.body.grant_type, 'refresh_token');
  res.json({ access_token: 'fake-access', expires_in: 3600 });
});
drive.use((req, res, next) => (req.get('authorization') === 'Bearer fake-access' ? next() : res.status(401).end()));
drive.get('/drive/v3/files', (req, res) => {
  if (req.query.q.includes("'FOLDER_DENIED' in parents")) return res.status(403).json({ error: 'forbidden' });
  const lst = req.query.q.match(/^'([^']+)' in parents and trashed = false$/);
  if (lst) return res.json({ files: [...files.values()].filter((f) => f.parents.includes(lst[1])).map((f) => ({ id: f.id, name: f.name, mimeType: f.mimeType, size: String((f.content || '').length), modifiedTime: '2026-10-20T00:00:00Z' })) });
  const m = req.query.q.match(/'([^']+)' in parents and name = '([^']+)'/);
  res.json({ files: [...files.values()].filter((f) => f.parents.includes(m[1]) && f.name === m[2]).map((f) => ({ id: f.id })) });
});
drive.get('/drive/v3/files/:id', (req, res) => {
  const f = files.get(req.params.id);
  if (!f) return res.status(404).json({ error: 'notFound' });
  if (req.query.alt === 'media') return res.type('text/markdown').send(f.content || '');
  res.json({ ...f, size: f.content ? String(f.content.length) : f.size, webViewLink: `https://drive.google.com/file/d/${f.id}/view` });
});
drive.post('/drive/v3/files', express.json(), (req, res) => {
  const id = `F${++seq}`.padEnd(12, '0');
  files.set(id, { id, ...req.body });
  res.json({ id });
});
drive.post('/upload/drive/v3/files', express.raw({ type: '*/*', limit: '20mb' }), (req, res) => {
  const text = req.body.toString('utf8');
  const meta = JSON.parse(text.split('\r\n\r\n')[1].split('\r\n')[0]);
  const id = `U${++seq}`.padEnd(14, 'x');
  files.set(id, { id, ...meta, mimeType: 'text/markdown', size: String(req.body.length) });
  res.json({ id, name: meta.name, mimeType: 'text/markdown', size: '42', webViewLink: `https://drive.google.com/file/d/${id}/view` });
});
const driveSrv = await new Promise((ok) => { const s = drive.listen(0, '127.0.0.1', () => ok(s)); });
const dport = driveSrv.address().port;
process.env.DRIVE_API_BASE = `http://127.0.0.1:${dport}`;
process.env.GOOGLE_TOKEN_URL = `http://127.0.0.1:${dport}/token`;
Object.assign(process.env, { GOOGLE_CLIENT_ID: 'x', GOOGLE_CLIENT_SECRET: 'y', GOOGLE_REFRESH_TOKEN: 'z' });

// ---------- WeKnora giả lập: ghi lại yêu cầu, kiểm khóa API ----------
const wkCalls = [];
const wk = express(); wk.use(express.json());
wk.use((req, res, next) => (req.get('x-api-key') === 'wk-test-key' ? next() : res.status(401).json({ message: 'bad key' })));
wk.get('/api/v1/knowledge-bases', (req, res) => res.json({ data: [{ id: 'tplkb000001', name: 'kdc-thanh-lap', embedding_model_id: 'emb-1', summary_model_id: 'sum-1', chunking_config: { chunk_size: 512 } }] }));
wk.post('/api/v1/knowledge-bases', (req, res) => { wkCalls.push(['kb', req.body]); res.json({ data: { id: 'wkkb-new-0001' } }); });
wk.post('/api/v1/knowledge-bases/:id/knowledge/manual', (req, res) => { wkCalls.push(['doc', req.params.id, req.body]); res.json({ data: { id: `wkdoc-${wkCalls.length}` } }); });
const wkSrv = await new Promise((ok) => { const s = wk.listen(0, '127.0.0.1', () => ok(s)); });
Object.assign(process.env, { WEKNORA_BASE_URL: `http://127.0.0.1:${wkSrv.address().port}/api/v1`, WEKNORA_API_KEY: 'wk-test-key' });

// ---------- Máy chủ MCP ----------
const { buildApp } = await import('../src/server.mjs');
const { close } = await import('../src/db.mjs');
const srv = await new Promise((ok) => { const s = buildApp().listen(0, '127.0.0.1', () => ok(s)); });
const url = new URL(`http://127.0.0.1:${srv.address().port}/mcp`);

async function connect(token) {
  const client = new Client({ name: 'test', version: '1' });
  await client.connect(new StreamableHTTPClientTransport(url, { requestInit: { headers: { Authorization: `Bearer ${token}` } } }));
  return client;
}
const text = (r) => r.content[0].text;
const json = (r) => JSON.parse(text(r));
let passed = 0;
const step = async (name, fn) => { await fn(); passed++; console.log('  ✓', name); };

try {
  await step('mã sai bị từ chối 401', async () => {
    const r = await fetch(url, { method: 'POST', headers: { Authorization: 'Bearer eos_' + '0'.repeat(48), 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'x', version: '1' } } }) });
    assert.equal(r.status, 401);
  });

  const c = await connect(process.env.TOKEN_FULL);
  await step('liệt kê công cụ, tài nguyên, lời nhắc', async () => {
    const tools = (await c.listTools()).tools.map((t) => t.name).sort();
    assert.deepEqual(tools, ['eos_approvals_pending', 'eos_attach_drive_file', 'eos_comment', 'eos_company_digest', 'eos_get_task', 'eos_guide', 'eos_incoming_list',
      'eos_list_kbs', 'eos_list_members', 'eos_list_tasks', 'eos_my_day', 'eos_my_hr', 'eos_save_to_drive', 'eos_search', 'eos_submit_result', 'eos_task_save', 'eos_update_progress', 'eos_whoami']);
    assert.equal((await c.listResources()).resources.length, 6);
    assert.equal((await c.listPrompts()).prompts.length, 2);
    const p = await c.getPrompt({ name: 'lam_va_nop_viec', arguments: { task: 'T-501' } });
    assert.match(p.messages[0].content.text, /eos_get_task T-501/);
  });
  await step('đọc hướng dẫn và whoami', async () => {
    assert.match(text(await c.callTool({ name: 'eos_guide', arguments: { topic: 'report' } })), /eos_submit_result/);
    const me = json(await c.callTool({ name: 'eos_whoami', arguments: {} }));
    assert.equal(me.user.name, 'Trần Minh');
    assert.equal(me.companies[0].department, 'Kỹ thuật');
    assert.deepEqual(me.token_scopes, ['read', 'write', 'drive', 'kb']);
  });
  await step('việc của tôi, chi tiết, tìm không dấu', async () => {
    const list = json(await c.callTool({ name: 'eos_list_tasks', arguments: {} }));
    assert.deepEqual(list.map((t) => t.id).sort(), ['T-1', 'T-501', 'T-503', 'T-504']);
    const day = json(await c.callTool({ name: 'eos_my_day', arguments: {} }));
    assert.equal(day.approvals_waiting, 0);
    assert.ok(Array.isArray(day.overdue));
    const t = json(await c.callTool({ name: 'eos_get_task', arguments: { task: 'T-501' } }));
    assert.equal(t.can_submit, true);
    const s = json(await c.callTool({ name: 'eos_search', arguments: { query: 'khoi luong mong' } }));
    assert.equal(s[0].id, 'T-501');
  });
  await step('tiến độ + bình luận', async () => {
    json(await c.callTool({ name: 'eos_update_progress', arguments: { task: 501, progress: 40, note: 'Xong phần móng M1' } }));
    json(await c.callTool({ name: 'eos_comment', arguments: { task: 'T-501', body: 'Cần bản vẽ KC-02 để làm tiếp' } }));
  });
  await step('lưu kết quả vào Drive cá nhân', async () => {
    const r = json(await c.callTool({ name: 'eos_save_to_drive', arguments: { task: 'T-501', filename: 'Bang khoi luong mong.md', content: '| Cấu kiện | m3 |\n|---|---|\n| M1 | 12,4 |' } }));
    assert.equal(r.saved, 'T-501 - Bang khoi luong mong.md');
    assert.match(r.folder, /^Kết quả\/\d{4}-\d{2}$/);
    const ketqua = [...files.values()].find((f) => f.name === 'Kết quả');
    assert.deepEqual(ketqua.parents, ['FOLDER_MINH'], 'thư mục Kết quả nằm trong thư mục của Minh');
    const t = json(await c.callTool({ name: 'eos_get_task', arguments: { task: 501 } }));
    assert.equal(t.files[0].name, 'T-501 - Bang khoi luong mong.md');
    assert.equal(t.files[0].role, 'result');
  });
  await step('gắn tệp có sẵn: trong thư mục được, ngoài thư mục bị chặn', async () => {
    const inside = [...files.values()].find((f) => f.name?.startsWith('T-501'));
    const r = json(await c.callTool({ name: 'eos_attach_drive_file', arguments: { task: 501, url: `https://drive.google.com/file/d/${inside.id}/view` } }));
    assert.equal(r.attached, inside.name);
    const bad = await c.callTool({ name: 'eos_attach_drive_file', arguments: { task: 501, url: 'https://drive.google.com/file/d/OUTSIDE1234567/view' } });
    assert.equal(bad.isError, true);
    assert.match(text(bad), /không nằm trong thư mục/);
  });
  await step('nộp kết quả → Xong', async () => {
    const r = json(await c.callTool({ name: 'eos_submit_result', arguments: { task: 'T-501', summary: 'Đã lập bảng khối lượng móng M1–M4, tệp trong Kết quả.' } }));
    assert.equal(r.status, 'done');
    const again = await c.callTool({ name: 'eos_submit_result', arguments: { task: 'T-501', summary: 'Nộp lại lần nữa xem sao' } });
    assert.equal(again.isError, true);
  });
  await step('không nộp hộ việc của người khác', async () => {
    const r = await c.callTool({ name: 'eos_submit_result', arguments: { task: 502, summary: 'Nộp hộ chị Lan việc họp' } });
    assert.equal(r.isError, true);
    assert.match(text(r), /Chỉ người được giao/);
  });
  await c.close();

  const ro = await connect(process.env.TOKEN_READ);
  await step('mã chỉ đọc không ghi được', async () => {
    assert.equal((await ro.callTool({ name: 'eos_list_tasks', arguments: { status: 'all' } })).isError, undefined);
    const w = await ro.callTool({ name: 'eos_comment', arguments: { task: 501, body: 'thử' } });
    assert.equal(w.isError, true);
    assert.match(text(w), /phạm vi "write"/);
  });
  await ro.close();

  const other = await connect(process.env.TOKEN_OTHER);
  await step('người khác phòng không xem được việc', async () => {
    const r = await other.callTool({ name: 'eos_get_task', arguments: { task: 501 } });
    assert.equal(r.isError, true);
    assert.match(text(r), /Không có quyền/);
    const d = await other.callTool({ name: 'eos_save_to_drive', arguments: { task: 501, filename: 'x.md', content: 'x' } });
    assert.equal(d.isError, true);
  });
  await other.close();

  await step('mã thiếu hr_self không đọc công của mình', async () => {
    const r = await (await connect(process.env.TOKEN_FULL)).callTool({ name: 'eos_my_hr', arguments: { what: 'leave' } });
    assert.equal(r.isError, true);
    assert.match(text(r), /hr_self/);
  });

  const ag = await connect(process.env.TOKEN_AGENT);
  await step('worker agent: chỉ có công cụ đọc, chia việc và soạn dự thảo', async () => {
    const tools = (await ag.listTools()).tools.map((t) => t.name).sort();
    assert.deepEqual(tools, ['eos_catalog_upsert', 'eos_delegate', 'eos_draft_document', 'eos_get_task', 'eos_guide', 'eos_kb_ingest', 'eos_project_files', 'eos_project_read', 'eos_project_save_report', 'eos_project_scope', 'eos_runner_claim', 'eos_runner_report', 'eos_runner_setup']);
    assert.match(text(await ag.callTool({ name: 'eos_guide', arguments: {} })), /kanban_complete/);
  });
  await step('worker đọc việc có thẻ chạy, bị chặn với việc khác', async () => {
    const t = json(await ag.callTool({ name: 'eos_get_task', arguments: { task: 'T-503' } }));
    assert.equal(t.assignee, 'Trần Minh');
    const bad = await ag.callTool({ name: 'eos_get_task', arguments: { task: 'T-501' } });
    assert.equal(bad.isError, true);
    assert.match(text(bad), /không có thẻ đang chạy/);
  });
  await step('điều phối chia việc con cho văn thư', async () => {
    const r = json(await ag.callTool({ name: 'eos_delegate', arguments: { task: 503, items: [
      { agent: 'van-thu', title: 'Gom biên bản nghiệm thu từ công văn đến', skill: 'tra-cuu' },
    ] } }));
    assert.equal(r.children.length, 1);
  });
  await ag.close();
  const ag2 = await connect(process.env.TOKEN_AGENT2);
  await step('văn thư không có quyền chia việc', async () => {
    const tools = (await ag2.listTools()).tools.map((t) => t.name);
    assert.ok(tools.includes('eos_delegate'));   // công cụ có, nhưng mã không có phạm vi delegate
    const r = await ag2.callTool({ name: 'eos_delegate', arguments: { task: 503, items: [{ agent: 'dieu-phoi', title: 'thử' }] } });
    assert.equal(r.isError, true);
    assert.match(text(r), /phạm vi "delegate"/);
  });

  // ---- Văn thư soạn dự thảo văn bản (eos_draft_document) ----
  const cv = { loai: 'cong_van', co_quan_ban_hanh: 'Công ty TNHH Demo', ky_hieu: 'demo-hc', dia_danh: 'Hà Nội', trich_yeu: 'V/v đề nghị cung cấp hồ sơ năng lực',
               kinh_gui: ['Công ty ABC'], noi_dung: 'Kính đề nghị Quý Công ty cung cấp hồ sơ năng lực.', cap_ky: 'KT', chuc_vu_cap_tren: 'Giám đốc',
               chuc_vu_ky: 'Phó giám đốc' };
  let drafted;
  await step('văn thư soạn dự thảo .docx → lưu Drive của người phụ trách, gắn vào việc', async () => {
    const r = json(await ag2.callTool({ name: 'eos_draft_document', arguments: { task: 504, ...cv } }));
    assert.match(r.name, /^T-504 - Du thao - Cong van - de nghi cung cap ho so nang luc\.docx$/);
    assert.ok(r.drive_id && /^https:\/\/drive\.google\.com\//.test(r.url));
    assert.match(r.folder, /Kết quả\/\d{4}-\d{2}/);
    drafted = r;
  });
  await step('người phụ trách thấy dự thảo trong việc của mình', async () => {
    const full = await connect(process.env.TOKEN_FULL);
    const t = json(await full.callTool({ name: 'eos_get_task', arguments: { task: 'T-504' } }));
    assert.ok(t.files.some((f) => f.name === drafted.name), JSON.stringify(t.files));
    await full.close();
  });
  await step('điều phối (mã không có phạm vi draft) không soạn được', async () => {
    const agX = await connect(process.env.TOKEN_AGENT);
    const r = await agX.callTool({ name: 'eos_draft_document', arguments: { task: 503, ...cv } });
    assert.equal(r.isError, true); assert.match(text(r), /phạm vi "draft"/);
    await agX.close();
  });
  await step('văn thư không soạn cho việc không có thẻ chạy của mình', async () => {
    const r = await ag2.callTool({ name: 'eos_draft_document', arguments: { task: 503, ...cv } });
    assert.equal(r.isError, true); assert.match(text(r), /không có thẻ đang chạy/);
  });
  await step('dữ liệu thiếu bị báo rõ, không tạo tệp', async () => {
    const before = json(await (await connect(process.env.TOKEN_FULL)).callTool({ name: 'eos_get_task', arguments: { task: 'T-504' } })).files.length;
    const r = await ag2.callTool({ name: 'eos_draft_document', arguments: { task: 504, ...cv, kinh_gui: undefined } });
    assert.equal(r.isError, true); assert.match(text(r), /kinh_gui/);
    const r2 = await ag2.callTool({ name: 'eos_draft_document', arguments: { task: 504, ...cv, cap_ky: 'TL', chuc_vu_cap_tren: undefined } });
    assert.equal(r2.isError, true); assert.match(text(r2), /chuc_vu_cap_tren/);
    const after = json(await (await connect(process.env.TOKEN_FULL)).callTool({ name: 'eos_get_task', arguments: { task: 'T-504' } })).files.length;
    assert.equal(after, before, 'không tạo thêm tệp');
  });
  await ag2.close();


  // ---------- Quy trình dự án: điều phối chia việc có phạm vi → runner → văn thư đọc hồ sơ, lập danh mục ----------
  const pg = (await import('pg')).default; const adm = new pg.Client({ connectionString: process.env.ADMIN_DSN }); await adm.connect();
  const sql = async (q, p) => (await adm.query(q, p)).rows;
  const ROOT = Number(process.env.ROOT_TASK);
  const dp = await connect(process.env.TOKEN_AGENT), vt = await connect(process.env.TOKEN_AGENT2), rn = await connect(process.env.TOKEN_RUNNER);
  let kz2, kvt;
  await step('phạm vi `project`/`runner` chỉ có ở mã agent: mã người bị từ chối', async () => {
    const full = await connect(process.env.TOKEN_FULL);
    const names = (await full.listTools()).tools.map((t) => t.name);
    assert.ok(!names.some((n) => /^eos_(project|runner|catalog)/.test(n)), 'người không thấy công cụ dự án/runner');
    await full.close();
    const tools = (await rn.listTools()).tools.map((t) => t.name);
    for (const n of ['eos_runner_claim', 'eos_runner_report', 'eos_runner_setup']) assert.ok(tools.includes(n), n);
    const r = await rn.callTool({ name: 'eos_project_scope', arguments: { task: ROOT } });
    assert.equal(r.isError, true); assert.match(text(r), /phạm vi "project"/, 'runner không có phạm vi project');
  });
  await step('điều phối đọc phạm vi việc gốc rồi chia việc: thiếu scope bị từ chối, đủ scope ghi vào CSDL', async () => {
    const sc = json(await dp.callTool({ name: 'eos_project_scope', arguments: { task: ROOT } }));
    assert.equal(sc.task.scope.stage, 'orchestrate'); assert.equal(sc.source_drive_folder_id, 'SRCFOLDER0000001'); assert.equal(sc.md_folder_id, null); assert.match(sc.playbook, /project-intake/);
    const bad = await dp.callTool({ name: 'eos_delegate', arguments: { task: ROOT, items: [{ agent: 'ho-so-runner', title: 'Xử lý hồ sơ' }] } });
    assert.equal(bad.isError, true); assert.match(text(bad), /phạm vi/);
    const ok = json(await dp.callTool({ name: 'eos_delegate', arguments: { task: ROOT, items: [
      { agent: 'ho-so-runner', title: 'Tải, chuyển Markdown, đăng ký hồ sơ', skill: 'xu-ly-ho-so', scope: { stage: 'fetch_convert' } },
      { agent: 'van-thu', title: 'Lập danh mục hồ sơ', skill: 'ho-so-danh-muc', scope: { stage: 'catalog', doc_types: ['hop-dong'] }, after: [0] }] } }));
    kz2 = Number(ok.children[0].slice(2)); kvt = Number(ok.children[1].slice(2));
    const rows = await sql('SELECT task_id, skill, scope FROM agent.task_scopes WHERE run_id = (SELECT run_id FROM agent.task_scopes WHERE task_id = $1) ORDER BY task_id', [ROOT]);
    assert.equal(rows.length, 3); assert.equal(rows[1].scope.agent, 'ho-so-runner'); assert.equal(rows[2].scope.stage, 'catalog');
  });
  await step('runner nhận việc qua MCP, đăng ký thư mục md và tệp, báo xong; chống gửi trùng', async () => {
    const c = json(await rn.callTool({ name: 'eos_runner_claim', arguments: {} }));
    assert.equal(c.task.id, kz2); assert.equal(c.scope.stage, 'fetch_convert'); assert.equal(c.run.drive_folder_id, 'SRCFOLDER0000001'); assert.match(c.card, /^runner-\d+$/);
    assert.equal(json(await rn.callTool({ name: 'eos_runner_claim', arguments: {} })).idle, true);
    const st = json(await rn.callTool({ name: 'eos_runner_setup', arguments: { task: kz2, md_folder_id: 'MDROOT0000001', weknora_kb_id: 'kb-test-0001',
      files: [{ drive_id: 'MDFILE0000001', name: 'HD-01.md', url: 'https://drive.google.com/file/d/MDFILE0000001/view', mime: 'text/markdown' },
              { drive_id: 'MDFILE0000002', name: 'QD-02.md', url: 'https://drive.google.com/file/d/MDFILE0000002/view' }] } }));
    assert.equal(st.files, 2);
    const hb = await rn.callTool({ name: 'eos_runner_report', arguments: { card: c.card, event: 'heartbeat', key: 'hb-mcp-0001', payload: { progress: 50 } } });
    assert.equal(json(hb).result, 'ok');
    const done = json(await rn.callTool({ name: 'eos_runner_report', arguments: { card: c.card, event: 'completed', key: 'done-mcp-0001', payload: { summary: 'Đã chuyển 2 tệp Markdown và đăng ký vào kho dữ liệu.' } } }));
    assert.equal(done.result, 'ok');
    const dup = json(await rn.callTool({ name: 'eos_runner_report', arguments: { card: c.card, event: 'completed', key: 'done-mcp-0001', payload: { summary: 'Đã chuyển 2 tệp Markdown và đăng ký vào kho dữ liệu.' } } }));
    assert.equal(dup.result, 'duplicate');
    const bad = await rn.callTool({ name: 'eos_runner_report', arguments: { card: 'runner-999999', event: 'heartbeat', key: 'hb-xx-0001' } });
    assert.equal(bad.isError, true);
    assert.equal((await sql('SELECT status FROM work.tasks WHERE id = $1', [kz2]))[0].status, 'done');
  });
  await step('văn thư (sau khi runner xong) đọc hồ sơ trong phạm vi: liệt kê, đọc từng đoạn; tệp ngoài phạm vi bị từ chối', async () => {
    const ob = (await sql("SELECT id FROM agent.outbox WHERE task_id = $1 AND kind = 'dispatch'", [kvt]))[0];
    assert.ok(ob, 'văn thư được giao sau khi runner xong');
    await sql("SELECT agent.outbox_ack($1, 't_vt_mcp')", [ob.id]); await sql("SELECT agent.ingest_event('eos-demo','t_vt_mcp','claimed','k-vt-mcp')");
    const sc = json(await vt.callTool({ name: 'eos_project_scope', arguments: { task: kvt } }));
    assert.equal(sc.md_folder_id, 'MDROOT0000001'); assert.equal(sc.kb.name, 'Dự án Dự án thử nạp hồ sơ'); assert.equal(sc.tasks.length, 3);
    const ls = json(await vt.callTool({ name: 'eos_project_files', arguments: { task: kvt } }));
    assert.deepEqual(ls.items.map((i) => [i.name, i.folder]), [['phap-ly', true], ['HD-01.md', false]].sort((a, b) => 0) && ls.items.map((i) => [i.name, i.folder]));
    assert.ok(ls.items.some((i) => i.name === 'HD-01.md') && ls.items.some((i) => i.name === 'phap-ly' && i.folder));
    const sub = json(await vt.callTool({ name: 'eos_project_files', arguments: { task: kvt, folder_id: 'MDSUB00000001' } }));
    assert.equal(sub.items[0].name, 'QD-02.md');
    const r1 = json(await vt.callTool({ name: 'eos_project_read', arguments: { task: kvt, file_id: 'MDFILE0000001' } }));
    assert.equal(r1.name, 'HD-01.md'); assert.equal(r1.text.length, 30000); assert.ok(r1.next_offset === 30000 && r1.total_chars > 30000);
    const r2 = json(await vt.callTool({ name: 'eos_project_read', arguments: { task: kvt, file_id: 'MDFILE0000001', offset: r1.next_offset } }));
    assert.equal(r2.next_offset, null); assert.match(json(await vt.callTool({ name: 'eos_project_read', arguments: { task: kvt, file_id: 'MDFILE0000002' } })).text, /Phê duyệt dự án/);
    for (const [args, re] of [[{ file_id: 'OUTMD00000001' }, /ngoài phạm vi/], [{ file_id: 'OUTSIDE1234567' }, /ngoài phạm vi/], [{ file_id: 'KHONGCO000000' }, /Không thấy/], [{ folder_id: 'SOMEONE_ELSE' }, /ngoài phạm vi/]]) {
      const r = await vt.callTool({ name: args.folder_id ? 'eos_project_files' : 'eos_project_read', arguments: { task: kvt, ...args } });
      assert.equal(r.isError, true, JSON.stringify(args)); assert.match(text(r), re);
    }
    const none = await vt.callTool({ name: 'eos_project_files', arguments: { task: kz2 } });
    assert.equal(none.isError, true); assert.match(text(none), /không có thẻ đang chạy/, 'không đọc bằng việc của agent khác');
    const dpR = await dp.callTool({ name: 'eos_project_files', arguments: { task: ROOT } });
    assert.ok(!dpR.isError, 'điều phối (có thẻ gốc) liệt kê được');
  });
  await step('văn thư lập danh mục hồ sơ và lưu bản tổng hợp vào Drive người theo dõi', async () => {
    const r = json(await vt.callTool({ name: 'eos_catalog_upsert', arguments: { task: kvt, items: [
      { category: 'Hợp đồng', record_no: 'HD-01/2026', title: 'Hợp đồng thi công gói 1', issued_on: '2026-03-01', contract_value: 1500000000, drive_id: 'MDFILE0000001' },
      { category: 'Pháp lý', title: 'Quyết định phê duyệt dự án', issued_on: '2026-01-10', drive_id: 'MDFILE0000002' }] } }));
    assert.equal(r.created, 2);
    assert.equal((await sql("SELECT count(*)::int n FROM doc.records WHERE project_id = (SELECT project_id FROM agent.workflow_runs LIMIT 1)"))[0].n, 2);
    const bad = await vt.callTool({ name: 'eos_catalog_upsert', arguments: { task: kvt, items: [{ category: 'X', title: 'ab' }] } });
    assert.equal(bad.isError, true);
    const rep = json(await vt.callTool({ name: 'eos_project_save_report', arguments: { task: kvt, filename: 'Tong hop van ban', content: '# Tổng hợp\n- HD-01.md: hợp đồng thi công 1,5 tỷ.\n- QD-02.md: quyết định phê duyệt.' } }));
    assert.match(rep.name, /^T-\d+ - Tong hop van ban\.md$/); assert.match(rep.url, /^https:\/\/drive\.google\.com/);
    const t = json(await (await connect(process.env.TOKEN_FULL)).callTool({ name: 'eos_get_task', arguments: { task: kvt } }));
    assert.ok(t.files.some((f) => f.name === rep.name), 'báo cáo gắn vào việc');
  });
  await step('nạp kho tri thức bởi agent: chỉ đúng agent, đúng giai đoạn kb_ingest; tạo KB sao chép cấu hình mẫu; bỏ mục lục; tệp ngoài phạm vi lỗi; chạy lại không nạp trùng', async () => {
    const kb = await connect(process.env.TOKEN_KB);
    await sql("UPDATE kb.bases SET weknora_kb_id = 'pending:du-an-thu' WHERE project_id = (SELECT project_id FROM agent.workflow_runs LIMIT 1)");   // runner đã ghi mã thử ở bước trước: đưa về giữ chỗ để thử đường tạo KB
    const tid = (await sql(`INSERT INTO work.tasks (company_id, department_id, project_id, parent_id, source, title, assignee_id, created_by, created_by_agent)
       SELECT company_id, department_id, project_id, $1, 'agent', 'Nạp kho tri thức', assignee_id, created_by, 'dieu-phoi' FROM work.tasks WHERE id = $1 RETURNING id`, [ROOT]))[0].id;
    await sql(`INSERT INTO agent.task_scopes (task_id, run_id, skill, scope, created_by) VALUES ($1, (SELECT run_id FROM agent.task_scopes WHERE task_id = $2), 'kb-quan-tri-du-lieu', '{"stage":"kb_ingest","agent":"quan-tri-du-lieu"}', 'agent:dieu-phoi')`, [tid, ROOT]);
    await sql("UPDATE work.tasks SET agent_id = (SELECT id FROM agent.agents WHERE code = 'quan-tri-du-lieu') WHERE id = $1", [tid]);
    const ob = (await sql("SELECT id FROM agent.outbox WHERE task_id = $1 AND kind = 'dispatch'", [tid]))[0];
    await sql("SELECT agent.outbox_ack($1, 't_kb_mcp')", [ob.id]); await sql("SELECT agent.ingest_event('eos-demo','t_kb_mcp','claimed','k-kb-mcp')");
    const call = (args) => kb.callTool({ name: 'eos_kb_ingest', arguments: { task: tid, ...args } });
    const denied = await vt.callTool({ name: 'eos_kb_ingest', arguments: { task: kvt, file_ids: ['MDFILE0000001'] } });
    assert.equal(denied.isError, true); assert.match(text(denied), /phạm vi "ingest"/, 'văn thư không có phạm vi ingest');
    const savedKey = process.env.WEKNORA_API_KEY; delete process.env.WEKNORA_API_KEY;
    const nocfg = await call({ file_ids: ['MDFILE0000001'] }); assert.equal(nocfg.isError, true); assert.match(text(nocfg), /chưa cấu hình WeKnora/); process.env.WEKNORA_API_KEY = savedKey;
    const wrongTask = await kb.callTool({ name: 'eos_kb_ingest', arguments: { task: kvt, file_ids: ['MDFILE0000001'] } });
    assert.equal(wrongTask.isError, true, 'không nạp trong việc của agent khác / không phải kb_ingest');
    const r = json(await call({ file_ids: ['MDFILE0000001', 'MDFILE0000003', 'MDIDX0000001', 'OUTMD00000001'] }));
    assert.equal(r.ingested, 2); assert.equal(r.kb_created, true); assert.equal(r.weknora_kb_id, 'wkkb-new-0001');
    assert.equal(r.skipped.length, 1); assert.match(r.skipped[0].reason, /mục lục/); assert.equal(r.failed.length, 1); assert.match(r.failed[0].error, /ngoài phạm vi/);
    const kbBody = wkCalls.find((c) => c[0] === 'kb')[1];
    assert.equal(kbBody.embedding_model_id, 'emb-1'); assert.equal(kbBody.name, 'Dự án Dự án thử nạp hồ sơ'); assert.deepEqual(kbBody.chunking_config, { chunk_size: 512 });
    const docs = wkCalls.filter((c) => c[0] === 'doc'); assert.equal(docs.length, 2); assert.equal(docs[0][1], 'wkkb-new-0001');
    const fm = docs.find((d) => d[2].title === 'FM')[2].content;
    assert.match(fm, /^Nguồn: gốc\.pdf\n\nNội dung thật/); assert.ok(!/sha256|---/.test(fm), 'front-matter bị bỏ');
    const rows = await sql("SELECT weknora_kb_id, (SELECT count(*)::int FROM kb.sources s WHERE s.base_id = b.id AND s.state = 'loaded') n FROM kb.bases b WHERE project_id = (SELECT project_id FROM agent.workflow_runs LIMIT 1)");
    assert.equal(rows[0].weknora_kb_id, 'wkkb-new-0001'); assert.equal(rows[0].n, 2);
    const again = json(await call({ file_ids: ['MDFILE0000001', 'MDFILE0000003'] }));
    assert.equal(again.ingested, 0); assert.equal(again.skipped.length, 2); assert.equal(wkCalls.filter((c) => c[0] === 'doc').length, 2, 'không nạp trùng'); assert.equal(wkCalls.filter((c) => c[0] === 'kb').length, 1, 'không tạo KB lần hai');
    await kb.close();
  });
  await step('bản tin: phạm vi theo vai trò; tạo/sửa việc qua MCP với email, dự án, agent, phải duyệt', async () => {
    const ad = await connect(process.env.TOKEN_ADMIN), me = await connect(process.env.TOKEN_FULL);
    const dg = json(await ad.callTool({ name: 'eos_company_digest', arguments: { days: 7 } }));
    assert.equal(dg.scope, 'Toàn công ty'); for (const k of ['open', 'overdue', 'due_today', 'blocked', 'ask_human', 'in_review', 'done_period']) assert.equal(typeof dg.counts[k], 'number', k);
    assert.ok(Array.isArray(dg.by_dept) && Array.isArray(dg.overdue) && dg.agents && typeof dg.agents.running === 'number');
    assert.ok(dg.projects.some((p) => p.name === 'Dự án thử nạp hồ sơ'));
    const mine = json(await me.callTool({ name: 'eos_company_digest', arguments: { days: 1 } }));
    assert.equal(mine.scope, 'Việc của tôi'); assert.equal(mine.agents, null); assert.deepEqual(mine.by_dept, []);
    assert.ok(mine.counts.open >= 1 && mine.counts.open < dg.counts.open + 1, 'thành viên chỉ thấy việc của mình');
    const mem = json(await me.callTool({ name: 'eos_list_members', arguments: {} }));
    assert.ok(mem.some((m) => m.email === 'minh@demo.vn' && m.role === 'member') && mem.every((m) => m.name && m.email), JSON.stringify(mem).slice(0, 200));
    // tạo việc
    const t = json(await ad.callTool({ name: 'eos_task_save', arguments: { title: 'Soạn báo cáo tuần cho phòng', description: 'Mai tạo qua MCP', assignee_email: 'minh@demo.vn', project: 'du-an-thu-nap-ho-so', due_date: '2030-02-01', priority: 'high', approval: true } }));
    assert.match(t.id, /^T-\d+$/);
    const row = (await sql('SELECT assignee_id, priority, project_id IS NOT NULL p, approval_flow_id IS NOT NULL f, created_by FROM work.tasks WHERE id = $1', [Number(t.id.slice(2))]))[0];
    assert.equal(row.assignee_id, 'cccccccc-0000-0000-0000-000000000001'); assert.equal(row.priority, 'high'); assert.equal(row.p, true); assert.equal(row.f, true); assert.equal(row.created_by, 'cccccccc-0000-0000-0000-0000000000ad');
    assert.equal((await sql('SELECT approval_status FROM work.tasks WHERE id = $1', [Number(t.id.slice(2))]))[0].approval_status, 'none');
    // sửa việc: đổi hạn, bỏ yêu cầu duyệt; việc của người khác không sửa được
    const e = json(await ad.callTool({ name: 'eos_task_save', arguments: { id: t.id, due_date: '2030-03-01', approval: false, status: 'in_progress' } }));
    assert.equal(e.id, t.id);
    const r2 = (await sql('SELECT due_date::text d, approval_flow_id, status FROM work.tasks WHERE id = $1', [Number(t.id.slice(2))]))[0];
    assert.equal(r2.d, '2030-03-01'); assert.equal(r2.approval_flow_id, null); assert.equal(r2.status, 'in_progress');
    for (const [args, re] of [[{ title: 'Việc lạ', assignee_email: 'khong-co@demo.vn' }, /Không có thành viên/], [{ title: 'Việc lạ', project: 'khong-co' }, /Không có dự án/], [{ title: 'a' }, /2 đến 300|Too small/]]) {
      const x = await ad.callTool({ name: 'eos_task_save', arguments: args }); assert.equal(x.isError, true); assert.match(text(x), re);
    }
    const other = await connect(process.env.TOKEN_OTHER);
    const deny = await other.callTool({ name: 'eos_task_save', arguments: { id: t.id, title: 'chiếm quyền' } }); assert.equal(deny.isError, true);
    const ro = await (await connect(process.env.TOKEN_READ)).callTool({ name: 'eos_task_save', arguments: { title: 'chỉ đọc không tạo được' } });
    assert.equal(ro.isError, true); assert.match(text(ro), /phạm vi "write"/);
    await ad.close(); await me.close(); await other.close();
  });
  await step('Mai (mã agent task_create): chỉ tạo việc mới + bình luận thường, chỉ thấy việc mình tạo, không sửa/duyệt/trả lời thay', async () => {
    const mai = await connect(process.env.TOKEN_MAI);
    const who = json(await mai.callTool({ name: 'eos_whoami', arguments: {} }));
    assert.deepEqual([...who.token_scopes].sort(), ['read', 'task_create']);
    const t = json(await mai.callTool({ name: 'eos_task_save', arguments: { title: 'Mai tạo: gọi nhà cung cấp', description: 'Yêu cầu của anh Tùng qua Zalo', assignee_email: 'minh@demo.vn' } }));
    assert.match(t.id, /^T-\d+$/);
    const n = Number(t.id.slice(2));
    assert.equal((await sql('SELECT created_by FROM work.tasks WHERE id = $1', [n]))[0].created_by, 'cccccccc-0000-0000-0000-0000000000a5');
    const note = json(await mai.callTool({ name: 'eos_comment', arguments: { task: t.id, body: 'Đã ghi nhận yêu cầu' } }));
    assert.ok(note.comment_id);
    const names = (await mai.listTools()).tools.map((x) => x.name);
    for (const n of ['eos_update_progress', 'eos_submit_result', 'eos_delegate', 'eos_project_scope', 'eos_incoming_list', 'eos_approvals_pending', 'eos_my_hr', 'eos_save_to_drive', 'eos_kb_ingest']) assert.ok(!names.includes(n), 'Mai không thấy ' + n);
    for (const n of ['eos_task_save', 'eos_comment', 'eos_list_members', 'eos_my_day']) assert.ok(names.includes(n), 'Mai thấy ' + n);
    const bad = [
      ['eos_task_save', { id: t.id, title: 'sửa lại' }, /chỉ được tạo việc mới/], ['eos_task_save', { id: t.id, status: 'cancelled' }, /chỉ được tạo việc mới/],
      ['eos_comment', { task: t.id, body: 'trả lời thay', kind: 'answer' }, /bình luận thường/],
      ['eos_task_save', { title: 'giao agent', agent: 'van-thu' }, /không giao cho agent/],
    ];
    for (const [name, args, re] of bad) { const x = await mai.callTool({ name, arguments: args }); assert.equal(x.isError, true, name); assert.match(text(x), re, name); }
    const other = await mai.callTool({ name: 'eos_get_task', arguments: { task: 501 } }); assert.equal(other.isError, true, 'không xem được việc của người khác');
    const cmt = await mai.callTool({ name: 'eos_comment', arguments: { task: 501, body: 'chen vào' } }); assert.equal(cmt.isError, true);
    const dg = json(await mai.callTool({ name: 'eos_company_digest', arguments: { days: 1 } })); assert.equal(dg.scope, 'Việc của tôi');
    await mai.close();
    // người không được mang phạm vi task_create; mã người dùng không cấp được
    await assert.rejects(() => sql("SELECT agent.mcp_token_issue('x','other','{read,task_create}',30)"));
  });
  await step('trả lời agent qua MCP đúng luật như web: người chỉ theo dõi bị từ chối, người phụ trách được; Mai không tạo trùng', async () => {
    await sql("INSERT INTO work.task_watchers (task_id, user_id) VALUES (504, 'cccccccc-0000-0000-0000-000000000003') ON CONFLICT DO NOTHING");
    await sql("UPDATE work.tasks SET waiting_on_human = false WHERE id = 504");
    const watcher = await connect(process.env.TOKEN_OTHER), owner = await connect(process.env.TOKEN_FULL);
    let x = await watcher.callTool({ name: 'eos_comment', arguments: { task: 'T-504', body: 'chen câu trả lời', kind: 'answer' } });
    assert.equal(x.isError, true); assert.match(text(x), /không đang chờ trả lời/, 'agent không chờ thì không trả lời được');
    await sql("UPDATE work.tasks SET waiting_on_human = true WHERE id = 504");
    x = await watcher.callTool({ name: 'eos_comment', arguments: { task: 'T-504', body: 'chen câu trả lời', kind: 'answer' } });
    assert.equal(x.isError, true); assert.match(text(x), /Chỉ người phụ trách hoặc người giao/);
    x = await watcher.callTool({ name: 'eos_comment', arguments: { task: 'T-504', body: 'ghi chú thường', kind: 'note' } }); assert.ok(!x.isError, 'người theo dõi vẫn ghi chú thường được');
    x = await owner.callTool({ name: 'eos_comment', arguments: { task: 'T-504', body: 'đây là câu trả lời của người phụ trách', kind: 'answer' } }); assert.ok(!x.isError, text(x));
    await sql("UPDATE work.tasks SET waiting_on_human = false WHERE id = 504");
    const mai = await connect(process.env.TOKEN_MAI);
    const args = { title: 'Mai tạo việc trùng thử', assignee_email: 'minh@demo.vn' };
    const a = json(await mai.callTool({ name: 'eos_task_save', arguments: args })), b = json(await mai.callTool({ name: 'eos_task_save', arguments: args }));
    assert.equal(b.id, a.id); assert.equal(b.duplicate, true);
    assert.equal((await sql("SELECT count(*)::int n FROM work.tasks WHERE title = 'Mai tạo việc trùng thử'"))[0].n, 1);
    await watcher.close(); await owner.close(); await mai.close();
  });
  await step('mã sai: 20 lần/IP trong cửa sổ → lần 21 trở đi 429 (kể cả mã đúng, không chạm CSDL); hết cửa sổ mã đúng dùng lại được; IP khác không bị ảnh hưởng', async () => {
    const guarded = await new Promise((ok) => { const s = buildApp({ authFailMax: 20, authFailWindowMs: 1500 }).listen(0, '127.0.0.1', () => ok(s)); });
    const url = `http://127.0.0.1:${guarded.address().port}/mcp`;
    const post = (token, ip) => fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', accept: 'application/json, text/event-stream', authorization: `Bearer ${token}`, 'x-forwarded-for': ip },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list' }) });
    const bad = 'eos_' + 'a'.repeat(48);
    const codes = []; for (let i = 0; i < 25; i++) codes.push((await post(bad, '203.0.113.7')).status);
    assert.deepEqual(codes.slice(0, 20), Array(20).fill(401)); assert.deepEqual(codes.slice(20), Array(5).fill(429));
    assert.equal((await post(bad, '203.0.113.7')).headers.get('retry-after'), '300');
    assert.equal((await post(process.env.TOKEN_FULL, '203.0.113.7')).status, 429, 'đang bị chặn thì mã đúng cũng 429');
    assert.equal((await post(process.env.TOKEN_FULL, '198.51.100.9')).status, 200, 'IP khác không bị chặn');
    await new Promise((r) => setTimeout(r, 1700));
    assert.equal((await post(process.env.TOKEN_FULL, '203.0.113.7')).status, 200, 'hết cửa sổ thì mã đúng dùng lại được');
    guarded.close();
  });
  await step('runner Python (máy khách MCP không giữ phiên) nói chuyện được với máy chủ thật', async () => {
    const { execFile } = await import('node:child_process'); const { promisify } = await import('node:util');   // bất đồng bộ: máy chủ MCP chạy cùng tiến trình với test
    const py = (script, ...args) => promisify(execFile)('python3', ['-I', '-c', "import sys; sys.path.insert(0, '../runner'); import json, eos_z2_runner as R\n" + script, ...args],
      { cwd: new URL('..', import.meta.url).pathname, encoding: 'utf8' });
    const ok = JSON.parse((await py("print(json.dumps(R.Mcp(sys.argv[1], sys.argv[2]).call('eos_runner_claim')))", url.href, process.env.TOKEN_RUNNER)).stdout);
    assert.equal(ok.idle, true);
    await assert.rejects(py("R.Mcp(sys.argv[1], sys.argv[2]).call('eos_runner_claim')", url.href, 'eos_' + '0'.repeat(48)), (e) => /McpError.*401/.test(e.stderr), 'mã sai bị từ chối');
  });
  await step('thư mục Drive ở trạng thái pending vẫn lưu được; thư mục agent không có quyền ghi → báo rõ cách khắc phục', async () => {
    const full = await connect(process.env.TOKEN_FULL);
    await sql("UPDATE core.users SET drive_state = 'pending' WHERE id = 'cccccccc-0000-0000-0000-000000000001'");
    const ok = await full.callTool({ name: 'eos_save_to_drive', arguments: { task: 501, filename: 'pending.md', content: 'Nội dung thử đủ dài' } });
    assert.ok(!ok.isError, text(ok));
    await sql("UPDATE core.users SET drive_folder_id = 'FOLDER_DENIED' WHERE id = 'cccccccc-0000-0000-0000-000000000001'");
    const bad = await full.callTool({ name: 'eos_save_to_drive', arguments: { task: 501, filename: 'denied.md', content: 'Nội dung thử đủ dài' } });
    assert.equal(bad.isError, true); assert.match(text(bad), /Người chỉnh sửa/);
    await sql("UPDATE core.users SET drive_state = 'none' WHERE id = 'cccccccc-0000-0000-0000-000000000001'");
    const none = await full.callTool({ name: 'eos_save_to_drive', arguments: { task: 501, filename: 'none.md', content: 'Nội dung thử đủ dài' } });
    assert.equal(none.isError, true); assert.match(text(none), /chưa thiết lập/);
    await sql("UPDATE core.users SET drive_state = 'ok', drive_folder_id = 'FOLDER_MINH' WHERE id = 'cccccccc-0000-0000-0000-000000000001'");
    await full.close();
  });
  await dp.close(); await vt.close(); await rn.close(); await adm.end();

  console.log(`MCP e2e: ${passed} bước đạt`);
} finally {
  srv.close(); driveSrv.close(); wkSrv.close(); await close();
}
