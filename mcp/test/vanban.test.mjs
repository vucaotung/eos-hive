// Kiểm tra thể thức văn bản sinh ra: đọc XML của .docx và đối chiếu thông số NĐ30 (https://nd30-guide.vercel.app/, docs/09).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import JSZip from 'jszip';
import { renderVanBan, vanBanSchema, SPEC, DOCX_MIME } from '../src/vanban.mjs';

const base = { co_quan_ban_hanh: 'Công ty TNHH Valnex', ky_hieu: 'valnex-hc', dia_danh: 'Hà Nội', cap_ky: '', chuc_vu_ky: 'Giám đốc' };
const cv = { ...base, loai: 'cong_van', trich_yeu: 'V/v đề nghị phối hợp', kinh_gui: ['Công ty ABC'], noi_dung: 'Đoạn một.\nĐoạn hai.' };
const qd = { ...base, loai: 'quyet_dinh', trich_yeu: 'Về việc thành lập Tổ công tác', can_cu: ['Điều lệ Công ty'],
             noi_dung: 'Điều 1. Thành lập: Tổ công tác gồm ba người.\nĐiều 2. Quyết định này có hiệu lực kể từ ngày ký.' };
const xml = async (spec, part = 'word/document.xml') => {
  const { buffer } = await renderVanBan(spec);
  const z = await JSZip.loadAsync(buffer);
  return z.file(part) ? z.file(part).async('string') : null;
};
const text = (x) => [...x.matchAll(/<w:t[^>]*>([^<]*)<\/w:t>/g)].map((m) => m[1]).join('|');

test('khổ giấy A4 và lề 30/20/20/20 mm', async () => {
  const x = await xml(cv);
  assert.match(x, /<w:pgSz [^>]*w:w="11906"[^>]*w:h="16838"/);
  assert.match(x, /<w:pgMar [^>]*w:top="1134"[^>]*w:right="1134"[^>]*w:bottom="1134"[^>]*w:left="1701"/);
  assert.equal(SPEC.col.left + SPEC.col.right, SPEC.page.width - SPEC.margin.left - SPEC.margin.right, 'header phủ đúng vùng in');
});

test('header là bảng 2 cột ẩn viền 3500:5571, không dùng tab/khoảng trắng để căn', async () => {
  const x = await xml(cv);
  const tbl = x.slice(x.indexOf('<w:tbl>'), x.indexOf('</w:tbl>'));
  assert.match(tbl, /<w:gridCol w:w="3500"\/><w:gridCol w:w="5571"\/>/);
  assert.equal((tbl.match(/<w:tr[ >]/g) || []).length, 2, '2 dòng');
  assert.doesNotMatch(tbl, /<w:tab\/>/, 'không tab trong header');
  assert.doesNotMatch(tbl, /w:val="single"[^>]*\/><w:left/, 'bảng ẩn viền');
});

