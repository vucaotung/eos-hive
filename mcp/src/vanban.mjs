// Dựng văn bản hành chính .docx đúng thể thức Nghị định 30/2020/NĐ-CP (Phụ lục I) cho công văn và quyết định.
// Chạy ở máy chủ MCP: worker Văn thư không có terminal, chỉ gửi JSON thể thức (công cụ eos_draft_document).
// Thông số lấy từ tài liệu https://nd30-guide.vercel.app/ (v1.0, 3/2026) và đối chiếu NĐ30; khác biệt được ghi chú tại chỗ.
// Đây là DỰ THẢO để trình ký: số, ngày, chữ ký do người điền; Văn thư AI không cấp số, không ký (mức L3).
import { z } from 'zod';
import {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, Header,
  WidthType, AlignmentType, BorderStyle, LineRuleType, TableLayoutType, VerticalAlign, Tab,
} from 'docx';

export const DOCX_MIME = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
const FONT = 'Times New Roman';

// ---- Thông số (đơn vị: twip = 1/20 pt; cỡ chữ: nửa điểm) ----
export const SPEC = Object.freeze({
  page: { width: 11906, height: 16838 },                         // A4
  margin: { top: 1134, right: 1134, bottom: 1134, left: 1701 },  // 20 / 20 / 20 / 30 mm (NĐ30: trái 30–35, phải 15–20, trên/dưới 20–25)
  col: { left: 3500, right: 5571 },                              // header 2 cột, tổng 9071 = bề rộng vùng in
  lineExact: 340,                                                // giãn dòng "chính xác 17 pt"
  para: 120,                                                     // 6 pt trước/sau đoạn
  firstLine: 720,                                                // lùi đầu dòng ~1,27 cm
  size: { quocHieu: 26, tieuNgu: 28, coQuan: 26, soKyHieu: 26, diaDanh: 28, trichYeu: 24, body: 28, quyen: 26, chucVu: 28,
          hoTen: 28, noiNhanTieuDe: 24, noiNhan: 22 },
  rule: { coQuanCell: 3500, coQuanLen: 1400, tieuNguCell: 5571, tieuNguLen: 3500 },   // độ dài gạch ngang
});
const NBSP = ' ';

