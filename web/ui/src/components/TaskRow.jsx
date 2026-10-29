import { useApp } from "../lib/store.jsx";
import { isOverdue, projectColor } from "../lib/format.js";
import { useRef, useState } from "react";
import { toast } from "@heroui/react";
import { rpc } from "../lib/api.js";
import { addDays, iso, fromIso } from "../lib/cal.js";
import { AgentChip, DueText, FlagMarks, Person, PriorityMark, StatusBadge, StatusIcon } from "./ui.jsx";
import { SelectMark, useLongPress, useSelect } from "./select.jsx";
import { Repeat } from "@phosphor-icons/react";

// Vuốt TRÁI (cảm ứng): lộ "Hoãn 1 ngày" và "Đổi hạn" (88px mỗi nút). Vuốt phải để hoàn thành chưa có: hoàn thành đi qua nộp kết quả/duyệt, không đóng bằng một cử chỉ.
function useSwipe(enabled) {
  const [dx, setDx] = useState(0), [open, setOpen] = useState(false), st = useRef(null);
  if (!enabled) return { dx: 0, open: false, close: () => {}, handlers: {} };
  return { dx: open ? -176 : dx, open, close: () => { setOpen(false); setDx(0); },
    handlers: {
      onTouchStart: (e) => { st.current = { x: e.touches[0].clientX, y: e.touches[0].clientY, lock: null }; },
      onTouchMove: (e) => { const s = st.current; if (!s) return; const mx = e.touches[0].clientX - s.x, my = e.touches[0].clientY - s.y;
        if (s.lock == null && (Math.abs(mx) > 10 || Math.abs(my) > 10)) s.lock = Math.abs(mx) > Math.abs(my) ? "x" : "y";
        if (s.lock === "x") setDx(Math.max(-176, Math.min(0, (open ? -176 : 0) + mx))); },
      onTouchEnd: () => { const s = st.current; st.current = null; if (s?.lock === "x") { const o = dx < -52; setOpen(o); setDx(0); if (o) navigator.vibrate?.(10); } },
    } };
}


