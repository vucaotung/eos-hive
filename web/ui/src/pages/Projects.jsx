import { useState } from "react";
import { Button, Modal, Tabs, toast } from "@heroui/react";
import { Plus, Pencil, TrashBin, FaceRobot } from "@gravity-ui/icons";
import { useApp, useLoad, go } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { ddmmyyyy, isOpen, isOverdue, parseDate } from "../lib/format.js";
import { Empty, ErrorBox, LoadingList, PageHeader, Person, SelectField, TextAreaInput, TextInput } from "../components/ui.jsx";

const STATUS = { planned: "Dự kiến", active: "Đang thực hiện", paused: "Tạm dừng", done: "Hoàn thành", cancelled: "Đã hủy" };
const PROJECT_ROLE = { manager: "Quản lý", member: "Thành viên", viewer: "Người xem" };
const slugify = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/gi, "d").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const blank = { id: null, name: "", slug: "", department_id: null, manager_id: null, status: "active", start_date: "", end_date: "", drive_url: "", description: "" };

// Hộp thoại một dự án: Thông tin (tạo/sửa/xóa) và Thành viên
function ProjectDialog({ project, isOpen, onClose }) {
  const { companyId, org, lookups, loadOrg, role, membership, refresh, userId } = useApp();
  const creating = !project?.id;
  const [f, setF] = useState(blank);
  const [seeded, setSeeded] = useState(null);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState(null);
  const [tab, setTab] = useState("info");
  const [add, setAdd] = useState({ user_id: null, role: "member" });
  if (isOpen && seeded !== (project?.id || "new")) {                       // nạp lại biểu mẫu mỗi lần mở dự án khác
    setSeeded(project?.id || "new"); setError(null); setTab("info"); setAdd({ user_id: null, role: "member" });
    setF(project?.id ? { id: project.id, name: project.name, slug: project.slug, department_id: project.department_id, manager_id: project.manager_id, status: project.status,
      start_date: project.start_date || "", end_date: project.end_date || "", drive_url: project.drive_url || "", description: project.description || "" }
      : { ...blank, department_id: role === "manager" ? membership?.department_id : null, manager_id: userId });
  }
  if (!isOpen && seeded) setSeeded(null);
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));
  const people = org.members.filter((m) => m.active && m.user).map((m) => ({ value: m.user.id, label: m.user.name }));
  const members = org.project_members.filter((m) => m.project_id === project?.id);
  const canDelete = !creating && (role === "owner" || role === "admin" || (role === "manager" && project.department_id === membership?.department_id));
  const canDept = role === "owner" || role === "admin" || role === "manager";
  const run = (name, fn, ok) => async () => { setBusy(name); setError(null); try { await fn(); if (ok) toast.success(ok); } catch (e) { setError(e); } finally { setBusy(""); } };

  const save = run("save", async () => {
    await rpc("app_project_save", { company_id: companyId, ...f, slug: f.slug || slugify(f.name), department_id: f.department_id || "", manager_id: f.manager_id || "" });
    await loadOrg(); refresh(); onClose();
  }, creating ? "Đã tạo dự án" : "Đã lưu dự án");
  const del = run("del", async () => {
    if (!confirm(`Xóa dự án "${project.name}"? Các việc của dự án vẫn còn, chỉ không thuộc dự án nào nữa. Không hoàn tác được.`)) return;
    const r = await rpc("app_project_delete", { id: project.id }); await loadOrg(); refresh(); onClose(); toast.success(`Đã xóa dự án${r.tasks_unlinked ? `, ${r.tasks_unlinked} việc đã bỏ liên kết` : ""}`);
  });
  const setMember = (user_id, r) => run("m" + user_id, async () => { await rpc("app_project_member_set", { project_id: project.id, user_id, role: r }); await loadOrg(); }, "Đã cập nhật thành viên dự án")();
  const rmMember = (user_id) => run("m" + user_id, async () => { await rpc("app_project_member_remove", { project_id: project.id, user_id }); await loadOrg(); }, "Đã gỡ khỏi dự án")();

  const info = (
    <form className="grid gap-4 sm:grid-cols-2" onSubmit={(e) => { e.preventDefault(); save(); }}>
      <div className="sm:col-span-2"><TextInput label="Tên dự án" value={f.name} onChange={(v) => { set("name")(v); if (creating) set("slug")(slugify(v)); }} isRequired /></div>
      <TextInput label="Mã dự án" value={f.slug} onChange={set("slug")} description="Chữ thường, số, gạch nối. Dùng chung với Drive và kho tri thức." />
      <SelectField label="Trạng thái" value={f.status} onChange={set("status")} options={Object.entries(STATUS).map(([value, label]) => ({ value, label }))} />
      <SelectField label="Phòng ban" value={f.department_id} onChange={set("department_id")} allowEmpty={role !== "manager"} emptyLabel="Chung công ty"
        options={org.departments.filter((d) => d.active && (role !== "manager" || d.id === membership?.department_id)).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
      <SelectField label="Người quản lý dự án" value={f.manager_id} onChange={set("manager_id")} allowEmpty emptyLabel="Chưa có" options={people} />
      <TextInput label="Bắt đầu" type="date" value={f.start_date} onChange={set("start_date")} />
      <TextInput label="Kết thúc dự kiến" type="date" value={f.end_date} onChange={set("end_date")} />
      <div className="sm:col-span-2"><TextInput label="Thư mục Drive của dự án" type="url" value={f.drive_url} onChange={set("drive_url")} placeholder="https://drive.google.com/drive/folders/..." /></div>
      <div className="sm:col-span-2"><TextAreaInput label="Mô tả" value={f.description} onChange={set("description")} rows={3} placeholder="Mục tiêu, phạm vi, đối tác" /></div>
      <button type="submit" hidden />
    </form>
  );
  const memberTab = (
    <div className="flex flex-col gap-4">
      {members.length ? (
        <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
          {members.map((m) => (
            <div key={m.user_id} className="flex flex-wrap items-center gap-3 bg-surface-secondary px-4 py-2.5">
              <span className="min-w-0 flex-1"><Person user={lookups.person[m.user_id]} /></span>
              {m.user_id === project.manager_id
                ? <span className="text-sm font-semibold">Quản lý</span>
                : <>
                  <SelectField className="w-36" label="Vai trò" value={m.role} onChange={(v) => v && v !== m.role && setMember(m.user_id, v)} options={["member", "viewer"].map((value) => ({ value, label: PROJECT_ROLE[value] }))} />
                  <Button isIconOnly size="sm" variant="ghost" aria-label="Gỡ khỏi dự án" isPending={busy === "m" + m.user_id} onPress={() => rmMember(m.user_id)}><TrashBin className="size-4" /></Button>
                </>}
            </div>
          ))}
        </div>
      ) : <Empty>Dự án chưa có thành viên.</Empty>}
      <div className="grid items-end gap-3 sm:grid-cols-[1fr_9rem_auto]">
        <SelectField label="Thêm thành viên" value={add.user_id} onChange={(v) => setAdd({ ...add, user_id: v })} placeholder="Chọn người"
          options={people.filter((p) => !members.some((m) => m.user_id === p.value))} />
        <SelectField label="Vai trò" value={add.role} onChange={(v) => setAdd({ ...add, role: v })} options={Object.entries(PROJECT_ROLE).filter(([k]) => k !== "manager").map(([value, label]) => ({ value, label }))} />
        <Button isDisabled={!add.user_id} isPending={busy === "add"} onPress={run("add", async () => { await rpc("app_project_member_set", { project_id: project.id, user_id: add.user_id, role: add.role }); await loadOrg(); setAdd({ user_id: null, role: "member" }); }, "Đã thêm vào dự án")}>Thêm</Button>
      </div>
      <p className="text-sm text-muted">Người quản lý dự án đổi ở tab Thông tin.</p>
    </div>
  );

  return (
    <Modal.Backdrop isOpen={isOpen} onOpenChange={(o) => !o && onClose()}>
      <Modal.Container placement="auto" scroll="inside">
        <Modal.Dialog className="sm:max-w-2xl">
          <Modal.CloseTrigger />
          <Modal.Header><Modal.Heading>{creating ? "Thêm dự án" : project.name}</Modal.Heading></Modal.Header>
          <Modal.Body>
            {creating ? info : (
              <Tabs selectedKey={tab} onSelectionChange={(k) => setTab(String(k))}>
                <Tabs.ListContainer><Tabs.List aria-label="Cài đặt dự án">
                  <Tabs.Tab id="info">Thông tin<Tabs.Indicator /></Tabs.Tab><Tabs.Tab id="members">Thành viên ({members.length})<Tabs.Indicator /></Tabs.Tab>
                </Tabs.List></Tabs.ListContainer>
                <Tabs.Panel id="info" className="pt-4">{info}</Tabs.Panel>
                <Tabs.Panel id="members" className="pt-4">{memberTab}</Tabs.Panel>
              </Tabs>
            )}
            {error && <div className="mt-4"><ErrorBox error={error} /></div>}
          </Modal.Body>
          <Modal.Footer className="justify-between">
            {canDelete ? <Button variant="danger-soft" isPending={busy === "del"} onPress={del}><TrashBin className="size-4" />Xóa dự án</Button> : <span />}
            <span className="flex gap-2">
              <Button variant="secondary" onPress={onClose}>{tab === "members" && !creating ? "Đóng" : "Hủy"}</Button>
              {(creating || tab === "info") && <Button isPending={busy === "save"} isDisabled={!canDept && creating} onPress={save}>{creating ? "Tạo dự án" : "Lưu thay đổi"}</Button>}
            </span>
          </Modal.Footer>
        </Modal.Dialog>
      </Modal.Container>
    </Modal.Backdrop>
  );
}

