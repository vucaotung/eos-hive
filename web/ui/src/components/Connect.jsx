import { useEffect, useState } from "react";
import { Button, Card, Checkbox, toast } from "@heroui/react";
import { PlugConnection as Plug } from "@gravity-ui/icons";
import { rpc, getConfig } from "../lib/api.js";
import { useLoad } from "../lib/store.jsx";
import { ago, ddmmyyyy } from "../lib/format.js";
import { CopyButton, Empty, ErrorBox, SelectField, TextInput } from "./ui.jsx";

const SCOPES = [["read", "Đọc việc, lịch, công văn của tôi"], ["write", "Ghi bình luận, tiến độ, nộp kết quả"], ["drive", "Lưu kết quả vào Drive của tôi"],
  ["kb", "Hỏi kho dữ liệu chung"], ["hr_self", "Xem công, phép, KPI của tôi"]];
const CLIENTS = [["claude", "Claude"], ["chatgpt", "ChatGPT"], ["gemini", "Gemini"], ["cursor", "Cursor"], ["other", "Khác"]];

// Kết nối AI agent cá nhân (Claude, ChatGPT, Cursor...) qua mã MCP: tạo, xem, thu hồi
export default function Connect() {
  const [tick, setTick] = useState(0);
  const [mcpUrl, setMcpUrl] = useState(`${location.origin}/mcp`);
  const { data, error } = useLoad(() => rpc("web_my_tokens"), [tick]);
  const [f, setF] = useState({ name: "", client: "claude", days: "30", scopes: ["read"] });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState(null);
  const [fresh, setFresh] = useState(null);
  useEffect(() => { getConfig().then((c) => c.mcp_url && setMcpUrl(c.mcp_url)).catch(() => {}); }, []);

  async function create() {
    setBusy(true); setErr(null);
    try {
      const r = await rpc("web_token_issue", { name: f.name, client: f.client, scopes: f.scopes, days: Number(f.days) });
      setFresh({ token: r.token, name: f.name }); setF({ ...f, name: "" }); setTick((x) => x + 1);
    } catch (e) { setErr(e); } finally { setBusy(false); }
  }
  async function revoke(k) {
    if (!confirm(`Thu hồi mã "${k.name}"?`)) return;
    try { await rpc("web_token_revoke", { id: k.id }); toast.success("Đã thu hồi mã"); setTick((x) => x + 1); } catch (e) { toast.danger(e.message); }
  }
  const toggle = (k) => setF((s) => ({ ...s, scopes: s.scopes.includes(k) ? s.scopes.filter((x) => x !== k) : [...s.scopes, k] }));

  return (
    <Card className="gap-5 p-5">
      <div className="flex items-start gap-3">
        <Plug className="mt-1 size-6 shrink-0 text-accent" />
        <div className="min-w-0">
          <h2 className="text-lg font-semibold">Kết nối AI agent của bạn</h2>
          <p className="text-muted">Mã MCP cho phép agent cá nhân (Claude, ChatGPT, Cursor…) làm việc thay bạn trong phạm vi bạn chọn. Máy chủ: <code className="rounded bg-surface-secondary px-1.5 py-0.5">{mcpUrl}</code>. Mã chỉ hiện <b>một lần</b> khi tạo.</p>
        </div>
      </div>

      {fresh && (
        <div className="flex flex-col gap-3 rounded-xl bg-accent-soft p-4">
          <p className="font-semibold">Mã "{fresh.name}": sao chép ngay, mất thì phải thu hồi và tạo lại. Đừng gửi qua chat hay lưu vào kho mã nguồn.</p>
          <code className="break-all rounded-lg bg-surface px-3 py-2 font-mono text-sm">{fresh.token}</code>
          <div className="flex flex-wrap gap-2"><CopyButton text={fresh.token} label="Sao chép mã" /><Button size="sm" variant="secondary" onPress={() => setFresh(null)}>Đã lưu, ẩn đi</Button></div>
          <p className="text-sm text-muted">Dán vào cấu hình MCP của ứng dụng: máy chủ <code>{mcpUrl}</code>, tiêu đề <code>Authorization: Bearer &lt;mã&gt;</code>.</p>
        </div>
      )}

      <form className="grid gap-4 sm:grid-cols-3" onSubmit={(e) => { e.preventDefault(); create(); }}>
        <div className="sm:col-span-3"><b>Tạo mã mới</b></div>
        <TextInput label="Tên gợi nhớ" value={f.name} onChange={(v) => setF({ ...f, name: v })} placeholder="Claude trên laptop" isRequired />
        <SelectField label="Ứng dụng" value={f.client} onChange={(v) => setF({ ...f, client: v })} options={CLIENTS.map(([value, label]) => ({ value, label }))} />
        <SelectField label="Hạn" value={f.days} onChange={(v) => setF({ ...f, days: v })} options={[["7", "7 ngày"], ["30", "30 ngày"], ["90", "90 ngày"]].map(([value, label]) => ({ value, label }))} />
        <fieldset className="flex flex-col gap-2 sm:col-span-3">
          <legend className="mb-1 text-sm font-semibold text-muted">Quyền (chọn tối thiểu cần thiết)</legend>
          {SCOPES.map(([k, label]) => (
            <Checkbox key={k} isSelected={f.scopes.includes(k)} onChange={() => toggle(k)}>
              <Checkbox.Control><Checkbox.Indicator /></Checkbox.Control><Checkbox.Content><code className="mr-2">{k}</code>{label}</Checkbox.Content>
            </Checkbox>
          ))}
        </fieldset>
        <div className="sm:col-span-3"><Button type="submit" isPending={busy} isDisabled={f.name.trim().length < 2 || !f.scopes.length}>Tạo mã</Button></div>
      </form>
      {err && <ErrorBox error={err} />}
      <ErrorBox error={error} />

      <div className="flex flex-col gap-2">
        <b>Mã của bạn</b>
        {data?.length ? (
          <div className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
            {data.map((k) => (
              <div key={k.id} className={`flex flex-wrap items-center gap-x-4 gap-y-1 bg-surface-secondary px-4 py-3 ${k.active ? "" : "opacity-60"}`}>
                <span className="min-w-0 flex-1"><b>{k.name}</b><span className="ml-2 text-sm text-muted">{k.client}</span></span>
                <code className="text-sm">eos_{k.prefix}…</code>
                <span className="text-sm text-muted">{(k.scopes || []).join(", ")}</span>
                <span className="text-sm text-muted">{k.revoked_at ? "Đã thu hồi" : `Hết hạn ${ddmmyyyy(new Date(k.expires_at))}`}</span>
                <span className="text-sm text-muted">{k.last_used_at ? `dùng ${ago(k.last_used_at)}` : "chưa dùng"}</span>
                {k.active && <Button size="sm" variant="ghost" onPress={() => revoke(k)}>Thu hồi</Button>}
              </div>
            ))}
          </div>
        ) : data && <Empty>Bạn chưa có mã nào.</Empty>}
      </div>
    </Card>
  );
}
