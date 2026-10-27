import { useMemo, useState } from "react";
import { Button, toast } from "@heroui/react";
import { ArrowElbowDownRight, CaretLeft, CaretRight, X } from "@phosphor-icons/react";
import { useApp, useLoad, go } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { STATUS, PRIORITY, isOpen, isOverdue, due, ddmmyyyy, parseDate, projectColor } from "../lib/format.js";
import { addDays, iso, startOfWeek } from "../lib/cal.js";
import { ErrorBox, LoadingList, PageHeader, StatusIcon, AgentChip } from "../components/ui.jsx";
import KanbanBoard from "../components/Kanban.jsx";
import { Seg } from "../components/charts.jsx";
import { Timeline } from "./Calendar.jsx";
import ZoomBox from "../components/ZoomBox.jsx";

// Trang dự án (design/README.md §7): Kanban · Danh sách (sửa tại chỗ) · Mindmap · Gantt, chung một thanh lọc.
const VIEWS = [["kanban", "Kanban"], ["list", "Danh sách"], ["mindmap", "Mindmap"], ["gantt", "Gantt"]];
const EDITABLE = ["todo", "in_progress", "blocked", "cancelled"];   // trạng thái đổi trực tiếp được; Chờ duyệt/Xong đi qua nộp và duyệt
const sel = "h-[30px] rounded-md border border-border bg-field-background px-1.5 text-[13px] disabled:opacity-60";

