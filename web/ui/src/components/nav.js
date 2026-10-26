import { CalendarCheck, UserCircle, UserSwitch, ChatCircleDots, ListChecks, SealCheck, FolderSimple, ChartBar, Gear, Kanban, User, GridFour, CalendarBlank, CalendarDots, ChartBarHorizontal } from "@phosphor-icons/react";

// Ba nhóm giống sidebar thiết kế (design/README.md §Khung): Việc của tôi · Quản lý · Góc nhìn. Điểm đến là các màn đã có; màn mới (Eisenhower, Lịch, Nhân sự...) thêm sau khi dữ liệu đủ (docs/18).
export const NAV_GROUPS = [
  { title: "Việc của tôi", items: [
    { id: "today", page: "today", label: "Hôm nay", icon: CalendarCheck },
    { id: "mine", page: "tasks", params: { f: "mine" }, label: "Việc của tôi", icon: UserCircle },
    { id: "gave", page: "tasks", params: { f: "gave" }, label: "Tôi đã giao", icon: UserSwitch },
    { id: "ask", page: "tasks", params: { f: "ask" }, label: "Agent hỏi", icon: ChatCircleDots },
  ] },
  { title: "Quản lý", items: [
    { id: "all", page: "tasks", label: "Tất cả việc", icon: ListChecks },
    { id: "approvals", page: "approvals", label: "Duyệt", icon: SealCheck, badge: "approvals" },
    { id: "projects", page: "projects", label: "Dự án", icon: FolderSimple },
    { id: "reports", page: "reports", label: "Báo cáo", icon: ChartBar },
    { id: "admin", page: "admin", label: "Quản trị", icon: Gear, adminOnly: true },
  ] },
  { title: "Góc nhìn", items: [
    { id: "kanban", page: "tasks", params: { v: "kanban" }, label: "Bảng Kanban", icon: Kanban },
    { id: "eisenhower", page: "eisenhower", label: "Eisenhower", icon: GridFour },
    { id: "cal-month", page: "calendar", params: { m: "month" }, label: "Lịch tháng", icon: CalendarBlank },
    { id: "cal-week", page: "calendar", params: { m: "week" }, label: "Lịch tuần", icon: CalendarDots },
    { id: "cal-timeline", page: "calendar", params: { m: "timeline" }, label: "Timeline", icon: ChartBarHorizontal },
  ] },
];
export const ME_ITEM = { id: "me", page: "me", label: "Tài khoản", icon: User };

// Mục đang chọn: cùng trang và mọi tham số của mục khớp; riêng "Tất cả việc" chỉ sáng khi không có f/v.
export function isActive(item, route) {
  if (item.page !== route.page) return false;
  const want = item.params || {};
  if (item.page === "calendar") return (route.params.m || "month") === want.m;
  const keys = Object.keys(want);
  if (keys.length) return keys.every((k) => route.params[k] === want[k]);
  return item.page !== "tasks" || (!route.params.f && !route.params.v);
}
