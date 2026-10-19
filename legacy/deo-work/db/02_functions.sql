-- Hàm nghiệp vụ. Mọi thao tác ghi đi qua các hàm này (SECURITY DEFINER), không ghi bảng trực tiếp.
SET search_path = app, public;
SET check_function_bodies = off;

CREATE FUNCTION fail(msg text, code text DEFAULT 'P0001') RETURNS void LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION '%', msg USING ERRCODE = code; END $$;

CREATE FUNCTION new_invite_code() RETURNS text LANGUAGE plpgsql SET search_path = app, public AS $$
DECLARE v text;
BEGIN
  LOOP
    v := upper(substr(translate(encode(gen_random_bytes(12), 'base64'), '+/=0O1Il', ''), 1, 8));
    EXIT WHEN v ~ '^[A-Z0-9]{8}$' AND NOT EXISTS (SELECT 1 FROM invites WHERE code = v);
  END LOOP;
  RETURN v;
END $$;

CREATE FUNCTION require_role(c uuid, roles member_role[]) RETURNS member_role
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = app, public AS $$
DECLARE r member_role := my_role(c);
BEGIN
  IF r IS NULL THEN PERFORM fail('Bạn không thuộc công ty này', '42501'); END IF;
  IF NOT (r = ANY(roles)) THEN PERFORM fail('Bạn không có quyền làm việc này', '42501'); END IF;
  RETURN r;
END $$;

-- =====================================================================
-- ĐĂNG NHẬP (chỉ dịch vụ auth gọi, role auth_svc)
-- =====================================================================
-- Trả về user id. Người mới bắt buộc có mã mời hợp lệ. Người cũ có thể dùng mã mời để vào thêm công ty khác.
CREATE FUNCTION auth_login(p_sub text, p_email text, p_name text, p_avatar text, p_invite text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE u users; i invites; v_code text := upper(nullif(btrim(p_invite), ''));
BEGIN
  SELECT * INTO u FROM users WHERE google_sub = p_sub;
  IF FOUND AND NOT u.active THEN PERFORM fail('Tài khoản đã bị khóa. Liên hệ quản trị công ty.', '42501'); END IF;

  IF v_code IS NOT NULL THEN
    SELECT * INTO i FROM invites WHERE code = v_code FOR UPDATE;
    IF NOT FOUND OR i.revoked THEN PERFORM fail('Mã mời không đúng hoặc đã bị thu hồi', '22023'); END IF;
    IF i.expires_at < now() THEN PERFORM fail('Mã mời đã hết hạn', '22023'); END IF;
    IF i.uses >= i.max_uses THEN PERFORM fail('Mã mời đã dùng hết lượt', '22023'); END IF;
    IF i.email IS NOT NULL AND lower(i.email) <> lower(p_email) THEN
      PERFORM fail('Mã mời này dành cho email khác', '22023'); END IF;
  ELSIF u.id IS NULL THEN
    PERFORM fail('INVITE_REQUIRED', '28000');
  END IF;

  IF u.id IS NULL THEN
    INSERT INTO users(google_sub, email, name, avatar_url) VALUES (p_sub, lower(p_email), p_name, p_avatar) RETURNING * INTO u;
  ELSE
    UPDATE users SET email = lower(p_email), name = p_name, avatar_url = p_avatar WHERE id = u.id;
  END IF;
  UPDATE users SET last_login_at = now() WHERE id = u.id;

  IF v_code IS NOT NULL THEN
    INSERT INTO memberships(user_id, company_id, department_id, role)
    VALUES (u.id, i.company_id, i.department_id, i.role)
    ON CONFLICT (user_id, company_id) DO UPDATE
      SET active = true,
          department_id = coalesce(EXCLUDED.department_id, memberships.department_id),
          role = CASE WHEN EXCLUDED.role < memberships.role THEN EXCLUDED.role ELSE memberships.role END;
    UPDATE invites SET uses = uses + 1 WHERE code = v_code;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM memberships WHERE user_id = u.id AND active) AND NOT u.is_system_admin THEN
    PERFORM fail('Tài khoản chưa thuộc công ty nào. Xin mã mời mới.', '42501');
  END IF;
  RETURN u.id;
