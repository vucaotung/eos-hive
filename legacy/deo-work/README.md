# Dẹo Work — web app giao việc cho các phòng ban

18/10/2026 · Thay cho schema `work` của PA1 và app cá nhân Dẹo Việc

Web app cho nhân viên nhiều công ty, nhiều phòng ban: giao việc, theo dõi, duyệt nhiều cấp, báo cáo. Agent AI (Hermes) tham gia như một người làm việc: nhận việc, hỏi lại, nộp kết quả để người duyệt đóng dấu. Chạy trên điện thoại và máy tính, cài được lên màn hình chính như app.

## Đã chốt

| Câu hỏi | Quyết định |
|---|---|
| Đăng nhập | Tài khoản Google (Gmail cá nhân). Lần đầu bắt buộc có mã mời do quản trị hoặc trưởng phòng cấp |
| Nơi lưu sổ việc | Postgres trên VPS 169, **chỉ siêu dữ liệu**: tiêu đề, trạng thái, người giao, hạn, ai duyệt, link |
| Tài liệu | Nằm trong thư mục Google Drive của từng người, đặt tên theo mẫu, chia sẻ quyền Người chỉnh sửa cho tài khoản agent. Máy chủ chỉ giữ tên tệp và link |
| Tài khoản agent | Tài khoản Workspace riêng (vd `hermes-bot@enterpriseos.bond`) |
| Địa chỉ | `work.enterpriseos.bond` |
| Giao diện | React 19 + HeroUI v3 + Tailwind v4, bản sắc "con dấu" giữ từ Dẹo Việc |

## Tính năng

- **Hôm nay**: một câu tóm tắt việc chờ bạn; việc của tôi, việc tôi đã giao, chờ tôi duyệt, agent đang hỏi, quá hạn.
- **Việc**: lọc theo trạng thái, phòng ban, người, dự án, tìm theo tên hoặc T-số; xem dạng danh sách hoặc bảng Kanban.
- **Chi tiết việc**: thông tin, việc con, đổi trạng thái, nộp kết quả, các bước duyệt, tài liệu (link Drive + tệp agent tự gắn), trao đổi, trả lời agent.
- **Duyệt**: tờ trình kèm ghi chú khi nộp và tài liệu; "Đóng dấu duyệt" hoặc "Trả lại" kèm lý do. Quy trình 1–6 bước; mỗi bước do trưởng phòng của việc, quản trị, chủ sở hữu, hoặc một người cụ thể duyệt.
- **Báo cáo**: theo phòng ban (mở, quá hạn, vướng, chờ duyệt, xong 30 ngày, tỷ lệ đúng hạn, số ngày làm trung bình) và theo người.
- **Quản trị**: thành viên (vai trò, phòng, khóa), mã mời (vai trò, phòng, email cố định, số lượt, hạn, thu hồi, link mời), phòng ban, quy trình duyệt, dự án.
- **Tài khoản**: đổi công ty (một người có thể thuộc nhiều công ty), thiết lập thư mục Drive, giao diện sáng/tối.

### Phân quyền (kiểm tra trong CSDL, không phụ thuộc giao diện)

| Vai trò | Thấy việc | Sửa việc | Quản trị |
|---|---|---|---|
| Chủ sở hữu | Cả công ty | Cả công ty | Mọi thứ, kể cả mời chủ sở hữu |
| Quản trị | Cả công ty | Cả công ty | Thành viên, phòng ban, quy trình, mã mời (trừ chủ sở hữu) |
| Trưởng phòng | Phòng mình + việc mình liên quan | Việc của phòng mình | Mời thành viên vào phòng mình, dự án |
| Thành viên | Phòng mình + việc mình giao, được giao, phải duyệt | Việc mình giao hoặc được giao | Không |

- Bước "Trưởng phòng" chỉ do trưởng phòng của đúng phòng ban duyệt. Quản trị hoặc chủ sở hữu chỉ thay khi phòng đó chưa có trưởng phòng.
- Không role nào ghi thẳng vào bảng. Mọi thao tác ghi đi qua hàm có kiểm tra quyền và trạng thái, và có nhật ký `task_events`.

## Kiến trúc

```
Trình duyệt ── https://work.enterpriseos.bond (Cloudflare) ── Caddy host VPS 169 ── 127.0.0.1:8095
                                                                    │
                                     container web (Caddy): /  → app tĩnh
                                                            /api → PostgREST ── Postgres (deo_work)
                                                            /auth → deo-auth ──┘
Hermes (VPS 173) ── Tailscale 100.70.174.54:3000 ── PostgREST (JWT role agent)
Agent drive_sync ── Google Drive API (tài khoản agent, chỉ đọc) ── ghi siêu dữ liệu qua PostgREST
```

