-- 0016 · Phạm vi mã `task_create` cho agent (Mai nhận yêu cầu): tạo việc mới + bình luận thường, KHÔNG sửa việc/đổi trạng thái/trả lời thay agent.
-- Thêm cột agent.agents.token_scopes (thu hẹp phạm vi mã của một agent), vai trò mẫu `tro_ly_ai`, quyền work.comment.create và kb.ask.
-- Nguồn chính: db/60_agent.sql, db/62_workflow.sql. Idempotent.
-- down: UPDATE agent.agents SET token_scopes = NULL; thu hồi mã có task_create (UPDATE agent.mcp_tokens SET revoked_at = now() WHERE 'task_create' = ANY(scopes));
--       DELETE FROM core.roles WHERE company_id IS NULL AND code = 'tro_ly_ai' (cần không còn user_roles); DROP COLUMN agent.agents.token_scopes; trả ràng buộc về bản 0009; nạp lại agent.mcp_token_issue_agent bản 0009.
BEGIN;
ALTER TABLE agent.agents DROP CONSTRAINT IF EXISTS agents_token_scopes_check;
ALTER TABLE agent.agents ADD COLUMN IF NOT EXISTS token_scopes text[];
ALTER TABLE agent.agents ADD CONSTRAINT agents_token_scopes_check
  CHECK (token_scopes IS NULL OR (token_scopes <@ ARRAY['read','kb','delegate','draft','project','runner','ingest','task_create']::text[] AND cardinality(token_scopes) > 0));
DO $$ DECLARE c record; BEGIN
  FOR c IN SELECT conname FROM pg_constraint WHERE conrelid = 'agent.mcp_tokens'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%scopes%' LOOP
    EXECUTE format('ALTER TABLE agent.mcp_tokens DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;
ALTER TABLE agent.mcp_tokens ADD CONSTRAINT mcp_tokens_scopes_check
  CHECK (scopes <@ ARRAY['read','write','drive','hr_self','kb','delegate','draft','project','runner','ingest','task_create']::text[] AND cardinality(scopes) > 0);
ALTER TABLE agent.mcp_tokens ADD CONSTRAINT mcp_tokens_agent_scope_check
  CHECK (CASE WHEN agent_id IS NULL THEN NOT (scopes && ARRAY['delegate','draft','project','runner','ingest','task_create']::text[]) ELSE scopes <@ ARRAY['read','kb','delegate','draft','project','runner','ingest','task_create']::text[] END);
CREATE OR REPLACE FUNCTION agent.mcp_token_issue_agent(p_agent text, p_days int DEFAULT 90) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE a agent.agents; raw text; sc text[];
BEGIN
  IF NOT coalesce((SELECT is_system_admin FROM core.users WHERE id = core.current_user_id()), false) THEN
    RAISE EXCEPTION 'Chỉ quản trị hệ thống cấp mã cho agent' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO a FROM agent.agents WHERE code = p_agent AND active;
  IF a.id IS NULL THEN RAISE EXCEPTION 'Không có agent %', p_agent; END IF;
  IF a.token_scopes IS NOT NULL THEN sc := a.token_scopes;   -- agent có phạm vi riêng (vd. mai: read + task_create)
  ELSIF a.executor = 'runner' THEN sc := '{runner}'::text[];
  ELSE
    sc := CASE WHEN a.can_delegate THEN '{read,kb,delegate,project}'::text[] ELSE '{read,kb,project}'::text[] END;
    IF a.module = 'doc' THEN sc := sc || '{draft}'::text[]; END IF;
    IF a.module = 'kb' THEN sc := sc || '{ingest}'::text[]; END IF;   -- chỉ agent phân hệ kho tri thức được nạp (eos_kb_ingest)
  END IF;
  raw := 'eos_' || encode(gen_random_bytes(24), 'hex');
  INSERT INTO agent.mcp_tokens (user_id, agent_id, name, client, prefix, token_hash, scopes, expires_at)
  VALUES (a.user_id, a.id, 'Agent ' || a.code, CASE WHEN a.executor = 'runner' THEN 'other' ELSE 'hermes' END, substr(raw, 5, 8), encode(digest(raw, 'sha256'), 'hex'), sc,
          now() + make_interval(days => least(greatest(p_days, 1), 365)));
  RETURN raw;
END $$;
-- ---------- Vai trò tối thiểu cho trợ lý AI nhận yêu cầu (Mai) ----------
-- Chỉ: giao việc, xem việc mình tạo/được giao (phạm vi own), bình luận, hỏi kho dữ liệu. Không sửa việc, không xem báo cáo, không quản trị.
INSERT INTO core.permissions (code, module, area, name, scoped, sort) VALUES
 ('work.comment.create', 'work', 'Công việc',   'Bình luận vào việc',        false, 25),
 ('kb.ask',              'kb',   'Kho dữ liệu', 'Hỏi Kho dữ liệu chung',     false, 70)
ON CONFLICT (code) DO NOTHING;
INSERT INTO core.roles (company_id, code, name, description, builtin)
SELECT NULL, 'tro_ly_ai', 'Trợ lý AI', 'Bot tiếp nhận yêu cầu: tạo việc, bình luận, hỏi kho dữ liệu; chỉ thấy việc mình tạo hoặc được giao', true
 WHERE NOT EXISTS (SELECT 1 FROM core.roles r WHERE r.company_id IS NULL AND r.code = 'tro_ly_ai');
INSERT INTO core.role_permissions (role_id, permission, scope)
SELECT r.id, v.p, v.s::core.perm_scope FROM core.roles r,
  (VALUES ('work.task.create','company'), ('work.task.view','own'), ('work.comment.create','company'), ('kb.ask','company')) v(p, s)
 WHERE r.company_id IS NULL AND r.code = 'tro_ly_ai'
ON CONFLICT (role_id, permission) DO NOTHING;

CREATE OR REPLACE FUNCTION agent._web_me() RETURNS core.users
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE u core.users;
BEGIN
  -- Người dùng thật; ngoại lệ DUY NHẤT: tài khoản agent được cấp phạm vi task_create (Mai), chỉ qua các hàm mcp_* có kiểm tra thêm (mcp_task_save chặn sửa/đổi trạng thái/giao agent)
  SELECT * INTO u FROM core.users x WHERE x.id = core.current_user_id() AND x.active
     AND (x.kind = 'person' OR (x.kind = 'agent' AND EXISTS (SELECT 1 FROM agent.agents g WHERE g.user_id = x.id AND g.active AND 'task_create' = ANY(g.token_scopes))));
  IF u.id IS NULL THEN RAISE EXCEPTION 'Chưa đăng nhập hoặc tài khoản bị khóa' USING ERRCODE = '42501'; END IF;
  RETURN u;
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
