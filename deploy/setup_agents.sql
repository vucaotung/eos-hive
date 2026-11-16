-- Khởi tạo agent hệ thống cho một công ty. Sửa :company và chạy bằng psql -v company=<uuid> -f setup_agents.sql
-- Tài khoản agent (kind = agent) để nhật ký ghi đúng ai làm.
-- Cột skills: van-thu nạp skill nd30-van-thu (docs/09; CÀI skill vào profile eos-van-thu trước khi giao việc). Các skill khác để TRỐNG có chủ đích: kỹ năng Hermes (kb-tra-cuu, nd30-van-thu, hr-cham-cong, lap-ke-hoach) chưa được viết;
-- khi có, chạy UPDATE agent.agents SET skills = '{ten-skill}' WHERE code = '…' (docs/07 A10).
-- Điều phối dùng profile riêng eos-dieu-phoi, KHÔNG dùng ops-admin (ops-admin có terminal root, docs/06).
INSERT INTO core.users (email, name, kind) VALUES
 ('dieu-phoi@agent.enterpriseos.bond','Điều phối AI','agent'),
 ('van-thu@agent.enterpriseos.bond','Văn thư AI','agent'),
 ('nhan-su@agent.enterpriseos.bond','Nhân sự AI','agent'),
 ('quan-tri-du-lieu@agent.enterpriseos.bond','Quản trị dữ liệu AI','agent'),
 ('phap-che@agent.enterpriseos.bond','Pháp chế AI','agent'),
 ('ks-kinh-te-xd@agent.enterpriseos.bond','Kỹ sư kinh tế xây dựng AI','agent')
ON CONFLICT DO NOTHING;
INSERT INTO agent.agents (user_id, code, name, kind, module, hermes_profile, skills, max_level, can_delegate, description, active)
SELECT u.id, v.code, v.name, v.kind, v.module, v.profile, v.skills, v.lv, v.dlg, v.descr, v.code NOT IN ('phap-che', 'ks-kinh-te-xd')   -- hai agent này tắt cho đến khi profile Hermes và mã MCP sẵn sàng (deploy/setup_law.sql bật phap-che)
  FROM (VALUES
   ('dieu-phoi@agent.enterpriseos.bond','dieu-phoi','Điều phối AI','orchestrator','work','eos-dieu-phoi','{}'::text[],2,true,
    'Nhận yêu cầu, chia việc con cho agent phân hệ, tổng hợp kết quả, bản tin sáng'),
   ('van-thu@agent.enterpriseos.bond','van-thu','Văn thư AI','module','doc','eos-van-thu','{nd30-van-thu}',1,false,
    'Đọc công văn đến, điền nháp sổ, đề xuất người xử lý, soạn công văn đi để trình ký'),
   ('nhan-su@agent.enterpriseos.bond','nhan-su','Nhân sự AI','module','hr','eos-nhan-su','{}',1,false,
    'Rà chấm công bất thường, kiểm đơn với số phép, nháp KPI và bảng lương'),
   ('quan-tri-du-lieu@agent.enterpriseos.bond','quan-tri-du-lieu','Quản trị dữ liệu AI','module','kb','eos-quan-tri-du-lieu','{}',1,false,
    'Quản trị Kho dữ liệu chung: trả lời có trích dẫn, gom câu không tìm thấy, đề xuất trang wiki'),
   ('phap-che@agent.enterpriseos.bond','phap-che','Pháp chế AI','specialist','doc','eos-phap-che','{}',1,false,
    'Rà soát pháp lý hồ sơ; quản lý KB pháp luật theo yêu cầu của chủ sở hữu (nạp văn bản, kiểm hiệu lực, đánh dấu hết hiệu lực; không kết luận thay luật sư)'),
   ('ks-kinh-te-xd@agent.enterpriseos.bond','ks-kinh-te-xd','Kỹ sư kinh tế xây dựng AI','specialist','doc','ks-kinh-te-xd','{}',1,false,
    'Thực hiện 20 bước quản lý dự án đầu tư xây dựng: bảng kiểm từng bước, soạn hồ sơ nháp, kiểm tra hồ sơ, theo dõi tiến độ pháp lý, đề xuất việc; không ký, không nộp, không gửi ra ngoài')
  ) v(email, code, name, kind, module, profile, skills, lv, dlg, descr)
  JOIN core.users u ON lower(u.email) = v.email
ON CONFLICT (code) DO NOTHING;
-- phap-che, ks-kinh-te-xd: chỉ tắt khi MỚI tạo (cột active ở trên); chạy lại script không tắt lại agent đã bật. Bật: phap-che bằng deploy/setup_law.sql; ks-kinh-te-xd bằng
--   UPDATE agent.agents SET active = true WHERE code = 'ks-kinh-te-xd';  (sau khi profile ks-kinh-te-xd có eos_bridge + mã MCP, prompts/60-trien-khai-v06.md)
INSERT INTO agent.company_settings (company_id, enabled, kanban_board)
SELECT id, true, 'eos-' || slug FROM core.companies WHERE id = :'company' ON CONFLICT (company_id) DO NOTHING;
INSERT INTO agent.company_agents (company_id, agent_id)
SELECT :'company', id FROM agent.agents ON CONFLICT DO NOTHING;
-- Đăng nhập dịch vụ: eos_mcp (máy chủ MCP) và cầu nối dùng JWT vai trò agent_bridge qua PostgREST
-- CREATE ROLE eos_mcp LOGIN PASSWORD '<đặt ngoài chat>' IN ROLE mcp_svc;
-- GRANT agent_bridge TO authenticator;   -- và thêm agent vào db-schemas của PostgREST
