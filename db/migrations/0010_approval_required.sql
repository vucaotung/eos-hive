-- 0010 · "Phải duyệt": quy trình duyệt dựng sẵn (Người giao / Trưởng phòng / Quản trị), bước "người giao", trạng thái duyệt của việc
-- (work.tasks.approval_status: none · pending · approved · rejected) và ràng buộc: việc gắn quy trình chỉ Xong khi đã duyệt xong (trigger).
-- agent.mcp_submit (nộp qua MCP của người) nay cũng mở yêu cầu duyệt thay vì đặt Chờ duyệt suông. Nguồn chính: db/00_core.sql, 60_agent.sql, 61_app.sql. Idempotent.
-- down: DROP TRIGGER tasks_need_approval; DROP FUNCTION work.tasks_need_approval_trg, agent._ensure_default_flows; ALTER TABLE work.tasks DROP COLUMN approval_status;
--       đưa các hàm về bản migration 0006/0008; bỏ ràng buộc 'creator' khỏi core.approval_steps.
BEGIN;
DO $$ DECLARE c record; BEGIN
  FOR c IN SELECT conname FROM pg_constraint WHERE conrelid = 'core.approval_steps'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%project_manager%' LOOP
    EXECUTE format('ALTER TABLE core.approval_steps DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;
ALTER TABLE core.approval_steps ADD CONSTRAINT approval_steps_kind_check CHECK (approver_kind IN ('dept_head','role','user','project_manager','creator'));
ALTER TABLE work.tasks ADD COLUMN IF NOT EXISTS approval_status text NOT NULL DEFAULT 'none' CHECK (approval_status IN ('none','pending','approved','rejected'));
UPDATE work.tasks t SET approval_status = 'pending' WHERE t.approval_status = 'none' AND EXISTS (SELECT 1 FROM core.approval_requests r WHERE r.entity_type = 'task' AND r.entity_id = t.id AND r.state = 'pending');
UPDATE work.tasks t SET approval_status = 'approved' WHERE t.approval_status = 'none' AND t.status = 'done' AND t.approval_flow_id IS NOT NULL AND EXISTS (SELECT 1 FROM core.approval_requests r WHERE r.entity_type = 'task' AND r.entity_id = t.id AND r.state = 'approved');
UPDATE work.tasks t SET approval_status = 'rejected' WHERE t.approval_status = 'none' AND t.status NOT IN ('done','cancelled') AND t.approval_flow_id IS NOT NULL
   AND (SELECT state FROM core.approval_requests r WHERE r.entity_type = 'task' AND r.entity_id = t.id ORDER BY r.id DESC LIMIT 1) = 'rejected';
CREATE OR REPLACE FUNCTION agent._task_json(t work.tasks) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  SELECT jsonb_build_object(
    'id', t.id, 'company_id', t.company_id, 'title', t.title, 'description', t.description, 'status', t.status, 'priority', t.priority,
    'assignee_id', t.assignee_id, 'department_id', t.department_id, 'project_id', t.project_id, 'parent_id', t.parent_id,
    'due_date', t.due_date, 'created_by', t.created_by, 'created_by_agent', t.created_by_agent, 'waiting_on_human', t.waiting_on_human,
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

CREATE OR REPLACE FUNCTION agent.app_task_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; cid uuid; v_title text; v_desc text; v_dept uuid; v_asg uuid; v_proj uuid; v_flow uuid; v_parent bigint;
        v_due date; v_prio work.task_priority; v_agent uuid; v_status work.task_status; ag_code text; new_id bigint;
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
    INSERT INTO work.tasks (company_id, department_id, project_id, parent_id, title, description, priority, assignee_id, agent_id, agent_role, approval_flow_id, due_date, created_by)
    VALUES (cid, v_dept, v_proj, v_parent, v_title, v_desc, v_prio, v_asg, v_agent, ag_code, v_flow, v_due, me.id) RETURNING id INTO new_id;
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
         due_date = v_due, priority = v_prio, agent_id = v_agent, agent_role = coalesce(ag_code, CASE WHEN v_agent IS NULL THEN NULL ELSE agent_role END),
         status = v_status, waiting_on_human = CASE WHEN v_status IS DISTINCT FROM t.status THEN false ELSE waiting_on_human END, updated_at = now()
   WHERE id = t.id;
  PERFORM agent._audit(cid, me.id, 'update', 'task', t.id::text, 'Sửa T-' || t.id);
  RETURN jsonb_build_object('id', t.id);
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

CREATE OR REPLACE FUNCTION agent.mcp_submit(p_task bigint, p_summary text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); t work.tasks; new_status work.task_status;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task FOR UPDATE;
  IF t.assignee_id IS DISTINCT FROM me THEN RAISE EXCEPTION 'Chỉ người được giao mới nộp kết quả T-%', p_task USING ERRCODE = '42501'; END IF;
  IF t.status NOT IN ('todo','in_progress','blocked') THEN RAISE EXCEPTION 'Việc đang ở trạng thái %, không nộp được', t.status; END IF;
  IF length(btrim(coalesce(p_summary, ''))) < 10 THEN RAISE EXCEPTION 'Tóm tắt kết quả quá ngắn'; END IF;
  UPDATE work.tasks SET result = left(p_summary, 4000), progress = 100, waiting_on_human = false, updated_at = now() WHERE id = p_task;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task, me, agent._mcp_actor(), 'submit', p_summary);
  new_status := agent._approval_start(p_task, me)::work.task_status;   -- có quy trình: mở yêu cầu duyệt (Chờ duyệt, approval_status = pending); không có: Xong (db/61_app.sql)
  INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
  VALUES (t.company_id, agent._mcp_actor(), me, 'work', 'submit', 'task', p_task::text, 'Nộp kết quả T-' || p_task || ' qua ' || core.current_via());
  RETURN jsonb_build_object('id', 'T-' || p_task, 'status', new_status);
END $$;

CREATE OR REPLACE FUNCTION agent.accept_result(p_task bigint, p_note text DEFAULT NULL) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); t work.tasks;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task FOR UPDATE;
  IF t.status <> 'in_review' OR t.agent_id IS NULL THEN RETURN 'not_in_review'; END IF;
  IF me IS DISTINCT FROM coalesce(t.created_by, (SELECT default_reviewer FROM agent.company_settings WHERE company_id = t.company_id)) THEN
    RAISE EXCEPTION 'Chỉ người giao mới chấp nhận kết quả T-%', p_task USING ERRCODE = '42501';
  END IF;
  UPDATE agent.reports SET verdict = 'accepted' WHERE task_id = p_task AND verdict = 'pending';
  IF t.approval_flow_id IS NOT NULL THEN
    -- còn quy trình duyệt: giữ Chờ duyệt và mở yêu cầu duyệt (core.approval_requests), các bước do agent.app_decide xử lý
    INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task, me, 'user:' || me, 'note', coalesce(p_note, 'Đã xem kết quả của agent, chuyển duyệt'));
    RETURN CASE agent._approval_start(p_task, NULL) WHEN 'in_review' THEN 'to_approval' ELSE 'done' END;   -- agent._approval_start: db/61_app.sql
  END IF;
  UPDATE work.tasks SET status = 'done', completed_at = now(), updated_at = now() WHERE id = p_task;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task, me, 'user:' || me, 'approve', coalesce(p_note, 'Chấp nhận kết quả'));
  RETURN 'done';
END $$;

CREATE OR REPLACE FUNCTION work.tasks_need_approval_trg() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'done' AND OLD.status <> 'done' AND NEW.approval_flow_id IS NOT NULL AND NEW.approval_status <> 'approved' THEN
    RAISE EXCEPTION 'Việc T-% phải được duyệt xong mới hoàn thành (trạng thái duyệt: %)', NEW.id, NEW.approval_status USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS tasks_need_approval ON work.tasks;
CREATE TRIGGER tasks_need_approval BEFORE UPDATE OF status ON work.tasks FOR EACH ROW EXECUTE FUNCTION work.tasks_need_approval_trg();
SELECT agent._ensure_default_flows(id) FROM core.companies WHERE active;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA agent FROM PUBLIC;
COMMIT;
