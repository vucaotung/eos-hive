# 21 · OCR tiếng Việt: kết quả benchmark Pha 2

Tóm tắt kết quả đo của Pha 2 (v0.6, plan "Agent Quản trị dữ liệu") dùng để chọn công cụ OCR cho trang scan trong pipeline hồ sơ (`pipeline/`, xem `pipeline/README.md`). Nguồn: nhật ký đo trên máy Z2 (`ops-log/pha2-benchmark.md`, ngày 2026-11-16, tệp cục bộ không đưa vào git). Tài liệu này không chứa tên thư mục khách hàng, tên tệp hay đoạn văn bản thật từ hồ sơ; nhận xét về chất lượng đầu ra là mô tả định tính. Chỗ nhật ký không có số thì ghi "không có trong ops-log".

Quyết định đã chốt dựa trên kết quả này: **Tesseract `vie` (bản best) là OCR chính**, PaddleOCR bị loại (`docs/20` mục 1, `CHANGELOG.md`).

## Số đo Pha 2

### Công cụ và phiên bản
- Máy đo: Z2_Workstation, 4 core, 15,9 GB RAM, CPU (không dùng GPU). Môi trường Python riêng (venv), Python 3.12.10. Độ phân giải render trang: 300 dpi.
- PaddleOCR: `paddlepaddle` 3.2.0 (CPU, cài từ chỉ mục paddlepaddle.org.cn), `paddleocr` 3.7.0, `paddlex` 3.7.2, `numpy` 2.3.5, `opencv-contrib` 4.10.0.84.
- Tesseract: 5.4.0 (bản UB-Mannheim), dữ liệu ngôn ngữ `vie.traineddata` bản best (11,9 MB, kho `tesseract-ocr/tessdata_best`), chế độ phân trang `psm 3`, chạy với `TESSDATA_DIR` trỏ tới thư mục dữ liệu riêng.
- Mô hình PaddleOCR thực sự được chọn khi yêu cầu `lang=vi`:

| Yêu cầu | Cặp mô hình phát hiện + nhận dạng | Ghi chú |
|---|---|---|
| PP-OCRv5 `lang=vi` | `PP-OCRv5_server_det` + `latin_PP-OCRv5_mobile_rec` | mô hình Latin dùng chung, không riêng cho tiếng Việt |
| PP-OCRv6 `lang=vi` | `PP-OCRv6_medium_det` + `PP-OCRv6_medium_rec` | `vi` có trong danh sách ngôn ngữ của `paddleocr` 3.7.0 |

### Mẫu đo
- Tesseract `vie`: **20 trang scan khổ A4**, chọn tự động từ một thư mục hồ sơ dự án (không ghi đường dẫn ở đây).
- PP-OCRv5: **3 trang A4**. PP-OCRv6: **2 trang A4**.
- Tiêu chí chọn trang chi tiết (ngưỡng lớp chữ, giới hạn khổ giấy): không có trong ops-log.
- Ngoài mẫu A4, ops-log có ghi một phép đo trên trang khổ lớn (ảnh 10200x7000 px, bản đồ). Số trang khổ lớn đã đo: không có trong ops-log.
- Không có bản gõ đúng (ground truth) của người dùng, nên **chưa tính được CER** (xem "Chưa đo được").

### Tốc độ, RAM, độ tin cậy
Số trên Z2 (4 core CPU), chỉ mang tính tham khảo: production là VPS 169, phần cứng khác.

| Model | Giây/trang | RAM đỉnh | Độ tin cậy TB | Số trang đo |
|---|---|---|---|---|
| Tesseract `vie` (best, psm 3) | 3,1 | ~307 MB (~0,3 GB), kể cả tiến trình con | 0,906 | 20 trang A4 |
| PP-OCRv5 (`server` det) | 41–44 (~42) | ~5,8 GB | 0,85–0,96 (xem ghi chú) | 3 trang A4 |
| PP-OCRv6 medium | 94–117 (~105) | ~3,9 GB | 0,85–0,96 (xem ghi chú) | 2 trang A4 |

