import { useCallback, useEffect, useState } from "react";
import { Button, Drawer, Separator, toast } from "@heroui/react";
import { Pencil, Plus, TrashBin, Link as LinkIcon, FaceRobot, FileText } from "@gravity-ui/icons";
import { useApp } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { KIND, PRIORITY, STATUS, ago, ddmmyyyy, isOpen, parseDate } from "../lib/format.js";
import { DueText, ErrorBox, Person, Seal, SelectField, StatusBadge, TextAreaInput, TextInput, useMedia } from "./ui.jsx";
import { TaskList } from "./TaskRow.jsx";
import TaskForm from "./TaskForm.jsx";

const KIND_TONE = { question: "text-warning", result: "text-accent", submit: "text-accent", approve: "text-success", reject: "text-danger", error: "text-danger" };

function Facts({ rows }) {
  return (
    <dl className="grid grid-cols-[auto_1fr] gap-x-4 rounded-xl bg-surface px-4 py-1">
      {rows.filter(Boolean).map(([k, v], i) => (
        <div key={k} className="contents">
          <dt className={`py-2.5 text-muted ${i ? "border-t-2 border-background" : ""}`}>{k}</dt>
          <dd className={`min-w-0 py-2.5 font-medium [overflow-wrap:anywhere] ${i ? "border-t-2 border-background" : ""}`}>{v}</dd>
        </div>
      ))}
    </dl>
  );
}

