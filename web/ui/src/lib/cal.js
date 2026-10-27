// Tiện ích lịch (tuần bắt đầu thứ Hai, theo giờ địa phương)
export const DAY_MS = 864e5;
export const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); x.setHours(0, 0, 0, 0); return x; };
export const startOfWeek = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); const wd = (x.getDay() + 6) % 7; return addDays(x, -wd); };
export const startOfMonth = (d) => { const x = new Date(d); x.setDate(1); x.setHours(0, 0, 0, 0); return x; };
export const sameDay = (a, b) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
export const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
export const fromIso = (s) => { const [y, m, d] = String(s).slice(0, 10).split("-").map(Number); return new Date(y, m - 1, d); };
export const diffDays = (a, b) => Math.round((a - b) / DAY_MS);
export const WEEKDAYS = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"];
export const monthTitle = (d) => `Tháng ${d.getMonth() + 1}/${d.getFullYear()}`;
export const rangeTitle = (a, b) => `${String(a.getDate()).padStart(2, "0")}/${String(a.getMonth() + 1).padStart(2, "0")} – ${String(b.getDate()).padStart(2, "0")}/${String(b.getMonth() + 1).padStart(2, "0")}/${b.getFullYear()}`;
// Ngày một việc nằm trên lịch: hạn chót; thanh timeline: từ ngày bắt đầu (hoặc ngày tạo) đến hạn
export const taskDue = (t) => (t.due_date ? fromIso(t.due_date) : null);
export const taskStart = (t) => (t.start_date ? fromIso(t.start_date) : t.created_at ? fromIso(String(t.created_at).slice(0, 10)) : taskDue(t));
