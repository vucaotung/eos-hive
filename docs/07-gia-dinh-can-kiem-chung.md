# 07 · Các giả định cần kiểm chứng trên máy thật

v0.0.0 được kiểm thử với **Hermes giả lập** (`bridge/test/fake_hermes.py`). Mọi dòng dưới đây là điều mã đang *giả định* về Hermes, Google hoặc môi trường. Chưa dòng nào được xác nhận. **Phải kiểm chứng trước khi bật cầu nối trên VPS 173**, ghi kết quả vào cột cuối và commit.

Nguồn tham chiếu khi viết: tài liệu Hermes Kanban (hermes-agent.nousresearch.com/docs/user-guide/features/kanban, đọc 2026-10-19). Tài liệu có thể khác bản cài thật.

## 1. Bảng giả định

Đã kiểm trên **Hermes Agent v0.22.1+85.g3046358.dirty (2026.9.24), kiểm 2026-10-19**. A10 (kỹ năng Hermes chưa viết) và A18 (ghi Drive thật, Pha 4) chưa kiểm (xem cột cuối).


| # | Giả định | Dùng ở | Cách kiểm | Trạng thái |
| --- | --- | --- | --- | --- |
| A1 | `hermes kanban create <tiêu đề> --board B --assignee P --tenant T --idempotency-key K --body X [--parent ID] [--skill S]… --json` chạy được và chấp nhận đủ cờ | `handle_outbox` | `hermes kanban create --help` | ✔ đủ cờ. **`--board` là cờ cấp `kanban`, đứng TRƯỚC động từ** (`kanban --board B create …`); đặt sau động từ báo lỗi cú pháp. Đã sửa cầu nối. |
| A2 | Có thể tạo thẻ vào board chưa tồn tại (hoặc board tự tạo); nếu không, cần lệnh tạo board trước | `handle_outbox` | thử với board mới `eos-smoke` | ✘ Hermes **không** tự tạo board (`board … does not exist`). Phải `kanban boards create <slug>`. Đã sửa: cầu nối tự tạo board khi gặp lỗi đó rồi thử lại. |
| A3 | `create --json` trả đối tượng có `id` hoặc `task_id` (có thể bọc trong `{"task":…}`) | `hermes()` bóc `task` | chạy và xem | ✔ `create --json` trả đối tượng **phẳng** có `id` (không bọc `task`). |
| A4 | Cùng `--idempotency-key` hai lần → không tạo thẻ đôi (trả thẻ cũ) | chống trùng | chạy hai lần | ✔ cùng `--idempotency-key` trả lại thẻ cũ, không tạo thẻ đôi. |
| A5 | `hermes kanban show <id> --board B --json` có: `status`, `summary` (hoặc `result`), `metadata` (hoặc `result_metadata`) chứa `outputs/sources/checks/confidence/residual_risk/next_actions`, lý do chặn (`blocked_reason`/`block_reason`/bình luận cuối), `comments[].body` | `event_from_card` | tạo thẻ, cho worker `kanban_block` rồi `kanban_complete`, chụp JSON | ✘ một phần. `show --json` = `{task, latest_summary, parents, children, comments, events, runs}`. Không có `summary`/`metadata`/`blocked_reason` ở cấp 1. Thật: `task.status`; tóm tắt = `latest_summary` (và `runs[-1].summary`); metadata = `runs[-1].metadata`; lý do chặn = `events[kind=blocked].payload.reason` (và `latest_summary`); bình luận = `comments[].body`. Đã sửa `event_from_card` + mẫu thật trong `bridge/test/fixtures/`. |
| A6 | `hermes kanban list --board B --json` trả mảng có `id`, `status`, `updated_at` | `reconcile` | chạy | ✘ một phần. `list --json` là mảng phẳng có `id,status,created_at,started_at,completed_at`, **không có `updated_at`**; thẻ `archived` bị ẩn (dùng `--archived`). Đã sửa dấu đối soát. |
| A7 | Giá trị `status` đúng bộ: triage, todo, ready, running, blocked, review, done, archived | `STATUS_EVENT` | từ A5/A6 | ✔ bộ trạng thái thật: archived, blocked, done, ready, review, running, scheduled, todo, triage (thêm `scheduled`). |
| A8 | `kanban comment <id> "<msg>" --board B` và `kanban unblock <id> --board B` đúng thứ tự đối số | outbox `answer` | `--help` + thử | ✔ `kanban --board B comment <id> <text> [--author A]`; `kanban --board B unblock <id>`. Thẻ chạy lại sau unblock. |
| A9 | `kanban archive <id> --board B` | outbox `cancel` | thử | ✔ `kanban --board B archive <id>`. |
| A10 | Kỹ năng Hermes (`lap-ke-hoach`, `nd30-van-thu`, `hr-cham-cong`, `kb-tra-cuu`) **chưa được viết**; `setup_agents.sql` để cột `skills` trống cho khỏi `--skill` lỗi. Khi viết xong: `UPDATE agent.agents SET skills='{…}'` | `setup_agents.sql` | `hermes skills list`; thử `create --skill` với tên có thật | ☐ |
| A11 | Plugin Hermes: gói có hàm `register(ctx)`; `ctx.register_hook(name, fn)` nhận hook `kanban_task_claimed`, `kanban_task_blocked`, `kanban_task_completed`; hàm gọi với kwargs `task_id`, `profile_name`, (có thể) `board` | `hermes_plugin/eos_bridge` | đọc mã Hermes cài trên máy; thêm `print(kwargs)` tạm | ✔ hook `kanban_task_claimed/blocked/completed`; kwargs `task_id, board, assignee, run_id, profile_name`; `completed` thêm `summary`, `blocked` thêm `reason` (đọc mã `hermes_cli/plugins.py`, `kanban_db.py`). Chưa chạy plugin thật (bước cài). |
| A12 | Thư mục cài plugin và cách bật theo profile (`hermes plugins …`) | docs/03 §3.4 | `hermes plugins --help` | ✘ một phần. Plugin thật cần `plugin.yaml` (name, version, description, provides_hooks); đã thêm. Thư mục: `~/.hermes/plugins/<tên>`; bật: `hermes plugins enable <tên>`. Chờ kiểm lúc cài. |
| A13 | Hook `claimed` chạy ở tiến trình dispatcher, `blocked/completed` ở tiến trình worker; cả hai ghi được `~/.hermes/eos_bridge/spool.jsonl` (cùng người dùng, quyền ghi) | plugin | chạy thẻ thật, xem spool | ✘ một phần (đã chạy thẻ thật, đọc `spool.jsonl`): `blocked` và `completed` do **worker** ghi đúng (profile `eos-*`, `board=eos-smoke`). `claimed` **không** ghi: nó bắn trong **dispatcher** của gateway (profile `default`), nơi plugin chưa bật, và ta không bật plugin trên `default`. Bù bằng đối soát: cầu nối thấy `running` thì phát `claimed`; đặt `RECONCILE_EVERY=60` (mặc định 600). Plugin có hiệu lực ngay sau `plugins enable`, không cần restart gateway. |
| A14 | `kanban_complete(summary, metadata)` lưu `metadata` nguyên dạng JSON và `show --json` trả lại | hợp đồng báo cáo | A5 | ✔ `kanban_complete(summary, metadata)` lưu nguyên 6 khóa tại `runs[-1].metadata` (kèm `reason`, `worker_session_id`). |
| A15 | Dispatcher của gateway `--multiplex` chạy thẻ cho **mọi** profile `eos-*` (không chỉ profile mặc định) | kiến trúc | thẻ thử cho `eos-quan-tri-du-lieu` | ✔ dispatcher của gateway (`gateway run`, KHÔNG có `--multiplex`) nhận thẻ của profile `eos-*` sau ~30 s: ready → running → done. |
| A16 | Worker nối được MCP `enterprise-os` bằng cấu hình `mcp_servers` (HTTP + header Bearer) ở profile | worker đọc việc | cấu hình và gọi `eos_get_task` | ✔ cấu hình `mcp_servers.enterprise-os` (`url`, `headers.Authorization: Bearer ${EOS_MCP_TOKEN}`) trong `config.yaml` của profile; Hermes tự nội suy `${VAR}` từ `.env` của profile. `hermes -p P mcp test enterprise-os` → kết nối, thấy 3 công cụ worker (`eos_guide`, `eos_get_task`, `eos_delegate`). Worker gọi `eos_guide topic=agent` thành công. Lưu ý: công cụ MCP là *deferred*, lần đầu model có thể gọi sai tên rồi tự tìm lại. |
| A17 | PostgREST với `db-schemas="agent"` nhận `POST /rpc/<fn>` kèm `Content-Profile: agent` | `Bridge.rpc` | `curl` | ✔ `POST https://work.enterpriseos.bond/api/rpc/outbox_pull` với `Content-Profile: agent` + JWT `agent_bridge` từ vps173 → 200; không JWT → 401; từ IP khác vps173 → 403 (Caddy). PostgREST nghe cổng 3200 (3000 là Ever Teams). |
| A18 | Refresh token Google cấp phạm vi `drive` đầy đủ; tài khoản agent là Editor trên thư mục người dùng | `drive.mjs` | `eos_save_to_drive` thật 1 tệp | ☐ |
| A19 | Hermes chạy `--multiplex`: tên profile `eos-van-thu`… hợp lệ, không trùng | triển khai | `hermes profile list` | ✔ `hermes profile create eos-*` hợp lệ; `profile list` thấy cả 4, không trùng. |
| A20 | Độ trễ nhận việc chấp nhận được: dispatcher 60 s + cầu nối 15 s | UX | đo | ✔ sơ bộ: thẻ `ready` → `running` sau 15–30 s; vòng đời thẻ thử ~1–2 phút. |

