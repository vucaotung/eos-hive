# 03 · Sổ tay vận hành (handbook)

Dành cho người giữ máy chủ. Mọi lệnh giả định bạn đã SSH vào đúng máy. **Không dán mật khẩu, mã, khóa vào chat hay vào git.**

## 1. Bản đồ máy

| Máy | Địa chỉ | Chạy | Đường dẫn chuẩn |
| --- | --- | --- | --- |
| VPS 169 | 169.58.107.168 | Postgres, PostgREST, MCP, Caddy (systemd, `/etc/caddy/Caddyfile`), WeKnora | `/opt/apps/enterprise-os/` |
| VPS 173 | 173.249.51.69 | Hermes (`hermes-gateway.service`, systemd *user*), cầu nối, Caddy (Docker `company-caddy`) | `/opt/apps/enterprise-os/bridge/`, `~/.hermes/eos_bridge/` |
| Z2 | máy tại chỗ, Ubuntu 26.04 | Phát triển, Claude Code, Docker, kéo sao lưu | `~/src/eos-hive` |

Cổng nội bộ: MCP `127.0.0.1:8790`, PostgREST `127.0.0.1:3000` (đề xuất), Hermes api_server `127.0.0.1:8646`. **Không** mở các cổng này ra Internet; chỉ Caddy (80/443) ra ngoài.

## 2. Thứ tự triển khai lần đầu

Làm đúng thứ tự; mỗi bước có cổng kiểm tra, không qua bước sau nếu chưa đạt.

1. **Z2**: clone repo, `make test` (cổng: ba bộ kiểm thử đều xanh).
2. **VPS 169 — CSDL**: tạo CSDL `eos`, nạp 9 tệp (cổng: 108 bảng, 5 view; `test_agent.sql` chạy trên CSDL *thử*, không chạy trên CSDL thật vì nó tự ROLLBACK nhưng tạo vai trò).
3. **VPS 169 — vai trò đăng nhập**: `eos_mcp` (trong `mcp_svc`), `authenticator` (PostgREST). Mật khẩu sinh ngẫu nhiên, cất trong `.env` quyền 600.
4. **VPS 169 — PostgREST**: schema `agent`, anon `nobody_anon`, `JWT_SECRET` ≥ 32 ký tự. Cổng: `curl -s localhost:3000/rpc/outbox_pull` không JWT trả 401.
5. **VPS 169 — MCP**: `npm ci`, `.env`, `eos-mcp.service`, đoạn Caddy `handle /mcp*`. Cổng: trên VPS 169 `curl -s 127.0.0.1:8790/healthz` → `{"ok":true}`; `curl -s -XPOST https://work.enterpriseos.bond/mcp -H 'Authorization: Bearer eos_sai'` → 401.
6. **VPS 169 — khởi tạo**: tạo công ty/phòng/người (giai đoạn 1 sẽ có màn hình; tạm thời bằng SQL), chạy `deploy/setup_agents.sql -v company=<uuid>`.
7. **VPS 173 — Hermes**: tạo 4 profile riêng `eos-dieu-phoi`, `eos-van-thu`, `eos-nhan-su`, `eos-quan-tri-du-lieu` (`phap-che` chưa tạo profile: chưa định nghĩa) (không dùng `ops-admin`: nó có terminal root), gateway nhiều profile đã `--multiplex`. Cổng: `hermes kanban --help` chạy được.
8. **VPS 173 — kiểm chứng giả định** (`docs/07`): bắt buộc làm *trước* khi bật cầu nối.
9. **VPS 173 — cầu nối**: chép plugin, `.env` với JWT `agent_bridge`, bật `eos-kanban-bridge.service`.
10. **Cả ba — khói đầu–cuối** (mục 7).

## 3. Cài đặt từng dịch vụ