function ListView({ tasks, all, onSave }) {
  const { org, lookups, openTask } = useApp();
  const ids = new Set(tasks.map((t) => t.id));
  const top = tasks.filter((t) => !t.parent_id || !ids.has(t.parent_id));
  const kids = (id) => tasks.filter((t) => t.parent_id === id);
  const people = org.members.filter((m) => m.active && m.user);
  const Row = ({ t, depth }) => {
    const editable = EDITABLE.includes(t.status), late = isOverdue(t);
    return (
      <div className={`grid items-center gap-2 border-t border-separator px-3 py-1.5 [grid-template-columns:minmax(0,1fr)_130px_110px_170px_130px] max-lg:[grid-template-columns:minmax(0,1fr)_130px] ${late ? "shadow-[inset_3px_0_0_var(--danger)]" : ""}`}>
        <span className="flex min-w-0 items-center gap-2" style={{ paddingLeft: depth * 22 }}>
          {depth > 0 && <ArrowElbowDownRight size={14} className="shrink-0 text-faint" aria-hidden="true" />}
          <StatusIcon status={t.status} waiting={t.waiting_on_human} size={16} />
          <button type="button" onClick={() => openTask(t.id)} className={`truncate text-left text-[13.5px] font-medium hover:underline ${t.status === "done" ? "text-faint line-through" : ""}`}>{t.title}</button>
          {t.agent_role && <AgentChip name={lookups.agent[t.agent_role]?.name || t.agent_role} size={18} showName={false} />}
        </span>
        <select aria-label={`Trạng thái ${t.title}`} className={sel} value={t.status} disabled={!editable} onChange={(e) => onSave(t, { status: e.target.value })}>
          {(editable ? EDITABLE : [t.status]).map((s) => <option key={s} value={s}>{STATUS[s]}</option>)}
        </select>
        <select aria-label={`Ưu tiên ${t.title}`} className={`${sel} max-lg:hidden`} value={t.priority} onChange={(e) => onSave(t, { priority: e.target.value })}>
          {Object.entries(PRIORITY).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
        </select>
        <select aria-label={`Người làm ${t.title}`} className={`${sel} max-lg:hidden`} value={t.assignee_id || ""} onChange={(e) => onSave(t, { assignee_id: e.target.value })}>
          <option value="">Chưa giao</option>{people.map((m) => <option key={m.user.id} value={m.user.id}>{m.user.name}</option>)}
        </select>
        <input type="date" aria-label={`Hạn ${t.title}`} className={`${sel} max-lg:hidden ${late ? "text-danger" : ""}`} value={t.due_date?.slice(0, 10) || ""} onChange={(e) => onSave(t, { due_date: e.target.value })} />
      </div>
    );
  };
  const render = (t, depth) => <div key={t.id}><Row t={t} depth={depth} />{kids(t.id).map((k) => render(k, depth + 1))}</div>;
  return (
    <div className="overflow-hidden rounded-[14px] bg-surface" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
      <div className="grid gap-2 px-3 py-2 text-[11px] font-medium uppercase tracking-[.06em] text-faint [grid-template-columns:minmax(0,1fr)_130px_110px_170px_130px] max-lg:[grid-template-columns:minmax(0,1fr)_130px]">
        <span>Công việc</span><span>Trạng thái</span><span className="max-lg:hidden">Ưu tiên</span><span className="max-lg:hidden">Người làm</span><span className="max-lg:hidden">Hạn</span>
      </div>
      {top.map((t) => render(t, 0))}
      {!top.length && <p className="px-4 py-6 text-sm text-muted">Không có việc nào khớp bộ lọc.</p>}
      <p className="border-t border-separator px-4 py-2 text-xs text-faint">Sửa trực tiếp trong bảng; chỉ người có quyền sửa việc mới lưu được (máy chủ kiểm tra). Việc Chờ duyệt/Xong đổi qua nộp và duyệt.</p>
    </div>
  );
}

function Mindmap({ project, tasks }) {
  const { openTask } = useApp();
  const ids = new Set(tasks.map((t) => t.id));
  const branches = tasks.filter((t) => !t.parent_id || !ids.has(t.parent_id));
  const kids = (id) => tasks.filter((t) => t.parent_id === id);
  const Leaf = ({ t }) => <button type="button" onClick={() => openTask(t.id)} className="flex max-w-[260px] items-center gap-1.5 rounded-lg border border-separator bg-surface px-2.5 py-1 text-left text-[12.5px] hover:bg-surface-secondary"><StatusIcon status={t.status} size={13} /><span className="truncate">{t.title}</span></button>;
  return (
    <div className="overflow-x-auto pb-3"><div className="flex min-w-max items-center">
      <div className="rounded-xl border border-accent bg-accent-soft px-4 py-3 text-center font-medium text-act" style={{ borderColor: "var(--accent)" }}>{project.name}</div>
      <div className="ml-8 flex flex-col gap-3 border-l border-border pl-0">
        {branches.map((b) => { const ks = kids(b.id), dn = ks.filter((k) => k.status === "done").length; return (
          <div key={b.id} className="flex items-center">
            <span className="h-px w-8 bg-border" />
            <button type="button" onClick={() => openTask(b.id)} className="w-[220px] rounded-xl border border-border bg-surface px-3 py-2 text-left hover:bg-surface-secondary">
              <span className="flex items-center gap-1.5 text-[13.5px] font-medium"><StatusIcon status={b.status} size={15} /><span className="truncate">{b.title}</span></span>
              {ks.length > 0 && <span className="text-xs text-muted">{dn}/{ks.length} xong</span>}
            </button>
            {ks.length > 0 && <><span className="h-px w-6 bg-border" /><div className="flex flex-col gap-1 border-l border-border py-1 pl-3">{ks.map((k) => <div key={k.id} className="flex items-center gap-2"><span className="h-px w-3 bg-border" /><Leaf t={k} /></div>)}</div></>}
          </div>); })}
        {!branches.length && <p className="pl-8 text-sm text-muted">Không có việc nào khớp bộ lọc.</p>}
      </div>
    </div></div>
  );
}

export default function Project() {
  const { companyId, org, lookups, userId, route } = useApp();
  const pid = route.params.id, view = VIEWS.some((v) => v[0] === route.params.v) ? route.params.v : "kanban";
  const project = org.projects.find((p) => p.id === pid);
  const [tick, setTick] = useState(0);
  const [f, setF] = useState({ q: "", mine: false, assignee: "", priority: "", due: "" });
  const [anchor, setAnchor] = useState(() => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; });
  const { data, error, loading } = useLoad(() => companyId ? rpc("app_tasks", { company_id: companyId, days: 90 }) : Promise.resolve([]), [companyId, tick]);
  const mine = useMemo(() => (data || []).filter((t) => t.project_id === pid && t.status !== "cancelled" || (t.project_id === pid && view === "list")), [data, pid, view]);
  const shown = useMemo(() => mine.filter((t) => (!f.q || `${t.title} T-${t.id}`.toLowerCase().includes(f.q.toLowerCase())) && (!f.mine || t.assignee_id === userId) && (!f.assignee || t.assignee_id === f.assignee)
    && (!f.priority || t.priority === f.priority) && (!f.due || (f.due === "late" ? isOverdue(t) : f.due === "week" ? isOpen(t) && t.due_date && due(t).n >= 0 && due(t).n <= 7 : !t.due_date))), [mine, f, userId]);
  if (!project) return <div className="flex flex-col gap-3"><PageHeader title="Dự án" /><p className="text-muted">Không tìm thấy dự án này. <button type="button" className="font-medium text-act hover:underline" onClick={() => go("projects")}>Về danh sách dự án</button></p></div>;
  const done = mine.filter((t) => t.status === "done").length, pct = mine.length ? Math.round((100 * done) / mine.length) : 0;
  const setView = (v) => go("project", { id: pid, v });
  const dirty = f.q || f.mine || f.assignee || f.priority || f.due;
  async function save(t, patch) {
    try { await rpc("app_task_save", { id: t.id, ...patch }); toast.success(`Đã lưu T-${t.id}`); setTick((x) => x + 1); }
    catch (e) { toast.danger(e.message); setTick((x) => x + 1); }   // lỗi: tải lại để bảng về giá trị thật
  }
  return (
    <div className="flex flex-col gap-5">
      <nav aria-label="Vị trí" className="flex items-center gap-2 text-[13px] text-muted"><a href="#/projects" className="hover:underline">Dự án</a><span aria-hidden="true">›</span><span className="inline-flex items-center gap-1.5 text-foreground"><i className="size-2.5 rounded-sm" style={{ background: projectColor(project.id) }} />{project.name}</span></nav>
      <PageHeader title={project.name} sub={`${pct}% · ${done}/${mine.length} việc${project.end_date ? ` · hạn ${ddmmyyyy(parseDate(project.end_date))}` : ""}`} />
      <div className="flex gap-1 border-b border-separator" role="tablist" aria-label="Chế độ xem dự án">
        {VIEWS.map(([k, l]) => <button key={k} type="button" role="tab" aria-selected={view === k} onClick={() => setView(k)} className={`h-10 px-4 text-[14px] font-medium ${view === k ? "text-act" : "text-muted hover:text-foreground"}`} style={view === k ? { boxShadow: "inset 0 -2px 0 var(--accent)" } : undefined}>{l}</button>)}
      </div>
      <div className="flex flex-wrap items-center gap-2 rounded-[14px] bg-surface p-2.5" style={{ boxShadow: "0 0 0 1px var(--separator)" }} role="search" aria-label="Lọc việc trong dự án">
        <input value={f.q} onChange={(e) => setF({ ...f, q: e.target.value })} aria-label="Tìm trong dự án" placeholder="Tìm trong dự án" className="h-8 min-w-40 flex-1 rounded-lg border border-border bg-field-background px-2.5 text-[13px]" />
        <button type="button" aria-pressed={f.mine} onClick={() => setF({ ...f, mine: !f.mine })} className={`h-8 rounded-lg px-3 text-[13px] font-medium ${f.mine ? "bg-accent-soft text-act" : "text-muted"}`} style={{ boxShadow: `inset 0 0 0 1px ${f.mine ? "var(--accent)" : "var(--border)"}` }}>Của tôi</button>
        <select aria-label="Người làm" className={sel} value={f.assignee} onChange={(e) => setF({ ...f, assignee: e.target.value })}><option value="">Người làm</option>{org.members.filter((m) => m.active && m.user).map((m) => <option key={m.user.id} value={m.user.id}>{m.user.name}</option>)}</select>
        <select aria-label="Ưu tiên" className={sel} value={f.priority} onChange={(e) => setF({ ...f, priority: e.target.value })}><option value="">Ưu tiên</option>{Object.entries(PRIORITY).map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select>
        <select aria-label="Hạn chót" className={sel} value={f.due} onChange={(e) => setF({ ...f, due: e.target.value })}><option value="">Hạn chót</option><option value="late">Quá hạn</option><option value="week">Trong 7 ngày</option><option value="none">Không có hạn</option></select>
        {dirty && <Button size="sm" variant="ghost" onPress={() => setF({ q: "", mine: false, assignee: "", priority: "", due: "" })}><X size={14} />Xóa lọc</Button>}
      </div>
      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={5} /> : view === "kanban" ? <KanbanBoard tasks={shown} /> : view === "list" ? <ListView tasks={shown} all={mine} onSave={save} />
        : view === "mindmap" ? <ZoomBox label="Phóng to Mindmap"><Mindmap project={project} tasks={shown} /></ZoomBox> : (<div className="flex flex-col gap-3">
          <div className="flex items-center gap-1"><Button isIconOnly size="sm" variant="secondary" aria-label="Trước" onPress={() => setAnchor(addDays(anchor, -14))}><CaretLeft size={16} /></Button>
            <Button size="sm" variant="secondary" onPress={() => { const d = new Date(); d.setHours(0, 0, 0, 0); setAnchor(d); }}>Hôm nay</Button>
            <Button isIconOnly size="sm" variant="secondary" aria-label="Sau" onPress={() => setAnchor(addDays(anchor, 14))}><CaretRight size={16} /></Button></div>
          <ZoomBox label="Phóng to Gantt"><Timeline anchor={anchor} tasks={shown} today={(() => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; })()} /></ZoomBox></div>)}
    </div>
  );
}
