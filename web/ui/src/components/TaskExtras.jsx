import { useEffect, useMemo, useRef, useState } from "react";
import { Button, toast } from "@heroui/react";
import { Tag, X, Bell, BellSlash, Link as LinkIcon, Warning, Stack, Trash, Prohibit, Plus, ArrowsClockwise } from "@phosphor-icons/react";
import { useApp, go } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { isOpen, dt, ddmmyyyy, parseDate } from "../lib/format.js";
import { SelectField, TextInput } from "./ui.jsx";
import { remindAt } from "../lib/quickadd.js";

const chipCls = "inline-flex h-7 items-center gap-1 rounded-full bg-surface pl-2.5 pr-1.5 text-[13px] text-foreground";
const ring = { boxShadow: "inset 0 0 0 1px var(--border)" };

// ---- Nhãn: gõ rồi Enter/dấu phẩy để thêm; gợi ý từ nhãn đã có và từ các việc giống (app_tag_suggest) ----
export function TagsInput({ value, onChange, title = "", description = "", disabled = false }) {
  const { companyId } = useApp();
  const [text, setText] = useState(""), [all, setAll] = useState([]), [sug, setSug] = useState([]);
  useEffect(() => { let a = true; rpc("app_tags", { company_id: companyId }).then((x) => a && setAll(x)).catch(() => {}); return () => { a = false; }; }, [companyId]);
  useEffect(() => {
    if (disabled || (title || "").trim().length < 3) { setSug([]); return; }
    let a = true; const h = setTimeout(() => rpc("app_tag_suggest", { company_id: companyId, title, description }).then((x) => a && setSug(x)).catch(() => {}), 500);
    return () => { a = false; clearTimeout(h); };
  }, [companyId, title, description, disabled]);
  const has = (n) => value.some((v) => v.toLowerCase() === n.toLowerCase());
  const add = (raw) => { const n = raw.replace(/^#+/, "").replace(/\s+/g, " ").trim().slice(0, 30); if (n && !has(n) && value.length < 8) onChange([...value, n]); setText(""); };
  const pool = useMemo(() => all.filter((t) => !has(t.name) && (!text || t.name.toLowerCase().includes(text.toLowerCase()))).slice(0, 6), [all, value, text]);   // eslint-disable-line
  const picks = sug.filter((n) => !has(n));
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-sm font-medium">Nhãn</span>
      <div className="flex min-h-10 flex-wrap items-center gap-1.5 rounded-xl px-2 py-1.5" style={ring}>
        {value.map((n) => <span key={n} className={chipCls} style={ring}><Tag size={13} aria-hidden="true" />{n}
          {!disabled && <button type="button" aria-label={`Bỏ nhãn ${n}`} onClick={() => onChange(value.filter((x) => x !== n))} className="grid size-5 place-items-center rounded-full text-muted hover:bg-surface-secondary"><X size={11} weight="bold" /></button>}</span>)}
        {!disabled && value.length < 8 && <input value={text} onChange={(e) => setText(e.target.value)} aria-label="Thêm nhãn" placeholder={value.length ? "" : "Gõ nhãn rồi Enter"}
          onKeyDown={(e) => { if (e.key === "Enter" || e.key === ",") { e.preventDefault(); e.stopPropagation(); add(text); } else if (e.key === "Backspace" && !text && value.length) onChange(value.slice(0, -1)); }}
          onBlur={() => text && add(text)} className="h-7 min-w-[120px] flex-1 bg-transparent text-[14px] outline-none placeholder:text-faint" />}
      </div>
      {!disabled && (picks.length > 0 || pool.length > 0) && (
        <div className="flex flex-wrap items-center gap-1.5 text-[13px]">
          {picks.length > 0 && <span className="text-muted">Gợi ý:</span>}
          {picks.map((n) => <button key={`s${n}`} type="button" onClick={() => add(n)} className="h-7 rounded-full bg-ai-bg px-2.5 text-ai hover:opacity-80" title="Gợi ý theo tiêu đề và các việc giống">✦ {n}</button>)}
          {pool.filter((t) => !picks.includes(t.name)).map((t) => <button key={t.id} type="button" onClick={() => add(t.name)} className="h-7 rounded-full px-2.5 text-muted hover:bg-surface-secondary" style={ring}>{t.name}</button>)}
        </div>)}
    </div>
  );
}

// ---- Giờ nhắc riêng của việc ----
const REMIND = [["none", "Không nhắc"], ["due8", "8:00 sáng ngày hạn"], ["day8", "8:00 sáng, 1 ngày trước hạn"], ["custom", "Chọn giờ cụ thể…"]];
export function remindFrom(mode, due, custom) {
  if (mode === "due8") return remindAt(due, "08:00");
  if (mode === "day8") { const d = parseDate(due); if (!d) return null; d.setDate(d.getDate() - 1); return remindAt(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`, "08:00"); }
  if (mode === "custom" && custom) return new Date(custom).toISOString();
  return null;
}
export function RemindPicker({ mode, onMode, custom, onCustom, due, extraOptions = [] }) {
  const at = remindFrom(mode, due, custom);
  const needDue = (mode === "due8" || mode === "day8") && !due;
  return (
    <div className="flex flex-col gap-1.5">
      <SelectField label="Nhắc việc" value={mode} onChange={(v) => onMode(v || "none")} options={[...extraOptions, ...REMIND.map(([value, label]) => ({ value, label }))]} />
      {mode === "custom" && <TextInput label="Giờ nhắc" type="datetime-local" value={custom} onChange={onCustom} />}
      {needDue && <p className="text-sm text-warning">Cần chọn hạn chót để tính giờ nhắc.</p>}
      {at && <p className="text-sm text-muted"><Bell size={13} className="mr-1 inline" aria-hidden="true" />Sẽ báo ở chuông lúc {dt(at)}</p>}
    </div>
  );
}

// ---- Việc phải chờ (B chờ A) ----
export function DepsPicker({ value, onChange, exclude = null, disabled = false }) {
  const { companyId } = useApp();
  const [open, setOpen] = useState(false), [q, setQ] = useState(""), [list, setList] = useState(null), [known, setKnown] = useState({});
  useEffect(() => { if (!open || list) return; rpc("app_tasks", { company_id: companyId, days: 60 }).then((x) => { setList(x.filter(isOpen)); setKnown((k) => ({ ...k, ...Object.fromEntries(x.map((t) => [t.id, t.title])) })); }).catch(() => setList([])); }, [open, list, companyId]);
  const res = useMemo(() => (list || []).filter((t) => t.id !== exclude && !value.includes(t.id) && (!q || `${t.title} T-${t.id}`.toLowerCase().includes(q.toLowerCase()))).slice(0, 8), [list, q, value, exclude]);
  return (
    <div className="flex flex-col gap-1.5">
      <span className="text-sm font-medium">Phải chờ việc khác xong</span>
      <div className="flex flex-wrap items-center gap-1.5">
        {value.map((id) => <span key={id} className={chipCls} style={ring}><Prohibit size={13} aria-hidden="true" />T-{id}{known[id] ? ` · ${known[id].slice(0, 28)}` : ""}
          {!disabled && <button type="button" aria-label={`Bỏ chờ T-${id}`} onClick={() => onChange(value.filter((x) => x !== id))} className="grid size-5 place-items-center rounded-full text-muted hover:bg-surface-secondary"><X size={11} weight="bold" /></button>}</span>)}
        {!disabled && value.length < 10 && <button type="button" onClick={() => setOpen((o) => !o)} aria-expanded={open} className="inline-flex h-7 items-center gap-1 rounded-full px-2.5 text-[13px] font-medium text-act hover:bg-accent-soft"><Plus size={12} weight="bold" />Thêm việc phải chờ</button>}
      </div>
      {open && (
        <div className="flex flex-col gap-1.5 rounded-xl p-2" style={ring}>
          <input autoFocus value={q} onChange={(e) => setQ(e.target.value)} placeholder="Tìm việc theo tên hoặc T-số" aria-label="Tìm việc phải chờ" className="h-9 rounded-lg bg-surface px-3 text-[14px] outline-none" />
          {!list ? <p className="px-1 text-sm text-muted">Đang tải…</p> : res.length === 0 ? <p className="px-1 text-sm text-muted">Không có việc nào khớp.</p> :
            res.map((t) => <button key={t.id} type="button" onClick={() => { onChange([...value, t.id]); setKnown((k) => ({ ...k, [t.id]: t.title })); setQ(""); setOpen(false); }} className="flex items-center gap-2 rounded-lg px-2 py-1.5 text-left text-[14px] hover:bg-surface-secondary"><span className="text-muted">T-{t.id}</span><span className="truncate">{t.title}</span></button>)}
        </div>)}
      {value.length > 0 && <p className="text-sm text-muted">Việc này chưa chuyển sang Chờ duyệt/Xong được khi các việc trên còn mở; khi xong hết, người làm được báo.</p>}
    </div>
  );
}

// ---- Cảnh báo trùng: hiện việc đang mở giống tiêu đề đang gõ ----
export function DupWarning({ title, exclude = null }) {
  const { companyId, lookups, openTask } = useApp();
  const [items, setItems] = useState([]);
  useEffect(() => {
    if ((title || "").trim().length < 6) { setItems([]); return; }
    let a = true; const h = setTimeout(() => rpc("app_task_similar", { company_id: companyId, title, exclude }).then((x) => a && setItems(x)).catch(() => a && setItems([])), 600);
    return () => { a = false; clearTimeout(h); };
  }, [companyId, title, exclude]);
  if (!items.length) return null;
  return (
    <div role="status" className="rounded-xl bg-wn-bg px-3.5 py-2.5 text-[13.5px]" style={{ boxShadow: "inset 0 0 0 1px var(--warning)" }}>
      <p className="flex items-center gap-1.5 font-medium text-warning"><Warning size={15} weight="fill" aria-hidden="true" />Có thể trùng với việc đang mở:</p>
      <ul className="mt-1 flex flex-col gap-0.5">{items.map((x) => (
        <li key={x.id}><button type="button" onClick={() => openTask(x.id)} className="text-left text-foreground underline decoration-dotted underline-offset-2 hover:text-act">T-{x.id} · {x.title}</button>
          <span className="text-muted"> — {lookups.person[x.assignee_id]?.name || "chưa giao"}{x.due_date ? `, hạn ${ddmmyyyy(parseDate(x.due_date))}` : ""}</span></li>))}</ul>
      <p className="mt-1 text-muted">Bấm để xem trước. Vẫn tạo được nếu đây là việc khác.</p>
    </div>
  );
}

// ---- Mẫu việc: chọn để điền sẵn form, lưu form hiện tại thành mẫu, xóa mẫu ----
export function TemplatePicker({ onApply, current }) {
  const { companyId } = useApp();
  const [list, setList] = useState(null), [open, setOpen] = useState(false), [name, setName] = useState(""), [busy, setBusy] = useState(false);
  const load = () => rpc("app_task_templates", { company_id: companyId }).then(setList).catch(() => setList([]));
  useEffect(() => { load(); }, [companyId]);   // eslint-disable-line
  async function saveCur() {
    setBusy(true);
    try { await rpc("app_task_template_save", { company_id: companyId, name, body: current() }); toast.success(`Đã lưu mẫu "${name}"`); setName(""); await load(); }
    catch (e) { toast.danger(e.message); } finally { setBusy(false); }
  }
  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap items-center gap-2">
        <Button size="sm" variant="secondary" onPress={() => setOpen((o) => !o)} aria-expanded={open}><Stack className="size-4" />Mẫu việc{list?.length ? ` (${list.length})` : ""}</Button>
        {open && <span className="text-sm text-muted">Chọn mẫu để điền sẵn; hoặc đặt tên rồi lưu form hiện tại thành mẫu.</span>}
      </div>
      {open && (
        <div className="flex flex-col gap-2 rounded-xl p-2.5" style={ring}>
          {!list ? <p className="text-sm text-muted">Đang tải…</p> : list.length === 0 ? <p className="text-sm text-muted">Chưa có mẫu nào.</p> :
            list.map((t) => (
              <div key={t.id} className="flex items-center gap-2">
                <button type="button" onClick={() => { onApply(t); setOpen(false); }} className="min-w-0 flex-1 rounded-lg px-2 py-1.5 text-left hover:bg-surface-secondary"><span className="block truncate text-[14px] font-medium">{t.name}</span>
                  <span className="block truncate text-[12.5px] text-muted">{t.body.title}{t.body.checklist?.length ? ` · ${t.body.checklist.length} mục checklist` : ""}{t.body.subtasks?.length ? ` · ${t.body.subtasks.length} việc con` : ""}{t.uses ? ` · dùng ${t.uses} lần` : ""}</span></button>
                <Button isIconOnly size="sm" variant="ghost" aria-label={`Xóa mẫu ${t.name}`} onPress={async () => { if (!confirm(`Xóa mẫu "${t.name}"?`)) return; try { await rpc("app_task_template_delete", { id: t.id }); await load(); } catch (e) { toast.danger(e.message); } }}><Trash className="size-4" /></Button>
              </div>))}
          <div className="flex items-end gap-2 border-t border-separator pt-2">
            <TextInput label="Lưu form hiện tại thành mẫu" value={name} onChange={setName} placeholder="Ví dụ: Hồ sơ thuê kho" />
            <Button variant="secondary" isPending={busy} isDisabled={name.trim().length < 2} onPress={saveCur}>Lưu mẫu</Button>
          </div>
        </div>)}
    </div>
  );
}

// ---- Đính kèm lúc tạo: dán link Google Drive/Docs ----
export function AttachInput({ value, onChange }) {
  const [url, setUrl] = useState(""), [name, setName] = useState(""), ref = useRef(null);
  const ok = /^https:\/\/(drive|docs)\.google\.com\//.test(url.trim());
  const add = () => { if (!ok) return; onChange([...value, { url: url.trim(), name: name.trim() }]); setUrl(""); setName(""); ref.current?.focus(); };
  return (
    <div className="flex flex-col gap-2">
      <span className="text-sm font-medium">Đính kèm (link Google Drive)</span>
      {value.map((a, i) => <div key={i} className={`${chipCls} max-w-full self-start`} style={ring}><LinkIcon size={13} aria-hidden="true" /><span className="truncate">{a.name || a.url}</span>
        <button type="button" aria-label="Bỏ đính kèm" onClick={() => onChange(value.filter((_, j) => j !== i))} className="grid size-5 shrink-0 place-items-center rounded-full text-muted hover:bg-surface-secondary"><X size={11} weight="bold" /></button></div>)}
      {value.length < 10 && (
        <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
          <TextInput label="Link" type="url" value={url} onChange={setUrl} placeholder="https://drive.google.com/…" className="w-full sm:flex-[2]" />
          <TextInput label="Tên hiển thị" value={name} onChange={setName} placeholder="Bản nháp v2" className="w-full sm:flex-1" />
          <Button variant="secondary" isDisabled={!ok} onPress={add}>Thêm</Button>
        </div>)}
      {url && !ok && <p className="text-sm text-warning">Chỉ nhận liên kết drive.google.com hoặc docs.google.com. Tải tệp trực tiếp từ máy chưa hỗ trợ (máy chủ web không giữ quyền Drive).</p>}
    </div>
  );
}

// ---- Khối ở ngăn chi tiết việc: nhãn, việc phải chờ, nhắc, nhân bản ----
export function DrawerExtras({ task, extras, canEdit, onChanged }) {
  const [tags, setTags] = useState(extras?.tags || []);
  const [mode, setMode] = useState("none"), [custom, setCustom] = useState(""), [deps, setDeps] = useState((extras?.depends_on || []).map((d) => d.id));
  const [busy, setBusy] = useState("");
  useEffect(() => { setTags(extras?.tags || []); setDeps((extras?.depends_on || []).map((d) => d.id)); setMode("none"); setCustom(""); }, [extras, task.id]);
  const act = async (k, fn, ok) => { setBusy(k); try { await fn(); if (ok) toast.success(ok); onChanged(); } catch (e) { toast.danger(e.message); } finally { setBusy(""); } };
  const blocked = extras?.blocked_by || [];
  const open = isOpen(task);
  const hasRemind = !!extras?.remind_at && !extras?.reminded_at;
  return (
    <section className="flex flex-col gap-3" aria-label="Nhãn, phụ thuộc và nhắc việc">
      {open && blocked.length > 0 && (
        <p className="flex flex-wrap items-center gap-1.5 rounded-xl bg-wn-bg px-3.5 py-2.5 text-[13.5px] text-warning" style={{ boxShadow: "inset 0 0 0 1px var(--warning)" }}><Prohibit size={15} weight="fill" aria-hidden="true" />
          Đang chờ {blocked.map((id) => <button key={id} type="button" onClick={() => go(location.hash.replace(/^#\/?/, "").split("?")[0] || "tasks", { t: String(id) })} className="font-semibold underline decoration-dotted">T-{id}</button>)} xong mới nộp/hoàn thành được.</p>)}
      {(extras?.dependents || []).length > 0 && <p className="text-[13.5px] text-muted">Đang có việc chờ việc này: {extras.dependents.map((d) => `T-${d.id}`).join(", ")}.</p>}
      <div className="flex flex-wrap items-start gap-x-6 gap-y-3">
        <div className="min-w-[240px] flex-1">
          {canEdit ? <><TagsInput value={tags} onChange={setTags} title={task.title} description={task.description || ""} />
            {JSON.stringify(tags) !== JSON.stringify(extras?.tags || []) && <Button size="sm" className="mt-2" isPending={busy === "tags"} onPress={() => act("tags", () => rpc("app_task_tags_set", { task: task.id, tags }), "Đã lưu nhãn")}>Lưu nhãn</Button>}</>
            : <div className="flex flex-wrap items-center gap-1.5">{(extras?.tags || []).map((n) => <span key={n} className={chipCls} style={ring}><Tag size={13} aria-hidden="true" />{n}</span>)}</div>}
        </div>
        {canEdit && <div className="min-w-[240px] flex-1">
          <DepsPicker value={deps} onChange={setDeps} exclude={task.id} />
          {JSON.stringify([...deps].sort()) !== JSON.stringify((extras?.depends_on || []).map((d) => d.id).sort()) && <Button size="sm" className="mt-2" isPending={busy === "deps"} onPress={() => act("deps", () => rpc("app_task_deps_set", { task: task.id, depends_on: deps }), "Đã lưu")}>Lưu việc phải chờ</Button>}
        </div>}
      </div>
      {open && canEdit && (
        <div className="flex flex-wrap items-end gap-3">
          <div className="min-w-[260px] flex-1">
            {hasRemind && <p className="mb-1.5 flex items-center gap-1.5 text-[13.5px]"><Bell size={14} weight="fill" className="text-info" aria-hidden="true" />Đang nhắc lúc <b className="font-medium">{dt(extras.remind_at)}</b></p>}
            <RemindPicker mode={mode} onMode={setMode} custom={custom} onCustom={setCustom} due={task.due_date} /></div>
          {mode !== "none" && <Button size="sm" isPending={busy === "remind"} isDisabled={!remindFrom(mode, task.due_date, custom)} onPress={() => act("remind", () => rpc("app_task_remind", { task: task.id, remind_at: remindFrom(mode, task.due_date, custom) }), "Đã đặt nhắc")}><Bell className="size-4" />Đặt nhắc</Button>}
          {hasRemind && <Button size="sm" variant="ghost" isPending={busy === "unremind"} onPress={() => act("unremind", () => rpc("app_task_remind", { task: task.id, remind_at: null }), "Đã bỏ nhắc")}><BellSlash className="size-4" />Bỏ nhắc</Button>}
        </div>)}
      {extras?.reminded_at && <p className="text-[13px] text-faint">Đã nhắc lúc {dt(extras.reminded_at)}.</p>}
    </section>
  );
}

export function CloneButton({ task, hasChildren }) {
  const { openTask, refresh } = useApp();
  const [busy, setBusy] = useState(false);
  const clone = async (subtasks) => {
    setBusy(true);
    try { const r = await rpc("app_task_clone", { task: task.id, subtasks }); toast.success(`Đã nhân bản thành T-${r.id}`); refresh(); openTask(r.id); }
    catch (e) { toast.danger(e.message); } finally { setBusy(false); }
  };
  return (<>
    <Button size="sm" variant="secondary" isPending={busy} onPress={() => clone(false)}><ArrowsClockwise className="size-4" />Nhân bản</Button>
    {hasChildren && <Button size="sm" variant="ghost" isPending={busy} onPress={() => clone(true)}>Nhân bản kèm việc con</Button>}
  </>);
}
