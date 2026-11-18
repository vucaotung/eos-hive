# 20 · Dữ liệu v0.6: agent quản trị dữ liệu, ảnh, Wiki, 20 bước, pháp luật

Bản 0.6.0 (plan v6 "Agent Quản trị dữ liệu"). Tài liệu này mô tả kiến trúc mới, phân quyền đọc/ghi KB theo profile, vận hành và giới hạn. Các bước triển khai: `prompts/60-trien-khai-v06.md`.

## 1. Trạng thái các nội dung
Bản mã và tài liệu này **chưa gồm** các phần cần máy thật (Z2, VPS); chúng được làm ở các pha riêng.

| # | Nội dung | Trong bản 0.6.0 | Còn thiếu / cần máy thật |
| --- | --- | --- | --- |
| 1 | Runner hồ sơ chuyển từ Z2 lên VPS 169 | `deploy/eos-runner.service`, `scripts/issue_runner_token.sh` dùng chung | đưa `deo-sync` vào git (`pipeline/`), `DEO_SYNC_DIR` mặc định, cài và chạy trên VPS 169 (Pha 1, 8) |
| 2 | OCR | Pha 2 đã benchmark: **chốt Tesseract `vie` (bản best)**; PaddleOCR PP-OCRv5/v6 bị loại vì bảng ký tự thiếu phần lớn chữ Việt có dấu (`ops-log/pha2-benchmark.md`). Pha 3: OCR từng trang, độ tin cậy từng trang, ngưỡng "cần soát" 0,80 | Tùng đã chốt giữ Tesseract và không đo CER thật (18/11/2026); cài Tesseract + dữ liệu `vie` best trên VPS 169 (Pha 8) |
| 3 | Nạp ảnh vào kho tri thức | `eos_kb_ingest` nạp ảnh ≤ 10 MB qua `knowledge/file`, `custom_metadata`, mã bước; pipeline (Pha 3) nén ảnh, đổi HEIC, giữ ngày chụp, front matter `buoc`/`giai_doan` để trống | chạy thử với Drive thật và WeKnora thật (Pha 8) |
| 4 | Wiki WeKnora qua KB mẫu | `ensureKb` sao chép `indexing_strategy`, `wiki_config`, `vlm_config`; `deploy/weknora/*.txt` | nâng WeKnora v0.8.2 → v0.9.0, tạo KB `_mau-du-an` (Pha 8) |
| 5 | Hồ sơ theo khung 20 bước | `doc.records.buoc` (0032), `kb.file_steps` + `eos_project_tag_step` (0033), skill `so-do-20-buoc`, `qlda-*` | duyệt bảng khung (Tùng và `ks-kinh-te-xd`) |
| 6 | Luồng văn bản pháp luật; profile `ks-kinh-te-xd` | `law_ingest` (0031), `eos_law_*`, skill pháp luật, agent `ks-kinh-te-xd` | tạo profile Hermes `eos-phap-che`, cấu hình `ks-kinh-te-xd` (Pha 8) |
| 7 | Quy tắc gộp trang và bảo trì Wiki | stage `wiki_lint`/`law_review` (0034), skill `bao-tri-wiki`, `ra-hieu-luc-phap-luat`, 2 việc định kỳ mẫu | nhập quy tắc gộp vào KB mẫu, bật việc định kỳ sau khi xem một lần chạy thử |

## 2. Kiến trúc
```
Drive hồ sơ ──rclone──▶ runner (VPS 169, user eos-runner) ──Markdown + ảnh nén──▶ thư mục _md_deo trên Drive
                                                                                      │
Dẹo Work ──giao việc──▶ Điều phối ──chia việc kèm scope──▶ agent Hermes (VPS 173, profile eos-*)
   │                                                           │  chỉ qua MCP Enterprise OS (VPS 169)
   │                                                           ▼
   │                                       MCP (VPS 169, giữ khóa WeKnora trong .env)
   │                                          eos_kb_ingest / eos_law_* ──ghi──▶ WeKnora (VPS 169)
   │                                          eos_project_tag_step ──────────▶ kb.file_steps (CSDL)
   └─ người duyệt                       Hermes đọc KB bằng MCP WeKnora CHỈ ĐỌC (token riêng từng profile)
```
- **DEO-INGEST-RULE giữ nguyên**: khóa ghi WeKnora chỉ nằm trong `.env` của máy chủ MCP trên VPS 169. VPS 173 không giữ khóa WeKnora ghi và Hermes không gọi WeKnora để ghi; các token WeKnora trên VPS 173 là token **chỉ đọc** (tìm kiếm, đọc Wiki).
- **Không có thao tác xóa** trong WeKnora bằng mã mới. Văn bản pháp luật hết hiệu lực chỉ được **đánh dấu** (`eos_law_mark`); phiên bản cũ của văn bản được giữ (`kb.sources.state = superseded` trong CSDL).
- Phiên bản WeKnora đang chạy là v0.8.2 (chưa có Wiki và `custom_metadata`). Mã **tự bắt lỗi**: KB mẫu có cấu hình Wiki mà WeKnora từ chối thì tạo KB bằng cấu hình lõi và ghi log; `PUT /knowledge/:id` báo 404/400/405/422 thì đặt cờ `metadata_unsupported`, ghi log một lần, bỏ qua metadata các tệp sau, **không làm lỗi tệp**.