// Bắt đầu quy trình nạp hồ sơ: dự án (mới hoặc có sẵn) + thư mục Drive + người theo dõi. Điều phối (Mai) sẽ chia việc cho các agent.
function IntakeDialog({ isOpen, onClose, project }) {
  const { companyId, org, refresh, loadOrg } = useApp();
  const [f, setF] = useState({ name: "", drive_url: "", supervisor_id: null, note: "" });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [seeded, setSeeded] = useState(false);
  if (isOpen && !seeded) { setSeeded(true); setError(null); setF({ name: "", drive_url: "", supervisor_id: project?.manager_id || null, note: "" }); }
  if (!isOpen && seeded) setSeeded(false);
  const people = org.members.filter((m) => m.active && m.user).map((m) => ({ value: m.user.id, label: m.user.name }));
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));
  async function start() {
    setBusy(true); setError(null);
    try {
      await rpc("app_workflow_start", { company_id: companyId, project_id: project?.id || "", project_name: f.name, drive_url: f.drive_url.trim(), supervisor_id: f.supervisor_id || "", note: f.note });
      await loadOrg(); refresh(); onClose(); toast.success("Đã giao Điều phối. Điều phối sẽ chia việc cho các agent trong ít phút");
    } catch (e) { setError(e); } finally { setBusy(false); }
  }
  return (
    <Modal.Backdrop isOpen={isOpen} onOpenChange={(o) => !o && onClose()}>
      <Modal.Container placement="auto" scroll="inside">
        <Modal.Dialog className="sm:max-w-xl">
          <Modal.CloseTrigger />
          <Modal.Header><Modal.Heading>{project ? `Nạp hồ sơ cho ${project.name}` : "Nạp hồ sơ dự án mới"}</Modal.Heading></Modal.Header>
          <Modal.Body>
            <form className="flex flex-col gap-4" onSubmit={(e) => { e.preventDefault(); start(); }}>
              <p className="text-muted">Điều phối đọc thư mục Drive, chia việc cho Runner Z2, Quản trị dữ liệu, Văn thư và Pháp chế theo kỹ năng, ghi phạm vi từng việc vào hệ thống. Người theo dõi là người phụ trách và duyệt mọi việc.</p>
              {!project && <TextInput label="Tên dự án" value={f.name} onChange={set("name")} isRequired placeholder="Ví dụ: Khu dân cư Thành Lập" />}
              <TextInput label="Link thư mục Drive chứa hồ sơ" type="url" value={f.drive_url} onChange={set("drive_url")} isRequired placeholder="https://drive.google.com/drive/folders/..."
                description="Thư mục phải chia sẻ quyền Người chỉnh sửa cho tài khoản Google của Runner (Markdown được đẩy vào thư mục con _md_deo)." />
              <SelectField label="Người theo dõi (người thật)" value={f.supervisor_id} onChange={set("supervisor_id")} options={people} isRequired />
              <TextAreaInput label="Chỉ đạo ban đầu (không bắt buộc)" value={f.note} onChange={set("note")} rows={3} placeholder="Ví dụ: ưu tiên hồ sơ pháp lý và hợp đồng; bỏ qua thư mục ARCHIVE" />
              <button type="submit" hidden />
            </form>
            {error && <div className="mt-4"><ErrorBox error={error} /></div>}
          </Modal.Body>
          <Modal.Footer><Button variant="secondary" onPress={onClose}>Hủy</Button>
            <Button isPending={busy} isDisabled={(!project && f.name.trim().length < 2) || !f.drive_url.trim() || !f.supervisor_id} onPress={start}>Bắt đầu nạp hồ sơ</Button></Modal.Footer>
        </Modal.Dialog>
      </Modal.Container>
    </Modal.Backdrop>
  );
}

