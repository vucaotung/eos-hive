import { useEffect, useRef, useState } from "react";
import { MagnifyingGlassMinus, MagnifyingGlassPlus } from "@phosphor-icons/react";

// Phóng to/thu nhỏ cho Gantt và Mindmap: chụm hai ngón (cảm ứng), Ctrl + lăn chuột, hoặc nút +/−. Giới hạn 50%–220%. Dùng CSS `zoom` nên bố cục và thanh cuộn co giãn đúng.
const MIN = 0.5, MAX = 2.2;
const clamp = (v) => Math.min(MAX, Math.max(MIN, Math.round(v * 100) / 100));

export default function ZoomBox({ children, label = "Phóng to thu nhỏ" }) {
  const [s, setS] = useState(1), box = useRef(null), st = useRef({ d: 0, s: 1 }), cur = useRef(1);
  cur.current = s;
  useEffect(() => {
    const el = box.current; if (!el) return;
    const dist = (t) => Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY);
    const start = (e) => { if (e.touches.length === 2) st.current = { d: dist(e.touches), s: cur.current }; };
    const move = (e) => { if (e.touches.length === 2 && st.current.d) { e.preventDefault(); setS(clamp(st.current.s * dist(e.touches) / st.current.d)); } };
    const end = () => { st.current.d = 0; };
    const wheel = (e) => { if (e.ctrlKey || e.metaKey) { e.preventDefault(); setS((v) => clamp(v * (e.deltaY < 0 ? 1.1 : 0.9))); } };
    el.addEventListener("touchstart", start, { passive: true }); el.addEventListener("touchmove", move, { passive: false }); el.addEventListener("touchend", end); el.addEventListener("wheel", wheel, { passive: false });
    return () => { el.removeEventListener("touchstart", start); el.removeEventListener("touchmove", move); el.removeEventListener("touchend", end); el.removeEventListener("wheel", wheel); };
  }, []);
  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-1" role="group" aria-label={label}>
        <button type="button" aria-label="Thu nhỏ" disabled={s <= MIN} onClick={() => setS((v) => clamp(v - 0.15))} className="grid size-9 place-items-center rounded-lg text-muted hover:bg-surface-secondary disabled:opacity-40"><MagnifyingGlassMinus size={18} /></button>
        <button type="button" aria-label="Về 100%" onClick={() => setS(1)} className="h-9 min-w-14 rounded-lg px-2 text-[13px] font-medium tabular-nums text-muted hover:bg-surface-secondary">{Math.round(s * 100)}%</button>
        <button type="button" aria-label="Phóng to" disabled={s >= MAX} onClick={() => setS((v) => clamp(v + 0.15))} className="grid size-9 place-items-center rounded-lg text-muted hover:bg-surface-secondary disabled:opacity-40"><MagnifyingGlassPlus size={18} /></button>
        <span className="ml-2 hidden text-xs text-faint sm:inline">Chụm hai ngón hoặc Ctrl + lăn chuột để phóng to</span>
      </div>
      <div ref={box} className="overflow-auto" style={{ touchAction: "pan-x pan-y" }}><div style={{ zoom: s }}>{children}</div></div>
    </div>
  );
}
