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
                       ['OUTMD00000001', { id: 'OUTMD00000001', name: 'ngoai.md', mimeType: 'text/markdown', parents: ['SOMEONE_ELSE'], content: 'bí mật ngoài phạm vi' }]]);
let seq = 0;
const drive = express();
drive.post('/token', express.urlencoded({ extended: false }), (req, res) => {
  assert.equal(req.body.grant_type, 'refresh_token');
  res.json({ access_token: 'fake-access', expires_in: 3600 });
});
drive.use((req, res, next) => (req.get('authorization') === 'Bearer fake-access' ? next() : res.status(401).end()));
drive.get('/drive/v3/files', (req, res) => {
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
    assert.deepEqual(tools, ['eos_approvals_pending', 'eos_attach_drive_file', 'eos_comment', 'eos_get_task', 'eos_guide', 'eos_incoming_list',
      'eos_list_kbs', 'eos_list_tasks', 'eos_my_day', 'eos_my_hr', 'eos_save_to_drive', 'eos_search', 'eos_submit_result', 'eos_update_progress', 'eos_whoami']);
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
    assert.deepEqual(tools, ['eos_catalog_upsert', 'eos_delegate', 'eos_draft_document', 'eos_get_task', 'eos_guide', 'eos_project_files', 'eos_project_read', 'eos_project_save_report', 'eos_project_scope', 'eos_runner_claim', 'eos_runner_report', 'eos_runner_setup']);
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
  await step('runner Python (máy khách MCP không giữ phiên) nói chuyện được với máy chủ thật', async () => {
    const { execFile } = await import('node:child_process'); const { promisify } = await import('node:util');   // bất đồng bộ: máy chủ MCP chạy cùng tiến trình với test
    const py = (script, ...args) => promisify(execFile)('python3', ['-I', '-c', "import sys; sys.path.insert(0, '../runner'); import json, eos_z2_runner as R\n" + script, ...args],
      { cwd: new URL('..', import.meta.url).pathname, encoding: 'utf8' });
    const ok = JSON.parse((await py("print(json.dumps(R.Mcp(sys.argv[1], sys.argv[2]).call('eos_runner_claim')))", url.href, process.env.TOKEN_RUNNER)).stdout);
    assert.equal(ok.idle, true);
    await assert.rejects(py("R.Mcp(sys.argv[1], sys.argv[2]).call('eos_runner_claim')", url.href, 'eos_' + '0'.repeat(48)), (e) => /McpError.*401/.test(e.stderr), 'mã sai bị từ chối');
  });
  await dp.close(); await vt.close(); await rn.close(); await adm.end();

  console.log(`MCP e2e: ${passed} bước đạt`);
} finally {
  srv.close(); driveSrv.close(); await close();
}
