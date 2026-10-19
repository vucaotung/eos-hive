import { useEffect, useMemo, useState } from "react";
import { Button, Modal, toast } from "@heroui/react";
import { useApp } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { PRIORITY, AGENT_ROLES } from "../lib/format.js";
import { SelectField, TextAreaInput, TextInput, ErrorBox } from "./ui.jsx";

const blank = (dept) => ({ title: "", description: "", department_id: dept || null, assignee_id: null, due_date: "", priority: "medium",
  project_id: null, approval_flow_id: null, agent_role: null });

// Tạo hoặc sửa việc. task = null → tạo mới; parent → việc con
export default function TaskForm({ isOpen, onClose, task = null, parent = null, onSaved }) {
  const { companyId, membership, org, lookups, refresh } = useApp();
  const [f, setF] = useState(blank(membership?.department_id));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!isOpen) return;
    setError(null);
    if (task) setF({ title: task.title, description: task.description || "", department_id: task.department_id, assignee_id: task.assignee_id,
      due_date: task.due_date || "", priority: task.priority, project_id: task.project_id, approval_flow_id: task.approval_flow_id, agent_role: task.agent_role });
    else setF({ ...blank(parent?.department_id || membership?.department_id), project_id: parent?.project_id || null });
  }, [isOpen, task, parent, membership]);

  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));
  const people = useMemo(() => org.members.filter((m) => m.active && m.user?.active !== false).map((m) => ({
    value: m.user.id, label: `${m.user.name}${m.department_id && lookups.dept[m.department_id] ? ` · ${lookups.dept[m.department_id].code}` : ""}` })), [org.members, lookups.dept]);
  const flows = org.flows.filter((fl) => !fl.department_id || fl.department_id === f.department_id);

  async function save() {
    if (f.title.trim().length < 2) { setError(new Error("Nhập tên việc (ít nhất 2 ký tự)")); return; }
    setBusy(true); setError(null);
    try {
      let saved;
      if (task) {
        saved = await rpc("update_task", { p_task: task.id, p: {
          title: f.title, description: f.description, department_id: f.department_id || "", assignee_id: f.assignee_id || "",
          due_date: f.due_date || "", priority: f.priority, project_id: f.project_id || "", approval_flow_id: f.approval_flow_id || "",
          agent_role: f.agent_role || "" } });
        toast.success(`Đã lưu T-${task.id}`);
      } else {
        saved = await rpc("create_task", { p_company: companyId, p_title: f.title, p_description: f.description || null,
          p_department: f.department_id, p_assignee: f.assignee_id, p_due: f.due_date || null, p_priority: f.priority,
          p_project: f.project_id, p_parent: parent?.id || null, p_agent_role: f.agent_role, p_flow: f.approval_flow_id });
        toast.success(`Đã giao T-${saved.id}`);
      }
      refresh(); onSaved?.(saved); onClose();
    } catch (e) { setError(e); } finally { setBusy(false); }
  }

  return (
    <Modal.Backdrop isOpen={isOpen} onOpenChange={(o) => !o && onClose()}>
      <Modal.Container placement="auto" scroll="inside">
        <Modal.Dialog className="sm:max-w-2xl">
          <Modal.CloseTrigger />
          <Modal.Header>
            <Modal.Heading>{task ? `Sửa T-${task.id}` : parent ? `Việc con của T-${parent.id}` : "Giao việc"}</Modal.Heading>
          </Modal.Header>
          <Modal.Body>
            <form className="grid gap-4 sm:grid-cols-2" onSubmit={(e) => { e.preventDefault(); save(); }}>
              <div className="sm:col-span-2"><TextInput label="Tên việc" value={f.title} onChange={set("title")} isRequired autoFocus placeholder="Ví dụ: Soạn công văn xin gia hạn tiến độ" /></div>
              <div className="sm:col-span-2"><TextAreaInput label="Mô tả" value={f.description} onChange={set("description")} rows={4}
                placeholder={"Mục tiêu, kết quả cần nộp, tài liệu liên quan"} /></div>
              <SelectField label="Phòng ban" value={f.department_id} onChange={set("department_id")} allowEmpty emptyLabel="Chung công ty"
                options={org.departments.filter((d) => d.active).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
              <SelectField label="Người phụ trách" value={f.assignee_id} onChange={set("assignee_id")} allowEmpty emptyLabel="Chưa giao" options={people} />
              <TextInput label="Hạn" type="date" value={f.due_date} onChange={set("due_date")} />
              <SelectField label="Ưu tiên" value={f.priority} onChange={set("priority")} options={Object.entries(PRIORITY).map(([value, label]) => ({ value, label }))} />
              <SelectField label="Dự án" value={f.project_id} onChange={set("project_id")} allowEmpty emptyLabel="Không thuộc dự án"
                options={org.projects.filter((p) => p.active).map((p) => ({ value: p.id, label: p.name }))} />
              <SelectField label="Quy trình duyệt" value={f.approval_flow_id} onChange={set("approval_flow_id")} allowEmpty emptyLabel="Không cần duyệt"
                options={flows.map((fl) => ({ value: fl.id, label: `${fl.name} (${fl.steps?.length || 0} bước)` }))} />
              <div className="sm:col-span-2">
                <SelectField label="Giao cho agent AI" value={f.agent_role} onChange={set("agent_role")} allowEmpty emptyLabel="Không, người làm"
                  options={Object.entries(AGENT_ROLES).map(([value, label]) => ({ value, label }))} />
                <p className="mt-1 text-sm text-muted">Agent nhận việc ở lượt quét kế tiếp, hỏi lại khi thiếu thông tin và nộp kết quả để người phụ trách duyệt.</p>
              </div>
              <button type="submit" hidden />
            </form>
            {error && <div className="mt-4"><ErrorBox error={error} /></div>}
          </Modal.Body>
          <Modal.Footer>
            <Button variant="secondary" onPress={onClose}>Hủy</Button>
            <Button isPending={busy} onPress={save}>{task ? "Lưu thay đổi" : "Giao việc"}</Button>
          </Modal.Footer>
        </Modal.Dialog>
      </Modal.Container>
    </Modal.Backdrop>
  );
}
