// Văn bản pháp luật do máy chủ tự tải (lawsource.mjs): tên miền, IP nội bộ, chuyển hướng, trần dung lượng, nhận dạng tệp, lỗi font, số hiệu, front matter, gọi bộ chuyển.
import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { otherRefs, fetchOfficial, sniffKind, vietQuality, bodyHasSoHieu, countDieu, buildLawMarkdown, checkConverted, privateIp, fileDomains, convertFile } from '../src/lawsource.mjs';
import { validateLaw } from '../src/law.mjs';

const pub = async () => [{ address: '203.162.1.1', family: 4 }];
const res = (status, { body = '', headers = {} } = {}) => ({
  status, headers: new Headers(headers),
  body: (async function* () { const b = Buffer.from(body); for (let i = 0; i < b.length; i += 4) yield b.subarray(i, i + 4); })(),
});
const VI = 'Điều 1. Phạm vi điều chỉnh\nLuật này quy định về hoạt động đầu tư xây dựng, quyền và nghĩa vụ của cơ quan, tổ chức, cá nhân. ';

test('tên miền tệp: mặc định gồm nguồn chính thống và tệp của cổng Chính phủ', () => {
  const d = fileDomains();
  for (const x of ['vbpl.vn', 'congbao.chinhphu.vn', '*.gov.vn', '*.chinhphu.vn', '*.cdnchinhphu.vn']) assert.ok(d.includes(x), x);
});

test('IP nội bộ bị nhận ra (v4, v6, ánh xạ v4)', () => {
  for (const ip of ['127.0.0.1', '10.1.2.3', '172.16.0.1', '192.168.1.1', '169.254.169.254', '100.64.0.1', '0.0.0.0', '::1', 'fd00::1', 'fe80::1', '::ffff:127.0.0.1']) assert.equal(privateIp(ip), true, ip);
  for (const ip of ['203.162.1.1', '8.8.8.8', '2001:4860::8888']) assert.equal(privateIp(ip), false, ip);
});

test('tải: nguồn ngoài danh sách, http, IP, tên miền trỏ IP nội bộ đều bị từ chối và không gọi mạng', async () => {
  let calls = 0; const f = async () => { calls++; return res(200, { body: 'x' }); };
  for (const u of ['https://thuvienphapluat.vn/a.docx', 'http://vbpl.vn/a.docx', 'https://203.162.1.1/a.pdf', 'https://vbpl.vn.evil.example/a.pdf'])
    await assert.rejects(fetchOfficial(u, { fetchImpl: f, lookup: pub }), undefined, u);
  await assert.rejects(fetchOfficial('https://vbpl.vn/a.pdf', { fetchImpl: f, lookup: async () => [{ address: '10.0.0.5', family: 4 }] }), /nội bộ/);
  assert.equal(calls, 0);
});

test('tải: chuyển hướng được kiểm lại tên miền ở mỗi chặng; quá số lần thì dừng', async () => {
  const seen = [];
  const f = async (u) => { seen.push(u); return u.includes('datafiles') ? res(200, { body: '%PDF-1.7 ...', headers: { 'content-type': 'application/pdf' } }) : res(302, { headers: { location: 'https://datafiles.chinhphu.vn/cpp/files/a.pdf' } }); };
  const r = await fetchOfficial('https://vanban.chinhphu.vn/?docid=1', { fetchImpl: f, lookup: pub });
  assert.equal(r.finalUrl, 'https://datafiles.chinhphu.vn/cpp/files/a.pdf'); assert.equal(seen.length, 2); assert.equal(sniffKind(r.bytes, r.contentType), 'pdf');
  const evil = async () => res(301, { headers: { location: 'https://evil.example/x.pdf' } });
  await assert.rejects(fetchOfficial('https://vbpl.vn/a', { fetchImpl: evil, lookup: pub }), /không thuộc danh sách/);
  const loop = async () => res(302, { headers: { location: '/lai' } });
  await assert.rejects(fetchOfficial('https://vbpl.vn/a', { fetchImpl: loop, lookup: pub, maxRedirects: 3 }), /chuyển hướng/);
  await assert.rejects(fetchOfficial('https://vbpl.vn/a', { fetchImpl: async () => res(404), lookup: pub }), /404/);
});

