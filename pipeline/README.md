# pipeline — xử lý hồ sơ dự án thành Markdown

Python thuần (3.12), chạy được trên **Windows** (phát triển, benchmark) và **Linux** (VPS 169, production). Từ 0.6 thay cho `~/work/deo-sync` (bash + rclone), đã mất cùng bản Linux cũ của Z2.

```
nguồn (thư mục Drive) ──fetch──▶ WORK_DIR/src/<slug> + manifest/<slug>.json
                      ──run────▶ WORK_DIR/md/<slug>/…  (+ 00_MUC_LUC.md)
                      ──push───▶ <thư mục nguồn>/_md_deo trên Drive  (+ push/<slug>.json cho runner đăng ký)
```

## Cài đặt
Windows (Python từ python.org, **không** dùng bản Store/Chocolatey):
```powershell
py -3.12 -m venv .venv-pipeline
.\.venv-pipeline\Scripts\python.exe -m pip install -r pipeline\requirements.txt
```
Linux: `python3 -m venv venv && venv/bin/pip install -r pipeline/requirements.txt`.

Chương trình ngoài (cấu hình bằng biến môi trường, không đoán đường dẫn):
- LibreOffice (`SOFFICE_BIN`) để đọc `.doc/.xls/.ppt`. Linux: `apt install libreoffice-core libreoffice-writer libreoffice-calc`.
- **Tesseract (`TESSERACT_CMD`) kèm dữ liệu `vie` bản best** để OCR trang scan. Windows: `winget install UB-Mannheim.TesseractOCR` (cần quyền quản trị; bản cài mặc định chỉ có `eng`, `osd`). Linux: `apt install tesseract-ocr`. Dữ liệu `vie` bản best (≈12 MB) tải ở `github.com/tesseract-ocr/tessdata_best/raw/main/vie.traineddata`, đặt vào một thư mục cùng `eng.traineddata`, `osd.traineddata` và thư mục `configs/` (chép từ thư mục tessdata của Tesseract), rồi đặt `TESSDATA_DIR` trỏ tới thư mục đó. Gói apt `tesseract-ocr-vie` là bản fast. Không có Tesseract thì pipeline vẫn chạy: trang scan được đánh dấu "cần OCR" trong mục lục.
- Vì sao Tesseract mà không phải PaddleOCR: bảng ký tự của PP-OCRv5/v6 chỉ có 44–46/134 chữ Việt có dấu; Tesseract `vie` đọc đúng nhiều dấu, nhanh hơn 14–35 lần, RAM ~0,3 GB (`ops-log/pha2-benchmark.md`).
- `pandoc` (`PANDOC_BIN`) chưa cần.

## Biến môi trường
Xem `pipeline/.env.example` (sao thành `pipeline/.env`, tệp này nằm trong `.gitignore`; hoặc đặt `DEO_ENV_FILE`). Chính: `WORK_DIR` (đặt ngắn, ví dụ `C:\eos-work`, vì đường dẫn Drive tiếng Việt lồng sâu dễ vượt 260 ký tự), `SOFFICE_BIN`, `MAX_SOURCE_MB`, `PDF_TEXT_MIN_CHARS`, và `GOOGLE_CLIENT_ID/SECRET/REFRESH_TOKEN` (chỉ khi dùng Drive API). Không có bí mật trong mã.

## Chạy thử một dự án nhỏ (không cần khóa Google)
Trên Z2, Drive for Desktop gắn ổ `G:`:
```powershell
$env:PYTHONUTF8='1'; $env:WORK_DIR='C:\eos-work'
$py = '.\.venv-pipeline\Scripts\python.exe'
& $py -m pipeline fetch kdc-thanh-lap-mau --source-dir 'G:\My Drive\<thư mục nguồn>'
& $py -m pipeline run   kdc-thanh-lap-mau
# kết quả: C:\eos-work\md\kdc-thanh-lap-mau\  và 00_MUC_LUC.md
```
Trên VPS (Drive API): `python -m pipeline fetch <slug> <id thư mục Drive>`, `run <slug>`, `push <slug> <id thư mục Drive>`. Runner (`runner/eos_z2_runner.py`) gọi đúng ba lệnh này. Trên Linux còn có `fetch_drive.sh` và `run_project.sh` là lớp vỏ mỏng gọi CLI.

