export const STATUS = {
  todo: "Chờ làm", in_progress: "Đang làm", blocked: "Vướng", in_review: "Chờ duyệt", done: "Xong", cancelled: "Đã hủy",
};
export const STATUS_COLOR = {
  todo: "text-muted", in_progress: "text-accent", blocked: "text-warning", in_review: "text-danger", done: "text-success", cancelled: "text-muted",
};
export const PRIORITY = { urgent: "Gấp", high: "Cao", medium: "Thường", low: "Thấp" };
export const PRIORITY_ORDER = { urgent: 0, high: 1, medium: 2, low: 3 };
export const ROLE = { owner: "Chủ sở hữu", admin: "Quản trị", manager: "Trưởng phòng", member: "Thành viên" };
// Tên hiển thị của agent theo mã (danh sách thật lấy từ me.agents; bảng này chỉ để dịch mã cũ trong nhật ký)
export const AGENT_ROLES = {
  "dieu-phoi": "Điều phối", "van-thu": "Văn thư", "nhan-su": "Nhân sự", "quan-tri-du-lieu": "Quản trị dữ liệu", "phap-che": "Pháp chế",
};
export const KIND = {
  note: "Ghi chú", question: "Agent hỏi", answer: "Trả lời", result: "Kết quả", submit: "Nộp kết quả",
  approve: "Đã duyệt", reject: "Trả lại", claim: "Nhận việc", error: "Lỗi", system: "Hệ thống",
};
export const DRIVE = { none: "Chưa khai báo", pending: "Đã lưu, chưa kiểm tra", ok: "Đã kết nối", error: "Cần sửa" };

const WD = ["Chủ nhật", "Thứ hai", "Thứ ba", "Thứ tư", "Thứ năm", "Thứ sáu", "Thứ bảy"];
export const today = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; };
export const parseDate = (s) => { if (!s) return null; const [y, m, d] = s.slice(0, 10).split("-").map(Number); return new Date(y, m - 1, d); };
export const ddmm = (d) => `${String(d.getDate()).padStart(2, "0")}/${String(d.getMonth() + 1).padStart(2, "0")}`;
export const ddmmyyyy = (d) => `${ddmm(d)}/${d.getFullYear()}`;
export const longDate = (d = new Date()) => `${WD[d.getDay()]}, ${ddmmyyyy(d)}`;
export const isoDate = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

export function due(t) {
  if (!t.due_date) return null;
  const d = parseDate(t.due_date), n = Math.round((d - today()) / 864e5), closed = t.status === "done" || t.status === "cancelled";
  let text = `Hạn ${ddmm(d)}`, tone = "";
  if (!closed) {
    if (n < 0) { text = `Quá hạn ${-n} ngày`; tone = "late"; }
    else if (n === 0) { text = "Hạn hôm nay"; tone = "soon"; }
    else if (n === 1) { text = "Hạn ngày mai"; tone = "soon"; }
    else if (n <= 3) { text = `Còn ${n} ngày`; tone = "soon"; }
  }
  return { text, tone, n, closed, date: d };
}
export const isOverdue = (t) => { const d = due(t); return !!d && !d.closed && d.n < 0; };
export const isOpen = (t) => t.status !== "done" && t.status !== "cancelled";

export function ago(iso) {
  const s = (Date.now() - new Date(iso)) / 1e3;
  if (s < 60) return "vừa xong";
  if (s < 3600) return `${Math.floor(s / 60)} phút trước`;
  if (s < 86400) return `${Math.floor(s / 3600)} giờ trước`;
  const d = Math.floor(s / 86400);
  if (d === 1) return "hôm qua";
  if (d < 30) return `${d} ngày trước`;
  return ddmmyyyy(new Date(iso));
}
export const dt = (iso) => { const d = new Date(iso); return `${ddmmyyyy(d)} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`; };
export const initials = (name = "") => name.trim().split(/\s+/).slice(-2).map((w) => w[0]).join("").toUpperCase();
export const byPriority = (a, b) => (PRIORITY_ORDER[a.priority] - PRIORITY_ORDER[b.priority]) || (a.due_date || "9").localeCompare(b.due_date || "9");
export const plural = (n, word) => `${n} ${word}`;

// Ô màu nhận diện dự án (ổn định theo id): oklch cùng độ sáng/độ đậm, chỉ đổi sắc độ
export function projectColor(id = "") {
  let h = 0; for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) % 360;
  return `oklch(0.72 0.11 ${h})`;
}
