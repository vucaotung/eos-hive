import { useEffect, useMemo, useState } from "react";
import { Input, ToggleButton, ToggleButtonGroup } from "@heroui/react";
import { ListUl, LayoutColumns3, Magnifier } from "@gravity-ui/icons";
import { useApp, useLoad, go } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { STATUS, byPriority, isOverdue, isOpen, due, ddmmyyyy } from "../lib/format.js";
import { ClockCountdown, Infinity as InfinityIcon, CheckCircle, Tray } from "@phosphor-icons/react";
import { fromIso, WEEKDAYS, startOfWeek } from "../lib/cal.js";
import { ErrorBox, LoadingList, PageHeader, SelectField, StatusBadge, DueText } from "../components/ui.jsx";
import { TaskList } from "../components/TaskRow.jsx";
import KanbanBoard from "../components/Kanban.jsx";
import { SelectBar, SelectProvider, useSelect } from "../components/select.jsx";
import BulkCreate from "../components/BulkCreate.jsx";
import { CheckSquare } from "@phosphor-icons/react";

const FILTERS = [
  ["open", "Đang mở", () => (t) => isOpen(t)],
  ["mine", "Của tôi", (u) => (t) => isOpen(t) && t.assignee_id === u],
  ["gave", "Tôi giao", (u) => (t) => isOpen(t) && t.created_by === u],
  ["ask", "Agent hỏi", () => (t) => isOpen(t) && t.waiting_on_human],
  ["review", "Chờ duyệt", () => (t) => t.status === "in_review"],
  ["late", "Quá hạn", () => (t) => isOverdue(t)],
  ["done", "Xong 60 ngày", () => (t) => t.status === "done"],
  ["upcoming", "Sắp tới", (u) => (t) => isOpen(t) && t.assignee_id === u && !!t.due_date && due(t).n > 0],
  ["anytime", "Bất cứ lúc nào", (u) => (t) => isOpen(t) && t.assignee_id === u && !t.due_date],
  ["backlog", "Backlog", () => (t) => isOpen(t) && !t.assignee_id && !t.agent_role],
  ["doing", "Đang làm", () => (t) => t.status === "in_progress"],
  ["soon3", "Hạn 3 ngày", () => (t) => isOpen(t) && !!t.due_date && due(t).n >= 0 && due(t).n <= 3],
  ["soon7", "Hạn 7 ngày", () => (t) => isOpen(t) && !!t.due_date && due(t).n >= 0 && due(t).n <= 7],
  ["all", "Tất cả", () => () => true],
];
const HIDDEN = new Set(["doing", "soon3", "soon7", "all"]);   // chỉ hiện khi đang chọn (đi vào từ ô chỉ số Tổng quan)
const NEED_DATE = ["upcoming"];

