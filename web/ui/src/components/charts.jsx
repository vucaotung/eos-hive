import { Coffee, Gauge, HourglassMedium, WarningOctagon } from "@phosphor-icons/react";
import { LOAD } from "../lib/stats.js";

export function Seg({ value, onChange, options, label }) {
  return (
    <div className="inline-flex rounded-lg p-0.5" role="group" aria-label={label} style={{ boxShadow: "inset 0 0 0 1px var(--border)" }}>
      {options.map(([k, l]) => (
        <button key={k} type="button" aria-pressed={value === k} onClick={() => onChange(k)}
          className={`h-8 whitespace-nowrap rounded-md px-3 text-[13px] font-medium ${value === k ? "bg-accent-soft text-act" : "text-muted hover:text-foreground"}`}
          style={value === k ? { boxShadow: "inset 0 0 0 1px var(--accent)" } : undefined}>{l}</button>))}
    </div>
  );
}

// Ô chỉ số: viền trên theo ngữ nghĩa, icon + nhãn nhỏ, số lớn tabular
export function Tile({ icon: Icon, label, value, sub, tone = "var(--accent)", onPress, bad }) {
  const C = onPress ? "button" : "div";
  return (
    <C type={onPress ? "button" : undefined} onClick={onPress} className="flex flex-col gap-1 rounded-[14px] bg-surface px-4 py-3 text-left hover:bg-surface-secondary" style={{ boxShadow: `0 0 0 1px var(--separator), inset 0 2px 0 ${tone}` }}>
      <span className="flex items-center gap-1.5 text-xs font-medium text-muted">{Icon && <Icon size={14} aria-hidden="true" />}{label}</span>
      <b className={`text-[28px] font-medium leading-none tabular-nums ${bad ? "text-danger" : ""}`}>{value}</b>
      {sub && <span className="text-[11.5px] text-faint">{sub}</span>}
    </C>
  );
}

export function Card({ title, aside, children, className = "" }) {
  return (
    <section className={`flex flex-col gap-3 rounded-[14px] bg-surface p-4 ${className}`} style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
      {(title || aside) && <header className="flex items-baseline justify-between gap-3"><h2 className="font-medium">{title}</h2>{aside}</header>}
      {children}
    </section>
  );
}

// Thanh xếp chồng: parts = [{label, value, color}]
export function StackBar({ parts, height = 14 }) {
  const total = parts.reduce((s, p) => s + p.value, 0) || 1;
  return (
    <div role="img" aria-label={parts.map((p) => `${p.label} ${p.value}`).join(", ")} className="flex w-full overflow-hidden rounded-full bg-surface-secondary" style={{ height }}>
      {parts.filter((p) => p.value > 0).map((p) => <span key={p.label} style={{ width: `${(100 * p.value) / total}%`, background: p.color }} />)}
    </div>
  );
}
export const Legend = ({ parts }) => (
  <ul className="grid grid-cols-2 gap-x-4 gap-y-1 text-[12.5px]">
    {parts.map((p) => <li key={p.label} className="flex items-center gap-1.5"><i className="size-2.5 rounded-sm" style={{ background: p.color }} /><span className="text-muted">{p.label}</span><b className="ml-auto font-medium tabular-nums">{p.value}</b></li>)}
  </ul>
);

// Thước tải 4 nấc + pill
const LOAD_ICON = [Coffee, Gauge, HourglassMedium, WarningOctagon];
export function LoadMeter({ level }) {
  const l = LOAD[level], Icon = LOAD_ICON[level];
  return (
    <span className="inline-flex items-center gap-2">
      <span className="inline-flex gap-0.5" aria-hidden="true">{LOAD.map((x, i) => <i key={x.id} className="h-2 w-4 rounded-sm" style={{ background: i <= level ? l.tone : "var(--separator)" }} />)}</span>
      <span className="inline-flex h-6 items-center gap-1 rounded-full px-2 text-xs font-medium" style={{ color: l.tone, boxShadow: "inset 0 0 0 1px currentColor" }}><Icon size={13} weight="fill" aria-hidden="true" />{l.label}</span>
    </span>
  );
}
