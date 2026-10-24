-- 0019 · Chống tạo trùng của bot theo khóa (công ty, tên chuẩn hóa, người phụ trách, nguồn tin source_ref), 15 phút; trả duplicate + id + lý do.
-- Nguồn chính: db/62_workflow.sql. Idempotent. down: DROP TABLE agent.task_create_keys; nạp lại agent.mcp_task_save bản 0017.
BEGIN;
-- Khóa chống tạo trùng của bot (mcp_task_save); dọn bằng agent.housekeeping_prune
CREATE TABLE IF NOT EXISTS agent.task_create_keys (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  dkey        text NOT NULL,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  created_by  uuid NOT NULL REFERENCES core.users(id),
  task_id     bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS task_create_keys_idx ON agent.task_create_keys (dkey, created_at DESC);
REVOKE ALL ON agent.task_create_keys FROM PUBLIC;

CREATE OR REPLACE FUNCTION agent.mcp_task_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid; q jsonb := p - 'assignee_email' - 'project' - 'agent' - 'approval' - 'source_ref'; t work.tasks; uid uuid; pid uuid; fid uuid; r jsonb; v_dkey text; dup bigint;
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
  -- (2) Bot (Zalo hay gửi lại tin) có thể tạo trùng. Khóa chống trùng = (công ty, tên chuẩn hóa, người phụ trách, nguồn tin nếu có `source_ref`), trong 15 phút:
  --     cùng tên nhưng khác người phụ trách (hoặc khác nguồn) là hai việc khác nhau. Khóa tư vấn (advisory) giữ hai lần gọi đồng thời không cùng lọt qua.
  IF me.kind = 'agent' AND (p->>'id') IS NULL THEN
    SELECT id INTO uid FROM core.users u2 WHERE lower(u2.email) = lower(btrim(coalesce(p->>'assignee_email', ''))) AND u2.kind = 'person';
    v_dkey := md5(cid::text || '|' || core.norm(coalesce(p->>'title', '')) || '|' || coalesce(uid::text, '') || '|' || coalesce(nullif(btrim(p->>'source_ref'), ''), ''));
    PERFORM pg_advisory_xact_lock(hashtextextended(v_dkey, 0));
    SELECT k.task_id INTO dup FROM agent.task_create_keys k WHERE k.dkey = v_dkey AND k.created_at > now() - interval '15 minutes' ORDER BY k.created_at DESC LIMIT 1;
    IF dup IS NOT NULL THEN
      RETURN jsonb_build_object('id', 'T-' || dup, 'url', 'https://work.enterpriseos.bond/app/#/tasks', 'duplicate', true,
                                'reason', 'Đã có việc cùng tên, cùng người phụ trách' || CASE WHEN nullif(btrim(p->>'source_ref'), '') IS NOT NULL THEN ', cùng nguồn tin' ELSE '' END || ' tạo trong 15 phút qua');
    END IF;
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
  IF v_dkey IS NOT NULL THEN INSERT INTO agent.task_create_keys (dkey, company_id, created_by, task_id) VALUES (v_dkey, cid, me.id, (r->>'id')::bigint); END IF;
  RETURN jsonb_build_object('id', 'T-' || (r->>'id'), 'url', 'https://work.enterpriseos.bond/app/#/tasks');
END $$;
COMMIT;
