import { useEffect, useState } from "react";
import { Button, Modal, Switch, Tabs, toast } from "@heroui/react";
import { Plus, Pencil, TrashBin } from "@gravity-ui/icons";
import { useApp, useLoad } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { ROLE, DRIVE, ddmmyyyy, ago } from "../lib/format.js";
import { CopyButton, Empty, ErrorBox, PageHeader, Person, SelectField, TextInput } from "../components/ui.jsx";
import AgentAdmin from "../components/AgentAdmin.jsx";

function Dialog({ title, isOpen, onClose, onSave, busy, error, children, saveLabel = "Lưu" }) {
  return (
    <Modal.Backdrop isOpen={isOpen} onOpenChange={(o) => !o && onClose()}>
      <Modal.Container placement="auto" scroll="inside">
        <Modal.Dialog className="sm:max-w-lg">
          <Modal.CloseTrigger />
          <Modal.Header><Modal.Heading>{title}</Modal.Heading></Modal.Header>
          <Modal.Body><form className="flex flex-col gap-4" onSubmit={(e) => { e.preventDefault(); onSave(); }}>{children}<button type="submit" hidden /></form>
            {error && <div className="mt-4"><ErrorBox error={error} /></div>}</Modal.Body>
          <Modal.Footer><Button variant="secondary" onPress={onClose}>Hủy</Button><Button isPending={busy} onPress={onSave}>{saveLabel}</Button></Modal.Footer>
        </Modal.Dialog>
      </Modal.Container>
    </Modal.Backdrop>
  );
}

function useEditor(initial) {
  const [open, setOpen] = useState(false), [f, setF] = useState(initial), [busy, setBusy] = useState(false), [error, setError] = useState(null);
  return {
    open, f, busy, error, set: (k) => (v) => setF((s) => ({ ...s, [k]: v })),
    start: (v = initial) => { setF(v); setError(null); setOpen(true); }, close: () => setOpen(false),
    run: async (fn, ok) => { setBusy(true); setError(null); try { await fn(); toast.success(ok); setOpen(false); } catch (e) { setError(e); } finally { setBusy(false); } },
  };
}

const rowCls = "flex flex-wrap items-center gap-x-4 gap-y-1 bg-surface px-4 py-3";

function Departments() {
  const { companyId, org, loadOrg } = useApp();
  const ed = useEditor({ id: null, code: "", name: "", active: true });
  const counts = Object.fromEntries(org.departments.map((d) => [d.id, org.members.filter((m) => m.active && m.department_id === d.id).length]));
  return (
    <div className="flex flex-col gap-4">
      <div><Button onPress={() => ed.start()}><Plus className="size-4" />Thêm phòng ban</Button></div>
      {org.departments.length ? (
        <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
          {org.departments.map((d) => (
            <div key={d.id} className={rowCls}>
              <b className="w-14">{d.code}</b><span className="min-w-0 flex-1 font-semibold">{d.name}</span>
              <span className="text-sm text-muted">{counts[d.id] || 0} người</span>
              {!d.active && <span className="text-sm font-semibold text-warning">Ngừng dùng</span>}
              <Button size="sm" variant="ghost" onPress={() => ed.start({ id: d.id, code: d.code, name: d.name, active: d.active })}><Pencil className="size-4" />Sửa</Button>
            </div>
          ))}
        </div>
      ) : <Empty>Chưa có phòng ban. Thêm phòng ban đầu tiên để giao việc theo phòng.</Empty>}
      <Dialog title={ed.f.id ? "Sửa phòng ban" : "Thêm phòng ban"} isOpen={ed.open} onClose={ed.close} busy={ed.busy} error={ed.error}
        onSave={() => ed.run(async () => { await rpc("app_dept_save", { company_id: companyId, code: ed.f.code, name: ed.f.name, id: ed.f.id, active: ed.f.active }); await loadOrg(); }, "Đã lưu phòng ban")}>
        <TextInput label="Mã phòng" value={ed.f.code} onChange={ed.set("code")} isRequired description="Tối đa 12 ký tự, ví dụ A, KT, PHAPCHE. Dùng trong tên thư mục Drive." />
        <TextInput label="Tên phòng ban" value={ed.f.name} onChange={ed.set("name")} isRequired />
        {ed.f.id && <Switch isSelected={ed.f.active} onChange={ed.set("active")}><Switch.Content><Switch.Control><Switch.Thumb /></Switch.Control>Đang sử dụng</Switch.Content></Switch>}
      </Dialog>
    </div>
  );
}

