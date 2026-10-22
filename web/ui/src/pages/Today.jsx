import { Alert, Button } from "@heroui/react";
import { useApp, useLoad, go } from "../lib/store.jsx";
import { rpc } from "../lib/api.js";
import { byPriority, isOverdue, isOpen, longDate } from "../lib/format.js";
import { ErrorBox, LoadingList, Section } from "../components/ui.jsx";
import { TaskList } from "../components/TaskRow.jsx";

export default function Today() {
  const { companyId, userId, me, membership, isAdmin } = useApp();
  const { data, error, loading } = useLoad(async () => {
    if (!companyId) return null;
    const [tasks, mine] = await Promise.all([rpc("app_tasks", { company_id: companyId, days: 1 }), rpc("app_my_approvals")]);
    return { tasks: tasks.filter(isOpen), approve: mine.items.map((i) => i.task).filter((t) => t.company_id === companyId) };
  }, [companyId]);

  const tasks = data?.tasks || [];
  const myOpen = tasks.filter((t) => t.assignee_id === userId && t.status !== "in_review").sort(byPriority);
  const iGave = tasks.filter((t) => t.created_by === userId && t.assignee_id !== userId).sort(byPriority);
  const asks = tasks.filter((t) => t.waiting_on_human && (t.assignee_id === userId || t.created_by === userId));
  const late = tasks.filter((t) => isOverdue(t) && (isAdmin || t.department_id === membership?.department_id)).sort(byPriority);
  const approve = data?.approve || [];

  const parts = [];
  if (approve.length) parts.push(`${approve.length} việc chờ duyệt`);
  if (asks.length) parts.push(`${asks.length} câu hỏi của agent`);
  if (myOpen.length) parts.push(`${myOpen.length} việc đang làm`);
  const first = me?.user?.name?.split(" ").at(-1) || "";
  const lead = parts.length ? `${first ? first + ", bạn" : "Bạn"} có ${parts.join(", ")}.` : "Không có việc nào đang chờ bạn.";
  const drive = me?.user?.drive_status;

  const count = (n, label, onPress) => (
    <button type="button" onClick={onPress} className="flex shrink-0 items-baseline gap-2 rounded-full bg-surface px-4 py-2.5 hover:bg-surface-secondary">
      <b className={`text-xl font-extrabold leading-none ${n ? "" : "text-muted"}`}>{n}</b><span className="text-sm font-semibold text-muted">{label}</span>
    </button>
  );

  return (
    <div className="flex flex-col gap-8">
      <div>
        <p className="text-sm font-medium text-muted">{longDate()}</p>
        <h1 className={`mt-1 max-w-[22ch] text-3xl font-extrabold leading-[1.1] tracking-tight text-balance sm:text-4xl ${parts.length ? "" : "text-muted"}`}>{lead}</h1>
      </div>

      {(drive === "none" || drive === "error") && (
        <Alert status={drive === "error" ? "danger" : "warning"}>
          <Alert.Indicator />
          <Alert.Content>
            <Alert.Title>{drive === "error" ? "Thư mục Drive của bạn cần sửa" : "Bạn chưa khai báo thư mục Drive làm việc"}</Alert.Title>
            <Alert.Description>{drive === "error" ? me?.user?.drive_note : "Tài liệu làm việc nằm trong Drive của bạn. Mất khoảng 2 phút để thiết lập."}</Alert.Description>
            <Button className="mt-2" size="sm" onPress={() => go("me")}>Thiết lập thư mục</Button>
          </Alert.Content>
        </Alert>
      )}

      <ErrorBox error={error} />

      <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 sm:mx-0 sm:flex-wrap sm:px-0">
        {count(approve.length, "chờ tôi duyệt", () => go("approvals"))}
        {count(asks.length, "agent hỏi", () => go("tasks", { f: "ask" }))}
        {count(myOpen.length, "việc của tôi", () => go("tasks", { f: "mine" }))}
        {count(late.length, "quá hạn", () => go("tasks", { f: "late" }))}
      </div>

      {loading && !data ? <LoadingList rows={4} /> : (
        <div className="grid items-start gap-8 lg:grid-cols-[minmax(0,1.3fr)_minmax(0,1fr)]">
          <div className="flex min-w-0 flex-col gap-8">
            <Section title="Việc của tôi" count={myOpen.length}><TaskList tasks={myOpen} empty="Bạn không có việc nào đang mở." /></Section>
            {iGave.length > 0 && <Section title="Tôi đã giao" count={iGave.length}><TaskList tasks={iGave} /></Section>}
          </div>
          <div className="flex min-w-0 flex-col gap-8">
            <Section title="Chờ tôi duyệt" count={approve.length} action={approve.length > 0 && <Button size="sm" variant="ghost" onPress={() => go("approvals")}>Mở hàng duyệt</Button>}>
              <TaskList tasks={approve} empty="Không có việc nào chờ bạn duyệt." />
            </Section>
            {asks.length > 0 && <Section title="Agent đang hỏi" count={asks.length}><TaskList tasks={asks} /></Section>}
            {late.length > 0 && <Section title={isAdmin ? "Quá hạn trong công ty" : "Quá hạn trong phòng"} count={late.length}><TaskList tasks={late.slice(0, 8)} /></Section>}
          </div>
        </div>
      )}
    </div>
  );
}
