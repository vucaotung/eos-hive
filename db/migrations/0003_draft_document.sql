-- 0003 · Văn thư AI soạn dự thảo .docx (công cụ MCP eos_draft_document): hàm ghi tệp cho agent và phạm vi `draft`.
-- Idempotent (CREATE OR REPLACE). Mã agent đã cấp trước đây KHÔNG có phạm vi draft: cấp lại cho van-thu (scripts/issue_agent_token.sh).
-- down: DROP FUNCTION agent.mcp_agent_register_file(bigint,text,text,text,text,bigint,text,text), agent.mcp_agent_drive_target(bigint), agent._agent_owner(bigint);
--       trả hai ràng buộc mcp_tokens_scopes_check, mcp_tokens_check1 về bản không có 'draft' (cần không còn mã draft), nạp lại agent.mcp_token_issue_agent bản 0002.
BEGIN;
-- Phạm vi mới `draft`: thêm vào tập hợp lệ; chỉ mã agent được mang (mã của người không có delegate/draft)
ALTER TABLE agent.mcp_tokens DROP CONSTRAINT IF EXISTS mcp_tokens_scopes_check;
ALTER TABLE agent.mcp_tokens ADD CONSTRAINT mcp_tokens_scopes_check
  CHECK (scopes <@ ARRAY['read','write','drive','hr_self','kb','delegate','draft']::text[] AND cardinality(scopes) > 0);
ALTER TABLE agent.mcp_tokens DROP CONSTRAINT IF EXISTS mcp_tokens_check1;
ALTER TABLE agent.mcp_tokens ADD CONSTRAINT mcp_tokens_check1
  CHECK (CASE WHEN agent_id IS NULL THEN NOT ('delegate' = ANY (scopes) OR 'draft' = ANY (scopes))
              ELSE scopes <@ ARRAY['read','kb','delegate','draft']::text[] END);

-- Văn thư AI soạn dự thảo văn bản: lưu .docx vào Drive của NGƯỜI PHỤ TRÁCH việc. Chỉ khi agent đang có thẻ chạy cho việc đó.
CREATE OR REPLACE FUNCTION agent._agent_owner(p_task bigint) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE a agent.agents := agent.current_agent(); t work.tasks;
BEGIN
  IF a.id IS NULL THEN RAISE EXCEPTION 'Chỉ dành cho agent hệ thống' USING ERRCODE = '42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM agent.cards WHERE task_id = p_task AND agent_id = a.id AND status IN ('todo','ready','running','blocked','review')) THEN
    RAISE EXCEPTION 'Agent % không có thẻ đang chạy cho T-%', a.code, p_task USING ERRCODE = '42501';
  END IF;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  RETURN coalesce(t.assignee_id, t.created_by);
END $$;

CREATE OR REPLACE FUNCTION agent.mcp_agent_drive_target(p_task bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE owner uuid := agent._agent_owner(p_task); u record;
BEGIN
  SELECT drive_folder_id, drive_state INTO u FROM core.users WHERE id = owner;
  RETURN jsonb_build_object('drive_folder_id', u.drive_folder_id, 'drive_state', u.drive_state);
END $$;

CREATE OR REPLACE FUNCTION agent.mcp_agent_register_file(p_task bigint, p_drive_id text, p_name text, p_mime text, p_url text,
                                                         p_bytes bigint, p_folder text, p_sha256 text DEFAULT NULL) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE a agent.agents := agent.current_agent(); owner uuid := agent._agent_owner(p_task);
BEGIN
  -- mượn quyền người phụ trách (như mcp_agent_task) để ghi tệp vào việc của họ; nhật ký ghi rõ agent nào làm
  PERFORM set_config('request.jwt.claims', json_build_object('sub', owner, 'via', 'agent:' || a.code, 'agent', a.id)::text, true);
  RETURN agent.mcp_register_file(p_task, p_drive_id, p_name, p_mime, p_url, p_bytes, p_folder, p_sha256);
END $$;

-- Phạm vi `draft`: agent phân hệ văn thư (module doc) được soạn dự thảo văn bản
CREATE OR REPLACE FUNCTION agent.mcp_token_issue_agent(p_agent text, p_days int DEFAULT 90) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE a agent.agents; raw text; sc text[];
BEGIN
  IF NOT coalesce((SELECT is_system_admin FROM core.users WHERE id = core.current_user_id()), false) THEN
    RAISE EXCEPTION 'Chỉ quản trị hệ thống cấp mã cho agent' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO a FROM agent.agents WHERE code = p_agent AND active;
  IF a.id IS NULL THEN RAISE EXCEPTION 'Không có agent %', p_agent; END IF;
  sc := CASE WHEN a.can_delegate THEN '{read,kb,delegate}'::text[] ELSE '{read,kb}'::text[] END;
  IF a.module = 'doc' THEN sc := sc || '{draft}'::text[]; END IF;
  raw := 'eos_' || encode(gen_random_bytes(24), 'hex');
  INSERT INTO agent.mcp_tokens (user_id, agent_id, name, client, prefix, token_hash, scopes, expires_at)
  VALUES (a.user_id, a.id, 'Agent ' || a.code, 'hermes', substr(raw, 5, 8), encode(digest(raw, 'sha256'), 'hex'), sc,
          now() + make_interval(days => least(greatest(p_days, 1), 365)));
  RETURN raw;
END $$;

GRANT EXECUTE ON FUNCTION agent.mcp_agent_drive_target(bigint),
  agent.mcp_agent_register_file(bigint, text, text, text, text, bigint, text, text) TO mcp_svc;
COMMIT;
