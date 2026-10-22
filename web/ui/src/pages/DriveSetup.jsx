import { useEffect, useState } from "react";
import { Button, Card, toast } from "@heroui/react";
import { Folder } from "@gravity-ui/icons";
import { rpc, getConfig } from "../lib/api.js";
import { useApp } from "../lib/store.jsx";
import { DRIVE, ago } from "../lib/format.js";
import { CopyButton, ErrorBox, TextInput } from "../components/ui.jsx";

const TONE = { none: "text-muted", pending: "text-warning", ok: "text-success", error: "text-danger" };

// Thiết lập thư mục Drive cá nhân: tạo thư mục đúng tên, chia sẻ quyền Editor cho agent, dán link
export default function DriveSetup({ compact = false, onDone }) {
  const { me, loadMe } = useApp();
  const [names, setNames] = useState([]);
  const [agentEmail, setAgentEmail] = useState("");
  const [url, setUrl] = useState(me?.user?.drive_folder_url || "");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const status = me?.user?.drive_status || "none";

  useEffect(() => {
    rpc("app_drive_names").then((n) => setNames(n || [])).catch(() => {});
    getConfig().then((c) => setAgentEmail(c.agent_email || "")).catch(() => {});
  }, []);

  async function save() {
    setBusy(true); setError(null);
    try { await rpc("app_drive_set", { url: url.trim() }); await loadMe(); toast.success("Đã lưu thư mục Drive"); onDone?.(); }
    catch (e) { setError(e); } finally { setBusy(false); }
  }

  return (
    <Card className="gap-5 p-5">
      <div className="flex items-start gap-3">
        <Folder className="mt-1 size-6 shrink-0 text-accent" />
        <div className="min-w-0">
          <h2 className="text-lg font-extrabold">Thư mục làm việc trên Google Drive</h2>
          <p className={`text-sm font-semibold ${TONE[status]}`}>{DRIVE[status]}{me?.user?.drive_checked_at ? `, kiểm tra ${ago(me.user.drive_checked_at)}` : ""}</p>
          {me?.user?.drive_note && status !== "none" && <p className="text-sm text-muted">{me.user.drive_note}</p>}
        </div>
      </div>
      {!compact && <p className="text-muted">Tài liệu làm việc của bạn nằm trong Drive của bạn, không lưu lên máy chủ công ty. Agent đọc thư mục này để gắn tài liệu vào việc và chia sẻ cho người liên quan.</p>}
      <ol className="flex flex-col gap-4">
        <li className="flex flex-col gap-2">
          <span className="font-semibold">1. Tạo một thư mục trong Google Drive với đúng tên:</span>
          {names.length ? names.map((n) => (
            <span key={n} className="flex flex-wrap items-center gap-2">
              <code className="rounded-md bg-surface-secondary px-2.5 py-1.5 text-[15px] font-semibold [overflow-wrap:anywhere]">{n}</code>
              <CopyButton text={n} label="Sao chép tên" />
            </span>
          )) : <span className="h-8 w-64 animate-pulse rounded bg-surface-secondary" />}
          {names.length > 1 && <span className="text-sm text-muted">Bạn thuộc nhiều công ty: tạo một thư mục cho mỗi công ty, hoặc một thư mục chung đặt theo tên đầu tiên.</span>}
        </li>
        <li className="flex flex-col gap-2">
          <span className="font-semibold">2. Chia sẻ thư mục, quyền <b>Người chỉnh sửa</b>, cho tài khoản agent:</span>
          {agentEmail ? (
            <span className="flex flex-wrap items-center gap-2">
              <code className="rounded-md bg-surface-secondary px-2.5 py-1.5 text-[15px] font-semibold">{agentEmail}</code>
              <CopyButton text={agentEmail} label="Sao chép email" />
            </span>
          ) : <span className="text-sm text-muted">Quản trị chưa cấu hình email agent.</span>}
        </li>
        <li className="flex flex-col gap-2">
          <span className="font-semibold">3. Dán link thư mục vào đây:</span>
          <form className="flex flex-col gap-2 sm:flex-row sm:items-end" onSubmit={(e) => { e.preventDefault(); save(); }}>
            <TextInput label="Link thư mục" type="url" value={url} onChange={setUrl} placeholder="https://drive.google.com/drive/folders/..." className="w-full sm:flex-1" />
            <Button type="submit" isPending={busy} isDisabled={!url.trim()}>{status === "none" ? "Lưu thư mục" : "Cập nhật"}</Button>
          </form>
        </li>
      </ol>
      {error && <ErrorBox error={error} />}
    </Card>
  );
}