### 3.1 CSDL (VPS 169)

    sudo -u postgres createdb eos
    cd /opt/apps/enterprise-os/db
    for f in 00_core 10_work 20_doc 30_hr 31_payroll_kpi 40_crm 45_kb 50_views 60_agent; do
      sudo -u postgres psql -X -q -v ON_ERROR_STOP=1 -d eos -f $f.sql || break
    done
    sudo -u postgres psql -X -d eos -c "CREATE ROLE eos_mcp LOGIN PASSWORD '…' IN ROLE mcp_svc"
    sudo -u postgres psql -X -d eos -c "CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD '…'; GRANT agent_bridge TO authenticator"

Nếu Postgres chạy trong Docker, thay `sudo -u postgres psql` bằng `docker exec -i <container> psql -U postgres`. Kiểm tra: `select count(*) from information_schema.tables where table_schema in ('core','work','doc','hr','crm','kb','agent') and table_type='BASE TABLE' and table_name not like 'audit_log_20%'` → 108.

### 3.2 PostgREST

`/etc/eos/postgrest.conf` (quyền 600): `db-uri` (user `authenticator`), `db-schemas = "agent"`, `db-anon-role = "nobody_anon"` (tạo vai trò NOLOGIN này), `jwt-secret`, `server-port = 3000`, `server-host = "127.0.0.1"`. Đơn vị systemd `postgrest-eos.service`. Caddy: `handle /api/* { uri strip_prefix /api; reverse_proxy 127.0.0.1:3000 }` — thêm giới hạn tốc độ nếu Caddy có module.

JWT cầu nối: dùng script để bí mật đi thẳng từ VPS 169 sang VPS 173, không hiện ra màn hình hay chat:

    scripts/issue_bridge_token.sh vps169 vps173 90      # chạy từ máy có SSH tới cả hai (Z2)

Script đọc `jwt-secret` trên VPS 169, ký JWT vai trò `agent_bridge` (hạn 90 ngày) bằng `deploy/mint_bridge_jwt.py` và ghi `~/.hermes/eos_bridge/.env` (600) trên VPS 173. Hạn 90 ngày: đặt nhắc đổi trước ngày 80.

### 3.3 MCP

    cd /opt/apps/enterprise-os/mcp && npm ci --omit=dev
    cp ../deploy/eos-mcp.env.example .env && chmod 600 .env     # điền DATABASE_URL, GOOGLE_*
    sudo cp ../deploy/eos-mcp.service /etc/systemd/system/ && sudo systemctl daemon-reload
    sudo systemctl enable --now eos-mcp && journalctl -u eos-mcp -n 30
    # Caddyfile: thêm deploy/Caddyfile.mcp.snippet vào khối work.enterpriseos.bond
    caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy

Biến `.env`: `DATABASE_URL`, `PORT=8790`, `MCP_RATE_PER_MIN=120`, `GOOGLE_CLIENT_ID/SECRET/REFRESH_TOKEN` (tài khoản agent Workspace, cùng bộ với `drive_sync.py`). Tài khoản Workspace phải là **Người chỉnh sửa** trên thư mục Drive của từng người, và refresh token phải cấp với phạm vi đầy đủ `https://www.googleapis.com/auth/drive` (phạm vi `drive.file` không thấy được thư mục do người khác chia sẻ → mọi lần lưu sẽ lỗi 404).

### 3.4 Cầu nối (VPS 173)

    mkdir -p ~/.hermes/eos_bridge && chmod 700 ~/.hermes/eos_bridge
    cp deploy/eos-kanban-bridge.env.example ~/.hermes/eos_bridge/.env && chmod 600 ~/.hermes/eos_bridge/.env   # điền EOS_BRIDGE_TOKEN
    # plugin: chép bridge/hermes_plugin/eos_bridge vào thư mục plugin của Hermes (xem docs/07, giả định A11–A12), bật cho các profile eos-*
    cp deploy/eos-kanban-bridge.service ~/.config/systemd/user/ && systemctl --user daemon-reload
    systemctl --user enable --now eos-kanban-bridge && journalctl --user -u eos-kanban-bridge -n 30
    python3 bridge/eos_kanban_bridge.py --once        # chạy thử một lượt, đọc kết quả

