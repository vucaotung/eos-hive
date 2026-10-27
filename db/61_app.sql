-- =====================================================================
-- 61 · Lớp ứng dụng web "Dẹo Work" trên lược đồ 108 bảng
-- Vai trò mẫu + quyền, mã mời, quy trình duyệt nhiều bước, và các hàm agent.app_* mà giao diện gọi.
-- Mọi hàm app_* nhận MỘT tham số jsonb, trả jsonb; danh tính lấy từ request.jwt.claims.sub (do máy chủ web đặt cho từng yêu cầu).
-- Vai trò theo thiết kế cũ: owner · admin · manager · member. Ánh xạ sang lược đồ mới:
--   owner/admin  = core.user_roles trỏ vai trò mẫu owner/admin (core.roles.company_id IS NULL)
--   manager      = core.memberships.is_dept_head
--   member       = còn lại (vai trò mẫu member)
-- =====================================================================

ALTER TABLE core.invites ADD COLUMN IF NOT EXISTS dept_head boolean NOT NULL DEFAULT false;   -- mã mời vào làm trưởng phòng

-- Trạng thái duyệt của việc: none (không cần duyệt) · pending (chờ duyệt) · approved (đã duyệt) · rejected (bị trả lại).
-- Việc gắn quy trình duyệt chỉ được chuyển sang Xong khi approval_status = 'approved' (trigger bên dưới), kể cả khi ai đó cập nhật trực tiếp.
ALTER TABLE work.tasks ADD COLUMN IF NOT EXISTS approval_status text NOT NULL DEFAULT 'none' CHECK (approval_status IN ('none','pending','approved','rejected'));
CREATE OR REPLACE FUNCTION work.tasks_need_approval_trg() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'done' AND OLD.status <> 'done' AND NEW.approval_flow_id IS NOT NULL AND NEW.approval_status <> 'approved' THEN
    RAISE EXCEPTION 'Việc T-% phải được duyệt xong mới hoàn thành (trạng thái duyệt: %)', NEW.id, NEW.approval_status USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS tasks_need_approval ON work.tasks;
CREATE TRIGGER tasks_need_approval BEFORE UPDATE OF status ON work.tasks FOR EACH ROW EXECUTE FUNCTION work.tasks_need_approval_trg();

-- ---------- Vai trò mẫu và quyền ----------
INSERT INTO core.roles (company_id, code, name, description, builtin)
SELECT NULL, v.code, v.name, v.d, true
  FROM (VALUES ('owner',  'Chủ sở hữu',      'Toàn quyền công ty, mời và đổi vai trò mọi người'),
               ('admin',  'Quản trị công ty', 'Quản trị thành viên, phòng ban, quy trình duyệt; không đụng tới chủ sở hữu'),
               ('member', 'Thành viên',       'Làm việc trong phòng ban của mình; trưởng phòng là thành viên được đánh dấu trưởng phòng')) v(code, name, d)
 WHERE NOT EXISTS (SELECT 1 FROM core.roles r WHERE r.company_id IS NULL AND r.code = v.code);

INSERT INTO core.permissions (code, module, area, name, scoped, sort) VALUES
 ('work.task.view',     'work', 'Công việc', 'Xem việc',                      true,  10),
 ('work.task.create',   'work', 'Công việc', 'Giao việc',                     false, 20),
 ('work.task.edit',     'work', 'Công việc', 'Sửa việc',                      true,  30),
 ('work.report.view',   'work', 'Báo cáo',   'Xem báo cáo',                   true,  40),
 ('core.invite.create', 'core', 'Quản trị',  'Tạo mã mời',                    false, 50),
 ('core.member.manage', 'core', 'Quản trị',  'Quản lý thành viên, phòng ban', false, 60)
ON CONFLICT (code) DO NOTHING;

INSERT INTO core.role_permissions (role_id, permission, scope)
SELECT r.id, p.code, CASE WHEN r.code IN ('owner','admin') THEN 'company'::core.perm_scope ELSE 'department'::core.perm_scope END
  FROM core.roles r CROSS JOIN core.permissions p
 WHERE r.company_id IS NULL AND r.code IN ('owner','admin','member')
   AND (r.code IN ('owner','admin') OR p.code IN ('work.task.view','work.task.create','work.task.edit','work.report.view'))
ON CONFLICT (role_id, permission) DO NOTHING;

-- ---------- Tiện ích ----------
CREATE OR REPLACE FUNCTION agent._sys_role(p_code text) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = core, public AS $$
  SELECT id FROM core.roles WHERE company_id IS NULL AND code = p_code
$$;

