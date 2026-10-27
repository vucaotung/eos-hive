import { useState } from "react";
import { Button, Switch, toast } from "@heroui/react";
import { rpc } from "../lib/api.js";
import { useLoad } from "../lib/store.jsx";
import { STATUS, ago, dt } from "../lib/format.js";
import { Empty, ErrorBox } from "./ui.jsx";

// Quản trị hệ thống (chỉ người có is_system_admin): cầu nối Hermes, agent, mã MCP của mọi người, nhật ký gọi MCP
const Stat = ({ n, label, bad }) => (
  <div className="flex flex-col gap-0.5 rounded-xl bg-surface px-4 py-3">
    <b className={`text-2xl font-semibold tracking-tight ${bad ? "text-danger" : ""}`}>{n}</b><span className="text-sm font-semibold text-muted">{label}</span>
  </div>
);
const Table = ({ head, children }) => (
  <div className="overflow-x-auto rounded-xl bg-surface">
    <table className="w-full min-w-[640px] text-left text-sm">
      <thead className="text-muted"><tr>{head.map((h) => <th key={h} className="px-3 py-3 font-semibold">{h}</th>)}</tr></thead>
      <tbody>{children}</tbody>
    </table>
  </div>
);
const Row = ({ dim, children }) => <tr className={`border-t-2 border-background ${dim ? "opacity-60" : ""}`}>{children}</tr>;
const Td = ({ children, className = "" }) => <td className={`px-3 py-2.5 ${className}`}>{children}</td>;

function Overview() {
  const { data: ov, error } = useLoad(() => rpc("web_admin_overview"), []);
  if (error) return <ErrorBox error={error} />;
  if (!ov) return <div className="h-40 animate-pulse rounded-xl bg-surface" />;
  const b = ov.bridge || {}, m = ov.mcp || {}, ts = ov.tasks || {};
  return (
    <div className="flex flex-col gap-6">
      <h3 className="font-semibold">Cầu nối Hermes</h3>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-5">
        <Stat n={b.outbox_pending ?? 0} label="Lệnh chờ đẩy sang Kanban" bad={b.outbox_pending > 0 && b.outbox_oldest_pending_s > 300} />
        <Stat n={b.outbox_errors ?? 0} label="Lệnh lỗi" bad={b.outbox_errors > 0} />
        <Stat n={b.cards_stuck_running ?? 0} label='Thẻ kẹt "đang chạy" > 2 giờ' bad={b.cards_stuck_running > 0} />
        <Stat n={b.last_card_event ? ago(b.last_card_event) : "–"} label="Sự kiện thẻ gần nhất" />
        <Stat n={ov.confirmations_pending ?? 0} label="Xác nhận L2 đang chờ" />
      </div>
      <h3 className="font-semibold">Agent</h3>
      <Table head={["Mã", "Tên", "Module", "Profile Hermes", "Bật", "Cấp", "Việc mở", "Đang chạy", "Skill", "Mã MCP còn", "Quyền mã"]}>
        {(ov.agents || []).map((a) => (
          <Row key={a.code} dim={!a.active}>
            <Td><code>{a.code}</code></Td><Td>{a.name}</Td><Td>{a.module}</Td><Td><code>{a.profile}</code></Td><Td>{a.active ? "✔" : "✘"}</Td><Td>L{a.max_level}</Td>
            <Td>{a.tasks_open}</Td><Td>{a.cards_running}</Td><Td>{(a.skills || []).join(", ") || "—"}</Td>
            <Td className={a.token_days_left == null ? (a.active ? "font-semibold text-danger" : "") : a.token_days_left <= 14 ? "font-semibold text-warning" : ""}>{a.token_days_left == null ? (a.active ? "chưa có" : "—") : `${a.token_days_left} ngày`}</Td>
            <Td>{(a.token_scopes || []).join(", ") || "—"}</Td>
          </Row>
        ))}
      </Table>
      <h3 className="font-semibold">Việc theo trạng thái</h3>
      <div className="grid grid-cols-3 gap-2 sm:grid-cols-6">{Object.entries(STATUS).map(([k, l]) => <Stat key={k} n={ts[k] ?? 0} label={l} />)}</div>
      <h3 className="font-semibold">MCP trong 24 giờ</h3>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4"><Stat n={m.calls_24h ?? 0} label="Lượt gọi" /><Stat n={m.denied_24h ?? 0} label="Bị từ chối" bad={m.denied_24h > 20} /></div>
    </div>
  );
}

