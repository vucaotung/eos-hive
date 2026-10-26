import { useMemo } from "react";
import { Button } from "@heroui/react";
import { DownloadSimple, Users, Coffee, Prohibit, Hourglass } from "@phosphor-icons/react";
import { useApp, useLoad } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { ROLE, isOverdue } from "../lib/format.js";
import { completedAt, countable, doneSince, onTime, workload } from "../lib/stats.js";
import { startOfMonth } from "../lib/cal.js";
import { AgentChip, ErrorBox, LoadingList, PageHeader, Person } from "../components/ui.jsx";
import { Card, LoadMeter, StackBar, Tile } from "../components/charts.jsx";

// Nhân sự (design/README.md §13): tải công việc từng người và cơ sở KPI. Agent AI có thẻ riêng, KHÔNG tính KPI.
export default function People() {
  const { companyId, org, lookups, me, openTask } = useApp();
  const { data, error, loading } = useLoad(() => companyId ? rpc("app_tasks", { company_id: companyId, days: 60 }) : Promise.resolve([]), [companyId]);
  const month = startOfMonth(new Date());
  const rows = useMemo(() => {
    const all = (data || []).filter(countable);
    return org.members.filter((m) => m.active && m.user).map((m) => {
      const ts = all.filter((t) => t.assignee_id === m.user.id && !t.agent_role), w = workload(all, m.user.id, isOverdue), done = doneSince(ts, month);
      const okN = done.filter(onTime).length;
      return { m, w, done: done.length, ok: okN, late: done.length - okN, pct: done.length ? Math.round((100 * okN) / done.length) : null };
    });
  }, [data, org.members]);
  const agents = useMemo(() => (me?.agents || []).map((a) => {
    const ts = (data || []).filter((t) => t.agent_role === a.code);
    return { a, running: ts.filter((t) => t.status === "in_progress").length, waiting: ts.filter((t) => t.waiting_on_human).length, done: doneSince(ts, month).length };
  }), [data, me]);
  const maxDone = Math.max(1, ...rows.map((r) => r.done));
  const exportCsv = () => {
    const esc = (s) => `"${String(s ?? "").replace(/"/g, '""')}"`;
    const lines = [["Người", "Phòng", "Vai trò", "Xong đúng hạn", "Xong trễ", "Đang mở", "Quá hạn", "Bị chặn", "Mức tải"].map(esc).join(",")].concat(rows.map(({ m, w, ok, late }) =>
      [m.user.name, lookups.dept[m.department_id]?.code || "", ROLE[m.role], ok, late, w.open, w.late.length, w.blocked.length, ["Rảnh", "Vừa sức", "Bận", "Quá tải"][w.level]].map(esc).join(",")));
    const url = URL.createObjectURL(new Blob(["﻿" + lines.join("\n")], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a"); a.href = url; a.download = `kpi-${month.getFullYear()}-${String(month.getMonth() + 1).padStart(2, "0")}.csv`; a.click(); URL.revokeObjectURL(url);
  };
  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Nhân sự" sub="Tải công việc và cơ sở KPI. Mức tải = việc mở + 2 × quá hạn + 2 × bị chặn (≤2 Rảnh, ≤5 Vừa sức, ≤9 Bận, còn lại Quá tải)." />
      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={4} /> : (<>
        <div className="grid grid-cols-[repeat(auto-fill,minmax(170px,1fr))] gap-3">
          <Tile icon={Users} label="Tổng nhân sự" value={rows.length} />
          <Tile icon={Coffee} label="Đang rảnh" value={rows.filter((r) => r.w.level === 0).length} tone="var(--success)" />
          <Tile icon={Prohibit} label="Có việc bị chặn" value={rows.filter((r) => r.w.blocked.length).length} tone="var(--danger)" bad />
          <Tile icon={Hourglass} label="Có việc chậm tiến độ" value={rows.filter((r) => r.w.late.length).length} tone="var(--warning)" />
        </div>
        <Card title={`Việc hoàn thành theo người · tháng ${month.getMonth() + 1}`} aside={<Button size="sm" variant="secondary" onPress={exportCsv}><DownloadSimple size={15} />Xuất KPI</Button>}>
          {rows.filter((r) => r.done).sort((a, b) => b.done - a.done).map((r) => (
            <div key={r.m.user_id} className="flex flex-col gap-1"><div className="flex items-center justify-between text-sm"><Person user={r.m.user} /><span className="text-xs text-muted tabular-nums">{r.ok} đúng hạn · {r.late} trễ{r.pct != null && ` · ${r.pct}%`}</span></div>
              <div style={{ width: `${(100 * r.done) / maxDone}%`, minWidth: 24 }}><StackBar height={10} parts={[{ label: "Đúng hạn", value: r.ok, color: "var(--success)" }, { label: "Trễ", value: r.late, color: "var(--warning)" }]} /></div></div>))}
          {!rows.some((r) => r.done) && <p className="text-sm text-muted">Tháng này chưa có việc nào hoàn thành.</p>}
          <p className="text-xs text-faint">Việc giao cho agent AI không tính KPI. Đúng hạn = hoàn thành trước hoặc đúng ngày hạn chót (việc không có hạn tính là đúng hạn).</p>
        </Card>
        <div className="grid gap-3 [grid-template-columns:repeat(auto-fill,minmax(min(300px,100%),1fr))]">
          {rows.sort((a, b) => b.w.score - a.w.score).map(({ m, w, done, pct }) => (
            <Card key={m.user_id}>
              <div className="flex items-center gap-3"><Person user={m.user} size="md" showName={false} /><div className="min-w-0 flex-1"><b className="block truncate font-medium">{m.user.name}</b><span className="text-xs text-muted">{lookups.dept[m.department_id]?.code || "Chung"} · {ROLE[m.role]}</span></div></div>
              <LoadMeter level={w.level} />
              <p className="text-sm text-muted"><b className="font-medium text-foreground">{w.open}</b> đang mở · <b className="font-medium text-foreground">{done}</b> xong tháng này{pct != null && <> · <b className="font-medium text-foreground">{pct}%</b> đúng hạn</>}</p>
              {w.blocked.slice(0, 2).map((t) => <button key={t.id} type="button" onClick={() => openTask(t.id)} className="text-left text-[13px] text-danger hover:underline">Bị chặn: {t.title}</button>)}
              {w.late.slice(0, 2).map((t) => <button key={t.id} type="button" onClick={() => openTask(t.id)} className="text-left text-[13px] text-warning hover:underline">Chậm: {t.title}</button>)}
            </Card>))}
          {agents.map(({ a, running, waiting, done }) => (
            <Card key={a.code}>
              <AgentChip name={a.name} size={32} />
              <p className="text-sm text-muted"><b className="font-medium text-foreground">{running}</b> đang làm · <b className="font-medium text-foreground">{waiting}</b> chờ người · <b className="font-medium text-foreground">{done}</b> xong tháng này</p>
              <p className="text-xs text-faint">Agent AI: không tính KPI, không có mức tải.</p>
            </Card>))}
        </div>
      </>)}
    </div>
  );
}
