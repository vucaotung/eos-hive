# 21 · OCR cho hồ sơ scan: Pha 2 (benchmark) và lựa chọn Tesseract

> **Quyết định (18/11/2026, Tùng): giữ Tesseract `vie` (bản best) làm OCR của pipeline. Tùng quyết định không làm bản gõ đúng và không đo CER thật.** Hệ quả ghi ở mục "Giới hạn đã biết".

Tài liệu này ghi lại **căn cứ và giới hạn** của việc chọn OCR cho pipeline hồ sơ (v0.6). Mọi số liệu dưới đây lấy từ `pipeline/README.md` do phiên Z2 viết; **bằng chứng gốc (`ops-log/pha2-benchmark.md`) nằm trên máy Z2 và không có trong repo** (thư mục `ops-log/` nằm trong `.gitignore`). Ai đã có tệp đó nên đưa bản tóm tắt vào đây.

## Đã so sánh
Tesseract `vie` (bản best), PaddleOCR PP-OCRv5 `lang=vi` (mô hình Latin) và PP-OCRv6. Khung đo nằm ở `pipeline/bench/` (`ocr_bench.py`: giây/trang, RAM đỉnh gồm tiến trình con, độ tin cậy; CER, lỗi dấu, số tiền/số văn bản đọc sai khi có bản gõ đúng `truth`).

## Lý do chọn Tesseract (theo `pipeline/README.md`)
- Bảng ký tự của PP-OCRv5/v6 chỉ có **44–46 trên 134** chữ Việt có dấu, nên không thể ra đúng nhiều chữ.
- Tesseract `vie` đọc đúng nhiều dấu, **nhanh hơn 14–35 lần**, RAM khoảng **0,3 GB**.
- Số đo thời gian và RAM đo trên Z2 (Windows): chỉ tham khảo; production là CPU của VPS 169.

## Giới hạn đã biết
- **Không có CER thật, theo quyết định của Tùng (18/11/2026).** Kế hoạch ban đầu đo CER trên bản gõ đúng của 5 trang; Tùng quyết định không làm. Lựa chọn Tesseract dựa trên độ phủ bảng ký tự và tốc độ, nên **chưa có số đo tỉ lệ lỗi ký tự, lỗi dấu, số tiền hay số văn bản đọc sai** trên hồ sơ thật. Chất lượng được kiểm soát bằng ngưỡng tin cậy 0,80 (trang kém vào "Cần soát" cho người soát tay) và việc người theo dõi đọc lại các trang quan trọng. Nếu sau này phát hiện sai số tiền hoặc số hiệu mà độ tin cậy vẫn cao, cần xem lại: khung đo `pipeline/bench/` đã sẵn sàng chấm CER khi có bản gõ đúng.
- Còn lỗi lẻ ("KÉT QUÁ", địa chỉ email); trang có con dấu, nghiêng cho độ tin cậy thấp (mẫu 0,45). Chưa tiền xử lý ảnh (nghiêng, nhị phân hóa).
- Các trang dưới ngưỡng tin cậy **0,80** vào mục "Cần soát" của `00_MUC_LUC.md` (biến `OCR_REVIEW_BELOW`); đây là chỗ người soát tay.
- PP-OCRv6 (phát hành 2026-06) có thể cập nhật bảng ký tự sau; nên đo lại khi có bản mới.

## Việc còn lại
1. Cài Tesseract và dữ liệu `vie` (bản best) trên VPS 169: `prompts/60-trien-khai-v06.md` Bước 5.
2. Đưa tóm tắt `ops-log/pha2-benchmark.md` vào đây (mục "Số đo Pha 2"; tệp gốc nằm trên máy Z2, ngoài repo).
3. Tùy chọn, khi có bản gõ đúng: chạy lại `ocr_bench` với `truth` để có CER thật.

## Chạy lại benchmark (Z2 Windows, venv riêng)
```powershell
$env:PYTHONUTF8='1'
python -m pipeline.bench.ocr_bench --scan-dir "G:\My Drive\<thư mục có PDF scan>" --n 20
python -m pipeline.bench.ocr_bench --pages pipeline/bench/out/pages.json --models tesseract,ppocrv5,ppocrv6
```
`pages.json`: `[{"id": "kdc-001", "pdf": "đường/dẫn.pdf", "page": 3, "truth": "đường/dẫn/kdc-001.txt"}]` (`truth` tùy chọn).