Ghi chú:
- Độ tin cậy của PaddleOCR trong ops-log chỉ có khoảng chung 0,85–0,96 cho cả hai mô hình; số riêng từng mô hình: không có trong ops-log.
- **Độ tin cậy của PaddleOCR vẫn cao dù đầu ra thiếu chữ có dấu**, nên không dùng nó làm cổng "cần soát" nếu chọn Paddle.
- Tesseract: 4/20 trang không có chữ (độ tin cậy trống, trang trắng hoặc gần trắng).
- Trang khổ lớn (10200x7000 px) với PP-OCRv5: 62–67 giây/trang, RAM đỉnh 6,7 GB. Pipeline phải giảm độ phân giải trang khổ lớn.
- VPS 169 có 7,8 GB RAM (đang dùng 1,6 GB), nên hai mô hình PaddleOCR quá nặng nếu không giảm dpi hoặc dùng bản mobile.
- Cách đo RAM của PaddleOCR (có tính tiến trình con hay không): không có trong ops-log.

### Độ phủ bảng ký tự của bộ nhận dạng
Đo trực tiếp từ tệp cấu hình `inference.yml` của từng mô hình. Mốc so sánh: **134 chữ Việt có dấu** (hoa và thường) ở dạng dựng sẵn (NFC). Không bảng nào có dấu rời (ký tự kết hợp), nên chữ nào không có trong bảng thì mô hình **không thể xuất ra**.

| Bộ nhận dạng | Số ký tự trong bảng | Chữ Việt có dấu có | Chữ thiếu (một phần) |
|---|---|---|---|
| `latin_PP-OCRv5_mobile_rec` | 772 | 44/134 | ạ ả ấ ầ ẩ ẫ ậ ắ ằ ẳ ẵ ặ ẹ ẻ ẽ ế … (không có ạ, ộ, ế) |
| `PP-OCRv6_medium_rec` | 18708 | 46/134 | ạ ả ấ ầ ẩ ẫ ậ ắ ằ ẳ ẵ ặ ẹ ẻ ẽ ế … (không có ạ, ộ, ế; có Ạ) |
| Tesseract `vie` | không có trong ops-log | không có trong ops-log | không có trong ops-log |

Cả hai bảng của PaddleOCR đều không thể xuất ra phần lớn chữ có dấu nặng, hỏi, ngã và chữ mũ kèm dấu. Quan sát đầu ra thật khớp với số đo này: PaddleOCR làm rơi ký tự có dấu, còn Tesseract đọc đúng nhiều dấu và chỉ còn lỗi lẻ.

### Số đo thay thế khi chưa có bản gõ đúng: tỉ lệ chữ cái có dấu
Với mỗi trang, đếm số chữ cái trong đầu ra và tỉ lệ chữ cái mang dấu. Tiếng Việt thường có khoảng 30% chữ cái mang dấu (theo ops-log).

| Trang mẫu | Tesseract `vie` | PP-OCRv5 `vi` | PP-OCRv6 |
|---|---|---|---|
| 1 | 1612 chữ cái, 29% có dấu | 1417, 13% | 1466, 14% |
| 2 | 959, 29% | 921, 17% | 927, 17% |

Tesseract khớp mức kỳ vọng, PaddleOCR chỉ bằng khoảng một nửa và đầu ra còn ít chữ cái hơn (bị bỏ rơi chữ).

### Chưa đo được
- CER, lỗi dấu theo ký tự, số tiền và số hiệu văn bản đọc sai: cần bản gõ đúng do người dùng cung cấp (script đo đã có trong `pipeline/bench/`, chạy khi có dữ liệu).
- Tesseract bản `fast`, các giá trị `psm` khác, giảm độ phân giải render: chưa thử.
- Đo lại trên VPS 169 (phần cứng khác Z2): không có trong ops-log.

## Kết luận
- **Tesseract `vie` (bản best) làm OCR chính** ở Pha 3: đọc đúng tiếng Việt hơn PaddleOCR theo hai bằng chứng độc lập (độ phủ bảng ký tự và tỉ lệ chữ có dấu trong đầu ra), nhanh hơn 14–35 lần, RAM thấp (~0,3 GB) phù hợp VPS 169 (7,8 GB).
- PP-OCRv5 `vi` và PP-OCRv6 bị loại cho tiếng Việt: bảng ký tự chỉ có 44/134 và 46/134 chữ có dấu, chậm, tốn RAM, và độ tin cậy báo cao khi đã mất chữ.
- Trang OCR có độ tin cậy thấp được đưa vào mục "Cần soát" của mục lục (ngưỡng và cách làm: `pipeline/README.md`).
- Mức chính xác tuyệt đối (CER) của Tesseract trên bản scan thật vẫn chưa xác nhận; chờ bản gõ đúng.
