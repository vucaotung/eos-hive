// Dựng HTML an toàn: mọi giá trị chèn vào mẫu đều bị thoát ký tự, trừ khi bọc bằng raw() có chủ ý.
class Raw { constructor(s) { this.s = s; } toString() { return this.s; } }
export const raw = (s) => new Raw(String(s));
export const esc = (v) => String(v ?? '').replace(/[&<>"'`]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;', '`': '&#96;' }[c]));
const part = (v) => (v instanceof Raw ? v.s : Array.isArray(v) ? v.map(part).join('') : v === false || v == null ? '' : esc(v));
export const html = (strings, ...vals) => new Raw(strings.reduce((out, s, i) => out + s + (i < vals.length ? part(vals[i]) : ''), ''));
export const join = (items, sep = '') => new Raw(items.map(part).join(sep));

const TZ = 'Asia/Ho_Chi_Minh';
const dt = new Intl.DateTimeFormat('vi-VN', { timeZone: TZ, dateStyle: 'short', timeStyle: 'short' });
const dd = new Intl.DateTimeFormat('vi-VN', { timeZone: TZ, dateStyle: 'medium' });
export const fmtDT = (v) => (v ? dt.format(new Date(v)) : '—');
export const fmtD = (v) => (v ? dd.format(new Date(String(v).length === 10 ? `${v}T12:00:00Z` : v)) : '—');
export const ago = (v) => {
  if (!v) return '—';
  const s = Math.max(0, Math.round((Date.now() - new Date(v).getTime()) / 1000));
  if (s < 90) return `${s} giây trước`; if (s < 5400) return `${Math.round(s / 60)} phút trước`;
  if (s < 129600) return `${Math.round(s / 3600)} giờ trước`; return `${Math.round(s / 86400)} ngày trước`;
};

export const STATUS = { todo: ['Chờ làm', 'muted'], in_progress: ['Đang làm', 'info'], blocked: ['Vướng', 'warn'], in_review: ['Chờ xem', 'accent'], done: ['Xong', 'ok'], cancelled: ['Đã hủy', 'muted'] };
export const PRIORITY = { low: 'Thấp', medium: 'Vừa', high: 'Cao', urgent: 'Khẩn' };
export const CONFIDENCE = { cao: ['Cao', 'ok'], trung_binh: ['Trung bình', 'warn'], thap: ['Thấp', 'bad'] };
export const VERDICT = { pending: 'Chờ duyệt', accepted: 'Đã chấp nhận', rework: 'Đã trả lại', auto_done: 'Tự đóng' };
export const COMMENT_KIND = { note: 'ghi chú', question: 'câu hỏi', answer: 'trả lời', reject: 'trả lại', submit: 'nộp kết quả', result: 'kết quả', claim: 'nhận việc', error: 'lỗi', approve: 'duyệt' };
export const badge = (label, cls) => html`<span class="badge b-${cls}">${label}</span>`;
export const statusBadge = (s) => { const [l, c] = STATUS[s] || [s, 'muted']; return badge(l, c); };

// Chỉ cho phép liên kết https tới Google Drive/Docs (dữ liệu từ agent không đáng tin)
export const safeLink = (url, text) => (/^https:\/\/(drive|docs)\.google\.com\//.test(url || '')
  ? html`<a href="${url}" target="_blank" rel="noopener noreferrer">${text}</a>` : html`<span>${text}</span>`);

export const actorLabel = (actor, meId) => {
  const a = String(actor || '');
  if (a.startsWith('agent:')) return html`<span class="who agent">🤖 ${a.slice(6)}</span>`;
  if (a.startsWith('user:')) return a.slice(5, 41) === meId ? html`<span class="who me">Bạn</span>` : html`<span class="who">Người dùng</span>`;
  return html`<span class="who">${a || 'hệ thống'}</span>`;
};
