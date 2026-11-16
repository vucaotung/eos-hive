# Mẫu báo cáo rà Wiki

Bộ kiểm tham chiếu `ops/wiki_lint.py` sinh đúng định dạng này; `validate_report` trong cùng tệp kiểm định dạng.

```markdown
# Báo cáo rà Wiki — <tên KB> — <YYYY-MM-DD>

## Tóm tắt
Cao: N · Trung bình: N · Thấp: N · Trang đã rà: N · Tài liệu đối chiếu: N

## Mức Cao

### [W-01] <tên loại> — loại: <mã loại>
- Trang: <tên trang (nhiều trang cách nhau " / ")>
- Nguồn: <[tên-tệp] hoặc trang Wiki; với số liệu: giá trị ← nguồn, cách nhau ";">
- Mô tả: <vấn đề>
- Đề nghị: <việc nên làm; người quản trị Wiki thực hiện>

## Mức Trung bình
...
## Mức Thấp
...

## Đề xuất đưa vào Fact Registry
| Chỉ tiêu | Giá trị (nguồn) | Đề xuất |
| --- | --- | --- |

## Không kiểm được
- <phép kiểm không làm được và lý do, hoặc "không">
```

## Mã loại và mức nghiêm trọng mặc định
| Mã loại | Nghĩa | Mức mặc định |
| --- | --- | --- |
| `so_lieu_mau_thuan` | cùng chỉ tiêu, giá trị khác nhau, chưa đánh dấu "mâu thuẫn" | Cao |
| `thieu_buoc` | tổng quan thiếu bước, hoặc ghi "đã có" không dẫn văn bản | Cao khi "đã có" không dẫn văn bản; Trung bình khi thiếu bước |
| `link_hong` | liên kết nội bộ trỏ trang không tồn tại | Trung bình |
| `chi_muc_lech` | tài liệu đã nạp không trang nào nhắc; trang trích tài liệu đã bị thay | Trung bình |
| `trung_chu_the` | hai trang cùng chủ thể | Trung bình |
| `trang_cu` | trang cũ hơn tài liệu nguồn mới nạp | Trung bình |
| `orphan` | trang mồ côi | Thấp |

Người theo dõi có thể nâng/hạ mức; agent giữ mức mặc định trừ khi có lý do ghi trong báo cáo.

## Chỉ tiêu cần kiểm số liệu mâu thuẫn
Tổng mức đầu tư (kinh phí), diện tích, ngày cấp phép; mở rộng khi trang có thêm chỉ tiêu dạng "Tên chỉ tiêu: giá trị" (ngày khởi công, giá hợp đồng, số quyết định…). Giá trị "khác nhau" tính sau khi bỏ dấu và khoảng trắng thừa; đơn vị khác nhau (tỷ/triệu) cũng báo để người xác nhận.