| Thư mục | Nội dung |
|---|---|
| `db/` | `01_schema.sql`, `02_functions.sql`, `03_security.sql`; `test_db.py` (41 phép thử nghiệp vụ và phân quyền); `seed_demo.py` (dữ liệu thử); `reset.sh` |
| `auth/` | Dịch vụ đăng nhập Node: xác minh Google ID token, đổi mã mời, cấp JWT 7 ngày, làm mới phiên |
| `web/` | React + HeroUI; `npm run build` → `dist/` |
| `agent/` | `drive_sync.py` quét thư mục Drive; `test_drive_sync.py` |
| `deploy/` | `docker-compose.yml`, `Caddyfile.app`, `host-Caddyfile.snippet`, `.env.example`, `install.sh`, `mint_jwt.py`, `backup.sh` |

## Triển khai

### 1. DNS
Trên Cloudflare: bản ghi `work` trỏ về `169.58.107.168`, bật proxy (đám mây cam), giống `teams` và `kb`.

### 2. Google OAuth (chỉ để đăng nhập)
Trong Google Cloud Console, dùng project của Workspace công ty:
1. APIs & Services → OAuth consent screen: User type **External** (vì nhân viên dùng Gmail cá nhân); tên app "Dẹo Work"; scope chỉ cần `openid`, `email`, `profile`. Ba scope này không phải qua thẩm định của Google.
2. Chuyển trạng thái sang **In production**. Nếu để Testing, chỉ người trong danh sách test vào được, và phiên hết hạn sau 7 ngày.
3. Credentials → Create OAuth client ID → Web application. Authorized JavaScript origins: `https://work.enterpriseos.bond`. Không cần redirect URI.
4. Chép Client ID vào `deploy/.env` (`GOOGLE_CLIENT_ID=`).

### 3. Cài trên VPS 169
```bash
# chép cả thư mục deo-work lên /opt/apps/deo-work
cd /opt/apps/deo-work/deploy
cp .env.example .env && nano .env        # điền GOOGLE_CLIENT_ID, AGENT_EMAIL
./install.sh                              # sinh bí mật, build web, khởi động, nạp schema, tạo công ty đầu tiên
```
`install.sh` in ra **mã mời chủ sở hữu** và link `https://work.enterpriseos.bond/#/join?code=...`. Thêm `host-Caddyfile.snippet` vào `/etc/caddy/Caddyfile`, chạy `caddy validate`, `systemctl reload caddy`. Mở link, đăng nhập bằng Gmail đã khai báo.

Công ty thứ hai trở đi:
```bash
docker compose exec -T db psql -U postgres -d deo_work -c "select app.bootstrap_company('valnex','Valnex','tung@gmail.com','[{\"code\":\"TK\",\"name\":\"Thiết kế\"}]')"
```

### 4. Mời nhân viên
Quản trị → Mã mời → Tạo mã. Chọn vai trò, phòng ban, giới hạn email (nên dùng), số lượt, hạn. Gửi link mời trực tiếp cho người đó. Người nhận đăng nhập Google, mã được điền sẵn, sau đó được dẫn qua bước thiết lập thư mục Drive.

### 5. Agent (Hermes trên VPS 173)
```bash
cd /opt/apps/deo-work/deploy && python3 mint_jwt.py hermes:ops-admin 90    # → DEO_AGENT_TOKEN
```

| Việc | Gọi |
|---|---|
| Nhận việc theo vai trò | `POST /rpc/agent_claim {"p_role":"tra-cuu"}` (nguyên tử, không nhận trùng) |
| Hỏi lại người | `POST /rpc/agent_ask {"p_task":15,"p_question":"..."}` → việc sang Vướng, người thấy câu hỏi trên app |
| Nộp kết quả | `POST /rpc/submit_task {"p_task":15,"p_note":"..."}` → có quy trình thì sang Chờ duyệt, không thì Xong |
| Ghi chú, link | `/rpc/add_comment`, `/rpc/add_link` |
| Tạo việc (từ chat) | `/rpc/create_task` |
| Đọc | `GET /tasks`, `/comments`, `/approvals`, `/my_approvals`… (agent đọc được mọi công ty) |

Script `deo_tasks.py` của PA1 chỉ cần đổi tên hàm theo bảng trên. Vai trò agent trên app: `tra-cuu`, `phap-che`, `tai-chinh`, `soan-thao`, `kiem-tra`, `lap-ke-hoach` (thêm ở `web/src/lib/format.js`).