// Nhóm danh sách theo ngữ cảnh (design/README.md §3): Sắp tới theo ngày; Bất cứ lúc nào theo trạng thái; Hoàn thành theo thời điểm; Backlog theo dự án
function groupsFor(f, tasks, today) {
  const label = (d) => { const n = Math.round((d - today) / 864e5); return n === 1 ? `Ngày mai · ${WEEKDAYS[(d.getDay() + 6) % 7]} ${String(d.getDate()).padStart(2, "0")}/${String(d.getMonth() + 1).padStart(2, "0")}` : `${WEEKDAYS[(d.getDay() + 6) % 7]} ${String(d.getDate()).padStart(2, "0")}/${String(d.getMonth() + 1).padStart(2, "0")}`; };
  const by = (keyFn, titleFn, order) => { const m = new Map(); for (const t of tasks) { const k = keyFn(t); if (!m.has(k)) m.set(k, []); m.get(k).push(t); } return [...m.entries()].sort((a, b) => order(a[0], b[0])).map(([k, items]) => ({ key: String(k), title: titleFn(k), items })); };
  if (f === "upcoming") { const wk = startOfWeek(today); const nextWk = new Date(wk); nextWk.setDate(nextWk.getDate() + 7);
    return by((t) => { const d = fromIso(t.due_date); return d < nextWk ? t.due_date.slice(0, 10) : "later"; }, (k) => k === "later" ? "Tuần sau trở đi" : label(fromIso(k)), (a, b) => (a === "later") - (b === "later") || String(a).localeCompare(String(b))); }
  if (f === "anytime") return by((t) => t.status === "in_progress" ? 0 : 1, (k) => (k === 0 ? "Đang làm" : "Chưa bắt đầu"), (a, b) => a - b);
  if (f === "done") { const wk = startOfWeek(today).getTime(); return by((t) => { const c = t.completed_at ? new Date(t.completed_at) : null; return !c ? 2 : c >= today ? 0 : c.getTime() >= wk ? 1 : 2; }, (k) => ["Hôm nay", "Tuần này", "Trước đó"][k], (a, b) => a - b); }
  if (f === "backlog") return by((t) => t.project_id || "_", (k) => k === "_" ? "Không thuộc dự án" : k, (a, b) => String(a).localeCompare(String(b)));
  return null;
}
function SelectToggle() { const s = useSelect(); return <button type="button" aria-pressed={s.on} onClick={() => (s.on ? s.exit() : s.enter())} className={`inline-flex h-9 items-center gap-1.5 rounded-lg px-3 text-[13px] font-medium ${s.on ? "bg-accent-soft text-act" : "text-muted hover:bg-surface-secondary"}`} style={{ boxShadow: `inset 0 0 0 1px ${s.on ? "var(--accent)" : "var(--border)"}` }}><CheckSquare size={16} />Chọn nhiều</button>; }