END $$;

-- Dùng khi làm mới phiên: người dùng còn hoạt động không
CREATE FUNCTION auth_check(p_user uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT EXISTS (SELECT 1 FROM users WHERE id = p_user AND active)
$$;

-- Khởi tạo: tạo công ty đầu tiên và mã mời owner (chạy bằng psql lúc cài đặt)
CREATE FUNCTION bootstrap_company(p_slug text, p_name text, p_owner_email text, p_departments jsonb DEFAULT '[]')
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE c uuid; v_code text; d jsonb;
BEGIN
  INSERT INTO companies(slug, name) VALUES (p_slug, p_name) RETURNING id INTO c;
  FOR d IN SELECT * FROM jsonb_array_elements(p_departments) LOOP
    INSERT INTO departments(company_id, code, name) VALUES (c, d->>'code', d->>'name');
  END LOOP;
  v_code := new_invite_code();
  INSERT INTO invites(code, company_id, role, email, note, max_uses, expires_at)
  VALUES (v_code, c, 'owner', lower(p_owner_email), 'Khởi tạo', 1, now() + interval '14 days');
  RETURN v_code;
END $$;

-- =====================================================================
-- NGƯỜI DÙNG
-- =====================================================================
CREATE FUNCTION me() RETURNS json LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT json_build_object(
    'user', (SELECT json_build_object('id', u.id, 'email', u.email, 'name', u.name, 'avatar_url', u.avatar_url,
              'is_system_admin', u.is_system_admin, 'drive_folder_url', u.drive_folder_url,
              'drive_status', u.drive_status, 'drive_note', u.drive_note, 'drive_checked_at', u.drive_checked_at)
             FROM users u WHERE u.id = uid()),
    'memberships', coalesce((SELECT json_agg(json_build_object(
              'company_id', c.id, 'company_slug', c.slug, 'company_name', c.name,
              'department_id', d.id, 'department_code', d.code, 'department_name', d.name,
              'role', m.role, 'title', m.title) ORDER BY c.name)
             FROM memberships m JOIN companies c ON c.id = m.company_id
             LEFT JOIN departments d ON d.id = m.department_id
             WHERE m.user_id = uid() AND m.active), '[]'::json))
$$;

-- Người dùng khai báo thư mục Drive. Agent sẽ kiểm tra tên + quyền rồi chuyển trạng thái.
CREATE FUNCTION set_drive_folder(p_url text) RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE v_id text;
BEGIN
  IF uid() IS NULL THEN PERFORM fail('Chưa đăng nhập', '42501'); END IF;
  v_id := substring(p_url FROM 'drive\.google\.com/drive/(?:u/\d+/)?folders/([A-Za-z0-9_-]{10,})');
  IF v_id IS NULL THEN v_id := substring(p_url FROM '[?&]id=([A-Za-z0-9_-]{10,})'); END IF;
  IF v_id IS NULL THEN PERFORM fail('Link chưa đúng dạng thư mục Google Drive (https://drive.google.com/drive/folders/...)', '22023'); END IF;
  UPDATE users SET drive_folder_url = 'https://drive.google.com/drive/folders/' || v_id, drive_folder_id = v_id,
                   drive_status = 'pending', drive_note = 'Đang chờ agent kiểm tra', drive_checked_at = NULL
   WHERE id = uid();
  RETURN me();
END $$;

-- =====================================================================
-- VIỆC
-- =====================================================================
CREATE FUNCTION check_member(c uuid, u uuid) RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = app, public AS $$
BEGIN
  IF u IS NOT NULL AND NOT EXISTS (SELECT 1 FROM memberships WHERE company_id = c AND user_id = u AND active) THEN
    PERFORM fail('Người được giao không thuộc công ty này', '22023'); END IF;
END $$;

CREATE FUNCTION create_task(
  p_company uuid, p_title text, p_description text DEFAULT NULL, p_department uuid DEFAULT NULL,
  p_assignee uuid DEFAULT NULL, p_due date DEFAULT NULL, p_priority task_priority DEFAULT 'medium',
  p_project uuid DEFAULT NULL, p_parent bigint DEFAULT NULL, p_agent_role text DEFAULT NULL,
  p_flow uuid DEFAULT NULL)
RETURNS tasks LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE t tasks;
BEGIN
  IF NOT is_agent() THEN PERFORM require_role(p_company, ARRAY['owner','admin','manager','member']::member_role[]); END IF;
  IF p_department IS NOT NULL AND NOT EXISTS (SELECT 1 FROM departments WHERE id = p_department AND company_id = p_company) THEN
    PERFORM fail('Phòng ban không thuộc công ty này', '22023'); END IF;
  IF p_project IS NOT NULL AND NOT EXISTS (SELECT 1 FROM projects WHERE id = p_project AND company_id = p_company) THEN
    PERFORM fail('Dự án không thuộc công ty này', '22023'); END IF;
  IF p_flow IS NOT NULL AND NOT EXISTS (SELECT 1 FROM approval_flows WHERE id = p_flow AND company_id = p_company AND active) THEN
    PERFORM fail('Quy trình duyệt không hợp lệ', '22023'); END IF;
  IF p_parent IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tasks WHERE id = p_parent AND company_id = p_company) THEN
    PERFORM fail('Việc cha không thuộc công ty này', '22023'); END IF;
  PERFORM check_member(p_company, p_assignee);
  INSERT INTO tasks(company_id, department_id, project_id, parent_id, title, description, priority, assignee_id,
                    agent_role, due_date, approval_flow_id, created_by, created_by_agent)
  VALUES (p_company, coalesce(p_department, my_dept(p_company)), p_project, p_parent, btrim(p_title), nullif(btrim(p_description), ''),
          p_priority, p_assignee, nullif(p_agent_role, ''), p_due, p_flow, uid(), CASE WHEN is_agent() THEN actor() END)
  RETURNING * INTO t;
  RETURN t;
