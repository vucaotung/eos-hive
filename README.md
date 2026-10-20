# Tổ Ong (eos-hive) — Enterprise OS có AI agent làm việc cùng người

Phiên bản **0.0.0** (nền móng, chưa chạy trên máy thật). Hệ thống quản trị nhiều công ty, nhiều phòng ban: công việc, công văn (NĐ 30), nhân sự – lương – KPI, kho dữ liệu chung, CRM. AI agent là thành viên có vai trò rõ: nhận việc qua **Hermes Kanban**, báo cáo hoàn thành để người duyệt; agent cá nhân của từng người đọc và ghi kết quả vào **Drive cá nhân** qua **MCP**.

## Một hình để nhớ

    Người ──(app web)──► Postgres (nguồn sự thật)  ◄──(MCP)── Agent cá nhân của từng người
                              │  ▲                                  └─► Drive cá nhân (nội dung tệp)
                    hộp thư đi │  │ sự kiện
                              ▼  │
                       Cầu nối (không LLM) ◄──► Hermes Kanban ──► Agent phân hệ (Điều phối, Văn thư, Nhân sự, Quản trị dữ liệu, Pháp chế)

- **Postgres là sổ gốc.** Người phụ trách luôn là người thật (được tính KPI); agent chỉ là người thực hiện.
- **Kanban chỉ là hàng đợi chạy việc** của agent, một board mỗi công ty. Người dùng không cần mở Kanban.
- **Nội dung tệp nằm ở Drive từng người.** Máy chủ chỉ giữ siêu dữ liệu và link (ngoại lệ có tài liệu: Kho dữ liệu chung).
- **Việc không đảo ngược được thì người làm** (duyệt, cấp số công văn, chốt lương, xóa): mức L3, hệ thống chặn agent.

## Bắt đầu nhanh (trên máy có Postgres 16)

    export EOS_TEST_DSN=postgres://postgres:MẬT_KHẨU@127.0.0.1:5432/eos_test   # CSDL _test sẽ bị xóa và dựng lại
    make test            # test-db (108 bảng) + test-mcp (16 bước) + test-bridge (7 bước, cần postgrest)

Chưa có Postgres: `docker run -d --name eos-pg -e POSTGRES_PASSWORD=pw -p 5432:5432 postgres:16`.

## Bản đồ thư mục

| Thư mục | Nội dung |
| --- | --- |
| `db/` | 9 tệp lược đồ (00→60), 2 tệp kiểm thử SQL |
| `mcp/` | Máy chủ MCP (Node 22) — chạy trên VPS 169 |
| `web/` | Giao diện web `/app` (Node 22, Express): hộp việc, duyệt kết quả agent, quản trị — chạy trên VPS 169 |
| `bridge/` | Cầu nối Kanban (Python) + plugin Hermes — chạy trên VPS 173 |
| `deploy/` | systemd, Caddy, mẫu `.env`, `setup_agents.sql`, `mint_bridge_jwt.py` |
| `scripts/` | test, quét bí mật, ghép lược đồ, xuất bản lên GitHub |
| `docs/` | Tài liệu — đọc theo bảng dưới |
| `prompts/` | Gói prompt cho Claude Code để triển khai lên Z2, VPS 169, VPS 173 |
| `legacy/` | Web app Dẹo Work, PWA Dẹo Việc (đời PA1, chưa chuyển sang lược đồ mới) |

## Đọc gì trước

| Bạn là | Đọc |
| --- | --- |
| Người mới vào dự án | [docs/00-tong-quan.md](docs/00-tong-quan.md) → [docs/01-kien-truc.md](docs/01-kien-truc.md) |
| Lập trình viên | [docs/02-guideline-phat-trien.md](docs/02-guideline-phat-trien.md) |
| Người vận hành máy chủ | [docs/03-so-tay-van-hanh.md](docs/03-so-tay-van-hanh.md), [docs/05-xu-ly-su-co.md](docs/05-xu-ly-su-co.md) |
| Nhân viên, trưởng phòng, quản trị | [docs/04-huong-dan-su-dung.md](docs/04-huong-dan-su-dung.md) |
| Người duyệt rủi ro | [docs/06-bao-mat.md](docs/06-bao-mat.md), [docs/07-gia-dinh-can-kiem-chung.md](docs/07-gia-dinh-can-kiem-chung.md) |
| Soạn văn bản hành chính bằng Văn thư AI | [docs/09-van-thu-nd30.md](docs/09-van-thu-nd30.md) |
| Dùng/vận hành giao diện web | [docs/10-web.md](docs/10-web.md) |
| Claude Code đi triển khai | [prompts/README.md](prompts/README.md) |

Lịch sử thay đổi: [CHANGELOG.md](CHANGELOG.md). Lộ trình: [docs/08-lo-trinh.md](docs/08-lo-trinh.md).
