import { useState } from "react";
import { Button, toast } from "@heroui/react";
import { CheckSquare, Square, X, Plus, ListChecks } from "@phosphor-icons/react";
import { useApp } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";

// Checklist của việc (design/README.md §8): tick/bỏ tick, thêm, xóa mục, chèn từ mẫu của công ty. Lưu cả danh sách mỗi lần đổi (máy chủ giữ người tick cũ).
export default function Checklist({ task, items, canEdit, onChanged }) {
  const { companyId } = useApp();
  const [text, setText] = useState(""), [busy, setBusy] = useState(false), [tpls, setTpls] = useState(null), [showTpl, setShowTpl] = useState(false);
  const done = items.filter((i) => i.done).length;
  async function save(next) {
    setBusy(true);
    try { await rpc("app_checklist_save", { task: task.id, items: next.map((i) => ({ title: i.title, done: i.done })) }); onChanged(); }
    catch (e) { toast.danger(e.message); } finally { setBusy(false); }
  }
  async function openTpl() {
    setShowTpl((v) => !v);
    if (!tpls) { try { setTpls(await rpc("app_checklist_templates", { company_id: companyId })); } catch (e) { toast.danger(e.message); setTpls([]); } }
  }
  async function apply(id, mode) {
    setBusy(true);
    try { const r = await rpc("app_checklist_apply", { task: task.id, template_id: id, mode }); toast.success(`Đã chèn ${r.added} mục`); setShowTpl(false); onChanged(); }
    catch (e) { toast.danger(e.message); } finally { setBusy(false); }
  }
  return (
    <section className="flex flex-col gap-2">
      <div className="flex items-center gap-3"><h3 className="font-medium">Checklist <span className="text-muted">{done}/{items.length}</span></h3>
        {items.length > 0 && <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-surface-secondary"><span className="block h-full rounded-full bg-success" style={{ width: `${Math.round((100 * done) / items.length)}%` }} /></span>}
        {canEdit && <Button size="sm" variant="ghost" className="ml-auto" onPress={openTpl}><ListChecks size={15} />Chèn từ mẫu</Button>}</div>
      {showTpl && (
        <div className="flex flex-col gap-1 rounded-[14px] bg-surface p-2" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
          {(tpls || []).map((t) => (
            <div key={t.id} className="flex items-center gap-2 rounded-lg px-2 py-1.5 hover:bg-surface-secondary"><span className="min-w-0 flex-1"><b className="text-[13.5px] font-medium">{t.name}</b><span className="ml-2 text-xs text-muted">{t.items.length} mục · dùng {t.uses} lần</span></span>
              <Button size="sm" variant="secondary" isDisabled={busy} onPress={() => apply(t.id, "append")}>Thêm vào cuối</Button>
              {items.length > 0 && <Button size="sm" variant="ghost" isDisabled={busy} onPress={() => apply(t.id, "replace")}>Thay thế</Button>}</div>))}
          {tpls && !tpls.length && <p className="px-2 py-2 text-sm text-muted">Công ty chưa có mẫu checklist. Quản trị tạo mẫu ở Tài khoản › Mẫu checklist.</p>}
        </div>)}
      {items.length > 0 && (
        <ul className="flex flex-col overflow-hidden rounded-[14px] bg-surface" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
          {items.map((it, i) => (
            <li key={it.id} className="flex items-center gap-2 border-t border-separator px-3 py-1.5 first:border-t-0">
              <button type="button" disabled={!canEdit || busy} aria-pressed={it.done} aria-label={`${it.done ? "Bỏ tick" : "Tick"}: ${it.title}`} onClick={() => save(items.map((x, j) => (j === i ? { ...x, done: !x.done } : x)))} className="grid size-9 shrink-0 place-items-center">
                {it.done ? <CheckSquare size={20} weight="fill" className="text-act" /> : <Square size={20} className="text-faint" />}</button>
              <span className={`min-w-0 flex-1 text-[13.5px] [overflow-wrap:anywhere] ${it.done ? "text-faint line-through" : ""}`}>{it.title}</span>
              {canEdit && <button type="button" disabled={busy} aria-label={`Xóa mục: ${it.title}`} onClick={() => save(items.filter((_, j) => j !== i))} className="grid size-8 place-items-center text-faint hover:text-danger"><X size={14} /></button>}
            </li>))}
        </ul>)}
      {!items.length && !canEdit && <p className="text-sm text-muted">Chưa có checklist.</p>}
      {canEdit && (
        <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); const t = text.trim(); if (!t) return; save([...items, { title: t, done: false }]).then(() => setText("")); }}>
          <input value={text} onChange={(e) => setText(e.target.value)} aria-label="Thêm mục checklist" placeholder="Thêm mục…" maxLength={300} className="h-9 min-w-0 flex-1 rounded-lg border border-border bg-field-background px-3 text-[13.5px]" />
          <Button type="submit" size="sm" variant="secondary" isDisabled={!text.trim() || busy}><Plus size={14} weight="bold" />Thêm</Button>
        </form>)}
    </section>
  );
}