## 3. Hồ sơ dự án: ảnh, mã bước, metadata
- Giai đoạn `data_quality`: `quan-tri-du-lieu` rà dữ liệu và **đề xuất mã bước 01–20** cho từng tệp (skill `so-do-20-buoc`), ghi bằng `eos_project_tag_step` vào `kb.file_steps(run_id, drive_id, buoc)`. Công cụ **không sửa tệp trên Drive**. Mã `00` = văn bản chung hoặc chưa chắc (kèm "cần xác nhận").
- Giai đoạn danh mục: `van-thu` ghi `buoc` vào `doc.records` (`eos_catalog_upsert`).
- Giai đoạn `kb_ingest`: `eos_kb_ingest` nạp Markdown (`knowledge/manual`) và **ảnh** (`image/*`, ≤ 10 MB, `knowledge/file`; trùng nội dung → WeKnora trả 409 kèm bản đã có, coi như đã nạp). Sau mỗi tệp ghi `custom_metadata`: `drive_link`, `duong_dan`, `buoc`, `giai_doan` (giai đoạn I = 01–09, II = 10–15, III = 16–20, `00` để trống). Mã bước lấy từ `kb.file_steps`, nếu không có thì từ front matter. Ảnh không có front matter lấy theo tệp `.md` cùng thư mục (cùng tên gốc, hoặc là `.md` duy nhất). `custom_metadata` của WeKnora **ghi đè cả object**, nên luôn gửi đủ khóa.
- Giai đoạn `buoc_20_kiem`: `ks-kinh-te-xd` lập bảng 20 bước của dự án, đề xuất bước hiện tại, hồ sơ thiếu, mốc pháp lý.

## 4. Luồng văn bản pháp luật (`phap-che`)
1. Chủ sở hữu hoặc quản trị (người thật) tạo việc: Dẹo Work → Dự án → **Nạp văn bản pháp luật** (`app_law_task_create`): danh sách số hiệu/link, KB đích (`phap-luat` hoặc `tieu-chuan`). Mai chỉ tạo **việc nháp** nhắc chủ sở hữu, không nạp.
2. `phap-che` (skill `nap-van-ban-phap-luat`, `tra-cuu-phap-luat`): tìm nguyên văn trên nguồn chính thống, kiểm hiệu lực, soạn Markdown, `eos_law_save` → `eos_law_ingest` → `eos_law_mark` cho văn bản bị thay thế.
3. Máy chủ MCP kiểm: người tạo việc là người thật có vai trò owner/admin, đúng agent, đúng giai đoạn `law_ingest`, KB thuộc `agent.company_settings.law_kb_names`, tệp nằm trong `law_md_folder_id`, front matter đủ trường, **nguồn thuộc danh sách chính thống** (`LAW_SOURCE_DOMAINS`, mặc định `vbpl.vn`, `congbao.chinhphu.vn`, `vanban.chinhphu.vn`, `chinhphu.vn`, `dichvucong.gov.vn`, `*.gov.vn`).
4. Dữ liệu: `kb.law_sources` (`so_hieu`, `tinh_trang`, `thay_the`, `buoc`, `nguon_url`, `ngay_tra`, `phien_ban` md5…), unique `(weknora_kb_id, so_hieu, phien_ban)`; chạy lại không nạp trùng.
5. KB pháp luật **dùng chung mọi công ty** theo cấu hình mặc định (mặc định, chờ Tùng xác nhận): mỗi công ty trỏ cùng tên KB.

## 5. Bảo trì Wiki định kỳ
| Việc | Agent / skill | Lịch (mẫu) | Làm gì |
| --- | --- | --- | --- |
| `wiki_lint` | `quan-tri-du-lieu` / `bao-tri-wiki` | thứ Hai hằng tuần, mỗi dự án | kiểm 7 loại: mồ côi, liên kết hỏng, chỉ mục lệch, trùng chủ thể, số liệu mâu thuẫn, trang cũ, tổng quan thiếu bước. Báo cáo `.md`, **không sửa Wiki**; mâu thuẫn kinh phí/diện tích/ngày cấp phép → đề xuất Fact Registry |
| `law_review` | `phap-che` / `ra-hieu-luc-phap-luat` | ngày 1 hằng tháng, mỗi KB pháp luật | đối chiếu từng dòng `kb.law_sources` với nguồn chính thống (`eos_law_list`), kiểm Wiki KB pháp luật. **Chỉ báo cáo và đề xuất**; đánh dấu/nạp mới cần việc `law_ingest` do Tùng tạo |
- Việc định kỳ mang phạm vi chỉ đọc (`work.recurrences.agent_code/scope`, migration 0034); `eos_project_*` hoạt động ở hai stage này nhưng chỉ đọc và `eos_project_save_report`. Tạo mẫu bằng `deploy/setup_wiki_maintenance.sql` (**không bật sẵn**); bật sau khi xem một lần chạy thử.
- Báo cáo `wiki_lint` gửi người theo dõi dự án; `law_review` gửi chủ sở hữu. **Bản tổng gửi Tùng chưa có cơ chế riêng** (đề xuất: việc tổng hợp do Điều phối).
- `ops/wiki_lint.py` + `ops/test/fixtures/wiki_demo.json` là bộ kiểm tham chiếu để xem trước kết quả và để test (agent không có terminal).
- Quy tắc gộp trang nằm trong `wiki_config.extraction_instructions` của KB mẫu: `deploy/weknora/wiki_extraction_du_an.txt` (dự án), `wiki_extraction_phap_luat.txt` (pháp luật), `wiki_content_du_an.txt` (trang tổng quan 3 giai đoạn, 20 bước). Mỗi tệp ≤ 4000 byte (kiểm bằng `make test-skills`).

