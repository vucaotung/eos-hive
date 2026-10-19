import { useState } from "react";
import { Button, Dropdown, Label } from "@heroui/react";
import { Calendar, ListUl, SealCheck, ChartColumn, Gear, Person as PersonIcon, Plus, Factory, ChevronDown } from "@gravity-ui/icons";
import { useApp, useLoad, go } from "../lib/store.jsx";
import { api, qs } from "../lib/api.js";
import { ROLE } from "../lib/format.js";
import { Person } from "./ui.jsx";
import TaskForm from "./TaskForm.jsx";

const NAV = [
  { id: "today", label: "Hôm nay", icon: Calendar },
  { id: "tasks", label: "Việc", icon: ListUl },
  { id: "approvals", label: "Duyệt", icon: SealCheck, badge: true },
  { id: "reports", label: "Báo cáo", icon: ChartColumn },
  { id: "admin", label: "Quản trị", icon: Gear, adminOnly: true },
  { id: "me", label: "Tài khoản", icon: PersonIcon },
];

function Mark() {
  return (
    <svg viewBox="0 0 32 32" className="size-7 shrink-0" aria-hidden="true">
      <rect x="3" y="3" width="26" height="26" rx="7" fill="var(--seal)" />
      <path d="M10 16.5l4 4 8-9" fill="none" stroke="#fff" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function CompanySwitcher() {
  const { memberships, membership, switchCompany } = useApp();
  if (!membership) return null;
  if (memberships.length < 2) {
    return <div className="flex min-w-0 items-center gap-2 text-sm text-muted"><Factory className="size-4 shrink-0" /><span className="truncate">{membership.company_name}</span></div>;
  }
  return (
    <Dropdown>
      <Button variant="ghost" size="sm" className="max-w-full justify-start gap-2 px-2">
        <Factory className="size-4 shrink-0" /><span className="truncate">{membership.company_name}</span><ChevronDown className="size-3.5 shrink-0" />
      </Button>
      <Dropdown.Popover>
        <Dropdown.Menu aria-label="Chọn công ty" onAction={(k) => switchCompany(String(k))}>
          {memberships.map((m) => (
            <Dropdown.Item key={m.company_id} id={m.company_id} textValue={m.company_name}>
              <Label>{m.company_name}</Label>
            </Dropdown.Item>
          ))}
        </Dropdown.Menu>
      </Dropdown.Popover>
    </Dropdown>
  );
}

export default function Shell({ children }) {
  const { route, me, membership, isAdmin, isManager, companyId } = useApp();
  const [creating, setCreating] = useState(false);
  const pending = useLoad(() => companyId ? api(`/my_approvals${qs({ select: "task_id" })}`) : Promise.resolve([]), [companyId]);
  const nApprovals = pending.data?.length || 0;
  const items = NAV.filter((n) => !n.adminOnly || isAdmin || isManager);
  const mobileItems = items.filter((n) => n.id !== "admin");
  const page = route.page;

  return (
    <div className="min-h-dvh lg:pl-64">
      {/* Sidebar desktop */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-64 flex-col gap-6 bg-background px-3 py-5 lg:flex">
        <div className="flex items-center gap-2.5 px-2 text-lg font-extrabold tracking-tight"><Mark />Dẹo Work</div>
        <div className="px-1"><CompanySwitcher /></div>
        <Button className="mx-1 justify-center" onPress={() => setCreating(true)}><Plus className="size-4" />Giao việc</Button>
        <nav aria-label="Điều hướng chính" className="flex flex-col gap-0.5">
          {items.map((n) => {
            const Icon = n.icon, active = page === n.id;
            return (
              <a key={n.id} href={`#/${n.id}`} aria-current={active ? "page" : undefined}
                className={`flex h-11 items-center gap-3 rounded-lg px-3 font-semibold transition-colors ${active ? "bg-surface font-extrabold text-foreground" : "text-muted hover:bg-surface-secondary hover:text-foreground"}`}>
                <Icon className="size-5" />{n.label}
                {n.badge && nApprovals > 0 && <span className="ml-auto grid h-5 min-w-5 place-items-center rounded-full bg-danger px-1.5 text-xs font-extrabold text-danger-foreground">{nApprovals}</span>}
              </a>
            );
          })}
        </nav>
        <a href="#/me" className="mt-auto flex items-center gap-2 rounded-lg px-2 py-2 hover:bg-surface-secondary">
          <Person user={me?.user} />
          <span className="ml-auto text-xs text-muted">{ROLE[membership?.role] || ""}</span>
        </a>
      </aside>

      {/* Thanh trên mobile */}
      <header className="safe-t sticky top-0 z-20 bg-background lg:hidden">
        <div className="flex h-14 items-center gap-2 px-4">
          <Mark /><span className="font-extrabold tracking-tight">Dẹo Work</span>
          <div className="ml-2 min-w-0 flex-1"><CompanySwitcher /></div>
        </div>
      </header>

      <main id="main" className="mx-auto w-full max-w-7xl px-4 pb-28 pt-2 sm:px-6 lg:px-10 lg:pb-16 lg:pt-8">
        {children}
      </main>

      {/* Nút giao việc mobile */}
      <Button isIconOnly aria-label="Giao việc" className="fixed right-4 z-30 size-14 rounded-full lg:hidden" style={{ bottom: "calc(76px + env(safe-area-inset-bottom, 0px))" }} onPress={() => setCreating(true)}>
        <Plus className="size-6" />
      </Button>

      {/* Tab dưới mobile */}
      <nav aria-label="Điều hướng chính" className="safe-b fixed inset-x-0 bottom-0 z-20 bg-surface lg:hidden">
        <div className="grid h-16" style={{ gridTemplateColumns: `repeat(${mobileItems.length}, 1fr)` }}>
          {mobileItems.map((n) => {
            const Icon = n.icon, active = page === n.id || (n.id === "me" && page === "admin");
            return (
              <a key={n.id} href={`#/${n.id}`} aria-current={active ? "page" : undefined}
                className={`relative flex flex-col items-center justify-center gap-0.5 text-xs font-bold ${active ? "text-foreground" : "text-muted"}`}>
                {active && <span className="absolute inset-x-[30%] top-0 h-[3px] rounded-b bg-foreground" />}
                <Icon className="size-6" />{n.id === "me" ? "Tôi" : n.label}
                {n.badge && nApprovals > 0 && <span className="absolute left-1/2 top-2 ml-2 grid h-5 min-w-5 place-items-center rounded-full bg-danger px-1.5 text-[11px] font-extrabold text-danger-foreground">{nApprovals}</span>}
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
