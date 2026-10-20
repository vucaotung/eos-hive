# 09 · Văn thư AI và skill NĐ 30

Văn thư AI (agent `van-thu`, profile Hermes `eos-van-thu`) soạn **dự thảo** công văn và quyết định đúng thể thức Nghị định 30/2020/NĐ-CP để người trình ký. Nó **không cấp số, không ký, không ban hành** (mức L3, chỉ người làm).

## Các mảnh ghép

| Mảnh | Ở đâu | Việc |
| --- | --- | --- |
| Skill `nd30-van-thu` | `deploy/hermes-skills/nd30-van-thu/` (cài vào profile `eos-van-thu`) | Dạy agent quy trình, thông tin bắt buộc, cách ký, văn phong, danh sách kiểm tra, cách báo cáo |
| Công cụ MCP `eos_draft_document` | `mcp/src/tools.mjs`, `mcp/src/vanban.mjs` | Dựng `.docx` ở máy chủ MCP rồi lưu vào Drive của người phụ trách và gắn vào việc |
| Phạm vi `draft` | `agent.mcp_token_issue_agent` (migration 0003) | Chỉ mã agent module `doc` có; mã của người không được có |
| Hàm SQL | `agent.mcp_agent_drive_target`, `agent.mcp_agent_register_file` | Kiểm agent có thẻ đang chạy cho việc; ghi tệp bằng quyền người phụ trách, nhật ký ghi `agent:van-thu` |

**Vì sao máy chủ dựng `.docx`:** worker Hermes không có terminal (`docs/06`), nên không chạy được script Node như skill gốc. Máy chủ MCP chạy mã đã kiểm thử; worker chỉ gửi JSON thể thức.

## Dùng
Giao việc cho agent `van-thu` (công ty đã bật), mô tả rõ: loại văn bản, gửi ai, nội dung chính, **ai ký**, địa danh. Agent soạn rồi nộp kết quả: người xem tệp trong Drive, mở bằng Word, điền **số** (từ sổ đăng ký), **ngày**, ký, đóng dấu. Thiếu thông tin thì agent chặn việc và hỏi một lần.

## Thể thức
Thông số ở `deploy/hermes-skills/nd30-van-thu/references/quy_tac_the_thuc.md`; được mã hóa trong `mcp/src/vanban.mjs` (hằng `SPEC`) và **kiểm bằng `mcp/test/vanban.test.mjs`** trên chính XML của tệp (khổ giấy, lề, bảng header 3500:5571, font, giãn dòng, cỡ chữ, không tab/gạch chân, tiền tố ký). Chạy: `make test-mcp`.

## Cách ký
Mô hình công ty (không phải mô hình bộ của trang nguồn): `references/phan_quyen_ky_valnex.md`. Người giao việc quyết định ai ký; agent chỉ ghi đúng hình thức. Sửa tệp này khi cơ cấu chức danh của Valnex đổi.

## Thêm loại văn bản mới (tờ trình, thông báo, biên bản…)
1. Thêm giá trị vào `vanBanShape.loai` và nhánh dựng thân văn bản trong `mcp/src/vanban.mjs` (header và chữ ký dùng chung).
2. Thêm kiểm thử trong `mcp/test/vanban.test.mjs`, nhìn thử bằng LibreOffice → PDF → ảnh.
3. Thêm ví dụ `vi_du_<loại>.json` vào skill (test tự kiểm ví dụ hợp lệ) và cập nhật `SKILL.md`.

## Cài đặt trên máy thật
1. `scripts/push_to_host.sh vps169 …` rồi `npm ci --omit=dev` (có thư viện `docx` ghim bản 9.9.0, không script cài đặt) và khởi động lại `eos-mcp`.
2. Áp `db/migrations/0003_draft_document.sql` (sao lưu trước, thử trên bản sao).
3. Cấp lại mã cho agent `van-thu` (để có phạm vi `draft`; thu hồi mã cũ): `scripts/issue_agent_token.sh vps169 vps173 van-thu eos-van-thu 90`.
4. `scripts/install_skill.sh vps173 eos-van-thu nd30-van-thu`.
5. `UPDATE agent.agents SET skills='{nd30-van-thu}' WHERE code='van-thu'` (`setup_agents.sql` đã đặt sẵn cho công ty mới). Cài skill **trước** khi giao việc, vì thẻ nạp skill theo tên.
6. Kiểm: `make acceptance ONLY=A7`.

## Nguồn và khác biệt
Thông số theo https://nd30-guide.vercel.app/ (v1.0, 3/2026, Minh Đỗ) và NĐ 30/2020/NĐ-CP Phụ lục I. Trang đó chỉ nói về công văn và quyết định, không có quy trình văn bản đến/đi, sổ đăng ký, cấp số, văn bản mật/khẩn. Những chỗ ta làm khác trang (địa danh không mặc định, độ dài gạch dưới tên cơ quan, "QUYẾT ĐỊNH:", "(Ký, ghi rõ họ tên)" chỉ ở dự thảo, nghĩa của TM.) có giải thích ở `quy_tac_the_thuc.md`. NĐ 30 bắt buộc với cơ quan nhà nước; Valnex dùng làm chuẩn tham chiếu nội bộ.

## Giới hạn đã biết
- Chỉ công văn và quyết định.
- Chưa có công cụ cấp số, đăng ký sổ văn bản đi/đến, xuất PDF, ký số.
- Số văn bản và ngày để trống có chủ ý.
- Ký hiệu (`VALNEX-<mã phòng>`) do agent suy từ phòng soạn thảo hoặc hỏi người giao; người giữ sổ chỉnh khi cấp số.