## 6. Profile và quyền đọc/ghi KB
| Profile Hermes (VPS 173) | Agent | Ghi KB (qua MCP VPS 169) | Đọc KB (MCP WeKnora chỉ đọc) | Công cụ khác |
| --- | --- | --- | --- | --- |
| `eos-dieu-phoi` | `dieu-phoi` | không | có | `eos_delegate` |
| `eos-van-thu` | `van-thu` | không (ghi danh mục `doc.records`) | có | `eos_catalog_upsert`, soạn dự thảo |
| `eos-quan-tri-du-lieu` | `quan-tri-du-lieu` | `eos_kb_ingest`, `eos_project_tag_step` | có (cả Wiki để `wiki_lint`) | `eos_project_*` |
| `eos-phap-che` | `phap-che` | `eos_law_save`, `eos_law_ingest`, `eos_law_mark` | có | web (SearXNG), `eos_law_list`; không terminal, không file, không nền tảng chat |
| `ks-kinh-te-xd` | `ks-kinh-te-xd` | không | có | web, MCP Enterprise OS (đọc dự án, `eos_project_save_report`), kênh chat Telegram (allowlist chỉ ID của Tùng, mặc định, chờ xác nhận); **terminal tắt** |
| `team_admin` (Mai) | `mai` | không | có | tạo việc nháp cho người |
- Phạm vi mã MCP: `law_ingest` chỉ cấp cho `phap-che` (CSDL: trigger trên `agent.agents` và `agent.mcp_tokens`); `ingest` chỉ cho agent module kb.
- Token WeKnora chỉ đọc: tạo riêng cho từng profile, chỉ bật nhóm công cụ tìm kiếm và đọc, **tắt** công cụ ghi/sửa Wiki/xóa; điền whitelist KB cho `hermes-ops-all`, `hermes-team` (Pha 8).

## 7. Vận hành
- Cấu hình công ty: `deploy/setup_law.sql` (thư mục pháp luật, bật `phap-che`), `deploy/setup_agents.sql` + `deploy/setup_agent_profiles.sql` (thêm `ks-kinh-te-xd`, tắt khi mới tạo), `deploy/setup_wiki_maintenance.sql`.
- Cấp mã: `scripts/issue_agent_token.sh vps169 vps173 phap-che eos-phap-che` (in phạm vi mã, có `law_ingest`).
- Bật `ks-kinh-te-xd`: `UPDATE agent.agents SET active = true WHERE code = 'ks-kinh-te-xd'` sau khi profile có `eos_bridge` và mã MCP.
- Biến môi trường MCP mới: `WEKNORA_TEMPLATE_KB` (v0.6: `_mau-du-an`), `LAW_SOURCE_DOMAINS`.
- Kiểm tra: `make test`, `make test-skills`; `MCP e2e` có ca ảnh, metadata, WeKnora cũ, luồng pháp luật.

## 8. Giới hạn đã biết
- Chưa thử với WeKnora thật: dạng phản hồi 409 (mã bản đã có), đường `PUT /knowledge/:id`, tên công cụ Wiki của MCP WeKnora. Kiểm ở Pha 8.
- Wiki của KB dự án và pháp luật chỉ có từ WeKnora v0.9.0 trở lên.
- Giao diện chọn KB đích ghi cứng `phap-luat`/`tieu-chuan`; máy chủ kiểm theo `law_kb_names`.
- Bước hiện tại của dự án chỉ là **đề xuất** của AI; người theo dõi quyết định. Bảng 20 bước là bản khung cần duyệt, không phải trích dẫn pháp luật; căn cứ pháp lý luôn tra lúc dùng (`tra-cuu-phap-luat`).
- `ks-kinh-te-xd` ở chế độ chat không ghi Drive/CSDL; muốn lưu phải tạo việc.
- Bản tổng wiki cho Tùng chưa tự động (mục 5).
- OCR là Tesseract `vie` (bản best), được Tùng chốt giữ (18/11/2026); **không có CER thật** theo quyết định của Tùng; còn lỗi lẻ và trang scan xấu cho độ tin cậy thấp, chưa tiền xử lý ảnh (nghiêng, nhị phân hóa). Chi tiết: `docs/21-ocr-pha2.md`.
- `make test-bridge` cần `postgrest`; chưa chạy trong môi trường phát triển của đợt này.
