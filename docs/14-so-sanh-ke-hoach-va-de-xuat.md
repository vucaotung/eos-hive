# 14 · So sánh kế hoạch ban đầu và hiện trạng; đề xuất nâng cấp (24/10/2026)

Kế hoạch gốc: `docs/08-lo-trinh.md` (v0.0.0), `prompts/00-MASTER.md`. Hiện trạng: v0.2.1 + hợp nhất Ever Teams (`docs/13`).

## 1. Khác biệt chính
| Hạng mục | Kế hoạch gốc | Hiện trạng | Đánh giá |
| --- | --- | --- | --- |
| Hệ quản lý việc | Enterprise OS song song, **không đụng Ever Teams** (luật 9) | Ever Teams đã nhập và gỡ; một hệ duy nhất | Đổi hướng có chủ đích; luật 9 đã sửa |
| Giao diện | RPC `agent.app_*` + web tối giản | Web đầy đủ (Dẹo Work UI chuyển sang lược đồ 108 bảng): Hôm nay, Việc, Dự án, Duyệt, Báo cáo, Quản trị | Vượt kế hoạch |
| Duyệt | Câu hỏi mở #1, #2 (mặc định có người xem) | Engine duyệt nhiều bước, *Phải duyệt*, trigger chặn Xong | Đã chốt bằng thiết kế |
| Dự án | Chưa có | Quản lý dự án đầy đủ + **hồ sơ dự án tự động** (Điều phối → runner → Văn thư → WeKnora) | Mới, ngoài lộ trình |
| MCP | 15+3 công cụ | 18 công cụ, phạm vi tách người/agent, ràng buộc CHECK | Vượt |
| Agent | 3 profile `eos-*` | 4 profile + runner Z2; `phap-che` chưa có | Thiếu pháp chế |
| Báo cáo | `agent.routines` bản tin sáng (0.2.0) | Bản tin/tuần bằng cron Hermes không LLM + `eos_company_digest` | Đạt bằng cách khác; `agent.routines` vẫn chưa kích hoạt |
| Kho tri thức | `eos_ask_kb` + hàng đợi câu không tìm thấy (0.2.0) | Nạp (`eos_kb_ingest`) có; hỏi đáp qua WeKnora MCP của từng profile; chưa có hàng đợi | Một nửa |
| OAuth 2.1 cho MCP (0.3.0) | Kế hoạch sau | Chưa; dùng mã Bearer 90 ngày | Lệch lịch, ổn |
| Giới hạn tốc độ/biên | 0.3.0 | Đã có (429 ở web) | Sớm hơn |
| RLS mọi bảng; `core.schema_migrations` | 0.1.0 | Còn nợ (migration vẫn áp tay 0001–0015) | **Nợ kỹ thuật** |
| CI xanh, GitHub | 0.0.x ưu tiên 1 | Chỉ ở `main` cục bộ, chưa đẩy 0.2.x | **Nợ** |
| Sao lưu + khôi phục thử | 0.0.x | Có `restore_drill.sh`; chưa có lịch 3 tháng liên tiếp | Một phần |
| Số hệ thống nhắc việc | 1 | 1 cho việc (EOS) nhưng **ERPNext (staff-work) và Dẹo (deo-facts, vòng lặp F4-F5)** còn sót | Cần quyết |

## 2. Rủi ro hiện tại
1. Bot Zalo/Telegram tạo việc dưới danh tính **một người** (chủ mã) → mất dấu vết ai yêu cầu.
2. Mã MCP hết hạn 90 ngày: bản tin im lặng khi hết (có dòng cảnh báo nhưng dễ bỏ sót).
3. Migration áp tay: lệch giữa dev/prod là rủi ro lặp lại.
4. Một điểm lỗi: Postgres + MCP + web cùng vps169.
5. `phap-che` có trong CSDL nhưng không có profile: việc giao sẽ kẹt.
6. Khóa WeKnora nằm chữ trong `team_admin/config.yaml`.
7. SSH mật khẩu / UFW (đã chấp nhận, `scripts/security_accepted.txt`).

## 3. Đề xuất (xếp theo giá trị/công sức)
**Ngay (≤ 1 tuần)**
- Chốt cách cấp quyền ghi cho Mai/ks: (a) tài khoản dịch vụ riêng "Mai (AI)" loại `agent` với phạm vi `write` và thêm tham số `requested_by` bắt buộc ghi vào mô tả; (b) mã của Tùng (nhanh, mất dấu vết); (c) chỉ đọc. **Khuyến nghị (a).**
- Đẩy `main` + tag lên GitHub, bật CI.
- Xóa 2 cron Ever và cron F4-F5 sau khi xem bản tin mới chạy ổn 2-3 sáng.
- Chuyển khóa WeKnora sang `.env`.

**Tháng này**
- `core.schema_migrations` + script `migrate.sh` chạy tự động khi triển khai.
- Cảnh báo mã sắp hết hạn trong bản tin (≤ 14 ngày), tự cấp lại bằng `issue_user_token.sh`.
- Thông báo đẩy (Telegram) khi việc *chờ duyệt* quá 24 giờ và khi agent hỏi lại.
- Profile `phap-che`, hoặc bỏ khỏi danh sách.
- Quyết `staff-work`/ERPNext: chuyển nhắc việc sang `eos_company_digest` theo người, rồi gỡ ERPNext khỏi luồng nhắc.

**Quý này**
- RLS cho mọi bảng; kiểm thử phân quyền theo vai trò.
- Zalo đa người: ánh xạ số Zalo ↔ tài khoản EOS để bot tạo việc đúng người.
- `eos_ask_kb` + hàng đợi câu không tìm thấy; kích hoạt `agent.routing_rules`/`routines`.
- OAuth 2.1 cho MCP; sao lưu ra ngoài máy (vps169 đang tự giữ).
- Đo tỷ lệ chấp nhận lần đầu của agent (điều kiện 1.0.0) bằng bảng điều khiển trong Báo cáo.
