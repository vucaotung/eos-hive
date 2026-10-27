import { useMemo, useState } from "react";
import { Button, Switch, toast } from "@heroui/react";
import { Plus, Repeat, PencilSimple, Trash } from "@phosphor-icons/react";
import { useApp, useLoad } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { PRIORITY, ddmmyyyy, parseDate } from "../lib/format.js";
import { Dialog, useEditor } from "../components/Dialog.jsx";
import { Empty, ErrorBox, LoadingList, PageHeader, Person, SelectField, TextAreaInput, TextInput, PriorityMark } from "../components/ui.jsx";

// Việc định kỳ (design/README.md §3): nhóm Hằng ngày / Hằng tuần / Hằng tháng; cột hạn hiện quy tắc. Việc được sinh bởi job ngày (03:30) hoặc ngay khi lưu nếu đã đến hạn.
const WD = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"];
export const ruleText = (r) => {
  const every = r.interval_n > 1 ? ` ${r.interval_n}` : "";
  if (r.freq === "daily") return r.interval_n > 1 ? `Cứ ${r.interval_n} ngày` : "Hằng ngày";
  if (r.freq === "weekly") return `${r.interval_n > 1 ? `Cứ ${r.interval_n} tuần` : "Hằng tuần"} · ${(r.weekdays || []).map((d) => WD[d - 1]).join(", ")}`;
  return `${r.interval_n > 1 ? `Cứ${every} tháng` : "Hằng tháng"} · ${r.month_day === 31 ? "ngày cuối tháng" : `ngày ${r.month_day}`}`;
};
const GROUPS = [["daily", "Hằng ngày"], ["weekly", "Hằng tuần"], ["monthly", "Hằng tháng"]];
const blank = () => ({ id: null, title: "", description: "", freq: "weekly", interval_n: "1", weekdays: [5], month_day: "1", due_offset: "0", start: new Date().toISOString().slice(0, 10), until_date: "",
  assignee_id: null, project_id: null, department_id: null, priority: "medium", skip_holidays: true, active: true });

