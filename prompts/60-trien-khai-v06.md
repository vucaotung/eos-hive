# 60 · Triển khai v0.6.0 (Agent Quản trị dữ liệu)

**Mục tiêu:** đưa v0.6.0 lên máy thật: WeKnora v0.9.0 có Wiki, KB mẫu `_mau-du-an`, migration 0031–0035, runner trên VPS 169, profile Hermes mới, token WeKnora chỉ đọc, nghiệm thu.
**Chỉ chạy khi chủ sở hữu nói "triển khai".** Đọc trước: `prompts/00-MASTER.md`, `docs/20-du-lieu-v06.md`, `prompts/20-vps169.md`, `prompts/30-vps173.md`, `docs/13`.
**Điều kiện đầu vào (Pha 0–3 đã đạt, làm trên Z2 Windows 11 bằng pipeline Python chạy được trên cả Windows và Linux, và đã gộp vào `main`; pipeline phải đã qua test trên Linux của CI):** `pipeline/` có trong git, model OCR đã chốt, ảnh/front matter mới đã kiểm. Chưa đạt thì **dừng và báo**, đừng triển khai nửa vời.
**Luật bổ sung:** không đặt khóa WeKnora ở VPS 173; không xóa gì trong WeKnora; bí mật chỉ đi bằng đường ống SSH, không in; sao lưu trước khi sửa; **dừng và hỏi** ở mọi dấu ⛔.

## Bước 0 — Hiện trạng (chỉ đọc), báo cáo trước khi làm tiếp
```bash
ssh vps169 'hostname; free -h | sed -n 2p; nproc; df -h / | tail -1
sudo docker ps --format "{{.Names}}\t{{.Image}}\t{{.Status}}"
cat /opt/apps/enterprise-os/VERSION
awk -F= "/^(WEKNORA_BASE_URL|WEKNORA_TEMPLATE_KB|LAW_SOURCE_DOMAINS)=/{print \$1, length(\$2)}" /opt/apps/enterprise-os/mcp/.env
sudo docker exec eos-postgres psql -U postgres -d eos -Atc "select count(*) from agent.company_settings"'
ssh vps173 'hermes profile list; systemctl --user is-active hermes-gateway'
```
**Dừng và hỏi** nếu: ổ trống < 10 GB (sao lưu + nâng WeKnora cần chỗ); RAM trống < 2 GB; image WeKnora không phải v0.8.2; có việc `kb_ingest`/runner đang chạy (`select state from agent.workflow_runs where state='running'`: đợi xong hoặc hỏi).

## Bước 1 — Sao lưu (VPS 169)
```bash
ssh vps169 'set -e; T=$(date +%F-%H%M); D=/var/backups/deo/pre-v06-$T; sudo install -d -m 700 $D
sudo docker exec eos-postgres pg_dump -U postgres -Fc eos | sudo tee $D/eos.dump >/dev/null
# CSDL của WeKnora: tên container và CSDL lấy từ docker ps / compose của WeKnora (không đoán)
sudo docker ps --format "{{.Names}}" | grep -i weknora
echo $D'
```
- Dump CSDL WeKnora (container Postgres của WeKnora, `pg_dump -Fc`) vào cùng thư mục; sao lưu volume `data-files` của WeKnora: `sudo docker run --rm -v <volume>:/d:ro -v $D:/o alpine tar czf /o/data-files.tgz -C /d .` (tên volume lấy từ `docker volume ls`).
- **Kiểm đọc được:** `pg_restore -l eos.dump | head`, `tar tzf data-files.tgz | head`, kích thước > 0. Ghi đường dẫn vào `ops-log/`.
- Sao lưu cấu hình trước khi sửa: `cp -a mcp/.env mcp/.env.bak.$(date +%F-%H%M)`.

