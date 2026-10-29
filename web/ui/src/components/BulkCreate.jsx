import { useMemo, useRef, useState } from "react";
import { Button, Modal, toast } from "@heroui/react";
import { useApp } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { PRIORITY } from "../lib/format.js";
import { parseBulk, remindAt } from "../lib/quickadd.js";
import { useMedia, TextAreaInput, ErrorBox, SelectField } from "./ui.jsx";
import { WarningCircle, UploadSimple } from "@phosphor-icons/react";

const HINT = `Mỗi dòng một việc, dùng cú pháp gõ nhanh:
Soạn hợp đồng thuê kho @lan thứ 6 !cao #hợp-đồng
Gọi khách báo giá mai 9h ~30p
Nộp thuế quý 20/10 !qt !kc

Hoặc dán CSV có dòng tiêu đề:
Tiêu đề,Người phụ trách,Hạn,Ưu tiên,Dự án,Nhãn`;

// Tạo hàng loạt: dán danh sách hoặc nhập CSV → xem trước → tạo tối đa 100 việc (dòng lỗi được báo, không chặn các dòng khác)
export default function BulkCreate({ isOpen, onClose }) {
  const { companyId, org, lookups, refresh } = useApp();
  const [text, setText] = useState(""), [busy, setBusy] = useState(false), [error, setError] = useState(null), [res, setRes] = useState(null);
  const [asg, setAsg] = useState(null), [proj, setProj] = useState(null);
  const file = useRef(null), sheet = useMedia("(max-width: 639px)");
  const ctx = useMemo(() => ({ members: org.members.filter((m) => m.user).map((m) => ({ id: m.user.id, name: m.user.name, email: m.user.email })), projects: org.projects.filter((p) => p.active).map((p) => ({ id: p.id, name: p.name })) }), [org.members, org.projects]);
  const rows = useMemo(() => parseBulk(text, ctx), [text, ctx]);
  const valid = rows.filter((r) => (r.title || "").trim().length >= 2);

  const close = () => { setText(""); setRes(null); setError(null); onClose(); };
  async function readFile(e) {
    const f = e.target.files?.[0]; e.target.value = "";
    if (!f) return;
    if (f.size > 500_000) { toast.danger("Tệp quá lớn (tối đa 500 KB)"); return; }
    setText(await f.text());
  }
  async function submit() {
    setBusy(true); setError(null);
    try {
      const items = valid.slice(0, 100).map((r) => ({ title: r.title, description: r.description || "", assignee_id: r.assignee_id || asg || "", due_date: r.due_date || "", priority: r.priority || "medium", project_id: r.project_id || proj || "",
        important: !!r.important, urgent: !!r.urgent, est_minutes: r.est_minutes || "", tags: r.tags || [], ...(r.time && r.due_date ? { remind_at: remindAt(r.due_date, r.time) } : {}) }));
      const out = await rpc("app_tasks_bulk", { company_id: companyId, items });
      setRes({ ...out, map: valid.slice(0, 100).map((r) => r.row) });
      if (out.created.length) { toast.success(`Đã tạo ${out.created.length} việc${out.errors.length ? `, ${out.errors.length} dòng lỗi` : ""}`); refresh(); }
    } catch (e) { setError(e); } finally { setBusy(false); }
  }

  return (
    <Modal.Backdrop isOpen={isOpen} onOpenChange={(o) => !o && close()}>
      <Modal.Container placement={sheet ? "bottom" : "auto"} scroll="inside">
        <Modal.Dialog className={sheet ? "rounded-t-[20px]" : "sm:max-w-[820px]"}>
          <Modal.CloseTrigger />
          <Modal.Header><Modal.Heading>Tạo việc hàng loạt</Modal.Heading></Modal.Header>
          <Modal.Body className="flex flex-col gap-4">
            {!res ? (<>
              <TextAreaInput label="Danh sách việc hoặc CSV" value={text} onChange={setText} rows={7} placeholder={HINT} />
              <div className="flex flex-wrap items-center gap-2">
                <input ref={file} type="file" accept=".csv,.txt,text/csv,text/plain" className="sr-only" onChange={readFile} aria-label="Chọn tệp CSV" />
                <Button size="sm" variant="secondary" onPress={() => file.current?.click()}><UploadSimple className="size-4" />Nhập từ tệp CSV</Button>
                <span className="text-sm text-muted">Tối đa 100 việc mỗi lần. Cột CSV: Tiêu đề, Người phụ trách (email hoặc tên), Hạn (20/5, mai…), Ưu tiên (thấp/thường/cao/gấp), Dự án, Nhãn, Mô tả.</span>
              </div>
              <div className="grid gap-3 sm:grid-cols-2">
                <SelectField label="Giao tất cả cho (nếu dòng không nêu)" value={asg} onChange={setAsg} allowEmpty emptyLabel="Chưa giao" options={org.members.filter((m) => m.user && m.active).map((m) => ({ value: m.user.id, label: m.user.name }))} />
                <SelectField label="Dự án chung (nếu dòng không nêu)" value={proj} onChange={setProj} allowEmpty emptyLabel="Không thuộc dự án" options={org.projects.filter((p) => p.active).map((p) => ({ value: p.id, label: p.name }))} />
              </div>
              {rows.length > 0 && (
                <div className="overflow-x-auto rounded-xl" style={{ boxShadow: "inset 0 0 0 1px var(--border)" }}>
                  <table className="w-full min-w-[560px] text-left text-[13.5px]">
                    <thead className="text-muted"><tr><th className="px-3 py-2 font-medium">#</th><th className="px-3 py-2 font-medium">Tên việc</th><th className="px-3 py-2 font-medium">Người</th><th className="px-3 py-2 font-medium">Hạn</th><th className="px-3 py-2 font-medium">Ưu tiên</th><th className="px-3 py-2 font-medium">Nhãn</th></tr></thead>
                    <tbody>{rows.slice(0, 100).map((r) => { const bad = (r.title || "").trim().length < 2; return (
                      <tr key={r.row} className="border-t border-separator align-top">
                        <td className="px-3 py-2 text-faint">{r.row}</td>
                        <td className="px-3 py-2"><span className={bad ? "text-danger" : ""}>{r.title || "(thiếu tên)"}</span>
                          {(r.warn?.length > 0 || bad) && <span className="mt-0.5 flex items-start gap-1 text-[12.5px] text-warning"><WarningCircle size={13} weight="fill" className="mt-0.5 shrink-0" aria-hidden="true" />{bad ? "Dòng này sẽ bị bỏ (tên quá ngắn). " : ""}{r.warn?.join("; ")}</span>}</td>
                        <td className="px-3 py-2">{lookups.person[r.assignee_id || asg]?.name || <span className="text-faint">—</span>}</td>
                        <td className="px-3 py-2 whitespace-nowrap">{r.due_date ? r.due_date.split("-").reverse().join("/") : <span className="text-faint">—</span>}{r.time && ` ${r.time}`}</td>
                        <td className="px-3 py-2">{PRIORITY[r.priority || "medium"]}</td>
                        <td className="px-3 py-2">{(r.tags || []).map((t) => `#${t}`).join(" ") || <span className="text-faint">—</span>}</td>
                      </tr>); })}</tbody>
                  </table>
                  {rows.length > 100 && <p className="border-t border-separator px-3 py-2 text-sm text-warning">Chỉ 100 dòng đầu được tạo; chia phần còn lại làm lượt sau.</p>}
                </div>)}
              <ErrorBox error={error} />
            </>) : (
              <div className="flex flex-col gap-3" role="status">
                <p className="text-[15px]"><b className="font-medium">Đã tạo {res.created.length} việc.</b>{res.errors.length > 0 && <span className="text-warning"> {res.errors.length} dòng lỗi, chưa tạo:</span>}</p>
                {res.errors.length > 0 && <ul className="flex flex-col gap-1 text-[13.5px]">{res.errors.map((e) => <li key={e.row} className="text-danger">Dòng {res.map[e.row - 1] ?? e.row}: {e.error}</li>)}</ul>}
                {res.errors.length > 0 && <p className="text-sm text-muted">Bấm "Sửa các dòng lỗi" để nạp lại riêng các dòng này (chỉ còn tên việc; thêm lại người, hạn… nếu cần) rồi tạo tiếp. Các dòng đã tạo không bị tạo lại.</p>}
              </div>)}
          </Modal.Body>
          <Modal.Footer>
            {!res ? (<>
              <span className="mr-auto text-sm text-muted">{valid.length ? `Sẽ tạo ${Math.min(valid.length, 100)} việc` : "Chưa có dòng hợp lệ"}</span>
              <Button variant="secondary" onPress={close}>Hủy</Button>
              <Button isPending={busy} isDisabled={!valid.length} onPress={submit}>Tạo {valid.length ? Math.min(valid.length, 100) : ""} việc</Button>
            </>) : (<>
              {res.errors.length > 0 && <Button variant="secondary" onPress={() => { setText(res.errors.map((e) => valid[e.row - 1]).filter(Boolean).map((r) => r.title).join("\n")); setRes(null); }}>Sửa các dòng lỗi</Button>}
              <Button onPress={close}>Xong</Button></>)}
          </Modal.Footer>
        </Modal.Dialog>
      </Modal.Container>
    </Modal.Backdrop>
  );
}
