-- Cấu hình luồng nạp văn bản pháp luật cho MỘT công ty (chạy tay, idempotent):
--   psql -v company=<uuid công ty> -v law_folder=<id thư mục Drive pháp luật> -f deploy/setup_law.sql
-- law_folder: thư mục Drive chung chứa bản Markdown văn bản pháp luật; tài khoản Drive của hệ thống (Google refresh token của MCP) phải có quyền "Người chỉnh sửa".
-- KB đích mặc định: phap-luat, tieu-chuan (dùng chung mọi công ty khi mỗi công ty tự trỏ cùng cấu hình). Đổi bằng law_kb_names.
\set ON_ERROR_STOP 1
UPDATE agent.company_settings
   SET law_md_folder_id = :'law_folder', updated_at = now()
 WHERE company_id = :'company'::uuid;
-- Bật phap-che cho công ty (agent phải có profile Hermes eos-phap-che và mã MCP: scripts/issue_agent_token.sh ... phap-che eos-phap-che)
UPDATE agent.agents SET active = true WHERE code = 'phap-che';
INSERT INTO agent.company_agents (company_id, agent_id, enabled)
SELECT :'company'::uuid, id, true FROM agent.agents WHERE code = 'phap-che'
ON CONFLICT (company_id, agent_id) DO UPDATE SET enabled = true;
SELECT law_md_folder_id, law_kb_names FROM agent.company_settings WHERE company_id = :'company'::uuid;