## Bước 2 — Nâng WeKnora v0.8.2 → v0.9.0 (VPS 169) ⛔
1. Đọc `MIGRATION.md` của WeKnora (bản v0.9.0) và ghi chú phát hành; xác định migration CSDL, đổi biến môi trường, đổi API.
2. ⛔ **Dừng, báo kế hoạch nâng (các bước, thời gian ngừng dịch vụ ước tính, cách quay lại: khôi phục dump + volume + image v0.8.2) và chờ chủ sở hữu đồng ý** rồi mới chạy.
3. Sau khi nâng: `curl -s -H "X-API-Key: $KEY" $BASE/knowledge-bases` còn thấy các KB cũ; truy vấn thử một KB cũ có kết quả. (Khóa lấy từ `mcp/.env` bằng `set -a; . ./mcp/.env` trong một lệnh ssh, không in.)
4. Không nâng được hoặc lỗi: khôi phục theo kế hoạch quay lại, báo, **dừng**.

## Bước 3 — KB mẫu `_mau-du-an` và KB pháp luật có Wiki (VPS 169)
Tạo qua API (chạy trên VPS 169, khóa đọc từ `mcp/.env`, không in). Mô hình nhúng và mô hình tóm tắt **lấy từ KB cũ đang dùng** (`GET /knowledge-bases`, chép `embedding_model_id`, `summary_model_id`, `chunking_config`); VLM: model do chủ sở hữu chỉ định (hỏi nếu chưa có).
```jsonc
// POST /knowledge-bases   (name: "_mau-du-an", KHÔNG nạp tài liệu nào vào KB này)
{ "name": "_mau-du-an", "type": "document",
  "embedding_model_id": "<chép từ KB cũ>", "summary_model_id": "<chép từ KB cũ>", "chunking_config": { /* chép từ KB cũ */ },
  "indexing_strategy": { "vector_enabled": true, "keyword_enabled": true, "wiki_enabled": true, "graph_enabled": false },
  "wiki_config": { "auto_generate": true, "synthesis_model_id": "<model>", "max_pages_per_ingest": 20, "extraction_granularity": "focused",
                   "content_instructions": "<nội dung deploy/weknora/wiki_content_du_an.txt>",
                   "extraction_instructions": "<nội dung deploy/weknora/wiki_extraction_du_an.txt>" },
  "vlm_config": { "enabled": true, "model_id": "<model VLM chủ sở hữu chỉ định>" } }
```
- Dựng JSON bằng `python3 -c` đọc các tệp `deploy/weknora/*.txt` (không dán tay); `content_instructions` ≤ 4000 byte (đã kiểm bằng `make test-skills`).
- KB `phap-luat` và `tieu-chuan`: tạo **bằng chính luồng MCP** ở bước nghiệm thu (sao chép cấu hình từ KB mẫu, bật Wiki). Sau khi KB tồn tại, `PUT` cấu hình Wiki của chúng với `wiki_extraction_phap_luat.txt` làm `extraction_instructions` (đường API cập nhật `wiki_config` của KB: xem tài liệu WeKnora v0.9.0; ⛔ hỏi nếu không rõ).
- **Kiểm gộp trang:** tạo KB thử `_thu-gop-wiki` (sao chép từ KB mẫu), nạp hai tài liệu cùng chủ đề (ví dụ hai bản ghi cùng một thửa đất), chờ Wiki sinh; kỳ vọng **một trang** được cập nhật chứ không có hai trang trùng chủ thể. Không đạt: báo, chỉnh `extraction_instructions`, thử lại. KB thử **không xóa** (đổi tên `_to_delete-…` nếu WeKnora cho, rồi báo chủ sở hữu).
- Đặt trong `mcp/.env`: `WEKNORA_TEMPLATE_KB=_mau-du-an` (sao lưu `.env` trước).

