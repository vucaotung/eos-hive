-- Dữ liệu thử cho web (chạy một lần trên CSDL vừa dựng). Các trạng thái được tạo bằng chính hàm thật (outbox_ack, ingest_event), không chèn tay.
\set ON_ERROR_STOP 1
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='eos_web') THEN CREATE ROLE eos_web LOGIN PASSWORD 'test-only' IN ROLE web_svc; END IF; END $$;
INSERT INTO core.companies (id, slug, name) VALUES ('33333333-3333-3333-3333-333333333333','demo','Công ty Demo'), ('44444444-4444-4444-4444-444444444444','khac','Công ty Khác');
INSERT INTO core.departments (id, company_id, code, name) VALUES ('dddddddd-0000-0000-0000-0000000000d1','33333333-3333-3333-3333-333333333333','HC','Hành chính'),
 ('dddddddd-0000-0000-0000-0000000000d2','44444444-4444-4444-4444-444444444444','KT','Kỹ thuật');
INSERT INTO core.users (id, email, name, kind, active, is_system_admin) VALUES
 ('cccccccc-0000-0000-0000-000000000001','minh@demo.vn','Trần Minh','person',true,false),
 ('cccccccc-0000-0000-0000-000000000002','admin@demo.vn','Quản Trị','person',true,true),
 ('cccccccc-0000-0000-0000-000000000003','khach@khac.vn','Khách Công Ty Khác','person',true,false),
 ('cccccccc-0000-0000-0000-000000000004','khoa@demo.vn','Người Bị Khóa','person',false,false),
 ('cccccccc-0000-0000-0000-0000000000a2','van-thu@agent','Văn thư AI','agent',true,false);
INSERT INTO core.memberships (user_id, company_id, department_id) VALUES
 ('cccccccc-0000-0000-0000-000000000001','33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1'),
 ('cccccccc-0000-0000-0000-000000000002','33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1'),
 ('cccccccc-0000-0000-0000-000000000003','44444444-4444-4444-4444-444444444444','dddddddd-0000-0000-0000-0000000000d2');
INSERT INTO core.departments (id, company_id, code, name) VALUES ('dddddddd-0000-0000-0000-0000000000d3','33333333-3333-3333-3333-333333333333','KT','Kế toán');
INSERT INTO core.users (id, email, name, kind, active, is_system_admin) VALUES
 ('cccccccc-0000-0000-0000-000000000005','truongphong@demo.vn','Lê Trưởng Phòng','person',true,false),
 ('cccccccc-0000-0000-0000-000000000006','ketoan@demo.vn','Phạm Kế Toán','person',true,false);
INSERT INTO core.memberships (user_id, company_id, department_id, is_dept_head) VALUES
 ('cccccccc-0000-0000-0000-000000000005','33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1', true),
 ('cccccccc-0000-0000-0000-000000000006','33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d3', false);
INSERT INTO core.user_roles (company_id, user_id, role_id)
SELECT m.company_id, m.user_id, agent._sys_role(CASE WHEN u.id = 'cccccccc-0000-0000-0000-000000000002' THEN 'owner' ELSE 'member' END)
  FROM core.memberships m JOIN core.users u ON u.id = m.user_id;
INSERT INTO core.users (id, email, name, kind) VALUES ('cccccccc-0000-0000-0000-0000000000a3','dieu-phoi@agent','Điều phối AI','agent');
INSERT INTO agent.agents (id, user_id, code, name, kind, module, hermes_profile, can_delegate) VALUES ('a2222222-0000-0000-0000-000000000003','cccccccc-0000-0000-0000-0000000000a3','dieu-phoi','Điều phối AI','orchestrator','work','eos-dieu-phoi',true);
INSERT INTO agent.agents (id, user_id, code, name, kind, module, hermes_profile, description) VALUES
 ('a2222222-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-0000000000a2','van-thu','Văn thư AI','module','doc','eos-van-thu','Soạn dự thảo công văn');
INSERT INTO agent.company_settings (company_id, enabled, kanban_board) VALUES ('33333333-3333-3333-3333-333333333333', true, 'eos-demo');
INSERT INTO agent.company_agents (company_id, agent_id) VALUES ('33333333-3333-3333-3333-333333333333','a2222222-0000-0000-0000-000000000002'), ('33333333-3333-3333-3333-333333333333','a2222222-0000-0000-0000-000000000003');

-- 601, 602: agent đã nộp kết quả (chờ duyệt) · 603: agent đang hỏi · 604: việc thường quá hạn · 605: việc của công ty khác
INSERT INTO work.tasks (id, company_id, department_id, title, description, assignee_id, agent_id, created_by) OVERRIDING SYSTEM VALUE VALUES
 (601,'33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1','Soạn công văn đề nghị cung cấp hồ sơ','Gửi Công ty ABC','cccccccc-0000-0000-0000-000000000001','a2222222-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-000000000001'),
 (602,'33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1','Soạn quyết định thành lập tổ','Tổ công tác','cccccccc-0000-0000-0000-000000000001','a2222222-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-000000000001'),
 (603,'33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1','Soạn thông báo nghỉ lễ','Chưa nói rõ ngày','cccccccc-0000-0000-0000-000000000001','a2222222-0000-0000-0000-000000000002','cccccccc-0000-0000-0000-000000000001');
SELECT agent.outbox_ack((SELECT id FROM agent.outbox WHERE task_id = t AND kind = 'dispatch'), 't_w' || t) FROM unnest(ARRAY[601,602,603]) t;
SELECT agent.ingest_event('eos-demo', 't_w' || t, 'claimed', 'k-claim-' || t) FROM unnest(ARRAY[601,602,603]) t;
SELECT agent.ingest_event('eos-demo','t_w601','completed','k-done-601','{"summary":"Đã soạn xong dự thảo công văn gửi Công ty ABC, chưa cấp số, chưa ký.","confidence":"cao","residual_risk":"Chưa rõ người ký","next_actions":"Người ký xem lại, cấp số, điền ngày","checks":["Đúng thể thức NĐ30"],"sources":["T-601"],"outputs":[{"drive_id":"D601","name":"Du thao - Cong van.docx","url":"https://drive.google.com/file/d/D601/view"}]}'::jsonb);
SELECT agent.ingest_event('eos-demo','t_w602','completed','k-done-602','{"summary":"Báo cáo thử có liên kết độc hại và HTML.","confidence":"high","outputs":[{"name":"<b>độc hại</b>","url":"javascript:alert(1)"},{"name":"Tệp thật","url":"https://drive.google.com/file/d/D602/view"}]}'::jsonb);
SELECT agent.ingest_event('eos-demo','t_w603','blocked','k-block-603','{"reason":"Nghỉ lễ từ ngày nào đến ngày nào? <script>alert(1)</script>"}'::jsonb);
INSERT INTO work.tasks (id, company_id, department_id, title, description, assignee_id, created_by, due_date) OVERRIDING SYSTEM VALUE VALUES
 (604,'33333333-3333-3333-3333-333333333333','dddddddd-0000-0000-0000-0000000000d1','Việc thường đã quá hạn','','cccccccc-0000-0000-0000-000000000001','cccccccc-0000-0000-0000-000000000001', current_date - 3),
 (605,'44444444-4444-4444-4444-444444444444','dddddddd-0000-0000-0000-0000000000d2','Việc bí mật của công ty khác','Không được lộ','cccccccc-0000-0000-0000-000000000003','cccccccc-0000-0000-0000-000000000003', NULL);