function Members() {
  const { companyId, org, lookups, loadOrg, userId, role } = useApp();
  const ed = useEditor({});
  const [showOff, setShowOff] = useState(false);
  const list = org.members.filter((m) => showOff || m.active);
  const roles = Object.entries(ROLE).filter(([k]) => role === "owner" || k !== "owner").map(([value, label]) => ({ value, label }));
  return (
    <div className="flex flex-col gap-4">
      <Switch isSelected={showOff} onChange={setShowOff}><Switch.Content><Switch.Control><Switch.Thumb /></Switch.Control>Hiện cả người đã khóa</Switch.Content></Switch>
      <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
        {list.map((m) => (
          <div key={m.user_id} className={rowCls}>
            <span className="min-w-0 flex-1"><Person user={m.user} /></span>
            <span className="w-40 truncate text-sm text-muted">{m.user?.email}</span>
            <span className="w-28 text-sm">{lookups.dept[m.department_id]?.code ? `${lookups.dept[m.department_id].code} · ` : ""}{ROLE[m.role]}</span>
            <span className={`w-36 text-sm ${m.user?.drive_status === "ok" ? "text-success" : m.user?.drive_status === "error" ? "text-danger" : "text-muted"}`}>Drive: {DRIVE[m.user?.drive_status || "none"]}</span>
            {!m.active && <span className="text-sm font-semibold text-warning">Đã khóa</span>}
            {m.user_id !== userId && (role !== "admin" || m.role !== "owner") && (
              <Button size="sm" variant="ghost" onPress={() => ed.start({ user_id: m.user_id, name: m.user?.name, role: m.role, department_id: m.department_id, title: m.title || "", active: m.active })}><Pencil className="size-4" />Sửa</Button>
            )}
          </div>
        ))}
      </div>
      <Dialog title={`Sửa ${ed.f.name || ""}`} isOpen={ed.open} onClose={ed.close} busy={ed.busy} error={ed.error}
        onSave={() => ed.run(async () => { await rpc("app_member_set", { company_id: companyId, user_id: ed.f.user_id, role: ed.f.role, department_id: ed.f.department_id, title: ed.f.title, active: ed.f.active }); await loadOrg(); }, "Đã cập nhật thành viên")}>
        <SelectField label="Vai trò" value={ed.f.role} onChange={ed.set("role")} options={roles} />
        <SelectField label="Phòng ban" value={ed.f.department_id} onChange={ed.set("department_id")} allowEmpty emptyLabel="Chung công ty" options={org.departments.map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
        <TextInput label="Chức danh" value={ed.f.title} onChange={ed.set("title")} placeholder="Ví dụ: Chuyên viên pháp lý" />
        <Switch isSelected={ed.f.active} onChange={ed.set("active")}><Switch.Content><Switch.Control><Switch.Thumb /></Switch.Control>Còn làm việc trong công ty (tắt để khóa truy cập)</Switch.Content></Switch>
      </Dialog>
    </div>
  );
}

function Invites() {
  const { companyId, org, lookups, role, membership, version } = useApp();
  const mgr = role === "manager";
  const init = { role: "member", department_id: mgr ? membership?.department_id : null, email: "", max_uses: "1", days: "7", note: "" };
  const ed = useEditor(init);
  const [created, setCreated] = useState(null);
  const [tick, setTick] = useState(0);
  const { data, error } = useLoad(() => rpc("app_invites", { company_id: companyId }), [companyId, tick]);
  const link = (code) => `${location.origin}/app/#/login?code=${code}`;
  const roles = Object.entries(ROLE).filter(([k]) => (role === "owner" ? true : role === "admin" ? k !== "owner" : k === "member")).map(([value, label]) => ({ value, label }));
  const state = (i) => i.revoked ? ["Đã thu hồi", "text-muted"] : new Date(i.expires_at) < new Date() ? ["Hết hạn", "text-muted"] : i.uses >= i.max_uses ? ["Đã dùng hết", "text-muted"] : ["Còn dùng được", "text-success"];
  return (
    <div className="flex flex-col gap-4">
      <div><Button onPress={() => { ed.start(init); }}><Plus className="size-4" />Tạo mã mời</Button></div>
      {created && (
        <div className="flex flex-col gap-3 rounded-xl bg-accent-soft p-4">
          <p className="font-semibold">Mã mời mới, gửi trực tiếp cho người được mời:</p>
          <div className="flex flex-wrap items-center gap-3">
            <code className="rounded-lg bg-surface px-3 py-2 text-2xl font-extrabold tracking-[.2em]">{created.code}</code>
            <CopyButton text={created.code} label="Sao chép mã" />
            <CopyButton text={link(created.code)} label="Sao chép link mời" />
          </div>
          <p className="text-sm text-muted">Người nhận mở link, đăng nhập bằng Google, mã được điền sẵn. {created.email ? `Chỉ ${created.email} dùng được.` : ""} Hết hạn {ddmmyyyy(new Date(created.expires_at))}.</p>
        </div>
      )}
      <ErrorBox error={error} />
      {data?.length ? (
        <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
          {data.map((i) => { const [s, tone] = state(i); return (
            <div key={i.code} className={rowCls}>
              <code className="w-28 font-bold tracking-wider">{i.code}</code>
              <span className="w-36 text-sm">{ROLE[i.role]}{i.department_id && lookups.dept[i.department_id] ? ` · ${lookups.dept[i.department_id].code}` : ""}</span>
              <span className="min-w-0 flex-1 truncate text-sm text-muted">{i.email || i.note || "Ai có mã đều dùng được"}</span>
              <span className="text-sm text-muted">{i.uses}/{i.max_uses} lượt</span>
              <span className={`w-28 text-sm font-semibold ${tone}`}>{s}</span>
              {s === "Còn dùng được" && <Button size="sm" variant="ghost" onPress={async () => { try { await rpc("app_invite_revoke", { code: i.code }); toast.success("Đã thu hồi mã"); setTick((x) => x + 1); } catch (e) { toast.danger(e.message); } }}><TrashBin className="size-4" />Thu hồi</Button>}
            </div>); })}
        </div>
      ) : data && <Empty>Chưa có mã mời nào.</Empty>}
      <Dialog title="Tạo mã mời" isOpen={ed.open} onClose={ed.close} busy={ed.busy} error={ed.error} saveLabel="Tạo mã"
        onSave={() => ed.run(async () => {
          const inv = await rpc("app_invite_create", { company_id: companyId, role: ed.f.role, department_id: ed.f.department_id, email: ed.f.email || null,
            max_uses: Number(ed.f.max_uses) || 1, days: Number(ed.f.days) || 7, note: ed.f.note || null });
          setCreated(inv); setTick((x) => x + 1);
        }, "Đã tạo mã mời")}>
        <SelectField label="Vai trò khi vào" value={ed.f.role} onChange={ed.set("role")} options={roles} />
        <SelectField label="Phòng ban" value={ed.f.department_id} onChange={ed.set("department_id")} allowEmpty={!mgr} emptyLabel="Chung công ty"
          options={org.departments.filter((d) => !mgr || d.id === membership?.department_id).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
        <TextInput label="Chỉ dành cho email (không bắt buộc)" type="email" value={ed.f.email} onChange={ed.set("email")} placeholder="ten@gmail.com" description="Để trống nếu muốn gửi một mã cho nhiều người." />
        <div className="grid grid-cols-2 gap-3">
          <TextInput label="Số lượt dùng" type="number" value={ed.f.max_uses} onChange={ed.set("max_uses")} />
          <TextInput label="Hết hạn sau (ngày)" type="number" value={ed.f.days} onChange={ed.set("days")} />
        </div>
        <TextInput label="Ghi chú" value={ed.f.note} onChange={ed.set("note")} placeholder="Ví dụ: Nhân viên mới phòng kế toán" />
      </Dialog>
      <span hidden>{version}</span>
    </div>
  );
}

function Flows() {
  const { companyId, org, lookups, loadOrg } = useApp();
  const blankStep = () => ({ name: "", kind: "manager", user: null });
  const ed = useEditor({ id: null, name: "", department_id: null, steps: [blankStep()] });
  const setStep = (i, k, v) => ed.set("steps")(ed.f.steps.map((s, j) => (j === i ? { ...s, [k]: v } : s)));
  const people = org.members.filter((m) => m.active && m.user).map((m) => ({ value: m.user.id, label: m.user.name }));
  const describe = (s) => s.approver_user ? lookups.person[s.approver_user]?.name || "Một người" : s.approver_role === "manager" ? "Trưởng phòng của việc" : ROLE[s.approver_role];
  return (
    <div className="flex flex-col gap-4">
      <div><Button onPress={() => ed.start({ id: null, name: "", department_id: null, steps: [blankStep()] })}><Plus className="size-4" />Tạo quy trình</Button></div>
      {org.flows.length ? (
        <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
          {org.flows.map((fl) => (
            <div key={fl.id} className={rowCls}>
              <span className="min-w-0 flex-1">
                <b>{fl.name}</b><span className="ml-2 text-sm text-muted">{fl.department_id ? lookups.dept[fl.department_id]?.name : "Cả công ty"}</span>
                <span className="mt-1 flex flex-wrap gap-1.5 text-sm">{[...(fl.steps || [])].sort((a, b) => a.step_no - b.step_no).map((s) => (
                  <span key={s.step_no} className="rounded-full bg-surface-secondary px-2.5 py-0.5"><b>{s.step_no}</b> {s.name}: {describe(s)}</span>))}</span>
              </span>
              <Button size="sm" variant="ghost" onPress={() => ed.start({ id: fl.id, name: fl.name, department_id: fl.department_id,
                steps: [...fl.steps].sort((a, b) => a.step_no - b.step_no).map((s) => ({ name: s.name, kind: s.approver_user ? "user" : s.approver_role, user: s.approver_user })) })}><Pencil className="size-4" />Sửa</Button>
              <Button size="sm" variant="ghost" onPress={async () => { try { await rpc("app_flow_archive", { id: fl.id }); await loadOrg(); toast.success("Đã ngừng quy trình"); } catch (e) { toast.danger(e.message); } }}><TrashBin className="size-4" />Ngừng</Button>
            </div>
          ))}
        </div>
      ) : <Empty>Chưa có quy trình duyệt. Việc không gắn quy trình sẽ hoàn thành ngay khi người làm nộp kết quả.</Empty>}
      <Dialog title={ed.f.id ? "Sửa quy trình duyệt" : "Tạo quy trình duyệt"} isOpen={ed.open} onClose={ed.close} busy={ed.busy} error={ed.error}
        onSave={() => ed.run(async () => {
          const steps = ed.f.steps.map((s, i) => s.kind === "user" ? { name: s.name || `Bước ${i + 1}`, approver_user: s.user } : { name: s.name || `Bước ${i + 1}`, approver_role: s.kind });
          await rpc("app_flow_save", { company_id: companyId, name: ed.f.name, steps, department_id: ed.f.department_id, id: ed.f.id }); await loadOrg();
        }, "Đã lưu quy trình")}>
        <TextInput label="Tên quy trình" value={ed.f.name} onChange={ed.set("name")} isRequired placeholder="Ví dụ: Văn bản gửi cơ quan nhà nước" />
        <SelectField label="Áp dụng cho" value={ed.f.department_id} onChange={ed.set("department_id")} allowEmpty emptyLabel="Cả công ty" options={org.departments.map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
        <ol className="flex flex-col gap-3">
          {ed.f.steps.map((s, i) => (
            <li key={i} className="flex flex-col gap-2 rounded-lg bg-surface-secondary p-3">
              <div className="flex items-center justify-between"><b>Bước {i + 1}</b>
                {ed.f.steps.length > 1 && <Button size="sm" variant="ghost" onPress={() => ed.set("steps")(ed.f.steps.filter((_, j) => j !== i))}>Bỏ bước</Button>}</div>
              <TextInput label="Tên bước" value={s.name} onChange={(v) => setStep(i, "name", v)} placeholder={i === 0 ? "Trưởng phòng duyệt" : "Giám đốc duyệt"} />
              <SelectField label="Người duyệt" value={s.kind} onChange={(v) => setStep(i, "kind", v)}
                options={[{ value: "manager", label: "Trưởng phòng của việc" }, { value: "admin", label: "Quản trị công ty" }, { value: "owner", label: "Chủ sở hữu" }, { value: "user", label: "Một người cụ thể" }]} />
              {s.kind === "user" && <SelectField label="Chọn người" value={s.user} onChange={(v) => setStep(i, "user", v)} options={people} />}
            </li>
          ))}
        </ol>
        {ed.f.steps.length < 6 && <Button variant="secondary" onPress={() => ed.set("steps")([...ed.f.steps, blankStep()])}><Plus className="size-4" />Thêm bước</Button>}
      </Dialog>
    </div>
  );
}

function Projects() {
  const { companyId, org, lookups, loadOrg } = useApp();
  const ed = useEditor({ id: null, slug: "", name: "", department_id: null, drive_url: "", active: true });
  const slugify = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/gi, "d").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return (
    <div className="flex flex-col gap-4">
      <div><Button onPress={() => ed.start()}><Plus className="size-4" />Thêm dự án</Button></div>
      {org.projects.length ? (
        <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
          {org.projects.map((p) => (
            <div key={p.id} className={rowCls}>
              <span className="min-w-0 flex-1"><b>{p.name}</b><span className="ml-2 text-sm text-muted">{p.slug}</span></span>
              <span className="text-sm text-muted">{lookups.dept[p.department_id]?.code || "Chung"}</span>
              {p.drive_url && <a className="text-sm font-semibold text-accent hover:underline" href={p.drive_url} target="_blank" rel="noopener noreferrer">Thư mục Drive</a>}
              {!p.active && <span className="text-sm font-semibold text-warning">Đã đóng</span>}
              <Button size="sm" variant="ghost" onPress={() => ed.start({ id: p.id, slug: p.slug, name: p.name, department_id: p.department_id, drive_url: p.drive_url || "", active: p.active })}><Pencil className="size-4" />Sửa</Button>
            </div>
          ))}
        </div>
      ) : <Empty>Chưa có dự án.</Empty>}
      <Dialog title={ed.f.id ? "Sửa dự án" : "Thêm dự án"} isOpen={ed.open} onClose={ed.close} busy={ed.busy} error={ed.error}
        onSave={() => ed.run(async () => { await rpc("app_project_save", { company_id: companyId, slug: ed.f.slug || slugify(ed.f.name), name: ed.f.name, department_id: ed.f.department_id, drive_url: ed.f.drive_url, id: ed.f.id, active: ed.f.active }); await loadOrg(); }, "Đã lưu dự án")}>
        <TextInput label="Tên dự án" value={ed.f.name} onChange={(v) => { ed.set("name")(v); if (!ed.f.id) ed.set("slug")(slugify(v)); }} isRequired />
        <TextInput label="Mã dự án" value={ed.f.slug} onChange={ed.set("slug")} description="Chữ thường, số và gạch nối. Dùng chung với Drive và kho tri thức." />
        <SelectField label="Phòng ban" value={ed.f.department_id} onChange={ed.set("department_id")} allowEmpty emptyLabel="Chung công ty" options={org.departments.map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
        <TextInput label="Thư mục Drive của dự án" type="url" value={ed.f.drive_url} onChange={ed.set("drive_url")} placeholder="https://drive.google.com/drive/folders/..." />
        {ed.f.id && <Switch isSelected={ed.f.active} onChange={ed.set("active")}><Switch.Content><Switch.Control><Switch.Thumb /></Switch.Control>Đang thực hiện</Switch.Content></Switch>}
      </Dialog>
    </div>
  );
}

export default function Admin() {
  const { isAdmin, isManager, isSystemAdmin, membership } = useApp();
  const tabs = [
    isAdmin && ["members", "Thành viên", Members],
    (isAdmin || isManager) && ["invites", "Mã mời", Invites],
    isAdmin && ["departments", "Phòng ban", Departments],
    isAdmin && ["flows", "Quy trình duyệt", Flows],
    (isAdmin || isManager) && ["projects", "Dự án", Projects],
    isSystemAdmin && ["agents", "Agent và MCP", AgentAdmin],
  ].filter(Boolean);
  const [tab, setTab] = useState(tabs[0]?.[0]);
  useEffect(() => { if (!tabs.find((t) => t[0] === tab)) setTab(tabs[0]?.[0]); }, [tabs, tab]);
  if (!tabs.length) return <Empty>Bạn không có quyền quản trị trong công ty này.</Empty>;
  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Quản trị" sub={membership?.company_name} />
      <Tabs selectedKey={tab} onSelectionChange={(k) => setTab(String(k))} className="w-full">
        <Tabs.ListContainer className="no-scrollbar overflow-x-auto">
          <Tabs.List aria-label="Mục quản trị">
            {tabs.map(([k, label]) => <Tabs.Tab key={k} id={k}>{label}<Tabs.Indicator /></Tabs.Tab>)}
          </Tabs.List>
        </Tabs.ListContainer>
        {tabs.map(([k, , C]) => <Tabs.Panel key={k} id={k} className="pt-5"><C /></Tabs.Panel>)}
      </Tabs>
    </div>
  );
}

export { ago };