// ---- Lược đồ đầu vào ----
const txt = (max, min = 1) => z.string().trim().min(min).max(max);
// Trường tùy chọn: chuỗi rỗng coi như bỏ trống (worker hay gửi "" khi chưa biết)
const opt = (schema) => z.preprocess((x) => (typeof x === 'string' && x.trim() === '' ? undefined : x), schema.optional());
export const vanBanShape = {
  loai: z.enum(['cong_van', 'quyet_dinh']).describe('cong_van = công văn (không có tên loại); quyet_dinh = quyết định'),
  co_quan_ban_hanh: txt(200).describe('Tên cơ quan/tổ chức ban hành, ví dụ "CÔNG TY TNHH VALNEX"'),
  co_quan_chu_quan: opt(txt(200)).describe('Cơ quan chủ quản (cấp trên trực tiếp); bỏ trống nếu không có'),
  ky_hieu: opt(txt(60)).describe('Phần ký hiệu sau dấu "/", ví dụ "VALNEX-HC". Số thứ tự do người cấp, KHÔNG điền'),
  dia_danh: txt(80).describe('Địa danh ban hành, ví dụ "Hà Nội"'),
  ngay: opt(z.string().regex(/^\d{4}-\d{2}-\d{2}$/)).describe('Ngày ban hành YYYY-MM-DD; bỏ trống để người điền khi ký'),
  trich_yeu: txt(300).describe('Trích yếu. Công văn: "V/v …"; quyết định: "Về việc …"'),
  kinh_gui: z.array(txt(200)).max(20).optional().describe('Công văn: danh sách nơi nhận chính'),
  can_cu: z.array(txt(500)).max(20).optional().describe('Quyết định: các căn cứ pháp lý/đề nghị (không gồm chữ "Căn cứ")'),
  noi_dung: z.union([
    txt(20000),
    z.array(z.object({ tieu_de: txt(200), noi_dung: txt(5000) })).min(1).max(30),
  ]).describe('Công văn: các đoạn cách nhau bằng xuống dòng. Quyết định: chuỗi (dòng "Điều N." tự in đậm) hoặc mảng {tieu_de, noi_dung}'),
  cap_ky: z.enum(['', 'TM', 'KT', 'TL', 'TUQ']).default('').describe('"" = người đứng đầu ký trực tiếp; TM = thay mặt tập thể; KT = cấp phó ký thay; TL = thừa lệnh; TUQ = thừa ủy quyền'),
  chuc_vu_cap_tren: opt(txt(120)).describe('Chức vụ/tập thể đứng sau TM./KT./TL./TUQ., ví dụ "GIÁM ĐỐC" hoặc "HỘI ĐỒNG QUẢN TRỊ"'),
  chuc_vu_ky: txt(120).describe('Chức vụ người ký, ví dụ "PHÓ GIÁM ĐỐC"'),
  nguoi_ky: opt(txt(100)).describe('Họ tên người ký; bỏ trống nếu chưa rõ (dự thảo)'),
  noi_nhan: z.array(txt(200)).max(30).optional().describe('Mỗi dòng bắt đầu bằng "- ". Mặc định: "- Như trên;" và "- Lưu: VT."'),
  du_thao: z.boolean().default(true).describe('true (mặc định) = dự thảo: có dòng "DỰ THẢO" ở đầu trang và chỗ chữ ký'),
};
export const vanBanSchema = z.object(vanBanShape).superRefine((v, ctx) => {
  const add = (message, path) => ctx.addIssue({ code: 'custom', message, path });
  if (v.loai === 'cong_van' && !v.kinh_gui?.length) add('Công văn cần kinh_gui (nơi nhận chính)', ['kinh_gui']);
  if (v.loai === 'quyet_dinh' && !v.can_cu?.length) add('Quyết định cần can_cu (ít nhất một căn cứ)', ['can_cu']);
  if (v.cap_ky && !v.chuc_vu_cap_tren) add(`cap_ky=${v.cap_ky} cần chuc_vu_cap_tren (chức vụ/tập thể đứng sau ${v.cap_ky}.)`, ['chuc_vu_cap_tren']);
  if (v.loai === 'cong_van' && Array.isArray(v.noi_dung)) add('Công văn: noi_dung là chuỗi', ['noi_dung']);
});

// ---- Khối dựng ----
const NONE = { style: BorderStyle.NONE, size: 0, color: 'auto' };
const noBorders = { top: NONE, bottom: NONE, left: NONE, right: NONE };
const run = (text, o = {}) => new TextRun({ text, font: FONT, size: o.size ?? SPEC.size.body, bold: !!o.bold, italics: !!o.italics, color: o.color });
const upper = (s) => s.toLocaleUpperCase('vi-VN');

function para(children, o = {}) {
  return new Paragraph({
    children: Array.isArray(children) ? children : [children],
    alignment: o.align ?? AlignmentType.LEFT,
    keepNext: o.keepNext,
    indent: o.indent,
    spacing: { before: o.before ?? 0, after: o.after ?? 0, line: o.line ?? SPEC.lineExact, lineRule: LineRuleType.EXACT },
    border: o.border,
  });
}
// Gạch ngang = đường viền TRÊN của một đoạn trống (không dùng gạch chân/ảnh/hình): cố định, không lệch khi in
function rule(cellWidth, length) {
  const side = Math.round((cellWidth - length) / 2);
  return new Paragraph({
    children: [new TextRun({ text: '', font: FONT, size: 2 })],
    spacing: { before: 40, after: 0, line: 20, lineRule: LineRuleType.EXACT },
    border: { top: { style: BorderStyle.SINGLE, size: 6, color: '000000', space: 1 } },
    indent: { left: side, right: side },
  });
}
const cell = (width, children, extra = {}) => new TableCell({
  width: { size: width, type: WidthType.DXA }, borders: noBorders, margins: { top: 0, bottom: 0, left: 0, right: 0 },
  verticalAlign: VerticalAlign.TOP, children, ...extra,
});
const table = (cols, rows) => new Table({
  width: { size: cols[0] + cols[1], type: WidthType.DXA }, columnWidths: cols, layout: TableLayoutType.FIXED,
  borders: { ...noBorders, insideHorizontal: NONE, insideVertical: NONE }, rows,
});

