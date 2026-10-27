import { useState } from "react";
import { Button, Dropdown, Label } from "@heroui/react";
import { CaretDown, MagnifyingGlass, Plus, DotsThree, CalendarCheck, FolderSimple, ListChecks } from "@phosphor-icons/react";
import { useApp, useLoad, go } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { ROLE } from "../lib/format.js";
import { Person } from "./ui.jsx";
import TaskForm from "./TaskForm.jsx";
import Logo from "./Logo.jsx";
import { NAV_GROUPS, ME_ITEM, isActive } from "./nav.js";

function CompanySwitcher() {
  const { memberships, membership, switchCompany } = useApp();
  if (!membership) return null;
  const chip = (
    <span className="flex min-w-0 items-center gap-2">
      <span className="grid size-6 shrink-0 place-items-center rounded-md border border-accent text-[10px] font-semibold text-act">{(membership.company_name || "?").slice(0, 2).toUpperCase()}</span>
      <span className="truncate text-sm font-medium">{membership.company_name}</span>
    </span>
  );
  if (memberships.length < 2) return <div className="flex min-w-0 items-center">{chip}</div>;
  return (
    <Dropdown>
      <Button variant="ghost" size="sm" className="max-w-full justify-start gap-2 px-2">{chip}<CaretDown size={14} className="shrink-0" /></Button>
      <Dropdown.Popover>
        <Dropdown.Menu aria-label="Chọn công ty" onAction={(k) => switchCompany(String(k))}>
          {memberships.map((m) => (
            <Dropdown.Item key={m.company_id} id={m.company_id} textValue={m.company_name}>
              <Label>{m.company_name} · {ROLE[m.role] || ""}</Label>
            </Dropdown.Item>
          ))}
        </Dropdown.Menu>
      </Dropdown.Popover>
    </Dropdown>
  );
}

function GlobalSearch() {
  const [q, setQ] = useState("");
  const submit = (e) => { e.preventDefault(); if (q.trim()) { go("tasks", { f: "open", q: q.trim() }); setQ(""); } };
  return (
    <form onSubmit={submit} role="search" className="relative hidden min-w-0 max-w-[460px] flex-1 md:block">
      <MagnifyingGlass size={16} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-faint" aria-hidden="true" />
      <input value={q} onChange={(e) => setQ(e.target.value)} aria-label="Tìm việc" placeholder="Tìm việc theo tên hoặc T-số…"
        className="h-9 w-full rounded-lg border border-border bg-surface pl-9 pr-3 text-sm placeholder:text-faint" />
    </form>
  );
}