## 2. Cách chụp mẫu thật (fixtures)

Trên VPS 173, với board thử, **không dùng board công ty thật**:

    mkdir -p /tmp/eos-fx && cd /tmp/eos-fx
    hermes kanban create "EOS smoke" --board eos-smoke --assignee eos-quan-tri-du-lieu --tenant TEST --idempotency-key smoke-1 --body "Hãy gọi kanban_block hỏi 'ứng dụng cho dự án nào?'" --json | tee create.json
    # đợi worker chạy; trả lời bằng comment + unblock; cho kanban_complete với summary ≥ 10 ký tự
    hermes kanban show <id> --board eos-smoke --json | tee show-blocked.json     # lúc đang blocked
    hermes kanban show <id> --board eos-smoke --json | tee show-done.json        # sau khi xong
    hermes kanban list --board eos-smoke --json | tee list.json

Đưa 4 tệp vào `bridge/test/fixtures/` (đã xóa nội dung nhạy cảm), rồi viết `bridge/test/test_fixtures.py` đọc chúng qua `event_from_card` và khẳng định đầu ra. Từ đó cầu nối được bảo vệ bằng dữ liệu thật.

## 3. Quy trình sửa khi giả định sai

1. Ghi sự thật vào cột "Trạng thái" (✔ hoặc ✘ + mô tả thực tế) và số phiên bản `hermes --version`.
2. Sửa **chỉ** `bridge/eos_kanban_bridge.py` và/hoặc plugin; không sửa hàm Postgres chỉ vì dạng JSON của Hermes (Postgres là hợp đồng ổn định).
3. Cập nhật `fake_hermes.py` cho khớp thực tế rồi chạy lại `make test-bridge`.
4. Ghi `CHANGELOG.md` mục *Sửa* và bản sửa vào nhánh `fix/bridge-real-hermes`.

## 4. Cách thoát hiểm nếu Hermes Kanban không dùng được

Cầu nối và Hermes là *một đường* tới agent. Nếu A1–A9 không thể thỏa, phương án dự phòng: cầu nối gọi trực tiếp API gateway của profile (`api_server`, `127.0.0.1:8646`) với prompt có cấu trúc, và nhận kết quả bằng chính cuộc gọi đó. Giữ nguyên hộp thư đi và `ingest_event`; chỉ thay hai hàm `handle_outbox` / `push`. Không đổi phía Postgres.