## Đầu ra (hợp đồng với MCP và runner)
- `md/<slug>/` có **cùng đường dẫn con** với nguồn. Hai nguồn cùng thư mục trùng tên gốc (a.docx, a.pdf) thành `a.docx.md`, `a.pdf.md`.
- Front matter, mỗi khóa một dòng `khóa: giá trị`: `project`, `drive_id`, `drive_link`, `duong_dan` (tên gốc trên Drive, dấu `/`), `md5`, `converter`, `route`, `converted_at`, `modified_time`, `so_trang`, `ocr_conf_tb`, **`buoc: ""`**, **`giai_doan: ""`** (luôn để trống; mã bước do `quan-tri-du-lieu` gắn sau, lưu ở CSDL). So với bản cũ: `drive_url`→`drive_link`, `source_path`→`duong_dan`, `sha256`→`md5`.
- PDF theo từng trang, mỗi trang có dấu `[[trang N]]`: trang có ≥ 30 ký tự lớp chữ lấy chữ bằng pymupdf4llm (route `A_native`); trang còn lại render 300 dpi (giảm cho trang khổ lớn) rồi OCR bằng Tesseract (route `B_ocr`). Trang OCR có độ tin cậy < 0,80 vào mục "Cần soát"; trang trắng (OCR không thấy chữ) không bị báo; `ocr_conf_tb` là trung bình các trang đã OCR. Không OCR được (thiếu Tesseract, trang lỗi) thì trang được đánh dấu và tệp ở route `C_scan`.
- Ảnh `jpg/jpeg/png/webp/heic/heif/tif/gif/bmp`: nén thành JPEG (cạnh dài ≤ 2000 px, chất lượng 85, tự giảm nếu > 10 MB), HEIC đổi sang JPEG, xoay đúng chiều, **giữ ngày chụp EXIF**; chép vào `md/<slug>/` cùng đường dẫn con với nguồn (đuôi `.jpg`). Ảnh trùng tên gốc với tệp khác cùng thư mục thành `a.png.jpg`. MCP lấy `buoc`/`duong_dan` của ảnh theo tệp `.md` cùng thư mục (cùng tên gốc, hoặc là `.md` duy nhất); ảnh không có `.md` đi kèm sẽ nạp không có mã bước.
- `00_MUC_LUC.md`: dòng tổng đúng mẫu runner (`Tổng N file: … đã có Markdown, … file có trang cần soát OCR, … lỗi.`; Tổng gồm cả ảnh và tệp không chuyển đổi), bảng tệp, và các mục: Cần soát (trang cần soát: OCR dưới ngưỡng và trang scan chưa OCR được), Ảnh, Lỗi, Không chuyển đổi, Đã đổi tên (ký tự Windows cấm).
- Không tải, chỉ ghi tên/đường dẫn/link: `.dwg .dxf .dgn`, video, nén, tệp thiết kế, lối tắt Google, tệp quá `MAX_SOURCE_MB`. Thư mục `_md_deo` và tệp tạm (`~$`, `desktop.ini`) luôn bị bỏ qua.
- Thư mục tạm xóa sau mỗi dự án kể cả khi lỗi; `fetch`/`run` chỉ xóa bên trong `WORK_DIR`.

## Kiểm thử
```
python -m unittest discover -s pipeline/test        # PYTHONUTF8=1 trên Windows
```
Test OCR thật chỉ chạy khi máy có Tesseract kèm `vie` (đặt `TESSDATA_DIR` nếu cần). CI (job `pipeline`, ubuntu-24.04, có LibreOffice, Tesseract `vie` và phông DejaVu) chạy cùng bộ test và test runner.

Benchmark OCR: `python -m pipeline.bench.ocr_bench` (venv riêng `pipeline/bench/requirements.txt`); kết quả Pha 2 ở `ops-log/pha2-benchmark.md`.

## Giới hạn đã biết
- Chưa có CER thật cho Tesseract: chờ bản gõ đúng của người dùng. Tesseract còn lỗi lẻ ("KÉT QUÁ", địa chỉ email); các trang như vậy được bắt bởi ngưỡng tin cậy 0,80.
- Chế độ `--source-dir` không có `drive_id`/`drive_link`; chế độ Drive API có.
- Bản scan xấu (con dấu, nghiêng) cho độ tin cậy thấp (mẫu: 0,45); tiền xử lý ảnh (nghiêng, nhị phân hóa) chưa làm.
