import { useEffect, useState } from "react";
import { Alert, Avatar, Button, Description, Input, Label, ListBox, Select, Skeleton, TextArea, TextField } from "@heroui/react";
import { STATUS, STATUS_COLOR, due, initials, ddmmyyyy } from "../lib/format.js";

export function useMedia(q) {
  const [m, setM] = useState(() => matchMedia(q).matches);
  useEffect(() => { const mq = matchMedia(q); const f = () => setM(mq.matches); mq.addEventListener("change", f); return () => mq.removeEventListener("change", f); }, [q]);
  return m;
}

export function StatusBadge({ status, waiting }) {
  if (waiting && status !== "done") return <span className="st-blocked inline-flex items-center gap-1.5 text-sm font-semibold text-warning"><i className="st-dot" />Chờ người trả lời</span>;
  return <span className={`st-${status} inline-flex items-center gap-1.5 text-sm font-semibold ${STATUS_COLOR[status]}`}><i className="st-dot" />{STATUS[status]}</span>;
}

export function DueText({ task, className = "" }) {
  const d = due(task);
  if (!d) return null;
  const tone = d.tone === "late" ? "text-danger font-semibold" : d.tone === "soon" ? "text-warning font-semibold" : "text-muted";
  return <span className={`${tone} ${className}`}>{d.text}</span>;
}

export function Person({ user, size = "sm", showName = true }) {
  if (!user) return <span className="text-muted">Chưa giao</span>;
  return (
    <span className="inline-flex min-w-0 items-center gap-2">
      <Avatar size={size} className="shrink-0">
        {user.avatar_url ? <Avatar.Image alt="" src={user.avatar_url} referrerPolicy="no-referrer" /> : null}
        <Avatar.Fallback>{initials(user.name)}</Avatar.Fallback>
      </Avatar>
      {showName && <span className="truncate">{user.name}</span>}
    </span>
  );
}

export function PageHeader({ title, sub, actions }) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div className="min-w-0">
        <h1 className="text-3xl font-extrabold tracking-tight text-balance sm:text-4xl">{title}</h1>
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
          <h2 className="text-lg font-extrabold tracking-tight">{title}{count != null && <span className="ml-2 font-semibold text-muted">{count}</span>}</h2>
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
