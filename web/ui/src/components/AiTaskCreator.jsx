import { useEffect, useMemo, useState } from "react";
import { Button, toast } from "@heroui/react";
import { Sparkle, CheckCircle, WarningCircle } from "@phosphor-icons/react";
import { useApp } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { PRIORITY } from "../lib/format.js";
import { AgentChip, ErrorBox, SelectField, TextAreaInput, TextInput } from "./ui.jsx";

// Tạo việc bằng trợ lý AI (design/README.md §10), giao cho Mai (profile team_admin): 1 Mô tả → 2 Xem và sửa → 3 Xác nhận.
// Mai chỉ ĐỀ XUẤT; không có gì được lưu cho đến khi người dùng bấm Xác nhận (việc được tạo bằng quyền của người dùng).
const EXAMPLES = [
  "Giao chị Lan soạn công văn gia hạn tiến độ cho dự án Phú Hải, hạn thứ Sáu tuần này",
  "Họp giao ban Tổng công ty thứ Hai tuần sau: anh Minh chuẩn bị báo cáo doanh thu, chị Lan chuẩn bị báo cáo nhân sự",
  "Rà soát hồ sơ thanh toán đợt 3 trước ngày 30, chia việc cho kế toán và kỹ thuật",
];

export default function AiTaskCreator({ requestId, onClose, onCreated }) {
  const { companyId, org, openTask, refresh } = useApp();
  const [step, setStep] = useState(1), [text, setText] = useState(""), [rid, setRid] = useState(requestId || null);
  const [req, setReq] = useState(null), [items, setItems] = useState([]), [busy, setBusy] = useState(false), [error, setError] = useState(null), [done, setDone] = useState([]);
  const people = useMemo(() => org.members.filter((m) => m.active && m.user).map((m) => ({ value: m.user.id, label: m.user.name })), [org.members]);

  const adopt = (r) => {
    setReq(r);
    if (r.state === "proposed") {
      setItems((r.proposal?.tasks || []).map((t) => ({ ...t, on: true, assignee_id: t.assignee_id || null, subtasks: (t.subtasks || []).map((s) => ({ ...s, on: true })) })));
      setStep(2);
    } else if (r.state === "confirmed") { setDone(r.created_tasks || []); setStep(3); }
  };
  // đang chờ Mai: hỏi trạng thái mỗi 3 giây (tối đa 10 phút, máy chủ tự báo hết hạn)
  useEffect(() => {
    if (!rid) return;
    let alive = true, timer;
    const tick = async () => {
      try { const r = await rpc("app_ai_request_get", { id: rid }); if (!alive) return; adopt(r); if (r.state === "pending") timer = setTimeout(tick, 3000); }
      catch (e) { if (alive) setError(e); }
    };
    tick(); return () => { alive = false; clearTimeout(timer); };
  }, [rid]);

  async function send() {
    setBusy(true); setError(null);
    try { const r = await rpc("app_ai_request", { company_id: companyId, description: text }); setReq({ state: "pending" }); setRid(r.id); }
    catch (e) { setError(e); } finally { setBusy(false); }
  }
  async function cancel() {
    try { if (rid) await rpc("app_ai_request_cancel", { id: rid }); } catch (e) { setError(e); return; }
    setRid(null); setReq(null); setStep(1);
  }
  async function confirm() {
    const chosen = items.filter((t) => t.on).map((t) => ({ title: t.title, description: t.description || "", assignee_id: t.assignee_id || "", due_date: t.due_date || "", priority: t.priority, important: !!t.important, urgent: !!t.urgent, project_id: t.project_id || "",
      subtasks: t.subtasks.filter((s) => s.on && s.title.trim()).map((s) => ({ title: s.title, due_date: s.due_date || "" })) }));
    if (!chosen.length) { setError(new Error("Chọn ít nhất một việc để tạo")); return; }
    setBusy(true); setError(null);
    try { const r = await rpc("app_ai_confirm", { id: rid, tasks: chosen }); setDone(r.created); setStep(3); refresh(); toast.success(`Đã tạo ${r.created.length} việc`); onCreated?.(r.created); }
    catch (e) { setError(e); } finally { setBusy(false); }
  }
  const upd = (i, k, v) => setItems((xs) => xs.map((x, j) => (j === i ? { ...x, [k]: v } : x)));
  const updSub = (i, si, k, v) => setItems((xs) => xs.map((x, j) => (j === i ? { ...x, subtasks: x.subtasks.map((s, n) => (n === si ? { ...s, [k]: v } : s)) } : x)));
  const total = items.filter((t) => t.on).reduce((n, t) => n + 1 + t.subtasks.filter((s) => s.on).length, 0);
  const steps = ["Mô tả", "Xem và sửa", "Xác nhận"];

  return (
    <div className="flex flex-col gap-4">
      <ol className="flex items-center gap-2 text-[13px]" aria-label="Các bước">{steps.map((s, i) => (
        <li key={s} aria-current={step === i + 1 ? "step" : undefined} className={`inline-flex items-center gap-1.5 ${step === i + 1 ? "font-medium text-act" : step > i + 1 ? "text-foreground" : "text-faint"}`}>
          <span className="grid size-5 place-items-center rounded-full text-[11px]" style={{ boxShadow: "inset 0 0 0 1px currentColor" }}>{step > i + 1 ? "✓" : i + 1}</span>{s}{i < 2 && <span className="mx-1 text-faint">›</span>}</li>))}</ol>

      {step === 1 && !rid && (<>
        <TextAreaInput label="Mô tả việc cần giao bằng lời của bạn" value={text} onChange={setText} rows={5} placeholder="Ví dụ: Giao anh Minh soạn báo cáo tuần trước thứ Sáu, kèm đối chiếu số liệu với kế toán" />
        <div className="flex flex-wrap gap-1.5">{EXAMPLES.map((e) => <button key={e} type="button" onClick={() => setText(e)} className="rounded-full px-3 py-1 text-left text-[12.5px] text-muted hover:bg-surface-secondary" style={{ boxShadow: "inset 0 0 0 1px var(--border)" }}>{e.length > 60 ? e.slice(0, 58) + "…" : e}</button>)}</div>
        <p className="text-xs text-muted">Mô tả được gửi cho <b className="font-medium">Mai (AI)</b> để phân tích. Mai chỉ đề xuất, bạn xem và sửa rồi mới tạo việc.</p>
        <ErrorBox error={error} />
        <div className="flex justify-end"><Button onPress={send} isPending={busy} isDisabled={text.trim().length < 5}><Sparkle size={16} weight="fill" />Phân tích mô tả</Button></div>
      </>)}

      {step === 1 && rid && req?.state !== "failed" && req?.state !== "cancelled" && (
        <div className="flex flex-col items-start gap-3 rounded-[14px] bg-ai-bg p-4" style={{ boxShadow: "inset 0 0 0 1px color-mix(in srgb, var(--ai) 40%, transparent)" }} role="status" aria-live="polite">
          <AgentChip name="Mai" size={26} />
          <p>Mai đang phân tích yêu cầu #{rid}… thường dưới một phút. Bạn có thể đóng cửa sổ này, hệ thống báo ở chuông khi Mai xong.</p>
          <div className="flex gap-2"><Button variant="secondary" onPress={onClose}>Đóng, báo khi xong</Button><Button variant="ghost" onPress={cancel}>Hủy yêu cầu</Button></div>
        </div>)}
      {step === 1 && rid && req?.state === "failed" && (
        <div className="flex flex-col items-start gap-3 rounded-[14px] bg-dg-bg p-4 text-danger" role="alert"><p className="flex items-start gap-2"><WarningCircle size={20} weight="fill" className="mt-0.5 shrink-0" />{req.error || "Mai chưa phân tích được yêu cầu."}</p>
          <div className="flex gap-2"><Button variant="secondary" onPress={() => { setRid(null); setReq(null); }}>Sửa mô tả và thử lại</Button></div></div>)}

      {step === 2 && (<>
        <div className="flex items-start gap-2 rounded-[14px] bg-ai-bg p-3 text-sm" style={{ boxShadow: "inset 0 0 0 1px color-mix(in srgb, var(--ai) 40%, transparent)" }}>
          <AgentChip name="Mai" size={22} showName={false} /><p><b className="font-medium">Mai đề xuất {items.length} việc.</b> {req?.proposal?.summary} Chưa có gì được lưu cho đến khi bạn bấm Xác nhận.</p></div>
        {items.map((t, i) => (
          <fieldset key={i} className={`flex flex-col gap-3 rounded-[14px] p-3 ${t.on ? "" : "opacity-50"}`} style={{ boxShadow: "inset 0 0 0 1px var(--border)" }}>
            <legend className="px-1 text-xs text-muted"><label className="inline-flex items-center gap-1.5"><input type="checkbox" checked={t.on} onChange={(e) => upd(i, "on", e.target.checked)} />Việc {i + 1}</label></legend>
            <TextInput label="Tiêu đề" value={t.title} onChange={(v) => upd(i, "title", v)} />
            <div className="grid gap-3 sm:grid-cols-2">
              <SelectField label="Người làm" value={t.assignee_id} onChange={(v) => upd(i, "assignee_id", v)} allowEmpty emptyLabel="Chưa giao" options={people} />
              <SelectField label="Ưu tiên" value={t.priority} onChange={(v) => upd(i, "priority", v)} options={Object.entries(PRIORITY).map(([value, label]) => ({ value, label }))} />
              <TextInput label="Hạn chót" type="date" value={t.due_date || ""} onChange={(v) => upd(i, "due_date", v)} />
              <SelectField label="Dự án" value={t.project_id} onChange={(v) => upd(i, "project_id", v)} allowEmpty emptyLabel="Không thuộc dự án" options={org.projects.filter((p) => p.active).map((p) => ({ value: p.id, label: p.name }))} />
            </div>
            {!t.assignee_id && t.assignee_hint && <p className="text-xs text-warning">Mai gợi ý "{t.assignee_hint}" nhưng không thấy người này trong công ty: chọn người làm ở trên.</p>}
            {t.subtasks.length > 0 && (
              <div className="flex flex-col gap-1.5"><span className="text-[13px] font-medium">Việc con đề xuất</span>
                {t.subtasks.map((s, si) => (
                  <div key={si} className="flex items-center gap-2"><input type="checkbox" aria-label={`Tạo việc con: ${s.title}`} checked={s.on} onChange={(e) => updSub(i, si, "on", e.target.checked)} />
                    <input value={s.title} onChange={(e) => updSub(i, si, "title", e.target.value)} aria-label="Tên việc con" className="h-9 min-w-0 flex-1 rounded-lg border border-border bg-field-background px-2.5 text-[13.5px]" />
                    <input type="date" value={s.due_date || ""} onChange={(e) => updSub(i, si, "due_date", e.target.value)} aria-label="Hạn việc con" className="h-9 w-[150px] rounded-lg border border-border bg-field-background px-2 text-[13px]" /></div>))}</div>)}
          </fieldset>))}
        <ErrorBox error={error} />
        <div className="flex flex-wrap justify-between gap-2"><Button variant="ghost" onPress={cancel}>Quay lại (hủy đề xuất)</Button><Button onPress={confirm} isPending={busy} isDisabled={!total}>Xác nhận tạo {total} việc</Button></div>
      </>)}

      {step === 3 && (
        <div className="flex flex-col items-start gap-3"><p className="flex items-center gap-2 font-medium"><CheckCircle size={20} weight="fill" className="text-success" />Đã tạo {done.length} việc.</p>
          <ul className="flex flex-wrap gap-1.5">{done.map((id) => <li key={id}><button type="button" onClick={() => { onClose(); openTask(id); }} className="rounded-full px-3 py-1 text-[13px] text-act hover:bg-accent-soft" style={{ boxShadow: "inset 0 0 0 1px var(--accent)" }}>Mở T-{id}</button></li>)}</ul>
          <Button onPress={onClose}>Đóng</Button></div>)}
    </div>
  );
}
