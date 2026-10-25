import { useEffect, useState } from "react";
import { Button, Drawer, Switch, toast } from "@heroui/react";
import { rpc } from "../lib/api.js";
import { useApp } from "../lib/store.jsx";
import { ago, ddmmyyyy } from "../lib/format.js";
import { ErrorBox, SelectField, TextInput, useMedia } from "./ui.jsx";

export const AGENT_STATUS = {
  on: ["Đang chạy", "text-success"], off: ["Tắt", "text-muted"], no_token: ["Chưa có mã", "text-warning"], expiring: ["Mã sắp hết hạn", "text-danger"],
};
const SCOPE_DOES = {
  read: "Đọc việc được giao", kb: "Hỏi Kho dữ liệu chung", project: "Đọc hồ sơ dự án và ghi danh mục hồ sơ", draft: "Soạn dự thảo văn bản (.docx), chưa cấp số, chưa ký",
  ingest: "Nạp tài liệu đã xử lý vào kho tri thức", delegate: "Chia việc con cho agent chuyên môn khác", runner: "Xử lý hồ sơ trên máy Z2 (đọc Drive, Markdown, OCR)",
  task_create: "Tạo việc mới cho người (không sửa việc, không đổi trạng thái, không giao cho agent)",
};
const LEVEL = ["Chỉ đọc", "Tự làm việc cấp thấp (L1) và ghi lại", "Làm việc cấp thấp và xin xác nhận trước việc cấp 2 (L2)"];
// L3 không bao giờ mở cho agent, dù cấu hình thế nào
const NEVER = ["Duyệt kết quả hoặc duyệt đề nghị", "Cấp số văn bản, ký, ban hành, gửi ra ngoài", "Chốt lương, đổi vai trò của người, xóa dữ liệu"];

const Facts = ({ rows }) => (
  <dl className="grid grid-cols-[auto_1fr] gap-x-4 rounded-xl bg-surface px-4 py-1">
    {rows.filter(Boolean).map(([k, v], i) => (
      <div key={k} className="contents">
        <dt className={`py-2.5 text-muted ${i ? "border-t-2 border-background" : ""}`}>{k}</dt>
        <dd className={`min-w-0 py-2.5 font-medium [overflow-wrap:anywhere] ${i ? "border-t-2 border-background" : ""}`}>{v}</dd>
      </div>
    ))}
  </dl>
);