END $$;

-- Sửa việc: p jsonb chỉ nhận các khóa cho phép
CREATE FUNCTION update_task(p_task bigint, p jsonb) RETURNS tasks LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE t tasks; v_status task_status;
BEGIN
  SELECT * INTO t FROM tasks WHERE id = p_task FOR UPDATE;
  IF NOT FOUND OR NOT can_see(t) THEN PERFORM fail('Không tìm thấy việc', '42704'); END IF;
  IF NOT can_edit(t) THEN PERFORM fail('Bạn không có quyền sửa việc này', '42501'); END IF;
  IF p ? 'status' THEN
    v_status := (p->>'status')::task_status;
    IF v_status IN ('in_review','done') THEN PERFORM fail('Dùng "Nộp kết quả" hoặc "Duyệt" để chuyển sang trạng thái này', '22023'); END IF;
    IF t.status = 'in_review' THEN PERFORM fail('Việc đang chờ duyệt, không đổi trạng thái được', '22023'); END IF;
  END IF;
  IF p ? 'assignee_id' THEN PERFORM check_member(t.company_id, nullif(p->>'assignee_id','')::uuid); END IF;
  IF p ? 'department_id' AND nullif(p->>'department_id','') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM departments WHERE id = (p->>'department_id')::uuid AND company_id = t.company_id) THEN
    PERFORM fail('Phòng ban không thuộc công ty này', '22023'); END IF;
  UPDATE tasks SET
    title         = CASE WHEN p ? 'title' THEN btrim(p->>'title') ELSE title END,
    description   = CASE WHEN p ? 'description' THEN nullif(btrim(p->>'description'), '') ELSE description END,
    priority      = CASE WHEN p ? 'priority' THEN (p->>'priority')::task_priority ELSE priority END,
    due_date      = CASE WHEN p ? 'due_date' THEN nullif(p->>'due_date','')::date ELSE due_date END,
    assignee_id   = CASE WHEN p ? 'assignee_id' THEN nullif(p->>'assignee_id','')::uuid ELSE assignee_id END,
    department_id = CASE WHEN p ? 'department_id' THEN nullif(p->>'department_id','')::uuid ELSE department_id END,
    project_id    = CASE WHEN p ? 'project_id' THEN nullif(p->>'project_id','')::uuid ELSE project_id END,
    approval_flow_id = CASE WHEN p ? 'approval_flow_id' THEN nullif(p->>'approval_flow_id','')::uuid ELSE approval_flow_id END,
    agent_role    = CASE WHEN p ? 'agent_role' THEN nullif(p->>'agent_role','') ELSE agent_role END,
    status        = coalesce(v_status, status)
  WHERE id = p_task RETURNING * INTO t;
  RETURN t;
