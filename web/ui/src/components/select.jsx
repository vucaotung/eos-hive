import { createContext, useContext, useMemo, useRef, useState } from "react";
import { Button, toast } from "@heroui/react";
import { CheckSquare, Square, X, CalendarBlank, UserSwitch, Prohibit, TrashSimple } from "@phosphor-icons/react";
import { useApp } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";

// Chọn nhiều (design/README.md §M11 và nút "Chọn nhiều" của web): nhấn giữ một dòng (mobile) hoặc bấm "Chọn nhiều" để vào chế độ chọn.
// Thao tác hàng loạt gọi app_task_save từng việc; việc nào không đủ quyền thì báo lỗi riêng (máy chủ kiểm quyền, giao diện không đoán trước).
const Ctx = createContext(null);
export const useSelect = () => useContext(Ctx);

export function SelectProvider({ children, onDone }) {
  const [on, setOn] = useState(false), [sel, setSel] = useState(() => new Set());
  const v = useMemo(() => ({
    on, sel,
    enter: (id) => { setOn(true); if (id) setSel(new Set([id])); },
    exit: () => { setOn(false); setSel(new Set()); },
    toggle: (id) => setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; }),
    setAll: (ids) => setSel(new Set(ids)), onDone,
  }), [on, sel, onDone]);
  return <Ctx.Provider value={v}>{children}</Ctx.Provider>;
}

// Dòng chọn được: nhấn giữ 500 ms vào chế độ chọn (không chặn cuộn: hủy khi ngón tay trượt)
export function useLongPress(onLong) {
  const t = useRef(null), p = useRef(null);
  const clear = () => { clearTimeout(t.current); t.current = null; };
  return {
    onTouchStart: (e) => { p.current = [e.touches[0].clientX, e.touches[0].clientY]; t.current = setTimeout(() => { navigator.vibrate?.(12); onLong(); t.current = "fired"; }, 500); },
    onTouchMove: (e) => { if (p.current && (Math.abs(e.touches[0].clientX - p.current[0]) > 8 || Math.abs(e.touches[0].clientY - p.current[1]) > 8)) clear(); },
    onTouchEnd: (e) => { if (t.current === "fired") { e.preventDefault(); } clear(); },
    onContextMenu: (e) => { if (t.current === "fired") e.preventDefault(); },
  };
}

export function SelectMark({ id }) {
  const s = useSelect(); if (!s?.on) return null;
  const on = s.sel.has(id), Icon = on ? CheckSquare : Square;
  return <Icon size={22} weight={on ? "fill" : "regular"} className={`mt-0.5 shrink-0 ${on ? "text-act" : "text-faint"}`} aria-hidden="true" />;
}

export function SelectBar({ tasks }) {
  const s = useSelect(), { org } = useApp();
  const [busy, setBusy] = useState(""), [date, setDate] = useState(""), [who, setWho] = useState(false);
  if (!s?.on) return null;
  const ids = [...s.sel], all = tasks.map((t) => t.id);
  async function run(label, patch) {
    if (!ids.length) { toast.danger("Chưa chọn việc nào"); return; }
    setBusy(label);
    const res = await Promise.allSettled(ids.map((id) => rpc("app_task_save", { id, ...patch })));
    const ok = res.filter((r) => r.status === "fulfilled").length, bad = res.filter((r) => r.status === "rejected");
    if (ok) toast.success(`${label}: ${ok}/${ids.length} việc`);
    if (bad.length) toast.danger(`${bad.length} việc không làm được: ${bad[0].reason?.message || "không đủ quyền"}`);
    setBusy(""); s.exit(); s.onDone?.();
  }
  const btn = "flex-1 min-w-[88px]";
  return (<>
    <div className="sticky top-14 z-20 flex items-center gap-3 rounded-xl bg-accent-soft px-3 py-2 text-act" style={{ boxShadow: "inset 0 0 0 1px var(--accent)" }} role="status">
      <Button isIconOnly size="sm" variant="ghost" aria-label="Thoát chế độ chọn" onPress={s.exit}><X size={16} /></Button>
      <b className="font-medium">Đã chọn {ids.length}</b>
      <Button size="sm" variant="ghost" className="ml-auto" onPress={() => s.setAll(ids.length === all.length ? [] : all)}>{ids.length === all.length ? "Bỏ chọn" : "Chọn tất cả"}</Button>
    </div>
    <div className="safe-b fixed inset-x-0 bottom-0 z-30 border-t border-separator bg-surface px-3 py-2 lg:left-60" role="toolbar" aria-label="Thao tác hàng loạt">
      {(who || date !== "") && (
        <div className="mb-2 flex items-center gap-2">
          {who ? <select aria-label="Giao cho" className="h-9 flex-1 rounded-lg border border-border bg-field-background px-2 text-sm" defaultValue="" onChange={(e) => e.target.value && run("Đã giao", { assignee_id: e.target.value })}>
            <option value="" disabled>Chọn người nhận việc</option>{org.members.filter((m) => m.active && m.user).map((m) => <option key={m.user.id} value={m.user.id}>{m.user.name}</option>)}</select>
            : <><input type="date" aria-label="Hạn mới" className="h-9 flex-1 rounded-lg border border-border bg-field-background px-2 text-sm" value={date} onChange={(e) => setDate(e.target.value)} /><Button size="sm" isDisabled={!date} isPending={busy === "Đã đổi hạn"} onPress={() => run("Đã đổi hạn", { due_date: date })}>Áp dụng</Button></>}
          <Button isIconOnly size="sm" variant="ghost" aria-label="Đóng" onPress={() => { setWho(false); setDate(""); }}><X size={14} /></Button>
        </div>)}
      <div className="flex gap-2">
        <Button className={btn} variant="secondary" size="sm" onPress={() => { setWho(false); setDate(new Date().toISOString().slice(0, 10)); }}><CalendarBlank size={16} />Đổi hạn</Button>
        <Button className={btn} variant="secondary" size="sm" onPress={() => { setDate(""); setWho(true); }}><UserSwitch size={16} />Giao cho</Button>
        <Button className={`${btn} text-danger`} variant="secondary" size="sm" isPending={busy === "Đã đánh dấu bị chặn"} onPress={() => run("Đã đánh dấu bị chặn", { status: "blocked" })}><Prohibit size={16} weight="bold" />Bị chặn</Button>
        <Button className={`${btn} text-danger`} variant="secondary" size="sm" isPending={busy === "Đã hủy"} onPress={() => { if (confirm(`Hủy ${ids.length} việc đã chọn?`)) run("Đã hủy", { status: "cancelled" }); }}><TrashSimple size={16} />Hủy việc</Button>
      </div>
    </div>
  </>);
}
