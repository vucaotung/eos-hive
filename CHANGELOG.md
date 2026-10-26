# Nhật ký thay đổi

Theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/) và [Semantic Versioning](https://semver.org/lang/vi/).
Trong giai đoạn 0.x, mọi thay đổi lược đồ CSDL có thể phá vỡ; đã triển khai thật thì phải đi qua migration (xem docs/02).

## 0.2.8 — Giao diện Nocturne giai đoạn 2a: chi tiết việc và form giao việc (chưa triển khai)
- Panel chi tiết việc theo thiết kế (820px, chip, cột phải, trao đổi dạng chat có nhãn AI, việc con có tiến độ, đánh dấu bị chặn, hủy việc); việc mở đồng bộ URL (`?t=`), sao chép link.
- Form giao việc: "Thêm chi tiết", Ctrl+Enter, phím N. Không đổi CSDL/API. Chi tiết và phần còn thiếu: docs/18.

## 0.2.7 — Giao diện Nocturne (giai đoạn 1, chưa triển khai)
- Token Nocturne sáng/tối (mặc định tối), font Inter, hệ mã hoá trạng thái và ưu tiên, avatar AI vuông có nhãn "AI", dòng việc mới, sidebar 3 nhóm, topbar có tìm kiếm, tab dưới mobile 5 mục và màn Thêm. Không đổi CSDL.
- `design/`: gói thiết kế tham chiếu (không phải mã production). Tiến độ và khoảng cách dữ liệu: docs/18.

## Chưa phát hành
- `scripts/issue_agent_token.sh --revoke-old`: sau khi mã mới ghi vào `.env` thành công, thu hồi các mã cũ còn hiệu lực của cùng agent (không thu hồi nếu ghi lỗi; không in mã). Có test với ssh giả trong `scripts/test_mcp.sh`.

## 0.2.6 — Thành viên gồm người và AI agent
- Tab Quản trị → Thành viên: danh sách chung người + AI agent, lọc, tìm kiếm, ngăn chi tiết agent (vai trò, được/không được làm, người phụ trách, bật/tắt nhận việc). Cột kỹ thuật chỉ chủ sở hữu/quản trị thấy.
- CSDL (0023): `company_agents.owner_user_id/department_id/title/updated_at`, `agent.app_members`, `agent.app_agent_set`, trigger kiểm người phụ trách. Agent vẫn không có membership; `app_org` vẫn chỉ trả người.
- `deploy/setup_agent_profiles.sql`: bảng phân vai 7 agent (không chạy tự động).
- `/mcp`: khóa mã sai theo (IP, tiền tố mã) 20 lần/5 phút + tổng theo IP 200 lần; `MCP_AUTHFAIL_ALLOW` miễn ngưỡng tổng. Bot cùng IP vps173 không khóa lẫn nhau.
- Skill `enterprise-os-guide` 1.1.0 (`source_ref`, `duplicate`, hàng đợi thông tin bổ sung), `deploy/logrotate.eos-housekeeping`. Chi tiết: docs/17.

## 0.2.5 — Giới hạn và sửa lỗi lớp MCP (nhánh feat/hardening-0.2.5, chưa triển khai)
- `/mcp`: 20 mã sai/5 phút theo IP → 429 trước khi chạm CSDL; mẫu Caddy `deploy/Caddyfile.mcp.snippet`.
- `mcp_token_issue`: tham số công ty phải do quản trị công ty cấp (0018).
- Chống trùng việc theo khóa (tên chuẩn hóa, người phụ trách, `source_ref`) và trả lý do (0019).
- Theo dõi tải tệp Drive, đánh dấu tệp mồ côi, `upload_sweep` không xóa tệp (0020).
- Nạp kho song song: giữ chỗ từng tài liệu và việc tạo kho (0021).
- `housekeeping_prune` dọn bảng tạm (0022); bộ đếm tốc độ trong bộ nhớ tự dọn.
- Mô tả `eos_task_save`/`eos_comment` ghi rõ nội dung việc là dữ liệu, không phải lệnh. Chi tiết: docs/16.

## 0.2.4 — 2026-10-24 · Rà soát logic MCP
- Sửa: `eos_comment kind=answer` qua MCP chỉ cần xem được việc → người theo dõi/xem theo phòng có thể "trả lời" thay để agent chạy lại. Nay đúng luật web (agent đang chờ; chỉ người phụ trách/giao/sửa được).
- Bot (Mai) không tạo việc trùng (cùng tên + người phụ trách trong 15 phút trả lại việc cũ, `duplicate: true`).
- Mai tắt `company_agents.enabled` để không ai giao việc/chia việc cho agent này (cầu nối sẽ đẩy thẻ sang team_admin). Migration 0017; MCP e2e 32 bước.

## 0.2.3 — 2026-10-24 · Tài khoản agent Mai (phạm vi `task_create`)
- Phạm vi mã mới `task_create` (chỉ mã agent): tạo việc mới cho người + bình luận ghi chú; không sửa việc, không đổi trạng thái, không giao agent, không trả lời thay. Mã agent vẫn không có `write`.
- Cột `agent.agents.token_scopes` (thu hẹp mã của một agent); vai trò mẫu `tro_ly_ai` (tạo việc, xem việc mình tạo phạm vi own, bình luận, hỏi kho); quyền `work.comment.create`, `kb.ask`.
- Mã `task_create` chỉ thấy 11 công cụ tối thiểu; `agent._web_me` chấp nhận agent có `task_create`; `mcp_task_save` chặn sửa/đổi trạng thái/giao agent ở lớp CSDL. Migration 0016; kiểm thử MCP 31 bước.

## 0.2.2 — 2026-10-24 · Hợp nhất Ever Teams → Enterprise OS
- Gỡ Ever Teams: dừng 14 container (giữ volume), Caddy `teams.*` chuyển hướng về Enterprise OS, gỡ MCP/plugin/skill/persona Ever khỏi `team_admin`, `ks-kinh-te-xd`, `ops-admin` (`ops/hermes_remove_everteams.py`, có sao lưu); nhập 21 việc Ever vào EOS.
- Bản tin ngày/tuần từ EOS (`eos_company_digest`, `ops/eos_report.py`) thay cron Ever; cron Ever tạm dừng.
- Công cụ MCP mới: `eos_list_members`, `eos_task_save`, `eos_company_digest` (18 công cụ). Migration 0014, 0015 (đóng lượt chạy workflow khi việc xong).
- Skill `enterprise-os-guide` cho Mai/ks; `scripts/issue_user_token.sh`.
- Tài liệu: `docs/13` (kiểm kê, luồng chuẩn), `docs/14` (so sánh kế hoạch, đề xuất), `prompts/50` (prompt tổng hợp báo cáo); cập nhật `prompts/00-MASTER.md`.

## [0.2.1] — 2026-10-23

### Đổi
- **Logo mới**: ô tổ ong (Tổ Ong) có người và AI agent (tia sáng) cạnh nhau, dấu duyệt đỏ son ở góc. Component `Logo.jsx`, bản vector `web/public/logo.svg`, favicon SVG, bộ icon PNG (192, 512, apple-touch, maskable).
- Tên hiển thị của giao diện: **Enterprise OS | AI agent and Human collab platform** (thay "Dẹo Work"): tiêu đề trang, thanh bên, màn đăng nhập, manifest cài đặt ứng dụng.

### Thêm
- **"Phải duyệt" trong cửa sổ Giao việc**: ô "Duyệt kết quả" có hai lựa chọn: *Không cần duyệt (nộp là xong)* và *Phải duyệt (chờ duyệt, được duyệt mới hoàn thành)*; chọn phải duyệt thì chọn "Ai duyệt". Mỗi công ty có sẵn ba quy trình: **Người giao duyệt**, **Trưởng phòng duyệt**, **Quản trị công ty duyệt** (tạo tự động, không cần quản trị dựng trước). Trước đó ô này chỉ có "Không cần duyệt" vì công ty chưa có quy trình nào.
- Bước duyệt mới **"Người giao việc"** (`approver_kind = 'creator'`, cũng chọn được khi tạo quy trình tùy biến). Người nộp không tự duyệt: khi người giao cũng là người làm thì trưởng phòng (hoặc quản trị nếu phòng chưa có trưởng phòng) duyệt thay.
- **Trạng thái duyệt của việc** `work.tasks.approval_status`: `none` · `pending` (chờ duyệt) · `approved` (đã duyệt) · `rejected` (bị trả lại). Hiện ở ngăn chi tiết ("Duyệt: …· chờ duyệt / đã duyệt / bị trả lại").
- **Ràng buộc ở CSDL**: việc gắn quy trình chỉ chuyển sang Xong khi `approval_status = 'approved'` (trigger `tasks_need_approval`), kể cả khi ai đó cập nhật trực tiếp. Không đổi quy trình khi việc đang chờ duyệt hoặc đã xong.
- Migration `0010`.

### Sửa
- **Việc đứng yên sau khi người trả lời agent** (T-37): agent chạy lại rồi chặn lần nữa (ở đây vì người phụ trách chưa thiết lập thư mục Drive nên không lưu được .docx), nhưng sự kiện bị bỏ qua nên Dẹo Work không hiện câu hỏi/lý do mới và việc cứ "Đang làm". Hai lỗi chồng nhau: khóa sự kiện của cầu nối trùng khóa lượt trước (nay có `epoch` tăng mỗi lần gửi câu trả lời), và thẻ vẫn ở trạng thái "chặn" sau khi trả lời nên lần chặn kế tiếp bị coi là "không đổi" (nay thẻ chuyển "đang chạy" ngay khi trả lời). Migration `0013`; test CSDL và test cầu nối.
- **Thư mục Drive đã khai báo nhưng chưa kiểm tra (`pending`) không dùng được** (T-37): chưa có tiến trình nào chuyển trạng thái sang `ok`, nên mọi agent lưu tệp cho người đó đều bị chặn mãi. Nay các công cụ lưu Drive (`eos_save_to_drive`, `eos_draft_document`, `eos_project_save_report`) chấp nhận `pending`, và nếu agent không ghi được (403/404) thì báo rõ: chia sẻ thư mục quyền Người chỉnh sửa cho tài khoản agent. Chỉ `none` (chưa khai báo) và `error` bị chặn.
- Cửa sổ Giao việc cảnh báo khi giao agent cho người chưa thiết lập thư mục Drive.
- **Việc đã Xong nhưng không có kết quả / không có nút mở kết quả** (T-37): người dùng bấm "Nộp kết quả" ngay lúc agent đang hỏi lại, việc bị đóng không có kết quả nào và agent bị bỏ rơi. Nay: (1) việc đang giao cho agent **không còn nút nộp** (người trả lời agent, chờ agent nộp, hoặc bỏ giao agent ở Sửa); CSDL cũng chặn; (2) nộp việc phải kèm **tóm tắt kết quả hoặc tài liệu/link**; (3) ngăn chi tiết việc đã xong/chờ duyệt có khối **Kết quả**: tóm tắt và các nút **"Mở: <tên tệp>"** cho mọi tài liệu, link và tệp báo cáo; không có kết quả thì nói rõ. Migration `0012`.
- Ngăn chi tiết: lời của agent không còn hiện là "Người dùng"; bỏ dòng "chạy trên agent:…".
- **Kết quả của agent không nhìn thấy được**: danh mục hồ sơ (`doc.records`) không có màn hình nào, và kết quả/tóm tắt của việc đã xong chỉ nằm trong phần trao đổi. Nay có hộp **Kết quả** ở thẻ dự án (nút "Xem kết quả"): tổng quan và kết quả từng việc của lần chạy, danh mục hồ sơ theo nhóm (số hiệu, ngày, giá trị, link tệp nguồn), báo cáo và tài liệu agent lưu, kho tri thức; ngăn chi tiết việc có mục **Kết quả** khi việc đã xong hoặc chờ duyệt. Migration `0011` (`agent.app_project_results`).
- `agent.mcp_submit` (nộp qua MCP của người) với việc có quy trình trước đây đặt Chờ duyệt mà **không mở yêu cầu duyệt**, nên không ai duyệt được; nay đi qua cùng động cơ duyệt (`agent._approval_start`).

## [0.2.0] — 2026-10-22

### Thêm
- **Quy trình nạp hồ sơ dự án** (`docs/12`): từ một thư mục Drive, hệ thống lập dự án, giao việc gốc cho Điều phối, **điều phối chia việc cho các agent theo kỹ năng và ghi phạm vi (`scope`) từng việc vào CSDL** (`agent.task_scopes`), người theo dõi (người thật) phụ trách và duyệt. Màn hình Dự án có **Nạp hồ sơ dự án**, thẻ dự án hiện tiến độ lần chạy, ngăn chi tiết việc hiện phạm vi.
- Agent kiểu **runner** (`agent.agents.executor`): dịch vụ trên Z2 tự nhận việc qua MCP (không qua hộp thư đi/Kanban), chạy pipeline `deo-sync` (tải, Markdown + OCR, mục lục), đẩy Markdown lên Drive, đăng ký tệp, hỏi người nạp WeKnora. `runner/eos_z2_runner.py`, `deploy/eos-z2-runner.service`, `scripts/issue_runner_token.sh`.
- Công cụ MCP: `eos_project_scope`, `eos_project_files`, `eos_project_read` (đọc Markdown trong đúng thư mục của lần chạy, kiểm theo CSDL), `eos_catalog_upsert` (danh mục hồ sơ `doc.records`), `eos_project_save_report`, `eos_runner_claim/report/setup`; `eos_delegate` nhận `scope`. Phạm vi mã `project` và `runner` (chỉ mã agent).
- **Agent Hermes nạp kho tri thức WeKnora**: công cụ MCP `eos_kb_ingest` (phạm vi mã `ingest`, chỉ agent module kb, chỉ trong việc `stage=kb_ingest` giao đúng agent đó). Máy chủ MCP trên vps169 giữ khóa WeKnora (`WEKNORA_BASE_URL`, `WEKNORA_API_KEY` trong `mcp/.env`), tạo KB của dự án nếu chưa có (sao chép cấu hình từ KB mẫu), nạp tối đa 20 tệp Markdown/lần qua `knowledge/manual`, bỏ mục lục và tệp đã nạp, ghi `kb.sources`. Hermes trên vps173 không thấy khóa (`DEO-INGEST-RULE` vẫn đúng). Migration `0009`.
- Skill Hermes: `dieu-phoi-du-an`, `ho-so-danh-muc` (Văn thư), `ra-soat-phap-che`, `kb-quan-tri-du-lieu`; `deploy/setup_project_workflow.sql`.
- Migration `0008`; bảng `agent.workflows`, `workflow_runs`, `task_scopes` (111 bảng). `make test-runner`; nghiệm thu **A9** (runner Z2 nhận việc qua MCP, chặn và hỏi người khi gặp giai đoạn lạ); `make audit` kiểm mã runner chỉ có phạm vi `runner` và mã người không có phạm vi dành riêng cho agent.

### Sửa
- `scripts/install_skill.sh`: bản skill cũ được sao lưu **ngoài** cây skills (`<profile>/skill-backups/`). Trước đó để `.bak.<giờ>` cạnh skill nên Hermes thấy hai skill trùng tên và mọi thẻ Kanban của profile hỏng (`kanban_skills_unavailable`), phát hiện ở lần chạy thật đầu tiên.

### Đổi
- `agent.delegate`: việc con trong một lần chạy bắt buộc có `scope`. Trả lời câu hỏi của thẻ runner đưa thẻ về sẵn sàng (không gửi lệnh sang cầu nối Hermes). Huỷ việc của runner không tạo lệnh hủy cho cầu nối.
- Mã agent hiện có được cấp thêm phạm vi `project` (migration 0008, không cần đổi mã trong profile).

### Hạn chế
- `phap-che` chưa có profile Hermes; trợ lý Mai chưa được nối; xem `docs/12`.

## [0.1.0] — 2026-10-22

### Thêm
- **Dẹo Work trên lược đồ 108 bảng** (`docs/10`): đưa giao diện quản lý dự án và công việc cũ (`legacy/deo-work`, React + HeroUI + Tailwind, chế độ tối, di động) lên Tổ Ong, chạy ở `/app`. Màn hình Hôm nay, Việc (danh sách và Kanban, lọc, tìm, ngăn chi tiết, việc con, link Drive), Duyệt (con dấu, nhiều bước), Báo cáo, Quản trị (thành viên, mã mời, phòng ban, quy trình duyệt, dự án), Tài khoản (thư mục Drive, Kết nối AI, giao diện sáng/tối). Trang agent cũ được gộp: **Kết nối AI** nằm ở Tài khoản; **Agent và MCP** (cầu nối, agent, mã MCP, nhật ký gọi) là tab trong Quản trị cho người quản trị hệ thống; kết quả agent nộp hiện trong Duyệt và ngăn chi tiết (chấp nhận hoặc trả lại).
- **Mã mời** như thiết kế cũ: link mời hoặc nhập mã sau khi đăng nhập Google; mã gắn vai trò, phòng ban, email, số lượt, hạn; trưởng phòng chỉ mời thành viên vào phòng mình.
- **Vai trò mẫu và quyền** (`owner`, `admin`, `member`; trưởng phòng = `is_dept_head`) và **động cơ duyệt nhiều bước** (1–6 bước: trưởng phòng, quản trị, chủ sở hữu, người cụ thể) trên `core.approval_*`; `agent.accept_result` nay mở yêu cầu duyệt khi việc của agent có quy trình (trước đó trả `to_approval` mà không làm gì).
- Migration `0006` và `0007` (dự án), `db/61_app.sql`: hàm `agent.app_*` (jsonb vào, jsonb ra, kiểm quyền trong hàm), `core.invites.dept_head`, gán vai trò cho thành viên hiện có.
- **Tab Dự án** trong thanh điều hướng: danh sách dự án kèm tiến độ; thêm, cài đặt (mô tả, trạng thái, người quản lý, ngày, Drive), thành viên dự án và xóa dự án. Bỏ tab Dự án trong Quản trị. Migration `0007` (`app_project_save` mở rộng, `app_project_member_set/remove`, `app_project_delete`, `_can_manage_project`).
- `make ui` dựng giao diện; CI kiểm bản dựng `web/public` khớp mã nguồn `web/ui`.

### Đổi
- Máy chủ web (`web/src`) viết lại thành API JSON bảng trắng + phục vụ giao diện React dựng sẵn; bỏ trang HTML dựng ở máy chủ. Đăng nhập Google nay chuyển về màn đăng nhập của ứng dụng (`#/login?e=…`) thay vì trang HTML riêng. Phông chữ tự lưu.
- CSP: `style-src` thêm `'unsafe-inline'` (thư viện giao diện đặt `style` theo phần tử); `script-src` vẫn chỉ `'self'`. `make audit` báo cảnh báo; A8 kiểm script-src chặt.
- Thu hồi quyền `web_svc` với `web_login`, `web_me`, `web_create_task`, `web_task`, `web_cancel_task`, `mcp_my_tasks`, `mcp_my_day`, `mcp_comment`, `accept_result`, `reject_result` (thay bằng `app_*`; hàm cũ còn trong CSDL).
- Cấu hình web: `API_RATE_PER_MIN` (mặc định 600/phút/người) thay `WRITE_RATE_PER_MIN`; thêm `AGENT_DRIVE_EMAIL`, `MCP_URL`.

### Sửa
- Caddy: gốc `work.enterpriseos.bond/` chuyển sang `/app/` (trước đó chỉ trả chữ "Enterprise OS"); sửa cú pháp `redir` thiếu `*` làm `/app` và `/` không chuyển hướng; đường lạ trả 404. A8 kiểm các chuyển hướng này.

### Hạn chế
- Chưa có tiến trình kiểm tra thư mục Drive của người dùng (trạng thái chỉ dừng ở "đã lưu"); xem `docs/10`.

## [Chưa phát hành]

## [0.0.5] — 2026-10-20

### Thêm
- **Giao diện web `/app`** (`web/`, `docs/10`): hộp việc, tạo việc giao agent, duyệt kết quả agent (chấp nhận hoặc trả lại có lý do), trả lời câu hỏi của agent, kết nối AI (cấp/thu hồi mã MCP), quản trị (agent, cầu nối, mã MCP, nhật ký gọi MCP). Đăng nhập Google chỉ cho người đã có trong `core.users`; phiên cookie ký HMAC; CSRF; CSP chặt; giới hạn tốc độ. Web chỉ gọi hàm `SECURITY DEFINER` qua vai trò `web_svc`. `deploy/eos-web.service`, `deploy/eos-web.env.example`, `deploy/Caddyfile.web.snippet`; `make test-web` (24 bước, Google giả lập kèm kiểm PKCE) và kịch bản nghiệm thu A8.
- Migration `0005`: vai trò `web_svc`, hàm `agent.web_*`.
- `make audit` (`scripts/security_audit.sh`): kiểm toán bảo mật chỉ đọc theo checklist `docs/06`, nay gồm cả giao diện web và quyền hàm CSDL; `scripts/security_accepted.txt` ghi rủi ro đã được chủ sở hữu chấp nhận (ngày, người, lý do).
- `make restore-drill` (`scripts/restore_drill.sh`): diễn tập khôi phục tự động, giải mã trên vps169 (mật khẩu sao lưu không rời máy), đối chiếu số bảng, số dòng, hàm và trigger với CSDL thật.

### Sửa
- **Quyền hàm schema `agent`**: `REVOKE ALL … FROM PUBLIC` ở giữa `db/60_agent.sql` bỏ sót các hàm tạo sau đó (từ v0.0.0: `mcp_*`, `delegate`, `mcp_token_issue_agent`; thêm các hàm ở migration 0001-0004), nên `agent_bridge` gọi được cả những hàm đó. Migration `0005` thu hồi lại cho toàn schema; `test_agent.sql` khẳng định không hàm nào cho PUBLIC chạy và cầu nối chỉ gọi 4 hàm.
- `docs/06`: checklist ghi trạng thái thật, liên kết tới kiểm tra tự động; thêm mục giao diện web, lưu ý cổng 8644 và Caddy thiếu `rate_limit`.
- `web_task` trả đủ báo cáo của agent (độ tin cậy, rủi ro còn lại, việc tiếp theo, kiểm tra, nguồn) cho màn hình duyệt.

## [0.0.4] — 2026-10-20

### Thêm
- **Văn thư AI soạn dự thảo công văn và quyết định theo NĐ 30** (`docs/09`): skill Hermes `nd30-van-thu` (`deploy/hermes-skills/`), công cụ MCP `eos_draft_document` (dựng `.docx` ở máy chủ, lưu Drive người phụ trách, gắn vào việc), phạm vi mã `draft` chỉ cho agent module `doc`, hàm SQL `mcp_agent_drive_target` và `mcp_agent_register_file`, migration `0003`. Phụ thuộc mới `docx@9.9.0` (ghim, không script cài đặt). `scripts/install_skill.sh`.
- Kiểm thử: `mcp/test/vanban.test.mjs` kiểm thông số thể thức trên XML của tệp (12 bài) và 5 bước e2e mới; ví dụ của skill được kiểm hợp lệ.

### Sửa
- `setup_agents.sql`: agent `van-thu` nạp skill `nd30-van-thu`.
- **Nhật ký ghi nhầm người thay vì agent** (phát hiện bởi A7): `agent._mcp_actor()` trả `agent:<mã>` khi lời gọi đến từ agent (migration `0004`); trước đó tệp do Văn thư AI soạn gắn vào việc với actor `user:<người phụ trách>`. Có kiểm thử.
- Nhật ký gọi MCP của `eos_draft_document` ghi thêm `cap_ky`, `ngay_dien`, `du_thao` (không ghi nội dung).
- Nghiệm thu: kịch bản **A7** (Văn thư soạn công văn đủ thông tin; thiếu thông tin thì hỏi, không bịa, không tạo tệp).

## [0.0.3] — 2026-10-20

### Thêm
- Kịch bản nghiệm thu **A6 Chia việc con** (`make acceptance`).

### Sửa
- **Báo cáo bị từ chối khi `confidence` do LLM điền sai dạng** (phát hiện bởi A6; worker nộp `1` và `high`): migration `0002` thêm `agent._norm_confidence` và trigger `reports_norm_confidence` chuẩn hóa về `cao|trung_binh|thap` (giá trị lạ → NULL). Trước đó `ingest_event` lỗi 23514, cầu nối thử lại vô hạn và việc không bao giờ Xong. Nội dung thẻ nêu rõ giá trị hợp lệ. Có kiểm thử trong `db/test_agent.sql`.
- `docs/05`: lệnh `unblock` thủ công đặt `--board` đúng chỗ; thêm 3 dòng xử lý sự cố mới.
- `scripts/acceptance.sh`: một kết nối SSH dùng chung (`ControlMaster`) và `dbq` tự thử lại khi `ssh` trả 255 (một cổng chập chờn ở lượt đầy đủ đầu tiên); lượt đầy đủ sau đó 43/44, riêng cổng chập chờn đạt ở lượt chạy lại.

## [0.0.2] — 2026-10-20

### Thêm
- **Nghiệm thu tự động trên máy thật** (`make acceptance`, `scripts/acceptance.sh`, `scripts/acceptance/mcp.mjs`): 5 kịch bản (vòng đời, quyền MCP, làm lại, hủy việc, chịu lỗi), tự dọn dữ liệu thử; hướng dẫn ở `docs/03` §7.1.
- Thư mục `db/migrations/` với migration đầu tiên `0001_cancel_outbox.sql` (bảng ghi phiên bản `core.schema_migrations` đi cùng 0.1.0).

### Sửa
- **Hủy việc không dừng thẻ Kanban** (phát hiện bởi kịch bản A4): thêm trigger `agent.tasks_cancel` phát `agent.outbox` kind=`cancel` (thẻ đã chạy) hoặc hủy lệnh `dispatch` chờ (thẻ chưa tạo). Có kiểm thử trong `db/test_agent.sql`; đã áp lên CSDL thật bằng migration 0001.

## [0.0.1] — 2026-10-20

Triển khai lần đầu lên máy thật (Z2, VPS 169, VPS 173) và nghiệm thu đầu–cuối.

### Sửa
- **Cầu nối ↔ Hermes thật** (`bridge/`, nhánh `fix/real-hermes`; kiểm chứng trên Hermes 0.22.1, `docs/07`): `--board` đứng trước động từ; tự tạo board khi chưa có; đọc `show --json` đúng chỗ (`task.status`, `latest_summary`, `runs[-1].metadata`, `events[blocked].payload.reason`); đối soát không dùng `updated_at`; thêm `plugin.yaml` cho plugin; `fake_hermes.py` khớp dạng thật; thêm `bridge/test/test_fixtures.py` + mẫu thật `bridge/test/fixtures/`. Hook `claimed` không bắn từ profile `eos-*` (chạy ở dispatcher của profile `default`): bù bằng đối soát 60 s (`docs/07` A13). Cầu nối phát `claimed` ngầm một lần trước `blocked`/`completed` để việc luôn qua Đang làm; unit đặt `PYTHONUNBUFFERED=1` (nhật ký không bị đệm).
- `deploy/setup_agents.sql`: agent `thu-thu` đổi thành `quan-tri-du-lieu` (profile `eos-quan-tri-du-lieu`, module `kb`); thêm `phap-che` giữ chỗ (`specialist`, module `doc` tạm vì cột `module` không cho để trống, `max_level` 0, tắt) cho đến khi được định nghĩa. Cập nhật tài liệu và prompt liên quan. Dữ liệu giả của bộ kiểm thử cầu nối vẫn dùng `thu-thu` (chỉ là mẫu).

### Thêm
- Kiểm chứng toàn bộ giả định Hermes Kanban trên Hermes 0.22.1 (`docs/07`); nghiệm thu: giao việc → thẻ → hỏi lại → trả lời → báo xong → chấp nhận; ghi Drive thật; khôi phục sao lưu thử (108 bảng).

## [0.0.0] — 2026-10-19

Bản nền đầu tiên: lược đồ, lớp AI agent, máy chủ MCP, cầu nối Kanban, tài liệu. **Chưa chạy trên máy thật.**
Dự án đặt tên Tổ Ong (eos-hive), tách ra từ chuỗi thiết kế PA1 → Dẹo Việc → Dẹo Work → Enterprise OS.

### Thêm
- **CSDL** (`db/`, PostgreSQL 16): 108 bảng, 5 view, 7 schema — `core` (tổ chức, người, quyền, duyệt nhiều cấp, tệp, nhật ký), `work` (việc, việc con, bình luận), `doc` (công văn đến–đi theo NĐ 30, kho hồ sơ), `hr` (chấm công, đơn từ, phép, lương, KPI), `crm` (khung), `kb` (Kho dữ liệu chung, ánh xạ WeKnora), `agent` (lớp AI agent).
- **Lớp AI agent** (`db/60_agent.sql`, 15 bảng): danh mục agent (điều phối, phân hệ, chuyên môn), mức tự chủ L0–L3 cho 19 hành động, xác nhận L2 (hết hạn sau 3 ngày), thẻ Kanban, hộp thư đi, sự kiện chống trùng, báo cáo hoàn thành có hợp đồng, làm lại tối đa 2 lần, chia việc (tối đa 8 việc con, 2 tầng, có thứ tự, thẻ tổng hợp), mã MCP, nhật ký MCP, ghi Drive.
- **Máy chủ MCP** (`mcp/`, Node 22): Streamable HTTP không trạng thái; 15 công cụ cho agent cá nhân, 3 công cụ cho worker agent; 6 chủ đề hướng dẫn; 2 lời nhắc. Mã `eos_` + 48 hex, chỉ lưu băm SHA-256, hạn ≤ 365 ngày, ≤ 5 mã/người, giới hạn 120 lần/phút.
- **Cầu nối Hermes Kanban** (`bridge/`, Python 3): hộp thư đi → `hermes kanban`; hook → `agent.ingest_event`; đối soát 10 phút. Kèm plugin Hermes `eos_bridge`.
- **Triển khai** (`deploy/`): đơn vị systemd cho MCP và cầu nối, mẫu biến môi trường, đoạn Caddy, `setup_agents.sql` (4 agent: Điều phối, Văn thư, Nhân sự, Quản trị dữ liệu; kèm Pháp chế giữ chỗ, tắt), `mint_bridge_jwt.py`.
- **Kiểm thử**: `test_schema.sql`, `test_agent.sql`, MCP đầu–cuối 16 bước (Drive giả lập), cầu nối 7 bước (PostgREST thật, Hermes giả lập). Script chạy được trên máy bất kỳ có Postgres (`scripts/`), kèm CI GitHub Actions.
- **Tài liệu** (`docs/`): tổng quan, kiến trúc, hướng dẫn phát triển, sổ tay vận hành, hướng dẫn sử dụng theo vai trò, xử lý sự cố, bảo mật, các giả định cần kiểm chứng. Gói prompt triển khai cho Claude Code (`prompts/`).
- **Tham chiếu cũ** (`legacy/`): web app Dẹo Work và PWA Dẹo Việc, viết cho lược đồ `work` đời PA1; chưa chuyển sang lược đồ 108 bảng.

### Đã biết còn thiếu (không phải lỗi, là chưa làm)
- Chưa có RPC cho app web, chính sách RLS, dữ liệu khởi tạo (giai đoạn 1). Chưa có màn hình web cho hộp việc của agent.
- Chưa có OAuth cho MCP: chỉ dùng mã Bearer, nên chưa nối được Claude.ai / ChatGPT bản web.
- Chưa có công cụ MCP hỏi Kho dữ liệu chung (cần API WeKnora). `agent.routing_rules` và `agent.routines` mới có bảng, chưa có bộ kích hoạt.
- **Cầu nối chưa thử với Hermes thật.** Dạng JSON của `hermes kanban show --json`, tham số hook và cách cài plugin là giả định — xem `docs/07-gia-dinh-can-kiem-chung.md`.
- Phân vùng `core.audit_log` chỉ có 2026 và 2027, không có phân vùng mặc định: từ 01/01/2028 ghi nhật ký sẽ lỗi nếu chưa tạo (docs/03 §4.1).
- Số liệu thuế, bảo hiểm trong `hr.payroll_settings` phải do kế toán nhập theo quy định hiện hành.
