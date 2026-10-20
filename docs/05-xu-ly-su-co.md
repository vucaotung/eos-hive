# 05 · Xử lý sự cố (troubleshooting)

Tìm theo triệu chứng. Mỗi dòng: **nguyên nhân thường gặp → cách xử lý**. Lệnh chạy trên máy ghi ở cột đầu. Các lỗi đánh dấu ✔ đã gặp thật khi xây v0.0.0.

## A. Máy chủ MCP (VPS 169)

| Triệu chứng | Nguyên nhân | Xử lý |
| --- | --- | --- |
| Agent báo 401 | Mã sai định dạng (phải `eos_` + 48 hex), hết hạn, đã thu hồi | `select prefix, expires_at, revoked_at from agent.mcp_tokens where user_id='…'`; cấp mã mới |
| 503 "Máy chủ tạm lỗi" ngay lúc xác thực | Không kết nối được Postgres (sai `DATABASE_URL`, mật khẩu, `pg_hba.conf`) ✔ | `journalctl -u eos-mcp -n 50` xem dòng `verify`; thử `psql "$DATABASE_URL" -c 'select 1'` |
| 429 | Vượt `MCP_RATE_PER_MIN` (120/phút/mã) | Agent lặp vòng; sửa agent. Không nâng giới hạn để che lỗi |
| "Mã MCP này không có phạm vi X" | Mã thiếu `read/write/drive/kb/hr_self` | Cấp mã mới đủ phạm vi (không sửa được mã cũ) |
| "Không có quyền" | Đúng thiết kế: việc ngoài quyền người dùng | Kiểm vai trò/phạm vi người đó; **đừng** nới quyền chỉ để agent chạy được |
| `eos_save_to_drive` lỗi 404/403 | Tài khoản agent Workspace chưa là Người chỉnh sửa thư mục; hoặc refresh token cấp phạm vi `drive.file` | Chia sẻ lại thư mục; cấp lại token với phạm vi `drive` đầy đủ |
| `drive.folder` ≠ ok trong `eos_whoami` | Người dùng chưa khai link thư mục, hoặc link sai | Khai lại trong hồ sơ; tên thư mục theo mẫu `DEO - <công ty> - <mã phòng> - <Họ tên>` |
| `eos_attach_drive_file` "tệp không nằm trong thư mục" | Đi quá 6 cấp cha, hoặc tệp ở Drive dùng chung khác | Chuyển tệp vào thư mục người dùng; không nâng giới hạn 6 cấp |
| Lưu tệp "quá lớn" | > 10 MB | Tệp lớn: người tự tải lên Drive rồi `eos_attach_drive_file` |
| Caddy 502 trên `/mcp` | MCP chưa chạy hoặc cổng khác | `systemctl status eos-mcp`; `curl 127.0.0.1:8790/healthz` |
| Caddy 404 trên `/healthz` từ ngoài | Đúng: Caddy chỉ chuyển `/mcp*` | Kiểm trong VPS |

## B. Cầu nối và Hermes (VPS 173)

