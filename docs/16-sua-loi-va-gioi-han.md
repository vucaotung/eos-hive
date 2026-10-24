# 16 · Sửa lỗi và giới hạn lớp MCP (0.2.5, nhánh `feat/hardening-0.2.5`)

Nền: 0.2.4 (migration 0017 đã áp trên VPS 169). Nhánh này xuất phát từ `feat/consolidate` (chứa 0016, 0017 chưa nằm trên `main`). **Chưa triển khai, chưa tạo PR.** Migration mới: 0018–0022.

| # | Việc | Trạng thái | Migration | Kiểm thử |
| --- | --- | --- | --- | --- |
| 1 | Giới hạn mã sai theo IP ở `/mcp` | Xong | không (code Node) | e2e: 25 mã sai → 20 lần 401, từ lần 21 trả 429 (có `Retry-After`); mã đúng cũng 429 khi đang bị chặn; IP khác không ảnh hưởng; hết cửa sổ mã đúng dùng lại |
| 2 | `mcp_token_issue` kiểm công ty | Xong | 0018 | `test_agent.sql`: thành viên thường, trưởng phòng, người ngoài, công ty không tồn tại → từ chối; chủ công ty (không phải quản trị hệ thống) → được; không truyền công ty → như cũ |
| 3 | Chống trùng việc theo khóa | Xong | 0019 | e2e: khác người phụ trách → hai việc; chuẩn hóa hoa/thường/khoảng trắng; cùng `source_ref` → `duplicate:true` + id + lý do; khác/thiếu `source_ref` → việc mới; quá 15 phút → tạo lại; hai lần gọi đồng thời → một việc; người thật không bị chặn |
| 4 | Tệp Drive mồ côi | Xong | 0020 | e2e: thành công → `done`; đăng ký lỗi (trigger giả lập) → `orphan` có `drive_id`, tệp không bị xóa; `upload_sweep` đánh dấu pending→failed, uploaded→orphan và liệt kê; không phải quản trị hệ thống bị từ chối |
| 5 | Nạp kho song song | Xong | 0021 | e2e: hai `eos_kb_ingest` đồng thời cùng tài liệu → WeKnora nhận đúng một lần; giữ chỗ treo > 30 phút lấy lại được |
| 6 | Dọn bảng tạm | Xong | 0022 | e2e: xóa dòng cũ, giữ orphan và bản ghi đã nạp; chỉ quản trị hệ thống; bộ đếm bộ nhớ tự dọn và giới hạn số khóa |
| 7 | Mô tả công cụ chống chỉ dẫn lạ | Xong | không | e2e: dòng "LƯU Ý AN TOÀN" có trong `eos_task_save`, `eos_comment`; mô tả việc chứa chỉ dẫn lạ (7 000+ ký tự) lưu và đọc lại nguyên văn, T-501 không bị hủy |

## Chi tiết từng việc
1. **Rate limit.** `makeAuthGuard` (`mcp/src/server.mjs`): đếm lần xác thực **thất bại** theo `req.ip`; `>= 20` lần trong 5 phút → 429 **trước** `verifyToken` (không chạm CSDL). Lần đúng không xóa bộ đếm; bị chặn rồi thì không kéo dài cửa sổ. Chỉnh bằng `MCP_AUTHFAIL_MAX`, `MCP_AUTHFAIL_WINDOW_MS`. **IP thật:** có Caddy phía trước nên `X-Forwarded-For` → `trust proxy 'loopback'`; nếu gọi thẳng cổng 8790 thì IP là IP kết nối. *Hạn chế:* trong bộ nhớ (khởi động lại thì xóa); nhiều máy sau cùng một IP (NAT, hoặc cả Hermes vps173 chung một IP) dùng chung hạn mức. `deploy/Caddyfile.mcp.snippet` là **mẫu** (chặn thiếu `Authorization`, giới hạn thân 16 MB); giới hạn tốc độ ở Caddy cần plugin nên không đưa vào. Không sửa Caddyfile thật.
2. **Công ty của mã.** Có `p_company` thì người cấp phải là quản trị hệ thống, hoặc thành viên đang hoạt động mà `core.perm_scope_of(me, company, 'core.member.manage') = 'company'` (owner, admin). Lưu ý đã sửa một lỗi NULL trong lúc làm: `NOT (… AND NULL)` → NULL làm câu `IF` bỏ qua; nay bọc `coalesce(…, false)`. *Chưa làm:* `eos_*` vẫn **không dùng** `mcp_tokens.company_id` để giới hạn dữ liệu (chỉ đảm bảo ai được cấp mã gắn công ty). Việc này cần quyết định riêng khi có công ty thứ hai.
3. **Khóa chống trùng.** `agent.task_create_keys(dkey, company_id, created_by, task_id)`; `dkey = md5(công ty | core.norm(tên) | id người phụ trách | source_ref)`; khóa tư vấn `pg_advisory_xact_lock` giữ hai lần gọi đồng thời. Tham số mới `source_ref` (≤ 120 ký tự) của `eos_task_save`, ví dụ id tin Zalo. Chỉ áp cho tài khoản agent (Mai); người thật không bị chặn. Phản hồi trùng: `{id, duplicate:true, reason}`. **Skill/persona của Mai nên truyền `source_ref`** khi có (chưa cập nhật skill).
4. **Tệp mồ côi.** `agent.drive_uploads` (`pending → uploaded → done`, hỏng thì `failed`/`orphan`). `mcp_upload_begin` (người: phải xem được việc; agent: phải có thẻ đang chạy), `mcp_upload_finish`. Áp cho `eos_save_to_drive`, `eos_project_save_report`, `eos_draft_document`. **Không xóa tệp Drive trong code.** Dọn: `agent.upload_sweep(1)` (chỉ quản trị hệ thống): lượt treo quá 1 giờ → `failed` / `orphan`, trả danh sách tệp mồ côi (`drive_id`, link, việc, thời điểm). Xem danh sách bất kỳ lúc nào:
   `SELECT id, task_id, filename, drive_id, error, created_at FROM agent.drive_uploads WHERE state = 'orphan' ORDER BY id;`