export default function AgentDrawer({ agent, tech, onClose, onSaved, goAgents }) {
  const { companyId, org, isAdmin, isSystemAdmin } = useApp();
  const desktop = useMedia("(min-width: 1024px)");
  const [f, setF] = useState({ title: "", owner: null, department_id: null });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  useEffect(() => { if (agent) { setF({ title: agent.title || "", owner: agent.owner?.id || null, department_id: agent.department_id || null }); setError(null); } }, [agent]);
  const [label, tone] = AGENT_STATUS[agent?.status] || ["", ""];
  const call = async (body, ok) => {
    setBusy(true); setError(null);
    try { await rpc("app_agent_set", { company_id: companyId, code: agent.code, ...body }); toast.success(ok); await onSaved(); }
    catch (e) { setError(e); } finally { setBusy(false); }
  };
  const people = org.members.filter((m) => m.active && m.user).map((m) => ({ value: m.user.id, label: m.user.name }));
  const dept = org.departments.find((d) => d.id === agent?.department_id);
  return (
    <Drawer.Backdrop isOpen={!!agent} onOpenChange={(o) => !o && onClose()} variant={desktop ? "transparent" : undefined}>
      <Drawer.Content placement={desktop ? "right" : "bottom"}>
        <Drawer.Dialog className={`bg-background ${desktop ? "w-[min(520px,100vw)] max-w-none" : "max-h-[92dvh]"}`}>
          {!desktop && <Drawer.Handle />}
          <Drawer.CloseTrigger />
          <Drawer.Header>
            {agent && (
              <div className="flex flex-col gap-2 pr-8">
                <div className="flex items-center gap-3 text-sm"><span className="rounded-md bg-accent-soft px-2 py-0.5 text-xs font-extrabold text-accent">AI</span><span className={`font-semibold ${tone}`}>{label}</span></div>
                <Drawer.Heading className="text-xl font-extrabold leading-snug tracking-tight">{agent.name}</Drawer.Heading>
                {agent.title && <p className="text-muted">{agent.title}</p>}
              </div>
            )}
          </Drawer.Header>
          <Drawer.Body className="flex flex-col gap-5 pb-8">
            {agent && (<>
              <p className="whitespace-pre-wrap [overflow-wrap:anywhere]">{agent.description || "Chưa có mô tả vai trò."}</p>
              <Facts rows={[
                ["Người phụ trách", agent.owner?.name || "Chưa có"],
                ["Phòng ban", dept ? `${dept.code} · ${dept.name}` : "Chung công ty"],
                tech && ["Nhận việc từ Kanban", agent.accepts_cards ? "Có" : "Không (dùng mã MCP riêng)"],
                tech && ["Mã MCP", agent.token_count ? `${agent.token_count} mã còn hiệu lực, gần nhất hết hạn ${ddmmyyyy(new Date(agent.token_expires))}` : "Chưa có mã"],
                tech && ["Hoạt động gần nhất", agent.last_active ? ago(agent.last_active) : "Chưa có"],
                tech && ["Việc", `${agent.running} đang làm, ${agent.waiting_human} đang chờ người`],
              ]} />
              {tech && (
                <section className="flex flex-col gap-2">
                  <h3 className="font-extrabold">Được làm</h3>
                  <ul className="list-disc pl-5 text-sm">
                    <li>{LEVEL[agent.max_level] || LEVEL[0]}</li>
                    {(agent.token_scopes || []).filter((s) => SCOPE_DOES[s]).map((s) => <li key={s}>{SCOPE_DOES[s]}</li>)}
                    {!(agent.token_scopes || []).length && <li className="text-muted">Chưa có mã MCP nên chưa làm gì trong hệ thống.</li>}
                  </ul>
                </section>
              )}
              <section className="flex flex-col gap-2">
                <h3 className="font-extrabold">Không bao giờ được làm</h3>
                <ul className="list-disc pl-5 text-sm">{NEVER.map((n) => <li key={n}>{n}</li>)}</ul>
                <p className="text-xs text-muted">Các việc này luôn do người làm (mức L3), giao diện không có cách mở cho agent.</p>
              </section>
              {isAdmin && (
                <section className="flex flex-col gap-3 rounded-xl bg-surface p-4">
                  <h3 className="font-extrabold">Thiết lập cho công ty</h3>
                  <Switch isSelected={!!agent.accepts_cards} isDisabled={busy || agent.active === false} onChange={(v) => call({ enabled: v }, v ? "Đã cho nhận việc" : "Đã tắt nhận việc")}>
                    <Switch.Content><Switch.Control><Switch.Thumb /></Switch.Control>Cho phép nhận việc từ Kanban (giao việc cho agent này)</Switch.Content>
                  </Switch>
                  {agent.active === false && <p className="text-sm text-warning">Quản trị hệ thống đang tắt agent này nên chưa bật được.</p>}
                  <TextInput label="Chức danh" value={f.title} onChange={(v) => setF({ ...f, title: v })} placeholder="Ví dụ: Trợ lý tiếp nhận" />
                  <SelectField label="Người phụ trách" value={f.owner} onChange={(v) => setF({ ...f, owner: v })} allowEmpty emptyLabel="Chưa có" options={people} />
                  <SelectField label="Phòng ban" value={f.department_id} onChange={(v) => setF({ ...f, department_id: v })} allowEmpty emptyLabel="Chung công ty"
                    options={org.departments.map((d) => ({ value: d.id, label: `${d.code} · ${d.name}` }))} />
                  <ErrorBox error={error} />
                  <div><Button isDisabled={busy} onPress={() => call({ title: f.title, owner_user_id: f.owner, department_id: f.department_id }, "Đã lưu hồ sơ agent")}>Lưu</Button></div>
                </section>
              )}
              {isSystemAdmin && <div><Button variant="secondary" onPress={goAgents}>Mở "Agent và MCP" (mã, nhật ký, cầu nối)</Button></div>}
            </>)}
          </Drawer.Body>
        </Drawer.Dialog>
      </Drawer.Content>
    </Drawer.Backdrop>
  );
}