END $$;

CREATE FUNCTION add_comment(p_task bigint, p_body text, p_kind comment_kind DEFAULT 'note') RETURNS comments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE t tasks; c comments;
BEGIN
  SELECT * INTO t FROM tasks WHERE id = p_task;
  IF NOT FOUND OR NOT can_see(t) THEN PERFORM fail('Không tìm thấy việc', '42704'); END IF;
  IF NOT is_agent() AND p_kind NOT IN ('note','answer') THEN p_kind := 'note'; END IF;
  INSERT INTO comments(task_id, user_id, actor, kind, body) VALUES (p_task, uid(), actor(), p_kind, btrim(p_body)) RETURNING * INTO c;
  RETURN c;
END $$;

-- Người trả lời câu hỏi của agent → agent nhận lại việc ở lượt quét kế tiếp
CREATE FUNCTION answer_agent(p_task bigint, p_body text) RETURNS tasks LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE t tasks;
BEGIN
  SELECT * INTO t FROM tasks WHERE id = p_task FOR UPDATE;
  IF NOT FOUND OR NOT can_see(t) THEN PERFORM fail('Không tìm thấy việc', '42704'); END IF;
  IF NOT t.waiting_on_human THEN PERFORM fail('Việc này không chờ trả lời', '22023'); END IF;
  INSERT INTO comments(task_id, user_id, actor, kind, body) VALUES (p_task, uid(), actor(), 'answer', btrim(p_body));
  UPDATE tasks SET waiting_on_human = false, status = 'todo' WHERE id = p_task RETURNING * INTO t;
  RETURN t;
END $$;

CREATE FUNCTION add_link(p_task bigint, p_url text, p_title text DEFAULT NULL) RETURNS task_links
LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE t tasks; l task_links;
BEGIN
  SELECT * INTO t FROM tasks WHERE id = p_task;
  IF NOT FOUND OR NOT can_see(t) THEN PERFORM fail('Không tìm thấy việc', '42704'); END IF;
  IF p_url !~ '^https://' THEN PERFORM fail('Link phải bắt đầu bằng https://', '22023'); END IF;
  INSERT INTO task_links(task_id, url, title, added_by, actor)
  VALUES (p_task, btrim(p_url), coalesce(nullif(btrim(p_title), ''), 'Tài liệu'), uid(), actor()) RETURNING * INTO l;
  RETURN l;
END $$;

CREATE FUNCTION remove_link(p_link bigint) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE t tasks; l task_links;
BEGIN
  SELECT * INTO l FROM task_links WHERE id = p_link;
  SELECT * INTO t FROM tasks WHERE id = l.task_id;
  IF NOT FOUND OR NOT (can_edit(t) OR l.added_by = uid()) THEN PERFORM fail('Bạn không có quyền gỡ link này', '42501'); END IF;
  DELETE FROM task_links WHERE id = p_link;
END $$;

