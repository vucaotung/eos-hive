import { useMemo, useState } from "react";
import { Button } from "@heroui/react";
import { CaretLeft, CaretRight, Flag, CaretDown, CaretUp } from "@phosphor-icons/react";
import { useApp, useLoad, go } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { isOverdue, projectColor, isOpen } from "../lib/format.js";
import { addDays, startOfWeek, startOfMonth, sameDay, iso, fromIso, diffDays, WEEKDAYS, monthTitle, rangeTitle, taskDue, taskStart } from "../lib/cal.js";
import { ErrorBox, LoadingList, PageHeader, StatusIcon } from "../components/ui.jsx";

// Lịch theo hạn chót (design/README.md §6). Chế độ: Tháng · Tuần · Timeline. Chế độ "Ngày" chưa có vì việc chưa có giờ bắt đầu/thời lượng (docs/18).
// Google Calendar chưa đồng bộ. Việc quá hạn có cờ đỏ.
const MODES = [["month", "Tháng"], ["week", "Tuần"], ["timeline", "Timeline"]];
const STATUS_VAR = { todo: "var(--muted)", in_progress: "var(--info)", blocked: "var(--danger)", in_review: "var(--warning)", done: "var(--success)", cancelled: "var(--fa)" };

function Chip({ task, compact }) {
  const { openTask, lookups } = useApp();
  const p = lookups.project[task.project_id], late = isOverdue(task), done = task.status === "done" || task.status === "cancelled";
  return (
    <button type="button" onClick={(e) => { e.stopPropagation(); openTask(task.id); }} title={task.title}
      className={`flex w-full gap-1 rounded px-1.5 py-0.5 text-left text-[12px] leading-5 hover:bg-surface-secondary ${compact ? "items-center truncate" : "items-start [overflow-wrap:anywhere]"} ${done ? "text-faint line-through" : ""}`}
      style={{ boxShadow: `inset 2px 0 0 ${p ? projectColor(p.id) : "var(--fa)"}` }}>
      {late && <Flag size={12} weight="fill" className="shrink-0 text-danger" aria-label="Quá hạn" />}
      {!compact && <StatusIcon status={task.status} waiting={task.waiting_on_human} size={12} />}
      <span className={compact ? "truncate" : ""}>{task.title}</span>
    </button>
  );
}

function Month({ anchor, byDay, today, setView }) {
  const first = startOfMonth(anchor), gridStart = startOfWeek(first), weeks = Math.ceil((diffDays(first, gridStart) + new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate()) / 7);
  const days = Array.from({ length: weeks * 7 }, (_, i) => addDays(gridStart, i));
  return (
    <div className="sm:overflow-x-auto"><div className="overflow-hidden rounded-[14px] bg-surface sm:min-w-[640px]" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
      <div className="grid grid-cols-7 border-b border-separator">{WEEKDAYS.map((w) => <div key={w} className="px-2 py-2 text-center text-[11px] font-medium uppercase tracking-[.06em] text-faint">{w}</div>)}</div>
      <div className="grid grid-cols-7">
        {days.map((d) => {
          const list = byDay.get(iso(d)) || [], out = d.getMonth() !== first.getMonth(), isToday = sameDay(d, today);
          return (
            <div key={iso(d)} onClick={() => setView("week", d)} className={`min-h-14 cursor-pointer border-b border-r border-separator p-1 sm:min-h-[112px] sm:p-1.5 [&:nth-child(7n)]:border-r-0 ${out ? "bg-background/60 text-faint" : ""}`}>
              <span className={`mb-1 inline-grid size-6 place-items-center rounded-full text-[12px] tabular-nums ${isToday ? "font-semibold text-act" : ""}`} style={isToday ? { boxShadow: "inset 0 0 0 1.5px var(--accent)" } : undefined}>{d.getDate()}</span>
              <div className="flex gap-1 sm:hidden" aria-label={`${list.length} việc`}>
                {list.slice(0, 3).map((t) => <i key={t.id} className="size-[5px] rounded-full" style={{ background: isOverdue(t) ? "var(--danger)" : "var(--accent)" }} />)}
              </div>
              <div className="hidden flex-col gap-0.5 sm:flex">
                {list.slice(0, 3).map((t) => <Chip key={t.id} task={t} compact />)}
                {list.length > 3 && <button type="button" onClick={(e) => { e.stopPropagation(); setView("week", d); }} className="px-1.5 text-left text-[11.5px] text-muted hover:underline">+{list.length - 3} việc nữa</button>}
              </div>
            </div>
          );
        })}
      </div>
    </div></div>
  );
}

