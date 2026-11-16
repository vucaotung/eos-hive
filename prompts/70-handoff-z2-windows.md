# 70 · Handoff: làm Pha 0–3 trên Z2 (Windows 11 + WSL2)

Bản handoff này thay bản trước (viết khi giả định Z2 là Ubuntu). **Z2 đã cài lại Windows 11** (hostname `Z2_Workstation`, user `vucao`): bản Linux, `~/work/deo-sync`, runner `eos-z2-runner` và cron sao lưu **đã bị xóa**.

Bạn là kỹ sư phát triển và triển khai cho dự án **Tổ Ong (eos-hive)**, repo `vucaotung/eos-hive`. Ngôn ngữ làm việc: **tiếng Việt**. Phiên cloud trước đã làm xong phần chỉ cần repo của plan v6 "Agent Quản trị dữ liệu" (bản 0.6.0). Phần còn lại cần máy thật nên giao cho bạn.

## 0. Môi trường và bắt đầu
**Cách làm khuyến nghị (người dùng thực hiện, bạn kiểm):** WSL2 + Ubuntu 24.04, chạy **Claude Code bên trong WSL**, repo đặt trong ổ WSL (`~/src/eos-hive`, không đặt ở `/mnt/c`: chậm và dễ lỗi CRLF/quyền). Lý do: pipeline là bash + Linux (rclone, LibreOffice, pandoc, poppler, Tesseract, PaddleOCR) và sẽ chạy trên VPS 169 (Linux); dựng lại trên Windows thuần làm kết quả so sánh vô nghĩa. Công cụ Bash của Claude Code trên Windows có thể bị Application Control chặn `git.exe`; trong WSL không có vấn đề này.

Kiểm môi trường (chỉ đọc), rồi báo cho tôi:
```bash
hostname; whoami; uname -a; cat /etc/os-release | head -2; nproc; free -h | sed -n 2p; df -h ~ | tail -1
for c in git python3 node psql rclone soffice pandoc pdftotext tesseract ssh; do printf '%s: ' $c; command -v $c || echo THIẾU; done
tesseract --list-langs 2>/dev/null | grep -c vie; ls ~/.ssh 2>&1 | head -3
```
Thiếu công cụ nào thì **đề xuất lệnh cài (apt) và chờ tôi đồng ý** (hỏi nếu apt đòi gỡ gói khác); không cài lặng lẽ. Gói cần: `git python3-venv nodejs(22) postgresql-16 rclone libreoffice pandoc poppler-utils tesseract-ocr tesseract-ocr-vie openssh-client`.
Bí mật: **tôi** tự đặt khóa SSH và đăng nhập rclone/GitHub trong WSL. Bạn không xin, không in, không ghi khóa/token; chỉ kiểm tệp có tồn tại và quyền `600`.

Sau đó:
```bash
git clone https://github.com/vucaotung/eos-hive.git ~/src/eos-hive 2>&1 | tail -1   # nếu chưa có; cần tôi đăng nhập GitHub trước
cd ~/src/eos-hive && git fetch origin && git checkout feat/v0.6-du-lieu && git pull && cat VERSION   # kỳ vọng 0.6.0
```
Đọc trước, tuân thủ tuyệt đối: `prompts/00-MASTER.md` (luật về bí mật, an toàn thao tác, ranh giới, mẫu báo cáo ≤ 15 dòng), `docs/20-du-lieu-v06.md` (mục 1: bảng trạng thái), `docs/12`, `docs/13`, `docs/17`, `docs/02-guideline-phat-trien.md`, `prompts/60-trien-khai-v06.md`.

