# Kế hoạch chia việc chuẩn cho quy trình project-intake

Thứ tự và phụ thuộc (chỉ số `after` tính từ 0 trong danh sách của một lần `eos_delegate`):

| # | agent | skill | scope tối thiểu | after | Kết quả mong đợi |
| --- | --- | --- | --- | --- | --- |
| 0 | `ho-so-runner` | `xu-ly-ho-so` | `{"stage":"fetch_convert"}` | | Markdown + mục lục trên thư mục md, tệp đã đăng ký, báo cáo số tệp/lỗi/OCR |
| 1 | `quan-tri-du-lieu` | `kb-quan-tri-du-lieu` | `{"stage":"data_quality"}` | [0] | Báo cáo chất lượng dữ liệu, đề xuất cấu trúc KB và bộ sự thật chính |
| 2 | `van-thu` | `ho-so-danh-muc` | `{"stage":"catalog"}` (thêm `doc_types` nếu người theo dõi chỉ định) | [0] | Danh mục hồ sơ (doc.records) + bản tổng hợp văn bản (Markdown trên Drive) |
| 3 | `phap-che` | `ra-soat-phap-che` | `{"stage":"legal","doc_types":["phap-ly","hop-dong"]}` | [0, 2] | Báo cáo rà soát: rủi ro, thiếu sót, mốc hạn |
| 4 | `ho-so-runner` | `xu-ly-ho-so` | `{"stage":"kb_ingest"}` | [1, 2] | Nạp kho tri thức (người duyệt bước nạp), ghi mã KB và nguồn đã nạp |

Ghi chú:
- `phap-che` có thể chưa bật cho công ty: nếu `eos_delegate` báo "chưa bật cho công ty", bỏ việc 3 và ghi rõ vào bản tổng hợp, đừng thay bằng agent khác.
- Người theo dõi có thể giới hạn: chỉ một phần thư mục (`paths`), chỉ một số loại tài liệu (`doc_types`). Chép nguyên vào scope các việc liên quan.
- Chia **một lần**: sau khi chia, việc gốc chờ các việc con (không chia thêm cho đến khi chúng xong).
