# Nhật ký thay đổi

Theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/) và [Semantic Versioning](https://semver.org/lang/vi/).
Trong giai đoạn 0.x, mọi thay đổi lược đồ CSDL có thể phá vỡ; đã triển khai thật thì phải đi qua migration (xem docs/02).

## [Chưa phát hành]

### Sửa
- **Cầu nối ↔ Hermes thật** (`bridge/`, nhánh `fix/real-hermes`; kiểm chứng trên Hermes 0.22.1, `docs/07`): `--board` đứng trước động từ; tự tạo board khi chưa có; đọc `show --json` đúng chỗ (`task.status`, `latest_summary`, `runs[-1].metadata`, `events[blocked].payload.reason`); đối soát không dùng `updated_at`; thêm `plugin.yaml` cho plugin; `fake_hermes.py` khớp dạng thật; thêm `bridge/test/test_fixtures.py` + mẫu thật `bridge/test/fixtures/`. Hook `claimed` không bắn từ profile `eos-*` (chạy ở dispatcher của profile `default`): bù bằng đối soát 60 s (`docs/07` A13).
- `deploy/setup_agents.sql`: agent `thu-thu` đổi thành `quan-tri-du-lieu` (profile `eos-quan-tri-du-lieu`, module `kb`); thêm `phap-che` giữ chỗ (`specialist`, module `doc` tạm vì cột `module` không cho để trống, `max_level` 0, tắt) cho đến khi được định nghĩa. Cập nhật tài liệu và prompt liên quan. Dữ liệu giả của bộ kiểm thử cầu nối vẫn dùng `thu-thu` (chỉ là mẫu).

## [0.0.0] — 2026-10-19

Bản nền đầu tiên: lược đồ, lớp AI agent, máy chủ MCP, cầu nối Kanban, tài liệu. **Chưa chạy trên máy thật.**
Dự án đặt tên Tổ Ong (eos-hive), tách ra từ chuỗi thiết kế PA1 → Dẹo Việc → Dẹo Work → Enterprise OS.

### Thêm
- **CSDL** (`db/`, PostgreSQL 16): 108 bảng, 5 view, 7 schema — `core` (tổ chức, người, quyền, duyệt nhiều cấp, tệp, nhật ký), `work` (việc, việc con, bình luận), `doc` (công văn đến–đi theo NĐ 30, kho hồ sơ), `hr` (chấm công, đơn từ, phép, lương, KPI), `crm` (khung), `kb` (Kho dữ liệu chung, ánh xạ WeKnora), `agent` (lớp AI agent).
- **Lớp AI agent** (`db/60_agent.sql`, 15 bảng): danh mục agent (điều phối, phân hệ, chuyên môn), mức tự chủ L0–L3 cho 19 hành động, xác nhận L2 (hết hạn sau 3 ngày), thẻ Kanban, hộp thư đi, sự kiện chống trùng, báo cáo hoàn thành có hợp đồng, làm lại tối đa 2 lần, chia việc (tối đa 8 việc con, 2 tầng, có thứ tự, thẻ tổng hợp), mã MCP, nhật ký MCP, ghi Drive.
- **Máy chủ MCP** (`mcp/`, Node 22): Streamable HTTP không trạng thái; 15 công cụ cho agent cá nhân, 3 công cụ cho worker agent; 6 chủ đề hướng dẫn; 2 lời nhắc. Mã `eos_` + 48 hex, chỉ lưu băm SHA-256, hạn ≤ 365 ngày, ≤ 5 mã/người, giới hạn 120 lần/phút.
- **Cầu nối Hermes Kanban** (`bridge/`, Python 3): hộp thư đi → `hermes kanban`; hook → `agent.ingest_event`; đối soát 10 phút. Kèm plugin Hermes `eos_bridge`.
- **Triển khai** (`deploy/`): đơn vị systemd cho MCP và cầu nối, mẫu biến môi trường, đoạn Caddy, `setup_agents.sql` (4 agent: Điều phối, Văn thư, Nhân sự, Quản trị dữ liệu; kèm Pháp chế giữ chỗ, tắt), `mint_bridge_jwt.py`.
- **Kiểm thử**: `test_schema.sql`, `test_agent.sql`, MCP đầu–cuối 16 bước (Drive giả lập), cầu nối 7 bước (PostgREST thật, Hermes giả lập). Script chạy được trên máy bất kỳ có Postgres (`scripts/`), kèm CI GitHub Actions.
- **Tài liệu** (`docs/`): tổng quan, kiến trúc, hướng dẫn phát triển, sổ tay vận hành, hướng dẫn sử dụng theo vai trò, xử lý sự cố, bảo mật, các giả định cần kiểm chứng. Gói prompt triển khai cho Claude Code (`prompts/`).
- **Tham chiếu cũ** (`legacy/`): web app Dẹo Work và PWA Dẹo Việc, viết cho lược đồ `work` đời PA1; chưa chuyển sang lược đồ 108 bảng.

### Đã biết còn thiếu (không phải lỗi, là chưa làm)
- Chưa có RPC cho app web, chính sách RLS, dữ liệu khởi tạo (giai đoạn 1). Chưa có màn hình web cho hộp việc của agent.
- Chưa có OAuth cho MCP: chỉ dùng mã Bearer, nên chưa nối được Claude.ai / ChatGPT bản web.
- Chưa có công cụ MCP hỏi Kho dữ liệu chung (cần API WeKnora). `agent.routing_rules` và `agent.routines` mới có bảng, chưa có bộ kích hoạt.
- **Cầu nối chưa thử với Hermes thật.** Dạng JSON của `hermes kanban show --json`, tham số hook và cách cài plugin là giả định — xem `docs/07-gia-dinh-can-kiem-chung.md`.
- Phân vùng `core.audit_log` chỉ có 2026 và 2027, không có phân vùng mặc định: từ 01/01/2028 ghi nhật ký sẽ lỗi nếu chưa tạo (docs/03 §4.1).
- Số liệu thuế, bảo hiểm trong `hr.payroll_settings` phải do kế toán nhập theo quy định hiện hành.