// Kết quả của dự án: tiến độ từng việc và kết quả của agent, danh mục hồ sơ, báo cáo/tài liệu, kho tri thức
const money = (n) => (n == null ? "" : new Intl.NumberFormat("vi-VN").format(n) + " đ");
function ResultsDialog({ project, isOpen, onClose }) {
  const { openTask, lookups: lk } = useApp();
  const agentLabel = (c) => lk.agent[c]?.name || c;
  const { data, error, loading } = useLoad(() => (isOpen && project ? rpc("app_project_results", { project_id: project.id }) : Promise.resolve(null)), [isOpen, project?.id]);
  const [tab, setTab] = useState("overview");
  const [open, setOpen] = useState({});
  const D = data;
  const cats = []; (D?.records || []).forEach((r) => { let c = cats.find((x) => x.name === r.category); if (!c) cats.push(c = { name: r.category, items: [] }); c.items.push(r); });
  const ST = { todo: "Chờ làm", in_progress: "Đang làm", blocked: "Vướng", in_review: "Chờ duyệt", done: "Xong", cancelled: "Đã hủy" };
  const link = (u, t) => u ? <a href={u} target="_blank" rel="noopener noreferrer" className="font-semibold text-accent hover:underline">{t}</a> : null;
  return (
    <Modal.Backdrop isOpen={isOpen} onOpenChange={(o) => !o && onClose()}>
      <Modal.Container placement="auto" scroll="inside">
        <Modal.Dialog className="sm:max-w-4xl">
          <Modal.CloseTrigger />
          <Modal.Header><Modal.Heading>Kết quả: {project?.name}</Modal.Heading></Modal.Header>
          <Modal.Body>
            <ErrorBox error={error} />
            {loading && !D ? <LoadingList rows={3} /> : D && (
              <Tabs selectedKey={tab} onSelectionChange={(k) => setTab(String(k))}>
                <Tabs.ListContainer className="no-scrollbar overflow-x-auto"><Tabs.List aria-label="Kết quả dự án">
                  <Tabs.Tab id="overview">Tổng quan<Tabs.Indicator /></Tabs.Tab>
                  <Tabs.Tab id="records">Danh mục hồ sơ ({D.records.length})<Tabs.Indicator /></Tabs.Tab>
                  <Tabs.Tab id="files">Báo cáo và tài liệu ({D.files.length})<Tabs.Indicator /></Tabs.Tab>
                  <Tabs.Tab id="kb">Kho tri thức<Tabs.Indicator /></Tabs.Tab>
                </Tabs.List></Tabs.ListContainer>
                <Tabs.Panel id="overview" className="flex flex-col gap-4 pt-4">
                  <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                    {[[D.records.length, "hồ sơ trong danh mục"], [D.files.length, "báo cáo và tài liệu"], [D.kb?.sources ?? 0, "tài liệu trong kho tri thức"], [D.tasks.filter((t) => t.status === "done").length + "/" + D.tasks.length, "việc đã xong"]].map(([n, l]) => (
                      <div key={l} className="flex flex-col gap-0.5 rounded-xl bg-surface-secondary px-4 py-3"><b className="text-2xl font-semibold tracking-tight">{n}</b><span className="text-sm font-semibold text-muted">{l}</span></div>
                    ))}
                  </div>
                  {D.run && <p className="flex flex-wrap gap-x-4 text-sm text-muted">{link(D.run.source_url, "Thư mục Drive nguồn")}{link(D.run.md_url, "Thư mục Markdown")}</p>}
                  {D.tasks.length ? D.tasks.map((t) => (
                    <section key={t.id} className="flex flex-col gap-2 rounded-xl bg-surface-secondary p-4">
                      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
                        <b className="min-w-0 flex-1 [overflow-wrap:anywhere]">{t.title}</b>
                        <span className="text-sm font-semibold">{ST[t.status]}</span>
                        <span className="text-sm text-muted">{t.agent ? `Agent ${agentLabel(t.agent)}` : ""} · T-{t.id}</span>
                        <Button size="sm" variant="ghost" onPress={() => openTask(t.id)}>Mở việc</Button>
                      </div>
                      {t.result ? (
                        <p className={`whitespace-pre-wrap [overflow-wrap:anywhere] ${open[t.id] ? "" : "line-clamp-4"}`}>{t.result}</p>
                      ) : <p className="text-sm text-muted">Chưa có kết quả.</p>}
                      {t.result && t.result.length > 280 && <button type="button" className="self-start text-sm font-semibold text-accent hover:underline" onClick={() => setOpen((o) => ({ ...o, [t.id]: !o[t.id] }))}>{open[t.id] ? "Thu gọn" : "Xem đầy đủ"}</button>}
                    </section>
                  )) : <Empty>Dự án chưa có lần nạp hồ sơ nào.</Empty>}
                </Tabs.Panel>
                <Tabs.Panel id="records" className="flex flex-col gap-5 pt-4">
                  {cats.length ? cats.map((c) => (
                    <section key={c.name} className="flex flex-col gap-2">
                      <h3 className="font-semibold">{c.name} <span className="font-semibold text-muted">{c.items.length}</span></h3>
                      <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
                        {c.items.map((r) => (
                          <div key={r.id} className="flex flex-col gap-1 bg-surface-secondary px-4 py-3">
                            <div className="flex flex-wrap items-baseline gap-x-3 gap-y-0.5">
                              {r.record_no && <code className="text-sm font-semibold">{r.record_no}</code>}
                              <span className="min-w-0 flex-1 font-semibold [overflow-wrap:anywhere]">{r.title}</span>
                              {r.issued_on && <span className="text-sm text-muted">{ddmmyyyy(parseDate(r.issued_on))}</span>}
                              {r.contract_value != null && <span className="text-sm font-semibold">{money(r.contract_value)}</span>}
                              {link(r.file_url, "Mở tệp nguồn")}
                            </div>
                            {r.description && <p className="text-sm text-muted [overflow-wrap:anywhere]">{r.description}</p>}
                          </div>
                        ))}
                      </div>
                    </section>
                  )) : <Empty>Chưa có hồ sơ trong danh mục.</Empty>}
                </Tabs.Panel>
                <Tabs.Panel id="files" className="pt-4">
                  {D.files.length ? (
                    <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
                      {D.files.map((f, i) => (
                        <div key={i} className="flex flex-wrap items-center gap-x-4 gap-y-1 bg-surface-secondary px-4 py-3">
                          <span className="min-w-0 flex-1 [overflow-wrap:anywhere]">{link(f.url, f.name)}</span>
                          <button type="button" className="text-sm text-muted hover:underline" onClick={() => openTask(f.task_id)}>T-{f.task_id}</button>
                        </div>
                      ))}
                    </div>
                  ) : <Empty>Chưa có báo cáo hoặc tài liệu nào.</Empty>}
                </Tabs.Panel>
                <Tabs.Panel id="kb" className="pt-4">
                  {D.kb ? (
                    <div className="flex flex-col gap-1 rounded-xl bg-surface-secondary p-4">
                      <b>{D.kb.name}</b>
                      <span className={D.kb.ready ? "font-semibold text-success" : "font-semibold text-warning"}>{D.kb.ready ? "Đã tạo trên WeKnora" : "Chưa nạp (kho giữ chỗ)"}</span>
                      <span className="text-sm text-muted">{D.kb.sources} tài liệu đã nạp. Hỏi kho này qua agent Quản trị dữ liệu hoặc trên kb.enterpriseos.bond.</span>
                    </div>
                  ) : <Empty>Dự án chưa có kho tri thức.</Empty>}
                </Tabs.Panel>
              </Tabs>
            )}
          </Modal.Body>
          <Modal.Footer><Button variant="secondary" onPress={onClose}>Đóng</Button></Modal.Footer>
        </Modal.Dialog>
      </Modal.Container>
    </Modal.Backdrop>
  );
}

