import { useApp, useLoad } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { ErrorBox, LoadingList, PageHeader, Person, Section, Empty } from "../components/ui.jsx";

// Thanh ngang tỷ lệ: phần xong đúng hạn / xong trễ, dùng cùng một thang
function Meter({ value, max, tone = "bg-accent", label }) {
  const pct = max ? Math.round((value / max) * 100) : 0;
  return (
    <span className="flex items-center gap-2" role="img" aria-label={label}>
      <span className="h-2.5 flex-1 overflow-hidden rounded-full bg-surface-secondary"><span className={`block h-full rounded-full ${tone}`} style={{ width: `${pct}%` }} /></span>
    </span>
  );
}

export default function Reports() {
  const { companyId, lookups, isAdmin, membership } = useApp();
  const { data, error, loading } = useLoad(async () => {
    if (!companyId) return null;
    return rpc("app_report", { company_id: companyId });
  }, [companyId]);

  const depts = (data?.depts || []).map((r) => ({ ...r, d: lookups.dept[r.department_id] }))
    .sort((a, b) => (a.d?.code || "~").localeCompare(b.d?.code || "~"));
  const total = depts.reduce((s, r) => ({ open: s.open + r.open, overdue: s.overdue + r.overdue, done: s.done + r.done_30d, ontime: s.ontime + r.done_on_time_30d, review: s.review + r.in_review }),
    { open: 0, overdue: 0, done: 0, ontime: 0, review: 0 });
  const maxOpen = Math.max(1, ...depts.map((r) => r.open));
  const people = (data?.people || []).filter((p) => lookups.person[p.user_id]);
  const maxPerson = Math.max(1, ...people.map((p) => p.open));

  const stat = (n, label, tone = "") => (
    <div className="flex flex-col gap-0.5 rounded-xl bg-surface px-4 py-3">
      <b className={`text-3xl font-extrabold tracking-tight ${tone}`}>{n}</b><span className="text-sm font-semibold text-muted">{label}</span>
    </div>
  );

  return (
    <div className="flex flex-col gap-8">
      <PageHeader title="Báo cáo" sub={isAdmin ? `Toàn công ty ${membership?.company_name || ""}` : "Phòng ban của bạn và việc bạn tham gia"} />
      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={4} /> : (<>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {stat(total.open, "việc đang mở")}
          {stat(total.overdue, "quá hạn", total.overdue ? "text-danger" : "")}
          {stat(total.review, "chờ duyệt")}
          {stat(total.done ? `${Math.round((total.ontime / total.done) * 100)}%` : "–", `đúng hạn trong ${total.done} việc xong 30 ngày`)}
        </div>

        <Section title="Theo phòng ban">
          {depts.length ? (
            <div className="overflow-x-auto rounded-xl bg-surface">
              <table className="w-full min-w-[640px] text-left">
                <thead className="text-sm text-muted">
                  <tr><th className="px-4 py-3 font-semibold">Phòng ban</th><th className="px-3 py-3 font-semibold">Đang mở</th><th className="w-[28%] px-3 py-3"><span className="sr-only">Biểu đồ</span></th>
                    <th className="px-3 py-3 font-semibold">Quá hạn</th><th className="px-3 py-3 font-semibold">Vướng</th><th className="px-3 py-3 font-semibold">Chờ duyệt</th>
                    <th className="px-3 py-3 font-semibold">Xong 30 ngày</th><th className="px-4 py-3 font-semibold">Ngày làm TB</th></tr>
                </thead>
                <tbody>
                  {depts.map((r) => (
                    <tr key={r.department_id || "none"} className="border-t-2 border-background">
                      <td className="px-4 py-3 font-semibold">{r.d ? `${r.d.code} · ${r.d.name}` : "Chung công ty"}</td>
                      <td className="px-3 py-3 font-extrabold">{r.open}</td>
                      <td className="px-3 py-3"><Meter value={r.open} max={maxOpen} label={`${r.open} việc mở`} /></td>
                      <td className={`px-3 py-3 ${r.overdue ? "font-extrabold text-danger" : "text-muted"}`}>{r.overdue}</td>
                      <td className={`px-3 py-3 ${r.blocked ? "font-semibold text-warning" : "text-muted"}`}>{r.blocked}</td>
                      <td className="px-3 py-3">{r.in_review}</td>
                      <td className="px-3 py-3">{r.done_30d}{r.done_30d > 0 && <span className="ml-1 text-sm text-muted">({Math.round((r.done_on_time_30d / r.done_30d) * 100)}% đúng hạn)</span>}</td>
                      <td className="px-4 py-3 text-muted">{r.avg_days_30d ?? "–"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <Empty>Chưa có việc nào để báo cáo.</Empty>}
        </Section>

        <Section title="Theo người">
          {people.length ? (
            <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
              {people.map((p) => (
                <div key={p.user_id} className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-4 gap-y-1.5 bg-surface px-4 py-3 sm:grid-cols-[minmax(0,14rem)_minmax(0,1fr)_auto]">
                  <Person user={lookups.person[p.user_id]} />
                  <span className="order-3 col-span-2 sm:order-none sm:col-span-1"><Meter value={p.open} max={maxPerson} label={`${p.open} việc mở`} /></span>
                  <span className="whitespace-nowrap text-sm"><b className="text-base">{p.open}</b> mở{p.overdue > 0 && <b className="ml-2 text-danger">{p.overdue} quá hạn</b>}<span className="ml-2 text-muted">{p.done_30d} xong</span></span>
                </div>
              ))}
            </div>
          ) : <Empty>Chưa có việc nào được giao cho người cụ thể.</Empty>}
        </Section>
      </>)}
    </div>
  );
}