test('tải: vượt trần dung lượng (theo content-length hoặc khi đọc dần)', async () => {
  await assert.rejects(fetchOfficial('https://vbpl.vn/a', { fetchImpl: async () => res(200, { body: 'x', headers: { 'content-length': String(99 * 1048576) } }), lookup: pub }), /vượt trần/);
  await assert.rejects(fetchOfficial('https://vbpl.vn/a', { fetchImpl: async () => res(200, { body: 'y'.repeat(50) }), lookup: pub, maxBytes: 20 }), /vượt trần/);
});

test('nhận dạng tệp theo nội dung', () => {
  assert.equal(sniffKind(Buffer.from('%PDF-1.4\n...')), 'pdf');
  assert.equal(sniffKind(Buffer.concat([Buffer.from([0x50, 0x4b, 0x03, 0x04]), Buffer.from('....word/document.xml....')])), 'docx');
  assert.equal(sniffKind(Buffer.concat([Buffer.from([0x50, 0x4b, 0x03, 0x04]), Buffer.from('xl/workbook.xml')])), null, 'zip không phải docx');
  assert.equal(sniffKind(Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0, 0])), 'doc');
  assert.equal(sniffKind(Buffer.from('﻿  <!DOCTYPE html><html><body>x')), 'html');
  assert.equal(sniffKind(Buffer.from('{"a":1}'), 'application/json'), null);
  assert.equal(sniffKind(Buffer.from('xin chào'), 'text/html; charset=utf-8'), 'html');
});

test('chất lượng chữ: tiếng Việt chuẩn đạt, bản lỗi font (TCVN3 hiển thị sai) bị từ chối', () => {
  const ok = vietQuality(VI.repeat(30));
  assert.ok(ok.ratio > 0.1 && ok.oddRatio === 0, JSON.stringify(ok));
  const moji = 'LuËt x©y dùng sè 135/2025/QH15. §iÒu 1. Ph¹m vi ®iÒu chØnh. LuËt nµy quy ®Þnh vÒ ho¹t ®éng ®Çu t­ x©y dùng. '.repeat(40);
  assert.ok(vietQuality(moji).oddRatio > 0.02, JSON.stringify(vietQuality(moji)));
  assert.equal(vietQuality('Nhiệt độ 25°C, «trích dẫn» · ± 5%. '.repeat(100)).oddRatio, 0);
  assert.match(checkConverted('135/2025/QH15', moji).join(' '), /lỗi font/);
  assert.deepEqual(checkConverted('135/2025/QH15', `Luật số: 135/2025/QH15\n${VI.repeat(30)}`), []);
});

test('số hiệu phải có trong nội dung (bỏ dấu, khoảng trắng, hoa thường)', () => {
  assert.equal(bodyHasSoHieu('207/2026/NĐ-CP', 'Số: 207/2026/ND-CP\nNGHỊ ĐỊNH'), true);
  assert.equal(bodyHasSoHieu('32/2026/TT-BXD', 'Số: 32 / 2026 / TT - BXD'), true);
  assert.equal(bodyHasSoHieu('135/2025/QH15', 'Luật số 50/2014/QH13'), false);
  assert.match(checkConverted('135/2025/QH15', `Luật số 50/2014/QH13\n${VI.repeat(30)}`).join(' '), /Không thấy số hiệu/);
});

test('đếm điều', () => {
  assert.equal(countDieu('Điều 1. A\n## Điều 2. B\n**Điều 3a.** C\nxem Điều 4 của Luật\nĐiều 5: D\n# **Điều 6. E**\nhết câu. **Điều 7. G**\n# **Điều 6. lặp**'), 6);
});