| Triệu chứng | Nguyên nhân | Xử lý |
| --- | --- | --- |
| Việc giao agent nhưng không có thẻ | Cầu nối không chạy; hoặc `agent.company_settings.enabled=false`; hoặc agent chưa bật cho công ty | `systemctl --user status eos-kanban-bridge`; `select * from agent.outbox order by id desc limit 5` (cột `error`) |
| `outbox.error` có "JWT expired" / PGRST301 ✔ | JWT `agent_bridge` hết hạn | Cấp JWT mới (`docs/03` §3.2), cập nhật `.env`, restart |
| `outbox.error` "exit 1: … unknown option" | Dòng lệnh `hermes kanban` đổi giữa các bản Hermes | `docs/07` — kiểm lại cờ; sửa `handle_outbox` |
| `outbox.error` "không có skill X" / `--skill` | Kỹ năng ghi trong `agent.agents.skills` chưa tồn tại trong Hermes | Tạo skill đó trong profile, hoặc bỏ khỏi danh sách (`docs/07` A10) |
| Lỗi `KeyError`/`NoneType` ở `event_from_card` | Dạng JSON `kanban show --json` khác giả định | Chụp mẫu thật (`docs/07` §2), sửa ánh xạ khóa |
| Thẻ chạy xong mà việc không đổi | Hook không bắn (plugin chưa bật cho profile) hoặc spool không ghi | `ls -l ~/.hermes/eos_bridge/spool.jsonl`; sau ≤ 10 phút đối soát sẽ bù — nếu không, plugin chưa chạy |
| Mỗi lượt đều in `missing_summary` | Agent gọi `kanban_complete` với tóm tắt < 10 ký tự | Đúng thiết kế; sửa prompt/skill của agent (nhắc hợp đồng báo cáo, `eos_guide topic=agent`) |
| Có hai thẻ cho một việc | Hiếm: khóa chống trùng khác nhau (`eos-<task>-<lượt>`) do làm lại | Bình thường nếu một thẻ là lượt làm lại; thẻ cũ phải ở `archived` |
| Nhật ký cầu nối lặp `ingest_event: 400 … 23514` (check_violation), việc không sang Chờ xem | Báo cáo agent vi phạm ràng buộc (trước 0.0.2: `confidence` ngoài `cao/trung_binh/thap`, ví dụ `1` hoặc `high`) | Từ 0.0.2 trigger `reports_norm_confidence` tự chuẩn hóa. Nếu vẫn còn lỗi khác: đọc `details` đầy đủ (log bị cắt 200 ký tự), sửa dữ liệu nguồn hoặc hàm; cầu nối tự thử lại mỗi 15 s nên không cần chạy tay |
| `journalctl --user -u eos-kanban-bridge` trống dù cầu nối đang xử lý | Python đệm stdout khi chạy dưới systemd | Unit phải có `Environment=PYTHONUNBUFFERED=1` (có từ 0.0.1) |
| Hủy việc mà thẻ Kanban vẫn chạy | Trước 0.0.2 không có gì phát lệnh `cancel` | Từ 0.0.2 trigger `tasks_cancel` phát `agent.outbox` kind=`cancel`; cầu nối archive thẻ. Worker đang chạy có thể kết thúc nhưng sự kiện của nó bị bỏ qua (`task_closed`) |
| Thẻ ở `running` mãi | Worker chết giữa chừng; dispatcher tick 60 s | `hermes kanban show <id>`; archive thẻ + tạo lại việc; xem log `hermes-gateway` |
| Dispatcher không nhận thẻ | Gateway không chạy profile đó (`--multiplex` thiếu), hoặc profile sai tên | `hermes gateway status`; tên profile phải khớp `agent.agents.hermes_profile` |
| Trả lời trên app mà agent không chạy tiếp | outbox `answer` lỗi, hoặc thẻ không ở `blocked` | Xem `agent.outbox`; `hermes kanban --board eos-<slug> unblock <id>` thủ công |
| Cầu nối chạy lại tạo thẻ trùng | **Không nên xảy ra** (khóa chống trùng) | Nếu xảy ra, báo lỗi nghiêm trọng; đừng xóa — archive |
| `systemctl --user` không chạy sau đăng xuất | Chưa bật linger | `loginctl enable-linger $USER` |
| Bảng điều khiển Kanban mở được từ Internet | Hermes Kanban **không xác thực** | Đóng ngay: chỉ bind `127.0.0.1`, truy cập qua SSH tunnel/Tailscale |

## C. Cơ sở dữ liệu và PostgREST (VPS 169)

| Triệu chứng | Nguyên nhân | Xử lý |
| --- | --- | --- |
| Nạp lược đồ: `core.current_user_id already exists` ✔ | Chạy lại `60_agent.sql` lên CSDL đã có | Lược đồ không idempotent ở 0.x: dựng lại CSDL sạch, hoặc migration |
| Nạp lược đồ dừng giữa chừng | `ON_ERROR_STOP` bắt lỗi | Xóa CSDL, sửa nguyên nhân, chạy lại từ `00` (không nạp tiếp nửa chừng) |
| `permission denied for table …` từ PostgREST | Vai trò `agent_bridge` chỉ có EXECUTE hàm, không có quyền bảng — đúng | Gọi đúng RPC; không cấp quyền bảng |
| PostgREST 404 trên `/rpc/…` sau khi dựng lại CSDL ✔ | Bộ nhớ lược đồ cũ; cần vai trò `nobody_anon` | `systemctl restart postgrest-eos` (hoặc `kill -SIGUSR1`), kiểm `nobody_anon` tồn tại |
| PGRST301 "JWT expired" ✔ | Token hết hạn | Cấp mới |
| PGRST302/JWSError | `jwt-secret` PostgREST ≠ bí mật khi ký | Dùng đúng bí mật; ≥ 32 ký tự |
| Insert `core.audit_log` lỗi "no partition found" | Sang năm 2028 chưa tạo phân vùng | `docs/03` §4.1 — **làm trước 01/12 hằng năm** |
| `mcp_token_issue`: "đã có 5 mã" | Giới hạn mỗi người | Thu hồi mã không dùng |
| Seed thử: "email null" / `secrecy` không hợp lệ ✔ | Agent cần email không rỗng; mức mật hợp lệ: `normal, confidential, secret, top_secret` | Sửa dữ liệu mẫu |
| Truy vấn chậm tìm kiếm không dấu | Thiếu extension `unaccent`/`pg_trgm` | `create extension` (siêu người dùng) |
| `waiting_on_human` hiện `true` thay vì `t` khi test ✔ | Hàm trả JSON, không phải boolean cột | So sánh với `'true'` |