-- Vai trò theo thiết kế cũ của một người trong một công ty. NULL = không phải thành viên (hoặc đã bị khóa).
CREATE OR REPLACE FUNCTION agent._role_of(p_user uuid, p_company uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = core, public AS $$
  SELECT CASE
           WHEN m.user_id IS NULL OR NOT m.active THEN NULL
           WHEN EXISTS (SELECT 1 FROM core.user_roles ur JOIN core.roles r ON r.id = ur.role_id
                         WHERE ur.company_id = p_company AND ur.user_id = p_user AND r.company_id IS NULL AND r.code = 'owner') THEN 'owner'
           WHEN u.is_system_admin OR EXISTS (SELECT 1 FROM core.user_roles ur JOIN core.roles r ON r.id = ur.role_id
                         WHERE ur.company_id = p_company AND ur.user_id = p_user AND r.company_id IS NULL AND r.code = 'admin') THEN 'admin'
           WHEN m.is_dept_head THEN 'manager'
           ELSE 'member' END
    FROM core.users u LEFT JOIN core.memberships m ON m.user_id = u.id AND m.company_id = p_company
   WHERE u.id = p_user
$$;

-- Như _role_of nhưng tính cả thành viên đã khóa (dùng khi quản trị sửa người đã khóa)
CREATE OR REPLACE FUNCTION agent._role_raw(p_user uuid, p_company uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = core, public AS $$
  SELECT CASE
           WHEN m.user_id IS NULL THEN NULL
           WHEN EXISTS (SELECT 1 FROM core.user_roles ur JOIN core.roles r ON r.id = ur.role_id
                         WHERE ur.company_id = p_company AND ur.user_id = p_user AND r.company_id IS NULL AND r.code = 'owner') THEN 'owner'
           WHEN u.is_system_admin OR EXISTS (SELECT 1 FROM core.user_roles ur JOIN core.roles r ON r.id = ur.role_id
                         WHERE ur.company_id = p_company AND ur.user_id = p_user AND r.company_id IS NULL AND r.code = 'admin') THEN 'admin'
           WHEN m.is_dept_head THEN 'manager'
           ELSE 'member' END
    FROM core.users u LEFT JOIN core.memberships m ON m.user_id = u.id AND m.company_id = p_company
   WHERE u.id = p_user
$$;

CREATE OR REPLACE FUNCTION agent._need_role(p_user uuid, p_company uuid, p_roles text[]) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE r text := agent._role_of(p_user, p_company);
BEGIN
  IF r IS NULL OR NOT (r = ANY (p_roles)) THEN RAISE EXCEPTION 'Bạn không có quyền thực hiện thao tác này' USING ERRCODE = '42501'; END IF;
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION agent._audit(p_company uuid, p_user uuid, p_action text, p_type text, p_id text, p_summary text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = core, public AS $$
  INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
  VALUES (p_company, 'user:' || p_user, p_user, 'web', p_action, p_type, p_id, left(p_summary, 300))
$$;

CREATE OR REPLACE FUNCTION agent._uuid(p jsonb, k text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT nullif(btrim(p->>k), '')::uuid $$;

CREATE OR REPLACE FUNCTION agent._task_json(t work.tasks) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  SELECT jsonb_build_object(
    'id', t.id, 'company_id', t.company_id, 'title', t.title, 'description', t.description, 'status', t.status, 'priority', t.priority,
    'assignee_id', t.assignee_id, 'department_id', t.department_id, 'project_id', t.project_id, 'parent_id', t.parent_id,
    'due_date', t.due_date, 'start_date', t.start_date, 'important', t.important, 'urgent', t.urgent, 'created_by', t.created_by, 'created_by_agent', t.created_by_agent, 'waiting_on_human', t.waiting_on_human,
    'agent_role', (SELECT g.code FROM agent.agents g WHERE g.id = t.agent_id), 'attempts', t.attempts, 'approval_flow_id', t.approval_flow_id, 'approval_status', t.approval_status,
    'claimed_by', t.claimed_by, 'progress', t.progress, 'result', t.result, 'completed_at', t.completed_at, 'created_at', t.created_at, 'updated_at', t.updated_at,
    'current_step', (SELECT r.current_step FROM core.approval_requests r WHERE r.entity_type = 'task' AND r.entity_id = t.id AND r.state = 'pending' ORDER BY r.id DESC LIMIT 1))
$$;

-- Người này có duyệt được bước hiện tại của yêu cầu không (ngữ nghĩa của Dẹo Work cũ)
CREATE OR REPLACE FUNCTION agent._can_approve_step(p_user uuid, r core.approval_requests, s core.approval_steps) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE rl text := agent._role_of(p_user, r.company_id); has_head boolean; sr text; pm uuid; tc uuid;
BEGIN
  IF rl IS NULL THEN RETURN false; END IF;
  IF s.approver_kind = 'user' THEN RETURN s.approver_user = p_user; END IF;
  IF s.approver_kind = 'creator' THEN
    SELECT created_by INTO tc FROM work.tasks WHERE id = r.entity_id;
    -- người giao duyệt; người nộp không tự duyệt việc của mình: khi người giao cũng là người nộp thì trưởng phòng (hoặc quản trị nếu phòng chưa có trưởng phòng) duyệt thay
    IF tc IS NOT NULL AND tc IS DISTINCT FROM r.requested_by THEN RETURN p_user = tc; END IF;
    IF p_user IS NOT DISTINCT FROM r.requested_by THEN RETURN false; END IF;
    SELECT EXISTS (SELECT 1 FROM core.memberships m WHERE m.company_id = r.company_id AND m.department_id = r.department_id AND m.is_dept_head AND m.active) INTO has_head;
    IF has_head THEN
      RETURN EXISTS (SELECT 1 FROM core.memberships m WHERE m.user_id = p_user AND m.company_id = r.company_id AND m.department_id = r.department_id AND m.is_dept_head AND m.active);
    END IF;
    RETURN rl IN ('owner', 'admin');
  END IF;
  IF s.approver_kind = 'dept_head' THEN
    SELECT EXISTS (SELECT 1 FROM core.memberships m WHERE m.company_id = r.company_id AND m.department_id = r.department_id AND m.is_dept_head AND m.active) INTO has_head;
    IF has_head THEN
      RETURN EXISTS (SELECT 1 FROM core.memberships m WHERE m.user_id = p_user AND m.company_id = r.company_id AND m.department_id = r.department_id AND m.is_dept_head AND m.active);
    END IF;
    RETURN rl IN ('owner', 'admin');          -- phòng chưa có trưởng phòng: quản trị duyệt thay
  END IF;
  IF s.approver_kind = 'role' THEN
    SELECT code INTO sr FROM core.roles WHERE id = s.approver_role;
    IF sr = 'owner' AND EXISTS (SELECT 1 FROM core.roles WHERE id = s.approver_role AND company_id IS NULL) THEN RETURN rl = 'owner'; END IF;
    IF sr = 'admin' AND EXISTS (SELECT 1 FROM core.roles WHERE id = s.approver_role AND company_id IS NULL) THEN RETURN rl IN ('owner', 'admin'); END IF;
    RETURN EXISTS (SELECT 1 FROM core.user_roles ur WHERE ur.company_id = r.company_id AND ur.user_id = p_user AND ur.role_id = s.approver_role);
  END IF;
  IF s.approver_kind = 'project_manager' THEN
    SELECT p.manager_id INTO pm FROM work.tasks t JOIN core.projects p ON p.id = t.project_id WHERE t.id = r.entity_id;
    IF pm IS NULL THEN RETURN rl IN ('owner', 'admin'); END IF;
    RETURN pm = p_user;
  END IF;
  RETURN false;
END $$;

-- Việc người này được xem: theo quyền work.task.view + người làm/giao/theo dõi + người đang phải duyệt.
-- p_days: chỉ lấy việc đang mở hoặc cập nhật trong N ngày; p_limit: số dòng tối đa (NULL = không giới hạn).
CREATE OR REPLACE FUNCTION agent._visible_tasks(p_user uuid, p_company uuid, p_days int DEFAULT NULL, p_limit int DEFAULT NULL) RETURNS SETOF work.tasks
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  SELECT t.* FROM work.tasks t
   WHERE t.company_id = p_company AND agent._role_of(p_user, p_company) IS NOT NULL
     AND (p_days IS NULL OR t.status NOT IN ('done','cancelled') OR t.updated_at > now() - make_interval(days => p_days))
     AND (work.can_view_task(p_user, t.id)
          OR EXISTS (SELECT 1 FROM core.approval_requests r JOIN core.approval_steps s ON s.flow_id = r.flow_id AND s.step_no = r.current_step
                      WHERE r.entity_type = 'task' AND r.entity_id = t.id AND r.state = 'pending' AND agent._can_approve_step(p_user, r, s)))
   ORDER BY t.updated_at DESC LIMIT p_limit
$$;

CREATE OR REPLACE FUNCTION agent._can_see(p_user uuid, t work.tasks) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  SELECT agent._role_of(p_user, t.company_id) IS NOT NULL AND (
         work.can_view_task(p_user, t.id)
      OR EXISTS (SELECT 1 FROM core.approval_requests r JOIN core.approval_steps s ON s.flow_id = r.flow_id AND s.step_no = r.current_step
                  WHERE r.entity_type = 'task' AND r.entity_id = t.id AND r.state = 'pending' AND agent._can_approve_step(p_user, r, s)))
$$;

CREATE OR REPLACE FUNCTION agent._can_edit(p_user uuid, t work.tasks) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  SELECT CASE WHEN x.r IS NULL THEN false
              WHEN x.r IN ('owner','admin') THEN true
              WHEN x.r = 'manager' THEN t.created_by = p_user OR t.assignee_id = p_user
                                        OR (t.department_id IS NOT NULL AND t.department_id = (SELECT m.department_id FROM core.memberships m WHERE m.user_id = p_user AND m.company_id = t.company_id))
              ELSE t.created_by = p_user OR t.assignee_id = p_user END
    FROM (SELECT agent._role_of(p_user, t.company_id) AS r) x
$$;

-- ---------- Quy trình duyệt ----------
-- Mở yêu cầu duyệt cho một việc (vòng = số lần nộp). Không có quy trình (hoặc quy trình đã ngừng) thì việc Xong luôn.
CREATE OR REPLACE FUNCTION agent._approval_start(p_task bigint, p_by uuid) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE t work.tasks; f core.approval_flows; r core.approval_requests;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task FOR UPDATE;
  SELECT * INTO f FROM core.approval_flows WHERE id = t.approval_flow_id AND active;
  IF f.id IS NULL OR NOT EXISTS (SELECT 1 FROM core.approval_steps WHERE flow_id = f.id) THEN
    -- quy trình đã bị ngừng/xóa: việc không còn cần duyệt
    UPDATE work.tasks SET approval_flow_id = NULL, approval_status = 'none', status = 'done', completed_at = now(), progress = 100, waiting_on_human = false, updated_at = now() WHERE id = t.id;
    RETURN 'done';
  END IF;
  IF EXISTS (SELECT 1 FROM core.approval_requests WHERE entity_type = 'task' AND entity_id = t.id AND state = 'pending') THEN
    RAISE EXCEPTION 'Việc T-% đang chờ duyệt rồi', t.id;
  END IF;
  INSERT INTO core.approval_requests (company_id, flow_id, entity_type, entity_id, title, department_id, state, round, current_step, requested_by)
  VALUES (t.company_id, f.id, 'task', t.id, left('T-' || t.id || ' · ' || t.title, 300), t.department_id, 'pending', t.attempts + 1, 1, p_by)
  RETURNING * INTO r;
  INSERT INTO core.approval_decisions (request_id, round, step_no, step_name, decision, approver_user)
  SELECT r.id, r.round, s.step_no, s.name, 'pending', s.approver_user FROM core.approval_steps s WHERE s.flow_id = f.id;
  UPDATE work.tasks SET status = 'in_review', approval_status = 'pending', progress = 100, waiting_on_human = false, updated_at = now() WHERE id = t.id;
  RETURN 'in_review';
END $$;

-- ---------- Đăng nhập, mã mời ----------
CREATE OR REPLACE FUNCTION agent._invite_role(i core.invites) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = core, public AS $$
  SELECT CASE WHEN EXISTS (SELECT 1 FROM core.roles r WHERE r.id = ANY (i.role_ids) AND r.company_id IS NULL AND r.code = 'owner') THEN 'owner'
              WHEN EXISTS (SELECT 1 FROM core.roles r WHERE r.id = ANY (i.role_ids) AND r.company_id IS NULL AND r.code = 'admin') THEN 'admin'
              WHEN i.dept_head THEN 'manager' ELSE 'member' END
$$;

-- Dùng một mã mời cho một người: tạo thành viên + vai trò. Ném lỗi (P0001) nếu mã không dùng được.
CREATE OR REPLACE FUNCTION agent._invite_accept(p_user uuid, p_code text, p_email text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE i core.invites; rid uuid;
BEGIN
  SELECT * INTO i FROM core.invites WHERE code = upper(btrim(p_code));
  IF i.code IS NULL OR i.revoked OR i.expires_at <= now() OR i.uses >= i.max_uses OR (i.email IS NOT NULL AND lower(i.email) <> lower(p_email)) THEN
    RAISE EXCEPTION 'Mã mời không đúng, đã hết hạn, đã dùng hết hoặc không dành cho email này';
  END IF;
  IF EXISTS (SELECT 1 FROM core.memberships WHERE user_id = p_user AND company_id = i.company_id) THEN
    RAISE EXCEPTION 'Tài khoản này đã có trong công ty';
  END IF;
  UPDATE core.invites SET uses = uses + 1 WHERE code = i.code AND uses < max_uses;
  IF NOT FOUND THEN RAISE EXCEPTION 'Mã mời đã dùng hết'; END IF;
  INSERT INTO core.memberships (user_id, company_id, department_id, is_dept_head) VALUES (p_user, i.company_id, i.department_id, i.dept_head AND i.department_id IS NOT NULL);
  SELECT r.id INTO rid FROM core.roles r WHERE r.id = ANY (i.role_ids) AND (r.company_id IS NULL OR r.company_id = i.company_id) ORDER BY (r.code = 'owner') DESC, (r.code = 'admin') DESC LIMIT 1;
  INSERT INTO core.user_roles (company_id, user_id, role_id, granted_by) VALUES (i.company_id, p_user, coalesce(rid, agent._sys_role('member')), i.created_by) ON CONFLICT DO NOTHING;
  PERFORM agent._audit(i.company_id, p_user, 'join', 'user', p_user::text, 'Vào công ty bằng mã mời ' || i.code);
  RETURN i.company_id;
END $$;

-- Đăng nhập Google. Người đã có tài khoản vào thẳng; người mới cần mã mời hợp lệ. Mã mời cũng dùng được để vào thêm công ty khác.
CREATE OR REPLACE FUNCTION agent.app_login(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE em text := lower(btrim(coalesce(p->>'email', ''))); sb text := btrim(coalesce(p->>'sub', '')); nm text := btrim(coalesce(p->>'name', ''));
        av text := nullif(btrim(coalesce(p->>'avatar', '')), ''); inv text := upper(btrim(coalesce(p->>'invite', ''))); u core.users; cid uuid; inv_company uuid;
BEGIN
  IF em = '' OR sb = '' THEN RETURN jsonb_build_object('ok', false, 'reason', 'invalid'); END IF;
  SELECT * INTO u FROM core.users WHERE lower(email) = em ORDER BY (kind = 'person') DESC LIMIT 1;
  IF u.id IS NOT NULL THEN
    IF NOT u.active OR u.kind <> 'person' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_allowed'); END IF;
    IF u.google_sub IS NOT NULL AND u.google_sub <> sb THEN RETURN jsonb_build_object('ok', false, 'reason', 'sub_mismatch'); END IF;
    IF inv <> '' THEN
      SELECT i.company_id INTO inv_company FROM core.invites i WHERE i.code = inv;
      IF inv_company IS NULL OR NOT EXISTS (SELECT 1 FROM core.memberships m WHERE m.user_id = u.id AND m.company_id = inv_company) THEN
        BEGIN PERFORM agent._invite_accept(u.id, inv, em);
        EXCEPTION WHEN raise_exception THEN RETURN jsonb_build_object('ok', false, 'reason', 'invite_invalid', 'message', SQLERRM); END;
      END IF;
    END IF;
    UPDATE core.users SET google_sub = coalesce(google_sub, sb), last_login_at = now(), avatar_url = coalesce(avatar_url, av), name = coalesce(nullif(name, ''), nm) WHERE id = u.id;
  ELSE
    IF inv = '' THEN RETURN jsonb_build_object('ok', false, 'reason', 'invite_required'); END IF;
    BEGIN
      INSERT INTO core.users (google_sub, email, name, avatar_url, kind, last_login_at) VALUES (sb, em, coalesce(nullif(nm, ''), em), av, 'person', now()) RETURNING * INTO u;
      PERFORM agent._invite_accept(u.id, inv, em);
    EXCEPTION WHEN raise_exception THEN RETURN jsonb_build_object('ok', false, 'reason', 'invite_invalid', 'message', SQLERRM); END;
  END IF;
  SELECT m.company_id INTO cid FROM core.memberships m WHERE m.user_id = u.id AND m.active ORDER BY m.joined_at LIMIT 1;
  IF cid IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'no_company'); END IF;
  PERFORM agent._audit(cid, u.id, 'login', 'user', u.id::text, 'Đăng nhập web (Google)');
  RETURN jsonb_build_object('ok', true, 'user_id', u.id, 'name', u.name, 'email', u.email);
END $$;

-- Quy trình duyệt dựng sẵn cho mỗi công ty (để "Phải duyệt" có lựa chọn ngay, không cần quản trị tạo trước). Chỉ tạo khi chưa từng có (kể cả đã ngừng).
CREATE OR REPLACE FUNCTION agent._ensure_default_flows(p_company uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE v record; fid uuid;
BEGIN
  FOR v IN SELECT * FROM (VALUES ('Người giao duyệt', 'Người giao duyệt', 'creator', NULL::text), ('Trưởng phòng duyệt', 'Trưởng phòng duyệt', 'dept_head', NULL), ('Quản trị công ty duyệt', 'Quản trị công ty duyệt', 'role', 'admin')) x(flow_name, step_name, kind, rolecode) LOOP
    IF NOT EXISTS (SELECT 1 FROM core.approval_flows WHERE company_id = p_company AND name = v.flow_name AND applies_to = 'task') THEN
      INSERT INTO core.approval_flows (company_id, applies_to, name) VALUES (p_company, 'task', v.flow_name) RETURNING id INTO fid;
      INSERT INTO core.approval_steps (flow_id, step_no, name, approver_kind, approver_role) VALUES (fid, 1, v.step_name, v.kind, CASE WHEN v.rolecode IS NULL THEN NULL ELSE agent._sys_role(v.rolecode) END);
    END IF;
  END LOOP;
END $$;

-- ---------- Người dùng hiện tại và tổ chức ----------
CREATE OR REPLACE FUNCTION agent.app_me(p jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me();
BEGIN
  RETURN jsonb_build_object(
    'user', jsonb_build_object('id', me.id, 'name', me.name, 'email', me.email, 'avatar_url', me.avatar_url, 'drive_status', me.drive_state,
              'drive_folder_url', me.drive_folder_url, 'drive_note', me.drive_note, 'drive_checked_at', me.drive_checked_at, 'is_system_admin', me.is_system_admin),
    'memberships', coalesce((SELECT jsonb_agg(jsonb_build_object('company_id', c.id, 'company_name', coalesce(c.short_name, c.name), 'company_slug', c.slug,
                       'department_id', m.department_id, 'department_code', d.code, 'department_name', d.name, 'role', agent._role_of(me.id, c.id), 'title', m.title)
                       ORDER BY m.joined_at)
                FROM core.memberships m JOIN core.companies c ON c.id = m.company_id AND c.active LEFT JOIN core.departments d ON d.id = m.department_id
               WHERE m.user_id = me.id AND m.active), '[]'),
    'agents', coalesce((SELECT jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'description', g.description) ORDER BY g.code)
                          FROM agent.agents g
                         WHERE g.active AND EXISTS (SELECT 1 FROM agent.company_agents ca JOIN core.memberships m ON m.company_id = ca.company_id AND m.user_id = me.id AND m.active
                                                     WHERE ca.agent_id = g.id AND ca.enabled)), '[]'));
END $$;

CREATE OR REPLACE FUNCTION agent.app_org(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id');
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  PERFORM agent._ensure_default_flows(cid);
  RETURN jsonb_build_object(
    'departments', coalesce((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'code', d.code, 'name', d.name, 'active', d.active, 'parent_id', d.parent_id) ORDER BY d.code)
                               FROM core.departments d WHERE d.company_id = cid), '[]'),
    'members', coalesce((SELECT jsonb_agg(jsonb_build_object('user_id', m.user_id, 'department_id', m.department_id, 'role', agent._role_raw(m.user_id, cid), 'title', m.title,
                       'active', m.active, 'user', jsonb_build_object('id', u.id, 'name', u.name, 'email', u.email, 'avatar_url', u.avatar_url, 'drive_status', u.drive_state, 'active', u.active))
                       ORDER BY u.name)
                  FROM core.memberships m JOIN core.users u ON u.id = m.user_id WHERE m.company_id = cid AND u.kind = 'person'), '[]'),
    'projects', coalesce((SELECT jsonb_agg(jsonb_build_object('id', pr.id, 'slug', pr.slug, 'code', pr.code, 'name', pr.name, 'department_id', pr.department_id, 'drive_url', pr.drive_url,
                       'description', pr.description, 'status', pr.status, 'manager_id', pr.manager_id, 'start_date', pr.start_date, 'end_date', pr.end_date,
                       'active', pr.status IN ('planned','active','paused'), 'can_manage', agent._can_manage_project(me.id, pr)) ORDER BY pr.name)
                  FROM core.projects pr WHERE pr.company_id = cid), '[]'),
    'project_members', coalesce((SELECT jsonb_agg(jsonb_build_object('project_id', x.project_id, 'user_id', x.user_id, 'role', x.role))
                  FROM core.project_members x JOIN core.projects pr ON pr.id = x.project_id WHERE pr.company_id = cid), '[]'),
    'flows', coalesce((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'department_id', f.department_id, 'active', f.active,
                       'steps', coalesce((SELECT jsonb_agg(jsonb_build_object('step_no', s.step_no, 'name', s.name, 'approver_user', s.approver_user,
                                 'approver_role', CASE s.approver_kind WHEN 'dept_head' THEN 'manager' WHEN 'creator' THEN 'creator' WHEN 'project_manager' THEN 'project_manager'
                                                  WHEN 'role' THEN (SELECT r.code FROM core.roles r WHERE r.id = s.approver_role) END) ORDER BY s.step_no)
                                    FROM core.approval_steps s WHERE s.flow_id = f.id), '[]')) ORDER BY f.name)
                  FROM core.approval_flows f WHERE f.company_id = cid AND f.active AND f.applies_to IN ('task','any')), '[]'));
END $$;

-- ---------- Việc ----------
CREATE OR REPLACE FUNCTION agent.app_tasks(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); days int := least(greatest(coalesce((p->>'days')::int, 60), 1), 400);
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  RETURN coalesce((SELECT jsonb_agg(agent._task_json(v) ORDER BY v.updated_at DESC) FROM agent._visible_tasks(me.id, cid, days, 1500) v), '[]');
END $$;

CREATE OR REPLACE FUNCTION agent.app_task(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; r core.approval_requests; can_appr boolean := false; flow_steps int;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = (p->>'id')::bigint;
  IF t.id IS NULL OR NOT agent._can_see(me.id, t) THEN RAISE EXCEPTION 'Không tìm thấy việc hoặc bạn không có quyền xem' USING ERRCODE = '42501'; END IF;
  SELECT * INTO r FROM core.approval_requests WHERE entity_type = 'task' AND entity_id = t.id ORDER BY id DESC LIMIT 1;
  IF r.id IS NOT NULL AND r.state = 'pending' THEN
    can_appr := agent._can_approve_step(me.id, r, (SELECT s FROM core.approval_steps s WHERE s.flow_id = r.flow_id AND s.step_no = r.current_step));
  END IF;
  RETURN jsonb_build_object(
    'task', agent._task_json(t),
    'comments', coalesce((SELECT jsonb_agg(jsonb_build_object('id', c.id, 'user_id', c.user_id, 'actor', c.actor, 'kind', c.kind, 'body', c.body, 'created_at', c.created_at) ORDER BY c.id)
                            FROM work.comments c WHERE c.task_id = t.id), '[]'),
    'links', coalesce((SELECT jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'title', l.title, 'added_by', l.added_by, 'created_at', l.created_at) ORDER BY l.id)
                         FROM work.task_links l WHERE l.task_id = t.id), '[]'),
    'files', coalesce((SELECT jsonb_agg(jsonb_build_object('file_id', f.id, 'name', f.name, 'web_url', f.web_url, 'owner_user', f.owner_user, 'modified_at', f.modified_at, 'role', a.role) ORDER BY f.id DESC)
                         FROM core.attachments a JOIN core.files f ON f.id = a.file_id WHERE a.entity_type = 'task' AND a.entity_id = t.id::text), '[]'),
    'children', coalesce((SELECT jsonb_agg(agent._task_json(k) ORDER BY k.id) FROM work.tasks k WHERE k.parent_id = t.id AND agent._can_see(me.id, k)), '[]'),
    'approvals', CASE WHEN r.id IS NULL THEN '[]'::jsonb ELSE coalesce((SELECT jsonb_agg(jsonb_build_object('step_no', d.step_no, 'step_name', d.step_name, 'decision', d.decision,
                    'decided_by', d.decided_by, 'decided_at', d.decided_at, 'note', d.note) ORDER BY d.step_no)
                    FROM core.approval_decisions d WHERE d.request_id = r.id AND d.round = r.round), '[]') END,
    'checklist', coalesce((SELECT jsonb_agg(jsonb_build_object('id', ci.id, 'title', ci.title, 'done', ci.done) ORDER BY ci.position) FROM work.checklist_items ci WHERE ci.task_id = t.id), '[]'),
    'watchers', coalesce((SELECT jsonb_agg(w.user_id) FROM work.task_watchers w JOIN core.users u ON u.id = w.user_id WHERE w.task_id = t.id), '[]'),
    'activity', coalesce((SELECT jsonb_agg(jsonb_build_object('at', x.at, 'summary', x.summary, 'ai', x.actor LIKE 'agent:%',
                  'who', CASE WHEN x.actor LIKE 'user:%' THEN (SELECT name FROM core.users WHERE id = substring(x.actor from 6)::uuid) WHEN x.actor LIKE 'agent:%' THEN (SELECT g2.name FROM agent.agents g2 WHERE g2.code = substring(x.actor from 7)) ELSE 'Hệ thống' END) ORDER BY x.at DESC)
                  FROM (SELECT * FROM core.audit_log al WHERE al.entity_type = 'task' AND al.entity_id = t.id::text ORDER BY al.at DESC, al.id DESC LIMIT 30) x), '[]'),
    'approval_state', r.state,
    'can_approve', can_appr AND t.status = 'in_review',
    'can_edit', agent._can_edit(me.id, t),
    'can_submit', t.status IN ('todo','in_progress','blocked') AND t.agent_id IS NULL AND (t.assignee_id = me.id OR agent._can_edit(me.id, t)),   -- việc giao agent: agent nộp, người xem và chấp nhận
    'can_answer', t.waiting_on_human AND t.status NOT IN ('done','cancelled') AND (t.assignee_id = me.id OR t.created_by = me.id OR agent._can_edit(me.id, t)),
    'can_review', t.status = 'in_review' AND t.agent_id IS NOT NULL AND r.state IS DISTINCT FROM 'pending'
                  AND me.id IS NOT DISTINCT FROM coalesce(t.created_by, (SELECT default_reviewer FROM agent.company_settings WHERE company_id = t.company_id)),
    'flow_steps', (SELECT count(*) FROM core.approval_steps s WHERE s.flow_id = t.approval_flow_id),
    'workflow', (SELECT jsonb_build_object('run_id', x.run_id, 'skill', x.skill, 'scope', x.scope, 'created_by', x.created_by) FROM agent.task_scopes x WHERE x.task_id = t.id),   -- phạm vi ghi bởi quy trình dự án (db/62)
    'reports', coalesce((SELECT jsonb_agg(jsonb_build_object('at', x.created_at, 'agent', (SELECT code FROM agent.agents WHERE id = x.agent_id), 'summary', x.summary, 'outputs', x.outputs,
                          'sources', x.sources, 'checks', x.checks, 'confidence', x.confidence, 'residual_risk', x.residual_risk, 'next_actions', x.next_actions, 'verdict', x.verdict)
                          ORDER BY x.created_at DESC) FROM agent.reports x WHERE x.task_id = t.id), '[]'));
END $$;

-- Tạo (không có id) hoặc sửa (có id) một việc. Trường không gửi thì giữ nguyên; chuỗi rỗng = bỏ giá trị.
CREATE OR REPLACE FUNCTION agent.app_task_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; cid uuid; v_title text; v_desc text; v_dept uuid; v_asg uuid; v_proj uuid; v_flow uuid; v_parent bigint;
        v_due date; v_start date; v_imp boolean; v_urg boolean; v_est int; chg text[] := '{}'; sl jsonb := '{"todo":"Chờ làm","in_progress":"Đang làm","blocked":"Vướng","in_review":"Chờ duyệt","done":"Xong","cancelled":"Đã hủy"}'; v_prio work.task_priority; v_agent uuid; v_status work.task_status; ag_code text; new_id bigint;
BEGIN
  IF (p->>'id') IS NOT NULL THEN
    SELECT * INTO t FROM work.tasks WHERE id = (p->>'id')::bigint FOR UPDATE;
    IF t.id IS NULL OR NOT agent._can_see(me.id, t) THEN RAISE EXCEPTION 'Không tìm thấy việc' USING ERRCODE = '42501'; END IF;
    IF NOT agent._can_edit(me.id, t) THEN RAISE EXCEPTION 'Bạn không có quyền sửa T-%', t.id USING ERRCODE = '42501'; END IF;
    cid := t.company_id;
  ELSE
    cid := agent._uuid(p, 'company_id');
    PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  END IF;
  v_title := CASE WHEN p ? 'title' OR t.id IS NULL THEN btrim(coalesce(p->>'title', '')) ELSE t.title END;
  IF length(v_title) < 2 OR length(v_title) > 300 THEN RAISE EXCEPTION 'Tên việc từ 2 đến 300 ký tự'; END IF;
  v_desc := CASE WHEN p ? 'description' THEN nullif(btrim(p->>'description'), '') ELSE t.description END;
  IF length(coalesce(v_desc, '')) > 8000 THEN RAISE EXCEPTION 'Mô tả tối đa 8000 ký tự'; END IF;
  v_dept   := CASE WHEN p ? 'department_id'    THEN agent._uuid(p, 'department_id')    WHEN t.id IS NULL THEN (SELECT department_id FROM core.memberships WHERE user_id = me.id AND company_id = cid) ELSE t.department_id END;
  v_asg    := CASE WHEN p ? 'assignee_id'      THEN agent._uuid(p, 'assignee_id')      ELSE t.assignee_id END;
  v_proj   := CASE WHEN p ? 'project_id'       THEN agent._uuid(p, 'project_id')       ELSE t.project_id END;
  v_flow   := CASE WHEN p ? 'approval_flow_id' THEN agent._uuid(p, 'approval_flow_id') ELSE t.approval_flow_id END;
  v_parent := CASE WHEN t.id IS NULL THEN nullif(btrim(coalesce(p->>'parent_id', '')), '')::bigint ELSE t.parent_id END;
  v_due    := CASE WHEN p ? 'due_date' THEN nullif(btrim(coalesce(p->>'due_date', '')), '')::date ELSE t.due_date END;
  v_start  := CASE WHEN p ? 'start_date' THEN nullif(btrim(coalesce(p->>'start_date', '')), '')::date ELSE t.start_date END;
  IF v_start IS NOT NULL AND v_due IS NOT NULL AND v_due < v_start THEN RAISE EXCEPTION 'Hạn chót phải sau hoặc bằng ngày bắt đầu'; END IF;
  -- Ma trận Eisenhower: Quan trọng / Khẩn cấp (ai sửa được việc thì đặt được cờ; kéo thả ô Eisenhower cũng đi qua đây)
  v_est    := CASE WHEN p ? 'est_minutes' THEN nullif(btrim(coalesce(p->>'est_minutes', '')), '')::int ELSE t.est_minutes END;
  IF v_est IS NOT NULL AND v_est NOT BETWEEN 1 AND 43200 THEN RAISE EXCEPTION 'Thời lượng từ 1 phút đến 30 ngày'; END IF;
  v_imp    := CASE WHEN p ? 'important' THEN coalesce((p->>'important')::boolean, false) ELSE coalesce(t.important, false) END;
  v_urg    := CASE WHEN p ? 'urgent'    THEN coalesce((p->>'urgent')::boolean, false)    ELSE coalesce(t.urgent, false) END;
  v_prio   := CASE WHEN p ? 'priority' THEN (p->>'priority')::work.task_priority WHEN t.id IS NULL THEN 'medium' ELSE t.priority END;
  IF v_dept IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.departments WHERE id = v_dept AND company_id = cid) THEN RAISE EXCEPTION 'Phòng ban không thuộc công ty này'; END IF;
  IF v_asg IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.memberships WHERE user_id = v_asg AND company_id = cid AND active) THEN RAISE EXCEPTION 'Người phụ trách không thuộc công ty này'; END IF;
  IF v_proj IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.projects WHERE id = v_proj AND company_id = cid) THEN RAISE EXCEPTION 'Dự án không thuộc công ty này'; END IF;
  IF v_flow IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.approval_flows WHERE id = v_flow AND company_id = cid AND active AND applies_to IN ('task','any')
                                          AND (department_id IS NULL OR department_id IS NOT DISTINCT FROM v_dept)) THEN RAISE EXCEPTION 'Quy trình duyệt không áp dụng cho việc này'; END IF;
  IF v_parent IS NOT NULL AND NOT EXISTS (SELECT 1 FROM work.tasks WHERE id = v_parent AND company_id = cid) THEN RAISE EXCEPTION 'Việc cha không thuộc công ty này'; END IF;
  IF t.id IS NOT NULL AND v_flow IS DISTINCT FROM t.approval_flow_id AND t.status IN ('in_review','done') THEN RAISE EXCEPTION 'Việc đang chờ duyệt hoặc đã xong, không đổi quy trình duyệt được'; END IF;
  v_agent := t.agent_id;
  IF p ? 'agent_role' OR t.id IS NULL THEN
    ag_code := nullif(btrim(coalesce(p->>'agent_role', '')), '');
    IF ag_code IS NULL THEN v_agent := NULL;
    ELSE
      SELECT g.id INTO v_agent FROM agent.agents g JOIN agent.company_agents ca ON ca.agent_id = g.id AND ca.company_id = cid AND ca.enabled WHERE g.code = ag_code AND g.active;
      IF v_agent IS NULL THEN RAISE EXCEPTION 'Agent % chưa được bật cho công ty', ag_code; END IF;
    END IF;
  END IF;

  IF t.id IS NULL THEN
    IF v_agent IS NOT NULL AND v_asg IS NULL THEN v_asg := me.id; END IF;
    INSERT INTO work.tasks (company_id, department_id, project_id, parent_id, title, description, priority, assignee_id, agent_id, agent_role, approval_flow_id, due_date, start_date, important, urgent, est_minutes, created_by)
    VALUES (cid, v_dept, v_proj, v_parent, v_title, v_desc, v_prio, v_asg, v_agent, ag_code, v_flow, v_due, v_start, v_imp, v_urg, v_est, me.id) RETURNING id INTO new_id;
    PERFORM agent._audit(cid, me.id, 'create', 'task', new_id::text, 'Giao việc T-' || new_id || CASE WHEN ag_code IS NOT NULL THEN ' cho agent ' || ag_code ELSE '' END);
    RETURN jsonb_build_object('id', new_id);
  END IF;

  IF v_agent IS DISTINCT FROM t.agent_id THEN
    IF t.status <> 'todo' THEN RAISE EXCEPTION 'Chỉ đổi agent khi việc đang ở Chờ làm'; END IF;
    IF EXISTS (SELECT 1 FROM agent.cards WHERE task_id = t.id AND status NOT IN ('done','archived','gave_up','crashed','timed_out','cancelled')) THEN
      RAISE EXCEPTION 'Agent đang chạy việc này, chưa đổi được';
    END IF;
  END IF;
  v_status := t.status;
  IF p ? 'status' AND (p->>'status')::work.task_status IS DISTINCT FROM t.status THEN
    IF t.status NOT IN ('todo','in_progress','blocked') OR (p->>'status') NOT IN ('todo','in_progress','blocked','cancelled') THEN
      RAISE EXCEPTION 'Không đổi được từ % sang %', t.status, p->>'status';
    END IF;
    v_status := (p->>'status')::work.task_status;
  END IF;
  UPDATE work.tasks SET title = v_title, description = v_desc, department_id = v_dept, assignee_id = v_asg, project_id = v_proj, approval_flow_id = v_flow,
         due_date = v_due, start_date = v_start, important = v_imp, urgent = v_urg, est_minutes = v_est, priority = v_prio, agent_id = v_agent, agent_role = coalesce(ag_code, CASE WHEN v_agent IS NULL THEN NULL ELSE agent_role END),
         status = v_status, waiting_on_human = CASE WHEN v_status IS DISTINCT FROM t.status THEN false ELSE waiting_on_human END, updated_at = now()
   WHERE id = t.id;
  IF v_title IS DISTINCT FROM t.title THEN chg := array_append(chg, 'tên việc'::text); END IF;
  IF v_status IS DISTINCT FROM t.status THEN chg := array_append(chg, ('trạng thái ' || (sl->>t.status::text) || ' → ' || (sl->>v_status::text))::text); END IF;
  IF v_asg IS DISTINCT FROM t.assignee_id THEN chg := array_append(chg, ('người phụ trách → ' || coalesce((SELECT name FROM core.users WHERE id = v_asg), 'chưa giao'))::text); END IF;
  IF v_due IS DISTINCT FROM t.due_date THEN chg := array_append(chg, ('hạn ' || coalesce(to_char(t.due_date, 'DD/MM'), 'không') || ' → ' || coalesce(to_char(v_due, 'DD/MM'), 'không'))::text); END IF;
  IF v_prio IS DISTINCT FROM t.priority THEN chg := array_append(chg, ('ưu tiên ' || t.priority || ' → ' || v_prio)::text); END IF;
  IF v_imp IS DISTINCT FROM t.important OR v_urg IS DISTINCT FROM t.urgent THEN chg := array_append(chg, 'ma trận Eisenhower'::text); END IF;
  IF v_proj IS DISTINCT FROM t.project_id THEN chg := array_append(chg, 'dự án'::text); END IF;
  IF v_est IS DISTINCT FROM t.est_minutes THEN chg := array_append(chg, 'thời lượng'::text); END IF;
  IF v_desc IS DISTINCT FROM t.description OR v_dept IS DISTINCT FROM t.department_id OR v_start IS DISTINCT FROM t.start_date OR v_flow IS DISTINCT FROM t.approval_flow_id OR v_agent IS DISTINCT FROM t.agent_id THEN chg := array_append(chg, 'chi tiết khác'::text); END IF;
  PERFORM agent._audit(cid, me.id, 'update', 'task', t.id::text, 'Sửa T-' || t.id || CASE WHEN cardinality(chg) > 0 THEN ': ' || array_to_string(chg, '; ') ELSE '' END);
  RETURN jsonb_build_object('id', t.id);
