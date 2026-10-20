# 08 · Lộ trình

## Đã có (v0.0.0)
Lược đồ 108 bảng · lớp agent · MCP (15+3 công cụ) · cầu nối + plugin (chưa thử Hermes thật) · tài liệu · CI · prompt triển khai.

## 0.0.x — đưa lên máy thật (ưu tiên số 1)
| Việc | Cổng đạt |
| --- | --- |
| Đẩy repo lên GitHub (private), CI xanh | CI xanh trên `main` |
| Kiểm chứng A1–A20 (`docs/07`), sửa cầu nối, thêm fixtures thật | Bảng giả định điền đủ ✔ |
| Triển khai CSDL + PostgREST + MCP lên VPS 169 | `docs/03` §2 bước 1–6 |
| Triển khai cầu nối + plugin + 3 profile `eos-*` lên VPS 173 | Khói đầu–cuối `docs/03` §7 |
| Tạo skill Hermes cho `kb-tra-cuu`, `nd30-van-thu`, `hr-cham-cong`, `lap-ke-hoach` hoặc bỏ cột | A10 |
| Thêm CSDL `eos` vào sao lưu; khôi phục thử | `docs/03` §5 |

## 0.1.0 — giai đoạn 1: lõi dùng được
- **Nối dây xác nhận L2 có cấu trúc** (phát hiện ở nghiệm thu): `agent.request_confirmation` / `decide_confirmation` đã có nhưng chưa có đường gọi — worker chỉ có `eos_guide`, `eos_get_task`, `eos_delegate` và cầu nối không gọi hàm này. Hiện L2 chạy qua chặn–trả lời (đã nghiệm thu, kịch bản A1). Cần quyết: thêm công cụ MCP cho worker, hay cầu nối nhận dạng `kanban_block` kiểu đề xuất.
- Bảng `core.schema_migrations` ghi phiên bản (đã có `db/migrations/0001`, `0002` áp tay).
- RPC cho app web (đăng nhập Google + mã mời), **RLS** cho mọi bảng, dữ liệu khởi tạo (công ty, phòng, vai trò, quyền, danh mục).
- Màn hình tạo mã MCP (Tài khoản → Kết nối AI agent) thay cho SQL.
- Chuyển `legacy/deo-work` sang lược đồ 108 bảng; hộp việc của agent (chờ xem, đang hỏi, xác nhận L2).
- Migration có phiên bản (`db/migrations/`).

## 0.2.0 — phân hệ
- Công văn: Văn thư AI đọc công văn đến, điền nháp sổ; cấp số do người; in sổ cuối năm.
- Nhân sự: rà chấm công, đối chiếu đơn/phép, nháp KPI/bảng lương.
- Kho dữ liệu chung: công cụ MCP hỏi WeKnora (`eos_ask_kb`), hàng đợi câu không tìm thấy.
- Kích hoạt `agent.routing_rules` và `agent.routines` (công văn đến mới → Văn thư; bản tin sáng).

## 0.3.0 — kết nối rộng
- OAuth 2.1 cho MCP → nối được Claude.ai / ChatGPT bản web.
- Giới hạn tốc độ và chặn IP ở lớp biên; bộ lọc nội dung nhạy cảm khi lưu Drive.
- CRM giai đoạn đầu.

## 1.0.0 — điều kiện
Một công ty dùng hằng ngày ≥ 30 ngày; tỷ lệ chấp nhận ngay lần đầu của agent đo được; khôi phục sao lưu đã diễn tập 3 tháng liên tiếp; không còn mục nào trong "Điểm yếu đã biết" (`docs/06`).

## Câu hỏi mở cần chủ sở hữu quyết (từ thiết kế)
1. Mặc định mọi kết quả agent phải có người xem trước khi Xong? (v0.0 đặt: **có**.)
2. Agent được phép nộp việc mà người phụ trách chưa nhìn không? (v0.0: không.)
3. Skill Hermes nào viết trước: Văn thư (NĐ 30) hay Quản trị dữ liệu (KB)?
4. Cloudflare có proxy `work.enterpriseos.bond` không (ảnh hưởng timeout và giới hạn tốc độ)?
