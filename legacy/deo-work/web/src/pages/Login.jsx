import { useEffect, useRef, useState } from "react";
import { Button, Card } from "@heroui/react";
import { authCall } from "../lib/api.js";
import { useApp } from "../lib/store.jsx";
import { ErrorBox, TextInput } from "../components/ui.jsx";

function loadGis() {
  if (window.google?.accounts?.id) return Promise.resolve();
  return new Promise((res, rej) => {
    const s = document.createElement("script");
    s.src = "https://accounts.google.com/gsi/client"; s.async = true; s.onload = res; s.onerror = () => rej(new Error("Không tải được nút đăng nhập Google"));
    document.head.appendChild(s);
  });
}

export default function Login() {
  const { signIn, route } = useApp();
  const [cfg, setCfg] = useState(null);
  const [invite, setInvite] = useState((route.params.code || "").toUpperCase());
  const [needInvite, setNeedInvite] = useState(!!route.params.code);
  const [pending, setPending] = useState(null);       // credential đang chờ mã mời
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);
  const [dev, setDev] = useState({ email: "", name: "" });
  const btn = useRef(null);
  const inviteRef = useRef(invite);
  inviteRef.current = invite;

  useEffect(() => { authCall("/config").then(setCfg).catch(setError); }, []);

  async function submit(credential, code = inviteRef.current) {
    setBusy(true); setError(null);
    try {
      const s = await authCall("/google", { credential, invite: code || undefined });
      signIn(s);
      history.replaceState(null, "", "#/today");
    } catch (e) {
      if (e.code === "INVITE_REQUIRED") { setPending(credential); setNeedInvite(true); setError(new Error("Tài khoản Google này chưa có trong hệ thống. Nhập mã mời quản trị gửi cho bạn.")); }
      else setError(e);
    } finally { setBusy(false); }
  }

  useEffect(() => {
    if (!cfg?.google_client_id) return;
    loadGis().then(() => {
      window.google.accounts.id.initialize({ client_id: cfg.google_client_id, callback: (r) => submit(r.credential), ux_mode: "popup" });
      if (btn.current) window.google.accounts.id.renderButton(btn.current, { theme: "outline", size: "large", text: "signin_with", shape: "pill", locale: "vi", width: 300 });
    }).catch(setError);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cfg]);

  return (
    <div className="grid min-h-dvh place-items-center px-4 py-10">
      <div className="flex w-full max-w-md flex-col gap-6">
        <div className="flex items-center gap-3">
          <svg viewBox="0 0 32 32" className="size-10" aria-hidden="true"><rect x="3" y="3" width="26" height="26" rx="7" fill="var(--seal)" /><path d="M10 16.5l4 4 8-9" fill="none" stroke="#fff" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" /></svg>
          <span className="text-2xl font-extrabold tracking-tight">Dẹo Work</span>
        </div>
        <div>
          <h1 className="text-3xl font-extrabold leading-tight tracking-tight text-balance">Giao việc, theo dõi và duyệt trong một nơi.</h1>
          <p className="mt-2 text-muted">Đăng nhập bằng tài khoản Google của bạn. Lần đầu vào cần mã mời từ quản trị công ty.</p>
        </div>
        <Card className="gap-5 p-5">
          {needInvite && (
            <TextInput label="Mã mời" value={invite} onChange={(v) => setInvite(v.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 8))}
              placeholder="8 ký tự, ví dụ K7Q2M9XD" description="Quản trị hoặc trưởng phòng gửi mã này cho bạn." />
          )}
          {pending && (
            <Button isPending={busy} isDisabled={invite.length !== 8} onPress={() => submit(pending, invite)}>Vào bằng mã mời</Button>
          )}
          {!pending && cfg?.google_client_id && <div ref={btn} className="min-h-11" />}
          {!pending && !cfg && !error && <div className="h-11 animate-pulse rounded-full bg-surface-secondary" />}
          {!needInvite && <button type="button" className="self-start text-sm font-semibold text-accent underline-offset-2 hover:underline" onClick={() => setNeedInvite(true)}>Tôi có mã mời</button>}
          {cfg?.dev_login && !pending && (
            <form className="flex flex-col gap-3 rounded-lg bg-surface-secondary p-3" onSubmit={(e) => { e.preventDefault(); submit(`dev:${dev.email}:${dev.name || dev.email}`); }}>
              <p className="text-sm font-semibold text-warning">Chế độ thử nghiệm: đăng nhập không qua Google</p>
              <TextInput label="Email" type="email" value={dev.email} onChange={(v) => setDev((s) => ({ ...s, email: v }))} />
              <TextInput label="Họ tên" value={dev.name} onChange={(v) => setDev((s) => ({ ...s, name: v }))} />
              <Button type="submit" variant="secondary" isPending={busy} isDisabled={!dev.email}>Đăng nhập thử</Button>
            </form>
          )}
          {error && <ErrorBox error={error} />}
        </Card>
        <p className="text-sm text-muted">Hệ thống chỉ đọc tên, email và ảnh đại diện từ Google. Tài liệu làm việc nằm trong thư mục Drive của chính bạn.</p>
      </div>
    </div>
  );
}
