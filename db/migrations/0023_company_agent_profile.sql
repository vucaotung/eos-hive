-- 0023 · Hồ sơ agent theo công ty (người phụ trách, phòng, chức danh) + RPC agent.app_members (người và agent) + agent.app_agent_set.
-- Nguồn chính: db/60_agent.sql (cột), db/62_workflow.sql (hàm, trigger). Idempotent. KHÔNG thêm agent vào core.memberships; agent.app_org vẫn chỉ trả người.
-- down: DROP FUNCTION agent.app_members(jsonb), agent.app_agent_set(jsonb); DROP TRIGGER company_agents_owner_chk ON agent.company_agents; DROP FUNCTION agent.company_agents_owner_chk();
--       ALTER TABLE agent.company_agents DROP COLUMN owner_user_id, DROP COLUMN department_id, DROP COLUMN title, DROP COLUMN updated_at;
BEGIN;
ALTER TABLE agent.company_agents ADD COLUMN IF NOT EXISTS owner_user_id uuid REFERENCES core.users(id) ON DELETE SET NULL;
ALTER TABLE agent.company_agents ADD COLUMN IF NOT EXISTS department_id uuid REFERENCES core.departments(id) ON DELETE SET NULL;
ALTER TABLE agent.company_agents ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE agent.company_agents ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE agent.company_agents DROP CONSTRAINT IF EXISTS company_agents_title_check;
ALTER TABLE agent.company_agents ADD CONSTRAINT company_agents_title_check CHECK (title IS NULL OR length(title) <= 80);
-- ---------- Thành viên gồm cả người và AI agent (tab "Thành viên") ----------
-- Agent KHÔNG có dòng core.memberships và agent.app_org vẫn chỉ trả người (u.kind = 'person'): ô chọn người phụ trách/người duyệt/báo cáo theo người dựa vào đó.
-- Agent hiện qua RPC riêng agent.app_members; chỉ owner/admin sửa được hồ sơ công ty của agent (agent.app_agent_set). max_level, can_delegate, skills, hermes_profile, action_levels
-- KHÔNG sửa được từ đây (quản trị hệ thống làm bằng SQL hoặc tab "Agent và MCP"). L3 không bao giờ mở cho agent.
CREATE OR REPLACE FUNCTION agent.company_agents_owner_chk() RETURNS trigger LANGUAGE plpgsql SET search_path = core, agent, public AS $$
BEGIN
  IF NEW.owner_user_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM core.memberships m JOIN core.users u ON u.id = m.user_id
        WHERE m.user_id = NEW.owner_user_id AND m.company_id = NEW.company_id AND m.active AND u.active AND u.kind = 'person') THEN
    RAISE EXCEPTION 'Người phụ trách agent phải là thành viên (người) đang hoạt động của công ty' USING ERRCODE = '23514';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS company_agents_owner_chk ON agent.company_agents;
CREATE TRIGGER company_agents_owner_chk BEFORE INSERT OR UPDATE OF owner_user_id, department_id, title, enabled ON agent.company_agents
  FOR EACH ROW EXECUTE FUNCTION agent.company_agents_owner_chk();

