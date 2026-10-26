# 18 · Giao diện Nocturne (thiết kế lại): tiến độ dựng và khoảng cách dữ liệu

Nguồn thiết kế: gói bàn giao Claude Design (26/10/2026) đã chép vào `design/` (tham chiếu, **không phải mã production**; mở bằng `npx serve design`). Đặc tả đầy đủ: `design/README.md`. Công cụ DesignSync không dùng được trong phiên không tương tác (cần `/design-login`), nên nhập từ tệp zip người dùng cung cấp.

## Đã dựng (giai đoạn 1, nhánh `feat/nocturne-ui`)
| Hạng mục | Trạng thái |
| --- | --- |
| Token Nocturne sáng/tối, ánh xạ vào biến HeroUI (`web/ui/src/app.css`), màu ngữ nghĩa thành lớp Tailwind (`text-ai`, `bg-dg-bg`, `text-faint`…), focus 2px, nút chính là **viền** màu nhấn | Xong. Mặc định chế độ **tối**; "Theo hệ thống" vẫn chọn được (Tài khoản). |
| Font Inter (vietnamese + latin + latin-ext, 400/500/600), bỏ Be Vietnam Pro; tiêu đề tối đa 500–600 | Xong |
| Hệ mã hoá trạng thái (hình + màu + chữ, icon Phosphor): pill viền, "Vướng" là huy hiệu vuông, "Chờ người trả lời", ưu tiên có icon, hạn có icon (quá hạn đỏ, ≤3 ngày vàng) | Xong (`components/ui.jsx`) |
| Người vs AI: avatar tròn cho người; **avatar vuông + sparkle + nhãn "AI"** cho agent | Xong (`AgentChip`) |
| Dòng việc (`TaskRow`): icon trạng thái trái, dải đỏ + nền đỏ nhạt khi quá hạn, gạch ngang khi xong, ô màu dự án | Xong |
| Khung: sidebar 240px 3 nhóm (Việc của tôi / Quản lý / Góc nhìn), topbar (công ty · tìm kiếm → danh sách việc · "+ Giao việc"), tab dưới mobile 5 mục có nút tạo nhanh viền accent, màn **Thêm** (M9) | Xong (`Shell.jsx`, `nav.js`, `pages/More.jsx`) |
| Hôm nay: ô chỉ số viền trên theo ngữ nghĩa; Việc: bộ lọc dạng pill, Kanban dùng ngôn ngữ mới | Xong |

## Khoảng cách giữa thiết kế và dữ liệu Enterprise OS (cần quyết định/backend trước khi dựng)
| Màn trong thiết kế | Điều còn thiếu | Đề xuất |
| --- | --- | --- |
| **Eisenhower** (và cờ ★ ⚡ trên mọi dòng) | `work.tasks` chưa có `important`/`urgent` | Migration thêm hai cột boolean + ghi vào `app_task_save`; kéo thả cập nhật cờ |
| **Sắp tới / Việc định kỳ / Bất cứ lúc nào / Backlog** | Không có quy tắc lặp; "không hạn" và "chưa giao" chỉ lọc được phía client | Nhóm theo `due_date`/`assignee_id` trước; định kỳ cần bảng quy tắc (có thể nối `agent.routines`) |
| **Kanban kéo thả** | Thiết kế 4 cột; EOS có 5 trạng thái (Vướng, Chờ duyệt) và luật duyệt: kéo vào "Xong" phải đi qua nộp/duyệt | Giữ 5 cột; chỉ cho kéo giữa Chờ làm/Đang làm/Vướng bằng `app_task_save`; "Xong" mở luồng nộp |
| **Lịch Tháng/Tuần/Ngày/Timeline** | Chỉ có `due_date` (không giờ, không thời lượng); chưa đồng bộ Google Calendar | Tháng/Tuần/Timeline làm được từ `start_date`/`due_date`; Ngày cần giờ bắt đầu và thời lượng |
| **Tổng quan** (burndown, dự báo rủi ro, mục tiêu tuần, chuỗi ngày) | Cần số liệu lịch sử và mục tiêu tuần; dự báo là việc của agent | `app_report` hiện có; thêm snapshot hằng ngày cho burndown |
| **Dự án: Danh sách / Mindmap / Gantt** | Có Kanban/tổng quan; chưa có 3 chế độ còn lại, việc con đã có (`parent_id`) | Dựng sau Danh sách việc |
| **Chi tiết việc, Form tạo** (panel 820px, AI tạo việc, @mention, nhật ký) | Có `TaskDrawer`/`TaskForm` cũ; chưa đổi sang bố cục mới | Giai đoạn 2 |
| **Trợ lý Hermes** (hỏi đáp trong web) | Chưa có API agent cho web; mọi hành động phải ghi `actor = agent` | Cần thiết kế riêng (quyền, ghi nhật ký) |
| **Thông báo (chuông)**, **chọn công ty dạng popover có số quá hạn** | Chưa có bảng thông báo; chọn công ty đã có (danh sách đơn giản) | Bảng `core.notifications` + đẩy realtime |
| **Cài đặt**: màu chủ đạo (Lam/Ngọc/Đồng), mật độ, mục tiêu tuần, mẫu checklist | Mới có chế độ sáng/tối/hệ thống | Ba màu thay thế **chưa đo tương phản WCAG AA**: đo trước khi đưa vào |
| **Nhân sự** (tải: Rảnh/Vừa sức/Bận/Quá tải, KPI) | Tải suy ra được từ việc mở/quá hạn; KPI ở module hr | Dựng sau khi chốt công thức tải |
| **Mobile M1–M11**: vuốt hoàn thành/hoãn, sheet tạo nhanh, nhấn giữ, chọn nhiều, Eisenhower, Lịch | Mới có tab dưới + Thêm + Hôm nay/Việc theo ngôn ngữ mới | Theo từng màn, kèm thao tác cảm ứng |

Ghi chú khác: dòng việc chỉ hiện nhãn ưu tiên Gấp/Cao (Thường/Thấp ẩn cho đỡ nhiễu; thiết kế hiện cả ba); không có nút tick hoàn thành vì hoàn thành đi qua nộp kết quả/duyệt; ô tìm kiếm trên thanh trên chuyển sang danh sách việc với từ khóa (chưa phải tìm toàn cục theo dự án/người/công văn).

## Kiểm thử
`make ui` dựng lại `web/public`; `make test-web` (21 bước) đạt. Ảnh chụp kiểm tra bằng Chrome không giao diện với dữ liệu giả lập (tối/sáng, desktop/mobile).

## Hoàn tác
Giao diện chỉ là mã tĩnh: triển khai lại bản trước (`v0.2.6`) và khởi động lại `eos-web`. Không có thay đổi CSDL.
