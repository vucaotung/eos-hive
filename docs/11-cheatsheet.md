# 11 · Cheatsheet

Tra nhanh. Chi tiết: `docs/03` (triển khai), `docs/06` (bảo mật), `docs/10` (web).

## Máy và địa chỉ
| Máy | Vai trò | Ghi chú |
| --- | --- | --- |
| Z2 | máy phát triển, chạy test, nghiệm thu, kéo sao lưu | Docker `eos-pg` (cổng 5433) cho test; DSN ở `~/.config/eos-hive/pg.env` |
| vps169 | Postgres (`eos-postgres`, 127.0.0.1:5434), PostgREST :3200, MCP :8790, web :8791, Caddy | thư mục `/opt/apps/enterprise-os`; `ssh vps169` |
| vps173 | Hermes (gateway, profile `eos-*`), cầu nối `eos-kanban-bridge` | `ssh vps173`; systemd user |
| Web | `https://work.enterpriseos.bond/app` (gốc `/` chuyển sang `/app/`) | MCP: `/mcp` |

## Lệnh `make`
| Lệnh | Làm gì |
| --- | --- |
| `make test` | cả bốn bộ test (CSDL, MCP, web, cầu nối); cần `EOS_TEST_DSN` (`set -a; . ~/.config/eos-hive/pg.env; set +a`) |
| `make test-db` / `test-mcp` / `test-web` / `test-bridge` | từng bộ |
| `make ui` | dựng giao diện `web/ui` → `web/public` (**phải commit kết quả**) |
| `make acceptance [ONLY=A8]` | nghiệm thu trên máy thật A1–A8 (A1–A7 tốn LLM, A8 chỉ web) |
| `make audit` | kiểm toán bảo mật chỉ đọc (checklist `docs/06`) |
| `make restore-drill [FRESH=1]` | diễn tập khôi phục sao lưu vào Postgres rỗng |
| `make secrets` | quét bí mật trước khi commit |

## Phát hành một thay đổi (quy trình đã dùng)
1. Nhánh `feat/…`, sửa; **đổi lược đồ**: sửa `db/*.sql` **và** viết `db/migrations/000N_….sql` (idempotent, có `-- down:`).
2. `make test`; nếu đụng giao diện: `make ui`; `make secrets`; commit.
3. Thử migration trên CSDL dựng từ lược đồ **commit trước**, so `pg_dump --schema-only` với bản dựng mới (khác nhau chỉ ở `\restrict`).
4. Triển khai: sao lưu `docker exec eos-postgres pg_dump -U postgres -Fc eos > /root/eos-pre-000N-….dump` → áp migration → `scripts/push_to_host.sh vps169 /opt/apps/enterprise-os` (yêu cầu cây sạch, chỉ chép `db mcp web bridge deploy docs scripts VERSION`) → `chown -R eos:eos web`, `systemctl restart eos-web`.
5. `make acceptance ONLY=A8` và `make audit`; cập nhật `CHANGELOG.md`, `VERSION`; merge `main`, tag `vX.Y.Z`, push.

## Dịch vụ (vps169)
    systemctl status|restart eos-web          journalctl -u eos-web -n 50
    systemctl status eos-mcp postgrest caddy  systemctl reload caddy      # sau khi sửa /etc/caddy/Caddyfile (có .bak.*; caddy validate trước)
    docker exec -it eos-postgres psql -U postgres -d eos
Cầu nối (vps173): `systemctl --user status eos-kanban-bridge`; nhật ký `journalctl --user -u eos-kanban-bridge`.

## Cấu hình web (`/opt/apps/enterprise-os/web/.env`, 600, chủ `eos`)
`PUBLIC_URL`, `DATABASE_URL` (tài khoản `eos_web`), `SESSION_SECRET` (đổi = đăng xuất mọi người), `GOOGLE_LOGIN_CLIENT_ID/SECRET`, `AGENT_DRIVE_EMAIL`, `MCP_URL`, `LOGIN_RATE_PER_MIN` (30), `API_RATE_PER_MIN` (600). Sửa xong: `systemctl restart eos-web`. Không bao giờ dán giá trị vào chat/git.