## Bước 4 — Migration và mã (VPS 169)
```bash
cd ~/src/eos-hive && git checkout main && git pull && scripts/push_to_host.sh vps169 /tmp/eos-hive-src
ssh vps169 'sudo rsync -a /tmp/eos-hive-src/ /opt/apps/enterprise-os/ && sudo chown -R eos:eos /opt/apps/enterprise-os && cat /opt/apps/enterprise-os/VERSION'   # kỳ vọng 0.6.0
```
Áp theo thứ tự, mỗi tệp **hai lần liền không lỗi** là bình thường (idempotent); dừng ở lỗi đầu tiên:
```bash
ssh vps169 'cd /opt/apps/enterprise-os/db/migrations && for m in 0031_law_ingest 0032_record_step 0033_file_steps 0034_standalone_stages 0035_playbook_v06; do
  echo "== $m"; sudo docker exec -i eos-postgres psql -U postgres -X -q -v ON_ERROR_STOP=1 -d eos < $m.sql 2>&1 | grep -v NOTICE || { echo "LỖI ở $m"; break; }; done'
ssh vps169 'sudo systemctl restart eos-mcp eos-web; sleep 3; systemctl is-active eos-mcp eos-web'
```
Kiểm: `\d doc.records` có cột `buoc`; `select to_regclass('kb.law_sources'), to_regclass('kb.file_steps')`; `select 'law_ingest' = any(array['x'])` không cần. Chạy `scripts/security_audit.sh` (chỉ đọc) và đọc kết quả.
Cài lại logrotate/housekeeping nếu `scripts/` đổi (xem `docs/17` mục thứ tự triển khai).

## Bước 5 — Runner hồ sơ trên VPS 169
1. **Phụ thuộc pipeline** (hỏi nếu apt đòi gỡ gói khác; không cần pandoc, poppler hay PaddleOCR: OCR là **Tesseract `vie`**, xem `docs/21-ocr-pha2.md`):
   ```bash
   ssh vps169 'sudo apt-get install -y rclone libreoffice-core libreoffice-writer libreoffice-calc tesseract-ocr python3-venv'
   ssh vps169 'sudo python3 -m venv /opt/apps/enterprise-os/venv && sudo /opt/apps/enterprise-os/venv/bin/pip install -r /opt/apps/enterprise-os/pipeline/requirements.txt'
   ```
   Dữ liệu `vie` **bản best** (gói apt `tesseract-ocr-vie` là bản fast, không dùng): tạo `/opt/apps/enterprise-os/tessdata`, chép vào đó `eng.traineddata`, `osd.traineddata` và thư mục `configs/` từ thư mục tessdata của Tesseract (đường dẫn in ở đầu `tesseract --list-langs`), rồi tải `vie.traineddata` (≈12 MB) từ `github.com/tesseract-ocr/tessdata_best/raw/main/vie.traineddata` (VPS 169 phải ra được github.com; không được thì tải ở máy khác và chuyển bằng `scp`). Kiểm: `tesseract --tessdata-dir /opt/apps/enterprise-os/tessdata --list-langs | grep vie`. `deploy/eos-runner.service` đã trỏ `TESSERACT_CMD`, `TESSDATA_DIR`, `SOFFICE_BIN` và dùng python trong venv.
