# 50 · Prompt giao cho agent: tổng hợp lại báo cáo Enterprise OS

> Dán nguyên khối dưới đây cho agent (Claude Code trên Z2, hoặc profile `ops-admin`). Agent chỉ ĐỌC, không sửa dữ liệu, không in bí mật.

---
Bạn là kỹ sư vận hành của Tổ Ong (eos-hive). Hãy tổng hợp **báo cáo hiện trạng hợp nhất** sau khi Ever Teams được thay bằng Enterprise OS (EOS). Trả lời tiếng Việt, ngắn gọn, có số liệu và nguồn.

**Đọc trước (repo `eos-hive`)**: `prompts/00-MASTER.md`, `docs/13-he-thong-hop-nhat.md`, `docs/14-so-sanh-ke-hoach-va-de-xuat.md`, `docs/08-lo-trinh.md`, `CHANGELOG.md`.

**Luật**: chỉ đọc; không in token/khóa/mật khẩu; không sửa cấu hình, không khởi động lại dịch vụ, không xóa; không suy đoán: mục nào không kiểm chứng được thì ghi "chưa kiểm chứng" kèm lý do.

**Kiểm chứng trên máy thật (ghi lệnh đã dùng và kết quả)**
1. vps169: `systemctl is-active eos-mcp eos-web postgrest-eos caddy`; `docker ps` (xác nhận KHÔNG còn container Ever Teams chạy); `curl -sI https://teams.enterpriseos.bond` (kỳ vọng 302 về work); đếm bảng/hàm trong CSDL `eos`; migration cao nhất đã áp (kỳ vọng 0015).
2. vps173: `systemctl --user is-active hermes-gateway eos-kanban-bridge zalo-sidecar`; với mỗi profile trong docs/13 §2: danh sách MCP, skill, cron (`hermes -p <p> cron list`). Báo mọi nơi còn chữ `ever`/`everteams` trong `config.yaml`, `SOUL.md`, `skills/`, `cron/jobs.json` (trừ `skill-backups/` và tệp `.bak*`).
3. Cron: với mỗi cron đang active ghi lần chạy gần nhất, ok/lỗi, có giao tới Telegram không. Riêng `Ban tin Enterprise OS hang sang`: chạy `hermes -p ops-admin cron run <id>` KHÔNG; chỉ xem `cron runs` và nội dung bản tin gần nhất.
4. EOS: dùng công cụ `eos_company_digest` (days=1 và 7) và `eos_list_tasks`; nêu số việc theo trạng thái, quá hạn, chờ duyệt, agent kẹt (task blocked > 24 giờ), số việc nhập từ Ever (mô tả có `ever-id:`) và còn mở.
5. Bảo mật nhanh: ngày hết hạn các mã MCP đang dùng (chỉ ngày, không in mã), việc nào ≤ 30 ngày thì cảnh báo.

**Báo cáo gồm 7 phần**
1. Tóm tắt điều hành (≤ 8 dòng): hệ thống đã hợp nhất chưa, rủi ro lớn nhất.
2. Bảng hiện trạng: dịch vụ, profile, agent, skill, công cụ, cron (đạt / lỗi / chưa kiểm chứng).
3. Dấu vết Ever Teams còn sót và việc cần chủ sở hữu quyết (xóa volume, DNS, cron tạm dừng).
4. Kết quả cron báo cáo hằng ngày/tuần và chất lượng nội dung bản tin (thiếu/thừa gì so với nhu cầu của lãnh đạo).
5. Số liệu công việc từ EOS (bảng) và 5 việc đáng chú ý nhất.
6. Diff so với kế hoạch gốc: cập nhật bảng ở docs/14 §1 bằng dữ kiện vừa kiểm chứng, chỉ rõ chỗ docs/13, docs/14 đã sai hoặc cũ.
7. Đề xuất: 5-8 mục xếp theo giá trị/công sức, mỗi mục ghi: vấn đề, đề xuất, công sức (S/M/L), rủi ro, cách hoàn tác.

Xuất ra `ops-log/bao-cao-hop-nhat-<ngày>.md` và tóm tắt ≤ 15 dòng trong câu trả lời.
---
