import { useCallback, useEffect, useRef, useState } from "react";
import { Bell, Sparkle } from "@phosphor-icons/react";
import { useApp } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { ago, initials } from "../lib/format.js";

// Chuông thông báo (design/README.md §14): popover dưới chuông, chip lọc Tất cả / Nhắc tên tôi / Từ AI, bấm một mục mở thẳng việc. Hỏi máy chủ mỗi 60 giây khi tab đang hiện.
const FILTERS = [["all", "Tất cả"], ["mention", "Nhắc tên tôi"], ["ai", "Từ AI"]];

export default function Notifications() {
  const { companyId, openTask } = useApp();
  const [open, setOpen] = useState(false), [filter, setFilter] = useState("all");
  const [data, setData] = useState({ unread: 0, items: [] }), [err, setErr] = useState(null);
  const box = useRef(null);
  const load = useCallback(async (f = filter) => {
    if (!companyId) return;
    try { setData(await rpc("app_notifications", { company_id: companyId, filter: f, limit: 30 })); setErr(null); } catch (e) { setErr(e); }
  }, [companyId, filter]);
  useEffect(() => { load(); }, [load]);
  useEffect(() => { const t = setInterval(() => { if (!document.hidden) load(); }, 60_000); return () => clearInterval(t); }, [load]);
  useEffect(() => {
    if (!open) return;
    const click = (e) => { if (box.current && !box.current.contains(e.target)) setOpen(false); }, key = (e) => { if (e.key === "Escape") setOpen(false); };
    addEventListener("mousedown", click); addEventListener("keydown", key); return () => { removeEventListener("mousedown", click); removeEventListener("keydown", key); };
  }, [open]);
  const readAll = async () => { await rpc("app_notifications_read", { company_id: companyId, all: true }); load(); };
  const pick = async (n) => {
    setOpen(false);
    if (!n.read) { rpc("app_notifications_read", { company_id: companyId, ids: [n.id] }).then(() => load()).catch(() => {}); }
    if (n.task) openTask(n.task);
  };
  const badge = data.unread > 99 ? "99+" : data.unread;
  return (
    <div className="relative" ref={box}>
      <button type="button" aria-label={data.unread ? `Thông báo, ${data.unread} chưa đọc` : "Thông báo"} aria-haspopup="dialog" aria-expanded={open} onClick={() => { setOpen((o) => !o); if (!open) load(); }}
        className="relative grid size-9 place-items-center rounded-lg text-muted hover:bg-surface-secondary hover:text-foreground">
        <Bell size={20} weight={data.unread ? "fill" : "regular"} aria-hidden="true" />
        {data.unread > 0 && <span className="absolute -right-0.5 -top-0.5 grid h-[18px] min-w-[18px] place-items-center rounded-full bg-danger px-1 text-[10px] font-semibold leading-none text-danger-foreground">{badge}</span>}
      </button>
      {open && (
        <div role="dialog" aria-label="Thông báo" className="absolute right-0 top-full z-40 mt-2 flex max-h-[min(560px,80dvh)] w-[min(400px,calc(100vw-1rem))] flex-col overflow-hidden rounded-[14px] bg-overlay" style={{ boxShadow: "0 0 0 1px var(--border), 0 16px 40px rgba(0,0,0,.45)" }}>
          <header className="flex items-center gap-2 px-4 pb-2 pt-3"><h2 className="font-medium">Thông báo</h2><span className="text-xs text-muted">{data.unread} chưa đọc</span>
            <button type="button" onClick={readAll} disabled={!data.unread} className="ml-auto text-[13px] font-medium text-act hover:underline disabled:opacity-40">Đánh dấu đã đọc</button></header>
          <div className="flex gap-1.5 px-4 pb-2" role="group" aria-label="Lọc thông báo">
            {FILTERS.map(([k, l]) => <button key={k} type="button" aria-pressed={filter === k} onClick={() => { setFilter(k); load(k); }} className={`h-7 whitespace-nowrap rounded-full px-3 text-[12.5px] font-medium ${filter === k ? "bg-accent-soft text-act" : "text-muted hover:bg-surface-secondary"}`} style={{ boxShadow: `inset 0 0 0 1px ${filter === k ? "var(--accent)" : "var(--border)"}` }}>{l}</button>)}
          </div>
          <ul className="flex-1 overflow-y-auto border-t border-separator">
            {err && <li className="px-4 py-3 text-sm text-danger">{err.message}</li>}
            {data.items.map((n) => (
              <li key={n.id}><button type="button" onClick={() => pick(n)} className={`flex w-full items-start gap-3 border-b border-separator px-4 py-3 text-left hover:bg-surface-secondary ${n.read ? "" : "bg-accent-soft/40"}`}>
                {n.ai ? <span className="grid size-8 shrink-0 place-items-center rounded-lg border border-ai bg-ai-bg text-ai" aria-label="AI"><Sparkle size={16} weight="fill" /></span>
                  : <span className="grid size-8 shrink-0 place-items-center rounded-full border border-border bg-surface-secondary text-xs font-medium">{initials(n.who || "?")}</span>}
                <span className="flex min-w-0 flex-1 flex-col gap-0.5"><span className="text-[13.5px] leading-snug [overflow-wrap:anywhere]">{n.title}</span>
                  {n.body && <span className="line-clamp-2 text-xs text-muted [overflow-wrap:anywhere]">{n.body}</span>}
                  <span className="text-[11.5px] text-faint">{ago(n.at)}</span></span>
                {!n.read && <i className="mt-1.5 size-2 shrink-0 rounded-full bg-accent" aria-label="Chưa đọc" />}
              </button></li>))}
            {!data.items.length && !err && <li className="px-4 py-8 text-center text-sm text-muted">{filter === "all" ? "Chưa có thông báo nào." : "Không có thông báo nào trong mục này."}</li>}
          </ul>
        </div>)}
    </div>
  );
}
