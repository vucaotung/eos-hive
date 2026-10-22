import { ChevronRight, FaceRobot } from "@gravity-ui/icons";
import { useApp } from "../lib/store.jsx";
import { PRIORITY } from "../lib/format.js";
import { DueText, StatusBadge } from "./ui.jsx";

export function TaskRow({ task, showDept = true, showProject = true }) {
  const { lookups, openTask, openTaskId } = useApp();
  const a = lookups.person[task.assignee_id], d = lookups.dept[task.department_id], p = lookups.project[task.project_id];
  const active = openTaskId === task.id;
  return (
    <button type="button" onClick={() => openTask(task.id)}
      className={`flex w-full items-start gap-3 bg-surface px-4 py-3.5 text-left transition-colors hover:bg-surface-secondary focus-visible:z-10 ${active ? "bg-surface-secondary shadow-[inset_3px_0_0_var(--foreground)]" : ""}`}>
      <span className="flex min-w-0 flex-1 flex-col gap-1">
        <span className="font-semibold leading-snug [overflow-wrap:anywhere]">{task.title}</span>
        <span className="flex flex-wrap items-center gap-x-3.5 gap-y-0.5 text-sm text-muted">
          <StatusBadge status={task.status} waiting={task.waiting_on_human} />
          {task.agent_role && <span className="inline-flex items-center gap-1"><FaceRobot className="size-3.5" />{lookups.agent[task.agent_role]?.name || task.agent_role}</span>}
          {a && <span>{a.name}</span>}
          {showDept && d && <span>{d.code}</span>}
          {showProject && p && <span className="max-w-48 truncate">{p.name}</span>}
          {(task.priority === "urgent" || task.priority === "high") && <span className="font-semibold text-foreground">{PRIORITY[task.priority]}</span>}
          <DueText task={task} />
          <span>T-{task.id}</span>
        </span>
      </span>
      <ChevronRight className="mt-1 size-4 shrink-0 text-muted" />
    </button>
  );
}

export function TaskList({ tasks, empty = "Không có việc nào.", ...rest }) {
  if (!tasks.length) return <p className="rounded-xl bg-surface px-4 py-5 text-muted">{empty}</p>;
  return <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">{tasks.map((t) => <TaskRow key={t.id} task={t} {...rest} />)}</div>;
}