function Week({ anchor, byDay, today }) {
  const days = Array.from({ length: 7 }, (_, i) => addDays(startOfWeek(anchor), i));
  return (
    <div className="grid grid-cols-1 gap-2 pb-2 sm:grid-cols-[repeat(7,minmax(128px,1fr))] sm:overflow-x-auto">
      {days.map((d, i) => {
        const list = byDay.get(iso(d)) || [], isToday = sameDay(d, today);
        return (
          <section key={iso(d)} aria-label={`${WEEKDAYS[i]} ${d.getDate()}/${d.getMonth() + 1}`} className="flex min-h-24 flex-col gap-1.5 rounded-[14px] bg-surface/60 p-2 sm:min-h-[320px]"
            style={{ boxShadow: `0 0 0 1px ${isToday ? "var(--accent)" : "var(--separator)"}${isToday ? ", inset 0 3px 0 var(--accent)" : ""}` }}>
            <h2 className="flex items-baseline justify-between px-1 text-[12px]"><span className="font-medium uppercase tracking-[.06em] text-faint">{WEEKDAYS[i]}</span><b className={`text-[15px] font-medium tabular-nums ${isToday ? "text-act" : ""}`}>{d.getDate()}/{d.getMonth() + 1}</b></h2>
            {list.map((t) => <Chip key={t.id} task={t} />)}
            {!list.length && <p className="px-1 py-2 text-xs text-faint">Không có việc đến hạn</p>}
          </section>
        );
      })}
    </div>
  );
}

const COLW = 40, NDAYS = 20;
function Timeline({ anchor, tasks, today }) {
  const { lookups, openTask } = useApp();
  const w0 = startOfWeek(anchor), wEnd = addDays(w0, NDAYS - 1), days = Array.from({ length: NDAYS }, (_, i) => addDays(w0, i));
  const [closed, setClosed] = useState({});
  const rows = useMemo(() => {
    const g = new Map();
    for (const t of tasks) {
      const due = taskDue(t); if (!due) continue;
      const s = taskStart(t) || due; if (due < w0 || s > wEnd) continue;
      const key = t.project_id || "_";
      if (!g.has(key)) g.set(key, []);
      g.get(key).push({ t, s: s > due ? due : s, e: due });
    }
    return [...g.entries()].map(([k, items]) => ({ k, name: k === "_" ? "Không thuộc dự án" : lookups.project[k]?.name || "Dự án", color: k === "_" ? "var(--fa)" : projectColor(k), items: items.sort((a, b) => a.s - b.s) }));
  }, [tasks, w0, wEnd, lookups.project]);
  const noDue = tasks.filter((t) => !t.due_date).length;
  return (
    <div className="flex flex-col gap-2">
      <div className="overflow-x-auto rounded-[14px] bg-surface" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
        <div style={{ minWidth: 260 + NDAYS * COLW }}>
          <div className="flex border-b border-separator">
            <div className="sticky left-0 z-10 w-[260px] shrink-0 bg-surface px-3 py-2 text-[11px] font-medium uppercase tracking-[.06em] text-faint">Việc</div>
            {days.map((d) => <div key={iso(d)} className={`w-10 shrink-0 py-1.5 text-center text-[11px] tabular-nums ${d.getDay() === 0 || d.getDay() === 6 ? "bg-separator" : ""} ${sameDay(d, today) ? "bg-accent-soft font-semibold text-act" : "text-muted"}`}>
              <div className="text-[10px] uppercase text-faint">{WEEKDAYS[(d.getDay() + 6) % 7]}</div>{d.getDate()}</div>)}
          </div>
          {rows.map((g) => (
            <div key={g.k}>
              <button type="button" onClick={() => setClosed((c) => ({ ...c, [g.k]: !c[g.k] }))} aria-expanded={!closed[g.k]} className="flex w-full items-center gap-2 border-b border-separator bg-surface-secondary px-3 py-1.5 text-left text-[13px] font-medium">
                {closed[g.k] ? <CaretDown size={13} /> : <CaretUp size={13} />}<i className="size-2.5 rounded-sm" style={{ background: g.color }} />{g.name}<span className="text-muted">{g.items.length}</span>
              </button>
              {!closed[g.k] && g.items.map(({ t, s, e }) => {
                const left = Math.max(0, diffDays(s, w0)) * COLW, right = (Math.min(diffDays(e, w0), NDAYS - 1) + 1) * COLW, late = isOverdue(t), c = STATUS_VAR[t.status] || "var(--muted)";
                return (
                  <div key={t.id} className="flex h-9 items-center border-b border-separator">
                    <button type="button" onClick={() => openTask(t.id)} className="sticky left-0 z-10 flex w-[260px] shrink-0 items-center gap-2 bg-surface px-3 text-left text-[13px] hover:bg-surface-secondary">
                      <StatusIcon status={t.status} waiting={t.waiting_on_human} size={14} /><span className="truncate">{t.title}</span></button>
                    <div className="relative h-full" style={{ width: NDAYS * COLW }}>
                      {days.map((d, i) => <i key={i} className={`absolute inset-y-0 w-10 ${sameDay(d, today) ? "bg-accent-soft/60" : d.getDay() === 0 || d.getDay() === 6 ? "bg-separator" : ""}`} style={{ left: i * COLW }} />)}
                      <button type="button" onClick={() => openTask(t.id)} aria-label={`${t.title}: ${iso(s)} đến ${iso(e)}`} title={`${t.title} · hạn ${iso(e)}`}
                        className="absolute top-1.5 h-6 rounded-[5px]" style={{ left: left + 1, width: Math.max(right - left - 2, 8), background: `color-mix(in srgb, ${c} 22%, transparent)`, boxShadow: `inset 0 0 0 1px ${c}${late ? ", inset 3px 0 0 var(--danger)" : ""}` }} />
                    </div>
                  </div>
                );
              })}
            </div>
          ))}
          {!rows.length && <p className="px-4 py-6 text-sm text-muted">Không có việc nào có hạn trong khoảng {rangeTitle(w0, wEnd)}.</p>}
        </div>
      </div>
      {noDue > 0 && <p className="text-xs text-muted">{noDue} việc chưa có hạn không hiện trên lịch.</p>}
      <p className="text-xs text-muted">Thanh chạy từ ngày bắt đầu (hoặc ngày tạo nếu chưa đặt) đến hạn chót.</p>
    </div>
  );
}

