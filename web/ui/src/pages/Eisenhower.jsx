import { useEffect, useMemo, useState } from "react";
import { Button, Dropdown, Label, toast } from "@heroui/react";
import { Lightning, CalendarPlus, UserSwitch, Hourglass, DotsThree, Star } from "@phosphor-icons/react";
import { useApp, useLoad } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { isOpen, byPriority } from "../lib/format.js";
import { ErrorBox, LoadingList, PageHeader, Person, StatusIcon, DueText } from "../components/ui.jsx";

// Ma trận Eisenhower (design/README.md §5). Ô được suy ra từ hai cờ Quan trọng / Khẩn cấp của việc; kéo thả hoặc menu "Chuyển ô" CẬP NHẬT hai cờ đó:
// Làm ngay = cả hai · Lên lịch = chỉ Quan trọng · Giao việc = chỉ Khẩn cấp · Để sau = không cờ. Quyền sửa do máy chủ kiểm (lỗi thì việc về chỗ cũ).
export const QUADS = [
  { id: "do", title: "Làm ngay", desc: "Quan trọng và khẩn cấp", important: true, urgent: true, Icon: Lightning, tone: "var(--danger)" },
  { id: "plan", title: "Lên lịch", desc: "Quan trọng, chưa khẩn cấp", important: true, urgent: false, Icon: CalendarPlus, tone: "var(--info)" },
  { id: "delegate", title: "Giao việc", desc: "Khẩn cấp, ít quan trọng", important: false, urgent: true, Icon: UserSwitch, tone: "var(--warning)" },
  { id: "later", title: "Để sau", desc: "Không quan trọng, không khẩn cấp", important: false, urgent: false, Icon: Hourglass, tone: "var(--muted)" },
];
export const quadOf = (t) => QUADS.find((q) => q.important === !!t.important && q.urgent === !!t.urgent);

function Item({ task, onMove, onDragStart, dragging }) {
  const { lookups, openTask } = useApp();
  return (
    <div draggable onDragStart={(e) => { e.dataTransfer.setData("text/plain", `task:${task.id}`); e.dataTransfer.effectAllowed = "move"; onDragStart(task.id); }}
      className={`flex items-center gap-2 rounded-lg border border-separator bg-surface px-2.5 py-2 ${dragging ? "opacity-40" : ""}`}>
      <button type="button" onClick={() => openTask(task.id)} className="flex min-w-0 flex-1 items-center gap-2 text-left">
        <StatusIcon status={task.status} waiting={task.waiting_on_human} size={16} />
        <span className="min-w-0 flex-1 truncate text-[13.5px] font-medium">{task.title}</span>
        <DueText task={task} className="hidden text-xs sm:inline-flex" />
        <Person user={lookups.person[task.assignee_id]} showName={false} />
      </button>
      <Dropdown>
        <Button isIconOnly size="sm" variant="ghost" aria-label={`Chuyển ô cho ${task.title}`}><DotsThree size={18} weight="bold" /></Button>
        <Dropdown.Popover>
          <Dropdown.Menu aria-label="Chuyển ô" onAction={(k) => onMove(task, QUADS.find((q) => q.id === k))}>
            {QUADS.map((q) => <Dropdown.Item key={q.id} id={q.id} textValue={q.title}><Label>Chuyển sang “{q.title}”</Label></Dropdown.Item>)}
          </Dropdown.Menu>
        </Dropdown.Popover>
      </Dropdown>
    </div>
  );
}

