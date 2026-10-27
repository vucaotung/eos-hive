// Số liệu suy ra từ danh sách việc (app_tasks). Không có bảng chụp lịch sử: burndown tính từ created_at/completed_at (giả định việc không mở lại).
import { addDays, iso, fromIso, startOfWeek, startOfMonth, diffDays } from "./cal.js";
import { isOpen } from "./format.js";

const dayEnd = (d) => addDays(d, 1).getTime();
export const countable = (t) => t.status !== "cancelled";
export const completedAt = (t) => (t.status === "done" && t.completed_at ? new Date(t.completed_at) : null);
export const onTime = (t) => { const c = completedAt(t); if (!c || !t.due_date) return true; return iso(c) <= t.due_date.slice(0, 10); };

export function periodStart(period, now = new Date()) {
  const t = new Date(now); t.setHours(0, 0, 0, 0);
  if (period === "month") return startOfMonth(t);
  if (period === "quarter") return new Date(t.getFullYear(), Math.floor(t.getMonth() / 3) * 3, 1);
  return startOfWeek(t);
}
export const doneSince = (tasks, from) => tasks.filter((t) => { const c = completedAt(t); return c && c >= from; });

// Chuỗi ngày liên tiếp (tính đến hôm nay hoặc hôm qua) có ít nhất một việc hoàn thành
export function streak(tasks, now = new Date()) {
  const days = new Set(tasks.map(completedAt).filter(Boolean).map(iso));
  let d = new Date(now); d.setHours(0, 0, 0, 0);
  if (!days.has(iso(d))) d = addDays(d, -1);
  let n = 0; while (days.has(iso(d))) { n++; d = addDays(d, -1); }
  return n;
}

// Số việc còn mở vào cuối mỗi ngày của n ngày gần nhất
export function burndown(tasks, n = 14, now = new Date()) {
  const today = new Date(now); today.setHours(0, 0, 0, 0);
  const list = tasks.filter(countable);
  return Array.from({ length: n }, (_, i) => {
    const d = addDays(today, i - (n - 1)), end = dayEnd(d);
    const open = list.filter((t) => new Date(t.created_at).getTime() < end && (!completedAt(t) || completedAt(t).getTime() >= end)).length;
    return { date: d, open };
  });
}

// Mức tải của một người: điểm = việc mở + 2 × quá hạn + 2 × bị chặn/chờ trả lời. Ngưỡng: ≤2 Rảnh, ≤5 Vừa sức, ≤9 Bận, còn lại Quá tải (đề xuất, chỉnh ở đây)
export const LOAD = [
  { id: "free", label: "Rảnh", max: 2, tone: "var(--success)" }, { id: "fit", label: "Vừa sức", max: 5, tone: "var(--info)" },
  { id: "busy", label: "Bận", max: 9, tone: "var(--warning)" }, { id: "over", label: "Quá tải", max: Infinity, tone: "var(--danger)" },
];
export function workload(tasks, userId, isLate) {
  const mine = tasks.filter((t) => t.assignee_id === userId && !t.agent_role && isOpen(t));
  const late = mine.filter(isLate), blocked = mine.filter((t) => t.status === "blocked" || t.waiting_on_human);
  const score = mine.length + 2 * late.length + 2 * blocked.length;
  return { open: mine.length, late, blocked, score, level: LOAD.findIndex((l) => score <= l.max) };
}
export { startOfWeek, diffDays, fromIso };
