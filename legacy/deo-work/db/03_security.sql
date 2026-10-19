-- Vai trò, quyền, RLS, view báo cáo.
-- Mật khẩu truyền vào bằng psql -v authenticator_pw=... -v auth_svc_pw=...
SET search_path = app, public;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticator') THEN CREATE ROLE authenticator LOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon')          THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user')      THEN CREATE ROLE app_user NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'agent')         THEN CREATE ROLE agent NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auth_svc')      THEN CREATE ROLE auth_svc LOGIN; END IF;
END $$;
ALTER ROLE authenticator PASSWORD :'authenticator_pw';
ALTER ROLE auth_svc PASSWORD :'auth_svc_pw';
GRANT anon, app_user, agent TO authenticator;

REVOKE ALL ON SCHEMA app FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA app FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA app REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
GRANT USAGE ON SCHEMA app TO app_user, agent, auth_svc;

-- ===== Đăng nhập =====
GRANT EXECUTE ON FUNCTION auth_login(text,text,text,text,text), auth_check(uuid) TO auth_svc;

-- ===== Đọc =====
GRANT SELECT ON companies, departments, memberships, projects, approval_flows, approval_steps,
                tasks, approvals, comments, task_links, drive_files TO app_user, agent;
GRANT SELECT (id, email, name, avatar_url, drive_status, drive_folder_url, active) ON users TO app_user;
GRANT SELECT ON users TO agent;
GRANT SELECT ON invites TO app_user;
GRANT SELECT ON task_events TO app_user, agent;

-- Hàm ngữ cảnh dùng trong policy
GRANT EXECUTE ON FUNCTION jwt_claim(text), uid(), actor(), is_agent(), my_role(uuid), my_dept(uuid), my_companies(),
  can_see(tasks), can_edit(tasks), can_approve(tasks), folder_name(uuid,uuid), my_folder_names() TO app_user, agent;

-- ===== Ghi: chỉ qua hàm =====
GRANT EXECUTE ON FUNCTION me(), set_drive_folder(text),
  create_task(uuid,text,text,uuid,uuid,date,task_priority,uuid,bigint,text,uuid),
  update_task(bigint,jsonb), add_comment(bigint,text,comment_kind), answer_agent(bigint,text),
  add_link(bigint,text,text), remove_link(bigint), submit_task(bigint,text), decide(bigint,boolean,text),
  save_department(uuid,text,text,uuid,boolean), create_invite(uuid,member_role,uuid,text,int,int,text), revoke_invite(text),
  set_member(uuid,uuid,member_role,uuid,text,boolean), save_project(uuid,text,text,uuid,text,uuid,boolean),
  save_flow(uuid,text,jsonb,uuid,uuid), archive_flow(uuid)
  TO app_user;
GRANT EXECUTE ON FUNCTION create_task(uuid,text,text,uuid,uuid,date,task_priority,uuid,bigint,text,uuid),
  update_task(bigint,jsonb), add_comment(bigint,text,comment_kind), add_link(bigint,text,text), submit_task(bigint,text),
  agent_claim(text), agent_ask(bigint,text), agent_drive_queue(), agent_drive_result(uuid,boolean,text), agent_drive_files(uuid,jsonb)
  TO agent;

-- ===== RLS =====
ALTER TABLE companies      ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments    ENABLE ROW LEVEL SECURITY;
ALTER TABLE users          ENABLE ROW LEVEL SECURITY;
ALTER TABLE memberships    ENABLE ROW LEVEL SECURITY;
ALTER TABLE invites        ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects       ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_flows ENABLE ROW LEVEL SECURITY;
ALTER TABLE approval_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks          ENABLE ROW LEVEL SECURITY;
ALTER TABLE approvals      ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments       ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_links     ENABLE ROW LEVEL SECURITY;
ALTER TABLE drive_files    ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_events    ENABLE ROW LEVEL SECURITY;

-- Agent đọc tất cả (ghi vẫn chỉ qua hàm)
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['companies','departments','users','memberships','projects','approval_flows','approval_steps',
                           'tasks','approvals','comments','task_links','drive_files','task_events'] LOOP
    EXECUTE format('CREATE POLICY agent_read ON %I FOR SELECT TO agent USING (true)', t);
  END LOOP;
END $$;

