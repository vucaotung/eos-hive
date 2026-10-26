-- 0025 · Cờ Eisenhower (important, urgent) và ngày bắt đầu trong app_task_save / _task_json (giao diện Eisenhower, Lịch, Timeline).
-- Nguồn chính: db/10_work.sql (cột), db/61_app.sql (hàm). Idempotent. Việc cũ: important = urgent = false (ô "Để sau"). KHÔNG đổi quyền sửa: chỉ người sửa được việc mới đặt được cờ.
-- down: nạp lại agent._task_json và agent.app_task_save bản 0010; ALTER TABLE work.tasks DROP COLUMN important, DROP COLUMN urgent.
BEGIN;
ALTER TABLE work.tasks ADD COLUMN IF NOT EXISTS important boolean NOT NULL DEFAULT false;
ALTER TABLE work.tasks ADD COLUMN IF NOT EXISTS urgent boolean NOT NULL DEFAULT false;
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
CREATE OR REPLACE FUNCTION agent.app_task_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; cid uuid; v_title text; v_desc text; v_dept uuid; v_asg uuid; v_proj uuid; v_flow uuid; v_parent bigint;
        v_due date; v_start date; v_imp boolean; v_urg boolean; v_prio work.task_priority; v_agent uuid; v_status work.task_status; ag_code text; new_id bigint;
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
    INSERT INTO work.tasks (company_id, department_id, project_id, parent_id, title, description, priority, assignee_id, agent_id, agent_role, approval_flow_id, due_date, start_date, important, urgent, created_by)
    VALUES (cid, v_dept, v_proj, v_parent, v_title, v_desc, v_prio, v_asg, v_agent, ag_code, v_flow, v_due, v_start, v_imp, v_urg, me.id) RETURNING id INTO new_id;
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
         due_date = v_due, start_date = v_start, important = v_imp, urgent = v_urg, priority = v_prio, agent_id = v_agent, agent_role = coalesce(ag_code, CASE WHEN v_agent IS NULL THEN NULL ELSE agent_role END),
         status = v_status, waiting_on_human = CASE WHEN v_status IS DISTINCT FROM t.status THEN false ELSE waiting_on_human END, updated_at = now()
   WHERE id = t.id;
  PERFORM agent._audit(cid, me.id, 'update', 'task', t.id::text, 'Sửa T-' || t.id);
  RETURN jsonb_build_object('id', t.id);
END $$;
COMMIT;
