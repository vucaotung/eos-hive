-- Thiết lập quy trình nạp hồ sơ dự án cho một công ty (sau migration 0008). Chạy: psql -v company=<uuid> -f setup_project_workflow.sql
-- Idempotent. Gồm: agent runner `ho-so-runner` (dịch vụ trên Z2, không phải Hermes), gán kỹ năng cho các agent hiện có.
-- Agent `phap-che` được gán kỹ năng nhưng CHỈ bật khi profile Hermes eos-phap-che đã tồn tại (docs/12): chạy thêm
--   UPDATE agent.agents SET active = true, max_level = 1 WHERE code = 'phap-che';  rồi cấp mã bằng scripts/issue_agent_token.sh
INSERT INTO core.users (email, name, kind) VALUES ('ho-so-runner@agent.enterpriseos.bond', 'Runner hồ sơ Z2', 'agent') ON CONFLICT DO NOTHING;
INSERT INTO agent.agents (user_id, code, name, kind, module, hermes_profile, skills, max_level, can_delegate, executor, description)
SELECT u.id, 'ho-so-runner', 'Runner hồ sơ Z2', 'specialist', 'kb', 'z2-runner', '{}', 1, false, 'runner',
       'Dịch vụ trên Z2: tải thư mục Drive dự án, chuyển Markdown + OCR, đẩy lên Drive, đăng ký tệp, chuẩn bị nạp kho tri thức (người duyệt bước nạp)'
  FROM core.users u WHERE u.email = 'ho-so-runner@agent.enterpriseos.bond'
ON CONFLICT (code) DO NOTHING;
INSERT INTO agent.company_agents (company_id, agent_id) SELECT :'company', id FROM agent.agents WHERE code = 'ho-so-runner' ON CONFLICT DO NOTHING;
UPDATE agent.agents SET skills = '{dieu-phoi-du-an}'                    WHERE code = 'dieu-phoi';
UPDATE agent.agents SET skills = '{nd30-van-thu,ho-so-danh-muc}'        WHERE code = 'van-thu';
UPDATE agent.agents SET skills = '{kb-quan-tri-du-lieu}'                WHERE code = 'quan-tri-du-lieu';
UPDATE agent.agents SET skills = '{ra-soat-phap-che}', description = 'Rà soát pháp lý hồ sơ dự án: văn bản pháp lý, hợp đồng, mốc hạn, rủi ro (hỗ trợ, không kết luận thay luật sư)' WHERE code = 'phap-che';
