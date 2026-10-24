# 13 · Hệ thống hợp nhất (24/10/2026): Enterprise OS là nơi duy nhất quản lý việc

Ever Teams **đã gỡ**. Mọi việc, dự án, duyệt, báo cáo nằm ở **Enterprise OS** (`https://work.enterpriseos.bond/app`). Tài liệu này là bản kiểm kê và luồng làm việc chuẩn sau hợp nhất.

## 1. Đã làm với Ever Teams
| Hạng mục | Trạng thái | Hoàn tác |
| --- | --- | --- |
| Sao lưu đủ (CSDL, tệp, cấu hình) | `/root/ever-teams-final-2026-10-24-1555/` (vps169), `~/backups/ever-teams-final/` (Z2) | – |
| 21 việc đang chạy | Đã nhập vào Enterprise OS (`ever-id:` trong mô tả, nhập lặp không trùng) | – |
| 14 container (api, webapp, db, redis, minio, jitsu, pgweb, …) | **Đã dừng**, `restart=no`, volume giữ nguyên | `cd /opt/apps/ever-teams && docker compose up -d` |
| Caddy `teams.*`, `teams-api.*` | Chuyển hướng 302 về `work.*/app` (sao lưu `Caddyfile.bak-everteams-*`) | khôi phục bản sao lưu, `systemctl reload caddy` |
| Hermes: MCP `everteams`, plugin `ever-teams-tasks`, skill `ever-teams*`, đoạn persona Mai, SOUL ks | Đã gỡ/viết lại bằng `ops/hermes_remove_everteams.py` (sao lưu `*.bak-everteams-*`; skill ở `skill-backups/`) | chép lại tệp `.bak-everteams-*` |
| Cron Ever của ops-admin (báo cáo sáng, tổng kết tuần) | **Tạm dừng** (không xóa); thay bằng 2 cron Enterprise OS | `hermes -p ops-admin cron resume <id>` |
| **Việc còn cho chủ sở hữu** | Xóa volume + image Ever (~GB) sau ≥ 30 ngày không sự cố; xóa bản ghi DNS `teams`, `teams-api`; xóa 2 cron Ever đã dừng | – |

## 2. Kiểm kê profile Hermes (vps173)
| Profile | Vai trò | Công cụ (MCP) | Skill chính | Cron |
| --- | --- | --- | --- | --- |
| `eos-dieu-phoi` | Agent: chia việc dự án | enterprise-os | du-an | – |
| `eos-van-thu` | Agent: công văn NĐ 30, biên mục | enterprise-os | van-thu, du-an | – |
| `eos-quan-tri-du-lieu` | Agent: nạp kho tri thức WeKnora | enterprise-os | du-an | – |
| `eos-nhan-su` | Agent: nhân sự | enterprise-os | – | – |
| `team_admin` (Mai, Zalo) | Điều phối viên giao tiếp | deo-facts, weknora (+ enterprise-os khi chủ duyệt token, §5) | enterprise-os-guide, project-dossier-evidence | – |
| `ks-kinh-te-xd` | Phòng Kinh tế xây dựng | drive, weknora (+ enterprise-os khi duyệt token) | xay-dung, enterprise-os-guide | cảnh báo 08:00, tuần T2 07:30, dọn file tạm 08:30 |
| `ops-admin` | Vận hành, bản tin | deo-facts, weknora, cloudflare | deo, hermes, erpnext, … | **bản tin EOS 08:00, tổng kết tuần EOS** (Ever: tạm dừng) |
| `staff-work` | Nhắc việc nhân viên (ERPNext) | erpnext | – | nhắc 08:00 và 17:30 |
| `default`, `personal_assitant` | Cá nhân, không thuộc luồng công ty | – | – | – |

Ngoài Hermes: **runner Z2** (agent `runner`, nhận việc qua MCP), **cầu nối** `eos-kanban-bridge` (Work ↔ Kanban Hermes), `zalo-sidecar`, `hermes-gateway`.

**Agent trong CSDL** (`agent.agents`): dieu-phoi, van-thu, quan-tri-du-lieu, nhan-su (executor `hermes`), runner (executor `runner`), `phap-che` (chưa có profile → không giao việc cho agent này).

## 3. Công cụ MCP Enterprise OS (18)
Đọc: `eos_my_day`, `eos_list_tasks`, `eos_get_task`, `eos_guide`, `eos_company_digest`, `eos_list_members`, `eos_list_projects`, … · Ghi: `eos_task_save`, `eos_comment`, `eos_delegate`, `eos_submit_result`, … · Dự án/runner/nạp: `eos_project_*`, `eos_runner_*`, `eos_kb_ingest`. Phạm vi mã: người dùng `read, write, drive, hr_self, kb`; agent thêm `delegate, draft, project, runner, ingest` (ràng buộc CHECK, người không được cấp). Mã hết hạn tối đa 90 ngày.