END $$;

CREATE OR REPLACE FUNCTION agent.app_submit(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; note text := nullif(btrim(coalesce(p->>'note', '')), ''); res text;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = (p->>'task')::bigint FOR UPDATE;
  IF t.id IS NULL OR NOT agent._can_see(me.id, t) THEN RAISE EXCEPTION 'Không tìm thấy việc' USING ERRCODE = '42501'; END IF;
  IF NOT (t.assignee_id = me.id OR agent._can_edit(me.id, t)) THEN RAISE EXCEPTION 'Chỉ người phụ trách hoặc người có quyền sửa mới nộp được' USING ERRCODE = '42501'; END IF;
  IF t.status NOT IN ('todo','in_progress','blocked') THEN RAISE EXCEPTION 'Việc đang % nên không nộp được', t.status; END IF;
  IF t.agent_id IS NOT NULL THEN RAISE EXCEPTION 'Việc đang giao cho agent: trả lời câu hỏi của agent hoặc chờ agent nộp kết quả. Muốn tự làm thì vào Sửa và bỏ giao agent.'; END IF;
  IF note IS NULL AND NOT EXISTS (SELECT 1 FROM work.task_links WHERE task_id = t.id) AND NOT EXISTS (SELECT 1 FROM core.attachments WHERE entity_type = 'task' AND entity_id = t.id::text) THEN
    RAISE EXCEPTION 'Ghi kết quả (tóm tắt) hoặc gắn link tài liệu trước khi nộp';
  END IF;
  IF note IS NOT NULL THEN UPDATE work.tasks SET result = left(note, 4000) WHERE id = t.id; END IF;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (t.id, me.id, 'user:' || me.id, 'submit', left(coalesce(note, 'Nộp kết quả'), 8000));
  res := agent._approval_start(t.id, me.id);
  PERFORM agent._audit(t.company_id, me.id, 'submit', 'task', t.id::text, 'Nộp T-' || t.id || ' → ' || res);
  RETURN jsonb_build_object('status', res);
END $$;

-- Duyệt hoặc trả lại bước hiện tại
CREATE OR REPLACE FUNCTION agent.app_decide(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; r core.approval_requests; s core.approval_steps; ok boolean := coalesce((p->>'approve')::boolean, false);
        nt text := nullif(btrim(coalesce(p->>'note', '')), ''); nxt int;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = (p->>'task')::bigint FOR UPDATE;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy việc' USING ERRCODE = '42501'; END IF;
  SELECT * INTO r FROM core.approval_requests WHERE entity_type = 'task' AND entity_id = t.id AND state = 'pending' ORDER BY id DESC LIMIT 1 FOR UPDATE;
  IF r.id IS NULL OR t.status <> 'in_review' THEN RAISE EXCEPTION 'Việc này không có bước duyệt nào đang chờ'; END IF;
  SELECT * INTO s FROM core.approval_steps WHERE flow_id = r.flow_id AND step_no = r.current_step;
  IF NOT agent._can_approve_step(me.id, r, s) THEN RAISE EXCEPTION 'Bạn không phải người duyệt bước này' USING ERRCODE = '42501'; END IF;
  IF NOT ok AND length(coalesce(nt, '')) < 3 THEN RAISE EXCEPTION 'Ghi lý do trả lại để người làm biết cần sửa gì'; END IF;
  UPDATE core.approval_decisions SET decision = CASE WHEN ok THEN 'approved'::core.decision ELSE 'rejected'::core.decision END, decided_by = me.id, decided_at = now(), note = left(nt, 1000)
   WHERE request_id = r.id AND round = r.round AND step_no = r.current_step;
  IF ok THEN
    INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (t.id, me.id, 'user:' || me.id, 'approve', left('Duyệt bước ' || s.step_no || ' (' || s.name || ')' || coalesce(': ' || nt, ''), 8000));
    SELECT min(step_no) INTO nxt FROM core.approval_steps WHERE flow_id = r.flow_id AND step_no > r.current_step;
    IF nxt IS NOT NULL THEN
      UPDATE core.approval_requests SET current_step = nxt WHERE id = r.id;
      UPDATE work.tasks SET updated_at = now() WHERE id = t.id;
      RETURN jsonb_build_object('status', 'in_review', 'step', nxt);
    END IF;
    UPDATE core.approval_requests SET state = 'approved', closed_at = now() WHERE id = r.id;
    UPDATE agent.reports SET verdict = 'accepted' WHERE task_id = t.id AND verdict = 'pending';
    UPDATE work.tasks SET approval_status = 'approved', status = 'done', completed_at = now(), progress = 100, updated_at = now() WHERE id = t.id;
    PERFORM agent._audit(t.company_id, me.id, 'approve', 'task', t.id::text, 'Duyệt xong T-' || t.id);
    RETURN jsonb_build_object('status', 'done');
  END IF;
  UPDATE core.approval_requests SET state = 'rejected', closed_at = now() WHERE id = r.id;
  UPDATE core.approval_decisions SET decision = 'skipped' WHERE request_id = r.id AND round = r.round AND decision = 'pending';
  UPDATE work.tasks SET approval_status = 'rejected' WHERE id = t.id;
  IF t.agent_id IS NOT NULL THEN
    -- việc của agent: bình luận 'reject' kích hoạt vòng làm lại (agent.comments_relay_trg), hoặc trả về người khi quá số lần
    INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (t.id, me.id, 'user:' || me.id, 'reject', left('Trả lại ở bước ' || s.step_no || ': ' || nt, 8000));
  ELSE
    INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (t.id, me.id, 'user:' || me.id, 'reject', left('Trả lại ở bước ' || s.step_no || ': ' || nt, 8000));
    UPDATE work.tasks SET status = 'in_progress', approval_status = 'rejected', attempts = attempts + 1, updated_at = now() WHERE id = t.id;
  END IF;
  PERFORM agent._audit(t.company_id, me.id, 'reject', 'task', t.id::text, 'Trả lại T-' || t.id);
  RETURN jsonb_build_object('status', (SELECT status FROM work.tasks WHERE id = t.id));
END $$;

CREATE OR REPLACE FUNCTION agent.app_answer(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; body text := btrim(coalesce(p->>'body', ''));
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = (p->>'task')::bigint;
  IF t.id IS NULL OR NOT agent._can_see(me.id, t) THEN RAISE EXCEPTION 'Không tìm thấy việc' USING ERRCODE = '42501'; END IF;
  IF NOT (t.waiting_on_human AND t.status NOT IN ('done','cancelled')) THEN RAISE EXCEPTION 'Agent không đang chờ trả lời việc này'; END IF;
  IF NOT (t.assignee_id = me.id OR t.created_by = me.id OR agent._can_edit(me.id, t)) THEN RAISE EXCEPTION 'Chỉ người phụ trách hoặc người giao trả lời được' USING ERRCODE = '42501'; END IF;
  IF body = '' THEN RAISE EXCEPTION 'Nhập câu trả lời'; END IF;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (t.id, me.id, 'user:' || me.id, 'answer', left(body, 8000));   -- trigger chuyển câu trả lời cho agent
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION agent.app_comment(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; body text := btrim(coalesce(p->>'body', '')); nid bigint;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = (p->>'task')::bigint;
  IF t.id IS NULL OR NOT agent._can_see(me.id, t) THEN RAISE EXCEPTION 'Không tìm thấy việc' USING ERRCODE = '42501'; END IF;
  IF body = '' THEN RAISE EXCEPTION 'Nhập nội dung ghi chú'; END IF;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (t.id, me.id, 'user:' || me.id, 'note', left(body, 8000)) RETURNING work.comments.id INTO nid;
  RETURN jsonb_build_object('id', nid);
END $$;

CREATE OR REPLACE FUNCTION agent.app_link_add(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; u text := btrim(coalesce(p->>'url', '')); ttl text := nullif(btrim(coalesce(p->>'title', '')), ''); nid bigint;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = (p->>'task')::bigint;
  IF t.id IS NULL OR NOT agent._can_see(me.id, t) THEN RAISE EXCEPTION 'Không tìm thấy việc' USING ERRCODE = '42501'; END IF;
  IF u !~ '^https://[^[:space:]]+$' OR length(u) > 2000 THEN RAISE EXCEPTION 'Link phải bắt đầu bằng https://'; END IF;
  INSERT INTO work.task_links (task_id, url, title, added_by, actor) VALUES (t.id, u, left(coalesce(ttl, substring(u from '^https://([^/]+)'), 'Tài liệu'), 200), me.id, 'user:' || me.id) RETURNING work.task_links.id INTO nid;
  RETURN jsonb_build_object('id', nid);
END $$;

CREATE OR REPLACE FUNCTION agent.app_link_remove(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); l work.task_links; t work.tasks;
BEGIN
  SELECT * INTO l FROM work.task_links WHERE id = (p->>'link')::bigint;
  SELECT * INTO t FROM work.tasks WHERE id = l.task_id;
  IF l.id IS NULL OR NOT agent._can_see(me.id, t) THEN RAISE EXCEPTION 'Không tìm thấy link' USING ERRCODE = '42501'; END IF;
  IF NOT (l.added_by = me.id OR agent._can_edit(me.id, t)) THEN RAISE EXCEPTION 'Bạn không có quyền gỡ link này' USING ERRCODE = '42501'; END IF;
  DELETE FROM work.task_links WHERE id = l.id;
  RETURN jsonb_build_object('ok', true);
END $$;

-- Kết quả của agent: người giao chấp nhận / trả lại (bao quanh agent.accept_result / reject_result)
CREATE OR REPLACE FUNCTION agent.app_accept(p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
BEGIN PERFORM agent._web_me(); RETURN jsonb_build_object('status', agent.accept_result((p->>'task')::bigint, nullif(btrim(coalesce(p->>'note', '')), ''))); END $$;
CREATE OR REPLACE FUNCTION agent.app_reject(p jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
BEGIN PERFORM agent._web_me(); RETURN jsonb_build_object('status', agent.reject_result((p->>'task')::bigint, p->>'reason')); END $$;

-- Hộp "Duyệt": các bước đang chờ tôi, kết quả agent chờ tôi xem, và việc tôi đã xử lý trong 30 ngày
CREATE OR REPLACE FUNCTION agent.app_my_approvals(p jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); out jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(x ORDER BY (x->'task'->>'updated_at') DESC), '[]') INTO out FROM (
    SELECT jsonb_build_object('kind', 'approval', 'task_id', t.id, 'task', agent._task_json(t), 'step_no', r.current_step, 'steps', (SELECT count(*) FROM core.approval_steps WHERE flow_id = r.flow_id),
             'step_name', s.name,
             'result', (SELECT jsonb_build_object('user_id', c.user_id, 'actor', c.actor, 'body', c.body, 'created_at', c.created_at) FROM work.comments c WHERE c.task_id = t.id AND c.kind IN ('submit','result') ORDER BY c.id DESC LIMIT 1),
             'links', coalesce((SELECT jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'title', l.title) ORDER BY l.id) FROM work.task_links l WHERE l.task_id = t.id), '[]')) x
      FROM core.approval_requests r JOIN core.approval_steps s ON s.flow_id = r.flow_id AND s.step_no = r.current_step JOIN work.tasks t ON t.id = r.entity_id
     WHERE r.entity_type = 'task' AND r.state = 'pending' AND t.status = 'in_review'
       AND EXISTS (SELECT 1 FROM core.memberships m WHERE m.user_id = me.id AND m.company_id = r.company_id AND m.active)
       AND agent._can_approve_step(me.id, r, s)
    UNION ALL
    SELECT jsonb_build_object('kind', 'review', 'task_id', t.id, 'task', agent._task_json(t), 'step_no', 0, 'steps', 0, 'step_name', 'Xem kết quả của agent',
             'result', (SELECT jsonb_build_object('user_id', c.user_id, 'actor', c.actor, 'body', c.body, 'created_at', c.created_at) FROM work.comments c WHERE c.task_id = t.id AND c.kind IN ('submit','result') ORDER BY c.id DESC LIMIT 1),
             'links', coalesce((SELECT jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'title', l.title) ORDER BY l.id) FROM work.task_links l WHERE l.task_id = t.id), '[]'))
      FROM work.tasks t
     WHERE t.status = 'in_review' AND t.agent_id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM core.approval_requests r WHERE r.entity_type = 'task' AND r.entity_id = t.id AND r.state = 'pending')
       AND me.id IS NOT DISTINCT FROM coalesce(t.created_by, (SELECT default_reviewer FROM agent.company_settings WHERE company_id = t.company_id))
       AND EXISTS (SELECT 1 FROM core.memberships m WHERE m.user_id = me.id AND m.company_id = t.company_id AND m.active)) q;
  RETURN jsonb_build_object('items', out,
    'recent', coalesce((SELECT jsonb_agg(agent._task_json(t) ORDER BY d.decided_at DESC) FROM (
                  SELECT DISTINCT ON (r.entity_id) r.entity_id, d.decided_at FROM core.approval_decisions d JOIN core.approval_requests r ON r.id = d.request_id AND r.entity_type = 'task'
                   WHERE d.decided_by = me.id AND d.decided_at > now() - interval '30 days' ORDER BY r.entity_id, d.decided_at DESC) d
                  JOIN work.tasks t ON t.id = d.entity_id WHERE agent._can_see(me.id, t)), '[]'));
END $$;

-- ---------- Báo cáo ----------
CREATE OR REPLACE FUNCTION agent.app_report(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); today date;
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  today := (now() AT TIME ZONE (SELECT timezone FROM core.companies WHERE id = cid))::date;
  RETURN jsonb_build_object(
    'depts', coalesce((SELECT jsonb_agg(to_jsonb(q)) FROM (
        SELECT v.department_id,
               count(*) FILTER (WHERE v.status NOT IN ('done','cancelled'))::int AS open,
               count(*) FILTER (WHERE v.status NOT IN ('done','cancelled') AND v.due_date < today)::int AS overdue,
               count(*) FILTER (WHERE v.status = 'blocked')::int AS blocked,
               count(*) FILTER (WHERE v.status = 'in_review')::int AS in_review,
               count(*) FILTER (WHERE v.status = 'done' AND v.completed_at > now() - interval '30 days')::int AS done_30d,
               count(*) FILTER (WHERE v.status = 'done' AND v.completed_at > now() - interval '30 days' AND (v.due_date IS NULL OR (v.completed_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date <= v.due_date))::int AS done_on_time_30d,
               round((avg(extract(epoch FROM v.completed_at - v.created_at) / 86400) FILTER (WHERE v.status = 'done' AND v.completed_at > now() - interval '30 days'))::numeric, 1) AS avg_days_30d
          FROM agent._visible_tasks(me.id, cid) v GROUP BY v.department_id) q), '[]'),
    'people', coalesce((SELECT jsonb_agg(to_jsonb(q) ORDER BY q.open DESC) FROM (
        SELECT v.assignee_id AS user_id,
               count(*) FILTER (WHERE v.status NOT IN ('done','cancelled'))::int AS open,
               count(*) FILTER (WHERE v.status NOT IN ('done','cancelled') AND v.due_date < today)::int AS overdue,
               count(*) FILTER (WHERE v.status = 'done' AND v.completed_at > now() - interval '30 days')::int AS done_30d
          FROM agent._visible_tasks(me.id, cid) v WHERE v.assignee_id IS NOT NULL GROUP BY v.assignee_id) q), '[]'));
END $$;

-- ---------- Quản trị: phòng ban, thành viên, mã mời, quy trình duyệt, dự án ----------
CREATE OR REPLACE FUNCTION agent.app_dept_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); did uuid := agent._uuid(p, 'id'); cd text := btrim(coalesce(p->>'code', '')); nm text := btrim(coalesce(p->>'name', ''));
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin']);
  IF cd !~ '^[A-Za-z0-9_-]{1,12}$' THEN RAISE EXCEPTION 'Mã phòng tối đa 12 ký tự: chữ, số, gạch nối'; END IF;
  IF length(nm) < 2 OR length(nm) > 120 THEN RAISE EXCEPTION 'Tên phòng ban từ 2 đến 120 ký tự'; END IF;
  IF did IS NULL THEN
    INSERT INTO core.departments (company_id, code, name) VALUES (cid, upper(cd), nm) RETURNING departments.id INTO did;
  ELSE
    UPDATE core.departments SET code = upper(cd), name = nm, active = coalesce((p->>'active')::boolean, active) WHERE departments.id = did AND company_id = cid;
    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy phòng ban'; END IF;
  END IF;
  PERFORM agent._audit(cid, me.id, 'dept_save', 'department', did::text, 'Lưu phòng ban ' || upper(cd));
  RETURN jsonb_build_object('id', did);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'Mã phòng % đã có', upper(cd);
END $$;

CREATE OR REPLACE FUNCTION agent.app_member_set(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); uid uuid := agent._uuid(p, 'user_id'); my text; cur text; nr text := coalesce(p->>'role', 'member');
        dept uuid := agent._uuid(p, 'department_id'); act boolean := coalesce((p->>'active')::boolean, true);
BEGIN
  my := agent._need_role(me.id, cid, ARRAY['owner','admin']);
  cur := agent._role_raw(uid, cid);
  IF cur IS NULL THEN RAISE EXCEPTION 'Người này không thuộc công ty'; END IF;
  IF nr NOT IN ('owner','admin','manager','member') THEN RAISE EXCEPTION 'Vai trò không hợp lệ'; END IF;
  IF uid = me.id AND (nr <> cur OR NOT act) THEN RAISE EXCEPTION 'Không tự đổi vai trò hoặc tự khóa chính mình'; END IF;
  IF my = 'admin' AND (cur = 'owner' OR nr = 'owner') THEN RAISE EXCEPTION 'Chỉ chủ sở hữu mới đổi được chủ sở hữu' USING ERRCODE = '42501'; END IF;
  IF cur = 'owner' AND (nr <> 'owner' OR NOT act) AND NOT EXISTS (
       SELECT 1 FROM core.memberships m JOIN core.user_roles ur ON ur.user_id = m.user_id AND ur.company_id = m.company_id
        WHERE m.company_id = cid AND m.active AND m.user_id <> uid AND ur.role_id = agent._sys_role('owner')) THEN
    RAISE EXCEPTION 'Công ty phải còn ít nhất một chủ sở hữu';
  END IF;
  IF dept IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.departments WHERE id = dept AND company_id = cid) THEN RAISE EXCEPTION 'Phòng ban không thuộc công ty này'; END IF;
  IF nr = 'manager' AND dept IS NULL THEN RAISE EXCEPTION 'Trưởng phòng cần có phòng ban'; END IF;
  UPDATE core.memberships SET department_id = dept, title = nullif(btrim(coalesce(p->>'title', '')), ''), active = act, is_dept_head = (nr = 'manager') WHERE user_id = uid AND company_id = cid;
  DELETE FROM core.user_roles WHERE company_id = cid AND user_id = uid AND role_id IN (SELECT id FROM core.roles WHERE company_id IS NULL AND code IN ('owner','admin','member'));
  INSERT INTO core.user_roles (company_id, user_id, role_id, granted_by) VALUES (cid, uid, agent._sys_role(CASE WHEN nr IN ('owner','admin') THEN nr ELSE 'member' END), me.id);
  PERFORM agent._audit(cid, me.id, 'member_set', 'user', uid::text, 'Đặt ' || nr || CASE WHEN act THEN '' ELSE ' (khóa)' END);
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION agent.app_invite_create(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); my text; rl text := coalesce(p->>'role', 'member'); dept uuid := agent._uuid(p, 'department_id');
        em text := lower(nullif(btrim(coalesce(p->>'email', '')), '')); mx int := coalesce((p->>'max_uses')::int, 1); dy int := coalesce((p->>'days')::int, 7); v_code text; i core.invites;
