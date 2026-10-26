# Handoff: Enterprise OS — thiết kế lại giao diện (web + mobile)

## Overview
Enterprise OS là hệ thống giao việc và điều phối công việc cho nhiều công ty, nhiều phòng ban, có AI agent **Hermes** tham gia như một thành viên. Gói này mô tả toàn bộ giao diện mới cho web (desktop ≥1280px, co giãn tốt xuống ~900px) và mobile (390px), cùng design system dùng chung. Toàn bộ chữ trên UI là tiếng Việt có dấu.

Người dùng: Ban Giám đốc (tổng quan nhiều công ty), Quản lý phòng ban (giao việc, theo dõi tải), Nhân viên (chủ yếu mobile: việc hôm nay, đánh dấu xong, trao đổi), Hermes (AI: nhận/giao việc, bình luận, báo cáo — luôn được nhận diện là AI).

## About the Design Files
Các file trong gói là **bản tham chiếu thiết kế viết bằng HTML** (prototype thể hiện giao diện và hành vi mong muốn), **không phải code production để copy nguyên**. Nhiệm vụ là **dựng lại các thiết kế này trong môi trường của codebase đích** (React/Next, Vue, React Native, Flutter…) theo pattern và thư viện sẵn có. Nếu chưa có codebase, đề xuất: **Next.js + TypeScript + Tailwind (hoặc CSS variables) + Radix/shadcn primitives** cho web, **React Native/Expo** cho mobile, chia sẻ token qua một package chung.

File `.dc.html` mở trực tiếp bằng trình duyệt (cần thư mục `_ds/` đi kèm). Logic trong file là class JS đơn giản (`renderVals()` trả dữ liệu cho template `{{ }}`) — đọc để hiểu state & dữ liệu mẫu, không cần tái sử dụng runtime.

## Fidelity
**High-fidelity.** Màu, chữ, khoảng cách, bo góc, trạng thái tương tác là bản cuối. Dựng lại sát pixel bằng component của codebase. Ngoại lệ: dữ liệu là mẫu; các nút lọc phụ (Danh mục, Khoảng ngày, Sắp xếp…) chỉ minh hoạ UI.

---

## Design Tokens

Nền tảng: design system **Nocturne** (`_ds/.../styles.css`) + lớp token ngữ nghĩa bổ sung. Mọi màu lấy từ biến, không hard-code.

### Màu — chế độ tối (mặc định)
| Token | Giá trị | Dùng cho |
|---|---|---|
| `--bg` | `#161826` | Nền trang |
| `--sf` | `#232532` | Bề mặt (thẻ, sidebar, panel) |
| `--sf2` | `oklch(0.30 0.02 277)` | Bề mặt 2: hover, avatar người, bubble chat của mình |
| `--ln` | `color-mix(#e9e9ed 16%, transparent)` | Viền control |
| `--ln2` | `color-mix(#e9e9ed 9%, transparent)` | Viền nhẹ, đường kẻ hàng |
| `--tx` | `#e9e9ed` | Chữ chính |
| `--mu` | `#b2b6ca` (neutral-400) | Chữ phụ |
| `--fa` | `#9397ab` (neutral-500) | Chữ mờ, nhãn cột |
| `--ac` | `#9184d9` | Màu nhấn (viền nút chính, tab đang chọn, focus) |
| `--act` | `#d2cefd` (accent-300) | Chữ màu nhấn cỡ nhỏ |
| `--acbg` | `#2b2741` (accent-900) | Nền mục đang chọn |
| `--ok` / `--okbg` | `oklch(0.76 0.13 155)` / `oklch(0.30 0.05 155)` | Thành công: Hoàn thành, Rảnh, đúng hạn |
| `--wn` / `--wnbg` | `oklch(0.82 0.13 80)` / `oklch(0.31 0.05 80)` | Cảnh báo: Tạm dừng, hạn ≤3 ngày, Bận, Quan trọng ★ |
| `--dg` / `--dgbg` | `oklch(0.72 0.15 25)` / `oklch(0.30 0.07 25)` | Quá hạn, Bị chặn, Khẩn cấp ⚡, Quá tải, Xoá |
| `--in` / `--inbg` | `oklch(0.76 0.10 240)` / `oklch(0.30 0.05 240)` | Thông tin: Đang làm, sự kiện Google, Vừa sức |
| `--ai` / `--aibg` | `#b5abfc` (accent-400) / `#2b2741` | Hermes / AI |
| `--scrim` | `oklch(0.12 0.02 277 / .62)` | Lớp phủ sau modal/panel |

### Màu — chế độ sáng (class `body.light`)
`--bg oklch(0.955 0.008 277)`, `--sf oklch(0.99 0.003 277)`, `--sf2 oklch(0.965 0.006 277)`, `--tx #161826`, `--mu #595d6c`, `--fa #6b6f80`, `--ac #6a5db3`, `--act #4f4590`, `--acbg #ecebfd`, `--ln color-mix(#161826 15%)`, `--ok oklch(0.48 0.12 155)`/`--okbg oklch(0.94 0.04 155)`, `--wn oklch(0.52 0.12 70)`/`oklch(0.95 0.05 85)`, `--dg oklch(0.52 0.17 25)`/`oklch(0.95 0.03 25)`, `--in oklch(0.50 0.12 245)`/`oklch(0.95 0.03 245)`, `--ai #5d5294`/`--aibg #ecebfd`, `--scrim oklch(0.2 0.02 277 / .4)`.

