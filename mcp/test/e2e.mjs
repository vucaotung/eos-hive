// Kiểm thử đầu–cuối: máy chủ MCP thật + Postgres thật + Google Drive giả lập, gọi bằng MCP client của SDK.
// Chạy: DATABASE_URL=... TOKEN_FULL=... TOKEN_READ=... TOKEN_OTHER=... node test/e2e.mjs
import assert from 'node:assert/strict';
import express from 'express';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

// ---------- Drive giả lập ----------
const files = new Map([['FOLDER_MINH', { id: 'FOLDER_MINH', name: 'DEO - Demo - KT - Trần Minh', mimeType: 'application/vnd.google-apps.folder', parents: [] }],
                       ['OUTSIDE1234567', { id: 'OUTSIDE1234567', name: 'la.docx', mimeType: 'x', parents: ['SOMEONE_ELSE'] }],
                       ['SOMEONE_ELSE', { id: 'SOMEONE_ELSE', name: 'Thư mục khác', parents: [] }]]);
let seq = 0;
const drive = express();
drive.post('/token', express.urlencoded({ extended: false }), (req, res) => {
  assert.equal(req.body.grant_type, 'refresh_token');
  res.json({ access_token: 'fake-access', expires_in: 3600 });
});
drive.use((req, res, next) => (req.get('authorization') === 'Bearer fake-access' ? next() : res.status(401).end()));
drive.get('/drive/v3/files', (req, res) => {
  const m = req.query.q.match(/'([^']+)' in parents and name = '([^']+)'/);
  res.json({ files: [...files.values()].filter((f) => f.parents.includes(m[1]) && f.name === m[2]).map((f) => ({ id: f.id })) });
});
drive.get('/drive/v3/files/:id', (req, res) => {
  const f = files.get(req.params.id);
  if (!f) return res.status(404).json({ error: 'notFound' });
  res.json({ ...f, webViewLink: `https://drive.google.com/file/d/${f.id}/view` });
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
    assert.deepEqual(list.map((t) => t.id).sort(), ['T-501', 'T-503', 'T-504']);
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
    assert.deepEqual(tools, ['eos_delegate', 'eos_draft_document', 'eos_get_task', 'eos_guide']);
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

  console.log(`MCP e2e: ${passed} bước đạt`);
} finally {
  srv.close(); driveSrv.close(); await close();
}
