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

Chương trình ngoài (cấu hình bằng biến môi trường, không đoán đường dẫn): LibreOffice (`SOFFICE_BIN`) để đọc `.doc/.xls/.ppt`. Trên Linux: `apt install libreoffice-core libreoffice-writer libreoffice-calc`. `pandoc` và Tesseract (`PANDOC_BIN`, `TESSERACT_CMD`) chưa cần ở bản này (OCR là Pha 2–3).

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
- PDF: từng trang có dấu `[[trang N]]`; trang có ≥ 30 ký tự lớp chữ lấy chữ bằng pymupdf4llm; trang không có chữ được đánh dấu "cần OCR" (OCR là Pha 3).
- `00_MUC_LUC.md`: dòng tổng đúng mẫu runner (`Tổng N file: … đã có Markdown, … file có trang cần soát OCR, … lỗi.`), bảng tệp, và các mục: Cần soát, Lỗi, Không chuyển đổi, Đã đổi tên (ký tự Windows cấm).
- Không tải, chỉ ghi tên/đường dẫn/link: `.dwg .dxf .dgn`, video, nén, tệp thiết kế, lối tắt Google, tệp quá `MAX_SOURCE_MB`. Thư mục `_md_deo` và tệp tạm (`~$`, `desktop.ini`) luôn bị bỏ qua.
- Thư mục tạm xóa sau mỗi dự án kể cả khi lỗi; `fetch`/`run` chỉ xóa bên trong `WORK_DIR`.

## Kiểm thử
```
python -m unittest discover -s pipeline/test        # PYTHONUTF8=1 trên Windows
```
CI (job `pipeline`, ubuntu-24.04, có LibreOffice) chạy cùng bộ test và test runner.

## Chưa có (pha sau)
Benchmark và chọn model OCR (Pha 2); OCR từng trang, ảnh (nén, HEIC), độ tin cậy từng trang (Pha 3).
