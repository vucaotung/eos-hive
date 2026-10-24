-- 0015 · agent.mcp_list_members (đổi tên người thành email khi giao việc qua MCP) và khép lần chạy nạp hồ sơ khi việc gốc xong/hủy.
-- Nguồn chính: db/62_workflow.sql. Idempotent. down: DROP TRIGGER workflow_run_close ON work.tasks; DROP FUNCTION agent.workflow_run_close_trg(), agent.mcp_list_members(jsonb).
BEGIN;
CREATE OR REPLACE FUNCTION agent.mcp_list_members(p jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := coalesce(agent._uuid(p, 'company_id'), (SELECT company_id FROM core.memberships WHERE user_id = me.id AND active ORDER BY joined_at LIMIT 1));
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('name', u.name, 'email', u.email, 'department', d.code, 'role', agent._role_of(u.id, cid), 'title', m.title) ORDER BY u.name)
                     FROM core.memberships m JOIN core.users u ON u.id = m.user_id AND u.kind = 'person' AND u.active LEFT JOIN core.departments d ON d.id = m.department_id
                    WHERE m.company_id = cid AND m.active), '[]');
END $$;
CREATE OR REPLACE FUNCTION agent.workflow_run_close_trg() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, public AS $$
BEGIN
  IF NEW.status IN ('done','cancelled') AND OLD.status IS DISTINCT FROM NEW.status THEN
    UPDATE agent.workflow_runs SET state = CASE WHEN NEW.status = 'done' THEN 'done' ELSE 'cancelled' END WHERE root_task = NEW.id AND state = 'running';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS workflow_run_close ON work.tasks;
CREATE TRIGGER workflow_run_close AFTER UPDATE OF status ON work.tasks FOR EACH ROW EXECUTE FUNCTION agent.workflow_run_close_trg();
UPDATE agent.workflow_runs r SET state = 'done' FROM work.tasks t WHERE t.id = r.root_task AND r.state = 'running' AND t.status = 'done';
UPDATE agent.workflow_runs r SET state = 'cancelled' FROM work.tasks t WHERE t.id = r.root_task AND r.state = 'running' AND t.status = 'cancelled';
REVOKE ALL ON FUNCTION agent.mcp_list_members(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.mcp_list_members(jsonb) TO mcp_svc;
COMMIT;
