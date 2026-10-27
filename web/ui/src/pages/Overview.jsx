import { useMemo, useState } from "react";
import { Flame, ListChecks, CheckCircle, CircleHalf, WarningCircle, ClockCountdown, CalendarBlank, Sparkle } from "@phosphor-icons/react";
import { useApp, useLoad, go } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { isOpen, isOverdue, due, projectColor } from "../lib/format.js";
import { addDays, iso } from "../lib/cal.js";
import { burndown, countable, doneSince, onTime, periodStart, streak, workload } from "../lib/stats.js";
import { ErrorBox, LoadingList, PageHeader, Person } from "../components/ui.jsx";
import { Card, Legend, Seg, StackBar, Tile } from "../components/charts.jsx";

// Tổng quan (design/README.md §1). Mọi số liệu suy ra từ danh sách việc; "Dự báo" là tính toán từ dữ liệu việc, KHÔNG do AI.
const PERIOD = [["week", "Tuần"], ["month", "Tháng"], ["quarter", "Quý"]];
const FACTOR = { week: 1, month: 4, quarter: 13 };
const STATUS_PARTS = [["todo", "Chờ làm", "var(--muted)"], ["in_progress", "Đang làm", "var(--info)"], ["blocked", "Vướng", "var(--danger)"], ["in_review", "Chờ duyệt", "var(--warning)"], ["done", "Xong", "var(--success)"]];

