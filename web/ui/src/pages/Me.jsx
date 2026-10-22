import { Button, Card } from "@heroui/react";
import { Gear, ArrowRightFromSquare } from "@gravity-ui/icons";
import { useApp, go } from "../lib/store.jsx";
import { ROLE } from "../lib/format.js";
import { PageHeader, Person, SelectField } from "../components/ui.jsx";
import DriveSetup from "./DriveSetup.jsx";
import Connect from "../components/Connect.jsx";

export default function Me() {
  const { me, memberships, membership, switchCompany, signOut, theme, setTheme, isAdmin, isManager } = useApp();
  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Tài khoản" />
      <Card className="gap-4 p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-col gap-1"><Person user={me?.user} size="md" /><span className="text-sm text-muted">{me?.user?.email}</span></div>
          <Button variant="secondary" onPress={signOut}><ArrowRightFromSquare className="size-4" />Đăng xuất</Button>
        </div>
        <div className="flex flex-col gap-0.5 overflow-hidden rounded-lg">
          {memberships.map((m) => (
            <button key={m.company_id} type="button" onClick={() => switchCompany(m.company_id)}
              className={`flex flex-wrap items-center gap-x-4 gap-y-1 px-4 py-3 text-left ${m.company_id === membership?.company_id ? "bg-accent-soft" : "bg-surface-secondary hover:bg-surface-tertiary"}`}>
              <b className="min-w-0 flex-1">{m.company_name}</b>
              <span className="text-sm">{m.department_code ? `${m.department_code} · ${m.department_name}` : "Chung công ty"}</span>
              <span className="text-sm text-muted">{ROLE[m.role]}</span>
            </button>
          ))}
        </div>
        {(isAdmin || isManager) && <div className="lg:hidden"><Button variant="secondary" onPress={() => go("admin")}><Gear className="size-4" />Quản trị công ty</Button></div>}
        <div className="max-w-xs">
          <SelectField label="Giao diện" value={theme || "system"} onChange={(v) => setTheme(v === "system" ? "" : v)}
            options={[{ value: "system", label: "Theo thiết bị" }, { value: "light", label: "Sáng" }, { value: "dark", label: "Tối" }]} />
        </div>
      </Card>
      <DriveSetup />
      <Connect />
    </div>
  );
}