2. User hệ thống: `sudo useradd --system --create-home --home-dir /var/lib/eos-runner --shell /usr/sbin/nologin eos-runner`.
3. ⛔ **rclone với OAuth client riêng, tài khoản ai666 — chủ sở hữu tự đăng nhập** (`sudo -u eos-runner rclone config`, cần trình duyệt: dùng `rclone authorize` ở máy có trình duyệt rồi dán token). Bạn chỉ kiểm `rclone lsd gdrive:` chạy được và thư mục thử có quyền **Người chỉnh sửa**.
4. Mã runner: `scripts/issue_runner_token.sh vps169` (ghi `/etc/eos/runner.env`, 600, chủ `eos-runner`; điều chỉnh đường dẫn nếu script ghi chỗ khác, ghi lại điều đã chỉnh).
5. Service: sửa `__MEMORY_MAX__` trong `deploy/eos-runner.service` theo RAM đo ở Bước 0 (RAM trống trừ dự phòng cho Postgres, WeKnora, MCP), chép vào `/etc/systemd/system/`, `systemctl daemon-reload`.
6. Chạy thử một lần sạch (không in mã: nạp tệp env bằng `.` trong shell con): `sudo -u eos-runner bash -c 'set -a; . /etc/eos/runner.env; set +a; export HOME=/var/lib/eos-runner WORK_DIR=/var/lib/eos-runner/work DEO_SYNC_DIR=/opt/apps/enterprise-os/pipeline SOFFICE_BIN=/usr/bin/soffice TESSERACT_CMD=/usr/bin/tesseract TESSDATA_DIR=/opt/apps/enterprise-os/tessdata; /opt/apps/enterprise-os/venv/bin/python /opt/apps/enterprise-os/runner/eos_z2_runner.py --once'`. Kỳ vọng "không có việc" hoặc xử lý đúng một việc thử. Kiểm thêm một PDF scan nhỏ qua OCR: trang có dấu `[[trang N]]`, độ tin cậy ghi trong `00_MUC_LUC.md`, trang dưới 0,80 nằm ở mục "Cần soát".
7. `systemctl enable --now eos-runner`; kiểm `systemctl status`, `journalctl -u eos-runner -n 30`, thư mục tạm trống sau khi chạy.
8. Z2 đã cài lại Windows 11 nên **không còn runner Z2 để tắt hay để dự phòng**. Chạy một dự án thử trên runner VPS 169 (đối chiếu số tệp `.md` và mục lục với `_md_deo` đã có trên Drive do pipeline cũ sinh ra); không đạt thì `systemctl disable --now eos-runner` và báo, chưa có đường xử lý hồ sơ nào khác cho đến khi sửa xong.

## Bước 6 — Profile Hermes (VPS 173)
Sao lưu `config.yaml` của từng profile trước khi sửa (`cp -a config.yaml config.yaml.bak.$(date +%F-%H%M)`). **Khởi động lại gateway chỉ khi chủ sở hữu đồng ý** ⛔; gateway chạy `--multiplex` cho nhiều profile, khởi động lại ảnh hưởng tất cả.
1. **`eos-phap-che`** (mới) theo chuẩn worker `eos-*` (`prompts/30-vps173.md`): không terminal, không file, không nền tảng chat; **bật web** (SearXNG `127.0.0.1:8888`, kiểm trả JSON); plugin `eos_bridge`; mã MCP: `scripts/issue_agent_token.sh --revoke-old vps169 vps173 phap-che eos-phap-che 90` (phải in phạm vi có `law_ingest`).
2. **`ks-kinh-te-xd`** (đã có SOUL và kênh chat): giữ SOUL và kênh. Thêm `eos_bridge`, mã MCP Enterprise OS (`issue_agent_token.sh … ks-kinh-te-xd ks-kinh-te-xd`), MCP WeKnora **chỉ đọc**, web. **Tắt terminal.** Allowlist Telegram chỉ ID của Tùng (chủ sở hữu cung cấp ID; thêm người khác sau). Khóa WeKnora dạng chữ cũ trong `config.yaml` (nếu còn) chuyển sang `.env` hoặc gỡ, **không in**.
3. Cài skill: `scripts/install_skill.sh vps173 eos-phap-che nap-van-ban-phap-luat`, `… tra-cuu-phap-luat`, `… ra-hieu-luc-phap-luat`, `… so-do-20-buoc`; `eos-quan-tri-du-lieu`: `kb-quan-tri-du-lieu` (1.1.0), `bao-tri-wiki`, `so-do-20-buoc`; `eos-van-thu`: `ho-so-danh-muc` (1.1.0), `so-do-20-buoc`; `eos-dieu-phoi`: `dieu-phoi-du-an` (1.1.0); `team_admin`: `enterprise-os-guide` (1.4.0, chép thư mục, `install_skill.sh` chỉ cài vào profile `eos-*`); `ks-kinh-te-xd`: `qlda-chuan-bi`, `qlda-thuc-hien`, `qlda-ket-thuc`, `so-do-20-buoc`, `tra-cuu-phap-luat` (chép tay vào profile này, có sao lưu).
4. Bật agent ở CSDL: `psql -v company=<uuid> -v law_folder=<id thư mục pháp luật> -f deploy/setup_law.sql`; `setup_agents.sql` (thêm `ks-kinh-te-xd`) và `setup_agent_profiles.sql`; `UPDATE agent.agents SET active = true WHERE code = 'ks-kinh-te-xd'` khi profile sẵn sàng. Chủ sở hữu tạo thư mục Drive pháp luật và chia sẻ quyền **Người chỉnh sửa** cho tài khoản Drive của MCP.

