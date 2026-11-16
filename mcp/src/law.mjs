// Văn bản pháp luật: đọc/kiểm front matter, kiểm nguồn chính thống, đặt tên tệp, dựng nội dung nạp WeKnora. Thuần hàm, không gọi mạng.
import { createHash } from 'node:crypto';

export const LAW_STATUS = ['con_hieu_luc', 'het_mot_phan', 'het_hieu_luc', 'chua_hieu_luc'];
export const LAW_REQUIRED = ['so_hieu', 'ten', 'co_quan', 'ngay_ban_hanh', 'tinh_trang', 'nguon', 'ngay_tra'];
export const LAW_MAX_BYTES = 5 * 1024 * 1024;
export const DEFAULT_LAW_DOMAINS = ['vbpl.vn', 'congbao.chinhphu.vn', 'vanban.chinhphu.vn', 'chinhphu.vn', 'dichvucong.gov.vn', '*.gov.vn'];

export const md5 = (s) => createHash('md5').update(s).digest('hex');
export const sha256 = (b) => createHash('sha256').update(b).digest('hex');

export const lawDomains = () => {
  const env = (process.env.LAW_SOURCE_DOMAINS || '').split(',').map((d) => d.trim().toLowerCase()).filter(Boolean);
  return env.length ? env : DEFAULT_LAW_DOMAINS;
};

// Nguồn phải là https, không kèm tài khoản/cổng lạ, tên miền khớp danh sách: "a.vn" khớp đúng a.vn (và www.a.vn); "*.gov.vn" khớp mọi tên miền con của gov.vn (không khớp gov.vn trần).
export function sourceAllowed(url, domains = lawDomains()) {
  let u;
  try { u = new URL(String(url)); } catch { return { ok: false, reason: 'nguon không phải URL hợp lệ' }; }
  if (u.protocol !== 'https:') return { ok: false, reason: 'nguon phải là https' };
  if (u.username || u.password) return { ok: false, reason: 'nguon không được chứa tài khoản' };
  if (u.port && u.port !== '443') return { ok: false, reason: 'nguon không dùng cổng khác 443' };
  const host = u.hostname.toLowerCase().replace(/\.$/, '').replace(/^www\./, '');
  for (const d of domains) {
    if (d.startsWith('*.')) { const suf = d.slice(1); if (host.endsWith(suf) && host.length > suf.length) return { ok: true, host }; }
    else if (host === d.replace(/^www\./, '')) return { ok: true, host };
  }
  return { ok: false, host, reason: `Nguồn "${host}" không thuộc danh sách nguồn chính thống (${domains.join(', ')}). Tìm bản nguyên văn trên vbpl.vn, Công báo hoặc cổng của Chính phủ/bộ/UBND rồi ghi nguon bằng đường dẫn đó; không dùng trang tổng hợp/thư viện pháp luật tư nhân làm nguồn.` };
}

// Tách front matter dạng "khóa: giá trị" (một dòng một khóa). Trả {fm, body, ok}
export function parseFrontMatter(text) {
  const t = String(text).replace(/^﻿/, '').replace(/\r\n/g, '\n');
  if (!t.startsWith('---\n')) return { ok: false, fm: {}, body: t };
  const e = t.indexOf('\n---', 4);
  if (e === -1) return { ok: false, fm: {}, body: t };
  const fm = {};
  for (const l of t.slice(4, e).split('\n')) {
    const i = l.indexOf(':'); if (i <= 0) continue;
    fm[l.slice(0, i).trim()] = l.slice(i + 1).trim().replace(/^"(.*)"$/, '$1').replace(/^'(.*)'$/, '$1');
  }
  return { ok: true, fm, body: t.slice(e + 4).replace(/^\n+/, '') };
}

const isDate = (s) => /^\d{4}-\d{2}-\d{2}$/.test(s || '') && new Date(`${s}T00:00:00Z`).toISOString().slice(0, 10) === s;
const today = () => new Date(Date.now() + 7 * 3600_000).toISOString().slice(0, 10);   // giờ Việt Nam

