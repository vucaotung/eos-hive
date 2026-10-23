-- 0012 · Nộp việc: phải có kết quả (tóm tắt hoặc tài liệu/link); việc đang giao cho agent thì người không nộp tay được (agent nộp, người xem và chấp nhận);
-- app_task trả can_submit=false cho việc giao agent. Nguồn chính: db/61_app.sql. Idempotent. down: khôi phục agent.app_submit/app_task từ migration 0010.
BEGIN;
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
COMMIT;
