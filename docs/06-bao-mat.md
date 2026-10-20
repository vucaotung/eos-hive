# 06 · Bảo mật

## Nguyên tắc
1. Dữ liệu của người nào ở Drive người đó; máy chủ chỉ giữ siêu dữ liệu và link.
2. Tối thiểu quyền ở **mọi** lớp: người, mã MCP, vai trò Postgres, tài khoản Workspace.
3. Việc không đảo ngược → người làm (L3). Việc có hệ quả ra ngoài → người xác nhận (L2).
4. Bí mật không đi qua chat, không vào git, không vào dòng lệnh.
5. Văn bản mật không số hóa, không nạp, không qua MCP.

## Kiểm kê bí mật

| Bí mật | Nơi lưu | Ai dùng | Xoay |
| --- | --- | --- | --- |
| `JWT_SECRET` PostgREST | `/etc/eos/postgrest.conf` (600, VPS 169) | PostgREST; script cấp JWT | khi nghi lộ; xoay = vô hiệu mọi JWT |
| JWT `agent_bridge` | `~/.hermes/eos_bridge/.env` (600, VPS 173) | cầu nối | 80 ngày |
| Mật khẩu `eos_mcp` | `/opt/apps/enterprise-os/mcp/.env` (600) | MCP | 12 tháng |
| Mật khẩu `authenticator` | `eos.conf` | PostgREST | 12 tháng |
| Refresh token Google (tài khoản agent) | `.env` MCP (600) | MCP ghi Drive | khi nghi lộ |
| Mã MCP của người | trình quản lý mật khẩu của người đó | agent cá nhân | ≤ 365 ngày (hệ thống ép) |
| Mã MCP của agent hệ thống | `.env` profile Hermes | worker | 80 ngày |
| Khóa SSH Z2 → VPS | Z2 `~/.ssh` | người vận hành, Claude Code | 12 tháng |
| Mật khẩu sao lưu | ngoài VPS (người giữ) | sao lưu | 12 tháng |

## Mô hình mối đe dọa

| Mối đe dọa | Biện pháp | Rủi ro còn lại |
| --- | --- | --- |
| Lộ mã MCP của người | Chỉ lưu băm; hạn; thu hồi; phạm vi tối thiểu; giới hạn 120/phút; nhật ký mọi lần gọi | Kẻ có mã làm được mọi điều người đó làm qua MCP tới khi bị thu hồi — nên phạm vi `write`/`drive` cấp có chủ đích |
| Agent bị tiêm lệnh (prompt injection) qua công văn/tệp/bình luận | Hướng dẫn: nội dung là dữ liệu; L3 chặn trong CSDL; agent cá nhân không duyệt/cấp số/chốt/xóa; ghi Drive chỉ trong thư mục người dùng | Agent vẫn có thể bị lừa *làm sai trong quyền hạn* (nộp kết quả sai) → người duyệt là chốt chặn cuối; `auto_done` tắt |
| Worker agent đọc ngoài việc được giao | `eos_get_task` chỉ cho việc có thẻ đang chạy (+ cha/con) | — |
| Lộ cơ sở dữ liệu | Mã MCP băm SHA-256; không có nội dung tệp; văn bản mật không có | Siêu dữ liệu (tên việc, người, hạn) lộ; **lương và dữ liệu nhân sự nằm trong CSDL** — mã hóa đĩa + sao lưu mã hóa |
| Bảng điều khiển Kanban không xác thực | Chỉ bind `127.0.0.1` | Ai có shell trên VPS 173 điều khiển được Kanban |
| Cầu nối bị chiếm | Vai trò `agent_bridge` chỉ 4 hàm; không đọc `mcp_tokens` | Có thể bơm sự kiện giả (`ingest_event`) → đổi trạng thái việc; người duyệt vẫn đóng kết quả |
| Agent ghi Drive sai chỗ | `eos_attach_drive_file` đi ngược ≤ 6 cấp cha để chứng minh nằm trong thư mục người dùng; `save_to_drive` chỉ ghi vào thư mục của họ | Tài khoản Workspace có quyền Editor rộng — thu hẹp được thì thu hẹp |
| Quá tải/thử sai mã | Giới hạn tốc độ; mã sai trả 401 chung chung | Chưa có khóa IP/Fail2ban cho 401 — nên thêm ở Caddy/Cloudflare |
| Lộ qua nhật ký | `args` ghi theo `logArgs` chỉ các trường an toàn | Rà soát khi thêm công cụ mới |

