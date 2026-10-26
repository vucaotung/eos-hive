import { useEffect, useState } from "react";
import { Alert, Avatar, Button, Description, Input, Label, ListBox, Select, Skeleton, TextArea, TextField } from "@heroui/react";
import { CircleDashed, CircleHalf, PauseCircle, CheckCircle, Prohibit, WarningCircle, XCircle, HourglassMedium, ChatCircleDots, CaretDoubleUp, CaretUp, Minus, Sparkle, Star, Lightning, ClockCountdown, Clock, CalendarBlank } from "@phosphor-icons/react";
import { STATUS, PRIORITY, due, initials, ddmmyyyy } from "../lib/format.js";

export function useMedia(q) {
  const [m, setM] = useState(() => matchMedia(q).matches);
  useEffect(() => { const mq = matchMedia(q); const f = () => setM(mq.matches); mq.addEventListener("change", f); return () => mq.removeEventListener("change", f); }, [q]);
  return m;
}

// Hệ mã hoá trạng thái (design/README.md): hình dạng + màu + chữ. Nhãn giữ theo nghiệp vụ Enterprise OS.
const ST = {
  todo: [CircleDashed, "text-muted", "regular"],
  in_progress: [CircleHalf, "text-info", "fill"],
  blocked: [Prohibit, "text-danger", "bold"],
  in_review: [HourglassMedium, "text-warning", "fill"],
  done: [CheckCircle, "text-success", "fill"],
  cancelled: [XCircle, "text-faint", "regular"],
};
export function StatusIcon({ status, waiting, size = 16, className = "" }) {
  const [Icon, tone, weight] = waiting && status !== "done" ? [ChatCircleDots, "text-warning", "fill"] : ST[status] || ST.todo;
  return <Icon size={size} weight={weight} className={`shrink-0 ${tone} ${className}`} aria-hidden="true" />;
}
export function StatusBadge({ status, waiting }) {
  const [, tone] = waiting && status !== "done" ? [0, "text-warning"] : ST[status] || ST.todo;
  const label = waiting && status !== "done" ? "Chờ người trả lời" : STATUS[status];
  // "Bị chặn" = huy hiệu vuông; các trạng thái khác = pill viền
  const shape = status === "blocked" && !waiting ? "rounded" : "rounded-full";
  return (
    <span className={`inline-flex h-6 items-center gap-1.5 whitespace-nowrap px-2.5 text-xs font-semibold ${shape} ${tone}`} style={{ boxShadow: "inset 0 0 0 1px currentColor" }}>
      <StatusIcon status={status} waiting={waiting} size={14} className="!text-current" />{label}
    </span>
  );
}

export function PriorityMark({ priority }) {
  if (!priority) return null;
  const [Icon, tone] = priority === "urgent" || priority === "high" ? [CaretDoubleUp, "text-danger"] : priority === "medium" ? [CaretUp, "text-warning"] : [Minus, "text-muted"];
  return <span className={`inline-flex items-center gap-1 whitespace-nowrap text-xs font-medium ${tone}`}><Icon size={14} weight="bold" aria-hidden="true" />{PRIORITY[priority]}</span>;
}

export function FlagMarks({ task }) {
  return (<>
    {task.important && <Star size={14} weight="fill" className="shrink-0 text-warning" aria-label="Quan trọng" />}
    {task.urgent && <Lightning size={14} weight="fill" className="shrink-0 text-danger" aria-label="Khẩn cấp" />}
  </>);
}

export function DueText({ task, className = "" }) {
  const d = due(task);
  if (!d) return null;
  const late = d.tone === "late", soon = d.tone === "soon";
  const Icon = late ? WarningCircle : soon ? ClockCountdown : d.n === 0 ? Clock : CalendarBlank;
  const tone = late ? "text-danger font-semibold" : soon ? "text-warning font-semibold" : "text-muted";
  return <span className={`inline-flex items-center gap-1 whitespace-nowrap ${tone} ${className}`}><Icon size={14} weight={late || soon ? "fill" : "regular"} aria-hidden="true" />{d.text}</span>;
}

// Người: avatar tròn, nền surface-secondary, viền; chữ viết tắt
export function Person({ user, size = "sm", showName = true }) {
  if (!user) return <span className="inline-flex items-center gap-2 text-faint"><span className="grid size-6 place-items-center rounded-full border border-dashed border-faint" />Chưa giao</span>;
  return (
    <span className="inline-flex min-w-0 items-center gap-2">
      <Avatar size={size} className="shrink-0 border border-border bg-surface-secondary">
        {user.avatar_url ? <Avatar.Image alt="" src={user.avatar_url} referrerPolicy="no-referrer" /> : null}
        <Avatar.Fallback className="bg-surface-secondary text-foreground">{initials(user.name)}</Avatar.Fallback>
      </Avatar>
      {showName && <span className="truncate">{user.name}</span>}
    </span>
  );
}