## 1. Trạng thái
- Nhánh `feat/v0.6-du-lieu`, PR nháp https://github.com/vucaotung/eos-hive/pull/14. CI (workflow `ci`: test_db, test_mcp, test_web, test_runner, test_bridge, bản dựng giao diện, kiểm skill) **xanh** ở mọi commit đã push.
- **Pha 4–7 đã xong, không làm lại:** `eos_kb_ingest` nạp ảnh + `custom_metadata`; `kb.file_steps` + `eos_project_tag_step`; luồng pháp luật `eos_law_*`; agent `ks-kinh-te-xd`; 8 skill mới; việc định kỳ `wiki_lint`/`law_review` (không bật sẵn); migration 0031–0035; tài liệu; `VERSION` = 0.6.0.
- **Còn lại:** Pha 0, 1, 2, 3 (bạn làm trong WSL2 trên Z2). Pha 8 (triển khai) chỉ khi tôi nói "triển khai".
- Làm tiếp trên `feat/v0.6-du-lieu`, mỗi pha một hoặc vài commit, push cùng nhánh. Không triển khai lên máy thật trước Pha 8.

## 2. Luật bổ sung của đợt này
- **DEO-INGEST-RULE giữ nguyên:** khóa WeKnora chỉ ở `.env` của máy chủ MCP trên VPS 169. Không đặt khóa WeKnora trên VPS 173, không cho Hermes gọi WeKnora để ghi. **Không xóa gì trong WeKnora** bằng mã mới.
- Mỗi thay đổi có test (`db/test_*.sql`, `mcp/test/*.mjs`, `runner/test/*`, `pipeline/test`). `make test` xanh trước khi sang pha sau; chạy `scripts/check_secrets.sh` trước mỗi commit. Kết thúc mỗi pha: báo cáo theo mẫu `00-MASTER.md`, **chờ tôi nói "tiếp"**.
- Mặc định tôi chưa chốt (ghi "mặc định, chờ Tùng xác nhận"; đổi được bằng cấu hình): KB mẫu `_mau-du-an` (biến `WEKNORA_TEMPLATE_KB`); rclone trên VPS 169 là ai666; mã bước ở cột `doc.records.buoc`; KB pháp luật dùng chung `phap-luat`/`tieu-chuan`; ảnh nạp hết sau khi nén; `wiki_lint` thứ Hai, `law_review` ngày 1; allowlist `ks-kinh-te-xd` chỉ Telegram ID của Tùng.

## 3. Điều đã đổi do Z2 cài lại (cần biết trước khi làm)
1. **Mã nguồn `deo-sync` không có trong repo** (chỉ được tham chiếu). Có thể nó đã mất cùng bản Linux. **Việc đầu tiên của Pha 0: tìm bản sao.** Nơi có thể có (chỉ đọc, kiểm lần lượt): repo GitHub riêng `vucaotung/deo-os-z2` (private, push lần cuối 2026-10-08; tên gợi ý là kho cấu hình Z2, **chưa kiểm có chứa deo-sync không**; muốn đọc phải gắn repo vào phiên, cần tôi đồng ý); `~/work`, `/opt`, `find / -name 'fetch_drive.sh' -o -name 'deo_md.py'` trên VPS 169 và VPS 173; Drive; ổ ngoài/sao lưu của tôi. Hỏi tôi nếu không thấy.
2. **Không có "bản cũ" để chạy so sánh.** Cổng Pha 1 "kết quả giống bản cũ" đổi thành: so với **đầu ra cũ đã có trên Drive** (`_md_deo` của KDC Thành Lập do pipeline cũ sinh ra: so số tệp `.md` và `00_MUC_LUC.md`). Cần rclone tới Drive (tôi đăng nhập).
3. **Nếu không tìm được `deo-sync`: Pha 1 thành "dựng lại pipeline theo hợp đồng ở mục 4"** và gộp với Pha 3. Báo tôi quyết định trước khi viết (phạm vi lớn; các hành vi cũ không có trong hợp đồng, như danh sách loại trừ hay cách đặt tên, sẽ không biết; suy ra từ đầu ra cũ trên Drive).
4. **Mất sao lưu ngoài máy:** cron 04:00 kéo sao lưu VPS 169 về `~/backups/deo169` không còn. Hiện sao lưu chỉ còn trên VPS 169 (`/var/backups/deo`). **Đề xuất dựng lại** (Task Scheduler + WSL `rsync`/`scp` qua SSH, hoặc máy khác) trước Pha 8; hỏi tôi. Bước sao lưu Pha 8 nên **kéo thêm một bản về Z2** trước khi nâng WeKnora. `make restore-drill` cũ giả định Docker trên Z2 Linux, nay chưa chạy được.
5. **Không còn runner Z2** để làm đường lùi: rollback runner là tắt `eos-runner` trên VPS 169 (xem `prompts/60-trien-khai-v06.md`). Vì vậy phải **thử pipeline trong WSL (Linux) thật kỹ** trước khi đưa lên VPS 169.
6. **Số đo benchmark (Pha 2):** CER và lỗi dấu không phụ thuộc phần cứng; **giây/trang và RAM đỉnh trong WSL2 chỉ mang tính tham khảo** (khác VPS 169). Sau khi chốt model, đo lại một lượt ngắn trên VPS 169 (venv riêng, `nice`, giới hạn bộ nhớ) **chỉ khi tôi đồng ý**, vì đó là máy đang chạy dịch vụ.