-- =====================================================================
-- DUYỆT NHIỀU CẤP
-- =====================================================================
-- Nộp kết quả: nếu việc có quy trình duyệt → tạo các bước và chuyển "Chờ duyệt"; nếu không → "Xong"
CREATE FUNCTION submit_task(p_task bigint, p_note text DEFAULT NULL) RETURNS tasks
LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE t tasks; v_round int;
BEGIN
  SELECT * INTO t FROM tasks WHERE id = p_task FOR UPDATE;
  IF NOT FOUND OR NOT can_see(t) THEN PERFORM fail('Không tìm thấy việc', '42704'); END IF;
  IF NOT (is_agent() OR t.assignee_id = uid() OR can_edit(t)) THEN PERFORM fail('Chỉ người được giao mới nộp kết quả', '42501'); END IF;
  IF t.status IN ('in_review','done','cancelled') THEN PERFORM fail('Việc đã nộp hoặc đã đóng', '22023'); END IF;
  IF nullif(btrim(p_note), '') IS NOT NULL THEN
    INSERT INTO comments(task_id, user_id, actor, kind, body) VALUES (p_task, uid(), actor(), CASE WHEN is_agent() THEN 'result'::comment_kind ELSE 'submit'::comment_kind END, btrim(p_note));
  END IF;
  v_round := t.attempts + 1;
  IF t.approval_flow_id IS NOT NULL AND EXISTS (SELECT 1 FROM approval_steps WHERE flow_id = t.approval_flow_id) THEN
    DELETE FROM approvals WHERE task_id = p_task AND round = v_round;
    INSERT INTO approvals(task_id, round, step_no, step_name, approver_role, approver_user)
    SELECT p_task, v_round, s.step_no, s.name, s.approver_role, s.approver_user FROM approval_steps s WHERE s.flow_id = t.approval_flow_id;
    UPDATE tasks SET status = 'in_review', current_step = (SELECT min(step_no) FROM approval_steps WHERE flow_id = t.approval_flow_id),
                     waiting_on_human = false
     WHERE id = p_task RETURNING * INTO t;
  ELSE
    UPDATE tasks SET status = 'done', waiting_on_human = false WHERE id = p_task RETURNING * INTO t;
  END IF;
  RETURN t;
END $$;

CREATE FUNCTION decide(p_task bigint, p_approve boolean, p_note text DEFAULT NULL) RETURNS tasks
LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE t tasks; v_round int; v_next int;
BEGIN
  SELECT * INTO t FROM tasks WHERE id = p_task FOR UPDATE;
  IF NOT FOUND THEN PERFORM fail('Không tìm thấy việc', '42704'); END IF;
  IF t.status <> 'in_review' THEN PERFORM fail('Việc không ở trạng thái chờ duyệt', '22023'); END IF;
  IF NOT can_approve(t) THEN PERFORM fail('Bạn không phải người duyệt bước này', '42501'); END IF;
  IF NOT p_approve AND coalesce(btrim(p_note), '') = '' THEN PERFORM fail('Cần ghi lý do trả lại', '22023'); END IF;
  v_round := t.attempts + 1;
  UPDATE approvals SET decision = CASE WHEN p_approve THEN 'approved'::decision ELSE 'rejected' END,
                       decided_by = uid(), decided_at = now(), note = nullif(btrim(p_note), '')
   WHERE task_id = p_task AND round = v_round AND step_no = t.current_step;
  INSERT INTO comments(task_id, user_id, actor, kind, body)
  VALUES (p_task, uid(), actor(), CASE WHEN p_approve THEN 'approve'::comment_kind ELSE 'reject' END,
          coalesce(nullif(btrim(p_note), ''), CASE WHEN p_approve THEN 'Đã duyệt' ELSE 'Trả lại' END));
  IF p_approve THEN
    SELECT min(step_no) INTO v_next FROM approvals WHERE task_id = p_task AND round = v_round AND step_no > t.current_step;
    IF v_next IS NULL THEN
      UPDATE tasks SET status = 'done', current_step = NULL WHERE id = p_task RETURNING * INTO t;
    ELSE
      UPDATE tasks SET current_step = v_next WHERE id = p_task RETURNING * INTO t;
    END IF;
  ELSE
    UPDATE approvals SET decision = 'skipped' WHERE task_id = p_task AND round = v_round AND decision = 'pending';
    UPDATE tasks SET status = CASE WHEN agent_role IS NOT NULL THEN 'todo'::task_status ELSE 'in_progress' END,
                     current_step = NULL, attempts = attempts + 1 WHERE id = p_task RETURNING * INTO t;
  END IF;
  RETURN t;
END $$;

-- =====================================================================
-- QUẢN TRỊ CÔNG TY
-- =====================================================================
CREATE FUNCTION save_department(p_company uuid, p_code text, p_name text, p_id uuid DEFAULT NULL, p_active boolean DEFAULT true)
RETURNS departments LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE d departments;
BEGIN
  PERFORM require_role(p_company, ARRAY['owner','admin']::member_role[]);
  IF p_id IS NULL THEN
    INSERT INTO departments(company_id, code, name) VALUES (p_company, upper(btrim(p_code)), btrim(p_name)) RETURNING * INTO d;
  ELSE
    UPDATE departments SET code = upper(btrim(p_code)), name = btrim(p_name), active = p_active
     WHERE id = p_id AND company_id = p_company RETURNING * INTO d;
    IF NOT FOUND THEN PERFORM fail('Không tìm thấy phòng ban', '42704'); END IF;
  END IF;
  RETURN d;
