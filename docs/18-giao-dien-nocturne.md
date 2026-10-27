# 18 · Giao diện Nocturne (thiết kế lại): tiến độ dựng và khoảng cách dữ liệu

Nguồn thiết kế: gói bàn giao Claude Design (26/10/2026) đã chép vào `design/` (tham chiếu, **không phải mã production**; mở bằng `npx serve design`). Đặc tả đầy đủ: `design/README.md`. Công cụ DesignSync không dùng được trong phiên không tương tác (cần `/design-login`), nên nhập từ tệp zip người dùng cung cấp.

## Đã dựng (giai đoạn 1: nhánh `feat/nocturne-ui`; giai đoạn 2a: nhánh `feat/nocturne-ui-2`; giai đoạn 2b/2c: nhánh `feat/nocturne-ui-3`)
| Hạng mục | Trạng thái |
| --- | --- |
| Token Nocturne sáng/tối, ánh xạ vào biến HeroUI (`web/ui/src/app.css`), màu ngữ nghĩa thành lớp Tailwind (`text-ai`, `bg-dg-bg`, `text-faint`…), focus 2px, nút chính là **viền** màu nhấn | Xong. Mặc định chế độ **tối**; "Theo hệ thống" vẫn chọn được (Tài khoản). |
| Font Inter (vietnamese + latin + latin-ext, 400/500/600), bỏ Be Vietnam Pro; tiêu đề tối đa 500–600 | Xong |
| Hệ mã hoá trạng thái (hình + màu + chữ, icon Phosphor): pill viền, "Vướng" là huy hiệu vuông, "Chờ người trả lời", ưu tiên có icon, hạn có icon (quá hạn đỏ, ≤3 ngày vàng) | Xong (`components/ui.jsx`) |
| Người vs AI: avatar tròn cho người; **avatar vuông + sparkle + nhãn "AI"** cho agent | Xong (`AgentChip`) |
| Dòng việc (`TaskRow`): icon trạng thái trái, dải đỏ + nền đỏ nhạt khi quá hạn, gạch ngang khi xong, ô màu dự án | Xong |
| Khung: sidebar 240px 3 nhóm (Việc của tôi / Quản lý / Góc nhìn), topbar (công ty · tìm kiếm → danh sách việc · "+ Giao việc"), tab dưới mobile 5 mục có nút tạo nhanh viền accent, màn **Thêm** (M9) | Xong (`Shell.jsx`, `nav.js`, `pages/More.jsx`) |
| Hôm nay: ô chỉ số viền trên theo ngữ nghĩa; Việc: bộ lọc dạng pill, Kanban dùng ngôn ngữ mới | Xong |
| **Chi tiết việc** (giai đoạn 2a): panel phải rộng `min(820px, 100vw − 260px)` trên nền scrim, breadcrumb "Dự án › T-số", "Sao chép link"; hàng chip (trạng thái, ưu tiên, người/AI, hạn); cột phải 230px (phòng ban, dự án, quy trình duyệt, người giao, cập nhật); mô tả; nút Sửa / Việc con / **Đánh dấu bị chặn** / **Hủy việc** / đổi trạng thái; việc con có thanh tiến độ; **Trao đổi dạng chat** (bong bóng; AI nền tím nhạt viền ai + nhãn "AI"; của mình căn phải; @nhắc tên tô màu) | Xong (`TaskDrawer.jsx`). Việc mở **đồng bộ URL**: `#/tasks?t=37` (sao chép link mở thẳng việc, Back đóng panel). |
| **Eisenhower** (2b): lưới 2×2 (Làm ngay / Lên lịch / Giao việc / Để sau) suy ra từ hai cờ Quan trọng ★ / Khẩn cấp ⚡; kéo thả HOẶC menu "Chuyển ô" (bàn phím) cập nhật hai cờ qua `app_task_save`; lỗi thì việc về chỗ cũ; cờ hiện cạnh tên việc ở mọi danh sách; form giao việc có nút bật hai cờ | Xong. **Cần migration 0025** (cột `important`, `urgent`, `start_date` trong `app_task_save`/`_task_json`). |
| **Lịch** (2c): Tháng (tối đa 3 việc/ô + "+n việc nữa", mobile hiện chấm), Tuần (7 cột, mobile xếp dọc), Timeline (20 ngày × 40px, nhóm theo dự án, thu gọn được, thanh từ ngày bắt đầu/ngày tạo đến hạn, quá hạn có dải đỏ); điều hướng ‹ Hôm nay ›; việc quá hạn có cờ đỏ | Xong theo `due_date`. **Chưa có chế độ Ngày** (việc chưa có giờ/thời lượng) và chưa đồng bộ Google Calendar. |
| **Form tạo/sửa việc** (giai đoạn 2a): modal 720px; mặc định chỉ tên, hạn, người phụ trách, dự án, ưu tiên, duyệt; **"Thêm chi tiết"** mở mô tả, phòng ban, quy trình duyệt, giao cho agent AI; **Ctrl+Enter** lưu, Esc đóng; phím **N** mở form (bỏ qua khi đang gõ) | Xong (`TaskForm.jsx`, `Shell.jsx`) |