Màu chủ đạo thay thế (Cài đặt): Lam `oklch(0.70 0.10 240)` / sáng `oklch(0.48 0.11 245)`; Ngọc `oklch(0.72 0.09 185)` / `oklch(0.46 0.08 190)`; Đồng `oklch(0.72 0.09 60)` / `oklch(0.50 0.09 55)`. **Chưa đo tương phản AA — cần kiểm tra trước khi phát hành.**

Màu nhận diện dự án (ô vuông 8–14px): Enterprise OS `oklch(0.70 0.11 290)`, Pháp lý `oklch(0.72 0.10 205)`, Tài chính `oklch(0.74 0.11 60)`, Tuyển dụng `oklch(0.72 0.11 130)`.

**Quy tắc:** không gradient; không flood màu nhấn ra mảng lớn; nút chính là **viền** màu nhấn trên nền trong suốt (`.btn-primary` của Nocturne), không tô đặc.

### Chữ
- Font: **Inter** (hỗ trợ đủ dấu tiếng Việt), weight 400/500/600. Không đậm tiêu đề quá 500.
- Số liệu: `font-variant-numeric: tabular-nums` (không dùng font mono riêng).
- Thang: Display 36/1.25/500 · H1 26/1.25/500 · H2 22/1.3/500 · Body 14/1.5/400 · Body-sm 13–13.5/1.5 · Label 12.5/1.4/500 · Caption 11.5/1.4 · Micro (nhãn AI, badge) 10–11/600.
- Line-height tối thiểu **1.25** cho tiêu đề (dấu chồng Ữ, Ặ), 1.5 cho nội dung.
- Nhãn chip/nút/badge: `white-space: nowrap`, cắt bằng ellipsis khi thiếu chỗ. Kiểm tra với nhãn dài "Có task chậm tiến độ", "Không giới hạn", "Hồ sơ pháp lý KĐT Phú Mỹ".
- Ngày `dd/mm`, giờ 24h `14:00`, thập phân dấu phẩy `2,4 MB`.

### Khoảng cách · bo góc · độ nổi
- Space (mật độ 0.7×): 2.8 / 5.6 / 8.4 / 11.2 / 16.8 / 22.4 px. Thực tế dùng gap 6–12px, padding thẻ 12–18px, padding trang web 20px 28px.
- Radius: sm 4 · md 8 · lg 14 · pill 999 · bottom sheet 20 (góc trên).
- Shadow: sm `0 0 0 1px #3f424d` · md `0 0 0 1px #595d6c, 0 6px 18px rgba(0,0,0,.55)` · lg `0 0 0 1px #9397ab, 0 16px 40px rgba(0,0,0,.65)`. sm = thẻ, md = menu/toast/nút nổi, lg = modal/panel/sheet.
- Mobile: vùng chạm ≥44px; dòng task 72px; tab bar 56px + 34px safe-area dưới; status bar/tai thỏ 47px.

### Trạng thái tương tác
- Hover: nền `--sf2` hoặc viền `--ln` → `--mu`.
- Focus bàn phím: `outline: 2px solid var(--ac); outline-offset: 2px` trên mọi phần tử tương tác.
- Disabled: opacity .45.
- Mục đang chọn ở sidebar: nền `--acbg`, chữ `--act`, vạch trái 2px `--ac` (inset shadow).
- Tab gạch chân: chữ `--ac` + `inset 0 -2px 0 var(--ac)`. Segmented: chữ `--ac` + `inset 0 0 0 1px var(--ac)`.

### Icon
**Phosphor Icons** (`@phosphor-icons/web` 2.1.1 hoặc `@phosphor-icons/react`). Biến thể regular cho trung tính, fill/bold cho trạng thái.

---

## Hệ mã hoá trạng thái (bắt buộc: hình dạng + màu + chữ)

| Khái niệm | Hiển thị |
|---|---|
| Chưa làm | pill viền `--mu`, icon `circle-dashed` |
| Đang làm | pill viền `--in`, icon `circle-half` fill |
| Tạm dừng | pill viền `--wn`, icon `pause-circle` fill |
| Hoàn thành | pill viền `--ok`, icon `check-circle` fill; tiêu đề gạch ngang, chữ `--fa` |
| Bị chặn | badge vuông r4, viền + chữ `--dg`, 600, icon `prohibit` bold |
| Quá hạn | dải trái 3px `--dg` (`box-shadow: inset 3px 0 0`), nền hàng `--dg` 5%, chữ hạn `--dg` 600 "24/10 · trễ 2 ngày", icon `warning-circle`; nhóm có cờ `flag` fill |
| Ưu tiên | Cao `caret-double-up` `--dg` · TB `caret-up` `--wn` · Thấp `minus` `--mu` + chữ |
| Cờ | Quan trọng `star` fill `--wn` · Khẩn cấp `lightning` fill `--dg` |
| Hạn | quá hạn (đỏ) · ≤3 ngày `clock-countdown` `--wn` · hôm nay `clock` · ngày `calendar-blank` · định kỳ `repeat` · không hạn `infinity` `--fa` |
| Tải nhân sự | thước 4 nấc + pill: Rảnh `coffee` `--ok` · Vừa sức `gauge` `--in` · Bận `hourglass-medium` `--wn` · Quá tải `warning-octagon` `--dg` |

