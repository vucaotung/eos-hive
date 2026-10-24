"""Bảo vệ cầu nối bằng DỮ LIỆU THẬT chụp từ Hermes 0.22.1 (bridge/test/fixtures, docs/07 A3–A9, A14).
Không cần Postgres hay Hermes: nạp JSON thật vào Bridge.event_from_card và kiểm cách dựng lệnh `kanban`."""
import json, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
os.environ.setdefault("BRIDGE_STATE_DIR", tempfile.mkdtemp())
import eos_kanban_bridge as br

FX = os.path.join(os.path.dirname(__file__), "fixtures")
def load(name): return json.load(open(os.path.join(FX, name), encoding="utf-8"))
b = br.Bridge()
ok = 0
def step(name):
    global ok; ok += 1; print("  ✓", name)

# A5: lý do chặn nằm ở events[kind=blocked].payload.reason (và latest_summary), không có blocked_reason cấp 1
ev, payload = b.event_from_card("t_d69159f5", load("show-blocked.json"), "kanban_task_blocked")
assert ev == "blocked" and payload == {"reason": "Ứng dụng cho dự án nào?"}, (ev, payload)
ev, _ = b.event_from_card("t_d69159f5", load("show-blocked.json"), None)
assert ev == "blocked"                       # suy từ task.status khi không có hook (đối soát)
step("thẻ thật đang Vướng → sự kiện blocked với đúng câu hỏi")

# A14: metadata có cấu trúc lưu nguyên ở runs[-1].metadata; summary ở latest_summary
ev, p = b.event_from_card("t_d69159f5", load("show-done2.json"), "kanban_task_completed")
assert ev == "completed"
assert p["summary"] == "Đã nhận câu trả lời và hoàn tất kiểm thử cầu nối bước 2", p
assert p["outputs"] == [{"name": "bao-cao-thu", "url": "https://example.invalid/x"}]
assert p["sources"] == ["nguon-1"] and p["checks"] == ["da-doi-chieu"] and p["confidence"] == 0.8
assert p["residual_risk"] == "thap" and p["next_actions"] == ["khong"], p
assert "reason" not in p and "worker_session_id" not in p     # chỉ đưa 6 khóa của hợp đồng báo cáo
step("thẻ thật đã Xong kèm metadata → sự kiện completed đủ 6 khóa của hợp đồng")

# Thẻ xong nhưng worker không nộp metadata có cấu trúc: chỉ có summary
ev, p = b.event_from_card("t_e7e3c534", load("show-done.json"), None)
assert ev == "completed" and p == {"summary": "Kiểm thử cầu nối: hoàn tất bước 1"}, p
step("thẻ thật xong không có metadata cấu trúc → chỉ summary, không lỗi")

# A6: list --json là mảng phẳng không có updated_at; khóa mốc thời gian có thật
rows = load("list.json") + load("list-archived.json")
assert rows and all("updated_at" not in r and "created_at" in r for r in rows)
assert {r["status"] for r in rows} <= {"archived", "blocked", "done", "ready", "review", "running", "scheduled", "todo", "triage"}
step("list --json: mảng phẳng, không updated_at, trạng thái thuộc bộ đã kiểm chứng")

# A3: create --json là đối tượng phẳng có id
c = load("create1.json")
assert c["id"].startswith("t_") and c["status"] == "ready" and "task" not in c
step("create --json: đối tượng phẳng có id")

# --board phải đứng TRƯỚC động từ (Hermes 0.22.1)
calls = []
class P:                                      # thay subprocess.run để bắt dòng lệnh
    returncode, stdout, stderr = 0, "[]", ""
real = br.subprocess.run
br.subprocess.run = lambda cmd, **kw: (calls.append(cmd), P())[1]
try:
    b.hermes("list", board="eos-vlx", json_out=True)
    b.hermes("unblock", "t_1", board="eos-vlx")
    b.hermes("comment", "t_1", "xin chào", "--author", "eos-bridge", board="eos-vlx")
finally:
    br.subprocess.run = real
k = lambda c: c[c.index("kanban"):]
assert k(calls[0]) == ["kanban", "--board", "eos-vlx", "list", "--json"], calls[0]
assert k(calls[1]) == ["kanban", "--board", "eos-vlx", "unblock", "t_1"], calls[1]
assert k(calls[2])[:4] == ["kanban", "--board", "eos-vlx", "comment"], calls[2]
step("lệnh kanban: --board đứng trước động từ")
# `claimed` ngầm: hook claimed không tới (dispatcher chạy ở profile default) -> blocked/completed vẫn đi qua Đang làm một lần
rpcs = []
b.cards = {"t_d69159f5": {"board": "eos-smoke", "task_id": 1, "status": "ready"}}
b.save = lambda: None
b.rpc = lambda fn, **kw: (rpcs.append((fn, kw["p_event"], kw["p_event_key"])), "ok")[1]
b.hermes = lambda verb, *a, **kw: load("show-blocked.json")
b.push("t_d69159f5", "kanban_task_blocked", "100")
b.hermes = lambda verb, *a, **kw: load("show-done2.json")
b.push("t_d69159f5", "kanban_task_completed", "200")
assert [r[1] for r in rpcs] == ["claimed", "blocked", "completed"], rpcs
assert rpcs[0][2] == "eos-smoke:t_d69159f5:claimed:implied", rpcs
step("blocked/completed không có claimed trước -> phát claimed ngầm đúng một lần")
# Agent chạy lại sau khi người trả lời: khóa sự kiện của lượt mới KHÁC khóa lượt trước (trước đây trùng → bị bỏ, việc đứng yên)
b2 = br.Bridge(); b2.save = lambda: None
b2.cards = {"t_x1": {"board": "eos-smoke", "task_id": 1, "status": "blocked", "claimed": True}}
keys = []
b2.rpc = lambda fn, **kw: (keys.append(kw.get("p_event_key")), "ok")[1] if fn == "ingest_event" else None
b2.hermes = lambda verb, *a, **kw: load("show-blocked.json")
b2.push("t_x1", None, "reconcile-blocked-T0")
b2.handle_outbox({"id": 1, "kind": "answer", "task_id": 1, "payload": {"board": "eos-smoke", "card_id": "t_x1", "body": "ok", "by": "user:1"}})
assert b2.cards["t_x1"].get("epoch") == 1 and b2.cards["t_x1"]["claimed"] is False
b2.push("t_x1", None, "reconcile-blocked-T0")
ev = [k for k in keys if k and ":blocked:" in k]
assert len(ev) == 2 and ev[0] != ev[1] and ev[1].endswith(":e1"), ev
step("sau câu trả lời, sự kiện của lượt chạy lại có khóa riêng (epoch)")
print(f"fixtures: {ok} bước đạt")