## Khoảng cách giữa thiết kế và dữ liệu Enterprise OS (cần quyết định/backend trước khi dựng)
| Màn trong thiết kế | Điều còn thiếu | Đề xuất |
| --- | --- | --- |
| ~~Eisenhower (và cờ ★ ⚡)~~ | Đã làm ở 2b (migration 0025) | Xong |
| **Sắp tới / Việc định kỳ / Bất cứ lúc nào / Backlog** | Không có quy tắc lặp; "không hạn" và "chưa giao" chỉ lọc được phía client | Nhóm theo `due_date`/`assignee_id` trước; định kỳ cần bảng quy tắc (có thể nối `agent.routines`) |
| **Kanban kéo thả** | Thiết kế 4 cột; EOS có 5 trạng thái (Vướng, Chờ duyệt) và luật duyệt: kéo vào "Xong" phải đi qua nộp/duyệt | Giữ 5 cột; chỉ cho kéo giữa Chờ làm/Đang làm/Vướng bằng `app_task_save`; "Xong" mở luồng nộp |
| **Lịch Ngày** và đồng bộ Google Calendar | Việc chỉ có ngày (không giờ, không thời lượng); chưa có tích hợp Google | Ngày cần giờ bắt đầu + thời lượng; Google cần OAuth và quyết định một chiều/hai chiều |
| **Tổng quan** (burndown, dự báo rủi ro, mục tiêu tuần, chuỗi ngày) | Cần số liệu lịch sử và mục tiêu tuần; dự báo là việc của agent | `app_report` hiện có; thêm snapshot hằng ngày cho burndown |
| **Dự án: Danh sách / Mindmap / Gantt** | Có Kanban/tổng quan; chưa có 3 chế độ còn lại, việc con đã có (`parent_id`) | Dựng sau Danh sách việc |
| **Còn thiếu ở chi tiết việc/form**: **Tạo bằng AI** (cần API phân tích mô tả), menu gõ `@` chọn tên, checklist + mẫu, đính kèm tệp ≤ 5 MB, nhật ký thay đổi, người theo dõi, lặp lại, cờ, thời lượng | `app_task` chưa trả checklist/nhật ký/người theo dõi; cần mở rộng hàm và bảng |
| **Trợ lý Hermes** (hỏi đáp trong web) | Chưa có API agent cho web; mọi hành động phải ghi `actor = agent` | Cần thiết kế riêng (quyền, ghi nhật ký) |
| **Thông báo (chuông)**, **chọn công ty dạng popover có số quá hạn** | Chưa có bảng thông báo; chọn công ty đã có (danh sách đơn giản) | Bảng `core.notifications` + đẩy realtime |
| **Cài đặt**: màu chủ đạo (Lam/Ngọc/Đồng), mật độ, mục tiêu tuần, mẫu checklist | Mới có chế độ sáng/tối/hệ thống | Ba màu thay thế **chưa đo tương phản WCAG AA**: đo trước khi đưa vào |
| **Nhân sự** (tải: Rảnh/Vừa sức/Bận/Quá tải, KPI) | Tải suy ra được từ việc mở/quá hạn; KPI ở module hr | Dựng sau khi chốt công thức tải |
| **Mobile M1–M11**: vuốt hoàn thành/hoãn, sheet tạo nhanh, nhấn giữ, chọn nhiều, Eisenhower, Lịch | Mới có tab dưới + Thêm + Hôm nay/Việc theo ngôn ngữ mới | Theo từng màn, kèm thao tác cảm ứng |

Ghi chú khác: dòng việc chỉ hiện nhãn ưu tiên Gấp/Cao (Thường/Thấp ẩn cho đỡ nhiễu; thiết kế hiện cả ba); không có nút tick hoàn thành vì hoàn thành đi qua nộp kết quả/duyệt; ô tìm kiếm trên thanh trên chuyển sang danh sách việc với từ khóa (chưa phải tìm toàn cục theo dự án/người/công văn).

## Kiểm thử
`make ui` dựng lại `web/public`; `make test-web` (21 bước) đạt. Ảnh chụp kiểm tra bằng Chrome không giao diện với dữ liệu giả lập (tối/sáng, desktop/mobile).

## Hoàn tác
Giai đoạn 1 và 2a chỉ là mã tĩnh: triển khai lại bản trước và khởi động lại `eos-web`. Giai đoạn 2b/2c có migration 0025 (cột thêm, tương thích ngược): giao diện cũ vẫn chạy với CSDL mới; muốn gỡ cột, xem lệnh down ở đầu `db/migrations/0025_task_flags_start.sql`.

## Thứ tự triển khai giai đoạn 2b/2c
1. Sao lưu `pg_dump -Fc eos`. 2. Áp migration `0025_task_flags_start.sql` TRƯỚC. 3. Đưa mã web lên (`push_to_host.sh`) và khởi động lại `eos-web`. (Giao diện mới gọi `app_task_save` với `important`/`urgent`/`start_date`: nếu mã chạy trước migration, lưu việc báo lỗi.)
