"""Plugin Hermes `eos_bridge`: ghi sự kiện Kanban vào spool để eos_kanban_bridge gửi về Enterprise OS.

Cài: chép thư mục eos_bridge vào thư mục plugin của Hermes (xem `hermes plugins` trên bản đang chạy) và bật plugin
cho các profile agent Enterprise OS. Hook chạy trong tiến trình dispatcher (claimed) và worker (blocked, completed),
nên plugin chỉ ghi một dòng JSON ra đĩa, không gọi mạng, không làm chậm worker.
"""
import json
import os
import time
from pathlib import Path

SPOOL = Path(os.environ.get("BRIDGE_STATE_DIR", "~/.hermes/eos_bridge")).expanduser() / "spool.jsonl"


def _write(hook, task_id=None, profile_name=None, **kw):
    if not task_id:
        return
    SPOOL.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps({"hook": hook, "task_id": str(task_id), "profile": profile_name,
                       "board": kw.get("board"), "ts": f"{time.time():.3f}"}, ensure_ascii=False)
    with SPOOL.open("a", encoding="utf-8") as f:   # một dòng < 4 KB: ghi nối tiếp an toàn giữa nhiều tiến trình
        f.write(line + "\n")


def register(ctx):
    for hook in ("kanban_task_claimed", "kanban_task_blocked", "kanban_task_completed"):
        ctx.register_hook(hook, lambda task_id=None, profile_name=None, _h=hook, **kw: _write(_h, task_id, profile_name, **kw))