### Người vs AI
- **Người:** avatar **tròn**, nền `--sf2`, viền `--ln`, chữ viết tắt 2 ký tự (VT, QT, ĐD…).
- **AI (Hermes):** avatar **vuông bo** (r 6–10 tuỳ cỡ), nền `--aibg`, viền `--ai`, icon `sparkle` fill `--ai`; kèm nhãn **"AI"** (10px/600, viền `--ai`, r4) cạnh tên. Bubble chat của AI: nền `color-mix(--ai 8%, --sf)`, viền `--ai` 40%. Mọi hành động AI trong nhật ký/thông báo có icon ✦. AI **không tính KPI**.
- Chưa giao: avatar tròn viền đứt `--fa`, tên "Chưa giao".

---

## Screens / Views — Web (`Enterprise OS Web.dc.html`)

### Khung (shell)
- Grid `240px | 1fr`, min-height 100vh.
- **Sidebar** (sticky, nền `--sf`, viền phải `--ln2`, padding 12/10): logo (ô 30px viền `--ac` "EOS" + "Enterprise OS" / "Giao việc & điều phối"), 3 nhóm tiêu đề 11px uppercase `--fa` letter-spacing .06em:
  - **Việc của tôi:** Hôm nay (8, badge đỏ 3 quá hạn), Sắp tới 12, Việc định kỳ 5, Bất cứ lúc nào 4, Hoàn thành 41, Backlog 6
  - **Quản lý:** Tổng quan, Tất cả task 64 (đỏ 5), Dự án 4, Thành viên 7, Nhân sự
  - **Góc nhìn:** Kanban, Eisenhower, Lịch tháng, Lịch ngày, Tuần, Timeline
  - Cuối: Cài đặt. Mỗi mục 34px, icon 17px, số đếm tabular `--fa`; badge quá hạn: nền `--dgbg`, chữ `--dg` 11/600 + icon cờ.
- **Topbar** (sticky, 56px, nền `--bg` 88% + blur 10px, viền dưới): nút chọn công ty (ô chữ tắt + tên + caret) · ô tìm kiếm toàn cục (max 460, co giãn, placeholder "Tìm task, dự án, người, công văn…") · nút **+ Task** (gợi ý phím N) · chuông (badge đỏ 5) · avatar 32px.
- Main: padding 20/28/110, max-width 1400.
- **Nút Hermes nổi:** cố định phải-dưới 24px, cao 52, r14, nền `--sf`, viền + chữ `--ai`, "✦ Hỏi Hermes".
- Mỗi màn có **ghi chú thay đổi** (khung viền đứt) — bật/tắt bằng prop `showNotes`; **không đưa vào production**.

### 1. Tổng quan
- Header: eyebrow "EOS Holdings · 4 dự án · 7 thành viên", H1; bên phải segmented **Tuần / Tháng / Quý** + nút lọc thành viên.
- Dải 6 ô chỉ số (grid auto-fill min 150px): Tổng 64 · Đã xong 41 · Đang làm 12 · Quá hạn 5 (số màu đỏ) · Hạn 3 ngày 7 · Hạn 7 ngày 11. Mỗi ô: viền trên 2px màu ngữ nghĩa (inset), icon + nhãn 12px, số 28px/500, dòng phụ 11.5px. Ô bấm được để lọc.
- Grid auto-fit min 400px:
  - **Tuần này đã hoàn thành:** số 52px "18 / 24 mục tiêu", 75% đạt mục tiêu, chuỗi 6 ngày (icon lửa `--wn`), 89% đúng hạn, thanh tiến độ 8px.
  - **Dự báo tuần tới** (gắn avatar AI): 22 việc đến hạn, 3 rủi ro (`--wn`) + danh sách lý do cụ thể.
  - **Theo trạng thái:** thanh xếp chồng 14px + chú thích 2 cột.
  - **Theo người làm:** thanh ngang Xong/Đang làm/Quá hạn mỗi người, Hermes có nhãn AI.
  - **Burndown 14 ngày:** cột "còn lại thực tế" (màu nhấn 45%, cột hôm nay đậm) + vạch đứt lý tưởng; trục 13/10 – 26/10.
  - **Ưu tiên theo dự án:** thanh xếp chồng Cao/TB/Thấp.

