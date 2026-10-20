# 10 · Giao diện web (`/app`)

Giao diện web của Tổ Ong tại `https://work.enterpriseos.bond/app`: **hộp việc** (việc của tôi, kết quả agent chờ duyệt, câu hỏi agent chờ trả lời), **tạo việc giao agent**, **duyệt kết quả** (chấp nhận hoặc trả lại có lý do), **kết nối AI** (cấp/thu hồi mã MCP) và **quản trị** (agent, cầu nối, mã MCP, nhật ký gọi MCP).

## Kiến trúc
    Trình duyệt ──HTTPS──► Caddy (work.enterpriseos.bond/app*) ──► eos-web (Node, 127.0.0.1:8791)
                                                                      │  tài khoản CSDL eos_web ∈ web_svc
                                                                      ▼
                                              Postgres: chỉ gọi hàm agent.web_* và vài hàm agent.mcp_*/accept_result
- Mã ở `web/` (Express 5 + pg, không bước dựng, không thư viện giao diện; HTML dựng ở máy chủ, CSS/JS cùng nguồn).
- **Không truy cập bảng trực tiếp.** `web_svc` chỉ có `EXECUTE` trên các hàm `SECURITY DEFINER` mang danh tính người đăng nhập (`request.jwt.claims.sub`), cùng mô hình đã kiểm thử của MCP. Chưa có RLS (`docs/06`), nên đây là lớp bảo vệ chính.
- Quản trị dựa vào `core.users.is_system_admin`, kiểm **trong hàm CSDL**, không chỉ ở giao diện.

## Đăng nhập và phiên
- Google OIDC (code flow + PKCE). Chỉ người đã có trong `core.users` (`kind='person'`, `active`) mới vào được; email lạ, tài khoản khóa, tài khoản agent đều nhận **cùng một trang từ chối** (không lộ ai có trong hệ thống).
- `sub` của Google gắn vào người dùng ở lần đăng nhập đầu và **phải khớp** các lần sau (chống chiếm email).
- Phiên là cookie ký HMAC (`HttpOnly`, `SameSite=Lax`, `Secure`, `Path=/app`, sống 8 giờ). Mỗi yêu cầu đều đối chiếu CSDL nên **khóa tài khoản (`active=false`) có hiệu lực ngay**. Đổi `SESSION_SECRET` = đăng xuất mọi người.
- Mọi thao tác ghi có mã CSRF gắn phiên, kiểm `Origin` và `Sec-Fetch-Site`; có giới hạn tốc độ (đăng nhập theo IP, ghi theo người).
- Tiêu đề: CSP không `unsafe-inline`, `frame-ancestors 'none'`, `no-store`, HSTS. Mọi nội dung hiển thị (kể cả do agent viết) được thoát ký tự; liên kết tệp chỉ nhận `https://drive|docs.google.com/`.

## Thêm người dùng
Chưa có màn hình mời người. Thêm bằng SQL (đúng email Google, kèm thành viên công ty):

    INSERT INTO core.users (email, name, kind) VALUES ('ten@gmail.com','Họ Tên','person');
    INSERT INTO core.memberships (user_id, company_id, department_id) SELECT u.id, c.id, d.id FROM core.users u, core.companies c, core.departments d WHERE u.email='ten@gmail.com' AND c.slug='valnex' AND d.company_id=c.id AND d.code='HC';
Thu hồi quyền: `UPDATE core.users SET active=false WHERE email='…'`.

## Cài đặt (VPS 169)
1. Áp `db/migrations/0005_web.sql` (sao lưu trước, thử trên bản sao).
2. Tạo tài khoản đăng nhập CSDL, mật khẩu sinh tại chỗ: `CREATE ROLE eos_web LOGIN PASSWORD '…' IN ROLE web_svc` (không là superuser).
3. `scripts/push_to_host.sh vps169 …`, rồi `cd /opt/apps/enterprise-os/web && npm ci --omit=dev --ignore-scripts` (chạy bằng user `eos`).
4. `.env` theo `deploy/eos-web.env.example` (600, chủ `eos`), `SESSION_SECRET` sinh bằng `openssl rand -hex 32`.
5. `deploy/eos-web.service` → `/etc/systemd/system/`, `systemctl enable --now eos-web`.
6. Thêm `deploy/Caddyfile.web.snippet` vào khối `work.enterpriseos.bond` (trước khối `handle` cuối; thay khối cuối bằng chuyển hướng gốc sang `/app/`), `caddy validate`, `systemctl reload caddy`. Chú ý cú pháp `redir * /app/ 302` (có dấu `*`): thiếu `*` thì `/app/` bị hiểu là bộ khớp đường dẫn và không chuyển hướng gì.
7. Bật đăng nhập: tạo OAuth client (loại **Web application**) trong Google Cloud, redirect URI `https://work.enterpriseos.bond/app/auth/callback`, điền `GOOGLE_LOGIN_CLIENT_ID/SECRET` vào `.env`, `systemctl restart eos-web`. Chưa điền thì trang đăng nhập báo chưa cấu hình (an toàn: không ai vào được).

## Vận hành
- Nhật ký: `journalctl -u eos-web` (có `login_ok`, `login_denied` kèm lý do, mã tham chiếu lỗi 500; không có cookie hay mã).
- Sức khỏe: `GET /app/healthz`; `make audit` kiểm dịch vụ, tiêu đề, cổng, quyền của `eos_web`.
- Lỗi 500 hiện mã tham chiếu; tìm mã đó trong nhật ký.

## Giới hạn đã biết
- Một giao diện cho công ty đầu tiên của người dùng (chưa chọn công ty); chưa có màn hình mời người, chỉnh agent, tải tệp lên, thông báo đẩy.
- Giới hạn tốc độ nằm trong bộ nhớ một tiến trình (đủ cho một máy chủ; chưa có ở lớp Caddy/Cloudflare).
- Phiên không thu hồi riêng lẻ (chỉ khóa người dùng hoặc đổi `SESSION_SECRET`).
- Chưa có MFA riêng: dựa vào xác thực hai bước của tài khoản Google.

## Kiểm thử
`make test-web` (`scripts/test_web.sh`, 24 bước, Google giả lập kèm kiểm PKCE): đăng nhập và mọi ca từ chối, open redirect, XSS, cách ly giữa công ty, CSRF/Origin, luồng trả lời/duyệt/trả lại/tạo/hủy việc, mã MCP, quản trị, phiên giả/hết hạn/khóa ngay, giới hạn tốc độ, cookie `Secure`. Nghiệm thu trên máy thật: `make acceptance ONLY=A8`.