Dịch vụ systemd *user* chỉ chạy khi đăng nhập trừ khi bật lingering: `loginctl enable-linger $USER` (cùng cách `hermes-gateway.service` đang chạy).

### 3.5 Khởi tạo agent cho một công ty

    psql -d eos -v ON_ERROR_STOP=1 -v company=<uuid-công-ty> -f deploy/setup_agents.sql

Tạo 4 agent, bật cho công ty, đặt board `eos-<slug>`. Rồi cấp mã MCP cho từng agent hệ thống (để worker đọc việc). Hàm chỉ cho **quản trị hệ thống** cấp, nên dùng script (nó đặt danh tính quản trị trong cùng giao dịch và đưa mã thẳng vào `.env` của profile Hermes, không hiện ra):

    scripts/issue_agent_token.sh vps169 vps173 quan-tri-du-lieu eos-quan-tri-du-lieu 90

Mã chỉ hiện đúng một lần và script không in nó; mất thì thu hồi (`agent.mcp_token_revoke`) và cấp lại. **Cấp lại không tự vô hiệu mã cũ** — thu hồi mã cũ ngay (mỗi tài khoản agent tối đa 5 mã còn hạn).

## 4. Việc định kỳ

| Tần suất | Việc | Lệnh / nơi |
| --- | --- | --- |
| Hằng ngày | Sao lưu CSDL (thêm `eos` vào `/opt/backup/backup.sh`, mã hóa `-pbkdf2 -iter 600000`); Z2 kéo 04:00 | xem §5 |
| Hằng ngày | Thẻ kẹt, hộp thư đi lỗi | §6 truy vấn "sức khỏe" |
| Hằng tuần | Xem `agent.mcp_calls` bất thường (nhiều `denied`) | §6 |
| Hằng tháng | **Khôi phục thử** bản sao lưu mới nhất vào Postgres rỗng trên Z2, đếm 108 bảng và số dòng chính | §5 |
| Mỗi 80 ngày | Đổi JWT cầu nối, đổi mã agent hệ thống | §3.2, §3.5 |
| Mỗi năm, **trước 01/12** | Tạo phân vùng `core.audit_log_<năm+1>` | §4.1 |
| Khi người nghỉ việc | Khóa tài khoản và thu hồi mã MCP | §4.2 |

### 4.1 Phân vùng nhật ký năm tới
Hiện có phân vùng 2026 và 2027, **không có phân vùng mặc định**: từ 01/01/2028 mọi lần ghi nhật ký sẽ lỗi nếu chưa tạo.

    CREATE TABLE core.audit_log_2028 PARTITION OF core.audit_log FOR VALUES FROM ('2028-01-01') TO ('2029-01-01');

### 4.2 Thu hồi mã MCP
    select agent.mcp_token_revoke(<token_id>);           -- một mã
    update agent.mcp_tokens set revoked_at = now() where user_id = '<uuid>' and revoked_at is null;  -- cả người

## 5. Sao lưu và khôi phục

Đã có: `/opt/backup/backup.sh` trên VPS 169 → `/var/backups/deo` (dump mã hóa), Z2 kéo về `~/backups/deo169` lúc 04:00. **Việc cần làm**: thêm CSDL `eos` vào dump.

    pg_dump -U postgres -Fc eos | openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -md sha512 -salt -pass file:/root/.backup_pass -out /var/backups/deo/eos_$(date +%F).dump.enc

Khôi phục thử (trên Z2):

    openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -md sha512 -pass file:… -in eos_YYYY-MM-DD.dump.enc | docker exec -i restore-pg pg_restore -U postgres -d eos --no-owner
    docker exec restore-pg psql -U postgres -d eos -Atc "select count(*) from core.users"

Ghi kết quả (ngày, số bảng, số dòng) vào nhật ký vận hành. **Không có phép khôi phục thì không có sao lưu.**

Mã MCP lưu băm; khôi phục không làm lộ mã nhưng người dùng phải tạo lại mã nếu bạn khôi phục bản cũ hơn ngày họ tạo.

