import { Button, Card } from "@heroui/react";
import { Gear, ArrowRightFromSquare } from "@gravity-ui/icons";
import { useApp, go } from "../lib/store.jsx";
import { ROLE } from "../lib/format.js";
import { PageHeader, Person, SelectField, TextInput } from "../components/ui.jsx";
import { ACCENTS } from "../lib/accent.js";
import ChecklistTemplates from "../components/ChecklistTemplates.jsx";
import DriveSetup from "./DriveSetup.jsx";
import Connect from "../components/Connect.jsx";

export default function Me() {
  const { me, memberships, membership, switchCompany, signOut, theme, setTheme, isAdmin, isManager, settings, setSetting } = useApp();
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
      </Card>
      <Card className="gap-5 p-5">
        <h2 className="text-lg font-medium">Giao diện</h2>
        <div className="max-w-xs">
          <SelectField label="Chế độ" value={theme || "system"} onChange={(v) => setTheme(v === "system" ? "" : v)}
            options={[{ value: "system", label: "Theo thiết bị" }, { value: "light", label: "Sáng" }, { value: "dark", label: "Tối" }]} />
        </div>
        <fieldset className="flex flex-col gap-2"><legend className="text-sm font-medium">Màu chủ đạo</legend>
          <div className="flex flex-wrap gap-3" role="radiogroup" aria-label="Màu chủ đạo">
            {Object.entries(ACCENTS).map(([k, a]) => (
              <button key={k} type="button" role="radio" aria-checked={settings.accent === k} aria-label={a.label} onClick={() => setSetting("accent", k)} className="flex flex-col items-center gap-1 text-xs text-muted">
                <span className="size-8 rounded-full" style={{ background: a.swatch, boxShadow: settings.accent === k ? "0 0 0 2px var(--background), 0 0 0 4px var(--foreground)" : "inset 0 0 0 1px var(--border)" }} />{a.label}
              </button>
            ))}
          </div>
          <p className="text-xs text-muted">Các màu thay thế đã đo tương phản WCAG AA (thấp nhất 5,42:1) ở cả chế độ sáng và tối.</p>
        </fieldset>
        <fieldset className="flex flex-col gap-2"><legend className="text-sm font-medium">Mật độ danh sách</legend>
          <div className="flex gap-1" role="radiogroup" aria-label="Mật độ">
            {[["normal", "Vừa"], ["compact", "Gọn"]].map(([k, l]) => <Button key={k} size="sm" variant={settings.density === k ? "primary" : "secondary"} role="radio" aria-checked={settings.density === k} onPress={() => setSetting("density", k)}>{l}</Button>)}
          </div>
        </fieldset>
      </Card>
      <Card className="gap-3 p-5">
        <h2 className="text-lg font-medium">Mục tiêu</h2>
        <div className="max-w-xs"><TextInput label="Mục tiêu hoàn thành mỗi tuần (việc)" type="number" value={String(settings.weeklyGoal)} onChange={(v) => setSetting("weeklyGoal", Math.min(60, Math.max(5, Number(v) || 5)))} description="5 đến 60. Dùng ở màn Tổng quan (lưu trên thiết bị này)." /></div>
      </Card>

      {(isAdmin || isManager) && <ChecklistTemplates />}
      <DriveSetup />
      <Connect />
    </div>
  );
}
