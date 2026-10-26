# 18 · Giao diện Nocturne (thiết kế lại): tiến độ dựng và khoảng cách dữ liệu

Nguồn thiết kế: gói bàn giao Claude Design (26/10/2026) đã chép vào `design/` (tham chiếu, **không phải mã production**; mở bằng `npx serve design`). Đặc tả đầy đủ: `design/README.md`. Công cụ DesignSync không dùng được trong phiên không tương tác (cần `/design-login`), nên nhập từ tệp zip người dùng cung cấp.

## Đã dựng (giai đoạn 1: nhánh `feat/nocturne-ui`; giai đoạn 2a: nhánh `feat/nocturne-ui-2`; giai đoạn 2b/2c: nhánh `feat/nocturne-ui-3`; giai đoạn 3: nhánh `feat/nocturne-ui-4`)
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
| **Tổng quan** (3): 6 ô chỉ số bấm được; "đã hoàn thành" so với mục tiêu theo Tuần/Tháng/Quý + chuỗi ngày + % đúng hạn; dự báo 7 ngày tới và danh sách rủi ro có lý do (tính từ dữ liệu, **không phải AI**); theo trạng thái; theo người (kèm hàng "Agent AI, không tính KPI"); burndown 14 ngày; ưu tiên theo dự án | Xong (`Overview.jsx`, `lib/stats.js`). Burndown suy từ `created_at`/`completed_at` (giả định không mở lại việc, chưa có bảng chụp hằng ngày). |
| **Nhân sự** (3): 4 ô chỉ số, biểu đồ hoàn thành trong tháng (đúng hạn/trễ), thẻ từng người (thước tải 4 nấc, việc bị chặn/chậm), thẻ agent AI (không KPI, không tải), **Xuất KPI** ra CSV | Xong (`People.jsx`). **Công thức tải là đề xuất:** điểm = việc mở + 2 × quá hạn + 2 × bị chặn; ≤2 Rảnh, ≤5 Vừa sức, ≤9 Bận, còn lại Quá tải. |
| **Dự án** (3): thẻ dự án mở trang dự án với tab **Kanban / Danh sách / Mindmap / Gantt** và thanh lọc chung (tìm, Của tôi, người làm, ưu tiên, hạn); Danh sách **sửa tại chỗ** (trạng thái, ưu tiên, người làm, hạn; việc con thụt lề); Mindmap gốc → việc → việc con; Gantt dùng Timeline một dự án | Xong (`Project.jsx`). Lưu qua `app_task_save`, máy chủ kiểm quyền. |
| **Sắp tới / Bất cứ lúc nào / Hoàn thành / Backlog** (3): nhóm theo ngày, theo trạng thái, theo thời điểm, theo dự án | Xong (bộ lọc mới của trang Việc + mục sidebar). **Việc định kỳ** chưa có (chưa có quy tắc lặp). |
| **Cài đặt** (3): màu chủ đạo Lam/Ngọc/Đồng, mật độ Vừa/Gọn, mục tiêu tuần (5–60) | Xong (Tài khoản). Lưu trong trình duyệt của thiết bị, không đổi dữ liệu công ty. **Đã ĐO tương phản WCAG:** accent/nền ≥ 5,45 ở 6 tổ hợp, chữ nhỏ trên nền accent-soft ≥ 4,5, chữ trên nút đặc ≥ 6,18; thấp nhất toàn bảng 5,42:1. Ghi chú "chưa đo" trong `design/README.md` đã lỗi thời. |
| **Mobile** (3): vuốt trái dòng việc (Hoãn 1 ngày / Đổi hạn, rung nhẹ) ở màn Hôm nay; nhấn giữ vào **chọn nhiều** + thanh thao tác (Đổi hạn, Giao cho, Bị chặn, Hủy việc) và nút "Chọn nhiều" trên web; Kanban cuộn có snap; Eisenhower thu gọn 2×2 + danh sách ô; chi tiết việc có tab Chi tiết / Trao đổi; form giao việc hiện như bottom sheet | Xong |
| **Form tạo/sửa việc** (giai đoạn 2a): modal 720px; mặc định chỉ tên, hạn, người phụ trách, dự án, ưu tiên, duyệt; **"Thêm chi tiết"** mở mô tả, phòng ban, quy trình duyệt, giao cho agent AI; **Ctrl+Enter** lưu, Esc đóng; phím **N** mở form (bỏ qua khi đang gõ) | Xong (`TaskForm.jsx`, `Shell.jsx`) |

