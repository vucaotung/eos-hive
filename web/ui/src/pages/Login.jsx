import { useState } from "react";
import { Button, Card } from "@heroui/react";
import { join } from "../lib/api.js";
import { useApp } from "../lib/store.jsx";
import { ErrorBox, TextInput } from "../components/ui.jsx";
import Logo from "../components/Logo.jsx";

const MESSAGES = {
  denied: "Tài khoản Google này chưa được cấp quyền vào hệ thống, hoặc phiên đăng nhập đã hết hạn. Nếu bạn có mã mời, nhập mã rồi đăng nhập lại.",
  state: "Phiên đăng nhập đã hết hạn. Hãy thử lại.",
  google: "Google không xác nhận được đăng nhập. Hãy thử lại.",
  invite_invalid: "Mã mời không đúng, đã hết hạn, đã dùng hết hoặc không dành cho email này.",
  invite_required: "Tài khoản Google này chưa có trong hệ thống. Nhập mã mời quản trị gửi cho bạn.",
  config: "Đăng nhập Google chưa được cấu hình trên máy chủ.",
};

export default function Login() {
  const { route, loadMe } = useApp();
  const need = route.params.e === "invite_required" || route.params.e === "invite_invalid";             // đã xác thực Google, đang chờ mã mời
  const [invite, setInvite] = useState((route.params.code || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8));
  const [showInvite, setShowInvite] = useState(!!route.params.code || need);
  const [error, setError] = useState(route.params.e ? new Error(MESSAGES[route.params.e] || MESSAGES.denied) : null);
  const [busy, setBusy] = useState(false);

  const googleHref = `/app/auth/google${invite.length === 8 ? `?invite=${invite}` : ""}`;
  async function submit() {
    setBusy(true); setError(null);
    try { await join(invite); history.replaceState(null, "", "#/today"); await loadMe(); }
    catch (e) { setError(e); } finally { setBusy(false); }
  }

  return (
    <div className="grid min-h-dvh place-items-center px-4 py-10">
      <div className="flex w-full max-w-md flex-col gap-6">
        <div className="flex items-center gap-3">
          <Logo className="size-16" />
          <span className="flex flex-col leading-tight"><span className="text-2xl font-extrabold tracking-tight">Enterprise OS</span><span className="text-sm font-semibold text-muted">AI agent and Human collab platform</span></span>
        </div>
        <div>
          <h1 className="text-3xl font-extrabold leading-tight tracking-tight text-balance">Con người và AI agent cùng làm việc trong một nơi.</h1>
          <p className="mt-2 text-muted">Đăng nhập bằng tài khoản Google của bạn. Lần đầu vào cần mã mời từ quản trị công ty.</p>
        </div>
        <Card className="gap-5 p-5">
          {showInvite && (
            <TextInput label="Mã mời" value={invite} onChange={(v) => setInvite(v.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8))}
              placeholder="8 ký tự, ví dụ K7Q2M9XD" description="Quản trị hoặc trưởng phòng gửi mã này cho bạn." autoFocus={need} />
          )}
          {need
            ? <Button isPending={busy} isDisabled={invite.length !== 8} onPress={submit}>Vào bằng mã mời</Button>
            : <a href={googleHref} className="inline-flex h-11 items-center justify-center rounded-full bg-accent px-6 font-semibold text-accent-foreground hover:opacity-90">Đăng nhập với Google</a>}
          {!showInvite && <button type="button" className="self-start text-sm font-semibold text-accent underline-offset-2 hover:underline" onClick={() => setShowInvite(true)}>Tôi có mã mời</button>}
          {error && <ErrorBox error={error} />}
        </Card>
        <p className="text-sm text-muted">Hệ thống chỉ đọc tên, email và ảnh đại diện từ Google. Tài liệu làm việc nằm trong thư mục Drive của chính bạn.</p>
      </div>
    </div>
  );
}