### 2. Hôm nay (và khung chung cho mọi màn danh sách)
- Header: eyebrow ngày, H1, dòng tóm tắt (3 quá hạn đỏ · 5 trong ngày · Hermes đang xử lý 1). Phải: segmented Tất cả/Của tôi/Đội nhóm, Lọc, Chọn nhiều.
- Hàng tiêu đề cột rồi các **nhóm**: "Quá hạn" (cờ đỏ, hành động "Dời tất cả sang hôm nay") **luôn trên cùng**, sau đó "Hôm nay · 26/10".
- **Dòng task** (flex-wrap; bên phải là grid cố định `150 | 124 | 76 | 112 | 104`): nút tick 36×36 (circle → check-circle `--ok`) · tiêu đề 500 + cờ ★/⚡ + badge Bị chặn; dòng phụ: ô màu dự án + tên dự án · người làm (avatar 24 + tên + nhãn AI) · hạn · ưu tiên · pill trạng thái · số việc con x/y, bình luận, đính kèm (opacity .35 khi 0). Padding 6/14/6/8, kẻ trên `--ln2`, hover `--sf2`.
- Bấm dòng → mở panel chi tiết. Bấm tick → hoàn thành + toast "Đã hoàn thành “…”" có **Hoàn tác**.

### 3. Các danh sách khác (cùng khung dòng task)
- **Sắp tới:** nhóm theo ngày ("Ngày mai · T3 27/10" icon `clock-countdown` vàng, T5 29/10, T6 30/10, "Tuần sau · 02/11 – 08/11").
- **Việc định kỳ:** nhóm Hằng ngày / Hằng tuần / Hằng tháng; cột Hạn hiển thị quy tắc ("Hằng tuần · T6"), icon `repeat`.
- **Bất cứ lúc nào:** nhóm Đang làm / Chưa bắt đầu; hạn "Không hạn" icon `infinity`.
- **Hoàn thành:** nhóm Hôm nay / Tuần này.
- **Backlog:** việc chưa giao (avatar viền đứt), hành động nhóm "Nhờ Hermes phân công".
- **Tất cả task:** thêm **thanh lọc** (nền `--sf`, r14): segmented trạng thái có icon (Tất cả/Chưa làm/Đang làm/Tạm dừng/Hoàn thành — đang hoạt động), segmented phạm vi Đội nhóm/Cá nhân/Chưa giao, "Người làm: 3" (đang bật → viền + chữ `--ac`), Danh mục, khoảng ngày "20/10 – 08/11", Sắp xếp. Kết quả nhóm theo dự án. Không có kết quả → trạng thái rỗng "Không có task nào khớp bộ lọc" + "Xoá lọc trạng thái".

### 4. Kanban
- 4 cột (grid `repeat(4, minmax(250px,1fr))`, cuộn ngang khi hẹp): Chưa làm / Đang làm / Tạm dừng / Hoàn thành; tiêu đề cột = icon trạng thái + tên + số + nút "+". Nền cột `color-mix(--sf 55%, --bg)`, r14, min-height 420.
- **Thẻ:** nền `--sf`, r8, padding 10/12: hàng dự án (ô màu + tên + icon ưu tiên) · tiêu đề 13.5/500 + cờ · badge Bị chặn · thanh việc con 3px `--ok` · hàng cuối avatar 22 + hạn + việc con + bình luận. Quá hạn: dải trái đỏ.
- **Kéo thả** HTML5: thẻ đang kéo opacity .4; cột đích viền `--ac`. Thả → đổi trạng thái; thả vào Hoàn thành = đánh dấu xong; toast "Đã chuyển sang “…”".

### 5. Eisenhower
- Grid `28px | 1fr | 1fr`; trục chữ: cột KHẨN CẤP / KHÔNG KHẨN, hàng QUAN TRỌNG / KHÔNG QUAN TRỌNG (dọc, writing-mode).
- 4 ô (min-height 260): **Làm ngay** (⚡ `--dg`), **Lên lịch** (`calendar-plus` `--in`), **Giao việc** (`user-switch` `--wn`), **Để sau** (`hourglass` `--mu`); viền trên 3px màu ô; tiêu đề + mô tả + số.
- Việc trong ô: hàng nhỏ (icon trạng thái, tiêu đề, hạn, avatar 22). Ô mặc định tính từ cờ imp/urg.
- Kéo thả giữa ô. **Prototype chỉ đổi ô hiển thị**; khi triển khai, thả vào ô phải **cập nhật cờ Quan trọng/Khẩn cấp** của task (Làm ngay = cả hai, Lên lịch = chỉ QT, Giao việc = chỉ Khẩn, Để sau = không cờ).

### 6. Lịch (Tháng / Tuần / Ngày / Timeline)
- Header chung: eyebrow "Đồng bộ Google Calendar · 2 phút trước", H1 theo chế độ, nút ‹ Hôm nay ›, segmented Tháng/Tuần/Ngày/Timeline (chuyển giữa 4 mục sidebar).
- **Tháng:** grid 7 cột, ô min-height 112; số ngày (hôm nay: viền tròn `--ac`), tối đa 3 mục, còn lại "+n việc nữa". Mục: dải trái 2px màu dự án; icon: quá hạn = cờ đỏ, Google = `google-logo` `--in`, định kỳ = `repeat`. Ngày ngoài tháng nền mờ.
- **Tuần:** 7 cột min 150 (cột hôm nay viền + vạch trên `--ac`), thẻ có tiêu đề + "giờ · người làm".
- **Ngày:** dải trên cùng cho việc không có giờ + việc quá hạn; lưới 07:00–19:00, 56px/giờ, khối định vị theo giờ, cao theo thời lượng (min 30px); sự kiện Google nền `--in` 14%; vạch đỏ 2px giờ hiện tại.
- **Timeline:** cột trái 260 sticky, 20 cột ngày × 40px (cuối tuần nền `--ln2`, cột hôm nay nền `--acbg`); nhóm theo dự án (hàng tiêu đề `--sf2`, thu gọn được); thanh r5 tô `color-mix(màu trạng thái 22%)` viền màu trạng thái, quá hạn có dải trái đỏ.

