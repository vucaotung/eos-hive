# 70 · Handoff: làm Pha 0–3 trên Z2 (Windows 11 thuần, không WSL)

> **Trạng thái (17/11/2026): tài liệu lịch sử.** Phiên Z2 đã làm Pha 1–3 (pipeline Python, benchmark, OCR từng trang bằng Tesseract `vie`) và PR #14 đã merge vào `main`. Còn lại: CER thật (cần bản gõ đúng của Tùng) và Pha 8. OCR đã chốt là Tesseract, không phải PaddleOCR: xem `docs/21-ocr-pha2.md`. Các mục về PaddleOCR bên dưới không còn là kế hoạch.

Bản này thay các bản trước. **Z2 đã cài lại Windows 11 và sẽ giữ nguyên như vậy: không cài WSL, không Docker Desktop, không máy ảo Linux.** Hostname `Z2_Workstation`, user `vucao`. Bản Linux cũ, `~/work/deo-sync`, runner `eos-z2-runner` và cron sao lưu **đã bị xóa**.

Bạn là kỹ sư phát triển và triển khai cho dự án **Tổ Ong (eos-hive)**, repo `vucaotung/eos-hive`. Ngôn ngữ làm việc: **tiếng Việt**. Phiên cloud trước đã làm xong phần chỉ cần repo của plan v6 "Agent Quản trị dữ liệu" (bản 0.6.0). Phần còn lại cần máy thật nên giao cho bạn.

## 0. Môi trường: Windows thuần
**Nguyên tắc:** pipeline viết bằng **Python (không bash)** để chạy được trên Windows (phát triển, benchmark) và Linux (VPS 169, production). Mọi thứ cần Postgres/bash chạy bằng **CI của GitHub** (ubuntu-24.04), không chạy tại Z2.

Kiểm môi trường (PowerShell, chỉ đọc), rồi báo cho tôi:
```powershell
hostname; whoami; [System.Environment]::OSVersion.VersionString; (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB
Get-PSDrive C | Select-Object Used,Free; (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem').LongPathsEnabled
foreach ($c in 'git','python','py','node','rclone','tesseract','pandoc','ssh','gh') { "{0}: {1}" -f $c, ((Get-Command $c -ErrorAction SilentlyContinue).Source ?? 'THIẾU') }
Test-Path 'C:\Program Files\LibreOffice\program\soffice.exe'; tesseract --list-langs 2>$null | Select-String vie
Get-ChildItem $HOME\.ssh -Name 2>$null | Select-Object -First 5
```
Thiếu công cụ nào thì **đề xuất lệnh cài và chờ tôi đồng ý**; không cài lặng lẽ. Bộ công cụ **chạy được trên Windows** (mã gói winget phải kiểm bằng `winget search`, chưa xác minh):
| Cần | Công cụ trên Windows | Ghi chú |
| --- | --- | --- |
| Python | bản cài từ python.org (ví dụ 3.12; winget `Python.Python.3.12`) | **không dùng bản Chocolatey/Store**: wheel PyMuPDF không có cho bản Chocolatey |
| Tải/đẩy Drive | `rclone` (bản Windows) | tôi tự đăng nhập; bạn chỉ kiểm `rclone listremotes` (tên remote) |
| Chuyển docx/xlsx/pptx | LibreOffice (`soffice.exe --headless --convert-to`) + `pandoc` | đường dẫn cấu hình qua biến `SOFFICE_BIN`, `PANDOC_BIN`, không đoán |
| Render PDF, lấy chữ trang có lớp chữ | **PyMuPDF + pymupdf4llm** (`page.get_pixmap(dpi=300)`) | **không cần poppler** |
| OCR dự phòng/so sánh | Tesseract bản Windows (UB-Mannheim) + dữ liệu `vie` | biến `TESSERACT_CMD` |
| OCR chính (ứng viên) | `paddlepaddle` CPU + `paddleocr` | xem lưu ý bên dưới |
| Ảnh | Pillow + `pillow-heif` | HEIC → JPEG, giữ EXIF |
| Đo | `psutil` | đo RAM đỉnh bằng lấy mẫu (không dùng module `resource`, chỉ có trên Unix) |
| SSH tới VPS | OpenSSH có sẵn trong Windows 11 | khóa do tôi đặt |
| Node (test MCP nhẹ) | Node.js 22 | `node --test mcp/test/*.test.mjs` |
Lưu ý PaddleOCR (từ tài liệu và báo cáo tìm được; **kiểm trên máy**): tài liệu chính thức ghim `paddlepaddle==3.2.0` cho CPU (chỉ mục `https://www.paddlepaddle.org.cn/packages/stable/cpu/`); có báo cáo `paddlepaddle` CPU 3.3.1 lỗi oneDNN (`NotImplementedError`) với PaddleOCR 3.7.0, tránh bằng ghim 3.2.0 (cờ `enable_mkldnn=False` chạy được nhưng chậm hơn và có báo cáo tốn bộ nhớ). Python 3.12 trên Windows có người dùng báo chạy được (nguồn bên thứ ba). **PP-OCRv5 mặc định không có tiếng Việt**: `lang='vi'` chọn mô hình Latin (`latin_PP-OCRv5_mobile_rec`). **PP-OCRv6** đã phát hành (2026-06, PaddleOCR 3.7.0; medium/small 50 ngôn ngữ, tiny 49); nguồn bên thứ ba liệt kê `vi`, **cần kiểm trong từ điển của mô hình** trước khi đưa vào bảng so sánh.

