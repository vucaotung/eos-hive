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
-- việc 504: văn thư đang có thẻ chạy (để thử eos_draft_document)
INSERT INTO work.tasks (id, company_id, department_id, title, assignee_id, agent_id, created_by, due_date)
OVERRIDING SYSTEM VALUE VALUES (504,'33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1','Soạn công văn đề nghị cung cấp hồ sơ năng lực',
  'cccccccc-0000-0000-0000-000000000001','a2222222-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-000000000002','2026-10-30');
SELECT agent.outbox_ack((SELECT id FROM agent.outbox WHERE task_id = 504), 't_demo2');
SELECT agent.ingest_event('eos-demo','t_demo2','claimed','eos-demo:t_demo2:1');
\pset tuples_only on
SELECT set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000001"}', false) \g /dev/null
SELECT 'TOKEN_FULL=' || agent.mcp_token_issue('Claude thử','claude','{read,write,drive,kb}',30);
SELECT 'TOKEN_READ=' || agent.mcp_token_issue('Chỉ đọc','chatgpt','{read}',30);
SELECT set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-000000000003"}', false) \g /dev/null
SELECT 'TOKEN_OTHER=' || agent.mcp_token_issue('Người khác','other','{read,write,drive}',30);
SELECT set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-0000000000ad"}', false) \g /dev/null
SELECT 'TOKEN_AGENT=' || agent.mcp_token_issue_agent('dieu-phoi', 30);
SELECT 'TOKEN_AGENT2=' || agent.mcp_token_issue_agent('van-thu', 30);

-- ---------- Quy trình dự án (db/62_workflow.sql): chủ sở hữu bắt đầu lần chạy, điều phối nhận thẻ gốc, runner có mã riêng ----------
INSERT INTO core.memberships (user_id, company_id, department_id) VALUES ('cccccccc-0000-0000-0000-0000000000ad','33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1');
INSERT INTO core.user_roles (company_id, user_id, role_id) VALUES ('33333333-3333-3333-3333-333333333333','cccccccc-0000-0000-0000-0000000000ad', agent._sys_role('owner'));
INSERT INTO core.users (id, email, name, kind) VALUES ('cccccccc-0000-0000-0000-0000000000a3','runner@agent','Runner hồ sơ Z2','agent');
INSERT INTO agent.agents (id, user_id, code, name, kind, module, hermes_profile, executor) VALUES
 ('a2222222-0000-0000-0000-000000000003','cccccccc-0000-0000-0000-0000000000a3','ho-so-runner','Runner hồ sơ Z2','specialist','kb','z2-runner','runner');
INSERT INTO agent.company_agents (company_id, agent_id) VALUES ('33333333-3333-3333-3333-333333333333','a2222222-0000-0000-0000-000000000003');
SELECT set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-0000000000ad"}', false) \g /dev/null
SELECT agent.app_workflow_start(jsonb_build_object('company_id','33333333-3333-3333-3333-333333333333','project_name','Dự án thử nạp hồ sơ','drive_url','https://drive.google.com/drive/folders/SRCFOLDER0000001',
  'supervisor_id','cccccccc-0000-0000-0000-000000000001')) \g /dev/null
SELECT agent.outbox_ack((SELECT id FROM agent.outbox WHERE task_id = (SELECT root_task FROM agent.workflow_runs LIMIT 1) AND kind = 'dispatch'), 't_root1');
SELECT agent.ingest_event('eos-demo','t_root1','claimed','eos-demo:t_root1:1');
\pset tuples_only on
SELECT 'ROOT_TASK=' || (SELECT root_task FROM agent.workflow_runs LIMIT 1);
SELECT 'TOKEN_RUNNER=' || agent.mcp_token_issue_agent('ho-so-runner', 30);
-- agent kho tri thức: được nạp (phạm vi ingest)
INSERT INTO core.users (id, email, name, kind) VALUES ('cccccccc-0000-0000-0000-0000000000a4','kb@agent','Quản trị dữ liệu AI','agent');
INSERT INTO agent.agents (id, user_id, code, name, kind, module, hermes_profile) VALUES
 ('a2222222-0000-0000-0000-000000000004','cccccccc-0000-0000-0000-0000000000a4','quan-tri-du-lieu','Quản trị dữ liệu AI','module','kb','eos-quan-tri-du-lieu');
INSERT INTO agent.company_agents (company_id, agent_id) VALUES ('33333333-3333-3333-3333-333333333333','a2222222-0000-0000-0000-000000000004');
SELECT 'TOKEN_KB=' || agent.mcp_token_issue_agent('quan-tri-du-lieu', 30);
SELECT set_config('request.jwt.claims','{"sub":"cccccccc-0000-0000-0000-0000000000ad"}', false) \g /dev/null
SELECT 'TOKEN_ADMIN=' || agent.mcp_token_issue('Quản trị đọc ghi','claude','{read,write}',30);
-- Mai (bot nhận yêu cầu): phạm vi mã riêng read + task_create, vai trò tối thiểu tro_ly_ai (giống dữ liệu thật)
INSERT INTO core.users (id, email, name, kind) VALUES ('cccccccc-0000-0000-0000-0000000000a5','mai@agent','Mai - Trợ lý AI','agent');
INSERT INTO agent.agents (id, user_id, code, name, kind, module, hermes_profile, token_scopes) VALUES
 ('a2222222-0000-0000-0000-000000000005','cccccccc-0000-0000-0000-0000000000a5','mai','Mai - Trợ lý AI','specialist','work','team_admin','{read,task_create}');
INSERT INTO agent.company_agents (company_id, agent_id) VALUES ('33333333-3333-3333-3333-333333333333','a2222222-0000-0000-0000-000000000005');
INSERT INTO core.memberships (user_id, company_id) VALUES ('cccccccc-0000-0000-0000-0000000000a5','33333333-3333-3333-3333-333333333333');
INSERT INTO core.user_roles (company_id, user_id, role_id) VALUES ('33333333-3333-3333-3333-333333333333','cccccccc-0000-0000-0000-0000000000a5', agent._sys_role('tro_ly_ai'));
SELECT 'TOKEN_MAI=' || agent.mcp_token_issue_agent('mai', 30);