## Bước 7 — Endpoint MCP của WeKnora (chỉ đọc)
- Tạo token **chỉ đọc** cho `ks-kinh-te-xd`, `eos-dieu-phoi`, `eos-van-thu`, `eos-phap-che`, `eos-quan-tri-du-lieu` (quản trị dữ liệu cần đọc Wiki để `wiki_lint`).
- Điền whitelist KB cho `hermes-ops-all`, `hermes-team` (chỉ các KB cần thiết, không dùng `*`).
- Chỉ bật nhóm công cụ **tìm kiếm và đọc**; **tắt** công cụ ghi, sửa Wiki, xóa. Ghi lại tên công cụ Wiki thật để cập nhật skill `bao-tri-wiki`.
- Token ghi vào `.env` từng profile **bằng đường ống SSH**, không in: `ssh vps169 '<lệnh in token>' | ssh vps173 'umask 077; … >> ~/.hermes/profiles/<p>/.env'`.

## Bước 8 — Nghiệm thu (có bằng chứng từng mục)
1. **Nạp hồ sơ KDC Thành Lập** vào KB mới: KB có Wiki; tài liệu có `custom_metadata` (link Drive, mã bước); ảnh tìm được bằng câu hỏi thử.
2. **5 văn bản pháp luật thử** (chủ sở hữu chọn): việc `law_ingest` do Tùng tạo; đúng nguồn chính thống; có trong KB `phap-luat`; một văn bản cũ được đánh dấu hết hiệu lực (không xóa).
3. **Từ chối đúng:** việc `law_ingest` do tài khoản không có quyền tạo bị từ chối; token chỉ đọc gọi công cụ ghi bị từ chối.
4. **`ks-kinh-te-xd`:** hỏi qua chat được trả lời có nguồn; nhận thẻ `buoc_20_kiem` lưu được bảng kiểm lên Drive.
5. **Chạy tay một lần** `wiki_lint` cho KB KDC Thành Lập và `law_review` (`deploy/setup_wiki_maintenance.sql` tạo mẫu, đặt `next_run` về hôm nay cho một mẫu rồi `select work.run_recurrences()` bằng tài khoản quản trị hệ thống, hoặc tạo việc tay cùng phạm vi). Có báo cáo đủ các mục. **Sau khi chủ sở hữu xem** thì bật hai việc định kỳ: `UPDATE work.recurrences SET active = true WHERE …`.
6. `scripts/security_audit.sh` và `make acceptance ONLY=A9` (runner) trên máy thật.

## Báo cáo cuối (theo mẫu `00-MASTER.md`) kèm danh sách việc người làm tiếp
Duyệt skill 20 bước, chọn văn bản pháp luật đầu tiên, thêm người vào allowlist `ks-kinh-te-xd`, chốt bản tổng wiki cho Tùng, xóa volume/DNS Ever Teams khi đủ 30 ngày (không thuộc đợt này).

## Quay lại
- Mã/migration: triển khai lại bản trước (`v0.5.0`) và khởi động lại `eos-mcp`, `eos-web`; cột/bảng mới tương thích ngược (các lệnh `down:` ở đầu từng migration nếu phải gỡ).
- WeKnora: khôi phục dump, volume `data-files` và image v0.8.2 theo kế hoạch đã chủ sở hữu duyệt ở Bước 2.
- Runner: `systemctl disable --now eos-runner` (không còn runner Z2 để bật lại; việc xử lý hồ sơ dừng đến khi sửa xong).
- Profile: chép lại `config.yaml.bak.*`, khởi động lại gateway khi chủ sở hữu đồng ý. `UPDATE agent.agents SET active = false WHERE code IN ('phap-che','ks-kinh-te-xd')`; `UPDATE work.recurrences SET active = false WHERE agent_code IS NOT NULL`.
