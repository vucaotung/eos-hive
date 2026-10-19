# 40 · Pha 4 — Nghiệm thu đầu–cuối

**Mục tiêu:** chứng minh vòng đời trọn vẹn trên máy thật: giao việc cho agent → thẻ Kanban → hỏi lại → trả lời → báo xong → người chấp nhận; agent cá nhân qua MCP; sao lưu khôi phục được.
**Chạy:** từ Z2. **Đã đạt** pha 1–3. Việc thử dùng công ty thật đã tạo ở pha 2 nhưng **gắn nhãn `[SMOKE]`** và dọn sau.

## Bước 1 — Chuẩn bị
1. Hỏi người dùng tạo/xác nhận một người dùng thử (có thể là chủ sở hữu). Đặt `drive_folder_id`, `drive_folder_url`, `drive_state='ok'` cho người đó nếu muốn thử ghi Drive (người dùng tạo thư mục thủ công, chia sẻ quyền **Editor** cho tài khoản agent Workspace, cung cấp ID — hỏi, đừng tự tạo).
2. Cấp mã MCP cho người đó (người vận hành, `docs/04` §7) với phạm vi `read,write,drive` — **không in**; ghi vào tệp 600 trên Z2 (`~/.config/eos-hive/smoke.env`: `EOS_SMOKE_TOKEN=…`) bằng đường ống, ví dụ:
   ```bash
   ssh vps169 '… psql … -c "…mcp_token_issue…"' | ( umask 077; { printf 'EOS_SMOKE_TOKEN='; tr -d '\n'; echo; } > ~/.config/eos-hive/smoke.env )
   ```
   (dùng cùng kiểu đặt `request.jwt.claims` như `scripts/issue_agent_token.sh`, với `sub` = id người dùng thử).

## Bước 2 — Khói MCP (agent cá nhân)
Với `EOS_SMOKE_TOKEN` (nạp từ tệp, không in), gọi MCP bằng client hợp lệ (SDK trong `mcp/node_modules` hoặc `npx @modelcontextprotocol/inspector --cli`):
- `initialize` + `tools/list`: kỳ vọng 15 công cụ.
- `eos_whoami` → tên đúng người, công ty, `drive.status`.
- `eos_my_day`, `eos_list_tasks` chạy không lỗi (có thể rỗng).
- Mã sai → 401; mã không có phạm vi `hr_self` gọi `eos_my_hr` → từ chối.

## Bước 3 — Khói vòng đời agent
Tạo việc thử bằng SQL (chưa có app) trên `eos` với `assignee_id` = người thử, `agent_id` = id agent `thu-thu`, tiêu đề `[SMOKE] kiểm thử Tổ Ong`, mô tả: "Chỉ để kiểm thử. Hãy kanban_block hỏi: 'Áp dụng cho dự án nào?'. Sau khi nhận câu trả lời, kanban_complete với summary ≥ 10 ký tự và metadata.confidence='cao'." Ghi `T-<id>`.

Theo dõi và chứng minh từng cạnh (ghi bằng chứng vào ops-log, đường dẫn):

| # | Kỳ vọng | Bằng chứng |
| --- | --- | --- |
| 1 | ≤ 2 phút: `agent.cards` có thẻ, `hermes kanban list --board eos-<slug>` thấy thẻ | truy vấn + lệnh |
| 2 | Dispatcher nhận → việc `in_progress` | `select status from work.tasks` |
| 3 | Agent `kanban_block` → việc `blocked`, `waiting_on_human`, có bình luận câu hỏi | `eos_get_task` qua MCP của người thử |
| 4 | Người trả lời bằng `eos_comment kind=answer` → thẻ `unblock` → chạy tiếp | `agent.outbox` kind=answer đã `done_at`; thẻ `running` lại |
| 5 | Agent `kanban_complete` → việc `in_review`, có `agent.reports`; metadata còn nguyên | `select * from agent.reports where task_id=…` |
| 6 | Người chấp nhận (`agent.accept_result`) → `done` | trạng thái việc |
| 7 | Chạy lại cầu nối `--once`: không báo cáo trùng (`no_change`/`duplicate`) | log cầu nối |
| 8 | (Tùy chọn) trả lại một lần → thẻ làm lại mới kèm lý do | `agent.cards.kind='rework'` |

Nếu kẹt ở cạnh nào: dừng, dùng `docs/05` mục B, không "bơm" trạng thái tay bằng SQL để che lỗi.

## Bước 4 — Ghi Drive (chỉ khi Google đã điền)
Qua MCP: `eos_save_to_drive` một tệp markdown nhỏ cho việc thử → trong Drive người dùng thấy `Kết quả/<năm-tháng>/T-<id> - …`. `eos_submit_result` với tóm tắt. Nếu lỗi 404/403: `docs/05` mục A.

## Bước 5 — Khôi phục sao lưu thử (trên Z2)
1. Sau 04:00 hôm sau (hoặc chạy tay `backup.sh` rồi kéo): xác nhận Z2 có bản `eos_*.dump.enc` mới trong `~/backups/deo169` (kích thước > 0).
2. Khôi phục vào Postgres rỗng trên Z2 (mật khẩu sao lưu do người dùng nhập tại chỗ, **không** qua chat):
   ```bash
   docker run -d --name eos-restore -e POSTGRES_PASSWORD=$(openssl rand -hex 8) -p 127.0.0.1:5436:5432 postgres:16
   # giải mã bằng openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha512 -pass stdin … | docker exec -i eos-restore pg_restore -U postgres -d eos --no-owner  (tạo DB eos trước)
   docker exec eos-restore psql -U postgres -d eos -Atc "select count(*) from information_schema.tables where table_schema in ('core','work','doc','hr','crm','kb','agent') and table_type='BASE TABLE' and table_name not like 'audit_log_20%'"   # 108
   docker exec eos-restore psql -U postgres -d eos -Atc "select count(*) from work.tasks"                              # khớp VPS 169
   docker rm -f eos-restore
   ```
3. Ghi kết quả (ngày, số bảng, số việc) vào ops-log và mục "Nhật ký vận hành" trong `docs/03` (thêm dòng).

## Bước 6 — Dọn và bàn giao
1. Hủy việc `[SMOKE]` (trạng thái `cancelled`), `hermes kanban archive` thẻ liên quan, thu hồi mã thử (`agent.mcp_token_revoke`), xóa `smoke.env`.
2. Cập nhật `docs/07` (đủ ✔/✘), `CHANGELOG.md` (mục `[Chưa phát hành]` → ghi những gì đã sửa), `VERSION` → `0.0.1` nếu có sửa mã; tag `v0.0.1`; push.
3. Chạy `scripts/check_secrets.sh`; `grep -rE 'eos_[0-9a-f]{48}|eyJ' ops-log/ || echo sạch`.
4. Viết báo cáo cuối (≤ 25 dòng): đạt gì, sửa gì, còn gì (ưu tiên theo `docs/08` mục 0.0.x), rủi ro bảo mật còn mở (`docs/06` điểm yếu), danh sách việc của người dùng.

## Cổng của pha 4
- [ ] MCP: 15 công cụ, `eos_whoami` đúng, mã sai 401
- [ ] Vòng đời agent: cạnh 1–7 đều có bằng chứng
- [ ] (Nếu Google đã điền) tệp kết quả xuất hiện đúng thư mục Drive
- [ ] Khôi phục thử: 108 bảng, số việc khớp
- [ ] Dữ liệu `[SMOKE]` đã dọn; mã thử đã thu hồi
- [ ] `docs/07` điền xong; CHANGELOG/VERSION/tag cập nhật; repo sạch bí mật
