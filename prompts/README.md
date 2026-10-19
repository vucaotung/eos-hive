# Gói prompt triển khai cho Claude Code

Dùng để Claude Code (chạy trên **Z2** hoặc máy của bạn) tự SSH vào VPS 169, VPS 173 và máy Z2 để dựng Tổ Ong theo đúng thứ tự và có cổng kiểm tra.

## Thứ tự

| Bước | Tệp | Máy | Kết quả |
| --- | --- | --- | --- |
| 0 | `PASTE-ME.md` | nơi chạy Claude Code | Dán đoạn này vào Claude Code để bắt đầu |
| — | `00-MASTER.md` | — | Bối cảnh và luật chung (Claude Code đọc đầu tiên) |
| 1 | `10-z2.md` | Z2 | Kiểm thử xanh, GitHub private, SSH tới VPS thông |
| 2 | `20-vps169.md` | VPS 169 | CSDL, PostgREST, MCP chạy sau Caddy |
| 3 | `30-vps173.md` | VPS 173 | Kiểm chứng giả định Hermes, cầu nối, 3 profile agent |
| 4 | `40-nghiem-thu.md` | cả ba | Khói đầu–cuối, khôi phục sao lưu thử |
| — | `90-rollback.md` | từng máy | Cách quay lại nếu hỏng |

## Việc bạn phải tự làm (Claude Code sẽ dừng và nhắc)

1. Cung cấp **bí mật** bằng tay trên máy đích, không qua chat: `GOOGLE_CLIENT_ID/SECRET/REFRESH_TOKEN` vào `mcp/.env`; mật khẩu sao lưu.
2. Bấm xác nhận **tạo repo GitHub**, **tạo DNS** `work.enterpriseos.bond`, và mọi lệnh Claude Code hỏi "xóa/ghi đè".
3. Nếu SSH chưa thông: dán **khóa công khai** Claude Code in ra vào `~/.ssh/authorized_keys` của máy đích.

## Cách dùng

1. Giải nén `eos-hive` (hoặc `git clone`) vào `~/src/eos-hive` trên Z2.
2. Mở Claude Code trong thư mục đó: `cd ~/src/eos-hive && claude`.
3. Dán nội dung `PASTE-ME.md`. Claude Code tự đọc các tệp còn lại theo thứ tự.
4. Mỗi pha kết thúc bằng một báo cáo ngắn; đọc rồi mới nói "tiếp".

## Luật vàng
- Claude Code **không bao giờ in** nội dung `.env`, mã `eos_…`, JWT, khóa, mật khẩu. Bí mật sinh ra ngay trên máy đích và ghi vào tệp quyền 600.
- Đọc trước, sao lưu, sửa, kiểm tra, có đường quay lại. Không đụng dịch vụ khác trên VPS (Ever Teams, WeKnora, Grafana/Loki, các profile Hermes khác).
