# 01 · Kiến trúc

## Thành phần và ranh giới tin cậy

    VPS 169                                                   VPS 173
    ┌────────────────────────────────────────────┐            ┌─────────────────────────────────────┐
    │ Caddy  work.enterpriseos.bond              │            │ Hermes gateway (nhiều profile)      │
    │  ├ /api/*  → PostgREST :3000 (schema agent)│◄───JWT─────│  ├ eos-dieu-phoi=Điều phối          │
    │  ├ /mcp*   → MCP :8790                     │ agent_bridge│  ├ eos-van-thu / eos-nhan-su / eos-quan-tri-du-lieu
    │  └ /       → app web (giai đoạn 1)         │            │ Kanban dispatcher (tick 60 s)       │
    │ Postgres 16 (7 schema, 108 bảng)           │            │ eos_kanban_bridge.py  (không LLM)   │
    │  vai trò: mcp_svc, agent_bridge            │            │ plugin eos_bridge → spool.jsonl     │
    └──────────▲─────────────────────────────────┘            └─────────────────────────────────────┘
               │ Bearer eos_…  (mỗi người một mã)
        Agent cá nhân ─────────► Drive cá nhân (qua tài khoản agent Workspace, OAuth refresh token)

## Ba luồng

### 1. Giao việc cho agent hệ thống
1. Việc có `agent_id` (hoặc quy tắc định tuyến) → trigger `agent._dispatch` tạo `agent.cards` và một dòng `agent.outbox(kind=dispatch)`.
2. Cầu nối `outbox_pull` (`FOR UPDATE SKIP LOCKED`) → `hermes kanban create <tiêu đề> --board eos-<công ty> --assignee <profile> --tenant <phòng> --idempotency-key eos-<task>-<n> --body …`.
3. `outbox_ack` ghi `card_id`. Chạy lại không tạo thẻ đôi nhờ khóa chống trùng.

### 2. Agent hỏi lại và báo xong
| Sự kiện Hermes | Hook | Cầu nối gọi | Kết quả trong Postgres |
| --- | --- | --- | --- |
| Dispatcher giao thẻ | `kanban_task_claimed` | `ingest_event(claimed)` | Việc → Đang làm |
| `kanban_block(reason)` | `kanban_task_blocked` | `ingest_event(blocked)` | Việc → Vướng, câu hỏi hiện trên app, `waiting_on_human` |
| Người trả lời trên app | — | outbox `answer` → `hermes kanban comment` + `unblock` | Thẻ chạy lại |
| `kanban_complete(summary, metadata)` | `kanban_task_completed` | `ingest_event(completed)` | Báo cáo + tệp Drive gắn vào việc; việc → Chờ xem |
| Người chấp nhận | — | — | Việc → Xong, KPI tính cho người |
| Người trả lại | — | outbox `dispatch` (làm lại) | Thẻ mới kèm lý do, tối đa 2 lần |

`ingest_event` kiểm tra tóm tắt (10–4000 ký tự) **trước** khi đổi trạng thái thẻ; thiếu → trả `missing_summary`, thẻ giữ nguyên. Sự kiện có `event_key` riêng nên gửi lại không gây tác dụng phụ (`duplicate`, `no_change`). Cứ 10 phút cầu nối đối soát `hermes kanban list` để bù hook bị lỡ.

### 3. Agent cá nhân qua MCP
Mỗi lời gọi công cụ chạy trong **một giao dịch** `SET LOCAL ROLE mcp_svc` + `request.jwt.claims {sub, via}` của chủ mã. Mọi hàm `agent.mcp_*` là `SECURITY DEFINER`, `search_path` cố định, kiểm quyền bằng `core.current_user_id()`. Máy chủ MCP không có đặc quyền thêm so với người dùng.

## Mô hình quyền

- **Người**: vai trò (`core.user_roles`) × quyền (`core.permissions`, có module `kb` và `agent`) × phạm vi (công ty/phòng/mình). Kiểm trong CSDL, không dựa giao diện.
- **Mã MCP của người**: phạm vi `read, write, drive, kb, hr_self`. Không có `delegate`.
- **Mã MCP của agent hệ thống**: có `delegate` (ràng buộc CHECK: chỉ mã gắn `agent_id`). Đọc bằng quyền người phụ trách nhưng chỉ việc có thẻ đang chạy và việc cha/con của nó.
- **Vai trò Postgres**: `mcp_svc` chỉ gọi hàm `agent.mcp_*`; `agent_bridge` chỉ gọi `outbox_pull`, `outbox_ack`, `ingest_event`, `request_confirmation`. `agent_bridge` bị từ chối đọc bảng `mcp_tokens` và gọi hàm `mcp_*` (đã kiểm thử).

## Quyết định thiết kế đáng nhớ

| Quyết định | Lý do |
| --- | --- |
| Postgres là sổ gốc, Kanban chỉ là hàng đợi | Hermes Kanban là một máy, không xác thực, thư mục làm việc tạm bị xóa khi xong; không thể là nơi lưu lịch sử và KPI |
| Cầu nối không dùng LLM | Đường dữ liệu phải tất định, kiểm thử được, chạy lại an toàn |
| Một board mỗi công ty | Board là ranh giới cô lập cứng của Hermes; tenant chỉ lọc mềm |
| Worker agent không ghi Postgres qua MCP | Kết quả đi một đường duy nhất (Kanban → cầu nối → `ingest_event`) để có chỗ kiểm tóm tắt và chống trùng |
| Người luôn là `assignee` | KPI và trách nhiệm không được dồn cho máy |
| Chỉ lưu băm SHA-256 của mã MCP | Lộ cơ sở dữ liệu không lộ mã dùng được |
| Nội dung tệp ở Drive cá nhân | Giữ dữ liệu riêng của từng người; sao lưu máy chủ nhẹ |

## Giới hạn đã biết của Hermes Kanban

Một máy duy nhất; bảng điều khiển và API không xác thực nên chỉ được nghe `127.0.0.1`; thư mục làm việc tạm bị xóa khi thẻ xong (kết quả phải ra Drive trước khi `kanban_complete`); dispatcher chạy trong gateway, nhịp 60 giây — độ trễ nhận việc tối thiểu 1 phút cộng nhịp cầu nối 15 giây.
