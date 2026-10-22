import { useState } from "react";
import { Button, Modal, Tabs, toast } from "@heroui/react";
import { Plus, Pencil, TrashBin } from "@gravity-ui/icons";
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

// Danh sách dự án kèm tiến độ; bấm thẻ để xem việc, "Cài đặt" để quản lý
export default function Projects() {
  const { companyId, org, lookups, isAdmin, isManager } = useApp();
  const { data, error, loading } = useLoad(() => companyId ? rpc("app_tasks", { company_id: companyId, days: 60 }) : Promise.resolve([]), [companyId]);
  const [editing, setEditing] = useState(undefined);              // undefined: đóng · null: tạo mới · object: sửa
  const rows = org.projects.map((p) => {
    const ts = (data || []).filter((t) => t.project_id === p.id);
    const done = ts.filter((t) => t.status === "done").length;
    return { p, open: ts.filter(isOpen).length, done, late: ts.filter(isOverdue).length, pct: ts.length ? Math.round((done / ts.length) * 100) : 0, nm: org.project_members.filter((m) => m.project_id === p.id).length };
  }).sort((a, b) => Number(b.p.active) - Number(a.p.active) || b.open - a.open);
  const canCreate = isAdmin || isManager;
  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Dự án" sub={`${org.projects.filter((p) => p.active).length} dự án đang thực hiện`}
        actions={canCreate && <Button onPress={() => setEditing(null)}><Plus className="size-4" />Thêm dự án</Button>} />
      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={3} /> : rows.length ? (
        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
          {rows.map(({ p, open, done, late, pct, nm }) => (
            <div key={p.id} className={`flex flex-col gap-3 rounded-xl bg-surface p-4 ${p.active ? "" : "opacity-60"}`}>
              <button type="button" onClick={() => go("tasks", { p: p.id })} className="flex flex-col gap-3 text-left">
                <span className="flex flex-col gap-0.5">
                  <b className="text-lg font-extrabold leading-snug">{p.name}</b>
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
              <span className="flex flex-wrap gap-2">
                {p.drive_url && <a className="inline-flex h-8 items-center rounded-full bg-surface-secondary px-3 text-sm font-semibold text-accent hover:underline" href={p.drive_url} target="_blank" rel="noopener noreferrer">Thư mục Drive</a>}
                {p.can_manage && <Button size="sm" variant="ghost" onPress={() => setEditing(p)}><Pencil className="size-4" />Cài đặt</Button>}
              </span>
            </div>
          ))}
        </div>
      ) : <Empty>Chưa có dự án. {canCreate ? "Bấm Thêm dự án để tạo dự án đầu tiên." : "Nhờ quản trị hoặc trưởng phòng tạo dự án."}</Empty>}
      <ProjectDialog project={editing || null} isOpen={editing !== undefined} onClose={() => setEditing(undefined)} />
    </div>
  );
}