Ràng buộc riêng của Windows (xử lý trong mã, không bỏ qua):
- **Đường dẫn dài:** thư mục Drive tiếng Việt lồng sâu dễ vượt 260 ký tự. Đặt `WORK_DIR` ngắn (ví dụ `C:\eos-work`), nhờ tôi bật `LongPathsEnabled` nếu cần (quyền quản trị).
- **Tên tệp:** Windows cấm `: * ? " < > |`, dấu chấm/khoảng trắng ở cuối, tên dành riêng (`CON`, `NUL`…); Drive cho phép. Ghi lại phép đổi tên và đưa vào mục lục; `duong_dan` vẫn lưu **tên gốc trên Drive**, dùng dấu `/` (`PurePosixPath`/`as_posix()`), không dùng `\`.
- **Mã hóa:** đặt `PYTHONUTF8=1`; mở/ghi tệp với `encoding='utf-8'`, `newline` rõ ràng; chuẩn hóa Unicode NFC cho tên tiếng Việt khi so sánh. Tệp shell/Python/SQL phải là LF (repo có `.gitattributes`).
- **Application Control:** công cụ Bash của Claude Code có thể bị chặn gọi `git.exe`; dùng PowerShell. Nếu một công cụ/Python bị chặn, **báo tôi**, không tìm cách vòng qua.
- Gọi chương trình ngoài bằng danh sách đối số (không qua shell), có `timeout`.
- Kiểm Linux thật: (1) CI chạy test pipeline trên ubuntu-24.04 (Pha 1 bạn thêm bước vào `.github/workflows/ci.yml`; Tesseract cài bằng apt, PaddleOCR đặt ở job tùy chọn vì nặng); (2) một lần chạy thử trên VPS 169 ở Pha 8 (có `Nice`, giới hạn bộ nhớ). Không có môi trường Linux tại Z2.

Bí mật: **tôi** đặt khóa SSH, đăng nhập GitHub và rclone. Bạn không xin, không in, không ghi khóa/token; chỉ kiểm tệp có tồn tại.

Sau đó:
```powershell
git clone https://github.com/vucaotung/eos-hive.git $HOME\src\eos-hive   # nếu chưa có; cần tôi đăng nhập GitHub trước
cd $HOME\src\eos-hive; git fetch origin; git checkout feat/v0.6-du-lieu; git pull; Get-Content VERSION   # kỳ vọng 0.6.0
```
Đọc trước, tuân thủ tuyệt đối: `prompts/00-MASTER.md` (luật về bí mật, an toàn thao tác, ranh giới, mẫu báo cáo ≤ 15 dòng), `docs/20-du-lieu-v06.md` (mục 1: bảng trạng thái), `docs/12`, `docs/13`, `docs/17`, `docs/02-guideline-phat-trien.md`, `prompts/60-trien-khai-v06.md`. Bản handoff này cũng nằm ở `prompts/70-handoff-z2-windows.md`.

## 1. Trạng thái
- Nhánh `feat/v0.6-du-lieu`, PR nháp https://github.com/vucaotung/eos-hive/pull/14. CI (workflow `ci`: test_db, test_mcp, test_web, test_runner, test_bridge, bản dựng giao diện, kiểm skill, kiểm migration) chạy trên mọi push; xem kết quả ở tab Actions của PR.
- **Pha 4–7 đã xong, không làm lại:** `eos_kb_ingest` nạp ảnh + `custom_metadata`; `kb.file_steps` + `eos_project_tag_step`; luồng pháp luật `eos_law_*`; agent `ks-kinh-te-xd`; 8 skill mới; việc định kỳ `wiki_lint`/`law_review` (không bật sẵn); migration 0031–0035; tài liệu; `VERSION` = 0.6.0.
- **Còn lại:** Pha 0, 1, 2, 3 (bạn làm trên Z2 Windows). Pha 8 (triển khai) chỉ khi tôi nói "triển khai".
- Làm tiếp trên `feat/v0.6-du-lieu`, mỗi pha một hoặc vài commit, push cùng nhánh. Không triển khai lên máy thật trước Pha 8.

## 2. Luật bổ sung của đợt này
- **DEO-INGEST-RULE giữ nguyên:** khóa WeKnora chỉ ở `.env` của máy chủ MCP trên VPS 169. Không đặt khóa WeKnora trên VPS 173, không cho Hermes gọi WeKnora để ghi. **Không xóa gì trong WeKnora** bằng mã mới.
- Mỗi thay đổi có test. Test pipeline là Python `unittest` (`python -m unittest discover -s pipeline/test`), chạy được trên Windows và CI Linux. `scripts/check_secrets.sh` cần bash: trên Z2 chạy bằng bản tương đương Python/PowerShell tạm thời hoặc để CI chạy (CI đã chạy bước này); **không commit khi chưa chắc không lộ bí mật**. Kết thúc mỗi pha: báo cáo theo mẫu `00-MASTER.md`, **chờ tôi nói "tiếp"**.
- Mặc định tôi chưa chốt (ghi "mặc định, chờ Tùng xác nhận"; đổi được bằng cấu hình): KB mẫu `_mau-du-an` (biến `WEKNORA_TEMPLATE_KB`); rclone trên VPS 169 là ai666; mã bước ở cột `doc.records.buoc`; KB pháp luật dùng chung `phap-luat`/`tieu-chuan`; ảnh nạp hết sau khi nén; `wiki_lint` thứ Hai, `law_review` ngày 1; allowlist `ks-kinh-te-xd` chỉ Telegram ID của Tùng.

## 3. Điều đã đổi do Z2 cài lại (cần biết trước khi làm)
1. **Mã nguồn `deo-sync` không có trong repo** (chỉ được tham chiếu). Có thể nó đã mất cùng bản Linux. **Việc đầu tiên của Pha 0: tìm bản sao.** Nơi có thể có (chỉ đọc): repo GitHub riêng `vucaotung/deo-os-z2` (private, push lần cuối 2026-10-08; tên gợi ý là kho cấu hình Z2, **chưa kiểm có chứa deo-sync không**; đọc cần tôi đồng ý, ví dụ tôi tự clone); `/opt`, home và `find / -name 'fetch_drive.sh' -o -name 'deo_md.py'` trên VPS 169 và VPS 173; Drive; ổ ngoài/sao lưu của tôi. Hỏi tôi nếu không thấy.
2. **Bản cũ có thể là bash (`fetch_drive.sh`, `run_project.sh`) + Python (`deo_md.py`).** Mặc định: **chuyển toàn bộ sang Python** (module `pipeline/` với CLI `python -m pipeline fetch|run`), vì bash trên Windows thuần phải qua Git Bash (dễ bị Application Control chặn, khác biệt đường dẫn/công cụ). Trên Linux có thể giữ `fetch_drive.sh`/`run_project.sh` là lớp vỏ mỏng gọi CLI Python để runner cũ vẫn chạy; sửa runner gọi CLI Python và cập nhật test. Hỏi tôi nếu bạn thấy cách khác tốt hơn.
3. **Không có "bản cũ" để chạy so sánh.** Cổng Pha 1 "kết quả giống bản cũ" đổi thành: so với **đầu ra cũ đã có trên Drive** (`_md_deo` của KDC Thành Lập do pipeline cũ sinh ra: so số tệp `.md` và `00_MUC_LUC.md`). Cần rclone tới Drive (tôi đăng nhập).
4. **Nếu không tìm được `deo-sync`: Pha 1 thành "dựng lại pipeline theo hợp đồng ở mục 4"** và gộp với Pha 3. Báo tôi quyết định trước khi viết (phạm vi lớn; các hành vi cũ không có trong hợp đồng, như danh sách loại trừ hay cách đặt tên, sẽ không biết; suy ra từ đầu ra cũ trên Drive).
5. **Mất sao lưu ngoài máy:** cron 04:00 kéo sao lưu VPS 169 về `~/backups/deo169` không còn; hiện sao lưu chỉ còn trên VPS 169 (`/var/backups/deo`). **Đề xuất dựng lại** (Task Scheduler + `scp`/`rclone` qua OpenSSH, hoặc máy khác) trước Pha 8; hỏi tôi. Bước sao lưu Pha 8 nên **kéo thêm một bản về Z2** trước khi nâng WeKnora. `make restore-drill` cũ (Docker trên Z2) không còn chạy được.
6. **Không còn runner Z2** làm đường lùi: rollback runner là tắt `eos-runner` trên VPS 169 (xem `prompts/60-trien-khai-v06.md`). Vì vậy pipeline phải qua test Linux của CI và một lần chạy thử cẩn thận ở Pha 8.
7. **Số đo benchmark (Pha 2):** CER và lỗi dấu không phụ thuộc phần cứng; **giây/trang và RAM đỉnh trên Z2 chỉ mang tính tham khảo** (khác VPS 169; Z2 có NVIDIA nhưng đích là CPU của VPS 169, dùng CPU). Sau khi chốt model, đo lại một lượt ngắn trên VPS 169 (venv riêng, `nice`, giới hạn bộ nhớ) **chỉ khi tôi đồng ý**, vì đó là máy đang chạy dịch vụ.

## 4. Hợp đồng pipeline ↔ runner ↔ MCP (suy từ `runner/eos_z2_runner.py` và `mcp/src`)
Runner gọi pipeline bằng danh sách đối số (không qua shell), với `DEO_SYNC_DIR` (mặc định hiện `~/work/deo-sync`; Pha 1 đổi mặc định thành `pipeline/` trong repo), `RCLONE_REMOTE` (mặc định `gdrive`), `WORK_DIR`. Bản cũ gọi:
- `bash fetch_drive.sh <slug> <id thư mục nguồn>`: tải thư mục nguồn của dự án về thư mục làm việc. `slug` khớp mẫu `SLUG` của runner; id khớp `SAFE_ID`.
- `bash run_project.sh <slug>`: chuyển đổi, sinh **`<WORK_DIR>/md/<slug>/`** (cây Markdown cùng đường dẫn con với nguồn) và **`00_MUC_LUC.md`** có đúng một dòng khớp biểu thức: `Tổng (\d+) file: (\d+) đã có Markdown, (\d+) file có trang cần soát OCR, (\d+) lỗi` (runner đọc 2000 ký tự đầu). Đường cũ `~/work/upload/<slug>/*.md` chỉ dùng cho đường dự phòng thủ công của giai đoạn `kb_ingest` của runner; giữ hoặc bỏ cùng lúc sửa runner và test.
- Runner rồi `rclone copy md/<slug> gdrive:_md_deo --drive-root-folder-id <nguồn>`, liệt kê tệp, đăng ký bằng `eos_runner_setup` (`drive_id`, `name`, `url` https, `mime`, `bytes`).
- Front matter mỗi `.md` (mỗi khóa một dòng, `khóa: giá trị`): `drive_id`, `drive_link`, `duong_dan` (**dấu `/`**), `md5`, `converter`, `ocr_conf_tb`, `so_trang`, **`buoc: ""`**, **`giai_doan: ""`** (để trống; mã bước do `quan-tri-du-lieu` gắn sau, lưu ở CSDL, không sửa lại tệp). MCP đọc `drive_link`, `duong_dan` (hoặc `source_path`), `buoc`, `giai_doan`, `pages` hoặc `so_trang`; `weknora.prepare` bỏ front matter khi nạp.
- Ảnh: nén cạnh dài ≤ 2000 px, JPEG chất lượng 85, HEIC đổi JPEG, giữ ngày chụp EXIF; chép vào `_md_deo` **cùng đường dẫn con**; tối đa 10 MB; `mime` đúng `image/*`. MCP lấy `buoc`/`duong_dan` của ảnh theo `.md` cùng thư mục (trùng tên gốc, hoặc là `.md` duy nhất không phải mục lục).
- MCP bỏ qua `00_*` và tệp bắt đầu bằng `_` khi nạp.

## 5. Việc cần làm

### Pha 0 — Khảo sát chỉ đọc (ghi vào `ops-log/`, không sửa gì)
1. **Z2 (Windows):** kiểm môi trường (mục 0). **Tìm bản sao `deo-sync`** (mục 3.1). Nếu tìm được: kê tệp, script, chỗ gọi Tesseract, bí mật (**chỉ tên tệp và tên biến, không giá trị**). Kiểm `rclone listremotes` (chỉ tên remote).
2. **VPS 169 (qua `ssh`):** `hostname; free -h; nproc; df -h /`; `docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'`; image tag WeKnora; `STORAGE_TYPE`, `MAX_FILE_SIZE_MB` (chỉ tên biến và giá trị không bí mật); danh sách KB qua API (tên và id) bằng khóa trong `mcp/.env` **không in khóa**.
3. **VPS 173:** `hermes profile list`; cấu hình profile `ks-kinh-te-xd` (chỉ in **tên khóa** của `config.yaml`: platforms, toolsets, mcp_servers, và tên tệp SOUL); SearXNG `127.0.0.1:8888` có trả JSON không.
SSH tới VPS: dùng bí danh `vps169`, `vps173` nếu có trong `%USERPROFILE%\.ssh\config`; thiếu thì hỏi tôi địa chỉ/user/đường dẫn khóa, **không đoán mật khẩu**.
Cổng: bản kê (hoặc xác nhận "không có bản sao"); RAM/CPU/ổ VPS 169; phiên bản WeKnora và danh sách KB; hiện trạng `ks-kinh-te-xd`; danh sách điều khác với giả định của plan.

### Pha 1 — Đưa pipeline vào git (bằng Python; hoặc dựng lại theo mục 4 nếu mất)
1. Có bản sao: chuyển vào `pipeline/` bằng Python, bỏ bí mật (thay bằng biến môi trường), thêm `pipeline/.env.example`. Không có: **dừng, báo quyết định** (mục 3.4).
2. Đường dẫn cứng đổi thành biến `DEO_SYNC_DIR`, `WORK_DIR`, `RCLONE_REMOTE`; đường dẫn chương trình ngoài qua `SOFFICE_BIN`, `PANDOC_BIN`, `TESSERACT_CMD`. Runner: mặc định `deo_sync` trỏ `pipeline/` nếu `DEO_SYNC_DIR` không đặt; giữ tương thích ngược (test runner hiện có phải vẫn đạt).
3. Viết `pipeline/README.md` (cài đặt trên Windows và Linux, biến môi trường, cách chạy thử một dự án nhỏ) và thêm bước test pipeline vào `.github/workflows/ci.yml`.
Cổng: không có bí mật trong tệp mới (CI chạy `check_secrets.sh`); chạy một folder thử, kết quả khớp đầu ra cũ trên Drive (số `.md`, mục lục); test pipeline xanh trên Z2 và trên CI Linux.

### Pha 2 — Benchmark OCR (trên Z2 Windows)
1. Venv riêng (`py -3.12 -m venv`), `paddlepaddle==3.2.0` (CPU) và `paddleocr` 3.x; ghi phiên bản chính xác.
2. `pipeline/bench/ocr_bench.py`: nhận danh sách trang (PDF + số trang); chạy **PP-OCRv5 `lang=vi`** (mô hình Latin), **PP-OCRv6** (kiểm `vi` trong từ điển trước; ghi rõ nếu không có), **Tesseract `vie`**. Đo giây/trang, RAM đỉnh (lấy mẫu `psutil`), độ tin cậy trung bình; xuất văn bản từng trang ra `bench/out/<model>/`.
3. Tôi sẽ đưa **20–30 trang scan thật** của KDC Thành Lập và bản gõ đúng của 5 trang. Script tính CER, lỗi dấu, và đếm số tiền/số văn bản đọc sai. **Chưa có dữ liệu thì hỏi tôi, đừng bịa.**
4. Báo cáo bảng so sánh và đề xuất một model (kèm lưu ý mục 3.7). **Chờ tôi chốt model** rồi mới sang Pha 3.

### Pha 3 — Sửa pipeline: OCR theo trang, ảnh, front matter
1. **PDF phân loại từng trang:** có lớp chữ (≥ 30 ký tự) → `pymupdf4llm`; còn lại render 300 dpi bằng PyMuPDF → model đã chốt. Mỗi trang có dấu `[[trang N]]`. Ghi độ tin cậy trung bình từng trang; trang < 0,80 vào `00_MUC_LUC.md` mục "Cần soát".
2. **Ảnh** jpg/png/webp/heic: nén và chép như mục 4, ghi vào mục lục.
3. **Không tải:** dwg, dxf, video, zip, rar, file thiết kế; chỉ ghi tên, đường dẫn, link vào mục lục.
4. **Front matter** đúng mục 4. 5. **Dọn dẹp:** thư mục tạm xóa sau mỗi dự án kể cả khi lỗi (`try/finally`).
6. **Test** với PDF mẫu nhỏ có cả trang chữ và trang scan, ảnh HEIC mẫu, tệp dwg giả, tên tệp tiếng Việt có ký tự Windows cấm, đường dẫn dài.
Cổng: test mới đạt trên Z2 và CI Linux; chạy thử folder thật, số trang OCR và số trang lấy chữ trực tiếp khớp mục lục; không còn tệp trong thư mục tạm.

### Pha 8 — Triển khai (chỉ khi tôi nói "triển khai")
Theo `prompts/60-trien-khai-v06.md`: sao lưu (kéo thêm một bản về Z2), nâng WeKnora v0.8.2 → v0.9.0 (**dừng, báo kế hoạch và cách quay lại, chờ tôi đồng ý**), KB mẫu có Wiki và VLM, migration 0031–0035, runner trên VPS 169 (rclone tôi tự đăng nhập), profile `eos-phap-che` và `ks-kinh-te-xd`, token WeKnora chỉ đọc, nghiệm thu. Khởi động lại gateway Hermes chỉ khi tôi đồng ý.

## 6. Sự thật đã kiểm về WeKnora v0.9.0 (mã nguồn Tencent/WeKnora, commit `cbdceba`)
- Header `X-API-Key`. Tạo KB nhận `indexing_strategy` `{vector_enabled, keyword_enabled, wiki_enabled, graph_enabled}`, `wiki_config` `{auto_generate, synthesis_model_id, max_pages_per_ingest, extraction_granularity: focused|standard|exhaustive, content_instructions (≤ 4000 byte), extraction_instructions}`, `vlm_config` `{enabled, model_id}`.
- Nạp tệp `POST /knowledge-bases/:id/knowledge/file` (multipart `file`, `fileName`), 409 khi trùng nội dung kèm bản đã có. Nạp Markdown `POST …/knowledge/manual` (`title`, `content`, `status: publish`). `PUT /knowledge/:id` nhận `custom_metadata` (≤ 20 khóa, khóa 1–64 ký tự, giá trị string/number/boolean/null ≤ 1000 ký tự, **ghi đè cả object**).
- Bản chạy trên VPS 169 là **v0.8.2** (chưa có Wiki và `custom_metadata`); mã MCP đã tự bắt lỗi. **Chưa thử với WeKnora thật** (phản hồi 409, `PUT /knowledge/:id`, tên công cụ Wiki của MCP WeKnora): khi gặp bản thật, đối chiếu `mcp/src/weknora.mjs` và sửa nếu khác.

## 7. Kiểm thử
- **Trên Z2 (Windows):** đặt `$env:PYTHONUTF8='1'` trước (nếu không, in tiếng Việt khi đầu ra bị chuyển hướng có thể lỗi mã hóa cp1252). Chạy: `python -m unittest discover -s pipeline/test`; `python -I runner/test/test_runner.py`; `python -I ops/test/test_wiki_lint.py`; `python -I scripts/check_skills.py`; `node --test mcp/test/law.test.mjs mcp/test/weknora.test.mjs` (hai tệp này không cần `npm ci`; các test MCP khác cần Postgres nên chạy ở CI).
- **Trên CI (ubuntu-24.04), không chạy tại Z2:** test_db, test_mcp (e2e), test_web, test_bridge, kiểm migration, bản dựng giao diện. Đẩy nhánh rồi đọc kết quả ở Actions của PR #14 (hoặc `gh run watch`/GitHub MCP); **chưa thấy xanh thì chưa nói là đạt**.
- Test Postgres/bash chạy tại chỗ trên Windows là không cần thiết và không được yêu cầu.

## 8. Việc người (tôi) làm, đừng làm thay
Đặt khóa SSH, đăng nhập GitHub và rclone trên Z2; (nếu cần) bật `LongPathsEnabled`; chốt model OCR; đưa trang scan và bản gõ đúng; chỉ định model VLM; duyệt skill 20 bước (bản khung); quyết cơ chế bản tổng Wiki gửi Tùng (chưa có); chọn văn bản pháp luật đầu tiên; cung cấp Telegram ID cho allowlist `ks-kinh-te-xd`; quyết dựng lại sao lưu ngoài máy.

Bắt đầu: kiểm môi trường (mục 0), cho tôi biết kết quả và nhánh hiện tại, rồi làm **Pha 0**. Báo cáo theo mẫu, chờ tôi nói "tiếp".
