# 00 · MASTER — bối cảnh và luật chung

## Dự án
**Tổ Ong (eos-hive)**: Enterprise OS nhiều công ty, nhiều phòng ban (công việc, công văn NĐ 30, nhân sự–lương–KPI, kho dữ liệu chung, CRM) trong đó **AI agent là thành viên**: nhận việc qua Hermes Kanban, báo cáo để người duyệt; agent cá nhân của từng người nối qua MCP, ghi kết quả vào Drive cá nhân. Chủ sở hữu: Tùng (vucaotung). Ngôn ngữ làm việc: **tiếng Việt**.

Đọc để hiểu: `docs/00-tong-quan.md`, `docs/01-kien-truc.md`.

## Ba máy

| Bí danh SSH | Máy | Vai trò | Ghi chú đã biết |
| --- | --- | --- | --- |
| `z2` | HP Z2 Mini G4, Ubuntu 26.04, user `vincent`, Docker + NVIDIA đã có, 4 core / 16 GB | Phát triển, kiểm thử, Claude Code, kéo sao lưu | Wayland (không Xorg); đã có `rclone` tới Drive của chủ; cron kéo sao lưu 04:00 từ VPS 169 về `~/backups/deo169` |
| `vps169` | 169.58.107.168 | Postgres, PostgREST, MCP, Caddy, WeKnora, Ever Teams (đang chạy) | Caddy chạy bằng **systemd** (`/etc/caddy/Caddyfile`); sao lưu `/opt/backup/backup.sh` → `/var/backups/deo`; mọi cổng hạ tầng bind `127.0.0.1` |
| `vps173` | 173.249.51.69 | Hermes Agent (gateway `--multiplex` cho 5 profile), Caddy trong Docker `company-caddy`, SearXNG, 9router | Hermes chạy bằng `hermes-gateway.service` (systemd **user**); UFW chặn cầu Docker `172.19.0.0/16` quay vào host |

Bí danh SSH có thể chưa cấu hình. Nếu thiếu: hỏi người dùng địa chỉ/user/khóa; tuyệt đối không đoán mật khẩu. Chưa biết: Postgres trên VPS 169 chạy trong Docker hay trên host → **phát hiện bằng lệnh chỉ-đọc** trước (xem `20-vps169.md` bước 0).

## Luật không thương lượng

### Bí mật
1. Không in/ghi log/đưa vào chat: nội dung `.env`, mã `eos_…`, JWT, khóa riêng, mật khẩu, refresh token. Khi cần kiểm tra tệp bí mật chỉ in **tên khóa và độ dài giá trị** (`awk -F= '{print $1, length($2)}'`).
2. Sinh bí mật ngay trên máy đích (`openssl rand -hex 24`), ghi bằng `umask 077`. Chuyển giữa hai máy bằng đường ống SSH không qua biến shell của bạn: `ssh A 'lệnh in bí mật' | ssh B 'umask 077; cat > tệp'`.
3. Giá trị Google (`GOOGLE_*`), mật khẩu sao lưu: người dùng tự nhập vào tệp trên máy đích. Bạn chỉ kiểm tra tệp có khóa đó và độ dài > 0.
4. Trước mỗi commit chạy `scripts/check_secrets.sh`. Bí mật đã lộ vào chat/log = coi như hỏng, báo người dùng đổi.
5. Mật khẩu root của VPS từng bị dán vào chat trước đây: nhắc người dùng chuyển sang khóa SSH và đổi mật khẩu; đừng xin lại nó.

### An toàn thao tác
6. **Đọc trước khi ghi.** Mỗi pha mở đầu bằng lệnh chỉ-đọc, báo hiện trạng.
7. **Sao lưu trước khi sửa** tệp cấu hình hiện có (`cp -a tệp tệp.bak.$(date +%F-%H%M)`), và dump CSDL trước khi động tới nó.
8. **Không xóa, không ghi đè** thứ không phải do bạn tạo trong phiên này. Muốn dọn: chuyển vào `_to_delete/` cùng thư mục và báo.
9. **Không đụng**: Ever Teams (12 container, CSDL của nó), WeKnora, Grafana/Loki/Promtail và volume của chúng, volume `proxy_caddy_config`/`proxy_caddy_data`, `evidence-db`, các profile Hermes ngoài `ops-admin` và `eos-*`, `hermes-gateway-ops-admin.service` (đã tắt có chủ đích).
10. Không `docker compose -p <đoán> down`. Không `rm -rf` ngoài thư mục tạm của bạn. Không `git push --force`. Không `chmod 777`.
11. Cấu hình Caddy: `caddy validate` trước, reload sau; giữ bản `.bak`. Trên VPS 173 Caddy ở Docker: `docker exec company-caddy caddy reload --config /etc/caddy/Caddyfile`; cổng mới cho Caddy cần luật `ufw allow from 172.19.0.0/16 to any port <cổng> proto tcp`.
12. Cổng dịch vụ nội bộ chỉ bind `127.0.0.1`. Bảng điều khiển/API Hermes Kanban **không xác thực**: không bao giờ mở ra ngoài.
13. Mỗi lệnh có thể treo (docker, apt, build) cho timeout rõ ràng; kiểm tra trạng thái sau, đừng giả định.

### Ranh giới việc của bạn
14. Chỉ làm điều có trong prompt pha hiện tại. Gặp điều khác thường (dịch vụ lạ, cổng bận, CSDL `eos` đã tồn tại, schema `core`/`work` đã tồn tại trong CSDL khác): **dừng và hỏi**.
15. Mã trong repo là nguồn sự thật. Nếu phải sửa mã để chạy được trên máy thật (đặc biệt `bridge/` theo `docs/07`): làm trên nhánh `fix/…`, có kiểm thử, ghi `CHANGELOG.md`; không sửa trực tiếp trên VPS.
16. Triển khai mã lên VPS bằng `scripts/push_to_host.sh` (chép bản đã commit, không cần GitHub trên VPS). Không cài khóa GitHub lên VPS.
17. Không bật tính năng chưa có trong v0.0.0 (OAuth MCP, routing rules, `auto_done`).

## Cách báo cáo cuối mỗi pha (≤ 15 dòng)
```
PHA <n> — <tên> — <ĐẠT | ĐẠT CÓ GHI CHÚ | CHƯA ĐẠT>
Máy: <hostname>  Commit: <sha ngắn>  Thời gian: <phút>
Cổng:  [x] ...  [x] ...  [ ] ... (lý do)
Thay đổi trên máy: <liệt kê tệp/dịch vụ đã tạo hoặc sửa>
Cần người dùng làm: <danh sách, nếu có>
Rủi ro/điều bất thường: <...>
Quay lại bằng: <lệnh hoặc mục trong 90-rollback.md>
```
Không dán log dài; đường dẫn tới `ops-log/` là đủ.

## Định nghĩa "xong"
Một pha chỉ ĐẠT khi **mọi Cổng** của nó có bằng chứng bạn đã thấy (đầu ra lệnh), không phải suy luận. Nếu không kiểm được một cổng, ghi "chưa kiểm" và nêu lý do; đừng đánh dấu đạt.
