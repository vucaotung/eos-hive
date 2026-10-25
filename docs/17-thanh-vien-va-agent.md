# 17 · Thành viên gồm người và AI agent (0.2.6)

Tab **Quản trị → Thành viên** nay hiện cả người và AI agent. Giao diện: bộ lọc *Tất cả / Người / AI agent*, ô tìm kiếm (tên, email, chức danh, người phụ trách). Agent có nhãn **AI**; bấm vào mở ngăn chi tiết. Tab này hiện cho chủ sở hữu, quản trị và trưởng phòng (menu Quản trị hiện chưa mở cho thành viên thường; RPC thì đã hỗ trợ vai trò đó, xem "Quyền").

## Nguyên tắc thiết kế (không đổi)
- Agent **không** có dòng `core.memberships` mới do tính năng này tạo ra. `agent.app_org` vẫn chỉ trả người (`u.kind = 'person'`): ô chọn người phụ trách, người duyệt, báo cáo theo người dựa vào `org.members`, nên agent không bao giờ lọt vào đó (giao việc cho agent như một người bị từ chối: test web). Ngoại lệ có sẵn từ trước: tài khoản Mai đã có membership (cần cho công cụ MCP của người); script mới không tạo thêm membership nào cho agent.
- Agent hiện qua RPC riêng `agent.app_members`. Chỉ `agent.app_agent_set` sửa hồ sơ công ty của agent, và chỉ sửa được `enabled`, `owner_user_id`, `department_id`, `title`. **Không** sửa được `max_level`, `can_delegate`, `skills`, `hermes_profile`, `action_levels` (quản trị hệ thống làm bằng SQL hoặc tab "Agent và MCP"). L3 (duyệt, cấp số, chốt lương, đổi vai trò, xóa) không bao giờ mở cho agent; ngăn chi tiết ghi rõ điều đó.

## Bảng phân vai
| Mã | Tên | Chức danh | Vai trò (mô tả lưu ở `agent.agents.description`) | Nhận việc Kanban |
| --- | --- | --- | --- | --- |
| `mai` | Mai - Trợ lý AI | Trợ lý tiếp nhận | Tiếp nhận yêu cầu qua Zalo/Telegram, trả lời thông tin, ghi nhận thông tin bổ sung chờ chủ sở hữu duyệt; chỉ tạo việc mới cho người theo lệnh của người được ủy quyền. | Không (mã MCP riêng) |
| `dieu-phoi` | Điều phối AI | Điều phối dự án | Chia việc dự án cho agent chuyên môn, theo dõi, tổng hợp; không tự làm việc chuyên môn. | Có |
| `van-thu` | Văn thư AI | Văn thư | Công văn NĐ 30, biên mục hồ sơ; không cấp số, không ký, không gửi ra ngoài. | Có |
| `quan-tri-du-lieu` | Quản trị dữ liệu AI | Quản trị dữ liệu | Kiểm chất lượng dữ liệu, nạp kho tri thức; chỉ nạp thông tin đã duyệt. | Có |
| `ho-so-runner` | Xử lý hồ sơ (Z2) | Xử lý hồ sơ (Z2) | Đọc Drive, chuyển Markdown, OCR trong thư mục dự án. | Có (runner) |
| `nhan-su` | Nhân sự AI | Nhân sự | Nháp chấm công, KPI; chưa có skill. | Không (tắt) |
| `phap-che` | Pháp chế AI | Pháp chế | Rà soát pháp lý hồ sơ, không kết luận thay luật sư; chưa có profile. | Không (tắt) |

Dữ liệu này đặt bằng `deploy/setup_agent_profiles.sql` (không chạy tự động): mô tả luôn đặt theo bảng; chức danh và người phụ trách chỉ đặt khi đang trống (không ghi đè chỉnh tay); `mai`, `nhan-su`, `phap-che` luôn đặt `enabled = false`.