export default function Overview() {
  const { companyId, org, lookups, settings, me } = useApp();
  const [period, setPeriod] = useState("week");
  const { data, error, loading } = useLoad(() => companyId ? rpc("app_tasks", { company_id: companyId, days: 90 }) : Promise.resolve([]), [companyId]);
  const S = useMemo(() => {
    const all = (data || []).filter(countable), open = all.filter(isOpen), today = new Date(); today.setHours(0, 0, 0, 0);
    const within = (n) => open.filter((t) => { const d = due(t); return d && d.n >= 0 && d.n <= n; });
    const from = periodStart(period), done = doneSince(all, from), goal = Math.round(settings.weeklyGoal * FACTOR[period]);
    const week = doneSince(all, periodStart("week"));
    // dự báo tuần tới: việc đến hạn trong 7 ngày + rủi ro (bị chặn/chờ trả lời, chưa giao, người làm quá tải, sát hạn mà chưa bắt đầu)
    const next = within(7), load = new Map();
    const lv = (uid) => { if (!load.has(uid)) load.set(uid, workload(all, uid, isOverdue).level); return load.get(uid); };
    const risks = next.map((t) => {
      const why = [];
      if (t.status === "blocked" || t.waiting_on_human) why.push("đang bị chặn hoặc chờ trả lời");
      if (!t.assignee_id && !t.agent_role) why.push("chưa có người phụ trách");
      if (t.assignee_id && lv(t.assignee_id) >= 3) why.push(`${lookups.person[t.assignee_id]?.name || "người phụ trách"} đang quá tải`);
      if (t.status === "todo" && due(t)?.n <= 2) why.push("sắp đến hạn mà chưa bắt đầu");
      return why.length ? { t, why } : null;
    }).filter(Boolean);
    const byPerson = org.members.filter((m) => m.active && m.user).map((m) => {
      const ts = all.filter((t) => t.assignee_id === m.user.id && !t.agent_role);
      return { user: m.user, done: doneSince(ts, from).length, doing: ts.filter((t) => t.status === "in_progress").length, late: ts.filter(isOverdue).length };
    }).filter((p) => p.done + p.doing + p.late > 0).sort((a, b) => b.done + b.doing + b.late - (a.done + a.doing + a.late)).slice(0, 8);
    const ai = all.filter((t) => t.agent_role);
    const byProject = org.projects.filter((p) => p.active).map((p) => {
      const ts = open.filter((t) => t.project_id === p.id);
      return { p, parts: [["Cao", ts.filter((t) => t.priority === "urgent" || t.priority === "high").length, "var(--danger)"], ["Thường", ts.filter((t) => t.priority === "medium").length, "var(--warning)"], ["Thấp", ts.filter((t) => t.priority === "low").length, "var(--muted)"]], n: ts.length };
    }).filter((x) => x.n > 0);
    return {
      total: all.length, done: all.filter((t) => t.status === "done").length, doing: all.filter((t) => t.status === "in_progress").length,
      late: open.filter(isOverdue).length, d3: within(3).length, d7: next.length, doneP: done.length, goal, week: week.length, weekGoal: settings.weeklyGoal,
      onTime: done.length ? Math.round((100 * done.filter(onTime).length) / done.length) : null, streak: streak(all), risks, next: next.length,
      status: STATUS_PARTS.map(([k, label, color]) => ({ label, color, value: all.filter((t) => t.status === k).length })), byPerson, ai, byProject, burn: burndown(all, 14),
    };
  }, [data, period, settings.weeklyGoal, org, lookups.person]);

  const pct = S.goal ? Math.min(100, Math.round((100 * S.doneP) / S.goal)) : 0;
  const maxBurn = Math.max(1, ...S.burn.map((b) => b.open));
  const first = S.burn[0]?.open || 0, nB = S.burn.length;
  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Tổng quan" sub={`${org.projects.filter((p) => p.active).length} dự án · ${org.members.filter((m) => m.active).length} thành viên`}
        actions={<Seg label="Kỳ" value={period} onChange={setPeriod} options={PERIOD} />} />
      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={5} /> : (<>
        <div className="grid grid-cols-[repeat(auto-fill,minmax(150px,1fr))] gap-3">
          <Tile icon={ListChecks} label="Tổng việc" value={S.total} onPress={() => go("tasks", { f: "all" })} />
          <Tile icon={CheckCircle} label="Đã xong" value={S.done} tone="var(--success)" onPress={() => go("tasks", { f: "done" })} />
          <Tile icon={CircleHalf} label="Đang làm" value={S.doing} tone="var(--info)" onPress={() => go("tasks", { f: "doing" })} />
          <Tile icon={WarningCircle} label="Quá hạn" value={S.late} tone="var(--danger)" bad={S.late > 0} onPress={() => go("tasks", { f: "late" })} />
          <Tile icon={ClockCountdown} label="Hạn 3 ngày" value={S.d3} tone="var(--warning)" onPress={() => go("tasks", { f: "soon3" })} />
          <Tile icon={CalendarBlank} label="Hạn 7 ngày" value={S.d7} onPress={() => go("tasks", { f: "soon7" })} />
        </div>
        <div className="grid items-start gap-4 [grid-template-columns:repeat(auto-fit,minmax(min(400px,100%),1fr))]">
          <Card title={`${period === "week" ? "Tuần này" : period === "month" ? "Tháng này" : "Quý này"} đã hoàn thành`}>
            <div className="flex items-end gap-3"><b className="text-[52px] font-medium leading-none tabular-nums">{S.doneP}</b><span className="pb-1.5 text-muted">/ {S.goal} mục tiêu</span></div>
            <div className="h-2 overflow-hidden rounded-full bg-surface-secondary" role="img" aria-label={`${pct}% mục tiêu`}><span className="block h-full rounded-full bg-success" style={{ width: `${pct}%` }} /></div>
            <p className="flex flex-wrap gap-x-5 gap-y-1 text-sm"><span><b className="font-medium">{pct}%</b> <span className="text-muted">đạt mục tiêu</span></span>
              <span className="inline-flex items-center gap-1"><Flame size={15} weight="fill" className="text-warning" aria-hidden="true" /><b className="font-medium">{S.streak}</b> <span className="text-muted">ngày liên tiếp</span></span>
              <span><b className="font-medium">{S.onTime == null ? "–" : `${S.onTime}%`}</b> <span className="text-muted">đúng hạn</span></span></p>
            <p className="text-xs text-faint">Đổi mục tiêu tuần ở Tài khoản › Mục tiêu (hiện {settings.weeklyGoal}/tuần).</p>
          </Card>
          <Card title="Dự báo tuần tới" aside={<span className="inline-flex items-center gap-1 text-xs text-muted"><Sparkle size={13} aria-hidden="true" />tính từ dữ liệu việc</span>}>
            <p className="flex items-baseline gap-4"><span><b className="text-[28px] font-medium tabular-nums">{S.next}</b> <span className="text-muted">việc đến hạn</span></span><span><b className="text-[28px] font-medium tabular-nums text-warning">{S.risks.length}</b> <span className="text-muted">có rủi ro</span></span></p>
            {S.risks.length ? <ul className="flex flex-col gap-2 text-sm">{S.risks.slice(0, 5).map(({ t, why }) => <li key={t.id}><button type="button" onClick={() => go("overview", { t: t.id })} className="text-left hover:underline"><b className="font-medium">{t.title}</b><span className="block text-xs text-warning">{why.join("; ")}</span></button></li>)}</ul>
              : <p className="text-sm text-muted">Chưa thấy rủi ro nào trong 7 ngày tới.</p>}
          </Card>
          <Card title="Theo trạng thái"><StackBar parts={S.status} /><Legend parts={S.status} /></Card>
          <Card title={`Theo người làm · ${PERIOD.find((p) => p[0] === period)[1].toLowerCase()} này`}>
            {S.byPerson.map(({ user, done, doing, late }) => (
              <div key={user.id} className="flex flex-col gap-1"><div className="flex items-center justify-between text-sm"><Person user={user} /><span className="text-xs text-muted tabular-nums">{done} xong · {doing} đang làm · <b className={late ? "font-medium text-danger" : "font-medium"}>{late} quá hạn</b></span></div>
                <StackBar height={8} parts={[{ label: "Xong", value: done, color: "var(--success)" }, { label: "Đang làm", value: doing, color: "var(--info)" }, { label: "Quá hạn", value: late, color: "var(--danger)" }]} /></div>))}
            {S.ai.length > 0 && <div className="flex flex-col gap-1 border-t border-separator pt-2 text-sm"><span className="flex items-center gap-2"><span className="grid size-6 place-items-center rounded-md border border-ai bg-ai-bg text-ai"><Sparkle size={13} weight="fill" /></span>Agent AI <span className="rounded border border-ai px-1 text-[10px] font-semibold leading-4 text-ai">AI</span><span className="ml-auto text-xs text-muted">{S.ai.length} việc · không tính KPI</span></span></div>}
            {!S.byPerson.length && <p className="text-sm text-muted">Chưa có việc nào trong kỳ.</p>}
          </Card>
          <Card title="Burndown 14 ngày" aside={<span className="text-xs text-muted">việc còn mở mỗi ngày</span>}>
            <svg viewBox={`0 0 ${nB * 28} 120`} className="h-36 w-full" role="img" aria-label="Biểu đồ burndown">
              {S.burn.map((b, i) => <rect key={i} x={i * 28 + 4} width={20} y={110 - (100 * b.open) / maxBurn} height={(100 * b.open) / maxBurn} rx="3" fill="var(--accent)" opacity={i === nB - 1 ? 1 : 0.45} />)}
              <line x1="4" y1={110 - (100 * first) / maxBurn} x2={nB * 28 - 4} y2="110" stroke="var(--muted)" strokeDasharray="4 4" strokeWidth="1.5" />
            </svg>
            <p className="flex justify-between text-xs text-muted"><span>{iso(S.burn[0].date).slice(8)}/{iso(S.burn[0].date).slice(5, 7)}</span><span>vạch đứt: đường lý tưởng về 0</span><span>hôm nay: {S.burn[nB - 1].open}</span></p>
          </Card>
          <Card title="Ưu tiên theo dự án">
            {S.byProject.map(({ p, parts, n }) => <div key={p.id} className="flex flex-col gap-1"><div className="flex items-center justify-between text-sm"><span className="inline-flex items-center gap-1.5"><i className="size-2.5 rounded-sm" style={{ background: projectColor(p.id) }} />{p.name}</span><span className="text-xs text-muted tabular-nums">{n} việc mở</span></div>
              <StackBar height={8} parts={parts.map(([label, value, color]) => ({ label, value, color }))} /></div>)}
            {!S.byProject.length && <p className="text-sm text-muted">Chưa có việc mở trong dự án nào.</p>}
            <Legend parts={[{ label: "Cao", color: "var(--danger)", value: S.byProject.reduce((s, x) => s + x.parts[0][1], 0) }, { label: "Thường", color: "var(--warning)", value: S.byProject.reduce((s, x) => s + x.parts[1][1], 0) }, { label: "Thấp", color: "var(--muted)", value: S.byProject.reduce((s, x) => s + x.parts[2][1], 0) }]} />
          </Card>
        </div>
      </>)}
    </div>
  );
}