export default function CalendarPage() {
  const { companyId, route } = useApp();
  const mode = MODES.some((m) => m[0] === route.params.m) ? route.params.m : "month";
  const today = useMemo(() => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; }, []);
  const anchor = route.params.d && /^\d{4}-\d{2}-\d{2}$/.test(route.params.d) ? fromIso(route.params.d) : today;
  const { data, error, loading } = useLoad(() => companyId ? rpc("app_tasks", { company_id: companyId, days: 90 }) : Promise.resolve([]), [companyId]);
  const tasks = useMemo(() => (data || []).filter((t) => t.status !== "cancelled"), [data]);
  const byDay = useMemo(() => { const m = new Map(); for (const t of tasks) { if (!t.due_date) continue; const k = t.due_date.slice(0, 10); if (!m.has(k)) m.set(k, []); m.get(k).push(t); } return m; }, [tasks]);
  const setView = (m, d) => go("calendar", { m, d: iso(d || anchor) });
  const step = (dir) => {
    const d = mode === "month" ? new Date(anchor.getFullYear(), anchor.getMonth() + dir, 1) : addDays(anchor, dir * (mode === "week" ? 7 : 14));
    go("calendar", { m: mode, d: iso(d) });
  };
  const title = mode === "month" ? monthTitle(anchor) : mode === "week" ? rangeTitle(startOfWeek(anchor), addDays(startOfWeek(anchor), 6)) : rangeTitle(startOfWeek(anchor), addDays(startOfWeek(anchor), NDAYS - 1));
  const open = tasks.filter(isOpen).length;
  return (
    <div className="flex flex-col gap-5">
      <PageHeader title={title} sub={`Lịch theo hạn chót · ${open} việc đang mở · chưa đồng bộ Google Calendar`}
        actions={<>
          <div className="flex items-center gap-1">
            <Button isIconOnly size="sm" variant="secondary" aria-label="Trước" onPress={() => step(-1)}><CaretLeft size={16} /></Button>
            <Button size="sm" variant="secondary" onPress={() => go("calendar", { m: mode, d: iso(today) })}>Hôm nay</Button>
            <Button isIconOnly size="sm" variant="secondary" aria-label="Sau" onPress={() => step(1)}><CaretRight size={16} /></Button>
          </div>
          <div className="flex gap-1" role="group" aria-label="Chế độ xem">
            {MODES.map(([k, l]) => <Button key={k} size="sm" variant={mode === k ? "primary" : "secondary"} onPress={() => setView(k)}>{l}</Button>)}
          </div>
        </>} />
      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={5} /> : mode === "month" ? <Month anchor={anchor} byDay={byDay} today={today} setView={setView} />
        : mode === "week" ? <Week anchor={anchor} byDay={byDay} today={today} /> : <Timeline anchor={anchor} tasks={tasks} today={today} />}
    </div>
  );
}
