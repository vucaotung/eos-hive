// WeKnora máy khách: sao chép cấu hình KB mẫu, tự lùi khi WeKnora cũ, metadata, cờ không hỗ trợ. Máy chủ giả, không cần CSDL.
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';

let calls = [], tplExtra = true, rejectExtra = false, putStatus = 200;
const srv = http.createServer((req, res) => {
  let b = ''; req.on('data', (c) => (b += c)); req.on('end', () => {
    const body = b && req.headers['content-type']?.includes('json') ? JSON.parse(b) : null;
    calls.push([req.method, req.url, body, req.headers['accept-language']]);
    const send = (st, j) => { res.writeHead(st, { 'content-type': 'application/json' }); res.end(JSON.stringify(j)); };
    if (req.headers['x-api-key'] !== 'k') return send(401, { message: 'bad key' });
    if (req.method === 'GET' && req.url === '/api/v1/knowledge-bases') {
      return send(200, { data: [{ id: 'tpl', name: '_mau-du-an', embedding_model_id: 'e', summary_model_id: 's', chunking_config: { n: 1 },
        ...(tplExtra ? { indexing_strategy: { wiki_enabled: true }, wiki_config: { auto_generate: true }, vlm_config: { enabled: true } } : {}) }] });
    }
    if (req.method === 'POST' && req.url === '/api/v1/knowledge-bases') {
      if (rejectExtra && body.wiki_config) return send(400, { message: 'unknown field wiki_config' });
      return send(200, { data: { id: 'new-kb' } });
    }
    if (req.method === 'PUT' && req.url.startsWith('/api/v1/knowledge/')) return send(putStatus, { data: {} });
    send(404, {});
  });
});
await new Promise((ok) => srv.listen(0, '127.0.0.1', ok));
Object.assign(process.env, { WEKNORA_BASE_URL: `http://127.0.0.1:${srv.address().port}/api/v1`, WEKNORA_API_KEY: 'k', WEKNORA_TEMPLATE_KB: '_mau-du-an' });
const wk = await import('../src/weknora.mjs');
const created = () => calls.find((c) => c[0] === 'POST')[2];
const reset = () => { calls = []; };

test('KB mới sao chép indexing_strategy, wiki_config, vlm_config từ KB mẫu', async () => {
  reset(); tplExtra = true; rejectExtra = false;
  const r = await wk.ensureKb('Dự án A', 'mô tả');
  assert.deepEqual([r.id, r.created], ['new-kb', true]);
  assert.deepEqual(created().indexing_strategy, { wiki_enabled: true }); assert.deepEqual(created().wiki_config, { auto_generate: true }); assert.deepEqual(created().vlm_config, { enabled: true });
  assert.equal(created().embedding_model_id, 'e');
});
test('KB mẫu thiếu trường nào thì bỏ qua trường đó (không gửi null)', async () => {
  reset(); tplExtra = false;
  await wk.ensureKb('Dự án B');
  for (const k of ['indexing_strategy', 'wiki_config', 'vlm_config']) assert.ok(!(k in created()), k);
  assert.deepEqual(created().chunking_config, { n: 1 });
});
test('WeKnora cũ từ chối trường mở rộng (400): tạo lại chỉ với cấu hình lõi và báo extra_config_ignored', async () => {
  reset(); tplExtra = true; rejectExtra = true; const logs = [];
  const r = await wk.ensureKb('Dự án C', '', (m) => logs.push(m));
  assert.equal(r.created, true); assert.equal(r.extra_config_ignored, true); assert.equal(logs.length, 1);
  assert.equal(calls.filter((c) => c[0] === 'POST').length, 2); assert.ok(!('wiki_config' in calls.filter((c) => c[0] === 'POST')[1][2]));
});
test('KB pháp luật (wiki: true) luôn bật Wiki, kể cả khi KB mẫu không có cấu hình Wiki', async () => {
  reset(); tplExtra = false; rejectExtra = false;
  await wk.ensureKb('phap-luat', '', console.warn, { wiki: true });
  assert.equal(created().indexing_strategy.wiki_enabled, true); assert.equal(created().wiki_config.auto_generate, true);
  reset(); tplExtra = true; await wk.ensureKb('tieu-chuan', '', console.warn, { wiki: true });
  assert.equal(created().wiki_config.auto_generate, true, 'giữ wiki_config của KB mẫu');
});
test('cleanMetadata: tối đa 20 khóa, khóa ≤ 64 ký tự, giá trị ≤ 1000 ký tự, kiểu hợp lệ', () => {
  const big = {}; for (let i = 0; i < 30; i++) big['k' + i] = i;
  assert.equal(Object.keys(wk.cleanMetadata(big)).length, 20);
  const m = wk.cleanMetadata({ ['x'.repeat(80)]: 'a', s: 'y'.repeat(2000), n: 3, b: true, z: null, u: undefined, o: { a: 1 } });
  assert.ok(Object.keys(m).every((k) => k.length <= 64)); assert.equal(m.s.length, 1000); assert.equal(m.n, 3); assert.equal(m.z, null); assert.ok(!('u' in m)); assert.equal(typeof m.o, 'string');
});
test('setMetadata: lỗi tạm thời (500) báo lại nhưng không đặt cờ; 404 đặt cờ, ghi log đúng một lần, lần sau không gọi PUT', async () => {
  reset(); putStatus = 500; const logs = [];
  const a = await wk.setMetadata('d1', { a: 1 }, (m) => logs.push(m)); assert.equal(a.ok, false); assert.equal(wk.state.metadataUnsupported, false);
  putStatus = 404;
  const b = await wk.setMetadata('d2', { a: 1 }, (m) => logs.push(m)); assert.equal(b.reason, 'unsupported'); assert.equal(wk.state.metadataUnsupported, true);
  const n = calls.length; const c = await wk.setMetadata('d3', { a: 1 }, (m) => logs.push(m)); assert.equal(c.reason, 'unsupported');
  assert.equal(calls.length, n, 'không gọi PUT nữa'); assert.equal(logs.length, 1, 'log một lần');
});
test.after(() => srv.close());

test('mọi lệnh gọi WeKnora gửi Accept-Language: Vietnamese (thiếu thì WeKnora mặc định zh-CN, Wiki ra tiếng Trung)', async () => {
  reset(); await wk.listKbs();
  assert.equal(calls[0][3], 'Vietnamese');
  process.env.WEKNORA_DOC_LANGUAGE = 'English'; reset(); await wk.listKbs(); delete process.env.WEKNORA_DOC_LANGUAGE;
  assert.equal(calls[0][3], 'English');
});
