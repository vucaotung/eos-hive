---
name: enterprise-os-guide
description: Dùng Enterprise OS (work.enterpriseos.bond) thay Ever Teams - hướng dẫn người dùng đăng nhập, giao việc, duyệt, xem kết quả dự án; và cách gọi công cụ eos_* để xem, tạo, sửa việc, lấy bản tin cho Mai và các bot Hermes. Luôn xác nhận trước khi tạo việc giao người khác.
version: 1.0.0
author: Tổ Ong (eos-hive)
license: MIT
metadata:
  hermes:
    tags: [Enterprise OS, công việc, hướng dẫn, Mai]
---

# Enterprise OS: hướng dẫn và công cụ

Enterprise OS là nơi **người và AI agent cùng làm việc**: giao việc, theo dõi, duyệt, hồ sơ dự án, kho tri thức. Web: **https://work.enterpriseos.bond/app** (đăng nhập bằng Google). Thay hoàn toàn Ever Teams (đã gỡ).

## Hướng dẫn người dùng (mỗi tin 1–3 bước, hỏi lại đã thấy màn hình chưa)
- **Vào hệ thống**: chỉ bằng **mã mời** (8 ký tự) hoặc link mời do quản trị/trưởng phòng gửi (vd. `…/app/#/login?code=XXXXXXXX`). Mở link, bấm **Đăng nhập với Google**, nhập mã nếu được hỏi. Không tự đăng ký. Chưa có mã: nhắn anh Tùng kèm email Google. **Không bao giờ nhận hay giữ hộ** mã mời, mật khẩu, mã MCP của ai trong chat.
- **Màn hình**: Hôm nay (việc của tôi, chờ tôi duyệt, quá hạn) · Việc (danh sách/bảng, lọc) · Dự án (tiến độ, **Xem kết quả**: danh mục hồ sơ, báo cáo, kho tri thức) · Duyệt · Báo cáo · Quản trị · Tài khoản (thư mục Drive, Kết nối AI).
- **Giao việc**: nút **Giao việc** → tên việc, phòng, người phụ trách, hạn, ưu tiên, dự án, **Duyệt kết quả** (*Không cần duyệt* hoặc *Phải duyệt*: nộp xong chờ người giao duyệt rồi mới hoàn thành), và có thể **giao cho agent AI** (Văn thư soạn công văn, Điều phối...).
- **Thư mục Drive**: Tài khoản → Thư mục Drive; chia sẻ quyền **Người chỉnh sửa** cho tài khoản agent hiện trên màn hình đó để agent lưu tệp kết quả.
- Việc đang giao cho agent: agent hỏi lại thì **trả lời trong việc** (không bấm Nộp). Kết quả có nút **Mở: <tên tệp>** ở khối Kết quả.

## Công cụ (cho bot: Mai, ks-kinh-te-xd, ...)
| Việc | Công cụ |
| --- | --- |
| Việc của người đang hỏi / hôm nay | `eos_my_day`, `eos_list_tasks` (box assigned, created, review...) |
| Chi tiết một việc | `eos_get_task` |
| Bản tin hằng ngày/tuần | `eos_company_digest` (days=1 hoặc 7). Bản tin sáng 08:00 tự động gửi qua Telegram |
| Đổi tên người thành email | `eos_list_members` |
| Tạo / sửa việc | `eos_task_save` (không id = tạo; `id` = "T-123" = sửa) |
| Bình luận | `eos_comment` |

### Quy tắc tạo việc (`eos_task_save`)
1. **Xác nhận trước**: nhắc lại "tạo việc <tên> giao <người> hạn <ngày>, <phải duyệt/không>?" rồi mới gọi, trừ khi chính anh Tùng ra lệnh rõ ràng.
2. Người phụ trách: tra `eos_list_members`, dùng **email**. Trùng tên hoặc không có thì hỏi lại, không đoán.
3. Việc cần người khác kiểm: `approval: true`. Việc nhỏ tự làm: bỏ qua.
4. Giao cho agent AI: `agent` = `van-thu` (soạn công văn NĐ 30), `quan-tri-du-lieu` (kho tri thức), `nhan-su`, `dieu-phoi` (việc nhiều bước cần chia). Hồ sơ cả dự án: do quản trị bấm **Dự án → Nạp hồ sơ dự án** trên web, bot không tự bắt đầu.
5. Dự án: `project` = mã/tên dự án có sẵn; không có thì hỏi, không tự tạo.
6. Sau khi tạo: trả **mã T-số** và link `https://work.enterpriseos.bond/app/`. Việc tạo mang danh tính chủ mã (không phải người nhắn Zalo): ghi tên người yêu cầu vào `description`.
7. **Không** đánh dấu xong, duyệt, hủy hay xóa thay người khác (không có công cụ duyệt cho bot).

## Khi có sự cố
Việc đứng yên: xem bình luận cuối; agent đang hỏi thì nhắc người phụ trách trả lời. Thiếu thư mục Drive: nhắc thiết lập. Còn lại: báo anh Tùng, kèm mã T-số.