// AI (agent): avatar VUÔNG bo, nền ai-bg, viền ai, biểu tượng sparkle, kèm nhãn "AI". AI không tính KPI.
export function AgentChip({ name, size = 24, showName = true }) {
  return (
    <span className="inline-flex min-w-0 items-center gap-2">
      <span className="grid shrink-0 place-items-center rounded-md border border-ai bg-ai-bg text-ai" style={{ width: size, height: size }} aria-hidden="true"><Sparkle size={Math.round(size * 0.55)} weight="fill" /></span>
      {showName && <span className="truncate">{name}</span>}
      <span className="rounded border border-ai px-1 text-[10px] font-semibold leading-4 text-ai">AI</span>
    </span>
  );
}

export function PageHeader({ title, sub, actions }) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1 className="text-[26px] font-medium leading-tight tracking-tight text-balance sm:text-[36px]">{title}</h1>
        {sub && <p className="mt-1 text-muted">{sub}</p>}
      </div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </div>
  );
}

export function Section({ title, count, action, children }) {
  return (
    <section className="flex flex-col gap-3">
      {(title || action) && (
        <div className="flex items-baseline justify-between gap-3">
          <h2 className="text-lg font-semibold tracking-tight">{title}{count != null && <span className="ml-2 font-semibold text-muted">{count}</span>}</h2>
          {action}
        </div>
      )}
      {children}
    </section>
  );
}

export function Empty({ children }) {
  return <p className="rounded-xl bg-surface px-4 py-5 text-muted">{children}</p>;
}

export function ErrorBox({ error, onRetry }) {
  if (!error) return null;
  return (
    <Alert status="danger">
      <Alert.Indicator />
      <Alert.Content>
        <Alert.Title>{error.message || String(error)}</Alert.Title>
        {onRetry && <Button className="mt-2" size="sm" variant="secondary" onPress={onRetry}>Thử lại</Button>}
      </Alert.Content>
    </Alert>
  );
}

export function LoadingList({ rows = 3 }) {
  return (
    <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl" aria-busy="true" aria-label="Đang tải">
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="flex flex-col gap-2 bg-surface px-4 py-4"><Skeleton className="h-4 w-3/5 rounded" /><Skeleton className="h-3 w-2/5 rounded" /></div>
      ))}
    </div>
  );
}

export function Seal({ date, press = false, className = "" }) {
  return <span className={`seal ${press ? "seal-press" : ""} ${className}`} aria-hidden="true">ĐÃ DUYỆT<small>{date ? ddmmyyyy(new Date(date)) : ""}</small></span>;
}

// ===== Ô nhập =====
export function TextInput({ label, value, onChange, type = "text", placeholder, description, isRequired, autoFocus, name, className = "w-full" }) {
  return (
    <TextField className={className} isRequired={isRequired} name={name}>
      <Label>{label}</Label>
      <Input type={type} value={value ?? ""} placeholder={placeholder} autoFocus={autoFocus} onChange={(e) => onChange(e.target.value)} />
      {description && <Description>{description}</Description>}
    </TextField>
  );
}

export function TextAreaInput({ label, value, onChange, placeholder, rows = 3, description, className = "w-full", hideLabel }) {
  return (
    <TextField className={className}>
      <Label className={hideLabel ? "sr-only" : ""}>{label}</Label>
      <TextArea rows={rows} value={value ?? ""} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} />
      {description && <Description>{description}</Description>}
    </TextField>
  );
}

const NONE = "__none";
export function SelectField({ label, value, onChange, options, placeholder = "Chọn", allowEmpty, emptyLabel = "Không chọn", className = "w-full", isRequired, isDisabled }) {
  const items = allowEmpty ? [{ value: NONE, label: emptyLabel }, ...options] : options;
  return (
    <Select className={className} placeholder={placeholder} isRequired={isRequired} isDisabled={isDisabled}
      value={value == null || value === "" ? (allowEmpty ? NONE : null) : value}
      onChange={(v) => onChange(v === NONE ? null : v)}>
      <Label>{label}</Label>
      <Select.Trigger><Select.Value /><Select.Indicator /></Select.Trigger>
      <Select.Popover>
        <ListBox>
          {items.map((o) => (
            <ListBox.Item key={o.value} id={o.value} textValue={o.label}>{o.label}<ListBox.ItemIndicator /></ListBox.Item>
          ))}
        </ListBox>
      </Select.Popover>
    </Select>
  );
}

export function CopyButton({ text, label = "Sao chép", done = "Đã sao chép", size = "sm", variant = "secondary" }) {
  const [ok, setOk] = useState(false);
  return (
    <Button size={size} variant={variant} onPress={async () => {
      try { await navigator.clipboard.writeText(text); setOk(true); setTimeout(() => setOk(false), 1600); } catch { /* trình duyệt chặn */ }
    }}>{ok ? done : label}</Button>
  );
}