## 6. Giám sát: truy vấn sức khỏe

    -- thẻ gửi đi quá 10 phút chưa được kéo/ack
    select id, kind, task_id, created_at, error from agent.outbox where done_at is null and created_at < now() - interval '10 minutes';
    -- thẻ Kanban kẹt "running" quá 2 giờ
    select card_id, task_id, status, last_event_at from agent.cards where status = 'running' and last_event_at < now() - interval '2 hours';
    -- xác nhận L2 sắp hết hạn
    select id, task_id, expires_at from agent.confirmations where state = 'pending' and expires_at < now() + interval '12 hours';
    -- mã MCP bị từ chối nhiều
    select token_id, count(*) from agent.mcp_calls where outcome = 'denied' and at > now() - interval '1 day' group by 1 having count(*) > 20;

Các truy vấn trên đã chạy thử trên CSDL thử v0.0.0. Nếu đổi lược đồ, chạy lại chúng.

## 7. Kiểm thử khói sau mỗi lần triển khai

1. Trên VPS 169: `curl -s 127.0.0.1:8790/healthz` → `{"ok":true}` (Caddy chỉ chuyển `/mcp*`, `/healthz` không ra ngoài).
2. Tạo mã MCP thử, gọi `eos_whoami` (qua MCP Inspector hoặc `curl` JSON-RPC) → thấy đúng tên người.
3. Tạo việc thử giao cho agent `quan-tri-du-lieu` → trong ≤ 2 phút thấy thẻ ở board `eos-<slug>` (`hermes kanban list --board eos-<slug>`).
4. Cho agent `kanban_block` → việc chuyển Vướng, câu hỏi hiện ở `work.comments`; trả lời → thẻ chạy lại.
5. `kanban_complete` với tóm tắt hợp lệ → việc sang Chờ xem; người chấp nhận → Xong.
6. Dọn việc thử (hủy việc, `hermes kanban archive`).

### 7.1 Nghiệm thu tự động trên máy thật

    make acceptance                 # mọi kịch bản (~35 phút, tốn token LLM thật)
    make acceptance ONLY=A2         # chỉ A2 (30 giây, không tốn LLM)

Chạy từ Z2 (cần `ssh vps169`, `ssh vps173`, `node ≥ 22`, `npm ci` trong `mcp/`). Mỗi kịch bản tạo việc gắn nhãn `[ACCEPT <mã-lượt>]` cho agent thật, kiểm từng cổng, rồi **dọn** (hủy việc, thu hồi mã thử, archive thẻ, bật lại cầu nối) kể cả khi lỗi. Nhật ký ở `ops-log/acceptance-<mã-lượt>.md`.

| Kịch bản | Chứng minh |
| --- | --- |
| A1 Vòng đời | giao việc → thẻ → hỏi lại → trả lời → báo xong → chấp nhận; báo cáo không trùng |
| A2 Quyền MCP | 15 công cụ; mã sai bị từ chối; thiếu phạm vi `hr_self` bị từ chối; việc không tồn tại báo lỗi |
| A3 Làm lại | trả kết quả có lý do → thẻ `rework` lượt 2 kèm lý do → xong |
| A4 Hủy việc | hủy việc → lệnh `cancel` → thẻ Kanban archive |
| A5 Chịu lỗi | dừng cầu nối → lệnh nằm chờ → chạy lại → đúng một thẻ |
| A6 Chia việc con | Điều phối chia 2 việc con (Văn thư, Nhân sự) → mỗi việc đúng profile → tự Xong → đúng một thẻ tổng hợp → chờ xem → chấp nhận |
| A7 Văn thư soạn NĐ30 | đủ thông tin → dự thảo .docx gắn vào việc do `agent:van-thu`, không điền ngày, vẫn là dự thảo; thiếu thông tin → chặn hỏi, không tạo tệp (`docs/09`) |

