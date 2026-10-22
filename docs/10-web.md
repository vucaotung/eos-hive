# 10 · Dẹo Work — giao diện web (`/app`)

Ứng dụng quản lý dự án và công việc tại `https://work.enterpriseos.bond/app`, thiết kế theo bản Dẹo Work (HeroUI + Tailwind, chế độ tối, dùng được trên điện thoại), chạy trên lược đồ 108 bảng của Tổ Ong và có sẵn agent AI.

| Màn hình | Làm gì |
| --- | --- |
| **Hôm nay** | việc của tôi, việc tôi giao, chờ tôi duyệt, agent đang hỏi, quá hạn |
| **Việc** | danh sách hoặc bảng Kanban; lọc (đang mở, của tôi, tôi giao, agent hỏi, chờ duyệt, quá hạn, xong 60 ngày), tìm, lọc phòng/người/dự án; mở một việc để sửa, đổi trạng thái, nộp, trao đổi, gắn link Drive, chia việc con |
| **Duyệt** | mỗi phiếu là một bước duyệt (đóng dấu hoặc trả lại có lý do) hoặc kết quả agent nộp cho người giao xem (chấp nhận hoặc trả lại để làm lại) |
| **Báo cáo** | theo phòng ban và theo người: đang mở, quá hạn, vướng, chờ duyệt, xong 30 ngày, tỷ lệ đúng hạn |
| **Dự án** | thẻ từng dự án (tiến độ, việc mở/quá hạn, người quản lý, số thành viên); bấm thẻ để xem việc của dự án; **Thêm dự án**, **Cài đặt** (tên, mã, trạng thái, phòng ban, người quản lý, ngày, Drive, mô tả), **Thành viên dự án** (quản lý/thành viên/người xem), **Xóa dự án** |
| **Quản trị** | thành viên và vai trò, **mã mời**, phòng ban, quy trình duyệt 1–6 bước; người có `is_system_admin` thêm tab **Agent và MCP** (cầu nối Hermes, agent, mã MCP của mọi người, nhật ký gọi MCP) |
| **Tài khoản** | thư mục Drive làm việc, **Kết nối AI agent** (cấp/thu hồi mã MCP), giao diện sáng/tối, đăng xuất |

## Kiến trúc
    Trình duyệt ──HTTPS──► Caddy (work.enterpriseos.bond/app*) ──► eos-web (Node, 127.0.0.1:8791)
                                                                      │  tài khoản CSDL eos_web ∈ web_svc
                                                                      ▼
                                           Postgres: chỉ EXECUTE các hàm agent.app_* và agent.web_* (mã MCP, quản trị)
- `web/src` là máy chủ Express 5 + pg: phục vụ giao diện dựng sẵn ở `web/public` và API JSON `/app/api`. `web/ui` là mã React 19 + HeroUI 3 + Tailwind 4 + Vite; **bản dựng được commit** (`make ui`) để VPS không cần công cụ dựng. CI kiểm bản dựng khớp mã nguồn.
- **Không truy cập bảng trực tiếp.** `web_svc` chỉ có `EXECUTE` trên các hàm `SECURITY DEFINER` mang danh tính người đăng nhập (`request.jwt.claims.sub`). Mọi kiểm quyền (vai trò, phòng ban, người duyệt) nằm **trong hàm CSDL** (`db/61_app.sql`), giao diện chỉ là lớp hiển thị. Chưa có RLS (`docs/06`), nên đây là lớp bảo vệ chính.
- API là **bảng trắng cố định** trong `web/src/routes.mjs`: `POST /app/api/rpc/<tên>` với thân JSON; hàm lạ trả 404; máy chủ không ghép SQL từ dữ liệu người dùng.
- Các hàm `app_*` đều nhận một tham số `jsonb` và trả `jsonb`; lỗi nghiệp vụ (`P0001`) và quyền (`42501`) có câu tiếng Việt hiển thị được, mọi lỗi khác chỉ trả mã tham chiếu.

## Vai trò và quyền (theo thiết kế Dẹo Work cũ)
`owner · admin · manager · member`. Ánh xạ sang lược đồ mới: owner/admin = `core.user_roles` trỏ vai trò mẫu (`core.roles.company_id IS NULL`); manager = `core.memberships.is_dept_head`; member = còn lại. `is_system_admin` được coi là admin ở công ty mình thuộc. Quyền xem việc đi theo `core.role_permissions` (owner/admin cả công ty, còn lại theo phòng) cộng người làm, người giao, người theo dõi và **người đang phải duyệt**.

