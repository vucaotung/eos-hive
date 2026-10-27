import { useApp } from "../lib/store.jsx";
import { isOverdue, projectColor } from "../lib/format.js";
import { AgentChip, DueText, FlagMarks, Person, PriorityMark, StatusBadge, StatusIcon } from "./ui.jsx";

// Dòng việc theo design/README.md: biểu tượng trạng thái bên trái, tiêu đề 500, dòng phụ (dự án · người · hạn · ưu tiên), pill trạng thái bên phải.
// Quá hạn: dải trái đỏ + nền đỏ nhạt. Xong: tiêu đề gạch ngang, chữ mờ. (Không có nút tick: hoàn thành đi qua nộp kết quả/duyệt.)
export function TaskRow({ task, showDept = true, showProject = true }) {
  const { lookups, openTask, openTaskId } = useApp();
  const a = lookups.person[task.assignee_id], d = lookups.dept[task.department_id], p = lookups.project[task.project_id];
  const active = openTaskId === task.id, late = isOverdue(task), done = task.status === "done" || task.status === "cancelled";
  const ag = task.agent_role ? lookups.agent[task.agent_role] : null;
  return (
    <button type="button" onClick={() => openTask(task.id)}
      className={`flex w-full items-start gap-3 border-t border-separator px-4 py-3 text-left transition-colors first:border-t-0 hover:bg-surface-secondary focus-visible:z-10 ${active ? "bg-accent-soft shadow-[inset_2px_0_0_var(--accent)]" : late ? "bg-dg-bg/40 shadow-[inset_3px_0_0_var(--danger)]" : "bg-surface"}`}>
      <StatusIcon status={task.status} waiting={task.waiting_on_human} size={20} className="mt-0.5" />
      <span className="flex min-w-0 flex-1 flex-col gap-1">
        <span className={`flex items-center gap-1.5 font-medium leading-snug [overflow-wrap:anywhere] ${done ? "text-faint line-through" : ""}`}>{task.title}<FlagMarks task={task} /></span>
        <span className="flex flex-wrap items-center gap-x-3.5 gap-y-1 text-[13px] text-muted">
          {showProject && p && <span className="inline-flex max-w-48 items-center gap-1.5 truncate"><i className="size-2 shrink-0 rounded-sm" style={{ background: projectColor(p.id) }} />{p.name}</span>}
          {task.agent_role && <AgentChip name={ag?.name || task.agent_role} size={20} />}
          {a ? <Person user={a} size="sm" /> : !task.agent_role && <Person user={null} />}
          {showDept && d && <span>{d.code}</span>}
          <PriorityMark priority={task.priority === "medium" || task.priority === "low" ? null : task.priority} />
          <DueText task={task} />
          <span className="text-faint">T-{task.id}</span>
        </span>
      </span>
      <span className="hidden shrink-0 pt-0.5 sm:block"><StatusBadge status={task.status} waiting={task.waiting_on_human} /></span>
    </button>
  );
}

export function TaskList({ tasks, empty = "Không có việc nào.", ...rest }) {
  if (!tasks.length) return <p className="rounded-xl bg-surface px-4 py-5 text-muted">{empty}</p>;
  return <div className="flex flex-col overflow-hidden rounded-[14px] bg-surface" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>{tasks.map((t) => <TaskRow key={t.id} task={t} {...rest} />)}</div>;
}