### 7. Dự án
- **Lưới thẻ** (auto-fill min 300): ô màu + công ty + hạn; tên 16/500; mô tả; "58% · 14/24 việc" + "⚑ 2 quá hạn" đỏ; thanh 6px; dãy avatar (AI vuông) + "n thành viên". Bấm → trang dự án.
- **Trang dự án:** breadcrumb "Dự án › tên"; H1 + "58% · hạn 25/11"; tab gạch chân **Kanban / Danh sách / Mindmap / Gantt**; **thanh lọc dùng chung cho cả 4 tab** (tìm trong dự án, "Của tôi" đang bật, Người làm, Ưu tiên, Hạn chót, Xoá lọc).
  - **Kanban:** như màn Kanban, chỉ việc của dự án.
  - **Danh sách:** cột `công việc | trạng thái 130 | ưu tiên 110 | người làm 170 | hạn 110`; **sửa tại chỗ** bằng select/input cao 30px; việc con thụt 22px với icon `arrow-elbow-down-right`.
  - **Mindmap:** nút gốc (viền `--ac`, nền `--acbg`) → nhánh hạng mục (200px, "x/y xong") → lá (icon trạng thái + tiêu đề); nối bằng đường 1px `--ln`.
  - **Gantt:** như Timeline, một dự án.

### 8. Chi tiết task — panel trượt phải (đề xuất thay cho trang mới)
- Overlay `--scrim` + panel cố định phải, rộng `min(820px, 100vw − 260px)`, nền `--bg`, shadow lg. Đóng: ✕, click scrim, **Esc**. Có nút "Mở toàn trang" và "Sao chép link" (deep link `/task/EOS-142`).
- Thanh trên 52px: dự án › mã task.
- Grid `1fr | 230px`:
  - **Trái:** tiêu đề 22/500 · hàng chip trạng thái (pill, có caret), Ưu tiên, Người làm, khoảng ngày "22/10 → 14:00" · nút **Đánh dấu bị chặn** (đỏ), Sửa, Lưu trữ, Xoá (ghost đỏ) · Mô tả · **Việc con** (3/5 + thanh; mỗi dòng 36px: tick, tên, người, hạn) · **Checklist** (checkbox accent) · **Tài liệu đính kèm** (thẻ link Drive / file + nút "Thêm link Drive", "Tải file (tối đa 5 MB)") · **Link kết quả** (`seal-check` `--ok`) · **Trao đổi** dạng chat (avatar, tên, nhãn AI, giờ; @mention màu `--act` 500) + ô nhập (đính kèm, textarea "gõ @ để nhắc tên", Gửi); gõ `@` mở menu nhắc tên (người + Hermes) · **Nhật ký thay đổi** (icon, ai, làm gì, khi nào; AI dùng ✦ `--ai`).
  - **Phải:** Người theo dõi (+Thêm), Cờ, Lặp lại, Danh mục, Người tạo + thời gian, Thời lượng.

### 9. Form tạo/sửa task (modal)
- Mở: nút "+ Task" hoặc phím **N** (không kích hoạt khi đang gõ trong input). Modal 720px, top 6vh, max-height 88vh, cuộn trong. Esc đóng; Ctrl+Enter lưu.
- Tab: **Tạo thủ công** / **✦ Tạo bằng AI**.
- Thủ công, phần mặc định: tên (17px, 44px) · segmented Công việc/Cá nhân · nút bật **Quan trọng** (★ `--wn`) / **Khẩn cấp** (⚡ `--dg`) + hiển thị ô Eisenhower tương ứng · grid 2 cột: Hạn chót, Người làm (gồm Hermes, Chưa giao), Dự án, Danh mục, Trạng thái, Ưu tiên · Người theo dõi dạng chip chọn nhiều (chip AI tím) · nút **"Thêm chi tiết"**.
- Thêm chi tiết: Lịch trình segmented **1 ngày / Nhiều ngày / Không giới hạn** · Bắt đầu, Giờ, Thời lượng, Lặp lại · Việc con + "Chèn từ mẫu “Hồ sơ đất đai”" · Đính kèm (link Drive hoặc file ≤5 MB) · Link kết quả.
- Footer: gợi ý phím, Huỷ, **Tạo task**.

