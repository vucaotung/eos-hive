# Dẹo Việc — app di động cho `deo_work` (PA1, GĐ4)

18/10/2026 · Bổ sung cho "PA1 — Hệ thống ghi chép công việc PostgreSQL + PostgREST"

App web cài lên màn hình chính (PWA), mở toàn màn hình như app native trên iPhone và Android. Bốn màn hình: **Hôm nay** (một câu tóm tắt việc chờ anh; duyệt và trả lời agent ngay tại chỗ; quá hạn; hoạt động gần đây), **Việc** (lọc theo trạng thái, dự án, "Việc của tôi", nhóm theo dự án), **Duyệt** (tờ trình agent nộp, đóng dấu hoặc trả lại, L3 xác nhận hai lần), **Dự án** (tiến độ theo team). Chạm vào một việc mở bảng chi tiết: thông tin, việc con, trả lời, ghi chú, trao đổi, con dấu "Đã duyệt" kèm ngày.

## Thiết kế (bản 2, 18/10/2026)

Làm lại theo frontend-design, frontend-ui-engineering, Front-End-Checklist, taste-skill và premium-frontend-ui. Hai skill sau viết cho landing page, nên chỉ lấy phần áp dụng được cho app làm việc.

- **Ý tưởng:** con dấu đỏ của văn bản hành chính. Màu đỏ son chỉ dùng cho hành động "Đóng dấu duyệt" và dấu "Đã duyệt". Khi duyệt, con dấu in xuống tờ trình (chuyển động duy nhất có chủ đích, chỉ chạy khi người dùng bấm).
- **Bỏ các dấu hiệu "giao diện do AI làm":** nhãn chữ in hoa giãn chữ, chữ đơn cách (monospace) cho mã việc, đường kẻ mảnh, đổ bóng khi đứng yên, kính mờ (backdrop blur), hàng ô số giống nhau, dấu chấm giữa ngăn thông tin.
- **Thay bằng:** bề mặt tách nhau bằng bậc tông màu; một họ chữ Be Vietnam Pro (vẽ cho tiếng Việt) với bốn cỡ; trạng thái có cả hình lẫn chữ (không chỉ màu); nút bo tròn hẳn.
- **Truy cập:** link bỏ qua đến nội dung; bảng chi tiết giữ tiêu điểm bên trong, Esc để đóng, trả tiêu điểm về chỗ cũ; phần nền bị khóa (inert) khi bảng mở; thông báo qua vùng live; vùng chạm tối thiểu 44px; không chặn phóng to.
- **Trạng thái:** khung xương khi đang tải, khối lỗi có nút "Thử lại" và "Mở kết nối", màn hình trống nói rõ việc gì sẽ hiện ở đó.
- **Hiệu năng và bảo mật:** bản build tách `app.css`, `app.js` ra file riêng, CSP bỏ `unsafe-inline` cho script; chỉ animate transform và opacity; hover chỉ bật trên thiết bị có chuột; tôn trọng chế độ giảm chuyển động.

Thay cho Appsmith ở GĐ4 của PA1: một container Caddy 64 MB thay vì vài GB RAM, không có lối ghi thẳng vào bảng.

## Cách app nối vào hệ thống

```
Điện thoại (bật Tailscale)
   │ HTTPS  https://vps169.<tailnet>.ts.net      ← tailscale serve, chỉ trong tailnet
   ▼
VPS 169: deo-app (Caddy, 127.0.0.1:8088)
   ├── /        → PWA tĩnh (dist/)
   └── /api/*   → deo-postgrest:3000 (mạng Docker nội bộ)
                     └── deo-pg / deo_work
```

- Không mở cổng Internet nào. Không qua Cloudflare, không qua Caddy 443 của host.
- Mỗi người một JWT role `human_app` có claim `pid` (= `people.id`). Mọi lệnh ghi đi qua hàm `app_*`, hàm tự lấy người dùng từ JWT, không tin tham số client gửi lên.
- Quyền duyệt vẫn do `people.is_approver` quyết định (kiểm trong `approve_task`).
- Fact Registry không có trong app (evidence-db tách riêng, quyết định D4). Nếu cần màn hình fact chỉ đọc, làm bước sau với một PostgREST thứ hai nối evidence-db bằng user chỉ SELECT.

## Bộ file