END $$;

CREATE FUNCTION create_invite(p_company uuid, p_role member_role DEFAULT 'member', p_department uuid DEFAULT NULL,
  p_email text DEFAULT NULL, p_max_uses int DEFAULT 1, p_days int DEFAULT 7, p_note text DEFAULT NULL)
RETURNS invites LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE r member_role; i invites; v_code text;
BEGIN
  r := require_role(p_company, ARRAY['owner','admin','manager']::member_role[]);
  -- Trưởng phòng chỉ mời thành viên vào phòng mình; admin không tạo được owner
  IF r = 'manager' AND (p_role <> 'member' OR p_department IS DISTINCT FROM my_dept(p_company)) THEN
    PERFORM fail('Trưởng phòng chỉ mời được thành viên vào phòng của mình', '42501'); END IF;
  IF r = 'admin' AND p_role = 'owner' THEN PERFORM fail('Chỉ chủ sở hữu mới mời được chủ sở hữu', '42501'); END IF;
  IF p_department IS NOT NULL AND NOT EXISTS (SELECT 1 FROM departments WHERE id = p_department AND company_id = p_company) THEN
    PERFORM fail('Phòng ban không thuộc công ty này', '22023'); END IF;
  IF p_days NOT BETWEEN 1 AND 60 THEN PERFORM fail('Hạn dùng từ 1 đến 60 ngày', '22023'); END IF;
  v_code := new_invite_code();
  INSERT INTO invites(code, company_id, department_id, role, email, note, max_uses, expires_at, created_by)
  VALUES (v_code, p_company, p_department, p_role, lower(nullif(btrim(p_email), '')), nullif(btrim(p_note), ''),
          p_max_uses, now() + make_interval(days => p_days), uid())
  RETURNING * INTO i;
  RETURN i;
END $$;