BEGIN
  my := agent._need_role(me.id, cid, ARRAY['owner','admin','manager']);
  IF rl NOT IN ('owner','admin','manager','member') THEN RAISE EXCEPTION 'Vai trò không hợp lệ'; END IF;
  IF my = 'manager' AND (rl <> 'member' OR dept IS DISTINCT FROM (SELECT department_id FROM core.memberships WHERE user_id = me.id AND company_id = cid)) THEN
    RAISE EXCEPTION 'Trưởng phòng chỉ mời được thành viên vào phòng của mình' USING ERRCODE = '42501';
  END IF;
  IF my = 'admin' AND rl = 'owner' THEN RAISE EXCEPTION 'Chỉ chủ sở hữu mới mời được chủ sở hữu' USING ERRCODE = '42501'; END IF;
  IF dept IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.departments WHERE id = dept AND company_id = cid) THEN RAISE EXCEPTION 'Phòng ban không thuộc công ty này'; END IF;
  IF rl = 'manager' AND dept IS NULL THEN RAISE EXCEPTION 'Trưởng phòng cần có phòng ban'; END IF;
  IF dy NOT BETWEEN 1 AND 60 THEN RAISE EXCEPTION 'Hạn dùng từ 1 đến 60 ngày'; END IF;
  IF mx NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Số lượt dùng từ 1 đến 200'; END IF;
  LOOP
    v_code := upper(substr(translate(encode(gen_random_bytes(12), 'base64'), '+/=0O1Il', ''), 1, 8));
    EXIT WHEN v_code ~ '^[A-Z0-9]{8}$' AND NOT EXISTS (SELECT 1 FROM core.invites WHERE code = v_code);
  END LOOP;
  INSERT INTO core.invites (code, company_id, department_id, role_ids, dept_head, email, note, max_uses, expires_at, created_by)
  VALUES (v_code, cid, dept, ARRAY[agent._sys_role(CASE WHEN rl IN ('owner','admin') THEN rl ELSE 'member' END)], rl = 'manager', em, left(nullif(btrim(coalesce(p->>'note', '')), ''), 200), mx, now() + make_interval(days => dy), me.id)
  RETURNING * INTO i;
  PERFORM agent._audit(cid, me.id, 'invite_create', 'invite', i.code, 'Tạo mã mời vai trò ' || rl);
  RETURN jsonb_build_object('code', i.code, 'role', rl, 'email', i.email, 'expires_at', i.expires_at, 'max_uses', i.max_uses);
