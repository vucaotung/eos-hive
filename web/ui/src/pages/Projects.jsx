import { Button } from "@heroui/react";
import { useApp, useLoad, go } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { isOpen, isOverdue } from "../lib/format.js";
import { Empty, ErrorBox, LoadingList, PageHeader } from "../components/ui.jsx";

// Danh sách dự án kèm số việc; bấm vào để xem việc của dự án
export default function Projects() {
  const { companyId, org, lookups, isAdmin, isManager } = useApp();
  const { data, error, loading } = useLoad(() => companyId ? rpc("app_tasks", { company_id: companyId, days: 60 }) : Promise.resolve([]), [companyId]);
  const rows = org.projects.map((p) => {
    const ts = (data || []).filter((t) => t.project_id === p.id);
    const open = ts.filter(isOpen).length, done = ts.filter((t) => t.status === "done").length;
    return { p, open, done, late: ts.filter(isOverdue).length, pct: ts.length ? Math.round((done / ts.length) * 100) : 0 };
  }).sort((a, b) => Number(b.p.active) - Number(a.p.active) || b.open - a.open);
  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Dự án" sub={`${org.projects.filter((p) => p.active).length} dự án đang thực hiện`}
        actions={(isAdmin || isManager) && <Button variant="secondary" onPress={() => go("admin")}>Quản lý dự án</Button>} />
      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={3} /> : rows.length ? (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {rows.map(({ p, open, done, late, pct }) => (
            <button key={p.id} type="button" onClick={() => go("tasks", { p: p.id })}
              className={`flex flex-col gap-3 rounded-xl bg-surface p-4 text-left hover:bg-surface-secondary ${p.active ? "" : "opacity-60"}`}>
              <span className="flex flex-col gap-0.5">
                <b className="text-lg font-extrabold leading-snug">{p.name}</b>
                <span className="text-sm text-muted">{lookups.dept[p.department_id]?.name || "Chung công ty"}{p.active ? "" : " · Đã đóng"}</span>
              </span>
              <span className="h-2.5 overflow-hidden rounded-full bg-surface-secondary" role="img" aria-label={`${pct}% việc đã xong`}>
                <span className="block h-full rounded-full bg-accent" style={{ width: `${pct}%` }} />
              </span>
              <span className="flex flex-wrap gap-x-4 text-sm"><span><b>{open}</b> đang mở</span>{late > 0 && <b className="text-danger">{late} quá hạn</b>}<span className="text-muted">{done} xong (60 ngày)</span></span>
            </button>
          ))}
        </div>
      ) : <Empty>Chưa có dự án. {(isAdmin || isManager) ? "Vào Quản lý dự án để thêm dự án đầu tiên." : "Nhờ quản trị hoặc trưởng phòng tạo dự án."}</Empty>}
    </div>
  );
}