### 6. Agent quét Drive
1. Đăng nhập Google Cloud bằng tài khoản admin Workspace, tạo OAuth client loại **Desktop**. Consent screen của client này đặt **Internal**, vì chỉ tài khoản agent trong Workspace dùng, nên không cần thẩm định.
2. Bật Google Drive API cho project.
3. Trên máy có trình duyệt: `GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... python3 agent/drive_sync.py --auth`, đăng nhập **bằng tài khoản agent**, chép `GOOGLE_REFRESH_TOKEN`.
4. Trên VPS 173: đặt `DEO_API`, `DEO_AGENT_TOKEN` (`mint_jwt.py hermes:drive 90`), ba biến Google vào `.env` của profile, thêm cron 15 phút chạy `drive_sync.py` ở chế độ không qua LLM (`--no-agent`).

Mỗi lượt, script làm 4 việc:
- Kiểm tra thư mục tồn tại, đúng tên `DEO - <công ty> - <mã phòng> - <Họ tên>`, và agent có quyền chỉnh sửa. Kết quả hiện ở trang Tài khoản của nhân viên kèm hướng dẫn sửa.
- Liệt kê tệp (3 cấp thư mục, tối đa 2000 tệp), chỉ ghi tên, loại, link và ngày sửa.
- Tự gắn tệp có tên bắt đầu `T-123` vào việc T-123.
- Không tải nội dung tệp về máy chủ.

### 7. Sao lưu
Thêm `deploy/backup.sh` vào `/opt/backup/backup.sh` hiện có, để bản dump đi cùng luồng mã hóa và Z2 kéo về lúc 04:00.

## Kiểm thử đã chạy

- `db/test_db.py`: **41/41** phép thử trên Postgres 16 thật, gồm:
  - mã mời: sai email, hết lượt, người lạ;
  - phân quyền xem và sửa theo phòng ban;
  - không ghi thẳng bảng;
  - duyệt 2 cấp có trả lại và nộp lại;
  - agent nhận việc nguyên tử, hỏi rồi được trả lời;
  - Drive: tên chuẩn, tự gắn T-xx, người khác không thấy tệp;
  - báo cáo theo quyền;
  - không tự hạ quyền owner cuối cùng;
  - khóa người dùng.
- **End-to-end trên trình duyệt** (Playwright) với PostgREST 12.2.3 + deo-auth + Vite: đăng nhập, Hôm nay, Việc (danh sách và Kanban), chi tiết, duyệt có con dấu, báo cáo, tạo mã mời, quy trình duyệt, giao việc mới, khung iPhone sáng và tối, người lạ bị chặn, bước thiết lập Drive. Không có lỗi script.
- Bản build production phục vụ qua `Caddyfile.app` thật với CSP chặt: không vi phạm CSP. Hai Caddyfile đã qua `caddy validate`.
- `agent/test_drive_sync.py`: Drive giả lập + PostgREST thật. Tên sai thì báo đúng tên cần đổi, tên đúng thì ghi danh mục tệp.

**Chưa chạy:** đăng nhập Google thật (cần Client ID), Drive API thật (cần tài khoản agent), `docker compose` (môi trường thử không có Docker; từng thành phần đã chạy riêng lẻ). Lần cài đầu trên VPS nên làm theo đúng thứ tự mục 3 và kiểm tra từng bước.

## Thử nhanh trên máy cục bộ
```bash
db/reset.sh                       # cần Postgres cục bộ (xem biến PGHOST, PGPORT trong reset.sh)
postgrest pgrst.conf              # db-schemas=app, db-anon-role=anon, jwt-secret giống deo-auth
cd auth && DEV_LOGIN=1 PGRST_JWT_SECRET=... DATABASE_URL=... node server.js
python3 db/seed_demo.py
cd web && npm run dev             # http://localhost:5173, đăng nhập thử bằng email trong seed_demo.py
```
`DEV_LOGIN=1` cho đăng nhập không qua Google, chỉ để thử. Dịch vụ từ chối khởi động nếu bật cùng `NODE_ENV=production`.

## Việc còn lại / giới hạn
- Bản đầu chưa có: thông báo email hoặc Telegram khi được giao việc hay đến lượt duyệt (đề xuất: Hermes đọc `task_events` và nhắn qua bot), kéo thả trên Kanban, tìm kiếm toàn văn, xuất báo cáo ra Sheets.
- Thư mục Drive: một người, một thư mục. Người thuộc nhiều công ty dùng tên của công ty đầu tiên.
- JS 198 KB và CSS 44 KB (đã nén), lần mở đầu chậm hơn Dẹo Việc; sau đó service worker lưu lại.
- Khi chạy thật, cập nhật tài liệu kiến trúc (mục 2.2, 2.3, 3.2) và ghi ADR: Dẹo Work thay Ever Teams và thay schema `work` của PA1.