END $$;

CREATE OR REPLACE FUNCTION agent.app_invites(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); my text;
BEGIN
  my := agent._need_role(me.id, cid, ARRAY['owner','admin','manager']);
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('code', i.code, 'role', agent._invite_role(i), 'department_id', i.department_id, 'email', i.email, 'note', i.note, 'max_uses', i.max_uses,
                   'uses', i.uses, 'expires_at', i.expires_at, 'revoked', i.revoked, 'created_at', i.created_at) ORDER BY i.created_at DESC)
                     FROM (SELECT * FROM core.invites WHERE company_id = cid AND (my IN ('owner','admin') OR created_by = me.id) ORDER BY created_at DESC LIMIT 100) i), '[]');
END $$;

CREATE OR REPLACE FUNCTION agent.app_invite_revoke(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); i core.invites; my text;
BEGIN
  SELECT * INTO i FROM core.invites WHERE code = upper(btrim(coalesce(p->>'code', '')));
  IF i.code IS NULL THEN RAISE EXCEPTION 'Không tìm thấy mã mời'; END IF;
  my := agent._need_role(me.id, i.company_id, ARRAY['owner','admin','manager']);
  IF my = 'manager' AND i.created_by IS DISTINCT FROM me.id THEN RAISE EXCEPTION 'Bạn chỉ thu hồi được mã do mình tạo' USING ERRCODE = '42501'; END IF;
  UPDATE core.invites SET revoked = true WHERE code = i.code;
  PERFORM agent._audit(i.company_id, me.id, 'invite_revoke', 'invite', i.code, 'Thu hồi mã mời');
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION agent.app_flow_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); fid uuid := agent._uuid(p, 'id'); nm text := btrim(coalesce(p->>'name', '')); dept uuid := agent._uuid(p, 'department_id');
        st jsonb := coalesce(p->'steps', '[]'); n int := jsonb_array_length(coalesce(p->'steps', '[]')); i int; s jsonb; k text; ru uuid; rr uuid;
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin']);
  IF length(nm) < 2 OR length(nm) > 120 THEN RAISE EXCEPTION 'Tên quy trình từ 2 đến 120 ký tự'; END IF;
  IF n NOT BETWEEN 1 AND 6 THEN RAISE EXCEPTION 'Quy trình có từ 1 đến 6 bước'; END IF;
  IF dept IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.departments WHERE id = dept AND company_id = cid) THEN RAISE EXCEPTION 'Phòng ban không thuộc công ty này'; END IF;
  IF fid IS NULL THEN
    INSERT INTO core.approval_flows (company_id, applies_to, department_id, name) VALUES (cid, 'task', dept, nm) RETURNING id INTO fid;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM core.approval_flows WHERE id = fid AND company_id = cid) THEN RAISE EXCEPTION 'Không tìm thấy quy trình'; END IF;
    IF EXISTS (SELECT 1 FROM core.approval_requests WHERE flow_id = fid AND state = 'pending') THEN
      RAISE EXCEPTION 'Đang có việc chờ duyệt theo quy trình này. Tạo quy trình mới rồi ngừng quy trình cũ.';
    END IF;
    UPDATE core.approval_flows SET name = nm, department_id = dept WHERE id = fid;
    DELETE FROM core.approval_steps WHERE flow_id = fid;
  END IF;
  FOR i IN 0 .. n - 1 LOOP
    s := st -> i;
    ru := agent._uuid(s, 'approver_user');
    IF ru IS NOT NULL THEN
      IF NOT EXISTS (SELECT 1 FROM core.memberships WHERE user_id = ru AND company_id = cid AND active) THEN RAISE EXCEPTION 'Người duyệt bước % không thuộc công ty', i + 1; END IF;
      INSERT INTO core.approval_steps (flow_id, step_no, name, approver_kind, approver_user) VALUES (fid, i + 1, left(coalesce(nullif(btrim(s->>'name'), ''), 'Bước ' || (i + 1)), 80), 'user', ru);
    ELSE
      k := coalesce(s->>'approver_role', '');
      IF k = 'manager' THEN
        INSERT INTO core.approval_steps (flow_id, step_no, name, approver_kind) VALUES (fid, i + 1, left(coalesce(nullif(btrim(s->>'name'), ''), 'Bước ' || (i + 1)), 80), 'dept_head');
      ELSIF k = 'creator' THEN
        INSERT INTO core.approval_steps (flow_id, step_no, name, approver_kind) VALUES (fid, i + 1, left(coalesce(nullif(btrim(s->>'name'), ''), 'Bước ' || (i + 1)), 80), 'creator');
      ELSIF k IN ('admin','owner') THEN
        INSERT INTO core.approval_steps (flow_id, step_no, name, approver_kind, approver_role) VALUES (fid, i + 1, left(coalesce(nullif(btrim(s->>'name'), ''), 'Bước ' || (i + 1)), 80), 'role', agent._sys_role(k));
      ELSE RAISE EXCEPTION 'Bước % thiếu người duyệt', i + 1;
      END IF;
    END IF;
  END LOOP;
  PERFORM agent._audit(cid, me.id, 'flow_save', 'approval_flow', fid::text, 'Lưu quy trình duyệt ' || nm);
  RETURN jsonb_build_object('id', fid);