| Việc | Ai làm được |
| --- | --- |
| Xem việc | owner/admin: cả công ty · manager/member: việc phòng mình + việc mình giao/làm/duyệt |
| Sửa việc | owner/admin: tất cả · manager: việc phòng mình · member: việc mình giao hoặc làm |
| Nộp việc | người phụ trách hoặc người có quyền sửa |
| Duyệt bước | bước "người cụ thể": người đó · bước "trưởng phòng": trưởng phòng của phòng có việc (phòng chưa có trưởng phòng thì owner/admin) · bước "quản trị": admin/owner · bước "chủ sở hữu": owner |
| Dự án | tạo: owner/admin/manager (manager chỉ vào phòng mình) · cài đặt và thành viên: owner/admin, trưởng phòng của phòng sở hữu, hoặc người quản lý dự án (không đổi được phòng) · xóa: owner/admin hoặc trưởng phòng sở hữu; việc của dự án còn nguyên, chỉ mất liên kết |
| Tạo mã mời | owner/admin (admin không mời owner) · manager chỉ mời thành viên vào phòng mình |
| Đổi vai trò/khóa thành viên | owner/admin; không tự hạ hoặc tự khóa mình; công ty luôn còn ít nhất một owner; admin không đụng owner |

## Duyệt nhiều bước
Giao việc chọn **Phải duyệt** (hoặc không). Công ty có sẵn 3 quy trình một bước: *Người giao duyệt*, *Trưởng phòng duyệt*, *Quản trị công ty duyệt*; quản trị tạo thêm quy trình nhiều bước ở Quản trị → Quy trình duyệt. Trạng thái duyệt của việc: `approval_status` = chưa nộp (`none`) → chờ duyệt (`pending`) → đã duyệt (`approved`) hoặc bị trả lại (`rejected`); **việc có quy trình chỉ Xong khi đã duyệt** (CSDL chặn mọi đường khác).

Việc gắn một **quy trình duyệt** (1–6 bước). Nộp việc mở một yêu cầu duyệt (`core.approval_requests`, vòng = số lần nộp, một dòng quyết định mỗi bước); mỗi bước duyệt xong thì sang bước kế, bước cuối duyệt xong thì việc **Xong**. Trả lại (bắt buộc ghi lý do) đóng yêu cầu, việc về **Đang làm** (hoặc cho agent làm lại), lần nộp sau là vòng mới. Việc không gắn quy trình thì Xong ngay khi nộp. Quy trình đang có việc chờ duyệt thì không sửa được bước (tạo quy trình mới rồi ngừng quy trình cũ).

Việc của **agent** có quy trình: agent nộp → người giao xem kết quả (chấp nhận hoặc trả lại) → chấp nhận thì mở yêu cầu duyệt các bước → người duyệt trả lại thì agent làm lại (theo `agent.company_settings.max_rework`).

## Đăng nhập, mã mời và phiên
- Google OIDC (code flow + PKCE). `sub` của Google gắn vào người dùng ở lần đăng nhập đầu và **phải khớp** các lần sau (chống chiếm email).
- Người đã có tài khoản vào thẳng. **Người mới cần mã mời** 8 ký tự (`core.invites`; một mã có vai trò, phòng ban, email giới hạn tùy chọn, số lượt, hạn 1–60 ngày). Hai cách dùng: mở **link mời** `…/app/#/login?code=XXXXXXXX` (mã điền sẵn, đi qua Google), hoặc đăng nhập Google trước rồi nhập mã khi được hỏi (danh tính Google đã xác thực được giữ 10 phút trong cookie ký, chỉ gửi tới `/app/api/join`). Mã sai, hết hạn, hết lượt, đã thu hồi hoặc gắn email khác đều nhận cùng một câu từ chối và không để lại tài khoản. Người đã có tài khoản dùng mã để vào thêm công ty khác.
- Tài khoản khóa (`active=false`), tài khoản agent hoặc `sub` sai chỉ thấy "chưa được cấp quyền", không lộ ai có trong hệ thống.
- Phiên là cookie ký HMAC (`HttpOnly`, `SameSite=Lax`, `Secure`, `Path=/app`, sống 8 giờ). Mỗi lệnh gọi đều qua hàm CSDL nên **khóa tài khoản có hiệu lực ngay**; thành viên bị khóa trong một công ty mất quyền công ty đó ngay. Đổi `SESSION_SECRET` = đăng xuất mọi người.
- Mọi lệnh ghi cần mã CSRF gắn phiên (tiêu đề `X-CSRF-Token`), kiểm `Origin` và `Sec-Fetch-Site`; có giới hạn tốc độ (đăng nhập và nhập mã mời theo IP, API theo người).