CREATE OR REPLACE FUNCTION agent.app_members(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); my text; tech boolean;
BEGIN
  my := agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  tech := my IN ('owner','admin');   -- cột kỹ thuật chỉ chủ sở hữu/quản trị công ty thấy
  RETURN jsonb_build_object(
    'tech', tech,
    'people', coalesce((SELECT jsonb_agg(jsonb_build_object('kind', 'person', 'user_id', m.user_id, 'department_id', m.department_id, 'role', agent._role_raw(m.user_id, cid), 'title', m.title,
                       'active', m.active, 'user', jsonb_build_object('id', u.id, 'name', u.name, 'email', u.email, 'avatar_url', u.avatar_url, 'drive_status', u.drive_state, 'active', u.active))
                       ORDER BY u.name)
                  FROM core.memberships m JOIN core.users u ON u.id = m.user_id WHERE m.company_id = cid AND u.kind = 'person'), '[]'),
    'agents', coalesce((SELECT jsonb_agg(x ORDER BY x->>'name') FROM (
      SELECT jsonb_build_object('kind', 'agent', 'code', g.code, 'name', g.name, 'title', ca.title, 'department_id', ca.department_id, 'description', g.description,
               'owner', CASE WHEN ca.owner_user_id IS NULL THEN NULL ELSE jsonb_build_object('id', ca.owner_user_id, 'name', (SELECT name FROM core.users WHERE id = ca.owner_user_id)) END,
               'status', CASE WHEN NOT g.active OR (NOT ca.enabled AND tk.n = 0) THEN 'off'
                              WHEN tk.n = 0 THEN 'no_token'
                              WHEN tk.first_exp < now() + interval '14 days' THEN 'expiring'
                              ELSE 'on' END)
             || CASE WHEN tech THEN jsonb_build_object(
               'agent_kind', g.kind, 'module', g.module, 'executor', g.executor, 'hermes_profile', g.hermes_profile, 'max_level', g.max_level, 'can_delegate', g.can_delegate,
               'skills', to_jsonb(g.skills), 'active', g.active, 'accepts_cards', ca.enabled, 'token_count', tk.n, 'token_expires', tk.first_exp, 'token_scopes', to_jsonb(tk.scopes),
               'last_active', greatest(act.mcp_at, act.ev_at), 'running', wk.running, 'waiting_human', wk.waiting) ELSE '{}'::jsonb END AS x
        FROM agent.company_agents ca JOIN agent.agents g ON g.id = ca.agent_id
        CROSS JOIN LATERAL (SELECT count(*)::int n, min(k.expires_at) first_exp, coalesce(array_agg(DISTINCT sc) FILTER (WHERE sc IS NOT NULL), '{}') scopes
                              FROM agent.mcp_tokens k LEFT JOIN LATERAL unnest(k.scopes) sc ON true
                             WHERE k.agent_id = g.id AND k.revoked_at IS NULL AND k.expires_at > now()) tk
        CROSS JOIN LATERAL (SELECT (SELECT max(c.at) FROM agent.mcp_calls c WHERE c.user_id = g.user_id) mcp_at,
                                   (SELECT max(e.received_at) FROM agent.events e JOIN agent.cards cd ON cd.id = e.card_ref WHERE cd.agent_id = g.id AND cd.company_id = cid) ev_at) act
        CROSS JOIN LATERAL (SELECT count(*) FILTER (WHERE t.status = 'in_progress')::int running, count(*) FILTER (WHERE t.waiting_on_human AND t.status NOT IN ('done','cancelled'))::int waiting
                              FROM work.tasks t WHERE t.agent_id = g.id AND t.company_id = cid) wk
       WHERE ca.company_id = cid) q), '[]'));
END $$;

CREATE OR REPLACE FUNCTION agent.app_agent_set(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); g agent.agents; ca agent.company_agents; v_title text; v_summary text := '';
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin']);
  SELECT x.* INTO g FROM agent.agents x WHERE x.code = btrim(coalesce(p->>'code', ''));
  SELECT y.* INTO ca FROM agent.company_agents y WHERE y.company_id = cid AND y.agent_id = g.id;
  IF g.id IS NULL OR ca.agent_id IS NULL THEN RAISE EXCEPTION 'Công ty không có agent này'; END IF;
  IF p ? 'enabled' THEN
    IF (p->>'enabled')::boolean AND NOT g.active THEN RAISE EXCEPTION 'Agent đang bị quản trị hệ thống tắt, chưa bật được' USING ERRCODE = '42501'; END IF;
    ca.enabled := (p->>'enabled')::boolean; v_summary := v_summary || ' enabled=' || ca.enabled;
  END IF;
  IF p ? 'owner_user_id' THEN
    ca.owner_user_id := agent._uuid(p, 'owner_user_id'); v_summary := v_summary || ' owner';   -- trigger kiểm: thành viên người của công ty
  END IF;
  IF p ? 'department_id' THEN
    ca.department_id := agent._uuid(p, 'department_id');
    IF ca.department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.departments WHERE id = ca.department_id AND company_id = cid) THEN RAISE EXCEPTION 'Phòng ban không thuộc công ty này'; END IF;
    v_summary := v_summary || ' phòng';
  END IF;
  IF p ? 'title' THEN
    v_title := nullif(btrim(coalesce(p->>'title', '')), '');
    IF length(coalesce(v_title, '')) > 80 THEN RAISE EXCEPTION 'Chức danh tối đa 80 ký tự'; END IF;
    ca.title := v_title; v_summary := v_summary || ' chức danh';
  END IF;
  UPDATE agent.company_agents SET enabled = ca.enabled, owner_user_id = ca.owner_user_id, department_id = ca.department_id, title = ca.title
   WHERE company_id = cid AND agent_id = g.id;
  PERFORM agent._audit(cid, me.id, 'agent_set', 'agent', g.code, 'Sửa hồ sơ agent ' || g.code || ':' || v_summary);
  RETURN jsonb_build_object('ok', true);
END $$;

GRANT EXECUTE ON FUNCTION agent.app_members(jsonb), agent.app_agent_set(jsonb) TO web_svc;
COMMIT;
