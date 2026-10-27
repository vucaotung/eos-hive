-- 0028 · Chi tiết việc: mẫu checklist, app_checklist_*, app_watchers_set; app_task trả checklist/watchers/activity; app_task_save nhận est_minutes và ghi nhật ký đổi gì.
-- Nguồn chính: db/63_features.sql (PHẦN C). Idempotent.
BEGIN;
CREATE TABLE IF NOT EXISTS work.checklist_templates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  items       text[] NOT NULL CHECK (cardinality(items) BETWEEN 1 AND 50),
  uses        int NOT NULL DEFAULT 0,
  created_by  uuid REFERENCES core.users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, name)
);
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
-- ==== PHẦN C: CHI TIẾT VIỆC (checklist, mẫu, người theo dõi) ====
-- app_task trả thêm checklist, watchers, activity (nhật ký thay đổi cụ thể); app_task_save nhận est_minutes và ghi nhật ký "đổi gì" (bản ở db/61_app.sql).
CREATE OR REPLACE FUNCTION agent._task_editor(p_task bigint) RETURNS work.tasks
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF t.id IS NULL OR NOT agent._can_see(me.id, t) THEN RAISE EXCEPTION 'Không tìm thấy việc hoặc bạn không có quyền xem' USING ERRCODE = '42501'; END IF;
  IF NOT (t.assignee_id = me.id OR t.created_by = me.id OR agent._can_edit(me.id, t)) THEN RAISE EXCEPTION 'Bạn không có quyền sửa phần này của T-%', t.id USING ERRCODE = '42501'; END IF;
  RETURN t;
END $$;

-- Thay toàn bộ checklist của việc (giữ người/ngày đã tick của mục đã tick từ trước nếu tên không đổi)
CREATE OR REPLACE FUNCTION agent.app_checklist_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks := agent._task_editor((p->>'task')::bigint); it jsonb; i int := 0; olds jsonb; keep jsonb; d int := 0; ttl text;
BEGIN
  IF jsonb_typeof(p->'items') <> 'array' OR jsonb_array_length(p->'items') > 50 THEN RAISE EXCEPTION 'Checklist tối đa 50 mục'; END IF;
  olds := coalesce((SELECT jsonb_agg(jsonb_build_object('title', title, 'by', done_by, 'at', done_at)) FROM work.checklist_items WHERE task_id = t.id AND done), '[]');
  DELETE FROM work.checklist_items WHERE task_id = t.id;
  FOR it IN SELECT * FROM jsonb_array_elements(p->'items') LOOP
    ttl := btrim(coalesce(it->>'title', ''));
    IF length(ttl) < 1 OR length(ttl) > 300 THEN RAISE EXCEPTION 'Mỗi mục checklist từ 1 đến 300 ký tự'; END IF;
    keep := (SELECT o FROM jsonb_array_elements(olds) o WHERE o->>'title' = ttl LIMIT 1);
    INSERT INTO work.checklist_items (task_id, position, title, done, done_by, done_at)
    VALUES (t.id, i, ttl, coalesce((it->>'done')::boolean, false), CASE WHEN coalesce((it->>'done')::boolean, false) THEN coalesce((keep->>'by')::uuid, me.id) END,
            CASE WHEN coalesce((it->>'done')::boolean, false) THEN coalesce((keep->>'at')::timestamptz, now()) END);
    IF coalesce((it->>'done')::boolean, false) THEN d := d + 1; END IF;
    i := i + 1;
  END LOOP;
  PERFORM agent._audit(t.company_id, me.id, 'checklist', 'task', t.id::text, 'Cập nhật checklist T-' || t.id || ' (' || d || '/' || i || ' xong)');
  RETURN jsonb_build_object('items', i, 'done', d);
END $$;

CREATE OR REPLACE FUNCTION agent.app_checklist_templates(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id');
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'items', to_jsonb(x.items), 'uses', x.uses) ORDER BY x.uses DESC, x.name) FROM work.checklist_templates x WHERE x.company_id = cid), '[]');
END $$;

CREATE OR REPLACE FUNCTION agent.app_checklist_template_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); tid uuid := agent._uuid(p, 'id'); nm text := btrim(coalesce(p->>'name', '')); its text[];
BEGIN
  IF tid IS NOT NULL THEN SELECT company_id INTO cid FROM work.checklist_templates WHERE id = tid; IF cid IS NULL THEN RAISE EXCEPTION 'Không tìm thấy mẫu'; END IF; END IF;
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager']);
  SELECT array_agg(btrim(x)) INTO its FROM jsonb_array_elements_text(coalesce(p->'items', '[]')) x WHERE btrim(x) <> '';
  IF length(nm) < 2 OR length(nm) > 120 THEN RAISE EXCEPTION 'Tên mẫu từ 2 đến 120 ký tự'; END IF;
  IF its IS NULL OR cardinality(its) NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Mẫu cần từ 1 đến 50 mục'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(its) x WHERE length(x) > 300) THEN RAISE EXCEPTION 'Mỗi mục tối đa 300 ký tự'; END IF;
  IF tid IS NULL THEN INSERT INTO work.checklist_templates (company_id, name, items, created_by) VALUES (cid, nm, its, me.id) RETURNING id INTO tid;
  ELSE UPDATE work.checklist_templates SET name = nm, items = its WHERE id = tid; END IF;
  RETURN jsonb_build_object('id', tid);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'Đã có mẫu tên "%"', nm;