export default function Eisenhower() {
  const { companyId, userId } = useApp();
  const [scope, setScope] = useState("all");
  const [tick, setTick] = useState(0);
  const [over, setOver] = useState({});          // id → cờ tạm thời (cập nhật lạc quan)
  const [drag, setDrag] = useState(null), [hover, setHover] = useState(null);
  const { data, error, loading } = useLoad(() => companyId ? rpc("app_tasks", { company_id: companyId, days: 1 }) : Promise.resolve([]), [companyId, tick]);

  useEffect(() => { setOver({}); }, [data]);
  const tasks = useMemo(() => (data || []).filter(isOpen).filter((t) => scope === "all" || t.assignee_id === userId)
    .map((t) => (over[t.id] ? { ...t, ...over[t.id] } : t)).sort(byPriority), [data, scope, userId, over]);

  async function move(task, q) {
    if (!q || quadOf(task)?.id === q.id) return;
    setOver((o) => ({ ...o, [task.id]: { important: q.important, urgent: q.urgent } }));
    try { await rpc("app_task_save", { id: task.id, important: q.important, urgent: q.urgent }); toast.success(`Đã chuyển sang “${q.title}”`); setTick((x) => x + 1); }   // cờ tạm giữ đến khi dữ liệu thật tải về
    catch (e) { toast.danger(e.message); setOver((o) => { const n = { ...o }; delete n[task.id]; return n; }); }   // lỗi: việc về chỗ cũ
  }
  const drop = (q) => { const t = tasks.find((x) => x.id === drag); setDrag(null); setHover(null); if (t) move(t, q); };

  const cell = (q) => {
    const list = tasks.filter((t) => quadOf(t)?.id === q.id);
    return (
      <section key={q.id} aria-label={q.title} onDragOver={(e) => { e.preventDefault(); setHover(q.id); }} onDragLeave={() => setHover(null)} onDrop={(e) => { e.preventDefault(); drop(q); }}
        className={`flex min-h-[260px] flex-col gap-2 rounded-[14px] bg-surface/55 p-3 ${hover === q.id ? "bg-accent-soft" : ""}`}
        style={{ boxShadow: `0 0 0 1px ${hover === q.id ? "var(--accent)" : "var(--separator)"}, inset 0 3px 0 ${q.tone}` }}>
        <header className="flex items-start gap-2">
          <q.Icon size={20} weight="fill" style={{ color: q.tone }} aria-hidden="true" />
          <div className="min-w-0 flex-1"><h2 className="font-medium leading-tight">{q.title}</h2><p className="text-xs text-muted">{q.desc}</p></div>
          <b className="text-lg font-medium tabular-nums">{list.length}</b>
        </header>
        <div className="flex flex-col gap-1.5">
          {list.slice(0, 40).map((t) => <Item key={t.id} task={t} onMove={move} onDragStart={setDrag} dragging={drag === t.id} />)}
          {!list.length && <p className="px-1 py-3 text-sm text-faint">Trống. Kéo việc vào đây hoặc dùng menu “Chuyển ô”.</p>}
          {list.length > 40 && <p className="px-1 text-xs text-muted">Còn {list.length - 40} việc nữa (lọc bớt để xem).</p>}
        </div>
      </section>
    );
  };

  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Eisenhower" sub="Sắp việc theo quan trọng và khẩn cấp. Kéo thả đổi cờ của việc."
        actions={
          <div className="flex gap-1" role="group" aria-label="Phạm vi">
            {[["all", "Tất cả"], ["mine", "Của tôi"]].map(([k, l]) => <Button key={k} size="sm" variant={scope === k ? "primary" : "secondary"} onPress={() => setScope(k)}>{l}</Button>)}
          </div>} />
      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={4} /> : (
        <div className="grid grid-cols-[28px_minmax(0,1fr)_minmax(0,1fr)] gap-3">
          <span />
          <p className="text-center text-[11px] font-medium uppercase tracking-[.08em] text-faint">Khẩn cấp</p>
          <p className="text-center text-[11px] font-medium uppercase tracking-[.08em] text-faint">Không khẩn</p>
          <p className="flex items-center justify-center text-[11px] font-medium uppercase tracking-[.08em] text-faint [writing-mode:vertical-rl] rotate-180">Quan trọng</p>
          {cell(QUADS[0])}{cell(QUADS[1])}
          <p className="flex items-center justify-center text-[11px] font-medium uppercase tracking-[.08em] text-faint [writing-mode:vertical-rl] rotate-180">Không quan trọng</p>
          {cell(QUADS[2])}{cell(QUADS[3])}
        </div>
      )}
      <p className="flex items-center gap-1.5 text-xs text-muted"><Star size={13} weight="fill" className="text-warning" /> = Quan trọng, <Lightning size={13} weight="fill" className="text-danger" /> = Khẩn cấp (hiện cạnh tên việc ở mọi danh sách). Chỉ người có quyền sửa việc mới đổi được cờ.</p>
    </div>
  );
}
