-- 0017 · Rà soát logic MCP: (1) trả lời agent qua eos_comment phải đúng luật như web (người phụ trách/giao/sửa được, và agent đang chờ); (2) bot tạo việc không tạo trùng trong 15 phút.
-- Nguồn chính: db/62_workflow.sql. Idempotent. down: nạp lại agent.mcp_comment bản db/60_agent.sql và agent.mcp_task_save bản 0016.
BEGIN;
CREATE OR REPLACE FUNCTION agent.mcp_comment(p_task bigint, p_body text, p_kind text DEFAULT 'note') RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); new_id bigint; t work.tasks;
BEGIN
  IF NOT work.can_view_task(me, p_task) THEN RAISE EXCEPTION 'Không có quyền với T-%', p_task USING ERRCODE = '42501'; END IF;
  IF p_kind NOT IN ('note','answer') THEN RAISE EXCEPTION 'Loại bình luận không hợp lệ'; END IF;
  IF btrim(coalesce(p_body, '')) = '' THEN RAISE EXCEPTION 'Nhập nội dung'; END IF;
  IF p_kind = 'answer' THEN
    SELECT * INTO t FROM work.tasks WHERE id = p_task;
    IF NOT (t.waiting_on_human AND t.status NOT IN ('done','cancelled')) THEN RAISE EXCEPTION 'Agent không đang chờ trả lời việc này'; END IF;
    IF NOT (t.assignee_id = me OR t.created_by = me OR agent._can_edit(me, t)) THEN RAISE EXCEPTION 'Chỉ người phụ trách hoặc người giao trả lời được' USING ERRCODE = '42501'; END IF;
  END IF;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task, me, agent._mcp_actor(), p_kind::work.comment_kind, left(p_body, 8000))
  RETURNING id INTO new_id;
  RETURN new_id;
END $$;
CREATE OR REPLACE FUNCTION agent.mcp_task_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid; q jsonb := p - 'assignee_email' - 'project' - 'agent' - 'approval'; t work.tasks; uid uuid; pid uuid; fid uuid; r jsonb;
BEGIN
  IF me.kind = 'agent' AND ((p->>'id') IS NOT NULL OR p ? 'status' OR coalesce(p->>'agent', '') <> '') THEN
    RAISE EXCEPTION 'Tài khoản agent chỉ được tạo việc mới cho người, không sửa việc, không đổi trạng thái, không giao cho agent' USING ERRCODE = '42501';
  END IF;
  IF (p->>'id') IS NOT NULL THEN
    SELECT * INTO t FROM work.tasks WHERE id = (regexp_replace(p->>'id', '^T-', '', 'i'))::bigint;
    IF t.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy việc'; END IF;
    cid := t.company_id; q := q || jsonb_build_object('id', t.id);
  ELSE
    cid := coalesce(agent._uuid(p, 'company_id'), (SELECT company_id FROM core.memberships WHERE user_id = me.id AND active ORDER BY joined_at LIMIT 1));
    q := q || jsonb_build_object('company_id', cid);
  END IF;
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  -- (2) Bot (Zalo hay gửi lại tin) có thể tạo trùng: cùng người tạo + cùng tên + cùng người phụ trách trong 15 phút thì trả lại việc cũ
  IF me.kind = 'agent' AND (p->>'id') IS NULL THEN
    SELECT id INTO t.id FROM work.tasks
     WHERE created_by = me.id AND company_id = cid AND created_at > now() - interval '15 minutes' AND lower(btrim(title)) = lower(btrim(coalesce(p->>'title', '')))
       AND assignee_id IS NOT DISTINCT FROM (SELECT u2.id FROM core.users u2 WHERE lower(u2.email) = lower(btrim(coalesce(p->>'assignee_email', ''))) AND u2.kind = 'person')
     ORDER BY id DESC LIMIT 1;
    IF t.id IS NOT NULL THEN RETURN jsonb_build_object('id', 'T-' || t.id, 'url', 'https://work.enterpriseos.bond/app/#/tasks', 'duplicate', true); END IF;
  END IF;
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
COMMIT;
