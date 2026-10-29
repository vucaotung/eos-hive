# 19 · Tạo việc nâng cao (11 tính năng, 0.5.0)

Migration **0030** (`db/64_creation.sql`, áp được nhiều lần, chỉ thêm). Mọi RPC mới nằm trong bảng trắng `web/src/routes.mjs`; web chỉ gọi `agent.app_*` bằng quyền của người dùng, MCP chỉ gọi `agent.mcp_task_tags`.

| # | Tính năng | Cách làm | Giới hạn / lưu ý |
| --- | --- | --- | --- |
| 1 | Đính kèm lúc tạo | Dán **link Google Drive/Docs** trong "Thêm chi tiết" → `app_task_create_ex.attach` ghi `core.files` + `core.attachments` | **Chưa tải tệp từ máy lên được**: máy chủ web không giữ thông tin đăng nhập Drive (cần quyết định cấp tài khoản dịch vụ Drive). Tối đa 10 link lúc tạo, 30 tệp/việc; chỉ nhận `drive.google.com`/`docs.google.com`. |
| 2 | Tạo từ mẫu việc | `work.task_templates` (tiêu đề, mô tả, ưu tiên, cờ, ước tính, hạn sau n ngày, nhãn, checklist, việc con). Nút **Mẫu việc** trong form: chọn, điền sẵn, lưu form hiện tại thành mẫu, xóa mẫu | Tối đa 100 mẫu/công ty; người tạo hoặc quản lý sửa/xóa. Bỏ trường lạ khi lưu mẫu. |
| 3 | Nhân bản | `app_task_clone` + nút **Nhân bản** (có "kèm việc con") ở ngăn chi tiết | Bản sao: Chờ làm, giữ người/dự án/ưu tiên/cờ/ước tính/nhãn, checklist bỏ dấu tick; hạn đã qua thì để trống; không nhân bản thẻ phân tích của Mai. |
| 4 | Phụ thuộc | `work.task_deps` + trigger: B **chưa chuyển sang Chờ duyệt/Xong** khi A còn mở (A xong hoặc hủy là hết chờ); A xong thì báo người làm B (loại `unblocked`) | Cấm tự chờ và vòng chờ nhau (kể cả gián tiếp); tối đa 10; bắt đầu làm B vẫn được (chặn mềm). |
| 5 | Gõ nhanh | Ô "Gõ nhanh" trong form giao việc, phân tích ở trình duyệt (`web/ui/src/lib/quickadd.js`, có test) | `@người` (mơ hồ thì để trống và báo), ngày (hôm nay, mai, ngày kia, thứ 2…7, cn, tuần sau, 20/11, +3), giờ 17h = **giờ nhắc**, `!cao !khan !thap !tb !qt !kc`, `#nhãn`, `^dự án`, `~90p`. "Mai" viết hoa là tên người. |
| 6 | Nhắc hạn | `work.tasks.remind_at/reminded_at`; `work.run_reminders()` chạy **mỗi 10 phút** (`scripts/housekeeping.sh --reminders`) báo người phụ trách (hoặc người tạo) ở chuông | Mỗi lần đặt giờ chỉ nhắc một lần; việc đã xong/hủy không nhắc; giờ phải ở tương lai ≤ 400 ngày. Chưa đẩy ra Telegram/email. |
| 7 | Hàng loạt | `app_tasks_bulk` + nút **Tạo hàng loạt** ở trang Việc: dán danh sách (cú pháp gõ nhanh) hoặc CSV (Tiêu đề, Người phụ trách, Hạn, Ưu tiên, Dự án, Nhãn, Mô tả), xem trước, báo lỗi theo dòng | ≤ 100 việc/lần; mỗi việc một tiểu giao dịch (dòng lỗi không chặn dòng khác); tệp CSV ≤ 500 KB. |
| 8 | Từ Zalo/Telegram qua Mai | Skill **1.3.0**: quy trình hiểu tin → kiểm trùng bằng `eos_search` → xác nhận một dòng → `eos_task_save` (`source_ref`, `tags`) → trả mã T-số; `mcp_task_tags` chỉ gắn nhãn cho việc **vừa tạo bởi chính tài khoản** (≤ 10 phút) | Bot chưa có công cụ đặt nhắc/phụ thuộc/đính kèm (hướng dẫn người dùng làm trên web). Nhiều việc/tin: tối đa 10. |
| 9 | Nhãn | `work.tags`, `work.task_tags`; ô nhãn trong form và ngăn chi tiết; gợi ý (`app_tag_suggest`: nhãn có tên trong chữ + nhãn hay dùng ở các việc giống); chip nhãn ở dòng việc và **lọc theo nhãn** ở trang Việc | ≤ 8 nhãn/việc, tên ≤ 30 ký tự, duy nhất theo tên không phân biệt hoa thường trong công ty. |
| 10 | Cảnh báo trùng | `app_task_similar` (độ giống tên bằng pg_trgm ≥ 0,45 hoặc tên chứa nguyên cụm), chỉ việc đang mở người dùng được xem; hiện khung vàng khi gõ tên, bấm để xem việc | Chỉ cảnh báo, vẫn tạo được. Bot dùng dedupe `source_ref` 15 phút có sẵn. |
| 11 | Việc lặp vô hạn / theo thời gian | `work.recurrences.max_runs/run_count`, tần suất thêm **hằng năm**; form: Kết thúc lặp = *Không bao giờ* / *Đến ngày* / *Sau n lần* (`app_recurrence_save_ex`) | Việc lặp từ form chỉ mang tiêu đề/mô tả/người/dự án/ưu tiên (nhãn, nhắc, đính kèm áp dụng cho việc tạo một lần). n tính cả việc đầu; đủ n thì tự dừng. |

## Cần làm sau khi triển khai
1. Áp migration `0030_creation_features.sql` **trước** khi đẩy mã (mã web gọi RPC mới).
2. Cài `deploy/cron.eos-housekeeping` vào `/etc/cron.d/eos-housekeeping` (thêm dòng chạy mỗi 10 phút) và `deploy/logrotate.eos-housekeeping` vào `/etc/logrotate.d/`.
3. Ops-admin cài skill `enterprise-os-guide` **1.3.0** vào `team_admin` rồi khởi động lại gateway từ shell ngoài; thử một tin nhắn thật.
4. Quyết định còn mở: tải tệp trực tiếp từ máy cần tài khoản dịch vụ Drive cho máy chủ web (đang dùng link).

## Kiểm thử
`make test-db` (khối "Tạo việc nâng cao ok"), `make test-web` (`quickadd.mjs` + bước e2e qua HTTP), `make test-mcp` (nhãn qua `eos_task_save`), `scripts/check_migration_30.sh` (áp hai lần trên CSDL trước 0030, hàm và cột khớp lược đồ dựng mới).
