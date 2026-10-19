"""Kiểm thử cầu nối với PostgREST thật + Postgres thật + Hermes CLI giả lập."""
import json, os, subprocess, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "hermes_plugin"))
import eos_kanban_bridge as br
import eos_bridge as plugin

DB = os.environ["FAKE_HERMES_DB"]
def hermes_state(): return json.load(open(DB))
def set_status(card, status, **extra):
    st = hermes_state(); st["tasks"][card].update(status=status, **extra); json.dump(st, open(DB, "w"))
def sql(q):
    dsn = os.environ.get("EOS_TEST_DSN")  # ví dụ postgres://user:pw@127.0.0.1:5432/eos_test
    cmd = ["psql", dsn, "-X", "-At", "-c", q] if dsn else ["su", "postgres", "-c", f"psql -X -At -d eos4 -c \"{q}\""]
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()

b = br.Bridge(); b.last_reconcile = 9e18   # tắt đối soát cho tới bước cuối
ok = 0
def step(name): 
    global ok; ok += 1; print("  ✓", name)

b.run_once()
st = hermes_state(); card = next(iter(st["tasks"]))
t = st["tasks"][card]
assert t["board"] == "eos-vlx" and t["assignee"] == "eos-thu-thu" and t["tenant"] == "PC", t
assert t["skills"] == ["kb-tra-cuu", "phap-che"] and t["key"] == "eos-7001-1", t
assert "eos_get_task T-7001" in t["body"]
assert sql("select card_id||'|'||status from agent.cards where task_id=7001") == f"{card}|todo"
step("việc giao cho agent → thẻ Kanban đúng board, profile, tenant, skill, khóa chống trùng")

b.run_once()
assert len(hermes_state()["tasks"]) == 1
step("chạy lại không tạo thẻ đôi")

set_status(card, "running"); plugin._write("kanban_task_claimed", card, "eos-thu-thu")
b.run_once()
assert sql("select status from work.tasks where id=7001") == "in_progress"
step("hook claimed → việc Đang làm")

set_status(card, "blocked", blocked_reason="Cần biết áp dụng cho dự án nào: KDC Thành Lập hay Đại Bái?")
plugin._write("kanban_task_blocked", card, "eos-thu-thu")
b.run_once()
assert sql("select status||'|'||waiting_on_human from work.tasks where id=7001") == "blocked|true"
assert "Đại Bái" in sql("select body from work.comments where task_id=7001 and kind='question'")
step("hook blocked → việc Vướng, câu hỏi hiện trên app")

sql("insert into work.comments (task_id,user_id,actor,kind,body) values (7001,'eeeeeeee-1111-0000-0000-000000000001','user:minh','answer','Dự án Đại Bái')")
b.run_once()
t = hermes_state()["tasks"][card]
assert t["status"] == "ready" and "Dự án Đại Bái" in t["comments"][-1]["body"], t
step("người trả lời trên app → bình luận + unblock trên Kanban")

set_status(card, "done", summary="Tóm tắt 6 điểm mới của NQ 29 áp dụng cho dự án Đại Bái.",
           metadata={"outputs": [{"drive_id": "1Qq", "name": "T-7001 - Tom tat NQ29.md", "url": "https://drive.google.com/file/d/1Qq"}],
                     "confidence": "cao", "checks": {"kiem-tra": "dat"}})
plugin._write("kanban_task_completed", card, "eos-thu-thu")
b.run_once()
assert sql("select status from work.tasks where id=7001") == "in_review"
assert sql("select count(*)||'|'||max(confidence) from agent.reports where task_id=7001") == "1|cao"
assert sql("select count(*) from core.attachments where entity_id='7001'") == "1"
step("hook completed → Chờ xem, báo cáo + tệp Drive gắn vào việc")

b.last_reconcile = 0; b.cards[card]["status"] = "running"   # giả lập hook bị lỡ
b.run_once()
assert sql("select count(*) from agent.reports where task_id=7001") == "1"
step("đối soát không tạo báo cáo trùng")
print(f"bridge: {ok} bước đạt")