export default function TaskDrawer() {
  const { openTaskId, openTask, lookups, userId, isAdmin, role, membership, refresh, version } = useApp();
  const desktop = useMedia("(min-width: 1024px)");
  const [d, setD] = useState(null);
  const [error, setError] = useState(null);
  const [editing, setEditing] = useState(false);
  const [sub, setSub] = useState(false);
  const [note, setNote] = useState("");
  const [comment, setComment] = useState("");
  const [answer, setAnswer] = useState("");
  const [reason, setReason] = useState("");
  const [rejecting, setRejecting] = useState(false);
  const [link, setLink] = useState({ url: "", title: "" });
  const [busy, setBusy] = useState("");
  const [stamped, setStamped] = useState(false);

  const load = useCallback((id) => rpc("app_task", { id }), []);

  useEffect(() => {
    if (!openTaskId) { setD(null); return; }
    let alive = true; setError(null); setStamped(false);
    load(openTaskId).then((x) => alive && setD(x)).catch((e) => alive && setError(e));
    return () => { alive = false; };
  }, [openTaskId, load, version]);
  useEffect(() => { setNote(""); setComment(""); setAnswer(""); setReason(""); setRejecting(false); setLink({ url: "", title: "" }); }, [openTaskId]);

  async function act(name, fn, ok) {
    setBusy(name);
    try { await fn(); if (ok) toast.success(ok); refresh(); }
    catch (e) { toast.danger(e.message); }
    finally { setBusy(""); }
  }

  const t = d?.task;
  const canEdit = !!d?.can_edit;
  const canSubmit = !!d?.can_submit;
  const lastApproval = t?.status === "done" ? d?.approvals?.filter((a) => a.decision === "approved").at(-1) : null;
  const report = d?.reports?.[0];
  const agentName = (code) => lookups.agent[code]?.name || code;
  const flow = t && lookups.flow[t.approval_flow_id];

  return (
    <>
      <Drawer.Backdrop isOpen={!!openTaskId} onOpenChange={(o) => !o && openTask(null)} variant={desktop ? "transparent" : undefined}>
        <Drawer.Content placement={desktop ? "right" : "bottom"}>
          <Drawer.Dialog className={`bg-background ${desktop ? "w-[min(560px,100vw)] max-w-none" : "max-h-[92dvh]"}`}>
            {!desktop && <Drawer.Handle />}
            <Drawer.CloseTrigger />
            <Drawer.Header>
              {t ? (
                <div className="flex flex-col gap-2 pr-8">
                  <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted">
                    <StatusBadge status={t.status} waiting={t.waiting_on_human} /><span>T-{t.id}</span>
                    {t.attempts > 0 && <span>Nộp lần {t.attempts + 1}</span>}
                  </div>
                  <Drawer.Heading className="text-xl font-extrabold leading-snug tracking-tight [overflow-wrap:anywhere]">{t.title}</Drawer.Heading>
                </div>
              ) : <Drawer.Heading>{error ? "Không mở được việc" : "Đang tải"}</Drawer.Heading>}
            </Drawer.Header>
            <Drawer.Body className="flex flex-col gap-5 pb-8">
              {error && <ErrorBox error={error} />}
              {!t && !error && <div className="h-40 animate-pulse rounded-xl bg-surface" />}
              {t && (<>
                {t.status === "done" && lastApproval && <div><Seal date={lastApproval.decided_at} press={stamped} /></div>}

                <Facts rows={[
                  ["Phòng ban", lookups.dept[t.department_id] ? `${lookups.dept[t.department_id].code} · ${lookups.dept[t.department_id].name}` : "Chung công ty"],
                  ["Phụ trách", <Person key="a" user={lookups.person[t.assignee_id]} />],
                  t.agent_role && ["Agent", <span key="g" className="inline-flex items-center gap-1.5"><FaceRobot className="size-4" />{agentName(t.agent_role)}{t.claimed_by ? `, chạy trên ${t.claimed_by.replace(/^hermes:/, "")}` : ""}</span>],
                  ["Ưu tiên", PRIORITY[t.priority]],
                  t.due_date && ["Hạn", <span key="d">{ddmmyyyy(parseDate(t.due_date))} <DueText task={t} className="ml-1" /></span>],
                  lookups.project[t.project_id] && ["Dự án", lookups.project[t.project_id].name],
                  flow && ["Quy trình duyệt", `${flow.name}, ${flow.steps?.length || 0} bước`],
                  ["Người giao", t.created_by ? (lookups.person[t.created_by]?.name || "Không rõ") : (t.created_by_agent || "Hệ thống")],
                  ["Cập nhật", ago(t.updated_at)],
                ]} />

                {t.description && <p className="whitespace-pre-wrap rounded-xl bg-surface px-4 py-3 [overflow-wrap:anywhere]">{t.description}</p>}

                <div className="flex flex-wrap gap-2">
                  {canEdit && <Button size="sm" variant="secondary" onPress={() => setEditing(true)}><Pencil className="size-4" />Sửa</Button>}
                  <Button size="sm" variant="secondary" onPress={() => setSub(true)}><Plus className="size-4" />Việc con</Button>
                  {canEdit && isOpen(t) && t.status !== "in_review" && (
                    <div className="min-w-44">
                      <SelectField label="Đổi trạng thái" value={t.status} onChange={(v) => v && v !== t.status && act("status", () => rpc("app_task_save", { id: t.id, status: v }), `Đã chuyển sang ${STATUS[v]}`)}
                        options={["todo", "in_progress", "blocked", "cancelled"].map((s) => ({ value: s, label: STATUS[s] }))} />
                    </div>
                  )}
                </div>

                {/* Agent đang hỏi */}
                {d.can_answer && (
                  <div className="flex flex-col gap-3 rounded-xl bg-surface p-4">
                    <span className="h-1 w-6 rounded bg-warning" />
                    <p className="text-[17px] leading-relaxed">{[...d.comments].reverse().find((c) => c.kind === "question")?.body || "Agent đang chờ bạn trả lời."}</p>
                    <TextAreaInput label="Câu trả lời" hideLabel value={answer} onChange={setAnswer} placeholder="Viết câu trả lời cho agent" rows={2} />
                    <Button isPending={busy === "answer"} isDisabled={!answer.trim()} onPress={() => act("answer", () => rpc("app_answer", { task: t.id, body: answer }), "Đã gửi, agent sẽ làm tiếp")}>Gửi trả lời</Button>
                  </div>
                )}

                {/* Kết quả agent nộp: người giao xem trước */}
                {report && (t.status === "in_review" || t.status === "done") && (
                  <section className="flex flex-col gap-2">
                    <h3 className="font-extrabold">Báo cáo của agent</h3>
                    <div className="flex flex-col gap-2 rounded-xl bg-surface p-4">
                      <p className="whitespace-pre-wrap [overflow-wrap:anywhere]">{report.summary}</p>
                      <p className="flex flex-wrap gap-x-4 gap-y-1 text-sm text-muted">
                        {report.confidence && <span>Độ tin cậy: {report.confidence}</span>}
                        {report.residual_risk && <span>Rủi ro còn lại: {report.residual_risk}</span>}
                        {report.next_actions && <span>Việc tiếp theo: {report.next_actions}</span>}
                      </p>
                      {Array.isArray(report.outputs) && report.outputs.filter((o) => /^https:\/\//.test(o?.url || "")).length > 0 && (
                        <ul className="flex flex-wrap gap-2">
                          {report.outputs.filter((o) => /^https:\/\//.test(o?.url || "")).map((o, i) => (
                            <li key={i}><a href={o.url} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1.5 rounded-full bg-surface-secondary px-3 py-1.5 text-sm font-semibold text-accent hover:underline"><FileText className="size-3.5" />{o.name || "Tệp"}</a></li>
                          ))}
                        </ul>
                      )}
                    </div>
                  </section>
                )}
                {d.can_review && (
                  <div className="relative flex flex-col gap-3 rounded-xl bg-surface p-4">
                    <p className="font-semibold">Agent đã nộp kết quả. Xem rồi chấp nhận{t.approval_flow_id ? " để chuyển sang các bước duyệt" : " để đóng việc"}, hoặc trả lại để làm lại.</p>
                    {rejecting && <TextAreaInput label="Lý do trả lại" value={reason} onChange={setReason} rows={2} description="Agent sẽ làm lại theo góp ý này." />}
                    <div className="flex flex-wrap gap-2">
                      <Button variant="secondary" className="flex-1" isPending={busy === "rework"} onPress={() => {
                        if (!rejecting) { setRejecting(true); return; }
                        if (reason.trim().length < 5) { toast.danger("Ghi lý do (ít nhất 5 ký tự) để agent biết cần sửa gì"); return; }
                        act("rework", () => rpc("app_reject", { task: t.id, reason }), "Đã trả lại, agent sẽ làm lại");
                      }}>{rejecting ? "Gửi trả lại" : "Trả lại"}</Button>
                      <Button className="flex-[2]" isPending={busy === "accept"} onPress={() => act("accept", () => rpc("app_accept", { task: t.id }), t.approval_flow_id ? "Đã chuyển sang các bước duyệt" : "Đã chấp nhận kết quả")}>Chấp nhận kết quả</Button>
                    </div>
                  </div>
                )}

                {/* Duyệt */}
                {d.approvals.length > 0 && (
                  <section className="flex flex-col gap-2">
                    <h3 className="font-extrabold">Các bước duyệt</h3>
                    <ol className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
                      {d.approvals.map((a) => {
                        const current = t.status === "in_review" && a.step_no === t.current_step;
                        const tone = a.decision === "approved" ? "text-success" : a.decision === "rejected" ? "text-danger" : current ? "text-foreground" : "text-muted";
                        return (
                          <li key={a.step_no} className={`flex items-start gap-3 bg-surface px-4 py-3 ${current ? "shadow-[inset_3px_0_0_var(--seal)]" : ""}`}>
                            <span className={`font-extrabold ${tone}`}>{a.step_no}</span>
                            <span className="flex min-w-0 flex-1 flex-col">
                              <span className="font-semibold">{a.step_name}</span>
                              <span className={`text-sm ${tone}`}>
                                {a.decision === "approved" && `Đã duyệt bởi ${lookups.person[a.decided_by]?.name || ""}, ${ago(a.decided_at)}`}
                                {a.decision === "rejected" && `Trả lại bởi ${lookups.person[a.decided_by]?.name || ""}: ${a.note || ""}`}
                                {a.decision === "pending" && (current ? "Đang chờ duyệt" : "Chưa tới lượt")}
                                {a.decision === "skipped" && "Bỏ qua"}
                              </span>
                            </span>
                          </li>
                        );
                      })}
                    </ol>
                  </section>
                )}
                {d.can_approve && t.status === "in_review" && (
                  <div className="relative flex flex-col gap-3 overflow-hidden rounded-xl bg-surface p-4">
                    {stamped && <div className="absolute right-4 top-4"><Seal date={new Date()} press /></div>}
                    <p className="font-semibold">Bạn duyệt bước {t.current_step}: {d.approvals.find((a) => a.step_no === t.current_step)?.step_name}</p>
                    {rejecting && <TextAreaInput label="Lý do trả lại" value={reason} onChange={setReason} rows={2} description="Người làm sẽ sửa theo góp ý này." />}
                    <div className="flex flex-wrap gap-2">
                      <Button variant="secondary" className="flex-1" isPending={busy === "reject"} onPress={() => {
                        if (!rejecting) { setRejecting(true); return; }
                        if (!reason.trim()) { toast.danger("Ghi lý do để người làm biết cần sửa gì"); return; }
                        act("reject", () => rpc("app_decide", { task: t.id, approve: false, note: reason }), `Đã trả lại T-${t.id}`);
                      }}>{rejecting ? "Gửi trả lại" : "Trả lại"}</Button>
                      <Button className="btn-stamp flex-[2]" isPending={busy === "approve"} onPress={async () => {
                        setStamped(true);
                        await act("approve", () => rpc("app_decide", { task: t.id, approve: true }), `Đã duyệt T-${t.id}`);
                      }}>Đóng dấu duyệt</Button>
                    </div>
                  </div>
                )}

                {/* Nộp kết quả */}
                {canSubmit && (
                  <div className="flex flex-col gap-3 rounded-xl bg-surface p-4">
                    <TextAreaInput label={t.approval_flow_id ? "Nộp để duyệt" : "Nộp kết quả"} value={note} onChange={setNote} rows={2}
                      placeholder="Tóm tắt kết quả, nơi lưu tài liệu" description={t.approval_flow_id ? `Việc sẽ chuyển qua ${flow?.steps?.length || ""} bước duyệt.` : "Việc sẽ chuyển sang Xong."} />
                    <Button isPending={busy === "submit"} onPress={() => act("submit", () => rpc("app_submit", { task: t.id, note }), t.approval_flow_id ? "Đã nộp để duyệt" : "Đã hoàn thành")}>
                      {t.approval_flow_id ? "Nộp để duyệt" : "Hoàn thành"}
                    </Button>
                  </div>
                )}

                {/* Tài liệu */}
                <section className="flex flex-col gap-2">
                  <h3 className="font-extrabold">Tài liệu</h3>
                  {(d.links.length > 0 || d.files.length > 0) ? (
                    <ul className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
                      {d.links.map((l) => (
                        <li key={`l${l.id}`} className="flex items-center gap-3 bg-surface px-4 py-3">
                          <LinkIcon className="size-4 shrink-0 text-muted" />
                          <a href={l.url} target="_blank" rel="noopener noreferrer" className="min-w-0 flex-1 truncate font-semibold text-accent underline-offset-2 hover:underline">{l.title}</a>
                          {(canEdit || l.added_by === userId) && <Button isIconOnly size="sm" variant="ghost" aria-label={`Gỡ ${l.title}`} onPress={() => act("rm", () => rpc("app_link_remove", { link: l.id }), "Đã gỡ link")}><TrashBin className="size-4" /></Button>}
                        </li>
                      ))}
                      {d.files.map((f) => (
                        <li key={f.file_id} className="flex items-center gap-3 bg-surface px-4 py-3">
                          <FileText className="size-4 shrink-0 text-muted" />
                          <a href={f.web_url} target="_blank" rel="noopener noreferrer" className="min-w-0 flex-1 truncate font-semibold text-accent underline-offset-2 hover:underline">{f.name}</a>
                          <span className="shrink-0 text-xs text-muted">Drive · {lookups.person[f.owner_user]?.name || ""}</span>
                        </li>
                      ))}
                    </ul>
                  ) : <p className="text-sm text-muted">Chưa có tài liệu. Dán link Drive, hoặc đặt tên tệp trong thư mục của bạn bắt đầu bằng "T-{t.id}" để agent tự gắn vào việc này.</p>}
                  <form className="flex flex-col gap-2 sm:flex-row sm:items-end" onSubmit={(e) => { e.preventDefault(); if (!link.url) return;
                    act("link", () => rpc("app_link_add", { task: t.id, url: link.url, title: link.title }), "Đã thêm tài liệu").then(() => setLink({ url: "", title: "" })); }}>
                    <TextInput label="Link Google Drive" type="url" value={link.url} onChange={(v) => setLink((s) => ({ ...s, url: v }))} placeholder="https://drive.google.com/..." className="w-full sm:flex-[2]" />
                    <TextInput label="Tên hiển thị" value={link.title} onChange={(v) => setLink((s) => ({ ...s, title: v }))} placeholder="Bản nháp v2" className="w-full sm:flex-1" />
                    <Button type="submit" variant="secondary" isPending={busy === "link"} isDisabled={!link.url}>Thêm</Button>
                  </form>
                </section>

                {d.children.length > 0 && (
                  <section className="flex flex-col gap-2"><h3 className="font-extrabold">Việc con</h3><TaskList tasks={d.children} showDept={false} /></section>
                )}

                <Separator />
                {/* Trao đổi */}
                <section className="flex flex-col gap-2">
                  <h3 className="font-extrabold">Trao đổi</h3>
                  {d.comments.length ? (
                    <ol className="flex flex-col gap-0.5 overflow-hidden rounded-xl">
                      {d.comments.map((c) => (
                        <li key={c.id} className="flex flex-col gap-1 bg-surface px-4 py-3">
                          <span className="flex flex-wrap gap-x-3 text-sm text-muted">
                            <b className={KIND_TONE[c.kind] || "text-foreground"}>{KIND[c.kind] || c.kind}</b>
                            <span>{c.user_id ? lookups.person[c.user_id]?.name || "Người dùng" : `Agent ${agentName(c.actor.replace(/^agent:/, ""))}`}</span>
                            <span>{ago(c.created_at)}</span>
                          </span>
                          <span className="whitespace-pre-wrap [overflow-wrap:anywhere]">{c.body}</span>
                        </li>
                      ))}
                    </ol>
                  ) : <p className="text-sm text-muted">Chưa có trao đổi.</p>}
                  <TextAreaInput label="Thêm ghi chú" hideLabel value={comment} onChange={setComment} placeholder="Viết ghi chú cho mọi người trong việc này" rows={2} />
                  <div><Button variant="secondary" isDisabled={!comment.trim()} isPending={busy === "comment"}
                    onPress={() => act("comment", () => rpc("app_comment", { task: t.id, body: comment }), "Đã lưu ghi chú").then(() => setComment(""))}>Lưu ghi chú</Button></div>
                </section>
              </>)}
            </Drawer.Body>
          </Drawer.Dialog>
        </Drawer.Content>
      </Drawer.Backdrop>
      {t && <TaskForm isOpen={editing} onClose={() => setEditing(false)} task={t} />}
      {t && <TaskForm isOpen={sub} onClose={() => setSub(false)} parent={t} />}
    </>
  );
}
