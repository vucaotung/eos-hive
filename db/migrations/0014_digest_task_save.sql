-- 0014 · Thay Ever Teams: bản tin hằng ngày/tuần (agent.mcp_company_digest) và tạo/sửa việc qua MCP (agent.mcp_task_save) cho Mai và agent cá nhân.
-- Nguồn chính: db/62_workflow.sql. Idempotent. down: DROP FUNCTION agent.mcp_company_digest(jsonb), agent.mcp_task_save(jsonb).
BEGIN;
CREATE OR REPLACE FUNCTION agent.mcp_company_digest(p jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := coalesce(agent._uuid(p, 'company_id'), (SELECT company_id FROM core.memberships WHERE user_id = me.id AND active ORDER BY joined_at LIMIT 1));
        rl text; today date; days int := least(greatest(coalesce((p->>'days')::int, 1), 1), 31); scope_name text; dept uuid; res jsonb;
BEGIN
  rl := agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  today := (now() AT TIME ZONE (SELECT timezone FROM core.companies WHERE id = cid))::date;
  SELECT department_id INTO dept FROM core.memberships WHERE user_id = me.id AND company_id = cid;
  scope_name := CASE WHEN rl IN ('owner','admin') THEN 'Toàn công ty' WHEN rl = 'manager' THEN 'Phòng ' || coalesce((SELECT code FROM core.departments WHERE id = dept), '?') ELSE 'Việc của tôi' END;
  WITH v AS (
    SELECT t.* FROM agent._visible_tasks(me.id, cid, 60, NULL) t
     WHERE rl IN ('owner','admin') OR (rl = 'manager' AND (t.department_id = dept OR t.assignee_id = me.id OR t.created_by = me.id)) OR (rl = 'member' AND (t.assignee_id = me.id OR t.created_by = me.id))),
  o AS (SELECT * FROM v WHERE status NOT IN ('done','cancelled')),
  nm AS (SELECT id, name FROM core.users)
  SELECT jsonb_build_object(
    'company', (SELECT coalesce(short_name, name) FROM core.companies WHERE id = cid), 'scope', scope_name, 'date', today, 'days', days,
    'counts', jsonb_build_object('open', (SELECT count(*) FROM o), 'overdue', (SELECT count(*) FROM o WHERE due_date < today), 'due_today', (SELECT count(*) FROM o WHERE due_date = today),
        'due_3d', (SELECT count(*) FROM o WHERE due_date > today AND due_date <= today + 3), 'blocked', (SELECT count(*) FROM o WHERE status = 'blocked'),
        'ask_human', (SELECT count(*) FROM o WHERE waiting_on_human), 'in_review', (SELECT count(*) FROM o WHERE status = 'in_review'),
        'done_period', (SELECT count(*) FROM v WHERE status = 'done' AND completed_at > now() - make_interval(days => days)),
        'created_period', (SELECT count(*) FROM v WHERE created_at > now() - make_interval(days => days))),
    'overdue', coalesce((SELECT jsonb_agg(jsonb_build_object('id', 'T-' || o.id, 'title', left(o.title, 90), 'who', (SELECT name FROM nm WHERE nm.id = o.assignee_id), 'due', o.due_date, 'days_late', today - o.due_date, 'status', o.status) ORDER BY o.due_date, o.id)
                         FROM (SELECT * FROM o WHERE due_date < today ORDER BY due_date, id LIMIT 12) o), '[]'),
    'due_today', coalesce((SELECT jsonb_agg(jsonb_build_object('id', 'T-' || o.id, 'title', left(o.title, 90), 'who', (SELECT name FROM nm WHERE nm.id = o.assignee_id)) ORDER BY o.id) FROM (SELECT * FROM o WHERE due_date = today LIMIT 12) o), '[]'),
    'need_you', coalesce((SELECT jsonb_agg(jsonb_build_object('id', 'T-' || o.id, 'title', left(o.title, 90), 'kind', CASE WHEN o.waiting_on_human THEN 'agent hỏi' ELSE 'chờ duyệt' END) ORDER BY o.updated_at DESC)
                         FROM (SELECT * FROM o WHERE waiting_on_human OR status = 'in_review' ORDER BY updated_at DESC LIMIT 12) o), '[]'),
    'done_period', coalesce((SELECT jsonb_agg(jsonb_build_object('id', 'T-' || d.id, 'title', left(d.title, 90), 'who', (SELECT name FROM nm WHERE nm.id = d.assignee_id)) ORDER BY d.completed_at DESC)
                         FROM (SELECT * FROM v WHERE status = 'done' AND completed_at > now() - make_interval(days => days) ORDER BY completed_at DESC LIMIT 12) d), '[]'),
    'by_dept', CASE WHEN rl IN ('owner','admin') THEN coalesce((SELECT jsonb_agg(jsonb_build_object('dept', coalesce(d.code, 'Chung'), 'open', x.open, 'overdue', x.late) ORDER BY x.open DESC)
                  FROM (SELECT department_id, count(*) open, count(*) FILTER (WHERE due_date < today) late FROM o GROUP BY department_id) x LEFT JOIN core.departments d ON d.id = x.department_id), '[]') ELSE '[]'::jsonb END,
    'by_person', CASE WHEN rl IN ('owner','admin','manager') THEN coalesce((SELECT jsonb_agg(jsonb_build_object('who', coalesce((SELECT name FROM nm WHERE nm.id = x.assignee_id), 'Chưa giao'), 'open', x.open, 'overdue', x.late) ORDER BY x.late DESC, x.open DESC)
                  FROM (SELECT assignee_id, count(*) open, count(*) FILTER (WHERE due_date < today) late FROM o GROUP BY assignee_id ORDER BY count(*) FILTER (WHERE due_date < today) DESC, count(*) DESC LIMIT 10) x), '[]') ELSE '[]'::jsonb END,
    'projects', coalesce((SELECT jsonb_agg(jsonb_build_object('name', pr.name, 'open', x.open, 'overdue', x.late, 'run', (SELECT state FROM agent.workflow_runs w WHERE w.project_id = pr.id ORDER BY id DESC LIMIT 1)) ORDER BY x.open DESC)
                  FROM (SELECT project_id, count(*) open, count(*) FILTER (WHERE due_date < today) late FROM o WHERE project_id IS NOT NULL GROUP BY project_id) x JOIN core.projects pr ON pr.id = x.project_id), '[]'),
    'agents', CASE WHEN rl IN ('owner','admin') THEN jsonb_build_object(
        'running', (SELECT count(*) FROM agent.cards c WHERE c.company_id = cid AND c.status = 'running'),
        'blocked', (SELECT count(*) FROM agent.cards c WHERE c.company_id = cid AND c.status = 'blocked'),
        'stuck_2h', (SELECT count(*) FROM agent.cards c WHERE c.company_id = cid AND c.status = 'running' AND c.last_event_at < now() - interval '2 hours'),
        'outbox_pending', (SELECT count(*) FROM agent.outbox WHERE done_at IS NULL AND error IS NULL)) ELSE NULL END
  ) INTO res;
  RETURN res;
END $$;
CREATE OR REPLACE FUNCTION agent.mcp_task_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid; q jsonb := p - 'assignee_email' - 'project' - 'agent' - 'approval'; t work.tasks; uid uuid; pid uuid; fid uuid; r jsonb;
BEGIN
  IF (p->>'id') IS NOT NULL THEN
    SELECT * INTO t FROM work.tasks WHERE id = (regexp_replace(p->>'id', '^T-', '', 'i'))::bigint;
    IF t.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy việc'; END IF;
    cid := t.company_id; q := q || jsonb_build_object('id', t.id);
  ELSE
    cid := coalesce(agent._uuid(p, 'company_id'), (SELECT company_id FROM core.memberships WHERE user_id = me.id AND active ORDER BY joined_at LIMIT 1));
    q := q || jsonb_build_object('company_id', cid);
  END IF;
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  IF p ? 'assignee_email' THEN
    SELECT u.id INTO uid FROM core.users u JOIN core.memberships m ON m.user_id = u.id AND m.company_id = cid AND m.active WHERE lower(u.email) = lower(btrim(p->>'assignee_email')) AND u.kind = 'person';
    IF uid IS NULL THEN RAISE EXCEPTION 'Không có thành viên có email %', p->>'assignee_email'; END IF;
    q := q || jsonb_build_object('assignee_id', uid);
  END IF;
  IF p ? 'project' AND coalesce(p->>'project', '') <> '' THEN
    SELECT id INTO pid FROM core.projects WHERE company_id = cid AND (slug = lower(btrim(p->>'project')) OR code = upper(btrim(p->>'project')) OR core.norm(name) = core.norm(p->>'project'));
    IF pid IS NULL THEN RAISE EXCEPTION 'Không có dự án "%"', p->>'project'; END IF;
    q := q || jsonb_build_object('project_id', pid);
  END IF;
  IF p ? 'agent' THEN q := q || jsonb_build_object('agent_role', coalesce(p->>'agent', '')); END IF;
  IF p ? 'approval' THEN
    IF (p->>'approval')::boolean THEN
      PERFORM agent._ensure_default_flows(cid);
      SELECT id INTO fid FROM core.approval_flows WHERE company_id = cid AND name = 'Người giao duyệt' AND active AND applies_to = 'task';
      IF fid IS NULL THEN RAISE EXCEPTION 'Chưa có quy trình "Người giao duyệt"'; END IF;
      q := q || jsonb_build_object('approval_flow_id', fid);
    ELSE q := q || jsonb_build_object('approval_flow_id', ''); END IF;
  END IF;
  r := agent.app_task_save(q);
  RETURN jsonb_build_object('id', 'T-' || (r->>'id'), 'url', 'https://work.enterpriseos.bond/app/#/tasks');
END $$;
REVOKE ALL ON FUNCTION agent.mcp_company_digest(jsonb), agent.mcp_task_save(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.mcp_company_digest(jsonb), agent.mcp_task_save(jsonb) TO mcp_svc;
COMMIT;
