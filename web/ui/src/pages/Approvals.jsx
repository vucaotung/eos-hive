import { useState } from "react";
import { Button, toast } from "@heroui/react";
import { Link as LinkIcon } from "@gravity-ui/icons";
import { useApp, useLoad } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { ago } from "../lib/format.js";
import { DueText, Empty, ErrorBox, LoadingList, PageHeader, Seal, Section, TextAreaInput } from "../components/ui.jsx";
import { TaskList } from "../components/TaskRow.jsx";

// Phiếu duyệt: kind "approval" = bước trong quy trình duyệt; kind "review" = người giao xem kết quả agent nộp
function Slip({ item, onDone }) {
  const { lookups, openTask } = useApp();
  const t = item.task, review = item.kind === "review";
  const [rejecting, setRejecting] = useState(false);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState("");
  const [stamped, setStamped] = useState(false);
  const [gone, setGone] = useState(false);
  const by = item.result;
  const who = by ? (by.user_id ? lookups.person[by.user_id]?.name : `Agent ${lookups.agent[by.actor.replace(/^agent:/, "")]?.name || ""}`) : null;

  async function decide(approve) {
    if (!approve && !rejecting) { setRejecting(true); return; }
    if (!approve && reason.trim().length < (review ? 5 : 3)) { toast.danger("Ghi lý do để người làm biết cần sửa gì"); return; }
    setBusy(approve ? "a" : "r");
    if (approve) setStamped(true);
    try {
      if (review) await rpc(approve ? "app_accept" : "app_reject", approve ? { task: t.id } : { task: t.id, reason });
      else await rpc("app_decide", { task: t.id, approve, note: approve ? "" : reason });
      toast.success(approve ? `Đã duyệt T-${t.id}` : `Đã trả lại T-${t.id}`);
      setTimeout(() => { setGone(true); setTimeout(onDone, 320); }, approve ? 700 : 0);
    } catch (e) { setStamped(false); toast.danger(e.message); setBusy(""); }
  }

  return (
    <article className={`relative flex flex-col gap-3.5 overflow-hidden rounded-xl bg-surface p-4 transition-all duration-300 sm:p-5 ${gone ? "translate-x-6 opacity-0" : ""}`}>
      {stamped && <div className="absolute right-4 top-4 z-10"><Seal date={new Date()} press /></div>}
      <div className="flex flex-wrap gap-x-3.5 gap-y-1 text-sm text-muted">
        <b className="text-foreground">{lookups.dept[t.department_id]?.code || "Chung"}</b>
        <span>{review ? item.step_name : `Bước ${item.step_no}/${item.steps}: ${item.step_name}`}</span>
        <span>T-{t.id}</span>{t.attempts > 0 && <span>Nộp lần {t.attempts + 1}</span>}<DueText task={t} />
      </div>
      <h3 className="text-xl font-extrabold leading-tight tracking-tight text-balance">
        <button type="button" className="text-left hover:underline" onClick={() => openTask(t.id)}>{t.title}</button>
      </h3>
      <div className="rounded-lg bg-background px-3.5 py-3">
        <span className="mb-1 block text-sm font-semibold text-muted">{by ? `${who || "Người làm"} nộp ${ago(by.created_at)}` : `Phụ trách: ${lookups.person[t.assignee_id]?.name || "chưa giao"}`}</span>
        <p className="whitespace-pre-wrap [overflow-wrap:anywhere]">{by?.body || "Không có ghi chú khi nộp. Mở việc để xem tài liệu và trao đổi."}</p>
      </div>
      {item.links.length > 0 && (
        <ul className="flex flex-wrap gap-2">
          {item.links.map((l) => (
            <li key={l.id}><a href={l.url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 rounded-full bg-surface-secondary px-3 py-1.5 text-sm font-semibold text-accent hover:underline"><LinkIcon className="size-3.5" />{l.title}</a></li>
          ))}
        </ul>
      )}
      {rejecting && <TextAreaInput label="Lý do trả lại" value={reason} onChange={setReason} rows={2} description={review ? "Agent sẽ làm lại theo góp ý này." : "Người làm sẽ sửa theo góp ý này rồi nộp lại."} />}
      <div className="flex flex-wrap gap-2">
        <Button variant="secondary" className="flex-1" isPending={busy === "r"} isDisabled={!!busy && busy !== "r"} onPress={() => decide(false)}>{rejecting ? "Gửi trả lại" : "Trả lại"}</Button>
        <Button className="btn-stamp flex-[2]" isPending={busy === "a"} isDisabled={!!busy && busy !== "a"} onPress={() => decide(true)}>{review ? "Chấp nhận kết quả" : "Đóng dấu duyệt"}</Button>
      </div>
    </article>
  );
}

export default function Approvals() {
  const { companyId, refresh } = useApp();
  const { data, error, loading } = useLoad(() => rpc("app_my_approvals"), [companyId]);
  const items = (data?.items || []).filter((i) => i.task.company_id === companyId);
  const recent = (data?.recent || []).filter((t) => t.company_id === companyId && !items.some((i) => i.task_id === t.id));
  return (
    <div className="flex flex-col gap-8">
      <PageHeader title="Duyệt" sub={data ? (items.length ? `${items.length} việc chờ bạn đóng dấu` : "Không còn việc nào chờ bạn duyệt") : " "} />
      <ErrorBox error={error} onRetry={refresh} />
      {loading && !data ? <LoadingList rows={3} /> : (
        <>
          {items.length ? <div className="grid items-start gap-4 xl:grid-cols-2">{items.map((it) => <Slip key={`${it.kind}${it.task_id}`} item={it} onDone={refresh} />)}</div>
            : <Empty>Khi có việc cần bạn duyệt theo quy trình, hoặc agent nộp kết quả cho bạn xem, việc sẽ hiện ở đây.</Empty>}
          {recent.length > 0 && <Section title="Bạn đã xử lý trong 30 ngày" count={recent.length}><TaskList tasks={recent} /></Section>}
        </>
      )}
    </div>
  );
}