### 10. Tạo task bằng AI (trong form)
- Stepper 1 Mô tả → 2 Xem & sửa → 3 Xác nhận.
- Bước 1: textarea mô tả tự nhiên + chip ví dụ; nút "✦ Phân tích mô tả".
- Bước 2: thông báo AI ("Hermes đề xuất… chưa có gì được lưu cho đến khi bạn bấm Xác nhận"); sửa được Tiêu đề, Người làm, Ưu tiên, Hạn; danh sách **việc con đề xuất** có checkbox + hạn. Nút "Quay lại", "Xác nhận tạo 1 task + 4 việc con".

### 11. Trợ lý Hermes (web)
- Panel nổi 400×≤580 phía trên nút Hermes. Header avatar AI + "Hermes · AI Agent · chỉ đọc dữ liệu bạn được xem".
- Tin người dùng căn phải (nền `--sf2`); câu trả lời của AI kèm **danh sách task bấm được** (dải đỏ nếu quá hạn, bấm → mở chi tiết) và nút hành động gợi ý ("Nhắc người làm", "Dời hạn sang 28/10").
- Gợi ý nhanh: **Việc hôm nay · Việc quá hạn · Tóm tắt tuần · Ai đang rảnh?**; ô nhập "Hỏi Hermes hoặc giao việc…".

### 12. Thành viên
- 4 thẻ vai trò (**Quản trị viên** `crown-simple` `--wn` · **Quản lý** `user-gear` `--in` · **Thành viên** `user` · **AI Agent** ✦ viền tím) với 3 dòng quyền + số người.
- Bảng: thành viên (avatar, tên, email), phòng ban, **select đổi vai trò** (AI bị khoá), hoạt động (chấm online), menu "…".
- Khối **Mã mời**: mã lớn (viền đứt `--ac`, letter-spacing .12em) + nút sao chép; vai trò khi tham gia, hết hạn (7/30 ngày), số lượt; nút "Tạo mã mời" sinh mã mới.

### 13. Nhân sự
- 4 ô chỉ số: Tổng nhân sự, Đang rảnh, Có task bị chặn, **Có task chậm tiến độ**.
- Biểu đồ cột "Task hoàn thành theo người · tháng 10" (đúng hạn `--ok` + trễ `--wn` xếp chồng) — cơ sở KPI; nút "Xuất KPI".
- Thẻ người (auto-fill min 300): avatar 38, tên, phòng ban · vai trò, pill tải, thước 4 nấc, "đang mở / xong tháng này / đúng hạn", dòng vấn đề cụ thể ("Bị chặn: …", "Chậm: …"). Hermes có thẻ riêng ghi "không tính KPI".

### 14. Thông báo · Chọn công ty · Cài đặt
- **Thông báo** (popover 400px dưới chuông): tiêu đề + "5 chưa đọc" + "Đánh dấu đã đọc"; chip lọc Tất cả / Nhắc tên tôi / Từ Hermes; mỗi mục: avatar (AI vuông), "**Ai** làm gì **task**" (task màu `--act`), giờ, chấm chưa đọc; chưa đọc nền `--ac` 5%. Bấm → mở chi tiết task.
- **Chọn công ty** (popover 320px): EOS Holdings (Quản trị viên), EOS Xây dựng (Quản lý), EOS Bất động sản (Thành viên) — mỗi mục 48px có vai trò, số dự án, số quá hạn, dấu ✓ mục hiện tại; "Xem gộp tất cả công ty", "Tạo công ty mới". Đổi công ty → cập nhật topbar + toast.
- **Cài đặt** (max 820, các khối grid `200px | 1fr`): Giao diện (Tối/Sáng/Theo hệ thống; 4 màu chủ đạo dạng chấm 32px có vòng chọn; mật độ Vừa/Gọn) · Mục tiêu (slider mục tiêu tuần 5–60, mặc định 24; ngày làm việc T2–CN) · Mẫu checklist (danh sách mẫu + số lần dùng, "Mẫu mới").

---

## Screens — Mobile (`Enterprise OS Mobile.dc.html`, 390×844)
Khung chung: status bar 47px; **tab bar dưới 5 mục**: Hôm nay · Lịch · **(+) Tạo nhanh** (nút 52×44, r12, viền 1.5px `--ac`) · Dự án · Thêm; padding dưới 34px cho thanh home. Nút Hermes nổi vuông 52px (r14, viền `--ai`) ở phải, trên tab bar — khác hình nút tạo.