## Người dùng và quyền (trong ứng dụng)
| Việc | Cách làm |
| --- | --- |
| Mời người | Quản trị → Mã mời → Tạo mã → gửi **link mời** (`/app/#/login?code=…`) hoặc mã 8 ký tự |
| Đổi vai trò / khóa | Quản trị → Thành viên → Sửa (owner · admin · manager = trưởng phòng · member) |
| Tạo phòng, quy trình duyệt | Quản trị → Phòng ban / Quy trình duyệt (1–6 bước) |
| Dự án (thêm, cài đặt, thành viên, xóa) | tab **Dự án** |
| Cấp mã MCP cho AI cá nhân | Tài khoản → Kết nối AI agent (mã chỉ hiện một lần, tối đa 5 mã/người) |
| Khóa ngay một người | `UPDATE core.users SET active=false WHERE email='…';` (có hiệu lực ở lệnh gọi kế tiếp) |

Vai trò: owner/admin cả công ty · trưởng phòng và thành viên theo phòng + việc mình giao/làm/duyệt. Công ty luôn còn ≥1 owner.

## Việc và duyệt
- Trạng thái: Chờ làm → Đang làm ⇄ Vướng → Chờ duyệt → Xong (hoặc Đã hủy).
- Nộp việc: có quy trình thì mở yêu cầu duyệt; không có thì Xong ngay. Trả lại phải ghi lý do, việc về Đang làm, nộp lại = vòng mới.
- Việc giao agent: agent nộp → người giao **Chấp nhận / Trả lại** (mục Duyệt) → có quy trình thì sang các bước duyệt. Agent hỏi: trả lời ngay trong ngăn chi tiết. Quá `max_rework` lần làm lại thì việc trả về người.

## Agent và MCP
- Agent: `dieu-phoi`, `van-thu`, `nhan-su`, `quan-tri-du-lieu`, (`phap-che` chưa định nghĩa). Mức tự chủ L0 đọc · L1 tự làm · L2 xin xác nhận · L3 chỉ người.
- MCP: máy chủ `https://work.enterpriseos.bond/mcp`, tiêu đề `Authorization: Bearer <mã eos_…>`. Phạm vi: `read write drive kb hr_self` (người), `draft`/`delegate` chỉ cấp cho agent hệ thống.
- Quản trị agent: Quản trị → tab **Agent và MCP** (người có `is_system_admin`): cầu nối, thẻ kẹt, mã sắp hết hạn, nhật ký gọi.

## Sự cố thường gặp
| Triệu chứng | Kiểm tra |
| --- | --- |
| Web 502/trống | `systemctl status eos-web`; `curl -s localhost:8791/app/healthz` (cần `Host: work.enterpriseos.bond`) |
| Đăng nhập báo "chưa được cấp quyền" | email chưa có tài khoản → cần mã mời; hoặc tài khoản bị khóa; `journalctl -u eos-web \| grep login_denied` |
| Lỗi 500 có "Mã tham chiếu" | `journalctl -u eos-web \| grep <mã>` |
| Giao việc cho agent báo "chưa bật" | `agent.company_settings.enabled` và `agent.company_agents` của công ty |
| Việc agent kẹt "đang chạy" | tab Agent và MCP (thẻ kẹt > 2 giờ); cầu nối trên vps173 |
| Giao diện cũ sau khi triển khai | Ctrl+F5; kiểm `web/public/index.html` trỏ tới `assets/index-….js` có thật |
| CI đỏ ở "Giao diện dựng khớp" | quên `make ui` trước khi commit |

## Nạp hồ sơ dự án (docs/12)
- Bắt đầu: Dự án → **Nạp hồ sơ dự án** (link Drive + người theo dõi). Điều phối chia việc; runner Z2 xử lý; Văn thư lập danh mục; Pháp chế rà soát; người nạp WeKnora trả lời `kb:<mã>`.
- Runner Z2: `systemctl --user status eos-z2-runner`; `journalctl --user -u eos-z2-runner -f`; thử một lần `python3 runner/eos_z2_runner.py --once`; cấp lại mã `scripts/issue_runner_token.sh vps169`.
- Phạm vi của việc: ngăn chi tiết việc, hoặc `SELECT task_id, skill, scope FROM agent.task_scopes WHERE run_id = …`.
- Cài skill: `scripts/install_skill.sh vps173 eos-van-thu ho-so-danh-muc`.

## Việc còn mở
Kiểm tra thư mục Drive của người dùng; thông báo đẩy; tải tệp; việc lặp lại; L2 có cấu trúc trên giao diện; RLS; đổi mật khẩu root/SSH khóa; UFW vps169; giới hạn tốc độ ở Caddy; thông số Valnex cho Văn thư AI (chờ tài liệu KB); định nghĩa agent `phap-che`.