END $$;

CREATE OR REPLACE FUNCTION agent.app_flow_archive(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); f core.approval_flows;
BEGIN
  SELECT * INTO f FROM core.approval_flows WHERE id = agent._uuid(p, 'id');
  IF f.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy quy trình'; END IF;
  PERFORM agent._need_role(me.id, f.company_id, ARRAY['owner','admin']);
  UPDATE core.approval_flows SET active = false WHERE id = f.id;
  PERFORM agent._audit(f.company_id, me.id, 'flow_archive', 'approval_flow', f.id::text, 'Ngừng quy trình ' || f.name);
  RETURN jsonb_build_object('ok', true);
END $$;

-- ---------- Thư mục Drive cá nhân ----------
CREATE OR REPLACE FUNCTION agent.app_drive_names(p jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me();
BEGIN
  RETURN coalesce((SELECT jsonb_agg('DEO - ' || c.slug || ' - ' || coalesce(d.code, 'CHUNG') || ' - ' || me.name ORDER BY m.joined_at)
                     FROM core.memberships m JOIN core.companies c ON c.id = m.company_id LEFT JOIN core.departments d ON d.id = m.department_id
                    WHERE m.user_id = me.id AND m.active), '[]');
END $$;

CREATE OR REPLACE FUNCTION agent.app_drive_set(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); fid text := substring(coalesce(p->>'url', '') from '^https://drive\.google\.com/drive/(?:u/[0-9]+/)?folders/([A-Za-z0-9_-]{10,})(?:[?/#].*)?$');
BEGIN
  IF fid IS NULL THEN RAISE EXCEPTION 'Link phải là thư mục Google Drive, dạng https://drive.google.com/drive/folders/...'; END IF;
  UPDATE core.users SET drive_folder_id = fid, drive_folder_url = 'https://drive.google.com/drive/folders/' || fid, drive_state = 'pending', drive_note = NULL, drive_checked_at = NULL WHERE id = me.id;
  RETURN jsonb_build_object('ok', true);
END $$;

-- ---------- Dự án: cài đặt, thành viên, xóa ----------
-- Quản lý được dự án: owner/admin; trưởng phòng của phòng sở hữu dự án; người quản lý dự án (manager_id)
CREATE OR REPLACE FUNCTION agent._can_manage_project(p_user uuid, pr core.projects) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, core, public AS $$
  SELECT CASE WHEN x.r IS NULL THEN false WHEN x.r IN ('owner','admin') THEN true
              WHEN x.r = 'manager' THEN pr.manager_id = p_user OR (pr.department_id IS NOT NULL AND pr.department_id = (SELECT m.department_id FROM core.memberships m WHERE m.user_id = p_user AND m.company_id = pr.company_id))
              ELSE pr.manager_id = p_user END
    FROM (SELECT agent._role_of(p_user, pr.company_id) AS r) x
$$;

CREATE OR REPLACE FUNCTION agent.app_project_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); pid uuid := agent._uuid(p, 'id'); my text; pr core.projects;
        nm text; sl text; dept uuid; du text; st text; mg uuid; cd text; n int := 1; ds text; sd date; ed date;