// Dòng việc theo design/README.md: biểu tượng trạng thái bên trái, tiêu đề 500, dòng phụ (dự án · người · hạn · ưu tiên), pill trạng thái bên phải.
// Quá hạn: dải trái đỏ + nền đỏ nhạt. Xong: tiêu đề gạch ngang, chữ mờ. (Không có nút tick: hoàn thành đi qua nộp kết quả/duyệt.)
export function TaskRow({ task, showDept = true, showProject = true, swipe = false }) {
  const { lookups, openTask, openTaskId, refresh, tagsMap } = useApp();
  const coarse = swipe && matchMedia("(pointer: coarse)").matches, sel = useSelect(), sw = useSwipe(coarse && !sel?.on);
  const lp = useLongPress(() => sel?.enter(task.id));
  const dateRef = useRef(null);
  async function shift(date) {
    try { await rpc("app_task_save", { id: task.id, due_date: date }); toast.success(`Đã đổi hạn T-${task.id} sang ${date.slice(8)}/${date.slice(5, 7)}`); refresh(); }
    catch (e) { toast.danger(e.message); }
    sw.close();
  }
  const a = lookups.person[task.assignee_id], d = lookups.dept[task.department_id], p = lookups.project[task.project_id];
  const active = openTaskId === task.id, late = isOverdue(task), done = task.status === "done" || task.status === "cancelled";
  const ag = task.agent_role ? lookups.agent[task.agent_role] : null;
  const row = (
    <button type="button" onClick={() => (sel?.on ? sel.toggle(task.id) : sw.open ? sw.close() : openTask(task.id))} {...lp}
      className={`task-row flex w-full items-start gap-3 border-t border-separator px-4 py-3 text-left transition-colors first:border-t-0 hover:bg-surface-secondary focus-visible:z-10 ${active ? "bg-accent-soft shadow-[inset_2px_0_0_var(--accent)]" : late ? "bg-dg-bg/40 shadow-[inset_3px_0_0_var(--danger)]" : "bg-surface"}`}>
      {sel?.on ? <SelectMark id={task.id} /> : <StatusIcon status={task.status} waiting={task.waiting_on_human} size={20} className="mt-0.5" />}
      <span className="flex min-w-0 flex-1 flex-col gap-1">
        <span className={`flex items-center gap-1.5 font-medium leading-snug [overflow-wrap:anywhere] ${done ? "text-faint line-through" : ""}`}>{task.title}<FlagMarks task={task} /></span>
        <span className="task-meta flex flex-wrap items-center gap-x-3.5 gap-y-1 text-[13px] text-muted">
          {showProject && p && <span className="inline-flex max-w-48 items-center gap-1.5 truncate"><i className="size-2 shrink-0 rounded-sm" style={{ background: projectColor(p.id) }} />{p.name}</span>}
          {task.agent_role && <AgentChip name={ag?.name || task.agent_role} size={20} />}
          {a ? <Person user={a} size="sm" /> : !task.agent_role && <Person user={null} />}
          {showDept && d && <span>{d.code}</span>}
          <PriorityMark priority={task.priority === "medium" || task.priority === "low" ? null : task.priority} />
          <DueText task={task} />
          {task.recurrence_id && <span className="inline-flex items-center gap-1" title="Việc định kỳ"><Repeat size={13} aria-label="Việc định kỳ" /></span>}
          {(tagsMap?.[task.id] || []).slice(0, 3).map((n) => <span key={n} className="inline-flex h-5 items-center rounded-full px-2 text-[12px] text-muted" style={{ boxShadow: "inset 0 0 0 1px var(--border)" }}>#{n}</span>)}
          {(tagsMap?.[task.id] || []).length > 3 && <span className="text-faint">+{tagsMap[task.id].length - 3}</span>}
          <span className="text-faint">T-{task.id}</span>
        </span>
      </span>
      <span className="hidden shrink-0 pt-0.5 sm:block"><StatusBadge status={task.status} waiting={task.waiting_on_human} /></span>
    </button>
  );
  if (!coarse) return row;   // vuốt chỉ có trên màn cảm ứng (không dựng nút hành động ẩn trên máy tính)
  return (
    <div className="relative overflow-hidden">
      <div className={`absolute inset-y-0 right-0 flex ${sw.dx === 0 && !sw.open ? "invisible" : ""}`} aria-hidden={!sw.open}>
        <button type="button" tabIndex={sw.open ? 0 : -1} onClick={() => shift(iso(addDays(task.due_date ? fromIso(task.due_date) : new Date(), 1)))} className="w-[88px] bg-wn-bg text-[13px] font-medium text-warning">Hoãn 1 ngày</button>
        <button type="button" tabIndex={sw.open ? 0 : -1} onClick={() => dateRef.current?.showPicker?.() ?? dateRef.current?.click()} className="w-[88px] bg-in-bg text-[13px] font-medium text-info">Đổi hạn</button>
        <input ref={dateRef} type="date" tabIndex={-1} aria-label="Hạn mới" className="pointer-events-none absolute opacity-0" onChange={(e) => e.target.value && shift(e.target.value)} />
      </div>
      <div style={{ transform: `translateX(${sw.dx}px)`, transition: sw.dx === 0 || sw.open ? "transform .18s" : "none" }} {...sw.handlers}>{row}</div>
    </div>
  );
}

export function TaskList({ tasks, empty = "Không có việc nào.", ...rest }) {
  if (!tasks.length) return <p className="rounded-xl bg-surface px-4 py-5 text-muted">{empty}</p>;
  return <div className="flex flex-col overflow-hidden rounded-[14px] bg-surface" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>{tasks.map((t) => <TaskRow key={t.id} task={t} {...rest} />)}</div>;
}
