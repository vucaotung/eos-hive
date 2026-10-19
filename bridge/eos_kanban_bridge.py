#!/usr/bin/env python3
"""Cầu nối Enterprise OS ↔ Hermes Kanban (chạy trên VPS 173, cạnh Hermes gateway).

Ba việc, lặp mỗi BRIDGE_INTERVAL giây (mặc định 15):
  1. Lấy agent.outbox (việc mới, câu trả lời, xác nhận, hủy) và chạy lệnh `hermes kanban …` tương ứng.
  2. Đọc tệp spool do plugin Hermes `eos_bridge` ghi khi có hook (claimed / blocked / completed),
     đọc chi tiết thẻ bằng `hermes kanban show --json` rồi gửi về agent.ingest_event.
  3. Mỗi RECONCILE_EVERY giây, so `hermes kanban list --json` với trạng thái đã biết để bù sự kiện bị lỡ.

Không dùng LLM. Gọi lại nhiều lần vẫn an toàn: thẻ có idempotency key, sự kiện có event_key riêng.

Biến môi trường:
  EOS_API            https://work.enterpriseos.bond/api   (PostgREST, schema agent mở cho vai trò agent_bridge)
  EOS_BRIDGE_TOKEN   JWT vai trò agent_bridge (mint_jwt.py bridge 90)
  EOS_APP_URL        https://work.enterpriseos.bond
  HERMES_BIN         hermes
  BRIDGE_STATE_DIR   ~/.hermes/eos_bridge   (spool.jsonl, cards.json)
"""
from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
import time
from pathlib import Path

import requests

API = os.environ.get("EOS_API", "http://127.0.0.1:3000").rstrip("/")
TOKEN = os.environ.get("EOS_BRIDGE_TOKEN", "")
APP = os.environ.get("EOS_APP_URL", "https://work.enterpriseos.bond").rstrip("/")
HERMES = shlex.split(os.environ.get("HERMES_BIN", "hermes"))
STATE = Path(os.environ.get("BRIDGE_STATE_DIR", "~/.hermes/eos_bridge")).expanduser()
INTERVAL = int(os.environ.get("BRIDGE_INTERVAL", "15"))
RECONCILE_EVERY = int(os.environ.get("RECONCILE_EVERY", "600"))

# Trạng thái Hermes → sự kiện gửi về Enterprise OS
STATUS_EVENT = {"running": "claimed", "blocked": "blocked", "review": "completed", "done": "completed", "archived": "archived"}


