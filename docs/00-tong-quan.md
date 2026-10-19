# 00 · Tổng quan

## Hệ thống làm gì

Enterprise OS phục vụ một chủ sở hữu có nhiều công ty, mỗi công ty nhiều phòng ban. Phân hệ:

| Phân hệ | Việc chính | Schema |
| --- | --- | --- |
| Công việc | Giao việc, việc con, bình luận, duyệt nhiều cấp (1–6 bước), đề nghị | `work` |
| Công văn và Tài liệu | Sổ công văn đến–đi theo NĐ 30, tình trạng xử lý, kho hồ sơ | `doc` |
| Nhân sự | Chấm công, đơn từ, phép năm, bảng công, lương, KPI tháng | `hr` |
| Kho dữ liệu chung | Hỏi đáp có trích dẫn trên tài liệu đã nạp (WeKnora), wiki có duyệt | `kb` |
| CRM | Giai đoạn sau (mới có khung bảng) | `crm` |
| AI agent | Danh mục agent, thẻ Kanban, báo cáo, mã MCP | `agent` |
| Nền | Tổ chức, người, vai trò, quyền, tệp, nhật ký, thông báo | `core` |

108 bảng, 5 view. Tên bảng và cột bằng tiếng Anh; nhãn hiển thị tiếng Việt.

## Vai trò của AI agent

Có ba loại, mỗi loại một cách vào hệ thống.

1. **Agent hệ thống** (Điều phối, Văn thư, Nhân sự, Thủ thư). Chạy trong Hermes, mỗi agent một profile. Nhận việc qua thẻ Kanban, nộp kết quả qua `kanban_complete` hoặc hỏi lại qua `kanban_block`. Không ghi vào Postgres trực tiếp; chỉ cầu nối ghi.
2. **Agent chuyên môn** (tra cứu, pháp chế, soạn thảo, kiểm tra). Không phải tài khoản riêng, là *kỹ năng* gắn vào thẻ.
3. **Agent cá nhân** của từng người (Claude, ChatGPT, Hermes riêng…). Nối vào MCP bằng mã do người tự tạo. Chỉ thấy và làm trong quyền của chính người đó; ghi kết quả vào Drive của người đó.

Quy tắc bất biến:
- `work.tasks.assignee_id` luôn là người. `work.tasks.agent_id` là agent thực hiện. KPI chỉ tính cho người.
- Mức tự chủ: **L0** chỉ đọc · **L1** làm và ghi nhật ký · **L2** phải xin xác nhận người giao · **L3** chỉ người làm. 19 hành động có mức gán sẵn trong `agent.action_levels`; hệ thống từ chối `request_confirmation` cho L3.
- Kết quả của agent chưa phải kết quả cuối: mặc định người giao phải **chấp nhận** (`agent.accept_result`) hoặc **trả lại** (`agent.reject_result`). Trả lại tối đa 2 lần; lần 3 việc về người phụ trách và agent dừng.
- Chia việc (`agent.delegate`): chỉ agent có `can_delegate` (mặc định Điều phối), tối đa 8 việc con, 2 tầng. Việc con có `kpi_counted=false`, cùng người phụ trách và hạn. Con cuối xong → sinh thẻ *Tổng hợp* cho Điều phối.

## Dữ liệu nằm ở đâu

| Loại | Nơi |
| --- | --- |
| Siêu dữ liệu việc, người, công văn (số, ngày, trạng thái, link) | Postgres trên VPS 169 |
| Nội dung tệp, kết quả công việc | Google Drive của từng người, `Kết quả/<năm-tháng>/T-<số> - <tên>` |
| Văn bản mật | **Không số hóa**, không nạp, không qua MCP (chỉ số và ngày) |
| Kho dữ liệu chung | WeKnora (ngoại lệ: có nội dung trên máy chủ) |

## Ba máy

| Máy | Vai trò với dự án này |
| --- | --- |
| **VPS 169** (169.58.107.168) | Postgres + PostgREST + máy chủ MCP + Caddy (`work.enterpriseos.bond`) + WeKnora |
| **VPS 173** (173.249.51.69) | Hermes Agent (gateway nhiều profile) + cầu nối Kanban + plugin `eos_bridge` |
| **Z2** (HP Z2 Mini G4, Ubuntu 26.04) | Máy phát triển, chạy Claude Code, kiểm thử bằng Docker, kéo sao lưu; không chạy dịch vụ cho người dùng |

## Thuật ngữ

| Từ | Nghĩa |
| --- | --- |
| Thẻ (card) | Một mục trên board Kanban, tương ứng một việc T-<số> |
| Board | Một bảng Kanban, mỗi công ty một board `eos-<slug>`; là ranh giới cô lập cứng |
| Tenant | Mã phòng ban gắn vào thẻ; chỉ là bộ lọc mềm |
| Hộp thư đi (outbox) | Hàng đợi lệnh Postgres → Kanban, cầu nối kéo bằng `outbox_pull` |
| Spool | Tệp `spool.jsonl` plugin Hermes ghi khi có hook, cầu nối đọc |
| Worker agent | Agent hệ thống đang chạy một thẻ |
| Mã MCP | Chuỗi `eos_` + 48 hex, thuộc về một người (hoặc một agent hệ thống) |