## 4. Cron báo cáo: kiểm tra 24/10/2026
| Cron | Lịch | Kết quả lần chạy gần nhất | Ghi chú |
| --- | --- | --- | --- |
| ops-admin · Bản tin Enterprise OS hằng sáng | 08:00 hằng ngày → Telegram | thử thủ công đạt | script, không LLM; lỗi MCP in 1 dòng cảnh báo, thoát 0 |
| ops-admin · Tổng kết tuần Enterprise OS | tuần | chưa tới kỳ đầu | |
| ops-admin · Ever (2 cái) | – | **tạm dừng** | xóa sau 30 ngày |
| ops-admin · Vòng lặp F4-F5 (`deo-agent-loop`) | */15 | tạm dừng sẵn từ trước | thuộc hệ Dẹo cũ, nên xóa |
| ks-kinh-te-xd · quét cảnh báo 0800 | 08:00 | 24/10 ok | |
| ks-kinh-te-xd · báo cáo tuần CHT | T2 07:30 | 19/10 ok | |
| ks-kinh-te-xd · dọn file tạm | 08:30 | đang hoạt động | |
| staff-work · nhắc việc sáng/cuối ngày | 08:00, 17:30 | 24/10 ok | **dữ liệu từ ERPNext, không phải Enterprise OS** (hệ thứ ba, §6) |

Mã bản tin (`EOS_REPORT_TOKEN`, phạm vi `read`) hết hạn sau 90 ngày kể từ lúc cấp (vào lịch cấp lại bằng `scripts/issue_user_token.sh`).

## 5. Mai và ks-kinh-te-xd dùng Enterprise OS thế nào
**Mai (team_admin)** có danh tính riêng: agent `mai` ("Mai - Trợ lý AI", `mai@agent.enterpriseos.bond`), vai trò mẫu `tro_ly_ai`, mã MCP phạm vi `read + task_create` (hết hạn 90 ngày từ 24/10/2026, ghi ở `team_admin/.env` biến `EOS_MCP_TOKEN`). Mai chỉ thấy 11 công cụ: tạo việc mới cho người (`eos_task_save`, không sửa, không đổi trạng thái, không giao agent), bình luận ghi chú, xem việc mình tạo/được giao, danh sách thành viên, bản tin "Việc của tôi". Việc Mai tạo mang tên Mai; người yêu cầu thật ghi trong mô tả. Cấu hình `enterprise-os` đã thêm vào `team_admin/config.yaml`; **hiệu lực sau khi khởi động lại `hermes-gateway`** (chờ chủ sở hữu duyệt).
**ks-kinh-te-xd**: đã có skill `enterprise-os-guide` và SOUL trỏ sang Enterprise OS; **chưa có mã MCP** (dùng kanban giao `team_admin`/hộp việc web). Nếu cần, tạo agent riêng tương tự Mai thay vì dùng mã của người.

## 6. Luồng làm việc chuẩn (thay luồng Ever Teams)
1. **Vào việc**: người dùng giao trên web (Giao việc: người/agent, hạn, ưu tiên, dự án, *Không cần duyệt / Phải duyệt*); hoặc nhắn Mai/ks → bot xác nhận → `eos_task_save`; hoặc cả dự án: **Dự án → Nạp hồ sơ dự án** (docs/12).
2. **Giao cho agent**: cầu nối tạo thẻ Kanban cho profile `eos-*` (hoặc runner Z2 nhận qua MCP). Agent hỏi lại → trả lời trong việc; không bấm Nộp thay.
3. **Nộp kết quả**: agent `eos_submit_result` (ghi tệp Drive thư mục dự án, link vào khối **Kết quả**); người nộp phải có ghi chú hoặc link.
4. **Duyệt**: việc *Phải duyệt* → `chờ duyệt` → người duyệt (trưởng phòng/vai trò/người/quản lý dự án/người giao) → `đã duyệt` mới được **Xong**.
5. **Hồ sơ dự án**: Điều phối chia việc → runner Z2 đọc Drive → Văn thư biên mục → Quản trị dữ liệu nạp WeKnora (`eos_kb_ingest`); kết quả ở **Dự án → Xem kết quả**.
6. **Báo cáo**: 08:00 bản tin ngày (quá hạn, chờ duyệt, hoàn thành hôm qua, agent kẹt), tuần: tổng kết; cả hai từ `eos_company_digest`.
7. **Giám sát**: `make acceptance`, `make audit`; sao lưu `/opt/backup/backup.sh` (có CSDL `eos`).

## 7. Việc mở
Mã Mai/ks (§5) · Zalo đa người (bot nhìn người nhắn là ai) · profile `phap-che` · bộ kiểm tra thư mục Drive người dùng · khóa WeKnora dạng chữ trong `team_admin/config.yaml` nên chuyển sang `.env` · `staff-work`/ERPNext và `deo-facts` (Dẹo cũ) cần quyết giữ hay gộp · đẩy GitHub bản 0.2.x.