test('chỉ dùng Times New Roman; không gạch chân, không ảnh', async () => {
  const x = await xml(qd);
  const fonts = new Set([...x.matchAll(/w:ascii="([^"]+)"/g)].map((m) => m[1]));
  assert.deepEqual([...fonts], ['Times New Roman']);
  assert.doesNotMatch(x, /<w:u /, 'không UnderlineType');
  assert.doesNotMatch(x, /<w:drawing|<v:line|<w:pict/, 'không ảnh/hình để gạch');
  assert.ok((x.match(/<w:pBdr><w:top /g) || []).length >= 2, 'gạch ngang bằng Border Top');
});

test('quốc hiệu đậm cỡ 13, tiêu ngữ đậm cỡ 14, tên cơ quan ban hành đậm cỡ 13', async () => {
  const x = await xml(cv);
  const runOf = (label) => { const i = x.indexOf(label); return x.slice(x.lastIndexOf('<w:r>', i), i); };
  assert.match(runOf('CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM'), /<w:b\/>.*<w:sz w:val="26"\/>|<w:sz w:val="26"\/>.*<w:b\/>/s);
  assert.match(runOf('Độc lập - Tự do - Hạnh phúc'), /<w:sz w:val="28"\/>/);
  assert.match(runOf('CÔNG TY TNHH VALNEX'), /<w:sz w:val="26"\/>/);
});

test('nội dung giãn dòng chính xác 17 pt, 6 pt trước/sau, căn đều, lùi đầu dòng', async () => {
  const x = await xml(cv);
  const i = x.indexOf('Đoạn một.');
  const p = x.slice(x.lastIndexOf('<w:p>', i), i);
  assert.match(p, /w:line="340"/); assert.match(p, /w:lineRule="exact"/);
  assert.match(p, /w:before="120"/); assert.match(p, /w:after="120"/);
  assert.match(p, /<w:jc w:val="both"\/>/); assert.match(p, /w:firstLine="720"/);
});

test('số ký hiệu để trống số (người cấp), ngày để trống khi chưa ký', async () => {
  const t = text(await xml(cv));
  assert.match(t, /Số:[\s ]+\/VALNEX-HC/);
  assert.doesNotMatch(t, /Số:\s*\d/);
  assert.match(t, /Hà Nội, ngày[\s ]+tháng[\s ]+năm/);
  assert.match(text(await xml({ ...cv, ngay: '2026-10-20' })), /Hà Nội, ngày 20 tháng 10 năm 2026/);
});

test('khối chữ ký: không tiền tố khi người đứng đầu ký; KT./TL./TUQ./TM. đúng dạng', async () => {
  assert.doesNotMatch(text(await xml(cv)), /(TM|KT|TL|TUQ)\./);
  for (const [cap, cap_tren, ky] of [['KT', 'Giám đốc', 'Phó giám đốc'], ['TL', 'Giám đốc', 'Trưởng phòng hành chính'],
                                       ['TUQ', 'Giám đốc', 'Phó trưởng phòng'], ['TM', 'Hội đồng thành viên', 'Chủ tịch']]) {
    const t = text(await xml({ ...cv, cap_ky: cap, chuc_vu_cap_tren: cap_tren, chuc_vu_ky: ky }));
    assert.ok(t.includes(`${cap}. ${cap_tren.toLocaleUpperCase('vi-VN')}|${ky.toLocaleUpperCase('vi-VN')}`), `${cap}: ${t.slice(-160)}`);
  }
});

test('công văn không có tên loại, có "Kính gửi"; quyết định có QUYẾT ĐỊNH, Căn cứ, Điều', async () => {
  const a = text(await xml(cv)); const b = text(await xml(qd));
  assert.match(a, /Kính gửi/); assert.doesNotMatch(a, /QUYẾT ĐỊNH|CÔNG VĂN/);
  assert.match(b, /QUYẾT ĐỊNH\|/); assert.match(b, /Căn cứ Điều lệ Công ty\./); assert.match(b, /QUYẾT ĐỊNH:/); assert.doesNotMatch(b, /Kính gửi/);
  const x = await xml(qd);
  const i = x.indexOf('Điều 1. Thành lập:');
  assert.match(x.slice(x.lastIndexOf('<w:r>', i), i), /<w:b\/>/, 'tiêu đề Điều in đậm');
});

test('dự thảo có dòng DỰ THẢO ở đầu trang; bản chính thức thì không', async () => {
  const h = await xml(cv, 'word/header1.xml');
  assert.ok(h && /DỰ THẢO/.test(text(h)));
  assert.equal(await xml({ ...cv, du_thao: false }, 'word/header1.xml'), null);
  assert.match(text(await xml(cv)), /\(Ký, ghi rõ họ tên\)/);
  assert.doesNotMatch(text(await xml({ ...cv, du_thao: false })), /Ký, ghi rõ họ tên/);
});

test('lược đồ từ chối đầu vào thiếu/sai; chuỗi rỗng ở trường tùy chọn được chấp nhận', () => {
  assert.throws(() => vanBanSchema.parse({ ...cv, kinh_gui: undefined }), /kinh_gui/);
  assert.throws(() => vanBanSchema.parse({ ...qd, can_cu: undefined }), /can_cu/);
  assert.throws(() => vanBanSchema.parse({ ...cv, cap_ky: 'KT' }), /chuc_vu_cap_tren/);
  assert.throws(() => vanBanSchema.parse({ ...cv, loai: 'to_trinh' }));
  assert.throws(() => vanBanSchema.parse({ ...cv, ngay: '20/10/2026' }));
  assert.doesNotThrow(() => vanBanSchema.parse({ ...cv, nguoi_ky: '', ngay: '', co_quan_chu_quan: '', chuc_vu_cap_tren: '' }));
});

test('tên tệp an toàn, không dấu, có tiền tố Dự thảo; MIME docx', async () => {
  const r = await renderVanBan({ ...cv, trich_yeu: 'V/v đề nghị: phối hợp/cung cấp "hồ sơ"' });
  assert.match(r.filename, /^Du thao - Cong van - [A-Za-z0-9 ]+\.docx$/);
  assert.equal(DOCX_MIME, 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
  assert.ok(r.buffer.length > 5000 && r.buffer.slice(0, 2).toString() === 'PK');
});

test('ví dụ trong skill nd30-van-thu hợp lệ với công cụ và dựng được', async () => {
  const dir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../deploy/hermes-skills/nd30-van-thu/references');
  const files = fs.readdirSync(dir).filter((f) => /^vi_du_.*\.json$/.test(f));
  assert.ok(files.length >= 2, 'có ví dụ công văn và quyết định');
  for (const f of files) {
    const spec = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    const r = await renderVanBan(spec);
    assert.ok(r.buffer.length > 5000, f);
    assert.equal(spec.du_thao, true, `${f}: ví dụ phải là dự thảo`);
    assert.ok(!spec.ngay, `${f}: ví dụ không điền ngày`);
  }
  const skill = fs.readFileSync(path.join(dir, '../SKILL.md'), 'utf8');
  assert.match(skill, /^---\nname: nd30-van-thu\n/);
  for (const must of ['Không cấp số', 'eos_draft_document', 'kanban_block', 'cao`, `trung_binh`, `thap']) assert.ok(skill.includes(must), `SKILL.md thiếu: ${must}`);
});