BEGIN
  IF pid IS NOT NULL THEN
    SELECT * INTO pr FROM core.projects WHERE id = pid;
    IF pr.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy dự án'; END IF;
    cid := pr.company_id;
    IF NOT agent._can_manage_project(me.id, pr) THEN RAISE EXCEPTION 'Bạn không có quyền sửa dự án này' USING ERRCODE = '42501'; END IF;
  END IF;
  my := agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  IF pid IS NULL AND my = 'member' THEN RAISE EXCEPTION 'Chỉ quản trị hoặc trưởng phòng mới tạo dự án' USING ERRCODE = '42501'; END IF;
  nm := btrim(coalesce(p->>'name', pr.name, '')); sl := btrim(coalesce(p->>'slug', pr.slug, ''));
  du := CASE WHEN p ? 'drive_url' THEN nullif(btrim(coalesce(p->>'drive_url', '')), '') ELSE pr.drive_url END;
  ds := CASE WHEN p ? 'description' THEN nullif(btrim(coalesce(p->>'description', '')), '') ELSE pr.description END;
  sd := CASE WHEN p ? 'start_date' THEN nullif(btrim(coalesce(p->>'start_date', '')), '')::date ELSE pr.start_date END;
  ed := CASE WHEN p ? 'end_date' THEN nullif(btrim(coalesce(p->>'end_date', '')), '')::date ELSE pr.end_date END;
  mg := CASE WHEN p ? 'manager_id' THEN agent._uuid(p, 'manager_id') WHEN pid IS NULL THEN me.id ELSE pr.manager_id END;
  st := coalesce(p->>'status', CASE WHEN p ? 'active' THEN CASE WHEN (p->>'active')::boolean THEN 'active' ELSE 'done' END END, pr.status, 'active');
  -- phòng ban: người chỉ là quản lý dự án không đổi phòng; trưởng phòng chỉ đặt vào phòng mình
  dept := CASE WHEN pid IS NOT NULL AND my NOT IN ('owner','admin') AND my <> 'manager' THEN pr.department_id
               WHEN p ? 'department_id' THEN agent._uuid(p, 'department_id') WHEN pid IS NULL THEN NULL ELSE pr.department_id END;
  IF my = 'manager' AND dept IS DISTINCT FROM (SELECT department_id FROM core.memberships WHERE user_id = me.id AND company_id = cid) AND (pid IS NULL OR dept IS DISTINCT FROM pr.department_id) THEN
    RAISE EXCEPTION 'Trưởng phòng chỉ đặt dự án vào phòng của mình' USING ERRCODE = '42501';
  END IF;
  IF length(nm) < 2 OR length(nm) > 160 THEN RAISE EXCEPTION 'Tên dự án từ 2 đến 160 ký tự'; END IF;
  IF sl !~ '^[a-z0-9]+(-[a-z0-9]+)*$' OR length(sl) > 60 THEN RAISE EXCEPTION 'Mã dự án chỉ gồm chữ thường, số và gạch nối'; END IF;
  IF du IS NOT NULL AND du !~ '^https://' THEN RAISE EXCEPTION 'Link Drive phải bắt đầu bằng https://'; END IF;
  IF length(coalesce(ds, '')) > 4000 THEN RAISE EXCEPTION 'Mô tả tối đa 4000 ký tự'; END IF;
  IF st NOT IN ('planned','active','paused','done','cancelled') THEN RAISE EXCEPTION 'Trạng thái dự án không hợp lệ'; END IF;
  IF sd IS NOT NULL AND ed IS NOT NULL AND ed < sd THEN RAISE EXCEPTION 'Ngày kết thúc phải sau ngày bắt đầu'; END IF;
  IF dept IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.departments WHERE id = dept AND company_id = cid) THEN RAISE EXCEPTION 'Phòng ban không thuộc công ty này'; END IF;
  IF mg IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.memberships WHERE user_id = mg AND company_id = cid AND active) THEN RAISE EXCEPTION 'Người quản lý dự án không thuộc công ty'; END IF;
  IF pid IS NULL THEN
    cd := upper(left(regexp_replace(sl, '[^a-z0-9]', '', 'g'), 16)); IF length(cd) < 2 THEN cd := 'DA' || cd; END IF;
    WHILE EXISTS (SELECT 1 FROM core.projects WHERE company_id = cid AND code = cd) LOOP n := n + 1; cd := upper(left(regexp_replace(sl, '[^a-z0-9]', '', 'g'), 14)) || n; END LOOP;
    INSERT INTO core.projects (company_id, department_id, code, slug, name, description, drive_url, status, manager_id, start_date, end_date)
    VALUES (cid, dept, cd, sl, nm, ds, du, st, mg, sd, ed) RETURNING id INTO pid;
  ELSE
    UPDATE core.projects SET department_id = dept, slug = sl, name = nm, description = ds, drive_url = du, status = st, manager_id = mg, start_date = sd, end_date = ed WHERE id = pid;
  END IF;
  IF mg IS NOT NULL THEN
    INSERT INTO core.project_members (project_id, user_id, role) VALUES (pid, mg, 'manager') ON CONFLICT (project_id, user_id) DO UPDATE SET role = 'manager';
  END IF;
  PERFORM agent._audit(cid, me.id, 'project_save', 'project', pid::text, 'Lưu dự án ' || nm);
  RETURN jsonb_build_object('id', pid);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'Mã dự án % đã có', sl;
