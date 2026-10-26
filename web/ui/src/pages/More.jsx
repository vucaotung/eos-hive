import { useApp, useLoad } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { ROLE } from "../lib/format.js";
import { PageHeader, Person } from "../components/ui.jsx";
import { NAV_GROUPS, ME_ITEM } from "../components/nav.js";

// Màn "Thêm" của mobile (M9): hồ sơ ở đầu, rồi ba nhóm như sidebar web, mỗi mục 48px. Nhóm Quản lý hiện theo vai trò.
export default function More() {
  const { me, membership, memberships, switchCompany, isAdmin, isManager, companyId } = useApp();
  const pending = useLoad(() => companyId ? rpc("app_my_approvals") : Promise.resolve({ items: [] }), [companyId]);
  const counts = { approvals: pending.data?.items?.length || 0 };
  const groups = NAV_GROUPS.map((g) => ({ ...g, items: g.items.filter((n) => !n.adminOnly || isAdmin || isManager) }));
  const row = "flex h-12 items-center gap-3 border-t border-separator bg-surface px-4 first:border-t-0 hover:bg-surface-secondary";
  return (
    <div className="flex flex-col gap-5">
      <PageHeader title="Thêm" />
      <a href="#/me" className="flex items-center gap-3 rounded-[14px] bg-surface p-4" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
        <Person user={me?.user} size="md" /><span className="ml-auto text-sm text-muted">{ROLE[membership?.role] || ""}</span>
      </a>
      {memberships.length > 1 && (
        <div className="flex flex-col gap-1.5"><h2 className="px-1 text-[11px] font-medium uppercase tracking-[.06em] text-faint">Công ty</h2>
          <div className="overflow-hidden rounded-[14px]" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
            {memberships.map((m) => <button key={m.company_id} type="button" onClick={() => switchCompany(m.company_id)} className={`${row} w-full text-left`}>
              <span className="min-w-0 flex-1 truncate">{m.company_name}</span><span className="text-sm text-muted">{ROLE[m.role]}</span>{m.company_id === membership?.company_id && <span className="text-act">✓</span>}</button>)}
          </div></div>
      )}
      {[...groups, { title: "Tài khoản", items: [ME_ITEM] }].map((g) => (
        <div key={g.title} className="flex flex-col gap-1.5"><h2 className="px-1 text-[11px] font-medium uppercase tracking-[.06em] text-faint">{g.title}</h2>
          <div className="overflow-hidden rounded-[14px]" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
            {g.items.map((n) => { const Icon = n.icon, badge = n.badge ? counts[n.badge] : 0; return (
              <a key={n.id} href={`#/${n.page}${n.params ? `?${new URLSearchParams(n.params)}` : ""}`} className={row}>
                <Icon size={20} aria-hidden="true" className="text-muted" /><span className="flex-1">{n.label}</span>
                {badge > 0 && <span className="inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-dg-bg px-1.5 text-[11px] font-semibold text-danger">{badge}</span>}
              </a>); })}
          </div></div>
      ))}
    </div>
  );
}