| File | Đặt ở VPS 169 |
|---|---|
| `sql/04_app.sql` | `/opt/apps/deo-work/sql/04_app.sql` |
| `deploy/docker-compose.app.yml` | `/opt/apps/deo-work/docker-compose.app.yml` |
| `deploy/Caddyfile` | `/opt/apps/deo-work/app/Caddyfile` |
| `dist/*` (sau `python3 build.py`: `index.html`, `app.css`, `app.js`, `register-sw.js`, `sw.js`, manifest, icon) | `/opt/apps/deo-work/app/dist/` |
| `deploy/mint_jwt.py` | `/opt/apps/deo-work/mint_jwt.py` (thay bản PA1) |
| `web/app.html` | mã nguồn app; sửa ở đây rồi build lại |

## Triển khai

Điều kiện: đã xong GĐ1 của PA1 (`deo-pg`, `deo-postgrest`, 3 tệp SQL đầu, `people` có Tung với `telegram_id` và `is_approver = true`).

1. **Quyền cho app**
   ```bash
   cd /opt/apps/deo-work
   docker exec -i deo-work-deo-pg-1 psql -U postgres -d deo_work -v ON_ERROR_STOP=1 < sql/04_app.sql
   docker compose restart deo-postgrest     # nạp lại schema cache
   ```
2. **Chép app và chạy container**
   ```bash
   mkdir -p app/dist && cp Caddyfile app/ && cp -r dist/* app/dist/
   docker compose -f docker-compose.yml -f docker-compose.app.yml up -d deo-app
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8088/        # 200
   curl -s http://127.0.0.1:8088/api/tasks?limit=1                         # 401 hoặc [] (chưa có mã)
   ```
3. **HTTPS trong tailnet**
   Bật HTTPS Certificates trong trang quản trị Tailscale (DNS → HTTPS Certificates) nếu chưa bật, rồi:
   ```bash
   tailscale serve --bg --https=443 http://127.0.0.1:8088
   tailscale serve status        # ghi lại địa chỉ https://<tên-máy>.<tailnet>.ts.net
   ```
   Sửa `APP_URL` trong `mint_jwt.py` thành địa chỉ đó.
4. **ACL Tailscale**: cho thiết bị của người dùng app vào VPS 169 cổng 443. Cổng 3000 vẫn chỉ dành cho VPS 173 như PA1.
5. **Cấp mã cho từng người**
   ```bash
   python3 mint_jwt.py human 1 180      # 1 = people.id của Tung, hạn 180 ngày
   ```
   Lệnh in ra mã và link `https://…/#t=<mã>`. Gửi link trực tiếp cho người đó (không qua bot, không qua nhóm chat). Mở link một lần, app lưu mã rồi tự xóa khỏi thanh địa chỉ.
6. **Cài lên điện thoại**
   - iPhone: mở link bằng Safari → nút Chia sẻ → "Thêm vào Màn hình chính".
   - Android: mở bằng Chrome → menu ⋮ → "Cài đặt ứng dụng".

## Kiểm tra đạt

- [ ] Từ mạng ngoài (tắt Tailscale), địa chỉ `ts.net` không mở được.
- [ ] Mã `human_app` của người không phải approver: bấm Duyệt → báo "Không có quyền duyệt".
- [ ] Việc L3: bấm Duyệt lần một → hiện cảnh báo, lần hai mới chuyển sang Xong; `task_events` ghi `actor = human:<id>`.
- [ ] Trả lời câu hỏi trong app → task về `todo`, cron F4 nhận lại ở lượt kế.
- [ ] Gọi `PATCH /api/tasks?id=eq.1` bằng mã `human_app` → 403.
- [ ] Tắt mạng điện thoại → app vẫn mở (vỏ app trong cache), báo "Không kết nối được máy chủ".

## Thu hồi và cập nhật

- **Thu hồi một người**: `UPDATE work.people SET active = false WHERE id = …;` Mã của họ bị từ chối ngay ở `app_me()` cho mọi lệnh ghi. Để chặn cả việc đọc, đổi `PGRST_JWT_SECRET`, restart PostgREST, cấp lại mã cho mọi người và cả hai bot.
- **Cập nhật app**: sửa `web/app.html` → `python3 build.py` → chép `dist/*` lên server. Đổi `V` trong `web/sw.js` (hiện là `deo-viec-v2`, lần sau `deo-viec-v3`) mỗi lần phát hành để điện thoại tải bản mới.
- **Team Valnex**: khi có thành viên Valnex dùng app, bật đoạn RLS ở cuối `04_app.sql`.

Tất cả SQL, Caddyfile và compose ở đây chưa chạy trên máy thật. Giao diện đã thử ở khung iPhone, sáng và tối, với dữ liệu mẫu: không lỗi script, không tràn ngang.
