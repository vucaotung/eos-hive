import { useMemo, useRef, useState } from "react";
import { useApp } from "../lib/store.jsx";
import { AgentChip, Person } from "./ui.jsx";

// Ô nhập có menu nhắc tên: gõ "@" để chọn người (và agent AI), lọc theo chữ gõ (không phân biệt dấu/hoa thường), ↑↓ chọn, Enter/Tab chèn, Esc đóng.
// Chèn đúng "@Họ tên đầy đủ": máy chủ nhận ra tên này để gửi thông báo cho người được nhắc (agent chỉ hiển thị, không nhận thông báo).
const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/g, "d").replace(/Đ/g, "D").toLowerCase();

export default function MentionTextArea({ value, onChange, placeholder, rows = 2, label = "Nội dung", onSubmit }) {
  const { org, me } = useApp();
  const ref = useRef(null);
  const [q, setQ] = useState(null), [at, setAt] = useState(0), [idx, setIdx] = useState(0);
  const opts = useMemo(() => {
    const people = org.members.filter((m) => m.active && m.user).map((m) => ({ key: m.user.id, name: m.user.name, user: m.user }));
    const agents = (me?.agents || []).map((a) => ({ key: `agent:${a.code}`, name: a.name, ai: true }));
    return [...people, ...agents];
  }, [org.members, me]);
  const shown = q == null ? [] : opts.filter((o) => norm(o.name).includes(norm(q))).slice(0, 6);
  function detect(text, caret) {
    const before = text.slice(0, caret), i = before.lastIndexOf("@");
    if (i < 0 || (i > 0 && !/\s/.test(before[i - 1]))) return setQ(null);
    const part = before.slice(i + 1);
    if (/\n/.test(part) || part.length > 30) return setQ(null);
    setAt(i); setQ(part); setIdx(0);
  }
  function pick(o) {
    const el = ref.current, caret = el.selectionStart, ins = `@${o.name} `;
    onChange(value.slice(0, at) + ins + value.slice(caret));
    setQ(null);
    requestAnimationFrame(() => { el.focus(); const pos = at + ins.length; el.setSelectionRange(pos, pos); });
  }
  return (
    <div className="relative">
      <textarea ref={ref} aria-label={label} value={value} rows={rows} placeholder={placeholder}
        onChange={(e) => { onChange(e.target.value); detect(e.target.value, e.target.selectionStart); }}
        onClick={(e) => detect(value, e.target.selectionStart)}
        onKeyDown={(e) => {
          if (q != null && shown.length) {
            if (e.key === "ArrowDown") { e.preventDefault(); setIdx((i) => (i + 1) % shown.length); return; }
            if (e.key === "ArrowUp") { e.preventDefault(); setIdx((i) => (i - 1 + shown.length) % shown.length); return; }
            if (e.key === "Enter" || e.key === "Tab") { e.preventDefault(); pick(shown[idx]); return; }
          }
          if (e.key === "Escape" && q != null) { e.preventDefault(); e.stopPropagation(); setQ(null); return; }
          if ((e.ctrlKey || e.metaKey) && e.key === "Enter") { e.preventDefault(); onSubmit?.(); }
        }}
        className="w-full rounded-lg border border-border bg-field-background px-3 py-2 text-[14px]" />
      {q != null && shown.length > 0 && (
        <ul role="listbox" aria-label="Nhắc tên" className="absolute bottom-full left-0 z-30 mb-1 w-[min(320px,100%)] overflow-hidden rounded-xl bg-overlay py-1" style={{ boxShadow: "0 0 0 1px var(--border), 0 8px 24px rgba(0,0,0,.4)" }}>
          {shown.map((o, i) => (
            <li key={o.key} role="option" aria-selected={i === idx}>
              <button type="button" onMouseDown={(e) => { e.preventDefault(); pick(o); }} onMouseEnter={() => setIdx(i)} className={`flex w-full items-center gap-2 px-3 py-1.5 text-left text-sm ${i === idx ? "bg-accent-soft text-act" : ""}`}>
                {o.ai ? <AgentChip name={o.name} size={22} /> : <Person user={o.user} />}
              </button>
            </li>))}
        </ul>)}
    </div>
  );
}
