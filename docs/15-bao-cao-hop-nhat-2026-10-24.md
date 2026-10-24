# Báo cáo hợp nhất Ever Teams → Enterprise OS · 24/10/2026 (v0.2.2)

## 1. Tóm tắt điều hành
- Enterprise OS là hệ quản lý việc **duy nhất**. Ever Teams đã dừng (container tắt, volume còn), `teams.*` chuyển hướng về `work.*/app`; 21 việc đang chạy đã nhập sang Enterprise OS.
- Bản tin sáng/tuần lấy từ Enterprise OS, gửi Telegram qua cron Hermes (không LLM). Cron Ever tạm dừng.
- Kiểm thử cục bộ đạt hết (DB 111 bảng, MCP 30 bước, web 20, cầu nối 7, runner 9, báo cáo 7); nghiệm thu máy thật A2/A8: 23/23.
- Rủi ro lớn nhất: bot (Mai, ks) chưa có quyền ghi Enterprise OS vì chưa chốt danh tính cấp mã; gateway chưa khởi động lại nên Mai/ks chưa nhận cấu hình mới.

## 2. Changelog (v0.2.0 → v0.2.2)
Xem `CHANGELOG.md`. Điểm chính: bản tin ngày/tuần (`eos_company_digest`, `ops/eos_report.py`), `eos_task_save`, `eos_list_members` (18 công cụ), migration 0012–0015 (chặn nộp tay việc agent, khóa epoch cầu nối, thẻ chạy lại khi trả lời, đóng lượt chạy workflow), khối Kết quả, skill `enterprise-os-guide`, công cụ gỡ Ever (`ops/hermes_remove_everteams.py`), bản tin dùng từ "công việc".

## 3. Diff
- Mã: 22 tệp, +784/−10 từ 66d9b4c~1 (số liệu `git diff --stat`); toàn bộ từ v0.2.0 xem `git diff v0.2.0 HEAD`.
- Hạ tầng: 14 container Ever dừng · Caddy sửa 2 site · Hermes sửa config team_admin, ks-kinh-te-xd, ops-admin + SOUL ks (sao lưu `.bak-everteams-*`) · migration 0014/0015 áp vps169 · MCP khởi động lại.
- Kế hoạch gốc vs hiện trạng: `docs/14` §1.

## 4. Đề xuất cải tiến (xếp ưu tiên)
| # | Đề xuất | Công sức | Giá trị |
| --- | --- | --- | --- |
| 1 | Tài khoản dịch vụ riêng "Mai (AI)" + `requested_by` bắt buộc, rồi cấp mã ghi cho Mai/ks | M | Cao: giữ dấu vết, bot tạo việc được |
| 2 | Đẩy `main`+tag lên GitHub, bật CI | S | Cao |
| 3 | `core.schema_migrations` + `migrate.sh` tự động khi triển khai | M | Cao: hết áp tay |
| 4 | Cảnh báo mã MCP sắp hết hạn trong bản tin; cấp lại theo lịch | S | Cao: tránh bản tin im lặng |
| 5 | Thông báo Telegram khi việc chờ duyệt > 24 giờ / agent hỏi lại | M | Trung bình-cao |
| 6 | Quyết ERPNext (staff-work) và Dẹo (deo-facts, vòng lặp F4-F5): gộp vào Enterprise OS, gỡ | M | Trung bình: còn đúng một hệ |
| 7 | Profile `phap-che` hoặc bỏ agent này | S | Trung bình |
| 8 | Chuyển khóa WeKnora khỏi `team_admin/config.yaml` sang `.env` | S | Trung bình (bảo mật) |
| 9 | RLS mọi bảng + kiểm thử phân quyền | L | Cao (dài hạn) |
| 10 | Zalo đa người (số Zalo ↔ tài khoản EOS); `eos_ask_kb` + hàng đợi câu không tìm thấy; OAuth 2.1 MCP | L | Dài hạn |

## 5. Việc chờ chủ sở hữu
Chọn danh tính mã cho Mai/ks · duyệt khởi động lại `hermes-gateway` · xóa volume/image Ever (≥ 30 ngày) · xóa DNS `teams`, `teams-api` · xóa cron tạm dừng · đẩy GitHub.
