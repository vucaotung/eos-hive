import { useEffect, useMemo, useState } from "react";
import { Button, Modal, toast } from "@heroui/react";
import { useApp } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { PRIORITY } from "../lib/format.js";
import { CaretDown, CaretUp, Star, Lightning } from "@phosphor-icons/react";
import { quadOf } from "../pages/Eisenhower.jsx";
import AiTaskCreator from "./AiTaskCreator.jsx";
import { useMedia } from "./ui.jsx";
import { SelectField, TextAreaInput, TextInput, ErrorBox } from "./ui.jsx";
import { TagsInput, RemindPicker, DepsPicker, DupWarning, TemplatePicker, AttachInput, remindFrom } from "./TaskExtras.jsx";
import { parseQuick } from "../lib/quickadd.js";
import { isoDate } from "../lib/format.js";

const blank = (dept) => ({ title: "", description: "", department_id: dept || null, assignee_id: null, due_date: "", priority: "medium",
  project_id: null, approval_flow_id: null, agent_role: null, important: false, urgent: false, start_date: "", est: "", repeat: "none", endMode: "never", endDate: "", endN: "10" });
const blankX = { tags: [], deps: [], remind: "none", remindCustom: "", attach: [], tpl: null, quick: "" };   // phần mở rộng (nhãn, chờ, nhắc, đính kèm, mẫu)

