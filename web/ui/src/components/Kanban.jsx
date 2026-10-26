import { useApp } from "../lib/store.jsx";
import { byPriority, isOverdue } from "../lib/format.js";
import { StatusBadge, DueText } from "./ui.jsx";

const COLUMNS = ["todo", "in_progress", "blocked", "in_review", "done"];

function KanbanCard({ task }) {
  const { lookups, openTask } = useApp();
  const a = lookups.person[task.assignee_id];
  return (
    <button type="button" onClick={() => openTask(task.id)} className={`flex w-full flex-col gap-1.5 rounded-lg border border-separator bg-surface p-3 text-left hover:bg-surface-secondary ${isOverdue(task) ? "shadow-[inset_3px_0_0_var(--danger)]" : ""}`}>
      <span className="text-[13.5px] font-medium leading-snug [overflow-wrap:anywhere]">{task.title}</span>
      <span className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted">
        {task.waiting_on_human && <StatusBadge status="blocked" waiting />}
        {a && <span>{a.name}</span>}<DueText task={task} /><span>T-{task.id}</span>
      </span>
    </button>
  );
}


// Bảng Kanban chỉ xem (mỗi cột một trạng thái). Mobile: cuộn ngang có snap, cột kế ló ra để biết còn cột
export default function KanbanBoard({ tasks }) {
  return (
    <div className="no-scrollbar -mx-4 flex snap-x snap-mandatory gap-3 overflow-x-auto px-4 pb-2 sm:mx-0 sm:snap-none sm:px-0">
      {COLUMNS.map((c) => {
        const col = tasks.filter((t) => t.status === c).sort(byPriority);
        return (
          <section key={c} className="flex min-h-[420px] w-[calc(100vw-4.5rem)] max-w-[340px] shrink-0 snap-start flex-col gap-2 rounded-[14px] bg-surface/55 p-2 sm:w-72 lg:w-auto lg:min-w-0 lg:max-w-none lg:flex-1" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
            <h2 className="flex items-center justify-between px-1.5 pt-1"><StatusBadge status={c} /><span className="text-sm font-semibold text-muted">{col.length}</span></h2>
            <div className="flex flex-col gap-1.5">
              {col.slice(0, 60).map((t) => <KanbanCard key={t.id} task={t} />)}
              {!col.length && <p className="px-1.5 py-3 text-sm text-muted">Trống</p>}
            </div>
          </section>
        );
      })}
    </div>
  );
}