test('front matter: chỉ khóa đã biết, một dòng, qua được validateLaw', () => {
  const md = buildLawMarkdown({ so_hieu: '135/2025/QH15', ten: 'Luật Xây dựng\nchèn: x', co_quan: 'Quốc hội', ngay_ban_hanh: '2025-12-10', tinh_trang: 'chua_hieu_luc',
    nguon: 'https://congbao.chinhphu.vn/van-ban/luat-so-135-2025-qh15-468695.htm', ngay_tra: '2026-11-19', buoc: '00', la: 'bỏ', ngay_hieu_luc: '' }, `﻿${VI.repeat(5)}`);
  assert.ok(!md.includes('la: bỏ')); assert.ok(!md.includes('ngay_hieu_luc')); assert.ok(md.includes('ten: Luật Xây dựng chèn: x\n'));
  assert.deepEqual(validateLaw(md).errors, []);
});

// Bộ chuyển giả: kiểm đối số, môi trường (không OCR), đọc JSON dòng cuối, báo lỗi rõ
const fakeSpawn = (out, { code = 0, err = '' } = {}) => {
  const seen = {};
  const impl = (cmd, args, opts) => {
    Object.assign(seen, { cmd, args, opts });
    const p = new EventEmitter(); p.stdout = new EventEmitter(); p.stderr = new EventEmitter(); p.kill = () => {};
    setImmediate(() => { if (err) p.stderr.emit('data', err); p.stdout.emit('data', out); p.emit('close', code); });
    return p;
  };
  return { impl, seen };
};
test('gọi bộ chuyển pipeline.law_convert', async () => {
  const f = fakeSpawn('log\n' + JSON.stringify({ ok: true, text: VI, converter: 'markitdown', pages: null }) + '\n');
  const j = await convertFile(Buffer.from('x'), 'docx', { python: '/py', cwd: '/app', spawnImpl: f.impl });
  assert.equal(j.text, VI); assert.equal(f.seen.cmd, '/py'); assert.deepEqual(f.seen.args.slice(0, 2), ['-m', 'pipeline.law_convert']); assert.equal(f.seen.args[3], 'docx');
  assert.equal(f.seen.opts.env.TESSERACT_CMD, ''); assert.equal(f.seen.opts.cwd, '/app'); assert.ok(!('GOOGLE_REFRESH_TOKEN' in f.seen.opts.env), 'không truyền bí mật của MCP');
  await assert.rejects(convertFile(Buffer.from('x'), 'pdf', { spawnImpl: fakeSpawn(JSON.stringify({ ok: false, error: 'Tệp có 3 trang scan' }), { code: 1 }).impl }), /trang scan/);
  await assert.rejects(convertFile(Buffer.from('x'), 'pdf', { spawnImpl: fakeSpawn('Traceback ...', { code: 1, err: 'ModuleNotFoundError' }).impl }), /không trả JSON/);
});

test('văn bản dẫn chiếu: bỏ chính văn bản, không trùng, ghi một dòng trong front matter và nội dung nạp', async () => {
  const refs = otherRefs('135/2025/QH15', ['135/2025/QH15', '50/2014/QH13', '207/2026/NĐ-CP', '50/2014/QH13']);
  assert.deepEqual(refs, ['50/2014/QH13', '207/2026/NĐ-CP']);
  const md = buildLawMarkdown({ so_hieu: '135/2025/QH15', ten: 'Luật Xây dựng', co_quan: 'Quốc hội', ngay_ban_hanh: '2025-12-10', tinh_trang: 'chua_hieu_luc',
    nguon: 'https://congbao.chinhphu.vn/van-ban/x', ngay_tra: '2026-11-19', dan_chieu: refs }, VI.repeat(5));
  assert.ok(md.includes('\ndan_chieu: 50/2014/QH13, 207/2026/NĐ-CP\n'));
  const { lawKbContent } = await import('../src/law.mjs');
  assert.match(lawKbContent(validateLaw(md).law), /Văn bản dẫn chiếu: 50\/2014\/QH13, 207\/2026\/NĐ-CP/);
});