CREATE FUNCTION revoke_invite(p_code text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE i invites;
BEGIN
  SELECT * INTO i FROM invites WHERE code = upper(p_code);
  IF NOT FOUND THEN PERFORM fail('Không tìm thấy mã mời', '42704'); END IF;
  PERFORM require_role(i.company_id, ARRAY['owner','admin','manager']::member_role[]);
  UPDATE invites SET revoked = true WHERE code = i.code;
END $$;

CREATE FUNCTION set_member(p_company uuid, p_user uuid, p_role member_role, p_department uuid DEFAULT NULL,
  p_title text DEFAULT NULL, p_active boolean DEFAULT true)
RETURNS memberships LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE r member_role; m memberships;
BEGIN
  r := require_role(p_company, ARRAY['owner','admin']::member_role[]);
  SELECT * INTO m FROM memberships WHERE company_id = p_company AND user_id = p_user;
  IF NOT FOUND THEN PERFORM fail('Người này không thuộc công ty', '42704'); END IF;
  IF r = 'admin' AND (m.role = 'owner' OR p_role = 'owner') THEN PERFORM fail('Chỉ chủ sở hữu mới đổi được vai trò chủ sở hữu', '42501'); END IF;
  IF p_user = uid() AND (p_role <> m.role OR NOT p_active) THEN PERFORM fail('Không tự đổi vai trò hoặc tự khóa chính mình', '42501'); END IF;
  IF m.role = 'owner' AND (p_role <> 'owner' OR NOT p_active)
     AND (SELECT count(*) FROM memberships WHERE company_id = p_company AND role = 'owner' AND active) <= 1 THEN
    PERFORM fail('Công ty phải còn ít nhất một chủ sở hữu', '22023'); END IF;
  UPDATE memberships SET role = p_role, department_id = p_department, title = nullif(btrim(p_title), ''), active = p_active
   WHERE company_id = p_company AND user_id = p_user RETURNING * INTO m;
  RETURN m;
END $$;

CREATE FUNCTION save_project(p_company uuid, p_slug text, p_name text, p_department uuid DEFAULT NULL,
  p_drive_url text DEFAULT NULL, p_id uuid DEFAULT NULL, p_active boolean DEFAULT true)
RETURNS projects LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE p projects;
BEGIN
  PERFORM require_role(p_company, ARRAY['owner','admin','manager']::member_role[]);
  IF p_id IS NULL THEN
    INSERT INTO projects(company_id, department_id, slug, name, drive_url)
    VALUES (p_company, p_department, lower(btrim(p_slug)), btrim(p_name), nullif(btrim(p_drive_url), '')) RETURNING * INTO p;
  ELSE
    UPDATE projects SET slug = lower(btrim(p_slug)), name = btrim(p_name), department_id = p_department,
                        drive_url = nullif(btrim(p_drive_url), ''), active = p_active
     WHERE id = p_id AND company_id = p_company RETURNING * INTO p;
  END IF;
  RETURN p;
END $$;

-- steps: [{"name":"Trưởng phòng","approver_role":"manager"},{"name":"Giám đốc","approver_user":"<uuid>"}]
CREATE FUNCTION save_flow(p_company uuid, p_name text, p_steps jsonb, p_department uuid DEFAULT NULL, p_id uuid DEFAULT NULL)
RETURNS approval_flows LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE f approval_flows; s jsonb; n int := 0;
BEGIN
  PERFORM require_role(p_company, ARRAY['owner','admin']::member_role[]);
  IF jsonb_typeof(p_steps) <> 'array' OR jsonb_array_length(p_steps) NOT BETWEEN 1 AND 6 THEN
    PERFORM fail('Quy trình cần từ 1 đến 6 bước', '22023'); END IF;
  IF p_id IS NULL THEN
    INSERT INTO approval_flows(company_id, department_id, name) VALUES (p_company, p_department, btrim(p_name)) RETURNING * INTO f;
  ELSE
    UPDATE approval_flows SET name = btrim(p_name), department_id = p_department WHERE id = p_id AND company_id = p_company RETURNING * INTO f;
    IF NOT FOUND THEN PERFORM fail('Không tìm thấy quy trình', '42704'); END IF;
    DELETE FROM approval_steps WHERE flow_id = f.id;
  END IF;
  FOR s IN SELECT * FROM jsonb_array_elements(p_steps) LOOP
    n := n + 1;
    IF s ? 'approver_user' THEN PERFORM check_member(p_company, (s->>'approver_user')::uuid); END IF;
    INSERT INTO approval_steps(flow_id, step_no, name, approver_role, approver_user)
    VALUES (f.id, n, coalesce(nullif(btrim(s->>'name'), ''), 'Bước ' || n),
            nullif(s->>'approver_role', '')::member_role, nullif(s->>'approver_user', '')::uuid);
  END LOOP;
  RETURN f;
END $$;

CREATE FUNCTION archive_flow(p_id uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE f approval_flows;
BEGIN
  SELECT * INTO f FROM approval_flows WHERE id = p_id;
  IF NOT FOUND THEN PERFORM fail('Không tìm thấy quy trình', '42704'); END IF;
  PERFORM require_role(f.company_id, ARRAY['owner','admin']::member_role[]);
  UPDATE approval_flows SET active = false WHERE id = p_id;
END $$;

-- =====================================================================
-- AGENT (role agent)
-- =====================================================================
CREATE FUNCTION agent_claim(p_role text) RETURNS SETOF tasks LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE t tasks;
BEGIN
  IF NOT is_agent() THEN PERFORM fail('Chỉ agent', '42501'); END IF;
  SELECT * INTO t FROM tasks WHERE status = 'todo' AND agent_role = p_role AND NOT waiting_on_human
   ORDER BY CASE priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END, created_at
   FOR UPDATE SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN RETURN; END IF;
  UPDATE tasks SET status = 'in_progress', claimed_by = actor(), claimed_at = now() WHERE id = t.id RETURNING * INTO t;
  INSERT INTO comments(task_id, actor, kind, body) VALUES (t.id, 'agent:' || p_role, 'claim', 'Đã nhận việc');
  RETURN NEXT t;
END $$;

CREATE FUNCTION agent_ask(p_task bigint, p_question text) RETURNS tasks LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE t tasks;
BEGIN
  IF NOT is_agent() THEN PERFORM fail('Chỉ agent', '42501'); END IF;
  UPDATE tasks SET status = 'blocked', waiting_on_human = true WHERE id = p_task AND status = 'in_progress' RETURNING * INTO t;
  IF NOT FOUND THEN PERFORM fail('Việc không ở trạng thái đang làm', '22023'); END IF;
  INSERT INTO comments(task_id, actor, kind, body) VALUES (p_task, 'agent:' || coalesce(t.agent_role, 'agent'), 'question', p_question);
  RETURN t;
END $$;

-- Danh sách thư mục Drive cần kiểm tra (mới khai báo hoặc kiểm tra lần cuối quá 24 giờ)
CREATE FUNCTION agent_drive_queue() RETURNS TABLE(user_id uuid, email text, name text, folder_id text, expected_names text[], status drive_state)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT u.id, u.email, u.name, u.drive_folder_id,
         ARRAY(SELECT folder_name(u.id, m.company_id) FROM memberships m WHERE m.user_id = u.id AND m.active),
         u.drive_status
    FROM users u
   WHERE is_agent() AND u.active AND u.drive_folder_id IS NOT NULL
     AND (u.drive_status = 'pending' OR u.drive_checked_at IS NULL OR u.drive_checked_at < now() - interval '24 hours')
$$;

CREATE FUNCTION agent_drive_result(p_user uuid, p_ok boolean, p_note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
BEGIN
  IF NOT is_agent() THEN PERFORM fail('Chỉ agent', '42501'); END IF;
  UPDATE users SET drive_status = CASE WHEN p_ok THEN 'ok'::drive_state ELSE 'error' END,
                   drive_note = p_note, drive_checked_at = now() WHERE id = p_user;
END $$;

-- files: [{"file_id","name","mime_type","web_url","size_bytes","modified_at"}]; gắn task theo tên "T-123 ..."
CREATE FUNCTION agent_drive_files(p_user uuid, p_files jsonb) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = app, public AS $$
DECLARE n int;
BEGIN
  IF NOT is_agent() THEN PERFORM fail('Chỉ agent', '42501'); END IF;
  DELETE FROM drive_files WHERE owner_user = p_user AND file_id NOT IN (SELECT f->>'file_id' FROM jsonb_array_elements(p_files) f);
  INSERT INTO drive_files(file_id, owner_user, name, mime_type, web_url, size_bytes, modified_at, task_id, synced_at)
  SELECT f->>'file_id', p_user, f->>'name', f->>'mime_type', f->>'web_url', (f->>'size_bytes')::bigint, (f->>'modified_at')::timestamptz,
         (SELECT t.id FROM tasks t JOIN memberships m ON m.company_id = t.company_id AND m.user_id = p_user
           WHERE t.id = nullif(substring(f->>'name' FROM '^T-(\d+)\M'), '')::bigint),
         now()
    FROM jsonb_array_elements(p_files) f
  ON CONFLICT (file_id) DO UPDATE SET name = EXCLUDED.name, mime_type = EXCLUDED.mime_type, web_url = EXCLUDED.web_url,
    size_bytes = EXCLUDED.size_bytes, modified_at = EXCLUDED.modified_at, task_id = EXCLUDED.task_id, synced_at = now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

-- Tên thư mục chuẩn: "DEO - <slug công ty> - <mã phòng> - <Họ tên>"
CREATE FUNCTION folder_name(p_user uuid, p_company uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT 'DEO - ' || c.slug || ' - ' || coalesce(d.code, 'CHUNG') || ' - ' || u.name
    FROM users u JOIN memberships m ON m.user_id = u.id AND m.company_id = p_company
    JOIN companies c ON c.id = p_company LEFT JOIN departments d ON d.id = m.department_id
   WHERE u.id = p_user
$$;

CREATE FUNCTION my_folder_names() RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT ARRAY(SELECT folder_name(uid(), m.company_id) FROM memberships m WHERE m.user_id = uid() AND m.active)
$$;