END $$;

CREATE OR REPLACE FUNCTION agent.app_checklist_template_delete(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); x work.checklist_templates;
BEGIN
  SELECT * INTO x FROM work.checklist_templates WHERE id = agent._uuid(p, 'id');
  IF x.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy mẫu'; END IF;
  PERFORM agent._need_role(me.id, x.company_id, ARRAY['owner','admin','manager']);
  DELETE FROM work.checklist_templates WHERE id = x.id;
  RETURN jsonb_build_object('deleted', true);
END $$;

-- Chèn mẫu vào việc (thêm vào cuối hoặc thay thế); tăng số lần dùng
CREATE OR REPLACE FUNCTION agent.app_checklist_apply(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks := agent._task_editor((p->>'task')::bigint); x work.checklist_templates; base int; n int;
BEGIN
  SELECT * INTO x FROM work.checklist_templates WHERE id = agent._uuid(p, 'template_id') AND company_id = t.company_id;
  IF x.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy mẫu trong công ty này'; END IF;
  IF coalesce(p->>'mode', 'append') = 'replace' THEN DELETE FROM work.checklist_items WHERE task_id = t.id; END IF;
  SELECT coalesce(max(position) + 1, 0) INTO base FROM work.checklist_items WHERE task_id = t.id;
  IF base + cardinality(x.items) > 50 THEN RAISE EXCEPTION 'Checklist tối đa 50 mục'; END IF;
  INSERT INTO work.checklist_items (task_id, position, title) SELECT t.id, base + (o - 1), it FROM unnest(x.items) WITH ORDINALITY u(it, o);
  GET DIAGNOSTICS n = ROW_COUNT;
  UPDATE work.checklist_templates SET uses = uses + 1 WHERE id = x.id;
  PERFORM agent._audit(t.company_id, me.id, 'checklist', 'task', t.id::text, 'Chèn mẫu checklist "' || x.name || '" vào T-' || t.id);
  RETURN jsonb_build_object('added', n);
END $$;

-- Người theo dõi (thay toàn bộ danh sách; người mới thêm được báo)
CREATE OR REPLACE FUNCTION agent.app_watchers_set(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks := agent._task_editor((p->>'task')::bigint); ids uuid[]; u uuid; added int := 0;
BEGIN
  SELECT coalesce(array_agg(DISTINCT x::uuid), '{}') INTO ids FROM jsonb_array_elements_text(coalesce(p->'user_ids', '[]')) x;
  IF cardinality(ids) > 20 THEN RAISE EXCEPTION 'Tối đa 20 người theo dõi'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(ids) x WHERE NOT EXISTS (SELECT 1 FROM core.memberships m JOIN core.users us ON us.id = m.user_id WHERE m.user_id = x AND m.company_id = t.company_id AND m.active AND us.kind = 'person' AND us.active)) THEN
    RAISE EXCEPTION 'Người theo dõi phải là thành viên (người) của công ty';
  END IF;
  FOREACH u IN ARRAY ids LOOP
    INSERT INTO work.task_watchers (task_id, user_id) VALUES (t.id, u) ON CONFLICT DO NOTHING;
    IF FOUND AND u IS DISTINCT FROM me.id THEN added := added + 1; PERFORM agent._notify_from(t.company_id, u, 'watching', me.name || ' thêm bạn vào theo dõi: ' || t.title, NULL, t.id, 'user:' || me.id, false); END IF;
  END LOOP;
  DELETE FROM work.task_watchers WHERE task_id = t.id AND NOT (user_id = ANY (ids));
  RETURN jsonb_build_object('watchers', cardinality(ids), 'added', added);
END $$;
-- ==== HẾT PHẦN C ====
GRANT EXECUTE ON FUNCTION agent.app_checklist_save(jsonb), agent.app_checklist_templates(jsonb), agent.app_checklist_template_save(jsonb), agent.app_checklist_template_delete(jsonb), agent.app_checklist_apply(jsonb), agent.app_watchers_set(jsonb) TO web_svc;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA agent FROM PUBLIC;
COMMIT;
