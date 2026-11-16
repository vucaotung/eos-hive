// Kiểm tra văn bản pháp luật ở máy chủ MCP (thuần hàm): nguồn chính thống, front matter, tên tệp, nội dung nạp, metadata.
import test from 'node:test';
import assert from 'node:assert/strict';
import { sourceAllowed, validateLaw, lawFilename, lawKbContent, lawMetadata, parseBuoc, parseFrontMatter, lawDomains, DEFAULT_LAW_DOMAINS } from '../src/law.mjs';

const body = 'Điều 1. Phạm vi điều chỉnh. Nghị định này quy định chi tiết một số điều của Luật. '.repeat(3);
const mk = (o = {}, drop = []) => {
  const fm = { so_hieu: '123/2024/NĐ-CP', ten: 'Nghị định mẫu', co_quan: 'Chính phủ', ngay_ban_hanh: '2024-01-02', tinh_trang: 'con_hieu_luc', nguon: 'https://vbpl.vn/x', ngay_tra: '2026-11-01', buoc: '[06, 09]', ...o };
  for (const k of drop) delete fm[k];
  return `---\n${Object.entries(fm).map(([k, v]) => `${k}: ${v}`).join('\n')}\n---\n\n${body}`;
};

test('nguồn chính thống: danh sách mặc định', () => {
  for (const u of ['https://vbpl.vn/a', 'https://www.vbpl.vn/a', 'https://congbao.chinhphu.vn/x', 'https://vanban.chinhphu.vn/x', 'https://chinhphu.vn/x', 'https://dichvucong.gov.vn/x', 'https://mt.gov.vn/x', 'https://sxd.hanoi.gov.vn/x'])
    assert.equal(sourceAllowed(u).ok, true, u);
});
test('nguồn không chính thống hoặc giả mạo bị từ chối', () => {
  for (const u of ['http://vbpl.vn/a', 'https://vbpl.vn.evil.example/a', 'https://evilvbpl.vn/a', 'https://luatvietnam.vn/a', 'https://thuvienphapluat.vn/a', 'https://gov.vn/a', 'https://x.gov.vn.evil.com/a',
                   'https://user:pw@vbpl.vn/a', 'https://vbpl.vn:8443/a', 'ftp://vbpl.vn/a', 'không phải url', ''])
    assert.equal(sourceAllowed(u).ok, false, u);
  assert.match(sourceAllowed('https://luatvietnam.vn/a').reason, /nguồn chính thống/);
});
test('LAW_SOURCE_DOMAINS ghi đè danh sách', () => {
  const old = process.env.LAW_SOURCE_DOMAINS;
  process.env.LAW_SOURCE_DOMAINS = 'phapluat.example.org, *.nhanuoc.vn';
  assert.deepEqual(lawDomains(), ['phapluat.example.org', '*.nhanuoc.vn']);
  assert.equal(sourceAllowed('https://phapluat.example.org/a').ok, true); assert.equal(sourceAllowed('https://vbpl.vn/a').ok, false); assert.equal(sourceAllowed('https://a.nhanuoc.vn/x').ok, true);
  process.env.LAW_SOURCE_DOMAINS = ''; assert.deepEqual(lawDomains(), DEFAULT_LAW_DOMAINS);
  if (old === undefined) delete process.env.LAW_SOURCE_DOMAINS; else process.env.LAW_SOURCE_DOMAINS = old;
});
test('front matter hợp lệ được chuẩn hóa', () => {
  const v = validateLaw(mk({ ngay_hieu_luc: '2024-03-01', linh_vuc: 'xây dựng', thay_the: '', loai: 'nghị định' }));
  assert.deepEqual(v.errors, []); assert.equal(v.law.so_hieu, '123/2024/NĐ-CP'); assert.deepEqual(v.law.buoc, ['06', '09']); assert.equal(v.law.linh_vuc, 'xây dựng'); assert.ok(v.law.body.startsWith('Điều 1.'));
});
test('thiếu trường bắt buộc: gom đủ lỗi trong một lượt', () => {
  const v = validateLaw(mk({}, ['so_hieu', 'co_quan', 'nguon']));
  assert.equal(v.law, null); for (const k of ['so_hieu', 'co_quan', 'nguon']) assert.ok(v.errors.some((e) => e.includes(`"${k}"`)), k);
});
test('ngày, tình trạng, mã bước, nội dung ngắn, không front matter', () => {
  assert.ok(validateLaw(mk({ ngay_ban_hanh: '2024-02-30' })).errors.some((e) => /ngay_ban_hanh/.test(e)));
  assert.ok(validateLaw(mk({ ngay_tra: '2099-01-01' })).errors.some((e) => /tương lai/.test(e)));
  assert.ok(validateLaw(mk({ tinh_trang: 'het_han' })).errors.some((e) => /tinh_trang/.test(e)));
  assert.ok(validateLaw(mk({ buoc: '06, 21' })).errors.some((e) => /buoc/.test(e)));
  assert.ok(validateLaw(mk({ nguon: 'https://luatvietnam.vn/x' })).errors.some((e) => /chính thống/.test(e)));
  assert.ok(validateLaw('---\nso_hieu: 1/2024\n---\n\nngắn').errors.length >= 3);
  assert.deepEqual(validateLaw('không có front matter\n' + body).errors, ['Thiếu front matter (--- … ---) ở đầu tệp']);
  assert.ok(validateLaw('x'.repeat(5 * 1024 * 1024 + 10)).errors.length);
});
test('tên tệp = số hiệu không dấu', () => {
  assert.equal(lawFilename('123/2024/NĐ-CP'), '123-2024-ND-CP.md');
  assert.equal(lawFilename('Luật số 50/2014/QH13'), 'Luat-so-50-2014-QH13.md');
  assert.equal(lawFilename('TCVN 5574:2018'), 'TCVN-5574-2018.md');
  assert.equal(lawFilename('../../etc/passwd'), 'etc-passwd.md'); assert.equal(lawFilename('///'), 'van-ban.md');
  assert.match(lawFilename('Đ'.repeat(300)), /^D{1,120}\.md$/);
});
test('mã bước, front matter, nội dung nạp, metadata', () => {
  assert.deepEqual(parseBuoc('[06, 09, 06]'), { list: ['06', '09'], bad: [] }); assert.deepEqual(parseBuoc('7, 20').bad, ['7']); assert.deepEqual(parseBuoc('').list, []);
  assert.equal(parseFrontMatter('---\na: "b"\nc: d: e\n---\nx').fm.c, 'd: e');
  const L = validateLaw(mk({ thay_the: '99/2025/NĐ-CP' })).law;
  const c = lawKbContent(L); assert.match(c, /^Số hiệu: 123\/2024\/NĐ-CP\nTên: Nghị định mẫu\n/); assert.match(c, /Văn bản thay thế: 99\/2025\/NĐ-CP/); assert.match(c, /Nguồn: https:\/\/vbpl\.vn\/x \(tra ngày 2026-11-01\)/);
  assert.deepEqual(lawMetadata(L), { so_hieu: '123/2024/NĐ-CP', tinh_trang: 'con_hieu_luc', nguon: 'https://vbpl.vn/x', buoc: '06,09', linh_vuc: '', thay_the: '99/2025/NĐ-CP', drive_link: '' });
});