class Bridge:
    def __init__(self) -> None:
        STATE.mkdir(parents=True, exist_ok=True)
        self.cards_file = STATE / "cards.json"
        self.spool = STATE / "spool.jsonl"
        self.cards: dict[str, dict] = json.loads(self.cards_file.read_text()) if self.cards_file.exists() else {}
        self.http = requests.Session()
        self.http.headers.update({"Authorization": f"Bearer {TOKEN}", "Content-Profile": "agent",
                                  "Accept-Profile": "agent", "Content-Type": "application/json"})
        self.last_reconcile = 0.0

    # ---------- Enterprise OS ----------
    def rpc(self, fn: str, **params):
        r = self.http.post(f"{API}/rpc/{fn}", data=json.dumps(params), timeout=20)
        if r.status_code >= 300:
            raise RuntimeError(f"rpc {fn}: {r.status_code} {r.text[:200]}")
        return r.json() if r.text else None

    # ---------- Hermes ----------
    def hermes(self, verb: str, *args: str, board: str | None = None, json_out: bool = False):
        # Hermes 0.22: --board là cờ của `kanban`, phải đứng TRƯỚC động từ (docs/07). `--json` đứng sau động từ.
        cmd = [*HERMES, "kanban", *(["--board", board] if board else []), verb, *args] + (["--json"] if json_out else [])
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if p.returncode != 0:
            raise RuntimeError(f"kanban {verb} exit {p.returncode}: {p.stderr.strip()[:300]}")
        if not json_out:
            return p.stdout
        return json.loads(p.stdout or "null")

    def save(self) -> None:
        tmp = self.cards_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.cards, ensure_ascii=False, indent=1))
        tmp.replace(self.cards_file)

    # ---------- 1. Hộp thư đi ----------
    def card_body(self, o: dict) -> str:
        p = o["payload"]
        lines = [
            f"Việc Enterprise OS: T-{o['task_id']} — {APP}/#/work/tasks/{o['task_id']}",
            f"Hạn: {p.get('due_date') or 'không có'} · Ưu tiên: {p.get('priority')}",
            "",
            "Đọc chi tiết, bình luận và tệp bằng MCP enterprise-os: eos_get_task "
            f"T-{o['task_id']} (eos_guide topic=report để biết cách bàn giao).",
        ]
        if p.get("card_kind") == "synthesis":
            kids = ", ".join(f"{k['id']} ({k['status']})" for k in p.get("children") or [])
            lines += ["", f"TỔNG HỢP. Các việc con đã xong: {kids}.",
                      f"Đọc T-{o['task_id']} (có kết quả từng việc con) rồi viết bản tổng hợp cho người phụ trách duyệt."]
        if p.get("parent_task"):
            lines += ["", f"Đây là việc con của {p['parent_task']}. Kết quả của bạn sẽ được agent cha tổng hợp."]
        if p.get("rework_reason"):
            lines += ["", f"LÀM LẠI. Người giao trả lại với lý do: {p['rework_reason']}",
                      "Đọc kết quả lượt trước ở mục Parent task results."]
        lines += ["", "Kết thúc bằng một trong ba lệnh:",
                  "- kanban_complete: summary (10–4000 ký tự) + metadata {outputs:[{drive_id,name,url}], sources, checks, confidence, residual_risk, next_actions}",
                  "- kanban_block: khi thiếu thông tin; reason = câu hỏi cụ thể + đã làm gì, còn gì",
                  "- Việc L2 (giao cho người khác, gửi ra ngoài…): block và nêu đề xuất; người giao xác nhận trên app.",
                  "Không duyệt, không cấp số, không chốt lương, không xóa."]
        return "\n".join(lines)

    def create_card(self, board: str, args: list[str]) -> dict:
        # A2: Hermes KHÔNG tự tạo board ("board … does not exist"); gặp lỗi đó thì tạo board một lần rồi thử lại.
        try:
            return self.hermes("create", *args, board=board, json_out=True)
        except RuntimeError as e:
            if "does not exist" not in str(e):
                raise
            self.hermes("boards", "create", board, "--name", f"Tổ Ong · {board}")
            return self.hermes("create", *args, board=board, json_out=True)

    def handle_outbox(self, o: dict) -> str | None:
        p = o["payload"]
        if o["kind"] == "dispatch":
            args = [p["title"], "--assignee", p["profile"],
                    "--tenant", p["tenant"], "--idempotency-key", p["idempotency_key"],
                    "--body", self.card_body(o)]
            if p.get("parent_card_id"):
                args += ["--parent", p["parent_card_id"]]
            for s in p.get("skills") or []:
                args += ["--skill", s]
            card = self.create_card(p["board"], args)  # đối tượng phẳng có "id" (A3)
            card_id = str(card["id"])
            self.cards[card_id] = {"board": p["board"], "task_id": o["task_id"], "status": card.get("status", "todo")}
            self.save()
            return card_id
        if o["kind"] == "answer":
            board, card = p.get("board"), p.get("card_id")
            if not card:
                return None
            if "confirmation_id" in p:
                msg = (f"[XAC-NHAN] Người giao {'ĐỒNG Ý' if p['approved'] else 'KHÔNG đồng ý'} đề xuất #{p['confirmation_id']}."
                       + (f" Ghi chú: {p['note']}" if p.get("note") else ""))
            else:
                msg = f"[TRA-LOI] {p.get('by', 'người')}: {p['body']}"
            self.hermes("comment", card, msg, "--author", "eos-bridge", board=board)
            self.hermes("unblock", card, board=board)
            return None
        if o["kind"] == "cancel" and p.get("card_id"):
            self.hermes("archive", p["card_id"], board=p["board"])
        return None

    def drain_outbox(self) -> None:
        for o in self.rpc("outbox_pull", p_limit=20) or []:
            try:
                card_id = self.handle_outbox(o)
                self.rpc("outbox_ack", p_id=o["id"], p_card_id=card_id, p_error=None)
            except Exception as e:  # noqa: BLE001 — ghi lỗi vào outbox, lượt sau thử lại
                print(f"outbox {o['id']}: {e}", file=sys.stderr)
                self.rpc("outbox_ack", p_id=o["id"], p_card_id=None, p_error=str(e))

    # ---------- 2. Sự kiện từ hook ----------
    @staticmethod
    def _last_run(info: dict) -> dict:
        runs = info.get("runs") or []
        return next((r for r in reversed(runs) if r.get("outcome") == "completed"), runs[-1] if runs else {})

    def event_from_card(self, card_id: str, info: dict, hook: str | None) -> tuple[str, dict] | None:
        # `show --json` = {task, latest_summary, comments, events, runs, …}; mẫu thật ở bridge/test/fixtures (docs/07 A5)
        task = info.get("task", info)
        status = task.get("status")
        event = {"kanban_task_claimed": "claimed", "kanban_task_blocked": "blocked",
                 "kanban_task_completed": "completed"}.get(hook or "", STATUS_EVENT.get(status))
        if event is None:
            return None
        payload: dict = {}
        if event == "blocked":
            blocked = [e for e in info.get("events") or [] if e.get("kind") == "blocked"]
            payload["reason"] = ((blocked[-1].get("payload") or {}).get("reason") if blocked else None) or info.get("latest_summary")
        if event == "completed":
            run = self._last_run(info)
            meta = run.get("metadata") or {}
            payload = {"summary": info.get("latest_summary") or run.get("summary") or task.get("result"),
                       **{k: meta.get(k) for k in ("outputs", "sources", "checks", "confidence", "residual_risk", "next_actions") if meta.get(k) is not None}}
        return event, payload

    def push(self, card_id: str, hook: str | None, stamp: str) -> None:
        known = self.cards.get(card_id)
        if not known:
            return  # thẻ không do cầu nối tạo (thẻ nội bộ của agent)
        info = self.hermes("show", card_id, board=known["board"], json_out=True) or {}
        ev = self.event_from_card(card_id, info, hook)
        if not ev:
            return
        event, payload = ev
        key = f"{known['board']}:{card_id}:{event}:{stamp}"
        res = self.rpc("ingest_event", p_board=known["board"], p_card=card_id, p_event=event, p_event_key=key, p_payload=payload)
        known["status"] = info.get("task", info).get("status", known.get("status"))
        self.save()
        print(f"{card_id} {event} → {res}")

    def drain_spool(self) -> None:
        if not self.spool.exists() or self.spool.stat().st_size == 0:
            return
        work = self.spool.with_suffix(".work")
        self.spool.replace(work)  # plugin ghi tiếp vào tệp mới
        pending = []
        for line in work.read_text().splitlines():
            try:
                h = json.loads(line)
                self.push(str(h["task_id"]), h.get("hook"), h.get("ts", str(time.time())))
            except Exception as e:  # noqa: BLE001
                print(f"spool: {e}", file=sys.stderr)
                pending.append(line)
        work.unlink()
        if pending:  # giữ lại để thử lượt sau
            with self.spool.open("a") as f:
                f.write("\n".join(pending) + "\n")

    # ---------- 3. Đối soát ----------
    def reconcile(self) -> None:
        boards = {c["board"] for c in self.cards.values() if c.get("status") not in ("done", "archived")}
        for board in boards:
            for info in self.hermes("list", board=board, json_out=True) or []:
                card_id = str(info.get("id"))
                known = self.cards.get(card_id)
                if not known or info.get("status") == known.get("status"):
                    continue
                if info.get("status") in STATUS_EVENT:
                    # mốc = trạng thái mới; nếu hook đã gửi cùng sự kiện, ingest_event vẫn nhận lần nữa nhưng việc đã đúng trạng thái
                    # `list --json` không có updated_at: dùng mốc thời gian có thật của thẻ làm dấu
                    stamp = info.get("completed_at") or info.get("started_at") or info.get("created_at") or ""
                    self.push(card_id, None, f"reconcile-{info.get('status')}-{stamp}")
        self.last_reconcile = time.time()

    def run_once(self) -> None:
        self.drain_outbox()
        self.drain_spool()
        if time.time() - self.last_reconcile >= RECONCILE_EVERY:
            self.reconcile()


if __name__ == "__main__":
    if not TOKEN:
        sys.exit("Thiếu EOS_BRIDGE_TOKEN")
    b = Bridge()
    once = "--once" in sys.argv
    while True:
        try:
            b.run_once()
        except Exception as e:  # noqa: BLE001 — mạng chập chờn: chờ lượt sau
            print(f"lượt lỗi: {e}", file=sys.stderr)
        if once:
            break
        time.sleep(INTERVAL)