- **M1 Hôm nay:** tiêu đề 30px; chip phạm vi (Của tôi · 6 / Đội nhóm · 8 / Chưa giao); nhóm Quá hạn trên cùng; dòng 72px, tick 44px. **Vuốt phải** → nền `--ok` "Hoàn thành"; **vuốt trái** → 2 nút 88px "Hoãn 1 ngày" (`--wn`) và "Đổi hạn" (`--in`). Ngưỡng gợi ý: lộ hành động ở ~30% chiều rộng, tự thực hiện khi vượt ~60%; có haptic + toast Hoàn tác.
- **M2 Tạo nhanh (bottom sheet):** r20 trên, tay nắm 36×5; lần đầu chỉ có **tên** (18px, gạch chân `--ac`, tự focus), **hạn** (chip Hôm nay / Mai 27/10 / T6 30/10 / Chọn), **người làm** (chip avatar; người hay giao gần đây xếp trước; có Hermes); nút "Thêm chi tiết" kéo sheet lên toàn màn; Huỷ + **Tạo task** (48px). Có lối "✦ Tạo bằng AI".
- **M3 Chi tiết + trao đổi:** thanh nav (‹, tên dự án, …); tiêu đề 21px; chip trạng thái/ưu tiên/hạn/người; tab phân đoạn **Chi tiết / Trao đổi · 8 / Nhật ký**; chat (AI có nhãn + viền tím, của mình căn phải nền `--acbg`); **ô nhập dính đáy** có hàng gợi ý @nhắc tên trên bàn phím; các thao tác Bị chặn/Sửa/Lưu trữ/Xoá trong menu "…".
- **M4 Kanban:** chỉ báo cột trên (4 nhãn có số + thanh 3px, cột hiện tại màu trạng thái); **mỗi cột ~340px, vuốt ngang có snap** (`scroll-snap-type: x mandatory`), cột kế ló ra ~30px; chấm chỉ báo dưới. **Nhấn giữ thẻ** → menu "Chuyển sang" (Chưa làm / Đang làm · hiện tại / Tạm dừng / Hoàn thành / Đánh dấu bị chặn), mỗi mục 44px.
- **M5 Lịch:** segmented Tuần/Tháng; tháng chỉ hiện số + **tối đa 3 chấm** 5px (đỏ = quá hạn, xanh = Google, tím = việc); hôm nay vòng `--ac`; chạm ngày → danh sách ngày trong sheet dưới (giờ 48px | thẻ có dải màu). Chế độ Tuần = dải 7 ngày vuốt ngang + danh sách.
- **M6 Dự án:** thẻ dự án gọn (tên, thanh tiến độ, %, số quá hạn, hạn); **Gantt/Mindmap chỉ xem** — cuộn ngang, chụm để phóng (pinch-zoom), cột hôm nay tô `--acbg`.
- **M7 Hermes:** toàn màn hình; câu trả lời là thẻ người/task bấm được; gợi ý nhanh + ô nhập (viền `--ai`, nút mic, gửi) **dính ngay trên bàn phím** (dùng `visualViewport`/`KeyboardAvoidingView`).
- **M8 Tổng quan:** segmented Tuần/Tháng/Quý; khối tuần (40px "18 / 24 · 75%", chuỗi ngày, % đúng hạn) lên đầu; 6 chỉ số lưới 3×2; dự báo rủi ro; theo trạng thái; các biểu đồ còn lại khi cuộn.
- **M9 Thêm:** hồ sơ + "Đổi công ty" ở đầu; 3 nhóm giống sidebar web (Việc của tôi / Quản lý / Góc nhìn), mỗi mục 48px có số đếm, badge quá hạn. Nhóm Quản lý chỉ hiện với Quản lý trở lên.
- **M10 Eisenhower:** lưới 2×2 thu gọn (số đếm + icon, ô đang chọn viền `--ac`) làm tab; danh sách ô đã chọn trong sheet dưới; đổi ô bằng menu khi nhấn giữ.
- **M11 Chọn nhiều:** nhấn giữ dòng → thanh trên nền `--acbg` "Đã chọn 3" + ✕ + "Chọn tất cả"; tick đổi thành ô chọn (`check-square` `--ac`); tab bar đổi thành 4 hành động: Hoàn thành / Đổi hạn / Giao cho / Khác.

---

## Design System & trạng thái (`Enterprise OS Design System.dc.html`)
Gồm: màu sáng/tối + ngữ nghĩa, thang chữ, khoảng cách/bo góc/độ nổi, component (chip trạng thái/ưu tiên/hạn, avatar người vs AI, ô chỉ số, dòng task ở 6 trạng thái gồm focus, nút, segmented, tab, chip lọc, thẻ Kanban thường/đang kéo), lớp nổi (modal xác nhận xoá, bottom sheet đổi hạn, 3 kiểu toast), và **trạng thái rỗng / skeleton / lỗi** cho Hôm nay, Kanban, Tổng quan:
- **Rỗng:** luôn có một hành động tiếp ("Xem Sắp tới", "+ Thêm", "Xem theo Tuần").
- **Skeleton:** khối `--ln2` giữ đúng kích thước nội dung thật; shimmer nhẹ, tắt khi `prefers-reduced-motion`.
- **Mất mạng:** banner `--wnbg`/`--wn` "Mất kết nối · đang hiện dữ liệu lúc 09:41"; vẫn cho đánh dấu xong, hàng chờ hiện "chờ đồng bộ" (cần hàng đợi offline).
- **Lỗi thao tác:** thẻ viền `--dg`, mô tả việc đã hoàn tác + Thử lại / Báo lỗi.
- **Lỗi từng khối** (Tổng quan): khối hỏng viền đứt đỏ + "Tải lại khối" — không làm trắng cả trang.

---