CREATE POLICY p ON companies   FOR SELECT TO app_user USING (id IN (SELECT my_companies()));
CREATE POLICY p ON departments FOR SELECT TO app_user USING (company_id IN (SELECT my_companies()));
CREATE POLICY p ON memberships FOR SELECT TO app_user USING (company_id IN (SELECT my_companies()));
CREATE POLICY p ON projects    FOR SELECT TO app_user USING (company_id IN (SELECT my_companies()));
CREATE POLICY p ON approval_flows FOR SELECT TO app_user USING (company_id IN (SELECT my_companies()));
CREATE POLICY p ON approval_steps FOR SELECT TO app_user
  USING (EXISTS (SELECT 1 FROM approval_flows f WHERE f.id = flow_id AND f.company_id IN (SELECT my_companies())));
-- Người dùng: thấy mình và những người cùng công ty
CREATE POLICY p ON users FOR SELECT TO app_user
  USING (id = uid() OR EXISTS (SELECT 1 FROM memberships m WHERE m.user_id = users.id AND m.company_id IN (SELECT my_companies())));
-- Mã mời: owner/admin thấy của công ty; trưởng phòng thấy mã mình tạo
CREATE POLICY p ON invites FOR SELECT TO app_user
  USING (my_role(company_id) IN ('owner','admin') OR (my_role(company_id) = 'manager' AND created_by = uid()));

CREATE POLICY p ON tasks FOR SELECT TO app_user USING (can_see(tasks));
CREATE POLICY p ON approvals  FOR SELECT TO app_user USING (EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id));
CREATE POLICY p ON comments   FOR SELECT TO app_user USING (EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id));
CREATE POLICY p ON task_links FOR SELECT TO app_user USING (EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id));
CREATE POLICY p ON task_events FOR SELECT TO app_user USING (EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id));
-- Tệp Drive: chủ thư mục thấy hết; người khác chỉ thấy tệp đã gắn vào việc họ xem được
CREATE POLICY p ON drive_files FOR SELECT TO app_user
  USING (owner_user = uid() OR (task_id IS NOT NULL AND EXISTS (SELECT 1 FROM tasks t WHERE t.id = task_id)));

-- ===== View báo cáo (áp dụng RLS của người xem) =====
CREATE VIEW report_departments WITH (security_invoker = true) AS
SELECT t.company_id, t.department_id,
       count(*) FILTER (WHERE t.status NOT IN ('done','cancelled'))                          AS open,
       count(*) FILTER (WHERE t.status = 'in_progress')                                      AS in_progress,
       count(*) FILTER (WHERE t.status = 'blocked')                                          AS blocked,
       count(*) FILTER (WHERE t.status = 'in_review')                                        AS in_review,
       count(*) FILTER (WHERE t.status NOT IN ('done','cancelled') AND t.due_date < current_date) AS overdue,
       count(*) FILTER (WHERE t.status = 'done' AND t.completed_at > now() - interval '30 days')  AS done_30d,
       count(*) FILTER (WHERE t.status = 'done' AND t.completed_at > now() - interval '30 days'
                          AND t.due_date IS NOT NULL AND t.completed_at::date <= t.due_date)   AS done_on_time_30d,
       round(avg(extract(epoch FROM t.completed_at - t.created_at) / 86400)
             FILTER (WHERE t.status = 'done' AND t.completed_at > now() - interval '30 days')::numeric, 1) AS avg_days_30d
  FROM tasks t GROUP BY t.company_id, t.department_id;

CREATE VIEW report_people WITH (security_invoker = true) AS
SELECT t.company_id, t.assignee_id AS user_id,
       count(*) FILTER (WHERE t.status NOT IN ('done','cancelled'))                          AS open,
       count(*) FILTER (WHERE t.status NOT IN ('done','cancelled') AND t.due_date < current_date) AS overdue,
       count(*) FILTER (WHERE t.status = 'done' AND t.completed_at > now() - interval '30 days')  AS done_30d
  FROM tasks t WHERE t.assignee_id IS NOT NULL GROUP BY t.company_id, t.assignee_id;

-- Hộp việc chờ tôi duyệt
CREATE VIEW my_approvals WITH (security_invoker = true) AS
SELECT t.id AS task_id, a.step_no, a.step_name, (SELECT count(*) FROM approvals x WHERE x.task_id = t.id AND x.round = a.round) AS steps
  FROM tasks t JOIN approvals a ON a.task_id = t.id AND a.round = t.attempts + 1 AND a.step_no = t.current_step
 WHERE t.status = 'in_review' AND can_approve(t);

GRANT SELECT ON report_departments, report_people, my_approvals TO app_user, agent;
