-- 0024 · agent.app_members: token_count đếm theo từng mã (trước đây đếm theo từng phạm vi do JOIN unnest: mã có 4 phạm vi hiện "4 mã").
-- Nguồn chính: db/62_workflow.sql. Idempotent. down: nạp lại agent.app_members bản 0023 (count(*)).
BEGIN;
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
        CROSS JOIN LATERAL (SELECT count(DISTINCT k.id)::int n, min(k.expires_at) first_exp, coalesce(array_agg(DISTINCT sc) FILTER (WHERE sc IS NOT NULL), '{}') scopes
                              FROM agent.mcp_tokens k LEFT JOIN LATERAL unnest(k.scopes) sc ON true
                             WHERE k.agent_id = g.id AND k.revoked_at IS NULL AND k.expires_at > now()) tk
        CROSS JOIN LATERAL (SELECT (SELECT max(c.at) FROM agent.mcp_calls c WHERE c.user_id = g.user_id) mcp_at,
                                   (SELECT max(e.received_at) FROM agent.events e JOIN agent.cards cd ON cd.id = e.card_ref WHERE cd.agent_id = g.id AND cd.company_id = cid) ev_at) act
        CROSS JOIN LATERAL (SELECT count(*) FILTER (WHERE t.status = 'in_progress')::int running, count(*) FILTER (WHERE t.waiting_on_human AND t.status NOT IN ('done','cancelled'))::int waiting
                              FROM work.tasks t WHERE t.agent_id = g.id AND t.company_id = cid) wk
       WHERE ca.company_id = cid) q), '[]'));
END $$;
GRANT EXECUTE ON FUNCTION agent.app_members(jsonb) TO web_svc;
COMMIT;