## Cách đọc tab Thành viên
- **Trạng thái:** *Đang chạy* (có mã MCP còn hiệu lực), *Tắt* (agent bị tắt, hoặc công ty tắt nhận việc và không có mã), *Chưa có mã* (nhận việc nhưng chưa có mã MCP), *Mã sắp hết hạn* (mã gần nhất hết hạn trong 14 ngày: cấp lại bằng `issue_agent_token.sh`).
- **Nhận việc Kanban** khác với trạng thái: Mai *Đang chạy* nhưng không nhận thẻ Kanban (chỉ dùng mã MCP riêng). Bật công tắc này cho Mai nghĩa là cho phép giao việc cho Mai trên Kanban của `team_admin`: **không nên**.
- Cột kỹ thuật (profile, mã MCP, `max_level`, hoạt động gần nhất, việc đang làm) chỉ chủ sở hữu/quản trị thấy. Phần "Được làm" của ngăn chi tiết suy ra từ `max_level` và phạm vi mã đang hiệu lực. Không bao giờ hiện hash hay tiền tố mã.
- **Quyền:** thành viên thường và trưởng phòng gọi `app_members` được nhưng chỉ thấy tên, chức danh, phòng, mô tả, người phụ trách, trạng thái; chỉ owner/admin gọi được `app_agent_set`.

## Giới hạn mã sai (Phần 2)
Khóa theo **(IP, 8 ký tự đầu của mã gửi lên)** 20 lần/5 phút; tổng theo IP 200 lần/5 phút. `MCP_AUTHFAIL_ALLOW` (danh sách IP, mặc định trống) miễn ngưỡng tổng nhưng vẫn áp ngưỡng theo cặp. Trên VPS 169 đặt `MCP_AUTHFAIL_ALLOW=173.249.51.69` để Mai, ks-kinh-te-xd, cron bản tin và cầu nối (cùng IP vps173) không khóa lẫn nhau. Lưu ý: khóa theo "8 ký tự đầu của chuỗi gửi lên" gồm tiền tố `eos_`, nên thực chất phân biệt theo 4 ký tự hex đầu (65 536 nhóm); ngưỡng tổng 200 là hàng rào chống lách bằng cách đổi tiền tố.

## Skill của Mai (Phần 3)
`enterprise-os-guide` 1.1.0: luôn truyền `source_ref` (`zalo:<id nhóm hoặc người>:<id tin nhắn>` hoặc `telegram:<chat>:<message_id>`); kết quả `duplicate: true` thì báo mã việc cũ, không tạo lại; thông tin bổ sung từ người không có quyền ra lệnh được ghi thành việc "Bổ sung: <chủ đề>" trong dự án **Hàng đợi thông tin nhóm Zalo**, Phải duyệt, giao chủ sở hữu, mô tả gồm người gửi, nhóm, thời gian, nội dung nguyên văn, căn cứ; không nạp kho trước khi được duyệt. **Dự án "Hàng đợi thông tin nhóm Zalo" phải do quản trị tạo trước** (Mai không tự tạo dự án).

## Thứ tự triển khai
1. Sao lưu: `pg_dump -Fc eos > /var/backups/deo/pre-0023-<thời điểm>.dump`.
2. Migration: `0023_company_agent_profile.sql` (idempotent).
3. `psql -v company=<uuid> -v owner_email=<email> -f deploy/setup_agent_profiles.sql`.
4. Đưa mã lên (`scripts/push_to_host.sh`), đặt `MCP_AUTHFAIL_ALLOW` trong `mcp/.env`, khởi động lại `eos-mcp` và `eos-web`.
5. Cài `deploy/logrotate.eos-housekeeping` vào `/etc/logrotate.d/eos-housekeeping`.
6. Tạo dự án "Hàng đợi thông tin nhóm Zalo" trong web (quản trị).
7. Kiểm: nghiệm thu A2, A8; tab Thành viên; mã Mai vẫn trả 200.
8. Việc của ops-admin: cài skill `enterprise-os-guide` 1.1.0 vào `team_admin` (chép thư mục `deploy/hermes-skills/enterprise-os-guide`), rồi khởi động lại gateway từ shell ngoài.

## Hoàn tác
- Giao diện/mã: triển khai lại bản trước (`v0.2.5`) rồi khởi động lại hai dịch vụ; CSDL mới tương thích ngược (cột thêm, hàm thêm).
- Dữ liệu hồ sơ agent: `UPDATE agent.company_agents SET title = NULL, owner_user_id = NULL, department_id = NULL WHERE company_id = '<uuid>';` (mô tả cũ lấy từ bản sao lưu `pre-0023`).
- CSDL: các lệnh down ở đầu `db/migrations/0023_company_agent_profile.sql`.
- `MCP_AUTHFAIL_ALLOW`: xóa dòng trong `mcp/.env`, khởi động lại `eos-mcp`. Logrotate: xóa `/etc/logrotate.d/eos-housekeeping`.
