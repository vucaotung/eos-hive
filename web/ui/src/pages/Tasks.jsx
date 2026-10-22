import { useMemo, useState } from "react";
import { Input, ToggleButton, ToggleButtonGroup } from "@heroui/react";
import { ListUl, LayoutColumns3, Magnifier } from "@gravity-ui/icons";
import { useApp, useLoad, go } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { STATUS, byPriority, isOverdue, isOpen } from "../lib/format.js";
import { ErrorBox, LoadingList, PageHeader, SelectField, StatusBadge, DueText } from "../components/ui.jsx";
import { TaskList } from "../components/TaskRow.jsx";

const FILTERS = [
  ["open", "Đang mở", () => (t) => isOpen(t)],
  ["mine", "Của tôi", (u) => (t) => isOpen(t) && t.assignee_id === u],
  ["gave", "Tôi giao", (u) => (t) => isOpen(t) && t.created_by === u],
  ["ask", "Agent hỏi", () => (t) => isOpen(t) && t.waiting_on_human],
  ["review", "Chờ duyệt", () => (t) => t.status === "in_review"],
  ["late", "Quá hạn", () => (t) => isOverdue(t)],
  ["done", "Xong 60 ngày", () => (t) => t.status === "done"],
];
const COLUMNS = ["todo", "in_progress", "blocked", "in_review", "done"];

function KanbanCard({ task }) {
  const { lookups, openTask } = useApp();
  const a = lookups.person[task.assignee_id];
  return (
    <button type="button" onClick={() => openTask(task.id)} className="flex w-full flex-col gap-1.5 rounded-lg bg-surface p-3 text-left hover:bg-surface-secondary">
      <span className="font-semibold leading-snug [overflow-wrap:anywhere]">{task.title}</span>
      <span className="flex flex-wrap gap-x-3 text-sm text-muted">
        {task.waiting_on_human && <StatusBadge status="blocked" waiting />}
        {a && <span>{a.name}</span>}<DueText task={task} /><span>T-{task.id}</span>
      </span>
    </button>
  );
}

export default function Tasks() {
  const { companyId, userId, org, route } = useApp();
  const [f, setF] = useState(route.params.f || "open");
  const [view, setView] = useState(() => { try { return localStorage.getItem("deo.view") || "list"; } catch { return "list"; } });
  const [dept, setDept] = useState(null);
  const [assignee, setAssignee] = useState(null);
  const [project, setProject] = useState(null);
  const [q, setQ] = useState("");

  const { data, error, loading } = useLoad(() => companyId ? rpc("app_tasks", { company_id: companyId, days: 60 }) : Promise.resolve([]), [companyId]);

  const base = useMemo(() => (data || []).filter((t) =>
    (!dept || t.department_id === dept) && (!assignee || t.assignee_id === assignee) && (!project || t.project_id === project) &&
    (!q || `${t.title} T-${t.id}`.toLowerCase().includes(q.toLowerCase()))), [data, dept, assignee, project, q]);
  const pick = FILTERS.find((x) => x[0] === f) || FILTERS[0];
  const shown = useMemo(() => {
    const arr = base.filter(pick[2](userId));
    return f === "done" ? arr.sort((a, b) => (b.completed_at || "").localeCompare(a.completed_at || "")) : arr.sort(byPriority);
  }, [base, pick, userId, f]);

  const setFilter = (k) => { setF(k); go("tasks", k === "open" ? undefined : { f: k }); };
  const setV = (v) => { setView(v); try { localStorage.setItem("deo.view", v); } catch { /* bỏ qua */ } };

  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Việc" sub={data ? `${data.filter(isOpen).length} việc đang mở` : " "}
        actions={
          <ToggleButtonGroup aria-label="Cách xem" selectionMode="single" disallowEmptySelection selectedKeys={new Set([view])} onSelectionChange={(k) => setV([...k][0])}>
            <ToggleButton id="list" aria-label="Danh sách"><ListUl className="size-4" />Danh sách</ToggleButton>
            <ToggleButton id="kanban" aria-label="Bảng"><LayoutColumns3 className="size-4" />Bảng</ToggleButton>
          </ToggleButtonGroup>
        } />

      <div className="flex flex-col gap-3">
        <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 sm:mx-0 sm:flex-wrap sm:px-0" role="group" aria-label="Lọc">
          {FILTERS.map(([k, label, fn]) => {
            const n = base.filter(fn(userId)).length, on = f === k;
            return (
              <button key={k} type="button" aria-pressed={on} onClick={() => setFilter(k)}
                className={`flex h-10 shrink-0 items-center gap-2 rounded-full px-4 text-[15px] font-semibold ${on ? "bg-foreground text-background" : "bg-surface hover:bg-surface-secondary"}`}>
                {label}<span className={on ? "opacity-70" : "text-muted"}>{n}</span>
              </button>
            );
          })}
        </div>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <label className="relative flex items-end">
            <span className="sr-only">Tìm việc</span>
            <Magnifier className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted" />
            <Input className="w-full pl-9" placeholder="Tìm theo tên hoặc T-số" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Tìm việc" />
          </label>
          <SelectField label="Phòng ban" value={dept} onChange={setDept} allowEmpty emptyLabel="Mọi phòng ban" options={org.departments.map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
          <SelectField label="Người phụ trách" value={assignee} onChange={setAssignee} allowEmpty emptyLabel="Mọi người" options={org.members.filter((m) => m.user).map((m) => ({ value: m.user.id, label: m.user.name }))} />
          <SelectField label="Dự án" value={project} onChange={setProject} allowEmpty emptyLabel="Mọi dự án" options={org.projects.map((p) => ({ value: p.id, label: p.name }))} />
        </div>
      </div>

      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={6} /> : view === "list" ? (
        <TaskList tasks={shown} empty="Không có việc nào khớp bộ lọc này." />
      ) : (
        <div className="no-scrollbar -mx-4 flex gap-3 overflow-x-auto px-4 pb-2 sm:mx-0 sm:px-0">
          {COLUMNS.map((c) => {
            const col = base.filter((t) => t.status === c).sort(byPriority);
            return (
              <section key={c} className="flex w-72 shrink-0 flex-col gap-2 rounded-xl bg-surface-secondary p-2 lg:w-auto lg:min-w-0 lg:flex-1">
                <h2 className="flex items-center justify-between px-1.5 pt-1"><StatusBadge status={c} /><span className="text-sm font-semibold text-muted">{col.length}</span></h2>
                <div className="flex flex-col gap-1.5">
                  {col.slice(0, 60).map((t) => <KanbanCard key={t.id} task={t} />)}
                  {!col.length && <p className="px-1.5 py-3 text-sm text-muted">Trống</p>}
                </div>
              </section>
            );
          })}
        </div>
      )}
    </div>
  );
}

export { STATUS };