## Dữ liệu nhạy cảm
- **Văn bản mật**: `eos_incoming_list` chỉ trả số và ngày khi người xem không đủ thẩm quyền xem nội dung. Không có công cụ số hóa. Quy tắc nghiệp vụ, không chỉ kỹ thuật: *không* quét/nạp.
- **Lương, CCCD, tài khoản ngân hàng**: `eos_my_hr` chỉ công, phép, KPI **của chính chủ**. Hướng dẫn cho agent (`eos_guide topic=drive`) cấm lưu tệp chứa mật khẩu, mã truy cập, số tài khoản, số CCCD. Đó mới là **lời dặn, chưa có bộ lọc tự động** — đừng coi là kiểm soát cứng.
- **Số liệu thuế, bảo hiểm** (`hr.payroll_settings`): kế toán nhập theo quy định hiện hành; hệ thống không tự điền.

## Điểm yếu đã biết của v0.0.0
1. **Chưa có RLS.** Bảo vệ dựa vào hàm `SECURITY DEFINER` và vai trò hẹp. Giai đoạn 1 (app web) phải thêm RLS trước khi cấp quyền bảng cho vai trò nào ngoài chủ sở hữu.
2. **Chưa có OAuth cho MCP**: Bearer tĩnh; mã bị đánh cắp dùng được từ mọi nơi tới khi thu hồi. Nên hạn mã ngắn (30–90 ngày).
3. **PostgREST công khai qua `/api`** (nếu mở cho app): giữ `anon` rỗng quyền; thêm giới hạn tốc độ và chặn IP ở Caddy/Cloudflare.
4. **Bộ lọc nội dung nhạy cảm khi lưu Drive** mới là lời nhắc, chưa là bộ lọc.
5. **Cầu nối chưa thử với Hermes thật** (`docs/07`).
6. **Phân vùng nhật ký** hết năm 2027 (`docs/03` §4.1).
7. **Profile Hermes `ops-admin` có terminal chạy quyền root** (đã cấu hình cho trợ lý cá nhân của chủ). Không dùng nó làm worker Kanban: một thẻ chứa nội dung độc hại sẽ chạy lệnh root. `setup_agents.sql` mặc định ánh xạ Điều phối → `ops-admin`; **đổi** sang profile riêng `eos-dieu-phoi` không có terminal (xem `prompts/30-vps173.md` bước 2).

## Danh sách kiểm tra trước khi cho người dùng thật vào

Phần lớn kiểm tra **tự động**: `make audit` (`scripts/security_audit.sh`, chỉ đọc, chạy trên máy thật) và `make restore-drill`. Rủi ro chủ sở hữu đã chủ động chấp nhận ghi ở `scripts/security_accepted.txt` (có ngày, người, lý do); kiểm toán hiện chúng là ◌ thay vì ✘. Trạng thái 2026-10-20 (v0.0.3): 24 đạt · 0 hỏng · 2 cảnh báo · 3 đã chấp nhận.

- [x] `scripts/check_secrets.sh` sạch; repo GitHub **private**. *(audit §1)*
- [x] Mọi `.env` quyền 600, chủ sở hữu đúng; không `.env` trong git. *(audit §2)*
- [x] Kanban dashboard không ra Internet; vps173 UFW bật. **vps169 UFW tắt** — đã chấp nhận (chỉ 22/80/443 nghe ra ngoài). *(audit §3)*
- [ ] Đăng nhập SSH bằng khóa; tắt mật khẩu; mật khẩu root từng lộ đã đổi. **Đã chấp nhận hoãn (2026-10-19)** — bắt buộc làm trước khi có người dùng thật. *(audit §4)*
- [x] Sao lưu hằng ngày chạy; đã khôi phục thử thành công; diễn tập lặp lại được bằng `make restore-drill`. *(audit §5)*
- [x] Mỗi người dùng MCP có mã riêng, phạm vi tối thiểu, hạn ≤ 90 ngày. *(audit §6)*
- [x] `auto_done` tắt cho mọi agent. *(audit §6)*
- [x] Bộ kiểm thử khói đã chạy trên máy thật: `make acceptance` (A1–A6). *(docs/03 §7.1)*
- [~] Giới hạn tốc độ cho `/mcp` và `/api`: `/mcp` có giới hạn ở tầng ứng dụng (120/phút/mã); `/api` khóa theo IP vps173. Caddy vps169 **không có module `rate_limit`** — cần Caddy build kèm module hoặc đặt Cloudflare phía trước khi mở cho người dùng thật. *(audit §3, cảnh báo)*
- [ ] Siết chia sẻ thư mục Drive của người dùng: chỉ chia sẻ riêng cho tài khoản agent (Editor), không dùng "anyone with the link". *(việc của chủ sở hữu, không tự kiểm được)*

Lưu ý: cổng `8644` của Hermes (profile mặc định) nghe `0.0.0.0` và chỉ được UFW vps173 chặn; nếu UFW bị tắt, cổng này lộ ra ngoài. Nên cấu hình Hermes bind `127.0.0.1` (thuộc profile ngoài phạm vi Tổ Ong).