function ngayThang(v) {
  if (v.ngay) { const [y, m, d] = v.ngay.split('-').map(Number); return `${v.dia_danh}, ngày ${d} tháng ${m} năm ${y}`; }
  return `${v.dia_danh}, ngày${NBSP.repeat(4)}tháng${NBSP.repeat(4)}năm${NBSP.repeat(4)}`;
}

function headerTable(v) {
  const S = SPEC.size; const C = SPEC.col;
  const left1 = [];
  if (v.co_quan_chu_quan) left1.push(para(run(upper(v.co_quan_chu_quan), { size: S.coQuan }), { align: AlignmentType.CENTER }));
  left1.push(para(run(upper(v.co_quan_ban_hanh), { size: S.coQuan, bold: true }), { align: AlignmentType.CENTER }));
  left1.push(rule(SPEC.rule.coQuanCell, SPEC.rule.coQuanLen));
  const right1 = [
    para(run('CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM', { size: S.quocHieu, bold: true }), { align: AlignmentType.CENTER }),
    para(run('Độc lập - Tự do - Hạnh phúc', { size: S.tieuNgu, bold: true }), { align: AlignmentType.CENTER }),
    rule(SPEC.rule.tieuNguCell, SPEC.rule.tieuNguLen),
  ];
  const so = `Số:${NBSP.repeat(6)}/${upper(v.ky_hieu ?? '')}`;
  const left2 = [para(run(so, { size: S.soKyHieu }), { align: AlignmentType.CENTER, before: 120 })];
  if (v.loai === 'cong_van') left2.push(para(run(v.trich_yeu, { size: S.trichYeu }), { align: AlignmentType.CENTER, before: 60 }));
  const right2 = [para(run(ngayThang(v), { size: S.diaDanh, italics: true }), { align: AlignmentType.CENTER, before: 120 })];
  return table([C.left, C.right], [
    new TableRow({ children: [cell(C.left, left1), cell(C.right, right1)] }),
    new TableRow({ children: [cell(C.left, left2), cell(C.right, right2)] }),
  ]);
}

const body = (text, o = {}) => para(typeof text === 'string' ? run(text, o) : text, {
  align: AlignmentType.JUSTIFIED, before: SPEC.para, after: SPEC.para, indent: { firstLine: SPEC.firstLine }, ...o.p,
});
const lines = (s) => s.split(/\r?\n/).map((x) => x.trim()).filter(Boolean);

function congVanBody(v) {
  const out = [];
  const kg = v.kinh_gui;
  if (kg.length === 1) out.push(para([run('Kính gửi: '), run(kg[0])], { align: AlignmentType.CENTER, before: 240, after: 120 }));
  else {
    // "Kính gửi:" rồi tab tới mép chung; các dòng sau thụt cùng mép để thẳng hàng
    const edge = 1500;
    kg.forEach((k, i) => out.push(para(
      [...(i === 0 ? [run('Kính gửi:')] : []),
       new TextRun({ children: i === 0 ? [new Tab(), `- ${k.replace(/^-\s*/, '')}${i === kg.length - 1 ? '.' : ';'}`] : [`- ${k.replace(/^-\s*/, '')}${i === kg.length - 1 ? '.' : ';'}`],
                     font: FONT, size: SPEC.size.body })],
      { before: i === 0 ? 240 : 0, indent: i === 0 ? { left: edge, hanging: edge } : { left: edge } })));
    out.push(para(run(''), { after: 60 }));
  }
  for (const l of lines(v.noi_dung)) out.push(body(l));
  return out;
}