// Tạo hoặc sửa việc. task = null → tạo mới; parent → việc con
export default function TaskForm({ isOpen, onClose, task = null, parent = null, onSaved, aiRequest = null }) {
  const { companyId, membership, org, lookups, refresh, me } = useApp();
  const [f, setF] = useState(blank(membership?.department_id));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const sheet = useMedia("(max-width: 639px)");   // mobile: hiện như bottom sheet (bo góc trên 20px)
  const [tab, setTab] = useState("manual");   // manual | ai (chỉ khi tạo mới)
  const canAi = !task && !parent;
  const [more, setMore] = useState(false);   // "Thêm chi tiết": mặc định chỉ hiện các trường thường dùng
  const [x, setX] = useState(blankX), setXk = (k) => (v) => setX((s) => ({ ...s, [k]: v }));
  const [x0, setX0] = useState(null);   // nhãn/chờ lúc mở để sửa (so khi lưu)

  useEffect(() => {
    if (!isOpen) return;
    setError(null); setMore(!!task || !!parent); setTab(aiRequest ? "ai" : "manual");
    if (task) setF({ title: task.title, description: task.description || "", department_id: task.department_id, assignee_id: task.assignee_id,
      due_date: task.due_date || "", priority: task.priority, project_id: task.project_id, approval_flow_id: task.approval_flow_id, agent_role: task.agent_role, important: !!task.important, urgent: !!task.urgent, start_date: task.start_date || "", est: task.est_minutes ? String(task.est_minutes) : "" });
    else setF({ ...blank(parent?.department_id || membership?.department_id), project_id: parent?.project_id || null });
    setX(blankX); setX0(null);
    if (task) rpc("app_task_extras", { id: task.id }).then((e) => { const v = { ...blankX, tags: e.tags || [], deps: (e.depends_on || []).map((d) => d.id) }; setX(v); setX0(v); }).catch(() => {});
  }, [isOpen, task, parent, membership, aiRequest]);

  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));
  const people = useMemo(() => org.members.filter((m) => m.active && m.user?.active !== false).map((m) => ({
    value: m.user.id, label: `${m.user.name}${m.department_id && lookups.dept[m.department_id] ? ` · ${lookups.dept[m.department_id].code}` : ""}` })), [org.members, lookups.dept]);
  const qctx = useMemo(() => ({ members: org.members.filter((m) => m.user).map((m) => ({ id: m.user.id, name: m.user.name, email: m.user.email })), projects: org.projects.filter((p) => p.active).map((p) => ({ id: p.id, name: p.name })) }), [org.members, org.projects]);
  const quick = parseQuick(x.quick, qctx);
  function applyQuick() {
    if (!x.quick.trim()) return;
    const q = parseQuick(x.quick, qctx);
    setF((s) => ({ ...s, title: q.title || s.title, assignee_id: q.assignee_id || s.assignee_id, due_date: q.due_date || s.due_date, priority: q.priority || s.priority, project_id: q.project_id || s.project_id,
      important: q.important || s.important, urgent: q.urgent || s.urgent, est: q.est || s.est }));
    setX((s) => ({ ...s, tags: [...new Set([...s.tags, ...q.tags])].slice(0, 8), quick: "", remind: q.time ? "custom" : s.remind,
      remindCustom: q.time ? `${q.due_date || isoDate(new Date())}T${q.time}` : s.remindCustom }));
    if (q.est || q.tags.length || q.time) setMore(true);
    if (q.unknown.length) toast.warning(`Chưa nhận ra: ${q.unknown.join(", ")} (chọn tay bên dưới)`);
  }
  function applyTemplate(t) {
    const b = t.body, d = b.due_in_days != null ? (() => { const n = new Date(); n.setDate(n.getDate() + b.due_in_days); return isoDate(n); })() : "";
    setF((s) => ({ ...s, title: b.title || s.title, description: b.description ?? s.description, priority: b.priority || s.priority, important: !!b.important, urgent: !!b.urgent, est: b.est_minutes ? String(b.est_minutes) : s.est, due_date: d || s.due_date }));
    setX((s) => ({ ...s, tags: [...new Set([...s.tags, ...(b.tags || [])])].slice(0, 8), tpl: { id: t.id, checklist: b.checklist || [], subtasks: b.subtasks || [] } }));
    setMore(true); toast.success(`Đã điền theo mẫu "${t.name}"`);
  }
  const currentAsTemplate = () => ({ title: f.title, description: f.description, priority: f.priority, important: f.important, urgent: f.urgent, est_minutes: f.est ? Number(f.est) : undefined, tags: x.tags,
    checklist: x.tpl?.checklist || [], subtasks: x.tpl?.subtasks || [], due_in_days: f.due_date ? Math.max(0, Math.round((new Date(f.due_date) - new Date(isoDate(new Date()))) / 864e5)) : undefined });
  const flows = org.flows.filter((fl) => !fl.department_id || fl.department_id === f.department_id);
  const defaultFlow = flows.find((fl) => fl.name === "Người giao duyệt") || flows[0];
  const locked = !!task && (task.status === "in_review" || task.status === "done");   // đang chờ duyệt hoặc đã xong: không đổi quy trình

  async function save() {
    if (f.title.trim().length < 2) { setError(new Error("Nhập tên việc (ít nhất 2 ký tự)")); return; }
    setBusy(true); setError(null);
    try {
      let saved;
      const fields = { title: f.title, description: f.description, department_id: f.department_id || "", assignee_id: f.assignee_id || "",
        due_date: f.due_date || "", priority: f.priority, project_id: f.project_id || "", approval_flow_id: f.approval_flow_id || "", agent_role: f.agent_role || "", important: !!f.important, urgent: !!f.urgent, start_date: f.start_date || "", est_minutes: f.est ? Number(f.est) : "" };
      if (!task && !parent && f.repeat !== "none") {   // chọn "Lặp lại": lưu thành việc định kỳ (việc đầu tiên tạo ngay nếu đến hạn)
        const start = f.due_date || isoDate(new Date());
        const end = f.endMode === "until" ? { mode: "until", date: f.endDate } : f.endMode === "count" ? { mode: "count", n: Number(f.endN) } : { mode: "never" };
        if (f.endMode === "until" && !f.endDate) throw new Error("Chọn ngày kết thúc việc lặp");
        saved = await rpc("app_recurrence_save_ex", { company_id: companyId, title: f.title, description: f.description, department_id: f.department_id || "", assignee_id: f.assignee_id || "", project_id: f.project_id || "", priority: f.priority, freq: f.repeat, start, end });
        toast.success(`Đã tạo việc định kỳ${saved.created_task ? ` và việc T-${saved.created_task}` : ""}`);
      } else if (task) {
        saved = await rpc("app_task_save", { id: task.id, ...fields });
        if (x0 && JSON.stringify(x.tags) !== JSON.stringify(x0.tags)) await rpc("app_task_tags_set", { task: task.id, tags: x.tags });
        if (x0 && JSON.stringify([...x.deps].sort()) !== JSON.stringify([...x0.deps].sort())) await rpc("app_task_deps_set", { task: task.id, depends_on: x.deps });
        toast.success(`Đã lưu T-${task.id}`);
      } else {
        const ra = remindFrom(x.remind, f.due_date, x.remindCustom);
        saved = await rpc("app_task_create_ex", { company_id: companyId, ...fields, parent_id: parent?.id || "", tags: x.tags, depends_on: x.deps, attach: x.attach,
          ...(ra ? { remind_at: ra } : {}), ...(x.tpl ? { template_id: x.tpl.id, checklist: x.tpl.checklist, subtasks: x.tpl.subtasks } : {}) });
        toast.success(`Đã giao T-${saved.id}`);
      }
      refresh(); onSaved?.(saved); onClose();
    } catch (e) { setError(e); } finally { setBusy(false); }
  }

  return (
    <Modal.Backdrop isOpen={isOpen} onOpenChange={(o) => !o && onClose()}>
      <Modal.Container placement={sheet ? "bottom" : "auto"} scroll="inside">
        <Modal.Dialog className={sheet ? "rounded-t-[20px]" : "sm:max-w-[720px]"}>
          <Modal.CloseTrigger />
          <Modal.Header>
            <Modal.Heading>{task ? `Sửa T-${task.id}` : parent ? `Việc con của T-${parent.id}` : "Giao việc"}</Modal.Heading>
          </Modal.Header>
          <Modal.Body>
            {canAi && (
              <div className="mb-4 inline-flex rounded-lg p-0.5" role="tablist" aria-label="Cách tạo việc" style={{ boxShadow: "inset 0 0 0 1px var(--border)" }}>
                {[["manual", "Tạo thủ công"], ["ai", "✦ Tạo bằng AI"]].map(([k, l]) => <button key={k} type="button" role="tab" aria-selected={tab === k} onClick={() => setTab(k)} className={`h-8 whitespace-nowrap rounded-md px-3 text-[13px] font-medium ${tab === k ? "bg-accent-soft text-act" : "text-muted"}`} style={tab === k ? { boxShadow: "inset 0 0 0 1px var(--accent)" } : undefined}>{l}</button>)}
              </div>)}
            {canAi && tab === "ai" ? <AiTaskCreator requestId={aiRequest} onClose={onClose} /> : (<>
            <form className="grid gap-4 sm:grid-cols-2" onSubmit={(e) => { e.preventDefault(); save(); }}
              onKeyDown={(e) => { if ((e.ctrlKey || e.metaKey) && e.key === "Enter") { e.preventDefault(); save(); } }}>
              {!task && !parent && (
                <div className="flex flex-col gap-1.5 sm:col-span-2">
                  <div className="flex items-end gap-2">
                    <div className="min-w-0 flex-1"><TextInput label="Gõ nhanh" value={x.quick} onChange={setXk("quick")} placeholder="Gửi báo giá @minh mai 17h !cao #báo-giá ~90p" /></div>
                    <Button variant="secondary" isDisabled={!x.quick.trim()} onPress={applyQuick}>Điền</Button>
                  </div>
                  {x.quick.trim() && (
                    <p className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[13px] text-muted" aria-live="polite">
                      <span>→ <b className="font-medium text-foreground">{quick.title || "(chưa có tên)"}</b></span>
                      {quick.assignee_id && <span>{lookups.person[quick.assignee_id]?.name}</span>}
                      {quick.due_date && <span>hạn {quick.due_date.split("-").reverse().join("/")}</span>}{quick.time && <span>nhắc {quick.time}</span>}
                      {quick.priority && <span>ưu tiên {PRIORITY[quick.priority]}</span>}{quick.tags.map((t) => <span key={t}>#{t}</span>)}{quick.est && <span>~{quick.est} phút</span>}
                      {quick.unknown.length > 0 && <span className="text-warning">chưa nhận ra {quick.unknown.join(", ")}</span>}
                    </p>)}
                  <TemplatePicker onApply={applyTemplate} current={currentAsTemplate} />
                </div>)}
              <div className="sm:col-span-2"><TextInput label="Tên việc" value={f.title} onChange={set("title")} isRequired autoFocus placeholder="Ví dụ: Soạn công văn xin gia hạn tiến độ" /></div>
              {!task && <div className="sm:col-span-2 empty:hidden"><DupWarning title={f.title} /></div>}
              {x.tpl && !task && <p className="text-[13px] text-muted sm:col-span-2">Theo mẫu: sẽ thêm {x.tpl.checklist.length} mục checklist và {x.tpl.subtasks.length} việc con. <button type="button" className="text-act underline" onClick={() => setXk("tpl")(null)}>Bỏ mẫu</button></p>}
              <TextInput label="Hạn chót" type="date" value={f.due_date} onChange={set("due_date")} />
              <SelectField label="Người phụ trách" value={f.assignee_id} onChange={set("assignee_id")} allowEmpty emptyLabel="Chưa giao" options={people} />
              <SelectField label="Dự án" value={f.project_id} onChange={set("project_id")} allowEmpty emptyLabel="Không thuộc dự án"
                options={org.projects.filter((p) => p.active).map((p) => ({ value: p.id, label: p.name }))} />
              <SelectField label="Ưu tiên" value={f.priority} onChange={set("priority")} options={Object.entries(PRIORITY).map(([value, label]) => ({ value, label }))} />
              <SelectField label="Duyệt kết quả" value={f.approval_flow_id ? "yes" : "no"} isDisabled={locked}
                onChange={(v) => set("approval_flow_id")(v === "yes" ? (defaultFlow?.id || null) : null)}
                options={[{ value: "no", label: "Không cần duyệt (nộp là xong)" }, { value: "yes", label: "Phải duyệt (chờ duyệt, được duyệt mới hoàn thành)" }]} />
              <div className="flex flex-col gap-1.5 sm:col-span-2">
                <span className="text-sm font-medium">Ma trận Eisenhower</span>
                <div className="flex flex-wrap items-center gap-2">
                  <button type="button" aria-pressed={f.important} onClick={() => set("important")(!f.important)} className={`inline-flex h-9 items-center gap-1.5 rounded-full px-3.5 text-[13.5px] font-medium ${f.important ? "bg-wn-bg text-warning" : "text-muted hover:bg-surface-secondary"}`} style={{ boxShadow: `inset 0 0 0 1px ${f.important ? "var(--warning)" : "var(--border)"}` }}><Star size={15} weight={f.important ? "fill" : "regular"} />Quan trọng</button>
                  <button type="button" aria-pressed={f.urgent} onClick={() => set("urgent")(!f.urgent)} className={`inline-flex h-9 items-center gap-1.5 rounded-full px-3.5 text-[13.5px] font-medium ${f.urgent ? "bg-dg-bg text-danger" : "text-muted hover:bg-surface-secondary"}`} style={{ boxShadow: `inset 0 0 0 1px ${f.urgent ? "var(--danger)" : "var(--border)"}` }}><Lightning size={15} weight={f.urgent ? "fill" : "regular"} />Khẩn cấp</button>
                  <span className="text-sm text-muted">Ô: <b className="font-medium text-foreground">{quadOf(f)?.title}</b></span>
                </div>
              </div>
              <div className="sm:col-span-2">
                <button type="button" aria-expanded={more} onClick={() => setMore((v) => !v)} className="inline-flex h-9 items-center gap-1.5 rounded-lg px-2 text-[13.5px] font-medium text-act hover:bg-accent-soft">
                  {more ? <CaretUp size={14} weight="bold" /> : <CaretDown size={14} weight="bold" />}{more ? "Ẩn chi tiết" : "Thêm chi tiết"}
                  {!more && <span className="font-normal text-muted">mô tả, nhãn, chờ việc khác, nhắc, đính kèm, lặp lại, agent AI</span>}
                </button>
              </div>
              {more && (<>
                <div className="sm:col-span-2"><TextAreaInput label="Mô tả" value={f.description} onChange={set("description")} rows={4}
                  placeholder={"Mục tiêu, kết quả cần nộp, tài liệu liên quan"} /></div>
                <SelectField label="Phòng ban" value={f.department_id} onChange={set("department_id")} allowEmpty emptyLabel="Chung công ty"
                  options={org.departments.filter((d) => d.active).map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
                {!task && !parent && <SelectField label="Lặp lại" value={f.repeat} onChange={set("repeat")} options={[{ value: "none", label: "Không lặp" }, { value: "daily", label: "Hằng ngày" }, { value: "weekly", label: "Hằng tuần (thứ của ngày bắt đầu)" }, { value: "monthly", label: "Hằng tháng (ngày của ngày bắt đầu)" }, { value: "yearly", label: "Hằng năm (ngày/tháng của ngày bắt đầu)" }]} />}
                {!task && !parent && f.repeat !== "none" && (
                  <div className="flex flex-col gap-2 sm:col-span-2">
                    <SelectField label="Kết thúc lặp" value={f.endMode} onChange={set("endMode")} options={[{ value: "never", label: "Không bao giờ (lặp vô hạn)" }, { value: "until", label: "Đến ngày" }, { value: "count", label: "Sau số lần nhất định" }]} />
                    {f.endMode === "until" && <TextInput label="Lặp đến hết ngày" type="date" value={f.endDate} onChange={set("endDate")} />}
                    {f.endMode === "count" && <TextInput label="Số lần tạo việc" type="number" value={f.endN} onChange={set("endN")} description="Tính cả việc đầu tiên; đủ số lần thì tự dừng." />}
                    <p className="text-sm text-muted">Việc đầu tiên tạo theo hạn chót bạn chọn; các việc sau do hệ thống tạo mỗi sáng. Nhãn, nhắc và đính kèm chỉ áp dụng cho việc tạo một lần.</p>
                  </div>)}
                <div className="sm:col-span-2"><TagsInput value={x.tags} onChange={setXk("tags")} title={f.title} description={f.description} /></div>
                <div className="sm:col-span-2"><DepsPicker value={x.deps} onChange={setXk("deps")} exclude={task?.id || null} /></div>
                {!task && f.repeat === "none" && <RemindPicker mode={x.remind} onMode={setXk("remind")} custom={x.remindCustom} onCustom={setXk("remindCustom")} due={f.due_date} />}
                {!task && f.repeat === "none" && <div className="sm:col-span-2"><AttachInput value={x.attach} onChange={setXk("attach")} /></div>}
                <TextInput label="Ngày bắt đầu" type="date" value={f.start_date} onChange={set("start_date")} description="Thanh Timeline chạy từ ngày này đến hạn chót." />
                <TextInput label="Thời lượng ước tính (phút)" type="number" value={f.est} onChange={set("est")} description="Ví dụ 90 = 1 giờ 30 phút; để trống nếu chưa rõ." />
                {f.approval_flow_id && (
                  <SelectField label="Ai duyệt" value={f.approval_flow_id} onChange={set("approval_flow_id")} isDisabled={locked}
                    options={flows.map((fl) => ({ value: fl.id, label: `${fl.name}${fl.steps?.length > 1 ? ` (${fl.steps.length} bước)` : ""}` }))} />
                )}
                <div className="sm:col-span-2">
                  <SelectField label="Giao cho agent AI" value={f.agent_role} onChange={set("agent_role")} allowEmpty emptyLabel="Không, người làm"
                    options={(me?.agents || []).map((a) => ({ value: a.code, label: `${a.name} (AI)` }))} />
                  {f.agent_role && (() => { const who = f.assignee_id ? lookups.person[f.assignee_id] : lookups.person[me?.user?.id]; return who && who.drive_status !== "ok" && (
                    <p className="mt-1 text-sm font-semibold text-warning">{who.name} chưa thiết lập thư mục Drive (Tài khoản → Thư mục Drive). Agent soạn xong vẫn không lưu được tệp .docx cho đến khi có thư mục này.</p>); })()}
                  <p className="mt-1 text-sm text-muted">Agent nhận việc ở lượt quét kế tiếp, hỏi lại khi thiếu thông tin và nộp kết quả để người phụ trách duyệt.</p>
                </div>
              </>)}
              <button type="submit" hidden />
            </form>
            {error && <div className="mt-4"><ErrorBox error={error} /></div>}</>)}
          </Modal.Body>
          {!(canAi && tab === "ai") && <Modal.Footer>
            <span className="mr-auto hidden text-xs text-faint sm:block">Ctrl+Enter để lưu · Esc để đóng</span>
            <Button variant="secondary" onPress={onClose}>Hủy</Button>
            <Button isPending={busy} onPress={save}>{task ? "Lưu thay đổi" : "Giao việc"}</Button>
          </Modal.Footer>}
        </Modal.Dialog>
      </Modal.Container>
    </Modal.Backdrop>
  );
}