export default function Recurring() {
  const { companyId, org, lookups, membership, userId } = useApp();
  const [tick, setTick] = useState(0);
  const { data, error, loading } = useLoad(() => companyId ? rpc("app_recurrences", { company_id: companyId }) : Promise.resolve([]), [companyId, tick]);
  const ed = useEditor(blank());
  const people = useMemo(() => org.members.filter((m) => m.active && m.user).map((m) => ({ value: m.user.id, label: m.user.name })), [org.members]);
  const reload = () => setTick((x) => x + 1);
  const toggle = async (r, on) => { try { await rpc("app_recurrence_set", { id: r.id, active: on }); toast.success(on ? "Đã bật lại" : "Đã tạm dừng"); reload(); } catch (e) { toast.danger(e.message); } };
  const del = async (r) => { if (!confirm(`Xóa việc định kỳ "${r.title}"? Các việc đã sinh vẫn giữ nguyên.`)) return; try { await rpc("app_recurrence_set", { id: r.id, delete: true }); toast.success("Đã xóa"); reload(); } catch (e) { toast.danger(e.message); } };
  const edit = (r) => ed.start({ ...blank(), ...r, interval_n: String(r.interval_n), month_day: String(r.month_day || 1), due_offset: String(r.due_offset), weekdays: r.weekdays || [5], start: r.next_run, until_date: r.until_date || "", description: r.description || "" });
  const f = ed.f;
  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Việc định kỳ" sub="Việc lặp lại theo lịch. Hệ thống tự tạo việc mới khi đến kỳ (bỏ cuối tuần và ngày lễ nếu bật)."
        actions={<Button onPress={() => ed.start(blank())}><Plus size={16} weight="bold" />Thêm việc định kỳ</Button>} />
      <ErrorBox error={error} />
      {loading && !data ? <LoadingList rows={3} /> : !(data || []).length ? <Empty>Chưa có việc định kỳ. Thêm việc báo cáo tuần, đối chiếu cuối tháng… để hệ thống tự giao đúng kỳ.</Empty> : GROUPS.map(([k, label]) => {
        const rows = (data || []).filter((r) => r.freq === k); if (!rows.length) return null;
        return (
          <section key={k} className="flex flex-col gap-2"><h2 className="flex items-center gap-2 px-1 text-[13px] font-medium text-muted"><Repeat size={15} />{label}<span className="text-faint">{rows.length}</span></h2>
            <div className="overflow-hidden rounded-[14px] bg-surface" style={{ boxShadow: "0 0 0 1px var(--separator)" }}>
              {rows.map((r) => (
                <div key={r.id} className={`flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-separator px-4 py-3 first:border-t-0 ${r.active ? "" : "opacity-55"}`}>
                  <span className="flex min-w-0 flex-1 flex-col"><b className="font-medium [overflow-wrap:anywhere]">{r.title}</b>
                    <span className="flex flex-wrap items-center gap-x-3 text-[13px] text-muted"><span className="inline-flex items-center gap-1"><Repeat size={13} />{ruleText(r)}</span>
                      {lookups.project[r.project_id] && <span>{lookups.project[r.project_id].name}</span>}<Person user={lookups.person[r.assignee_id]} /><PriorityMark priority={r.priority === "medium" || r.priority === "low" ? null : r.priority} />
                      {r.active ? <span>Lần tới {ddmmyyyy(parseDate(r.next_run))}</span> : <span className="font-medium text-warning">Tạm dừng</span>}{r.until_date && <span>đến {ddmmyyyy(parseDate(r.until_date))}</span>}</span></span>
                  {r.can_edit && <span className="flex items-center gap-1">
                    <Switch isSelected={r.active} onChange={(v) => toggle(r, v)} aria-label={`Bật hoặc tạm dừng ${r.title}`}><Switch.Control><Switch.Thumb /></Switch.Control></Switch>
                    <Button isIconOnly size="sm" variant="ghost" aria-label={`Sửa ${r.title}`} onPress={() => edit(r)}><PencilSimple size={16} /></Button>
                    <Button isIconOnly size="sm" variant="ghost" aria-label={`Xóa ${r.title}`} className="text-danger" onPress={() => del(r)}><Trash size={16} /></Button></span>}
                </div>))}
            </div></section>);
      })}
      <Dialog title={f.id ? "Sửa việc định kỳ" : "Thêm việc định kỳ"} isOpen={ed.open} onClose={ed.close} busy={ed.busy} error={ed.error}
        onSave={() => ed.run(async () => {
          await rpc("app_recurrence_save", { company_id: companyId, id: f.id, title: f.title, description: f.description, freq: f.freq, interval_n: Number(f.interval_n) || 1,
            weekdays: f.freq === "weekly" ? f.weekdays : undefined, month_day: f.freq === "monthly" ? Number(f.month_day) : undefined, due_offset: Number(f.due_offset) || 0, start: f.start, until_date: f.until_date || "",
            assignee_id: f.assignee_id || "", project_id: f.project_id || "", priority: f.priority, skip_holidays: f.skip_holidays });
          reload();
        }, "Đã lưu việc định kỳ")}>
        <TextInput label="Tên việc" value={f.title} onChange={ed.set("title")} isRequired placeholder="Ví dụ: Báo cáo tuần cho Ban Giám đốc" />
        <TextAreaInput label="Mô tả" value={f.description} onChange={ed.set("description")} rows={2} />
        <div className="grid grid-cols-2 gap-3">
          <SelectField label="Tần suất" value={f.freq} onChange={ed.set("freq")} options={GROUPS.map(([value, label]) => ({ value, label }))} />
          <TextInput label="Cứ mỗi (chu kỳ)" type="number" value={f.interval_n} onChange={ed.set("interval_n")} description="1 đến 12" />
        </div>
        {f.freq === "weekly" && (
          <fieldset className="flex flex-col gap-1.5"><legend className="text-sm font-medium">Các thứ trong tuần</legend>
            <div className="flex flex-wrap gap-1.5">{WD.map((d, i) => { const on = f.weekdays.includes(i + 1); return (
              <button key={d} type="button" aria-pressed={on} onClick={() => ed.set("weekdays")(on ? f.weekdays.filter((x) => x !== i + 1) : [...f.weekdays, i + 1].sort())} className={`h-9 min-w-11 rounded-full px-3 text-[13px] font-medium ${on ? "bg-accent-soft text-act" : "text-muted"}`} style={{ boxShadow: `inset 0 0 0 1px ${on ? "var(--accent)" : "var(--border)"}` }}>{d}</button>); })}</div></fieldset>)}
        {f.freq === "monthly" && <TextInput label="Ngày trong tháng" type="number" value={f.month_day} onChange={ed.set("month_day")} description="1 đến 31 (31 = ngày cuối tháng; tháng ngắn tự lùi về ngày cuối)" />}
        <div className="grid grid-cols-2 gap-3">
          <TextInput label="Bắt đầu từ" type="date" value={f.start} onChange={ed.set("start")} />
          <TextInput label="Kết thúc (tùy chọn)" type="date" value={f.until_date} onChange={ed.set("until_date")} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <SelectField label="Người phụ trách" value={f.assignee_id} onChange={ed.set("assignee_id")} allowEmpty emptyLabel="Chưa giao" options={people} />
          <TextInput label="Hạn sau ngày tạo (ngày)" type="number" value={f.due_offset} onChange={ed.set("due_offset")} description="0 = hạn ngay ngày tạo" />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <SelectField label="Dự án" value={f.project_id} onChange={ed.set("project_id")} allowEmpty emptyLabel="Không thuộc dự án" options={org.projects.filter((p) => p.active).map((p) => ({ value: p.id, label: p.name }))} />
          <SelectField label="Ưu tiên" value={f.priority} onChange={ed.set("priority")} options={Object.entries(PRIORITY).map(([value, label]) => ({ value, label }))} />
        </div>
        <Switch isSelected={f.skip_holidays} onChange={ed.set("skip_holidays")}><Switch.Content><Switch.Control><Switch.Thumb /></Switch.Control>Bỏ qua cuối tuần và ngày lễ</Switch.Content></Switch>
      </Dialog>
    </div>
  );
}