## Interactions & Behavior (tổng hợp)
- Phím tắt: **N** = tạo task; **Esc** = đóng panel/modal/Hermes; Ctrl+K = tìm kiếm (đề xuất); Ctrl+Enter = lưu form.
- Toast: giữa đáy (web) / trên tab bar (mobile); tự ẩn ~3.5–4 giây; luôn có Hoàn tác hoặc hành động tiếp; toast lỗi không tự ẩn.
- Popover (thông báo, công ty): click ra ngoài để đóng.
- Hoàn thành task: tick → trạng thái done, gạch ngang, toast Hoàn tác (optimistic update, rollback khi lỗi).
- Kéo thả (Kanban, Eisenhower): optimistic; lỗi → thẻ về chỗ cũ + thẻ lỗi. Nên dùng `dnd-kit` thay HTML5 DnD để hỗ trợ bàn phím/cảm ứng.
- Upload: chặn file >5 MB phía client, gợi ý dùng link Drive.
- @mention: gõ `@` mở danh sách thành viên (gồm Hermes), lọc theo chữ gõ, ↑↓ Enter để chọn.
- Responsive web: lưới thẻ dùng auto-fill/auto-fit; bảng rộng cuộn ngang trong khung; topbar ô tìm kiếm co lại trước.
- Mobile: mọi vùng chạm ≥44px; tôn trọng safe-area (`env(safe-area-inset-*)`).
- Tiếp cận: WCAG AA; focus ring đầy đủ; `aria-label` cho nút icon; trạng thái không chỉ bằng màu; `role="status"` cho toast; `aria-busy` khi skeleton.

## State Management (gợi ý)
- **Entity:** Company, Member (role: admin | manager | member | agent; isAI), Project (color, members, dueDate), Task (title, type công việc/cá nhân, status todo|doing|paused|done, priority high|med|low, important, urgent, blocked, assigneeId|null, watcherIds, categoryId, projectId, start/due, time, durationMin, schedule one|multi|none, recurrence rule, subtasks, checklist, attachments, resultLink, createdBy/At), Comment (authorId, body, mentions, isAI), ActivityLog, Notification, InviteCode (code, role, expiresAt, usesLeft), ChecklistTemplate, Settings (theme, accent, density, weeklyGoal, workdays).
- **Giá trị suy ra:** nhóm Hôm nay/Quá hạn/Sắp tới; ô Eisenhower từ (important, urgent); mức tải nhân sự (Rảnh/Vừa sức/Bận/Quá tải) theo số việc mở + quá hạn; chỉ số tuần (hoàn thành/mục tiêu, chuỗi ngày, % đúng hạn); burndown; dự báo rủi ro (Hermes).
- **UI state:** công ty hiện tại, màn/tab hiện tại, task đang mở (đồng bộ URL), bộ lọc (giữ khi đổi tab trong trang dự án), modal/sheet/popover đang mở, chế độ chọn nhiều, hàng đợi offline.
- **Dữ liệu:** đồng bộ Google Calendar (2 chiều hoặc chỉ đọc — cần xác định); realtime cho bình luận/thông báo (WebSocket/SSE); Hermes qua API agent riêng, mọi hành động ghi `actorType: 'ai'`.

## Assets
- Icon: Phosphor Icons (MIT).
- Font: Inter (Google Fonts / rsms, OFL).
- Không có ảnh bitmap. Biểu đồ dựng bằng div/CSS — khi triển khai có thể dùng Recharts/visx/ECharts với cùng bảng màu ngữ nghĩa.
- Dữ liệu mẫu (tên người, dự án, ngày) là giả lập, chỉ để minh hoạ.

## Files
- `Enterprise OS Web.dc.html` — prototype web tương tác (mọi mục sidebar, panel chi tiết, form + AI, Hermes, thông báo, chọn công ty). Props: `theme` (dark|light), `showNotes`.
- `Enterprise OS Mobile.dc.html` — 11 màn mobile M1–M11 đặt cạnh nhau. Prop `theme`.
- `Enterprise OS Design System.dc.html` — token, component, lớp nổi, trạng thái rỗng/loading/lỗi.
- `_ds/nocturne-…/styles.css` — token gốc Nocturne + class `.btn`, `.seg`, `.input`, `.field`… (`_ds_bundle.js` là runtime hỗ trợ của file thiết kế).
- `support.js` — runtime để mở các file `.dc.html` trong trình duyệt (không dùng cho production).
- `uploads/Enterprise OS.html` — bản giao diện hiện tại (tham chiếu “trước khi thiết kế lại”).

Mở file: giải nén, chạy một static server tại thư mục gốc (ví dụ `npx serve .`), mở từng `.dc.html`.

## Gợi ý dùng với Claude Code
1. Giải nén gói này vào thư mục `design/` của repo.
2. Prompt mở đầu: *“Đọc design/README.md và các file .dc.html. Dựng design token (sáng/tối) và các component chung (TaskRow, KanbanCard, StatusChip, PriorityChip, DueChip, Avatar người/AI, StatTile, Segmented, FilterBar, BottomSheet, Modal, Toast, EmptyState, Skeleton) trước, sau đó làm màn Hôm nay.”*
3. Làm từng màn theo thứ tự: Hôm nay → Chi tiết task → Form → Kanban → Dự án → Tổng quan → Lịch → Nhân sự/Thành viên → Mobile.