// Danh sách dự án kèm tiến độ; bấm thẻ để xem việc, "Cài đặt" để quản lý
export default function Projects() {
  const { companyId, org, lookups, isAdmin, isManager, openTask } = useApp();
  const { data, error, loading } = useLoad(() => companyId ? rpc("app_tasks", { company_id: companyId, days: 60 }) : Promise.resolve([]), [companyId]);
  const [editing, setEditing] = useState(undefined);              // undefined: đóng · null: tạo mới · object: sửa
  const [intake, setIntake] = useState(undefined);
  const [results, setResults] = useState(null);                  // dự án đang xem kết quả
  const agentLabel = (c) => lookups.agent[c]?.name || c;                // undefined: đóng · null: dự án mới · object: dự án có sẵn
  const runs = useLoad(() => companyId ? rpc("app_workflow_runs", { company_id: companyId }) : Promise.resolve([]), [companyId]);
  const runOf = (pid) => (runs.data || []).find((r) => r.project_id === pid);
  const rows = org.projects.map((p) => {
    const ts = (data || []).filter((t) => t.project_id === p.id);
    const done = ts.filter((t) => t.status === "done").length;
    return { p, open: ts.filter(isOpen).length, done, late: ts.filter(isOverdue).length, pct: ts.length ? Math.round((done / ts.length) * 100) : 0, nm: org.project_members.filter((m) => m.project_id === p.id).length };
  }).sort((a, b) => Number(b.p.active) - Number(a.p.active) || b.open - a.open);
  const canCreate = isAdmin || isManager;
  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Dự án" sub={`${org.projects.filter((p) => p.active).length} dự án đang thực hiện`}
        actions={<>{isAdmin && <Button variant="secondary" onPress={() => setIntake(null)}><FaceRobot className="size-4" />Nạp hồ sơ dự án</Button>}{canCreate && <Button onPress={() => setEditing(null)}><Plus className="size-4" />Thêm dự án</Button>}</>} />
      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={3} /> : rows.length ? (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {rows.map(({ p, open, done, late, pct, nm }) => (
            <div key={p.id} className={`flex flex-col gap-3 rounded-xl bg-surface p-4 ${p.active ? "" : "opacity-60"}`}>
              <button type="button" onClick={() => go("project", { id: p.id })} className="flex flex-col gap-3 text-left">
                <span className="flex flex-col gap-0.5">
                  <b className="text-lg font-semibold leading-snug">{p.name}</b>
                  <span className="text-sm text-muted">{lookups.dept[p.department_id]?.name || "Chung công ty"} · {STATUS[p.status] || p.status}</span>
                </span>
                {p.description && <span className="line-clamp-2 text-sm text-muted">{p.description}</span>}
                <span className="h-2.5 overflow-hidden rounded-full bg-surface-secondary" role="img" aria-label={`${pct}% việc đã xong`}><span className="block h-full rounded-full bg-accent" style={{ width: `${pct}%` }} /></span>
                <span className="flex flex-wrap gap-x-4 text-sm"><span><b>{open}</b> đang mở</span>{late > 0 && <b className="text-danger">{late} quá hạn</b>}<span className="text-muted">{done} xong (60 ngày)</span></span>
                <span className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-muted">
                  {p.manager_id && lookups.person[p.manager_id] && <span>QL: {lookups.person[p.manager_id].name}</span>}
                  <span>{nm} thành viên</span>{p.end_date && <span>Hạn {ddmmyyyy(parseDate(p.end_date))}</span>}
                </span>
              </button>
              {runOf(p.id) && (
                <button type="button" onClick={() => setResults(p)} className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg bg-accent-soft px-3 py-2 text-left text-sm">
                  <FaceRobot className="size-4 shrink-0" /><b>{runOf(p.id).state === "running" ? "Đang nạp hồ sơ" : runOf(p.id).state === "done" ? "Đã nạp hồ sơ" : "Đã dừng nạp hồ sơ"}</b>
                  <b className="ml-auto text-accent">Xem kết quả</b>{Object.entries(runOf(p.id).tasks || {}).map(([k, n]) => <span key={k}>{n} {({ todo: "chờ", in_progress: "đang làm", blocked: "vướng", in_review: "chờ duyệt", done: "xong", cancelled: "hủy" })[k] || k}</span>)}
                </button>
              )}
              <span className="flex flex-wrap gap-2">
                {isAdmin && p.active && !(runOf(p.id)?.state === "running") && <Button size="sm" variant="ghost" onPress={() => setIntake(p)}><FaceRobot className="size-4" />Nạp hồ sơ</Button>}
                {p.drive_url && <a className="inline-flex h-8 items-center rounded-full bg-surface-secondary px-3 text-sm font-semibold text-accent hover:underline" href={p.drive_url} target="_blank" rel="noopener noreferrer">Thư mục Drive</a>}
                {p.can_manage && <Button size="sm" variant="ghost" onPress={() => setEditing(p)}><Pencil className="size-4" />Cài đặt</Button>}
              </span>
            </div>
          ))}
        </div>
      ) : <Empty>Chưa có dự án. {canCreate ? "Bấm Thêm dự án để tạo dự án đầu tiên." : "Nhờ quản trị hoặc trưởng phòng tạo dự án."}</Empty>}
      <ResultsDialog project={results} isOpen={!!results} onClose={() => setResults(null)} />
      <ProjectDialog project={editing || null} isOpen={editing !== undefined} onClose={() => setEditing(undefined)} />
      <IntakeDialog project={intake || null} isOpen={intake !== undefined} onClose={() => setIntake(undefined)} />
    </div>
  );
}