function Tokens() {
  const [tick, setTick] = useState(0);
  const { data, error } = useLoad(() => rpc("web_admin_tokens"), [tick]);
  async function revoke(k) {
    if (!confirm(`Thu hồi mã của ${k.who}?`)) return;
    try { await rpc("web_token_revoke", { id: k.id }); toast.success("Đã thu hồi mã"); setTick((x) => x + 1); } catch (e) { toast.danger(e.message); }
  }
  return (<div className="flex flex-col gap-3"><ErrorBox error={error} />
    {data?.length ? (
      <Table head={["Của", "Tên", "Mã", "Quyền", "Hết hạn", "Dùng gần nhất", "IP", ""]}>
        {data.map((k) => (
          <Row key={k.id} dim={!k.active}>
            <Td>{k.who}</Td><Td>{k.name}</Td><Td><code>eos_{k.prefix}…</code></Td><Td>{(k.scopes || []).join(", ")}</Td>
            <Td>{k.revoked_at ? "Đã thu hồi" : dt(k.expires_at)}</Td><Td>{k.last_used_at ? ago(k.last_used_at) : "—"}</Td><Td>{k.last_ip || "—"}</Td>
            <Td>{k.active && <Button size="sm" variant="ghost" onPress={() => revoke(k)}>Thu hồi</Button>}</Td>
          </Row>
        ))}
      </Table>
    ) : data && <Empty>Chưa có mã nào.</Empty>}</div>);
}

function Calls() {
  const [denied, setDenied] = useState(false);
  const { data, error } = useLoad(() => rpc("web_admin_calls", { limit: 150, denied }), [denied]);
  return (<div className="flex flex-col gap-3">
    <Switch isSelected={denied} onChange={setDenied}><Switch.Content><Switch.Control><Switch.Thumb /></Switch.Control>Chỉ lượt bị từ chối</Switch.Content></Switch>
    <ErrorBox error={error} />
    {data?.length ? (
      <Table head={["Lúc", "Của", "Mã", "Công cụ", "Kết quả", "Đối tượng", "ms"]}>
        {data.map((c, i) => (
          <Row key={i}>
            <Td>{dt(c.at)}</Td><Td>{c.who || "—"}</Td><Td><code>{c.prefix ? `eos_${c.prefix}…` : "—"}</code></Td><Td><code>{c.tool}</code></Td>
            <Td className={c.outcome === "ok" ? "text-success" : "font-semibold text-danger"}>{c.outcome}</Td><Td>{c.entity || "—"}</Td><Td>{c.ms ?? "—"}</Td>
          </Row>
        ))}
      </Table>
    ) : data && <Empty>Không có lượt gọi nào.</Empty>}</div>);
}

export default function AgentAdmin() {
  const [view, setView] = useState("overview");
  const views = [["overview", "Tổng quan", Overview], ["tokens", "Mã MCP", Tokens], ["calls", "Nhật ký gọi MCP", Calls]];
  const C = views.find((v) => v[0] === view)[2];
  return (
    <div className="flex flex-col gap-5">
      <div className="no-scrollbar flex gap-2 overflow-x-auto" role="group" aria-label="Mục">
        {views.map(([k, label]) => (
          <button key={k} type="button" aria-pressed={view === k} onClick={() => setView(k)}
            className={`h-10 shrink-0 rounded-full px-4 text-[15px] font-semibold ${view === k ? "bg-foreground text-background" : "bg-surface hover:bg-surface-secondary"}`}>{label}</button>
        ))}
      </div>
      <C />
    </div>
  );
}