export default function Tasks() {
  const { companyId, userId, org, route, refresh, tagsMap } = useApp();
  const [f, setF] = useState(route.params.f || "open");
  const [view, setView] = useState(() => route.params.v || (() => { try { return localStorage.getItem("deo.view") || "list"; } catch { return "list"; } })());
  const [dept, setDept] = useState(null);
  const [assignee, setAssignee] = useState(null);
  const [project, setProject] = useState(route.params.p || null);
  const [q, setQ] = useState(route.params.q || "");
  const [tag, setTag] = useState(route.params.tag || null);
  const [bulk, setBulk] = useState(false);
  const allTags = useMemo(() => [...new Set(Object.values(tagsMap || {}).flat())].sort((a, b) => a.localeCompare(b, "vi")), [tagsMap]);
  useEffect(() => { if (route.params.f) setF(route.params.f); else if (!route.params.q) setF("open"); setQ(route.params.q || ""); if (route.params.v) setView(route.params.v); }, [route.params.f, route.params.q, route.params.v]);

  const { data, error, loading } = useLoad(() => companyId ? rpc("app_tasks", { company_id: companyId, days: 60 }) : Promise.resolve([]), [companyId]);

  const base = useMemo(() => (data || []).filter((t) =>
    (!dept || t.department_id === dept) && (!assignee || t.assignee_id === assignee) && (!project || t.project_id === project) && (!tag || (tagsMap?.[t.id] || []).includes(tag)) &&
    (!q || `${t.title} T-${t.id}`.toLowerCase().includes(q.toLowerCase()))), [data, dept, assignee, project, q, tag, tagsMap]);
  const pick = FILTERS.find((x) => x[0] === f) || FILTERS[0];
  const shown = useMemo(() => {
    const arr = base.filter(pick[2](userId));
    return f === "done" ? arr.sort((a, b) => (b.completed_at || "").localeCompare(a.completed_at || "")) : arr.sort(byPriority);
  }, [base, pick, userId, f]);

  const setFilter = (k) => { setF(k); go("tasks", k === "open" ? undefined : { f: k }); };
  const setV = (v) => { setView(v); try { localStorage.setItem("deo.view", v); } catch { /* bỏ qua */ } };

  return (
    <SelectProvider onDone={refresh}>
    <div className="flex flex-col gap-6">
      <PageHeader title="Việc" sub={data ? `${data.filter(isOpen).length} việc đang mở` : " "}
        actions={<>
          <button type="button" onClick={() => setBulk(true)} className="inline-flex h-9 items-center gap-1.5 rounded-lg px-3 text-[13px] font-medium text-muted hover:bg-surface-secondary" style={{ boxShadow: "inset 0 0 0 1px var(--border)" }}>Tạo hàng loạt</button>
          <SelectToggle />
          <ToggleButtonGroup aria-label="Cách xem" selectionMode="single" disallowEmptySelection selectedKeys={new Set([view])} onSelectionChange={(k) => setV([...k][0])}>
            <ToggleButton id="list" aria-label="Danh sách"><ListUl className="size-4" />Danh sách</ToggleButton>
            <ToggleButton id="kanban" aria-label="Bảng"><LayoutColumns3 className="size-4" />Bảng</ToggleButton>
          </ToggleButtonGroup></>
        } />
      <SelectBar tasks={shown} />

      <div className="flex flex-col gap-3">
        <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 sm:mx-0 sm:flex-wrap sm:px-0" role="group" aria-label="Lọc">
          {FILTERS.filter(([k]) => !HIDDEN.has(k) || k === f).map(([k, label, fn]) => {
            const n = base.filter(fn(userId)).length, on = f === k;
            return (
              <button key={k} type="button" aria-pressed={on} onClick={() => setFilter(k)}
                className={`flex h-9 shrink-0 items-center gap-2 whitespace-nowrap rounded-full px-3.5 text-[13.5px] font-medium ${on ? "bg-accent-soft text-act" : "bg-surface text-muted hover:bg-surface-secondary hover:text-foreground"}`} style={{ boxShadow: on ? "inset 0 0 0 1px var(--accent)" : "inset 0 0 0 1px var(--border)" }}>
                {label}<span className={on ? "opacity-70" : "text-muted"}>{n}</span>
              </button>
            );
          })}
        </div>
        {allTags.length > 0 && (
          <div className="no-scrollbar -mx-4 flex items-center gap-1.5 overflow-x-auto px-4 sm:mx-0 sm:flex-wrap sm:px-0" role="group" aria-label="Lọc theo nhãn">
            <span className="shrink-0 text-[13px] text-muted">Nhãn</span>
            {allTags.map((n) => <button key={n} type="button" aria-pressed={tag === n} onClick={() => setTag(tag === n ? null : n)} className={`h-7 shrink-0 whitespace-nowrap rounded-full px-2.5 text-[13px] ${tag === n ? "bg-accent-soft text-act" : "text-muted hover:bg-surface-secondary"}`} style={{ boxShadow: `inset 0 0 0 1px ${tag === n ? "var(--accent)" : "var(--border)"}` }}>#{n}</button>)}
          </div>)}
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
        (() => { const today = new Date(); today.setHours(0, 0, 0, 0); const gs = groupsFor(f, shown, today);
          return gs ? (gs.length ? <div className="flex flex-col gap-5">{gs.map((g) => (
            <section key={g.key} className="flex flex-col gap-2"><h2 className="flex items-center gap-2 px-1 text-[13px] font-medium text-muted">{g.title === "Ngày mai" || String(g.title).startsWith("Ngày mai") ? <ClockCountdown size={15} className="text-warning" /> : f === "anytime" ? <InfinityIcon size={15} /> : f === "done" ? <CheckCircle size={15} className="text-success" /> : null}{f === "backlog" && g.title !== "Không thuộc dự án" ? (org.projects.find((p) => p.id === g.title)?.name || "Dự án") : g.title}<span className="text-faint">{g.items.length}</span>
              {f === "backlog" && <span className="ml-auto text-xs font-normal text-faint">Việc chưa giao: người có quyền giao ở panel chi tiết</span>}</h2>
              <TaskList tasks={g.items} /></section>))}</div> : <TaskList tasks={[]} empty="Không có việc nào khớp bộ lọc này." />)
            : <TaskList tasks={shown} empty="Không có việc nào khớp bộ lọc này." />; })()
      ) : (
        <KanbanBoard tasks={base} />
      )}
    </div>
    <BulkCreate isOpen={bulk} onClose={() => setBulk(false)} />
    </SelectProvider>
  );
}

export { STATUS };
