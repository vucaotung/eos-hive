# Nhóm hồ sơ và mẫu tổng hợp

## Nhóm (category) gợi ý — dùng đúng tên để danh mục thống nhất
Pháp lý dự án · Quy hoạch và đất đai · Hợp đồng · Thiết kế và dự toán · Thanh toán và quyết toán · Công văn đến · Công văn đi · Biên bản và họp · Báo cáo · Khác
(Tên nhóm tự tạo nếu chưa có; không đặt nhóm mới khi một nhóm trên đã đủ nghĩa.)

## Trường nên có
- `record_no`: số hiệu trên văn bản (ví dụ "1475/QĐ-UBND"); không có thì để trống.
- `title`: tên/trích yếu ngắn, đủ phân biệt.
- `issued_on`, `expires_on`: YYYY-MM-DD, chỉ khi văn bản ghi rõ.
- `contract_value`, `executed_value`: đồng, số nguyên; chỉ với hợp đồng/thanh toán có số liệu trong tệp.
- `description`: 1–3 câu: nội dung chính, bên liên quan, nghi vấn (ví dụ "hai bản có số liệu khác nhau").
- `drive_id`: id tệp Markdown nguồn.

## Mẫu bản tổng hợp (Markdown)
```
# Tổng hợp hồ sơ dự án <tên>
Ngày lập: <ngày> · Phạm vi: <stage, paths, doc_types> · Người lập: Văn thư AI

## 1. Tóm tắt (tối đa 10 dòng)
## 2. Văn bản theo nhóm
### Pháp lý dự án
- <số hiệu> <tên> (<ngày>): <ý chính một câu> [tệp-nguồn.md]
### Hợp đồng ...
## 3. Mốc thời gian quan trọng
| Ngày | Sự kiện | Nguồn |
## 4. Số liệu chính và các chỗ mâu thuẫn
| Chỉ tiêu | Giá trị A [nguồn] | Giá trị B [nguồn] | Ghi chú |
## 5. Tệp không đọc được / thiếu và đề nghị xử lý
```