## Còn lại: cần backend hoặc quyết định (chưa làm)
| Hạng mục thiết kế | Điều còn thiếu | Đề xuất |
| --- | --- | --- |
| **Việc định kỳ** | Không có quy tắc lặp | Bảng quy tắc lặp (có thể nối `agent.routines`) + sinh việc theo lịch |
| **Lịch Ngày** và **đồng bộ Google Calendar** | Việc chỉ có ngày (không giờ, không thời lượng); chưa có tích hợp Google | Giờ bắt đầu + thời lượng; OAuth và quyết định một chiều/hai chiều |
| **Tạo việc bằng AI** (stepper 3 bước) | Cần API phân tích mô tả thành việc + việc con, ghi `actor = agent` | Thiết kế riêng (quyền, xác nhận trước khi lưu) |
| **Trợ lý Hermes trong web** (nút nổi, hỏi đáp, M7) | Chưa có API agent riêng cho web | Thiết kế riêng, chỉ đọc dữ liệu người dùng được xem |
| **Thông báo (chuông)** | Chưa có bảng thông báo | `core.notifications` + đẩy realtime |
| **Chi tiết việc**: checklist + mẫu, đính kèm tệp ≤ 5 MB, nhật ký thay đổi, người theo dõi, lặp lại, thời lượng; menu gõ `@` chọn tên | `app_task` chưa trả các dữ liệu này (có bảng `work.checklist_items`, `task_watchers`, `audit_log` nhưng chưa nối) | Mở rộng `app_task`/`app_task_save` và bảng mẫu checklist |
| **Vuốt phải để hoàn thành**, pinch-zoom Gantt/Mindmap | Hoàn thành đi qua nộp kết quả/duyệt, không đóng bằng một cử chỉ; pinch cần thư viện cử chỉ | Quyết định có cho "Hoàn thành nhanh" với việc không cần duyệt không |
| **Kéo thả Kanban** | 5 trạng thái + luật duyệt (kéo vào "Xong" phải đi qua nộp) | Chỉ cho kéo giữa Chờ làm/Đang làm/Vướng |
| **Burndown thật** | Hiện suy từ ngày tạo/hoàn thành | Bảng chụp số liệu hằng ngày |

Ghi chú khác: dòng việc chỉ hiện nhãn ưu tiên Gấp/Cao (Thường/Thấp ẩn cho đỡ nhiễu; thiết kế hiện cả ba); không có nút tick hoàn thành vì hoàn thành đi qua nộp kết quả/duyệt; ô tìm kiếm trên thanh trên chuyển sang danh sách việc với từ khóa (chưa phải tìm toàn cục theo dự án/người/công văn).

## Kiểm thử
`make ui` dựng lại `web/public`; `make test-web` (21 bước) đạt. Ảnh chụp kiểm tra bằng Chrome không giao diện với dữ liệu giả lập (tối/sáng, desktop/mobile).

## Hoàn tác
Giai đoạn 1 và 2a chỉ là mã tĩnh: triển khai lại bản trước và khởi động lại `eos-web`. Giai đoạn 2b/2c có migration 0025 (cột thêm, tương thích ngược): giao diện cũ vẫn chạy với CSDL mới; muốn gỡ cột, xem lệnh down ở đầu `db/migrations/0025_task_flags_start.sql`.

## Thứ tự triển khai giai đoạn 2b/2c
1. Sao lưu `pg_dump -Fc eos`. 2. Áp migration `0025_task_flags_start.sql` TRƯỚC. 3. Đưa mã web lên (`push_to_host.sh`) và khởi động lại `eos-web`. (Giao diện mới gọi `app_task_save` với `important`/`urgent`/`start_date`: nếu mã chạy trước migration, lưu việc báo lỗi.)