// Mã bước từ "06, 09" hoặc "[06, 09]"; mỗi mã 00–20
export function parseBuoc(v) {
  const parts = String(v || '').replace(/[\[\]"']/g, '').split(/[,\s;]+/).filter(Boolean);
  const bad = parts.filter((x) => !/^(0[0-9]|1[0-9]|20)$/.test(x));
  return { list: [...new Set(parts.filter((x) => /^(0[0-9]|1[0-9]|20)$/.test(x)))], bad };
}

// Kiểm toàn bộ: trả {errors[], law} (law đã chuẩn hóa). Mọi lỗi được gom để agent sửa một lượt.
export function validateLaw(text, { domains } = {}) {
  const errors = [];
  if (Buffer.byteLength(text, 'utf8') > LAW_MAX_BYTES) errors.push(`Tệp quá ${LAW_MAX_BYTES / 1048576} MB`);
  const { ok, fm, body } = parseFrontMatter(text);
  if (!ok) return { errors: ['Thiếu front matter (--- … ---) ở đầu tệp'], law: null };
  for (const k of LAW_REQUIRED) if (!String(fm[k] || '').trim()) errors.push(`Front matter thiếu "${k}"`);
  const so = String(fm.so_hieu || '').trim();
  if (so && (so.length < 2 || so.length > 120 || /[\n\r]/.test(so))) errors.push('so_hieu phải dài 2–120 ký tự');
  if (fm.ten && (fm.ten.length < 3 || fm.ten.length > 500)) errors.push('ten phải dài 3–500 ký tự');
  for (const k of ['ngay_ban_hanh', 'ngay_tra', 'ngay_hieu_luc']) if (fm[k] && !isDate(fm[k])) errors.push(`${k} phải là YYYY-MM-DD hợp lệ`);
  if (isDate(fm.ngay_tra) && fm.ngay_tra > today()) errors.push('ngay_tra không được ở tương lai');
  if (fm.tinh_trang && !LAW_STATUS.includes(fm.tinh_trang)) errors.push(`tinh_trang phải là một trong: ${LAW_STATUS.join(', ')}`);
  if (fm.nguon) { const s = sourceAllowed(fm.nguon, domains); if (!s.ok) errors.push(s.reason); }
  const b = parseBuoc(fm.buoc); if (b.bad.length) errors.push(`buoc có mã không hợp lệ (${b.bad.join(', ')}); dùng 00–20`);
  if (body.trim().length < 100) errors.push('Nội dung văn bản quá ngắn (cần nguyên văn, giữ chương/điều/khoản/điểm)');
  if (errors.length) return { errors, law: null };
  return { errors, law: {
    so_hieu: so, ten: fm.ten.trim(), loai: fm.loai || '', co_quan: fm.co_quan.trim(), ngay_ban_hanh: fm.ngay_ban_hanh, ngay_hieu_luc: fm.ngay_hieu_luc || '', tinh_trang: fm.tinh_trang,
    thay_the: fm.thay_the || '', sua_doi: fm.sua_doi || '', linh_vuc: fm.linh_vuc || '', buoc: b.list, nguon: fm.nguon.trim(), ngay_tra: fm.ngay_tra, body,
  } };
}

// Tên tệp = số hiệu không dấu: "123/2024/NĐ-CP" → "123-2024-ND-CP.md"
export function lawFilename(soHieu) {
  const base = String(soHieu).normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/g, 'd').replace(/Đ/g, 'D')
    .replace(/[^A-Za-z0-9._-]+/g, '-').replace(/-+/g, '-').replace(/^[-.]+|[-.]+$/g, '').slice(0, 120);
  return `${base || 'van-ban'}.md`;
}

// Nội dung nạp WeKnora: đầu trang ghi đủ thông tin nhận diện (để tìm kiếm và Wiki nhận chủ thể), rồi nguyên văn
export function lawKbContent(l) {
  const head = [`Số hiệu: ${l.so_hieu}`, `Tên: ${l.ten}`, l.loai && `Loại: ${l.loai}`, `Cơ quan ban hành: ${l.co_quan}`, `Ngày ban hành: ${l.ngay_ban_hanh}`,
    l.ngay_hieu_luc && `Ngày hiệu lực: ${l.ngay_hieu_luc}`, `Tình trạng: ${l.tinh_trang}`, l.thay_the && `Văn bản thay thế: ${l.thay_the}`, l.sua_doi && `Sửa đổi, bổ sung bởi: ${l.sua_doi}`,
    l.linh_vuc && `Lĩnh vực: ${l.linh_vuc}`, `Nguồn: ${l.nguon} (tra ngày ${l.ngay_tra})`].filter(Boolean).join('\n');
  return `${head}\n\n${l.body}`;
}

// custom_metadata (WeKnora ghi đè cả object nên luôn gửi đủ các khóa)
export function lawMetadata(l) {
  return { so_hieu: l.so_hieu, tinh_trang: l.tinh_trang, nguon: l.nguon, buoc: Array.isArray(l.buoc) ? l.buoc.join(',') : (l.buoc || ''), linh_vuc: l.linh_vuc || '', thay_the: l.thay_the || '', drive_link: l.drive_link || '' };
}