## D. Máy phát triển Z2

| Triệu chứng | Nguyên nhân | Xử lý |
| --- | --- | --- |
| `docker: permission denied` | Shell chưa nhận nhóm `docker` | `sudo apt install util-linux-extra` rồi `newgrp docker` (hoặc đăng xuất/vào lại) |
| `make test` báo "tên CSDL phải chứa _test" | Bảo vệ khỏi xóa nhầm | Đổi `EOS_TEST_DSN` trỏ vào CSDL `eos_test` |
| `test_mcp.sh`: `Peer authentication failed` ✔ | Dùng socket thay vì TCP | `EOS_TEST_DSN` dạng `postgres://user:pw@127.0.0.1:5432/eos_test` |
| `test_mcp.sh` / `test_bridge.sh` gãy giữa chừng ✔ | Từng chạy trên CSDL đã có dữ liệu của bộ khác (seed hai lần → vượt 5 mã/người; bridge gặp thẻ lạ) | Mỗi script nay tự dựng lại CSDL; nếu vẫn gãy, đọc dòng lỗi đầu tiên, đừng chạy lặp |
| `test_bridge.sh`: "Không thấy postgrest" | Chưa cài | Tải bản 12.2.3 từ github.com/PostgREST/postgrest/releases, đặt `POSTGREST_BIN` |
| `test_bridge.sh` treo | Cổng 3901 đang bận | `pkill -x postgrest` |
| `gh auth` lỗi | Token môi trường sai | `unset GH_TOKEN; gh auth login` |
| Không gõ được tiếng Việt (Wayland) | Ubuntu 26.04 chỉ có Wayland | Dùng `ibus-bamboo` (đã cài), `gsettings set org.gnome.desktop.input-sources sources "[('xkb','us'),('ibus','Bamboo')]"` |
| `pre-commit` chặn commit | `check_secrets.sh` thấy mẫu bí mật | Xóa bí mật khỏi tệp, **đổi bí mật đó** (coi như đã lộ), commit lại |

## E. Mạng và Caddy

| Triệu chứng | Xử lý |
| --- | --- |
| VPS 173: Caddy (Docker) 502 tới cổng mới | Thêm `ufw allow from 172.19.0.0/16 to any port <cổng> proto tcp` |
| Reload Caddy lỗi | `caddy validate --config …` trước; Docker: `docker exec company-caddy caddy reload --config /etc/caddy/Caddyfile` |
| Cloudflare proxied làm `/mcp` chậm/đứt | MCP dùng HTTP phản hồi ngắn, không SSE kéo dài — nếu đứt, kiểm tra timeout 100 s của Cloudflare |
| SSH từ Z2 vào VPS đòi duyệt trình duyệt | Tailscale SSH xác thực web ở lần đầu; cron không dùng được → dùng khóa SSH riêng quyền hẹp |

## F. Quy trình xử lý sự cố chung

1. **Dừng chảy máu**: thu hồi mã/JWT nghi lộ; `systemctl stop` dịch vụ gây hại. Không xóa dữ liệu.
2. **Chụp trạng thái**: `journalctl`, truy vấn §6 handbook, ảnh `agent.outbox/cards/events`.
3. **Tìm nguyên nhân trong bảng trên**; nếu không có, tạo bản ghi mới vào bảng này sau khi xử lý xong.
4. **Sửa tận gốc + kiểm thử** thêm vào bộ test để không tái phát.
5. Ghi vào CHANGELOG (mục `Sửa`) nếu là lỗi trong mã.

## G. Khi nghi ngờ lộ bí mật

| Bí mật | Hành động |
| --- | --- |
| Mã MCP (`eos_…`) | `agent.mcp_token_revoke`; xem `agent.mcp_calls` của mã đó 7 ngày gần nhất; báo người dùng |
| JWT `agent_bridge` | Đổi `jwt-secret` PostgREST (vô hiệu **mọi** JWT), cấp lại JWT cầu nối và mọi JWT khác |
| Refresh token Google | Thu hồi tại myaccount.google.com → Bảo mật → Truy cập bên thứ ba; cấp lại |
| Mật khẩu `eos_mcp` / `authenticator` | `ALTER ROLE … PASSWORD`, cập nhật `.env`, restart |
| Khóa SSH | Xóa khỏi `authorized_keys`, tạo khóa mới |
| Mật khẩu root/VPS đã từng dán vào chat | Đổi ngay; chuyển sang khóa SSH, tắt đăng nhập mật khẩu |