function quyetDinhBody(v) {
  const out = [];
  out.push(para(run('QUYẾT ĐỊNH', { bold: true }), { align: AlignmentType.CENTER, before: 240, keepNext: true }));
  out.push(para(run(v.trich_yeu, { bold: true }), { align: AlignmentType.CENTER, keepNext: true }));
  out.push(rule(SPEC.col.right + SPEC.col.left, 2400));
  out.push(para(run(''), { after: 60 }));
  v.can_cu.forEach((c, i) => {
    const clean = c.replace(/^Căn cứ\s+/i, '').replace(/[;.]\s*$/, '');
    out.push(body([run(`Căn cứ ${clean}${i === v.can_cu.length - 1 ? '.' : ';'}`, { italics: true })], {}));
  });
  out.push(para(run('QUYẾT ĐỊNH:', { bold: true }), { align: AlignmentType.CENTER, before: 120, after: 60, keepNext: true }));
  if (Array.isArray(v.noi_dung)) {
    v.noi_dung.forEach((d, i) => {
      out.push(body([run(`Điều ${i + 1}. ${d.tieu_de}.`, { bold: true })], {}));
      for (const l of lines(d.noi_dung)) out.push(body(l));
    });
  } else {
    for (const l of lines(v.noi_dung)) {
      const m = l.match(/^(Điều\s+\d+\.)\s*(.*)$/i);
      if (m) {
        const colon = m[2].indexOf(':');
        const head = colon >= 0 ? `${m[1]} ${m[2].slice(0, colon + 1)}` : m[1];
        const rest = colon >= 0 ? m[2].slice(colon + 1) : ` ${m[2]}`;
        out.push(body([run(head, { bold: true }), run(rest)], {}));
      } else out.push(body(l));
    }
  }
  return out;
}

function signAndRecipients(v) {
  const S = SPEC.size;
  const defaults = v.loai === 'cong_van' ? ['- Như trên;', '- Lưu: VT.'] : ['- Như Điều 3;', '- Lưu: VT.'];
  const recips = v.noi_nhan?.length ? v.noi_nhan : defaults;
  const left = [para(run('Nơi nhận:', { size: S.noiNhanTieuDe, bold: true, italics: true }))];
  for (const r of recips) left.push(para(run(r.startsWith('-') ? r : `- ${r}`, { size: S.noiNhan })));

  const right = [];
  if (v.cap_ky) {
    right.push(para(run(`${v.cap_ky}. ${upper(v.chuc_vu_cap_tren)}`, { size: S.quyen, bold: true }), { align: AlignmentType.CENTER, keepNext: true }));
  }
  right.push(para(run(upper(v.chuc_vu_ky), { size: S.chucVu, bold: true }), { align: AlignmentType.CENTER, keepNext: true }));
  // chỗ ký và đóng dấu: 3 dòng trống; dự thảo ghi rõ để người ký không bỏ sót
  right.push(para(run(v.du_thao ? '(Ký, ghi rõ họ tên)' : '', { size: S.body, italics: true }), { align: AlignmentType.CENTER, keepNext: true }));
  right.push(para(run(''), { keepNext: true }), para(run(''), { keepNext: true }));
  right.push(para(run(v.nguoi_ky ?? '', { size: S.hoTen, bold: true }), { align: AlignmentType.CENTER }));
  return table([5000, 4071], [new TableRow({ cantSplit: true, children: [cell(5000, left), cell(4071, right)] })]);
}

export async function renderVanBan(input) {
  const v = vanBanSchema.parse(input);
  const children = [
    headerTable(v),
    ...(v.loai === 'cong_van' ? congVanBody(v) : quyetDinhBody(v)),
    para(run(''), { before: 120 }),
    signAndRecipients(v),
  ];
  const doc = new Document({
    creator: 'Văn thư AI - Enterprise OS', title: v.trich_yeu, description: v.du_thao ? 'Dự thảo, chưa cấp số, chưa ký' : 'Văn bản',
    styles: { default: { document: { run: { font: FONT, size: SPEC.size.body } } } },
    sections: [{
      properties: { page: { size: { width: SPEC.page.width, height: SPEC.page.height }, margin: { ...SPEC.margin, header: 567, footer: 567 } } },
      headers: v.du_thao ? { default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT,
        children: [new TextRun({ text: 'DỰ THẢO — chưa cấp số, chưa ký, chưa ban hành', font: FONT, size: 18, italics: true, color: '888888' })] })] }) } : undefined,
      children,
    }],
  });
  const buffer = await Packer.toBuffer(doc);
  const kind = v.loai === 'cong_van' ? 'Cong van' : 'Quyet dinh';
  const slug = v.trich_yeu.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/gi, 'd')
    .replace(/^(v\/v|ve viec)\s*/i, '').replace(/[^A-Za-z0-9]+/g, ' ').trim().slice(0, 60).trim();
  return { buffer, filename: `${v.du_thao ? 'Du thao - ' : ''}${kind}${slug ? ' - ' + slug : ''}.docx`, spec: v };
}
