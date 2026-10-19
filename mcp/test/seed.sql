-- Dữ liệu thử cho máy chủ MCP (không ROLLBACK). In ra hai mã MCP.
\set ON_ERROR_STOP 1
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='eos_mcp') THEN CREATE ROLE eos_mcp LOGIN PASSWORD 'test-only' IN ROLE mcp_svc; END IF; END $$;
INSERT INTO core.companies (id, slug, name) VALUES ('33333333-3333-3333-3333-333333333333','demo','Công ty Demo');
INSERT INTO core.departments (id, company_id, code, name) VALUES ('dddddddd-0000-0000-0000-0000000000d1','33333333-3333-3333-3333-333333333333','KT','Kỹ thuật');
INSERT INTO core.users (id, google_sub, email, name, drive_folder_id, drive_folder_url, drive_state) VALUES
 ('cccccccc-0000-0000-0000-000000000001','gx','minh@demo.vn','Trần Minh','FOLDER_MINH','https://drive.google.com/drive/folders/FOLDER_MINH','ok'),
 ('cccccccc-0000-0000-0000-000000000002','gy','lan@demo.vn','Lê Lan',NULL,NULL,'none'),
 ('cccccccc-0000-0000-0000-000000000003','gz','khach@demo.vn','Người khác phòng',NULL,NULL,'none');
INSERT INTO core.memberships (user_id, company_id, department_id) VALUES
 ('cccccccc-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1'),
 ('cccccccc-0000-0000-0000-000000000002','33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1'),
 ('cccccccc-0000-0000-0000-000000000003','33333333-3333-3333-3333-333333333333',NULL);
INSERT INTO work.tasks (id, company_id, department_id, title, description, assignee_id, created_by, due_date)
OVERRIDING SYSTEM VALUE VALUES
 (501,'33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1','Lập bảng khối lượng móng','Theo bản vẽ KC-01, xuất bảng Excel','cccccccc-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-000000000002','2026-10-24'),
 (502,'33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1','Họp giao ban tuần','', 'cccccccc-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-000000000002','2026-10-21');
-- agent hệ thống: điều phối (được chia việc) và văn thư; việc 503 đang có thẻ chạy của điều phối
INSERT INTO core.users (id, email, name, kind, is_system_admin) VALUES
 ('cccccccc-0000-0000-0000-0000000000ad','admin@demo.vn','Quản trị','person',true),
 ('cccccccc-0000-0000-0000-0000000000a1','dieu-phoi@agent','Điều phối AI','agent',false),
 ('cccccccc-0000-0000-0000-0000000000a2','van-thu@agent','Văn thư AI','agent',false);
INSERT INTO agent.agents (id, user_id, code, name, kind, module, hermes_profile, can_delegate) VALUES
 ('a2222222-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-0000000000a1','dieu-phoi','Điều phối AI','orchestrator','work','ops-admin',true),
 ('a2222222-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-0000000000a2','van-thu','Văn thư AI','module','doc','eos-van-thu',false);
INSERT INTO agent.company_settings (company_id, enabled, kanban_board) VALUES ('33333333-3333-3333-3333-333333333333', true, 'eos-demo');
INSERT INTO agent.company_agents (company_id, agent_id) VALUES
 ('33333333-3333-3333-3333-333333333333','a2222222-0000-0000-0000-000000000001'),
 ('33333333-3333-3333-3333-333333333333','a2222222-0000-0000-0000-000000000002');
INSERT INTO work.tasks (id, company_id, department_id, title, assignee_id, agent_id, created_by, due_date)
OVERRIDING SYSTEM VALUE VALUES (503,'33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1','Chuẩn bị hồ sơ nghiệm thu móng',
  'cccccccc-0000-0000-0000-000000000001','a2222222-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-000000000002','2026-10-28');
SELECT agent.outbox_ack((SELECT id FROM agent.outbox WHERE task_id = 503), 't_demo1');
SELECT agent.ingest_event('eos-demo','t_demo1','claimed','eos-demo:t_demo1:1');
\pset tuples_only on
SELECT set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000001"}', false) \g /dev/null
SELECT 'TOKEN_FULL=' || agent.mcp_token_issue('Claude thử','claude','{read,write,drive,kb}',30);
SELECT 'TOKEN_READ=' || agent.mcp_token_issue('Chỉ đọc','chatgpt','{read}',30);
SELECT set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000003"}', false) \g /dev/null
SELECT 'TOKEN_OTHER=' || agent.mcp_token_issue('Người khác','other','{read,write,drive}',30);
SELECT set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-0000000000ad"}', false) \g /dev/null
SELECT 'TOKEN_AGENT=' || agent.mcp_token_issue_agent('dieu-phoi', 30);
SELECT 'TOKEN_AGENT2=' || agent.mcp_token_issue_agent('van-thu', 30);