## 4. Hợp đồng pipeline ↔ runner ↔ MCP (suy từ `runner/eos_z2_runner.py` và `mcp/src`)
Runner gọi pipeline bằng danh sách đối số (không qua shell), với `DEO_SYNC_DIR` (mặc định hiện `~/work/deo-sync`; Pha 1 đổi mặc định thành `pipeline/` trong repo), `RCLONE_REMOTE` (mặc định `gdrive`), `WORK_DIR`:
- `bash fetch_drive.sh <slug> <id thư mục nguồn>`: tải thư mục nguồn của dự án về thư mục làm việc. `slug` khớp mẫu `SLUG` của runner; id khớp `SAFE_ID`.
- `bash run_project.sh <slug>`: chuyển đổi, sinh **`<WORK_DIR>/md/<slug>/`** (cây Markdown cùng đường dẫn con với nguồn) và **`00_MUC_LUC.md`** có đúng một dòng khớp biểu thức: `Tổng (\d+) file: (\d+) đã có Markdown, (\d+) file có trang cần soát OCR, (\d+) lỗi` (runner đọc 2000 ký tự đầu). Đường cũ `~/work/upload/<slug>/*.md` chỉ dùng cho đường dự phòng thủ công của giai đoạn `kb_ingest` của runner; có thể giữ hoặc bỏ nếu cập nhật runner và test.
- Runner rồi `rclone copy md/<slug> gdrive:_md_deo --drive-root-folder-id <nguồn>`, liệt kê tệp, đăng ký bằng `eos_runner_setup` (`drive_id`, `name`, `url` https, `mime`, `bytes`).
- Front matter mỗi `.md` (mỗi khóa một dòng, `khóa: giá trị`): `drive_id`, `drive_link`, `duong_dan` (**dấu `/`, không dùng `\`**), `md5`, `converter`, `ocr_conf_tb`, `so_trang`, **`buoc: ""`**, **`giai_doan: ""`** (để trống; mã bước do `quan-tri-du-lieu` gắn sau, lưu ở CSDL, không sửa lại tệp). MCP đọc `drive_link`, `duong_dan` (hoặc `source_path`), `buoc`, `giai_doan`, `pages` hoặc `so_trang`; `weknora.prepare` bỏ front matter khi nạp.
- Ảnh: nén cạnh dài ≤ 2000 px, JPEG chất lượng 85, HEIC đổi JPEG, giữ ngày chụp EXIF; chép vào `_md_deo` **cùng đường dẫn con**; tối đa 10 MB; `mime` đúng `image/*`. MCP lấy `buoc`/`duong_dan` của ảnh theo `.md` cùng thư mục (trùng tên gốc, hoặc là `.md` duy nhất không phải mục lục).
- MCP bỏ qua `00_*` và tệp bắt đầu bằng `_` khi nạp.
- Tệp shell/Python/SQL phải là **LF** (repo có `.gitattributes`); nếu clone bằng git của Windows sẽ bị CRLF và hỏng script: dùng WSL.

## 5. Việc cần làm

### Pha 0 — Khảo sát chỉ đọc (ghi vào `ops-log/`, không sửa gì)
1. **Z2 (WSL):** kiểm môi trường (mục 0). **Tìm bản sao `deo-sync`** (mục 3.1). Nếu tìm được: kê tệp, script, chỗ gọi Tesseract, bí mật (**chỉ tên tệp và tên biến, không giá trị**). Kiểm `rclone listremotes` (chỉ tên remote).
2. **VPS 169:** `hostname; free -h; nproc; df -h /`; `docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}'`; image tag WeKnora; `STORAGE_TYPE`, `MAX_FILE_SIZE_MB` (chỉ tên biến và giá trị không bí mật); danh sách KB qua API (tên và id) bằng khóa trong `mcp/.env` **không in khóa**.
3. **VPS 173:** `hermes profile list`; cấu hình profile `ks-kinh-te-xd` (chỉ in **tên khóa** của `config.yaml`: platforms, toolsets, mcp_servers, và tên tệp SOUL); SearXNG `127.0.0.1:8888` có trả JSON không.
SSH tới VPS: dùng bí danh `vps169`, `vps173` nếu có trong `~/.ssh/config` của WSL; thiếu thì hỏi tôi địa chỉ/user/đường dẫn khóa, **không đoán mật khẩu**.
Cổng: bản kê (hoặc xác nhận "không có bản sao"); RAM/CPU/ổ VPS 169; phiên bản WeKnora và danh sách KB; hiện trạng `ks-kinh-te-xd`; danh sách điều khác với giả định của plan.

### Pha 1 — Đưa pipeline vào git (hoặc dựng lại theo mục 4 nếu mất)
1. Có bản sao: chép vào `pipeline/`, bỏ bí mật (thay bằng biến môi trường), thêm `pipeline/.env.example`, chạy `scripts/check_secrets.sh`. Không có: **dừng, báo quyết định** (mục 3.3).
2. Đường dẫn cứng đổi thành biến `DEO_SYNC_DIR`, `WORK_DIR`, `RCLONE_REMOTE`. Runner: mặc định `deo_sync` trỏ `pipeline/` nếu `DEO_SYNC_DIR` không đặt; giữ tương thích ngược.
3. Viết `pipeline/README.md`: cài đặt, phụ thuộc, cách chạy thử một dự án nhỏ (trong WSL).
Cổng: `check_secrets.sh` sạch; chạy một folder thử, kết quả khớp đầu ra cũ trên Drive (số `.md`, mục lục); `make test` xanh.

### Pha 2 — Benchmark OCR (trong WSL2 trên Z2)
1. Venv riêng, `paddlepaddle` (CPU) và `paddleocr` 3.x; ghi phiên bản. (Z2 có NVIDIA nhưng đích là CPU của VPS 169: dùng CPU.)
2. `pipeline/bench/ocr_bench.py`: nhận danh sách trang (PDF + số trang); chạy **PP-OCRv5 `lang=vi`**, **PP-OCRv6** (nếu cài được; kiểm có tiếng Việt), **Tesseract `vie`**. Đo giây/trang, RAM đỉnh, độ tin cậy trung bình; xuất văn bản từng trang ra `bench/out/<model>/`.
3. Tôi sẽ đưa **20–30 trang scan thật** của KDC Thành Lập và bản gõ đúng của 5 trang. Script tính CER, lỗi dấu, và đếm số tiền/số văn bản đọc sai. **Chưa có dữ liệu thì hỏi tôi, đừng bịa.**
4. Báo cáo bảng so sánh và đề xuất một model (kèm lưu ý mục 3.6). **Chờ tôi chốt model** rồi mới sang Pha 3.

### Pha 3 — Sửa pipeline: OCR theo trang, ảnh, front matter
1. **PDF phân loại từng trang:** có lớp chữ (≥ 30 ký tự) → `pymupdf4llm`; còn lại render 300 dpi → model đã chốt. Mỗi trang có dấu `[[trang N]]`. Ghi độ tin cậy trung bình từng trang; trang < 0,80 vào `00_MUC_LUC.md` mục "Cần soát".
2. **Ảnh** jpg/png/webp/heic: nén và chép như mục 4, ghi vào mục lục.
3. **Không tải:** dwg, dxf, video, zip, rar, file thiết kế; chỉ ghi tên, đường dẫn, link vào mục lục.
4. **Front matter** đúng mục 4. 5. **Dọn dẹp:** thư mục tạm xóa sau mỗi dự án kể cả khi lỗi (`try/finally`).
6. **Test** với PDF mẫu nhỏ có cả trang chữ và trang scan, ảnh HEIC mẫu, tệp dwg giả.
Cổng: test mới đạt; chạy thử folder thật, số trang OCR và số trang lấy chữ trực tiếp khớp mục lục; không còn tệp trong thư mục tạm.

### Pha 8 — Triển khai (chỉ khi tôi nói "triển khai")
Theo `prompts/60-trien-khai-v06.md`: sao lưu (kéo thêm một bản về Z2), nâng WeKnora v0.8.2 → v0.9.0 (**dừng, báo kế hoạch và cách quay lại, chờ tôi đồng ý**), KB mẫu có Wiki và VLM, migration 0031–0035, runner trên VPS 169 (rclone tôi tự đăng nhập), profile `eos-phap-che` và `ks-kinh-te-xd`, token WeKnora chỉ đọc, nghiệm thu. Khởi động lại gateway Hermes chỉ khi tôi đồng ý.

## 6. Sự thật đã kiểm về WeKnora v0.9.0 (mã nguồn Tencent/WeKnora, commit `cbdceba`)
- Header `X-API-Key`. Tạo KB nhận `indexing_strategy` `{vector_enabled, keyword_enabled, wiki_enabled, graph_enabled}`, `wiki_config` `{auto_generate, synthesis_model_id, max_pages_per_ingest, extraction_granularity: focused|standard|exhaustive, content_instructions (≤ 4000 byte), extraction_instructions}`, `vlm_config` `{enabled, model_id}`.
- Nạp tệp `POST /knowledge-bases/:id/knowledge/file` (multipart `file`, `fileName`), 409 khi trùng nội dung kèm bản đã có. Nạp Markdown `POST …/knowledge/manual` (`title`, `content`, `status: publish`). `PUT /knowledge/:id` nhận `custom_metadata` (≤ 20 khóa, khóa 1–64 ký tự, giá trị string/number/boolean/null ≤ 1000 ký tự, **ghi đè cả object**).
- Bản chạy trên VPS 169 là **v0.8.2** (chưa có Wiki và `custom_metadata`); mã MCP đã tự bắt lỗi. **Chưa thử với WeKnora thật** (phản hồi 409, `PUT /knowledge/:id`, tên công cụ Wiki của MCP WeKnora): khi gặp bản thật, đối chiếu `mcp/src/weknora.mjs` và sửa nếu khác.

## 7. Kiểm thử (trong WSL)
```bash
export EOS_TEST_DSN=postgres://postgres:pw@127.0.0.1:5432/eos_test   # Postgres 16 chạy trong WSL; tên CSDL phải chứa "_test"
make test-db test-migration test-mcp test-web test-runner test-skills
```
`make test-bridge` cần binary `postgrest` (CI tự tải v12.2.3). `scripts/check_migrations_v06.sh` cần `git fetch origin main`. Cài Postgres trong WSL: hỏi tôi trước; đặt mật khẩu `postgres` cục bộ cho tài khoản thử (không dùng cho thứ gì khác).

## 8. Việc người (tôi) làm, đừng làm thay
Bật WSL2 và cài Ubuntu; đặt khóa SSH, đăng nhập GitHub và rclone trong WSL; chốt model OCR; đưa trang scan và bản gõ đúng; chỉ định model VLM; duyệt skill 20 bước (bản khung); quyết cơ chế bản tổng Wiki gửi Tùng (chưa có); chọn văn bản pháp luật đầu tiên; cung cấp Telegram ID cho allowlist `ks-kinh-te-xd`; quyết dựng lại sao lưu ngoài máy.

Bắt đầu: kiểm môi trường (mục 0), cho tôi biết kết quả và nhánh hiện tại, rồi làm **Pha 0**. Báo cáo theo mẫu, chờ tôi nói "tiếp".