Chạy sau mỗi lần nâng cấp mã hoặc Hermes. Thêm kịch bản: hàm `s_An` trong `scripts/acceptance.sh`, dùng `check` (cổng bắt buộc) hoặc `xcheck` (lỗi đã biết, kèm lý do).

### 7.2 Kiểm toán bảo mật và diễn tập khôi phục

    make audit                       # chỉ đọc, ~1 phút: quyền tệp, bề mặt mạng, hạn mã, agent, sao lưu
    make restore-drill               # khôi phục eos.dump bản sao lưu mới nhất vào Postgres rỗng trên Z2 (~1 phút)
    make restore-drill FRESH=1       # chạy backup.sh trước (~6 phút) để so khớp tuyệt đối

Chạy `make audit` hằng tuần và sau mỗi thay đổi hạ tầng; `make restore-drill` hằng tháng (mục 4). Cảnh báo "còn N ngày" của mã agent/JWT cầu nối là nhắc đổi mã (ngưỡng 14 ngày).

## 8. Nâng cấp

- **Mã (MCP/cầu nối)**: `git pull` (tag) → `npm ci` → `systemctl restart`. Cầu nối an toàn khi khởi động lại (idempotent).
- **Lược đồ**: chỉ qua migration (`docs/02`), sau sao lưu. Hàm `CREATE OR REPLACE` có thể nạp lại trực tiếp; bảng thì không.
- **Hermes**: sau mỗi lần nâng cấp, chạy lại kiểm chứng giả định (`docs/07`) — dạng JSON và hook có thể đổi.
- **Node/Postgres**: nâng bản vá ngay; nâng bản chính phải chạy `make test` trước.

## 9. Quy tắc an toàn khi thao tác

- Đọc trước, sao lưu, sửa, kiểm tra, có đường quay lại. Lệnh xóa/ghi đè luôn hỏi người có quyền trước.
- Không `docker compose -p <đoán> down`: kiểm nhãn thật bằng `docker inspect … com.docker.compose.project`.
- Không chạm volume `proxy_caddy_*` và các volume Grafana/Loki/Promtail trên VPS 173.
- UFW trên VPS 173 chặn cầu docker `172.19.0.0/16` quay vào host: cổng mới cho Caddy phải thêm luật `ufw allow from 172.19.0.0/16 to any port <cổng>`.
- Không chạy `hermes-gateway-ops-admin.service` riêng (xung đột với instance nhúng trong dashboard).

## 10. Nhật ký vận hành

Thêm một dòng mỗi lần triển khai, khôi phục thử hoặc sự cố. Không ghi bí mật.

| Ngày | Máy | Việc | Kết quả | Người |
| --- | --- | --- | --- | --- |
| 2026-10-19 | — | Phát hành v0.0.0 (chưa triển khai máy thật) | kiểm thử CSDL 108 bảng, MCP 16 bước, cầu nối 7 bước (Hermes giả lập) | Claude |
| 2026-10-19 | z2 | Pha 1: kiểm thử + GitHub riêng tư + SSH tới 2 VPS | test-db 108/5, test-mcp 16, test-bridge 7; CI xanh | Claude + Tùng |
| 2026-10-19 | vps169 | Pha 2: Postgres 16 riêng (5434), PostgREST (3200), MCP (8790), Caddy work.enterpriseos.bond, công ty Valnex, 5 agent, sao lưu thêm `eos.dump` | 108 bảng/5 view; mã sai 401; /api ngoài 403 | Claude + Tùng |
| 2026-10-19 | vps173 | Pha 3: 4 profile eos-*, plugin + cầu nối, kiểm chứng A1–A9/A11–A17 với Hermes 0.22.1, sửa cầu nối | fixtures 7 bước; worker đọc MCP | Claude + Tùng |
| 2026-10-20 | cả ba | Pha 4: nghiệm thu đầu–cuối (T-1 hỏi–đáp–xong, T-2), ghi Drive thật, khôi phục thử trên Z2 | khôi phục: 108 bảng, work.tasks 2, agent.reports 2 khớp VPS 169 | Claude + Tùng |
