\set ON_ERROR_STOP 1
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD 'test-only'; END IF; END $$;
GRANT agent_bridge TO authenticator;
INSERT INTO core.companies (id, slug, name) VALUES ('44444444-4444-4444-4444-444444444444','vlx','Valnex');
INSERT INTO core.departments (id, company_id, code, name) VALUES ('dddddddd-0000-0000-0000-0000000000e1','44444444-4444-4444-4444-444444444444','PC','Pháp chế');
INSERT INTO core.users (id, google_sub, email, name, kind) VALUES
 ('eeeeeeee-1111-0000-0000-000000000001','h1','minh@vlx.vn','Minh','person'),
 ('eeeeeeee-1111-0000-0000-000000000002','h2','lan@vlx.vn','Lan','person'),
 ('eeeeeeee-1111-0000-0000-0000000000a1',NULL,'thu-thu@agent','Thủ thư AI','agent');
INSERT INTO agent.agents (id, user_id, code, name, kind, module, hermes_profile, skills) VALUES
 ('a1111111-0000-0000-0000-000000000001','eeeeeeee-1111-0000-0000-0000000000a1','thu-thu','Thủ thư AI','module','kb','eos-thu-thu','{kb-tra-cuu}');
INSERT INTO agent.company_settings (company_id, enabled, kanban_board) VALUES ('44444444-4444-4444-4444-444444444444', true, 'eos-vlx');
INSERT INTO agent.company_agents (company_id, agent_id) VALUES ('44444444-4444-4444-4444-444444444444','a1111111-0000-0000-0000-000000000001');
INSERT INTO work.tasks (id, company_id, department_id, title, assignee_id, agent_id, agent_role, created_by, due_date)
OVERRIDING SYSTEM VALUE VALUES (7001,'44444444-4444-4444-4444-444444444444','dddddddd-0000-0000-0000-0000000000e1',
 'Tóm tắt điểm mới NQ 29/2026/QH16','eeeeeeee-1111-0000-0000-000000000001','a1111111-0000-0000-0000-000000000001','phap-che','eeeeeeee-1111-0000-0000-000000000002','2026-10-30');
