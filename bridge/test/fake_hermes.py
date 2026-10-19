#!/usr/bin/env python3
"""Hermes CLI giả lập cho kiểm thử: `hermes kanban [--board B] <verb> …`, trạng thái lưu trong FAKE_HERMES_DB.

Hình dạng JSON khớp Hermes 0.22.1 thật (mẫu: bridge/test/fixtures, docs/07):
  create → đối tượng phẳng; list → mảng phẳng không có updated_at; show → {task, latest_summary, comments, events, runs, …}.
`--board` chỉ hợp lệ TRƯỚC động từ; đặt sau động từ báo lỗi cú pháp như bản thật.
Kiểm thử đặt trạng thái bằng set_status(card, status, summary=…, metadata=…, blocked_reason=…) (test_bridge.py).
"""
import json, os, sys, time
DB = os.environ["FAKE_HERMES_DB"]
st = json.load(open(DB)) if os.path.exists(DB) else {"seq": 0, "tasks": {}, "calls": []}
st.setdefault("boards", ["default"])
a = sys.argv[1:]
assert a[0] == "kanban"
rest = a[1:]
board = None
if rest and rest[0] == "--board":
    board, rest = rest[1], rest[2:]
verb, rest = rest[0], rest[1:]
if "--board" in rest:
    sys.stderr.write("usage: hermes [-h] …\nhermes: error: unrecognized arguments: --board\n")
    sys.exit(2)
st["calls"].append(([verb] + rest) if not board else ["--board", board, verb] + rest)
if verb == "boards":                          # `kanban boards create <slug> [--name N]` (A2)
    if rest[0] == "create" and rest[1] not in st["boards"]:
        st["boards"].append(rest[1])
    json.dump(st, open(DB, "w"), ensure_ascii=False)
    sys.exit(0)
if board and board not in st["boards"]:       # Hermes không tự tạo board
    sys.stderr.write(f"kanban: board '{board}' does not exist. Create it with `hermes kanban boards create {board}`.\n")
    sys.exit(1)
def opt(name):
    return rest[rest.index(name) + 1] if name in rest else None
now = int(time.time())

def flat(t):
    keep = ("id", "title", "body", "assignee", "status", "tenant", "created_at", "started_at", "completed_at", "skills")
    return {k: t.get(k) for k in keep}

def show(t):
    events = [{"kind": "created", "payload": {"assignee": t["assignee"]}}]
    if t.get("blocked_reason"):
        events.append({"kind": "blocked", "payload": {"reason": t["blocked_reason"], "kind": "needs_input"}})
    runs = []
    if t["status"] in ("done", "review", "blocked", "running"):
        outcome = {"done": "completed", "review": "completed", "blocked": "blocked", "running": None}[t["status"]]
        runs.append({"id": 1, "profile": t["assignee"], "status": t["status"], "outcome": outcome,
                     "summary": t.get("summary") or t.get("blocked_reason"),
                     "metadata": ({**t["metadata"], "reason": "xong"} if t.get("metadata") else None)})
    latest = t.get("summary") if t["status"] in ("done", "review") else t.get("blocked_reason")
    return {"task": flat(t), "latest_summary": latest, "parents": [], "children": [],
            "comments": t["comments"], "events": events, "runs": runs}

out = None
if verb == "create":
    key = opt("--idempotency-key")
    hit = [t for t in st["tasks"].values() if t["key"] == key and t["status"] != "archived"]
    if hit:
        out = flat(hit[0])
    else:
        st["seq"] += 1
        tid = f"t_{st['seq']:04d}"
        t = st["tasks"][tid] = {"id": tid, "title": rest[0], "status": "ready", "key": key, "board": board,
                                "assignee": opt("--assignee"), "tenant": opt("--tenant"), "body": opt("--body"),
                                "created_at": now, "started_at": None, "completed_at": None,
                                "skills": [rest[i + 1] for i, x in enumerate(rest) if x == "--skill"], "comments": []}
        out = flat(t)
elif verb == "show":
    out = show(st["tasks"][rest[0]])
elif verb == "list":
    out = [flat(t) for t in st["tasks"].values() if t["board"] == board and t["status"] != "archived"]
elif verb == "comment":
    st["tasks"][rest[0]]["comments"].append({"author": opt("--author") or "user", "body": rest[1]})
elif verb == "unblock":
    st["tasks"][rest[0]]["status"] = "ready"
elif verb == "archive":
    st["tasks"][rest[0]]["status"] = "archived"
else:
    sys.stderr.write(f"fake_hermes: động từ chưa hỗ trợ: {verb}\n")
    sys.exit(2)
json.dump(st, open(DB, "w"), ensure_ascii=False)
if "--json" in rest:
    print(json.dumps(out, ensure_ascii=False))