export default function Shell({ children }) {
  const { route, me, membership, isAdmin, isManager, companyId } = useApp();
  const [creating, setCreating] = useState(false);
  const pending = useLoad(() => companyId ? rpc("app_my_approvals") : Promise.resolve({ items: [] }), [companyId]);
  const counts = { approvals: pending.data?.items?.length || 0 };
  const groups = NAV_GROUPS.map((g) => ({ ...g, items: g.items.filter((n) => !n.adminOnly || isAdmin || isManager) }));
  const page = route.page;
  const tabs = [
    { id: "today", label: "Hôm nay", icon: CalendarCheck, on: page === "today", href: "#/today" },
    { id: "tasks", label: "Việc", icon: ListChecks, on: page === "tasks", href: "#/tasks" },
    { id: "new" },
    { id: "projects", label: "Dự án", icon: FolderSimple, on: page === "projects", href: "#/projects" },
    { id: "more", label: "Thêm", icon: DotsThree, on: ["more", "approvals", "reports", "admin", "me"].includes(page), href: "#/more", dot: counts.approvals > 0 },
  ];

  return (
    <div className="min-h-dvh lg:pl-60">
      {/* Sidebar desktop 240px */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-60 flex-col gap-4 overflow-y-auto border-r border-separator bg-surface px-2.5 py-3 lg:flex">
        <div className="flex items-center gap-2.5 px-2 pb-1"><Logo className="size-9" /><span className="flex flex-col leading-tight"><span className="text-[15px] font-semibold tracking-tight">Enterprise OS</span><span className="text-[11px] text-faint">Giao việc & điều phối</span></span></div>
        <nav aria-label="Điều hướng chính" className="flex flex-col gap-4">
          {groups.map((g) => (
            <div key={g.title} className="flex flex-col gap-0.5">
              <h2 className="px-2.5 pb-1 text-[11px] font-medium uppercase tracking-[.06em] text-faint">{g.title}</h2>
              {g.items.map((n) => {
                const Icon = n.icon, active = isActive(n, route), badge = n.badge ? counts[n.badge] : 0;
                return (
                  <a key={n.id} href={`#/${n.page}${n.params ? `?${new URLSearchParams(n.params)}` : ""}`} aria-current={active ? "page" : undefined}
                    className={`flex h-[34px] items-center gap-2.5 rounded-lg px-2.5 text-[13.5px] transition-colors ${active ? "bg-accent-soft font-medium text-act shadow-[inset_2px_0_0_var(--accent)]" : "text-muted hover:bg-surface-secondary hover:text-foreground"}`}>
                    <Icon size={17} weight={active ? "fill" : "regular"} aria-hidden="true" />{n.label}
                    {badge > 0 && <span className="ml-auto inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-dg-bg px-1.5 text-[11px] font-semibold text-danger">{badge}</span>}
                  </a>
                );
              })}
            </div>
          ))}
        </nav>
        <div className="mt-auto flex flex-col gap-1 border-t border-separator pt-3">
          {(() => { const Icon = ME_ITEM.icon, active = page === "me"; return (
            <a href="#/me" aria-current={active ? "page" : undefined} className={`flex h-[34px] items-center gap-2.5 rounded-lg px-2.5 text-[13.5px] ${active ? "bg-accent-soft font-medium text-act shadow-[inset_2px_0_0_var(--accent)]" : "text-muted hover:bg-surface-secondary hover:text-foreground"}`}><Icon size={17} aria-hidden="true" />Tài khoản & cài đặt</a>); })()}
          <div className="flex items-center gap-2 px-2 py-1.5"><Person user={me?.user} /><span className="ml-auto text-xs text-faint">{ROLE[membership?.role] || ""}</span></div>
        </div>
      </aside>

      {/* Thanh trên: công ty · tìm kiếm · + Giao việc */}
      <header className="safe-t sticky top-0 z-20 border-b border-separator bg-background/90 backdrop-blur-[10px]">
        <div className="flex h-14 items-center gap-3 px-4 lg:px-7">
          <span className="flex items-center gap-2 lg:hidden"><Logo className="size-8" /></span>
          <div className="min-w-0 max-w-64"><CompanySwitcher /></div>
          <GlobalSearch />
          <div className="ml-auto hidden lg:block"><Button onPress={() => setCreating(true)}><Plus size={16} weight="bold" />Giao việc</Button></div>
          <a href="#/me" className="hidden size-8 lg:block" aria-label="Tài khoản"><Person user={me?.user} showName={false} /></a>
        </div>
      </header>

      <main id="main" className="mx-auto w-full max-w-[1400px] px-4 pb-28 pt-5 sm:px-6 lg:px-7 lg:pb-16">
        {children}
      </main>

      {/* Tab dưới mobile: 5 mục, ở giữa là nút tạo nhanh (viền màu nhấn) */}
      <nav aria-label="Điều hướng chính" className="safe-b fixed inset-x-0 bottom-0 z-20 border-t border-separator bg-surface lg:hidden">
        <div className="grid h-14 grid-cols-5">
          {tabs.map((t) => {
            if (t.id === "new") return (
              <button key="new" type="button" aria-label="Giao việc nhanh" onClick={() => setCreating(true)} className="flex items-center justify-center">
                <span className="grid h-11 w-[52px] place-items-center rounded-xl text-act" style={{ boxShadow: "inset 0 0 0 1.5px var(--accent)" }}><Plus size={22} weight="bold" /></span>
              </button>);
            const Icon = t.icon;
            return (
              <a key={t.id} href={t.href} aria-current={t.on ? "page" : undefined} className={`relative flex flex-col items-center justify-center gap-0.5 text-[11px] font-medium ${t.on ? "text-act" : "text-muted"}`}>
                <Icon size={22} weight={t.on ? "fill" : "regular"} aria-hidden="true" />{t.label}
                {t.dot && <span className="absolute right-[30%] top-2 size-2 rounded-full bg-danger" aria-label="Có việc chờ duyệt" />}
              </a>
            );
          })}
        </div>
      </nav>

      <TaskForm isOpen={creating} onClose={() => setCreating(false)} />
    </div>
  );
}

export { go };