## Bảo mật nội dung
- CSP: `default-src 'none'`, `script-src 'self'` (không `unsafe-inline`/`unsafe-eval`), `frame-ancestors 'none'`, `connect-src 'self'`, phông chữ tự lưu (`@fontsource`, không gọi Google Fonts). **Ngoại lệ có chủ đích: `style-src 'unsafe-inline'`** vì thư viện giao diện (React Aria/HeroUI) đặt `style` theo phần tử khi định vị hộp thoại; nó chỉ ảnh hưởng kiểu dáng, không thực thi mã. `make audit` báo thành cảnh báo.
- Mọi nội dung (kể cả do agent viết) hiển thị qua React nên được thoát ký tự; link nộp qua giao diện chỉ nhận `https://`; tệp kết quả của agent chỉ hiện khi URL là `https://`.
- Tiêu đề: HSTS, `nosniff`, `Referrer-Policy: same-origin`, API `no-store`, hashed assets cache dài.

## Cài đặt (VPS 169)
1. Sao lưu CSDL rồi áp `db/migrations/0006_deo_work.sql` (thử trên bản sao dựng từ lược đồ cũ; có thể chạy lặp). Nó gán vai trò cho thành viên hiện có: người `is_system_admin` thành **owner**, còn lại **member**.
2. Tài khoản CSDL `eos_web` (thành viên `web_svc`) đã tạo từ bản 0.0.5; nếu mới, `CREATE ROLE eos_web LOGIN PASSWORD '…' IN ROLE web_svc`.
3. `scripts/push_to_host.sh vps169 /opt/apps/enterprise-os` (gồm `web/public` đã dựng), rồi `cd web && npm ci --omit=dev --ignore-scripts` (user `eos`). **VPS không cần** `web/ui`.
4. `.env` theo `deploy/eos-web.env.example` (600, chủ `eos`): thêm `AGENT_DRIVE_EMAIL` nếu có; `systemctl restart eos-web`.
5. Caddy, OAuth client và `eos-web.service` giữ như `0.0.5` (`deploy/Caddyfile.web.snippet`, redirect URI `https://work.enterpriseos.bond/app/auth/callback`).
6. Công ty đầu tiên: nếu chưa có phòng ban, vào **Quản trị → Phòng ban**, rồi **Mã mời** để mời người.

## Phát triển giao diện
    cd web/ui && npm ci && API_TARGET=http://127.0.0.1:8791 npm run dev    # http://localhost:5173/app/
    make ui                                                                 # dựng ra web/public, rồi commit
Mã giao diện giữ nguyên bố cục Dẹo Work cũ (`legacy/deo-work/web`), chỉ thay lớp dữ liệu: `src/lib/api.js` (gọi `/app/api`), `src/lib/store.jsx` (phiên, công ty, tổ chức), và các lệnh gọi trong từng trang.

## Vận hành
- Nhật ký: `journalctl -u eos-web` (`login_ok`, `login_denied` kèm lý do, `join_denied`, mã tham chiếu lỗi 500; không có cookie hay mã).
- Sức khỏe: `GET /app/healthz`; `make audit` kiểm dịch vụ, tiêu đề, cổng, quyền của `eos_web`.

## Giới hạn đã biết
- **Thư mục Drive của từng người** được ghi nhận (link, trạng thái "đã lưu") nhưng **chưa có tiến trình kiểm tra thư mục** đổi trạng thái sang "đã kết nối"/"cần sửa"; người dùng bỏ qua được bước này.
- Chưa có: thông báo đẩy, tải tệp lên (chỉ gắn link Drive), việc lặp lại, theo dõi người xem (`task_watchers` có trong CSDL nhưng chưa có nút), Service Worker/cài như ứng dụng (có manifest).
- Giới hạn tốc độ nằm trong bộ nhớ một tiến trình (chưa có ở lớp Caddy/Cloudflare). Phiên không thu hồi riêng lẻ. Chưa có MFA riêng: dựa vào xác thực hai bước của Google.
- Thành viên dự án chưa quyết định quyền xem việc (quyền xem vẫn theo phòng/người làm/giao/duyệt); mới dùng để tổ chức và hiển thị.
- Vai trò tùy biến (ngoài owner/admin/manager/member) chưa có màn hình; bảng `core.roles` đã sẵn.

## Kiểm thử
`make test-db` (`db/test_agent.sql`: vai trò, mã mời, duyệt nhiều bước, kết quả agent, quản trị, quyền hàm) và `make test-web` (17 bước, Google giả lập kèm kiểm PKCE): tiêu đề, tệp tĩnh và đường ngược thư mục, mọi ca từ chối đăng nhập, CSRF/Origin, hàm lạ, thông báo lỗi không lộ SQL, vòng đời việc và duyệt 2 bước, kết quả agent, cách ly công ty và phòng, mã mời, quản trị, Drive, mã MCP, phiên giả/khóa ngay, giới hạn tốc độ, cookie `Secure`. Nghiệm thu trên máy thật: `make acceptance ONLY=A8`.