END $$;

CREATE OR REPLACE FUNCTION agent.app_project_member_set(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); pr core.projects; uid uuid := agent._uuid(p, 'user_id'); rl text := coalesce(p->>'role', 'member');
BEGIN
  SELECT * INTO pr FROM core.projects WHERE id = agent._uuid(p, 'project_id');
  IF pr.id IS NULL OR agent._role_of(me.id, pr.company_id) IS NULL THEN RAISE EXCEPTION 'Không tìm thấy dự án' USING ERRCODE = '42501'; END IF;
  IF NOT agent._can_manage_project(me.id, pr) THEN RAISE EXCEPTION 'Bạn không có quyền quản lý thành viên dự án này' USING ERRCODE = '42501'; END IF;
  IF rl NOT IN ('manager','member','viewer') THEN RAISE EXCEPTION 'Vai trò trong dự án không hợp lệ'; END IF;
  IF NOT EXISTS (SELECT 1 FROM core.memberships WHERE user_id = uid AND company_id = pr.company_id AND active) THEN RAISE EXCEPTION 'Người này không thuộc công ty'; END IF;
  IF uid = pr.manager_id AND rl <> 'manager' THEN RAISE EXCEPTION 'Đổi người quản lý dự án trong phần cài đặt trước'; END IF;
  INSERT INTO core.project_members (project_id, user_id, role) VALUES (pr.id, uid, rl) ON CONFLICT (project_id, user_id) DO UPDATE SET role = EXCLUDED.role;
  PERFORM agent._audit(pr.company_id, me.id, 'project_member_set', 'project', pr.id::text, 'Thành viên dự án ' || pr.name || ': ' || rl);
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION agent.app_project_member_remove(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); pr core.projects; uid uuid := agent._uuid(p, 'user_id');
BEGIN
  SELECT * INTO pr FROM core.projects WHERE id = agent._uuid(p, 'project_id');
  IF pr.id IS NULL OR agent._role_of(me.id, pr.company_id) IS NULL THEN RAISE EXCEPTION 'Không tìm thấy dự án' USING ERRCODE = '42501'; END IF;
  IF NOT agent._can_manage_project(me.id, pr) THEN RAISE EXCEPTION 'Bạn không có quyền quản lý thành viên dự án này' USING ERRCODE = '42501'; END IF;
  IF uid = pr.manager_id THEN RAISE EXCEPTION 'Không gỡ được người quản lý dự án; đổi người quản lý trong phần cài đặt'; END IF;
  DELETE FROM core.project_members WHERE project_id = pr.id AND user_id = uid;
  PERFORM agent._audit(pr.company_id, me.id, 'project_member_remove', 'project', pr.id::text, 'Gỡ thành viên khỏi dự án ' || pr.name);
  RETURN jsonb_build_object('ok', true);
END $$;

-- Xóa dự án: chỉ owner/admin hoặc trưởng phòng của phòng sở hữu. Việc thuộc dự án không bị xóa, chỉ mất liên kết dự án.
CREATE OR REPLACE FUNCTION agent.app_project_delete(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, work, public AS $$
DECLARE me core.users := agent._web_me(); pr core.projects; my text; n int;
BEGIN
  SELECT * INTO pr FROM core.projects WHERE id = agent._uuid(p, 'id');
  IF pr.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy dự án'; END IF;
  my := agent._need_role(me.id, pr.company_id, ARRAY['owner','admin','manager']);
  IF my = 'manager' AND pr.department_id IS DISTINCT FROM (SELECT department_id FROM core.memberships WHERE user_id = me.id AND company_id = pr.company_id) THEN
    RAISE EXCEPTION 'Trưởng phòng chỉ xóa dự án của phòng mình' USING ERRCODE = '42501';
  END IF;
  SELECT count(*) INTO n FROM work.tasks WHERE project_id = pr.id;
  DELETE FROM core.projects WHERE id = pr.id;
  PERFORM agent._audit(pr.company_id, me.id, 'project_delete', 'project', pr.id::text, 'Xóa dự án ' || pr.name || ' (' || n || ' việc mất liên kết dự án)');
  RETURN jsonb_build_object('ok', true, 'tasks_unlinked', n);
END $$;

REVOKE ALL ON FUNCTION agent._can_manage_project(uuid, core.projects), agent.app_project_save(jsonb), agent.app_project_member_set(jsonb), agent.app_project_member_remove(jsonb), agent.app_project_delete(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.app_project_save(jsonb), agent.app_project_member_set(jsonb), agent.app_project_member_remove(jsonb), agent.app_project_delete(jsonb) TO web_svc;

-- ---------- Quyền ----------
-- Sửa lỗ cũ: REVOKE giữa tệp 60 bỏ sót hàm tạo sau; thu hồi lại cho toàn schema rồi cấp đúng danh sách cho web_svc.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA agent FROM PUBLIC;
-- Các hàm web_* / mcp_* cũ mà giao diện mới không còn gọi: thu hồi để giảm bề mặt tấn công
REVOKE EXECUTE ON FUNCTION agent.web_login(text, text, text, text), agent.web_me(), agent.web_create_task(text, text, text, date, text),
  agent.web_task(bigint), agent.web_cancel_task(bigint, text), agent.mcp_my_tasks(text, text, int), agent.mcp_my_day(), agent.mcp_comment(bigint, text, text),
  agent.accept_result(bigint, text), agent.reject_result(bigint, text) FROM web_svc;
GRANT EXECUTE ON FUNCTION agent.app_login(jsonb), agent.app_me(jsonb), agent.app_org(jsonb), agent.app_tasks(jsonb), agent.app_task(jsonb), agent.app_task_save(jsonb),
  agent.app_submit(jsonb), agent.app_decide(jsonb), agent.app_answer(jsonb), agent.app_comment(jsonb), agent.app_link_add(jsonb), agent.app_link_remove(jsonb),
  agent.app_accept(jsonb), agent.app_reject(jsonb), agent.app_my_approvals(jsonb), agent.app_report(jsonb), agent.app_dept_save(jsonb), agent.app_member_set(jsonb),
  agent.app_invite_create(jsonb), agent.app_invites(jsonb), agent.app_invite_revoke(jsonb), agent.app_flow_save(jsonb), agent.app_flow_archive(jsonb),
  agent.app_drive_names(jsonb), agent.app_drive_set(jsonb) TO web_svc;
