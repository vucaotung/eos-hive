#!/usr/bin/env python3
"""Hermes CLI giả lập cho kiểm thử: `hermes kanban <verb> …`, trạng thái lưu trong FAKE_HERMES_DB."""
import json, os, sys
DB = os.environ["FAKE_HERMES_DB"]
st = json.load(open(DB)) if os.path.exists(DB) else {"seq": 0, "tasks": {}, "calls": []}
a = sys.argv[1:]
assert a[0] == "kanban"
verb, rest = a[1], a[2:]
st["calls"].append([verb] + rest)
def opt(name):
    return rest[rest.index(name) + 1] if name in rest else None
out = None
if verb == "create":
    key = opt("--idempotency-key")
    hit = [t for t in st["tasks"].values() if t["key"] == key]
    if hit:
        out = hit[0]
    else:
        st["seq"] += 1
        tid = f"t_{st['seq']:04d}"
        out = st["tasks"][tid] = {"id": tid, "title": rest[0], "status": "todo", "key": key, "board": opt("--board"),
                                   "assignee": opt("--assignee"), "tenant": opt("--tenant"), "body": opt("--body"),
                                   "skills": [rest[i + 1] for i, x in enumerate(rest) if x == "--skill"], "comments": []}
elif verb == "show":
    out = st["tasks"][rest[0]]
elif verb == "list":
    out = [t for t in st["tasks"].values() if t["board"] == opt("--board")]
elif verb == "comment":
    st["tasks"][rest[0]]["comments"].append({"body": rest[1]})
elif verb == "unblock":
    st["tasks"][rest[0]]["status"] = "ready"
elif verb == "archive":
    st["tasks"][rest[0]]["status"] = "archived"
json.dump(st, open(DB, "w"), ensure_ascii=False)
if "--json" in rest:
    print(json.dumps(out, ensure_ascii=False))
