import { useState } from "react";
import { Button, Card, toast } from "@heroui/react";
import { Plus, PencilSimple, Trash } from "@phosphor-icons/react";
import { useApp, useLoad } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { Dialog, useEditor } from "./Dialog.jsx";
import { TextAreaInput, TextInput, ErrorBox } from "./ui.jsx";

// Mẫu checklist của công ty (Cài đặt › Mẫu checklist): mỗi dòng của ô nhập là một mục
export default function ChecklistTemplates() {
  const { companyId } = useApp();
  const [tick, setTick] = useState(0), ed = useEditor({ id: null, name: "", text: "" });
  const { data, error } = useLoad(() => companyId ? rpc("app_checklist_templates", { company_id: companyId }) : Promise.resolve([]), [companyId, tick]);
  const reload = () => setTick((x) => x + 1);
  const del = async (t) => { if (!confirm(`Xóa mẫu "${t.name}"?`)) return; try { await rpc("app_checklist_template_delete", { id: t.id }); toast.success("Đã xóa mẫu"); reload(); } catch (e) { toast.danger(e.message); } };
  return (
    <Card className="gap-3 p-5">
      <div className="flex items-center justify-between gap-3"><h2 className="text-lg font-medium">Mẫu checklist</h2><Button size="sm" onPress={() => ed.start({ id: null, name: "", text: "" })}><Plus size={14} weight="bold" />Mẫu mới</Button></div>
      <ErrorBox error={error} />
      <ul className="flex flex-col overflow-hidden rounded-lg">
        {(data || []).map((t) => (
          <li key={t.id} className="flex items-center gap-3 border-t border-separator bg-surface-secondary px-3 py-2 first:border-t-0"><span className="min-w-0 flex-1"><b className="font-medium">{t.name}</b><span className="ml-2 text-xs text-muted">{t.items.length} mục · dùng {t.uses} lần</span></span>
            <Button isIconOnly size="sm" variant="ghost" aria-label={`Sửa ${t.name}`} onPress={() => ed.start({ id: t.id, name: t.name, text: t.items.join("\n") })}><PencilSimple size={16} /></Button>
            <Button isIconOnly size="sm" variant="ghost" className="text-danger" aria-label={`Xóa ${t.name}`} onPress={() => del(t)}><Trash size={16} /></Button></li>))}
        {data && !data.length && <li className="bg-surface-secondary px-3 py-3 text-sm text-muted">Chưa có mẫu nào. Ví dụ "Hồ sơ đất đai": Giấy chứng nhận, Bản đồ địa chính, Biên bản bàn giao.</li>}
      </ul>
      <Dialog title={ed.f.id ? "Sửa mẫu checklist" : "Mẫu checklist mới"} isOpen={ed.open} onClose={ed.close} busy={ed.busy} error={ed.error}
        onSave={() => ed.run(async () => { await rpc("app_checklist_template_save", { company_id: companyId, id: ed.f.id, name: ed.f.name, items: ed.f.text.split("\n").map((x) => x.trim()).filter(Boolean) }); reload(); }, "Đã lưu mẫu")}>
        <TextInput label="Tên mẫu" value={ed.f.name} onChange={ed.set("name")} isRequired placeholder="Ví dụ: Hồ sơ đất đai" />
        <TextAreaInput label="Các mục (mỗi dòng một mục)" value={ed.f.text} onChange={ed.set("text")} rows={6} description="Tối đa 50 mục, mỗi mục tối đa 300 ký tự." />
      </Dialog>
    </Card>
  );
}