5. **Nạp song song.** `agent.kb_ingest_claims(base_id, drive_id, …)`; `mcp_kb_ingest_claim` giữ chỗ trước khi làm (INSERT … ON CONFLICT), `mcp_kb_ingest_finish` đánh dấu `done` hoặc nhả. Dòng đặc biệt `'__create__'` giữ chỗ việc **tạo kho** (hai lần gọi không tạo hai kho; lần sau báo "đang được tạo, thử lại"). Khóa theo **(kho, tài liệu)** thay vì (công ty, tài liệu): kho thuộc đúng một công ty (có `company_id` kèm) và cùng một tệp Drive ở hai kho khác nhau là hợp lệ. Giữ chỗ treo > 30 phút được lấy lại; `done` mà nguồn đã bị xóa khỏi kho cho nạp lại.
6. **Dọn.** `agent.housekeeping_prune(p_days := 1)` (chỉ quản trị hệ thống) xóa: `task_create_keys` cũ, `drive_uploads` trạng thái `done` cũ, `kb_ingest_claims` `claiming` bị bỏ quên. **Không** đụng `failed`/`orphan`, claims `done`, `mcp_calls` (nhật ký kiểm toán: giữ hay xóa là chính sách của chủ sở hữu). **Bảng đếm tốc độ nằm trong bộ nhớ Node**, không có bảng CSDL: tiến trình tự dọn mỗi phút và giới hạn số khóa (50 000). Không tự đặt cron. Gợi ý lịch (chạy bằng quản trị hệ thống qua psql, ví dụ hằng đêm 03:30), mỗi lệnh có `set_config('request.jwt.claims', …)` của quản trị hệ thống giống `scripts/issue_user_token.sh`:
   `BEGIN; SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT id FROM core.users WHERE is_system_admin AND kind='person' ORDER BY created_at LIMIT 1))::text, true) \g /dev/null` rồi `SELECT agent.upload_sweep(1); SELECT agent.housekeeping_prune(1); COMMIT;`
7. **Prompt injection.** Thêm một câu vào mô tả `eos_task_save` và `eos_comment`. Đây là lớp nhắc nhở, **không** phải biện pháp bảo vệ duy nhất: quyền hạn thực của Mai (11 công cụ, chỉ tạo việc mới) mới là hàng rào.

## Kết quả kiểm thử cục bộ (`make test`)
Ghi ở báo cáo cuối của nhánh (CSDL 114 bảng, MCP e2e 36 bước, web 20, cầu nối 7, runner 9, báo cáo 7).

## Thứ tự triển khai khuyến nghị
1. Sao lưu `pg_dump -Fc eos`.
2. **Migration trước**, theo thứ tự: 0018 → 0019 → 0020 → 0021 → 0022 (đều idempotent, mỗi tệp tự `BEGIN/COMMIT`). Điều kiện: 0016 và 0017 đã áp (0017 đã áp; kiểm 0016 bằng `SELECT 1 FROM core.roles WHERE code='tro_ly_ai'`).
3. **Code sau:** `scripts/push_to_host.sh` rồi `systemctl restart eos-mcp`. (Code mới tìm các bảng/hàm mới: **không** khởi động lại trước khi áp xong 0019–0021, nếu không `eos_task_save` của Mai, tải Drive và nạp kho báo lỗi.) Code cũ vẫn chạy được với CSDL mới.
4. Kiểm: `make acceptance ONLY=A2,A8`; gọi `eos_whoami` bằng mã Mai; thử 21 mã sai từ một máy: lần 21 phải 429.
5. Đặt lịch `upload_sweep` và `housekeeping_prune` (tay, sau khi xem), và (tùy chọn) ghép mẫu Caddy.
6. Khuyến nghị: cập nhật skill/persona của Mai để truyền `source_ref` (id tin Zalo) khi gọi `eos_task_save`; không bắt buộc.
