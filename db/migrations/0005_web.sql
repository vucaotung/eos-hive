-- 0005 · Lớp dữ liệu cho giao diện web (vai trò web_svc, hàm web_*) và sửa quyền PUBLIC trên hàm schema agent.
-- Phát hiện khi chuẩn bị web: REVOKE ALL ... FROM PUBLIC ở giữa db/60_agent.sql bỏ sót các hàm tạo sau đó (mcp_*, delegate, mcp_token_issue_agent,
-- và hàm thêm ở migration 0001-0004): vai trò agent_bridge gọi được cả những hàm đó. Migration này thu hồi lại cho toàn schema.
-- Idempotent (CREATE OR REPLACE; REVOKE/GRANT lặp được). Tài khoản đăng nhập eos_web tạo riêng khi triển khai (mật khẩu không nằm trong migration).
-- down: REVOKE EXECUTE các hàm web_* khỏi web_svc và DROP FUNCTION agent.web_*, agent._web_*; DROP ROLE web_svc. (Quyền PUBLIC đã thu hồi không cần trả lại.)
BEGIN;
-- ---------- Web (giao diện người dùng): vai trò web_svc và các hàm web_* ----------
-- Web chạy như dịch vụ riêng (đăng nhập eos_web, thành viên web_svc). Mọi thao tác đi qua hàm SECURITY DEFINER mang danh tính
-- người đăng nhập (request.jwt.claims.sub), không truy cập bảng trực tiếp. Quản trị dùng core.users.is_system_admin.
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_svc') THEN CREATE ROLE web_svc NOLOGIN; END IF; END $$;
GRANT USAGE ON SCHEMA agent, core, work TO web_svc;

CREATE OR REPLACE FUNCTION agent._web_me() RETURNS core.users
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE u core.users;
BEGIN
  SELECT * INTO u FROM core.users WHERE id = core.current_user_id() AND active AND kind = 'person';
  IF u.id IS NULL THEN RAISE EXCEPTION 'Chưa đăng nhập hoặc tài khoản bị khóa' USING ERRCODE = '42501'; END IF;
  RETURN u;
END $$;

CREATE OR REPLACE FUNCTION agent._web_admin() RETURNS core.users
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE u core.users := agent._web_me();
BEGIN
  IF NOT u.is_system_admin THEN RAISE EXCEPTION 'Chỉ quản trị hệ thống' USING ERRCODE = '42501'; END IF;
  RETURN u;
END $$;

-- Đăng nhập Google: chỉ người đã có trong core.users (active, kind=person) mới vào được; sub Google gắn lần đầu và phải khớp các lần sau
CREATE OR REPLACE FUNCTION agent.web_login(p_email text, p_sub text, p_name text, p_avatar text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE u core.users; cid uuid;
BEGIN
  IF coalesce(p_email, '') = '' OR coalesce(p_sub, '') = '' THEN RETURN jsonb_build_object('ok', false, 'reason', 'invalid'); END IF;
  SELECT * INTO u FROM core.users WHERE lower(email) = lower(p_email) AND kind = 'person' AND active;
  IF u.id IS NULL THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_allowed'); END IF;
  IF u.google_sub IS NOT NULL AND u.google_sub <> p_sub THEN RETURN jsonb_build_object('ok', false, 'reason', 'sub_mismatch'); END IF;
  UPDATE core.users SET google_sub = coalesce(google_sub, p_sub), last_login_at = now(),
         avatar_url = coalesce(avatar_url, nullif(p_avatar, '')), name = coalesce(nullif(name, ''), p_name) WHERE id = u.id;
  SELECT company_id INTO cid FROM core.memberships WHERE user_id = u.id AND active ORDER BY joined_at LIMIT 1;
  IF cid IS NOT NULL THEN
    INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
    VALUES (cid, 'user:' || u.id, u.id, 'web', 'login', 'user', u.id::text, 'Đăng nhập web (Google)');
  END IF;
  RETURN jsonb_build_object('ok', true, 'user_id', u.id, 'name', coalesce(nullif(u.name, ''), p_name), 'email', u.email, 'is_admin', u.is_system_admin);
END $$;

CREATE OR REPLACE FUNCTION agent.web_me() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me();
BEGIN
  RETURN agent.mcp_whoami() || jsonb_build_object('is_admin', me.is_system_admin, 'avatar_url', me.avatar_url,
    'agents', coalesce((SELECT jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'description', g.description) ORDER BY g.code)
                          FROM agent.agents g
                         WHERE g.active AND EXISTS (SELECT 1 FROM agent.company_agents ca JOIN core.memberships m ON m.company_id = ca.company_id AND m.user_id = me.id AND m.active
                                                     WHERE ca.agent_id = g.id AND ca.enabled)), '[]'));
END $$;

-- Tạo việc từ web, giao cho agent (tùy chọn). Người tạo cũng là người phụ trách (và là người duyệt kết quả của agent).
CREATE OR REPLACE FUNCTION agent.web_create_task(p_title text, p_description text, p_agent text DEFAULT NULL, p_due date DEFAULT NULL, p_priority text DEFAULT 'medium') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); m record; a agent.agents; new_id bigint;
BEGIN
  IF length(btrim(coalesce(p_title, ''))) < 3 OR length(p_title) > 300 THEN RAISE EXCEPTION 'Tiêu đề từ 3 đến 300 ký tự'; END IF;
  IF length(coalesce(p_description, '')) > 8000 THEN RAISE EXCEPTION 'Mô tả tối đa 8000 ký tự'; END IF;
  IF p_priority NOT IN ('low', 'medium', 'high', 'urgent') THEN RAISE EXCEPTION 'Mức ưu tiên không hợp lệ'; END IF;
  SELECT company_id, department_id INTO m FROM core.memberships WHERE user_id = me.id AND active ORDER BY joined_at LIMIT 1;
  IF m.company_id IS NULL THEN RAISE EXCEPTION 'Bạn chưa thuộc công ty nào'; END IF;
  IF coalesce(p_agent, '') <> '' THEN
    SELECT g.* INTO a FROM agent.agents g
     WHERE g.code = p_agent AND g.active
       AND EXISTS (SELECT 1 FROM agent.company_agents ca WHERE ca.company_id = m.company_id AND ca.agent_id = g.id AND ca.enabled);
    IF a.id IS NULL THEN RAISE EXCEPTION 'Agent % chưa bật cho công ty', p_agent; END IF;
  END IF;
  INSERT INTO work.tasks (company_id, department_id, title, description, priority, assignee_id, agent_id, created_by, due_date)
  VALUES (m.company_id, m.department_id, btrim(p_title), nullif(btrim(coalesce(p_description, '')), ''), p_priority::work.task_priority, me.id, a.id, me.id, p_due)
  RETURNING id INTO new_id;
  INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
  VALUES (m.company_id, 'user:' || me.id, me.id, 'web', 'create', 'task', new_id::text, 'Tạo việc từ web' || CASE WHEN a.id IS NOT NULL THEN ' giao cho ' || a.code ELSE '' END);
  RETURN jsonb_build_object('id', 'T-' || new_id, 'agent', a.code);
END $$;

-- Chi tiết việc cho màn hình: mcp_task (đã kiểm quyền xem) kèm cờ thao tác và thẻ gần nhất
CREATE OR REPLACE FUNCTION agent.web_task(p_task bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; j jsonb := agent.mcp_task(p_task);
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  RETURN j || jsonb_build_object(
    'flags', jsonb_build_object(
      'can_review', t.status = 'in_review' AND t.agent_id IS NOT NULL
                    AND me.id IS NOT DISTINCT FROM coalesce(t.created_by, (SELECT default_reviewer FROM agent.company_settings WHERE company_id = t.company_id)),
      'can_answer', t.waiting_on_human AND (t.assignee_id = me.id OR t.created_by = me.id),
      'can_cancel', t.status NOT IN ('done', 'cancelled') AND (t.created_by = me.id OR t.assignee_id = me.id)),
    'reports', coalesce((SELECT jsonb_agg(jsonb_build_object('at', r.created_at, 'agent', (SELECT code FROM agent.agents WHERE id = r.agent_id), 'summary', r.summary,
                          'outputs', r.outputs, 'sources', r.sources, 'checks', r.checks, 'confidence', r.confidence, 'residual_risk', r.residual_risk,
                          'next_actions', r.next_actions, 'verdict', r.verdict) ORDER BY r.created_at DESC) FROM agent.reports r WHERE r.task_id = p_task), '[]'),
    'cards', coalesce((SELECT jsonb_agg(jsonb_build_object('card_id', c.card_id, 'kind', c.kind, 'attempt', c.attempt, 'status', c.status, 'last_event_at', c.last_event_at) ORDER BY c.id DESC)
                         FROM (SELECT * FROM agent.cards WHERE task_id = p_task ORDER BY id DESC LIMIT 5) c), '[]'));
END $$;

CREATE OR REPLACE FUNCTION agent.web_cancel_task(p_task bigint, p_reason text DEFAULT NULL) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task FOR UPDATE;
  IF t.id IS NULL OR NOT (t.created_by = me.id OR t.assignee_id = me.id) THEN RAISE EXCEPTION 'Không có quyền hủy T-%', p_task USING ERRCODE = '42501'; END IF;
  IF t.status IN ('done', 'cancelled') THEN RETURN 'already_closed'; END IF;
  UPDATE work.tasks SET status = 'cancelled', completed_at = NULL, kpi_counted = false, updated_at = now() WHERE id = p_task;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body)
  VALUES (p_task, me.id, 'user:' || me.id, 'note', 'Hủy việc' || CASE WHEN btrim(coalesce(p_reason, '')) <> '' THEN ': ' || left(btrim(p_reason), 500) ELSE '' END);
  RETURN 'cancelled';
END $$;

-- Mã MCP của chính người dùng (màn hình "Kết nối AI agent")
CREATE OR REPLACE FUNCTION agent.web_my_tokens() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me();
BEGIN
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'client', k.client, 'prefix', k.prefix, 'scopes', k.scopes,
           'expires_at', k.expires_at, 'revoked_at', k.revoked_at, 'last_used_at', k.last_used_at, 'active', (k.revoked_at IS NULL AND k.expires_at > now())) ORDER BY k.created_at DESC)
      FROM (SELECT * FROM agent.mcp_tokens WHERE user_id = me.id AND agent_id IS NULL ORDER BY created_at DESC LIMIT 50) k), '[]');
END $$;

CREATE OR REPLACE FUNCTION agent.web_token_issue(p_name text, p_client text, p_scopes text[], p_days int DEFAULT 30) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); raw text; cid uuid;
BEGIN
  IF length(btrim(coalesce(p_name, ''))) < 2 OR length(p_name) > 60 THEN RAISE EXCEPTION 'Tên mã từ 2 đến 60 ký tự'; END IF;
  IF p_days IS NULL OR p_days NOT BETWEEN 1 AND 90 THEN RAISE EXCEPTION 'Hạn mã từ 1 đến 90 ngày'; END IF;
  IF p_scopes IS NULL OR cardinality(p_scopes) = 0 OR NOT (p_scopes <@ ARRAY['read', 'write', 'drive', 'hr_self', 'kb']::text[]) THEN
    RAISE EXCEPTION 'Phạm vi không hợp lệ (read, write, drive, hr_self, kb)';
  END IF;
  raw := agent.mcp_token_issue(btrim(p_name), coalesce(nullif(p_client, ''), 'other'), p_scopes, p_days);
  SELECT company_id INTO cid FROM core.memberships WHERE user_id = me.id AND active ORDER BY joined_at LIMIT 1;
  IF cid IS NOT NULL THEN
    INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
    VALUES (cid, 'user:' || me.id, me.id, 'web', 'token_issue', 'mcp_token', substr(raw, 5, 8), 'Cấp mã MCP "' || left(btrim(p_name), 60) || '" phạm vi ' || array_to_string(p_scopes, ','));
  END IF;
  RETURN jsonb_build_object('token', raw, 'prefix', substr(raw, 5, 8));
END $$;

CREATE OR REPLACE FUNCTION agent.web_token_revoke(p_id uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me();
BEGIN
  RETURN coalesce(agent.mcp_token_revoke(p_id), false);   -- chính chủ, hoặc quản trị hệ thống
END $$;

-- Quản trị: tổng quan agent, cầu nối, việc, MCP
CREATE OR REPLACE FUNCTION agent.web_admin_overview() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_admin();
BEGIN
  RETURN jsonb_build_object(
    'agents', coalesce((SELECT jsonb_agg(jsonb_build_object('code', g.code, 'name', g.name, 'module', g.module, 'profile', g.hermes_profile, 'active', g.active,
        'max_level', g.max_level, 'skills', g.skills,
        'tasks_open', (SELECT count(*) FROM work.tasks t WHERE t.agent_id = g.id AND t.status NOT IN ('done', 'cancelled')),
        'cards_running', (SELECT count(*) FROM agent.cards c WHERE c.agent_id = g.id AND c.status = 'running'),
        'last_event', (SELECT max(c.last_event_at) FROM agent.cards c WHERE c.agent_id = g.id),
        'token_days_left', (SELECT min(extract(day FROM k.expires_at - now())::int) FROM agent.mcp_tokens k WHERE k.agent_id = g.id AND k.revoked_at IS NULL AND k.expires_at > now()),
        'token_scopes', (SELECT k.scopes FROM agent.mcp_tokens k WHERE k.agent_id = g.id AND k.revoked_at IS NULL AND k.expires_at > now() ORDER BY k.created_at DESC LIMIT 1)) ORDER BY g.code)
      FROM agent.agents g), '[]'),
    'bridge', jsonb_build_object(
      'outbox_pending', (SELECT count(*) FROM agent.outbox WHERE done_at IS NULL),
      'outbox_oldest_pending_s', (SELECT coalesce(extract(epoch FROM now() - min(created_at))::int, 0) FROM agent.outbox WHERE done_at IS NULL),
      'outbox_errors', (SELECT count(*) FROM agent.outbox WHERE done_at IS NULL AND error IS NOT NULL),
      'cards_stuck_running', (SELECT count(*) FROM agent.cards WHERE status = 'running' AND last_event_at < now() - interval '2 hours'),
      'last_card_event', (SELECT max(last_event_at) FROM agent.cards)),
    'tasks', coalesce((SELECT jsonb_object_agg(s, n) FROM (SELECT status::text AS s, count(*) AS n FROM work.tasks GROUP BY 1) x), '{}'),
    'confirmations_pending', (SELECT count(*) FROM agent.confirmations WHERE state = 'pending'),
    'mcp', jsonb_build_object(
      'calls_24h', (SELECT count(*) FROM agent.mcp_calls WHERE at > now() - interval '1 day'),
      'denied_24h', (SELECT count(*) FROM agent.mcp_calls WHERE at > now() - interval '1 day' AND outcome = 'denied')));
END $$;

CREATE OR REPLACE FUNCTION agent.web_admin_tokens() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_admin();
BEGIN
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'client', k.client, 'prefix', k.prefix, 'scopes', k.scopes,
           'who', CASE WHEN k.agent_id IS NOT NULL THEN 'agent:' || (SELECT code FROM agent.agents WHERE id = k.agent_id) ELSE (SELECT email FROM core.users WHERE id = k.user_id) END,
           'expires_at', k.expires_at, 'revoked_at', k.revoked_at, 'last_used_at', k.last_used_at, 'last_ip', host(k.last_ip),
           'active', (k.revoked_at IS NULL AND k.expires_at > now())) ORDER BY k.created_at DESC)
      FROM (SELECT * FROM agent.mcp_tokens ORDER BY created_at DESC LIMIT 200) k), '[]');
END $$;

CREATE OR REPLACE FUNCTION agent.web_admin_calls(p_limit int DEFAULT 100, p_denied_only boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_admin();
BEGIN
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('at', c.at, 'tool', c.tool, 'outcome', c.outcome, 'ms', c.ms, 'entity', coalesce(c.entity_type || ':' || c.entity_id, ''),
           'prefix', k.prefix, 'who', CASE WHEN k.agent_id IS NOT NULL THEN 'agent:' || (SELECT code FROM agent.agents WHERE id = k.agent_id) ELSE (SELECT email FROM core.users WHERE id = c.user_id) END) ORDER BY c.at DESC)
      FROM (SELECT * FROM agent.mcp_calls WHERE (NOT p_denied_only OR outcome = 'denied') ORDER BY at DESC LIMIT least(greatest(p_limit, 1), 500)) c
      LEFT JOIN agent.mcp_tokens k ON k.id = c.token_id), '[]');
END $$;

-- Quyền: không hàm nào trong schema agent cho PUBLIC chạy (sửa lỗi: REVOKE giữa tệp bỏ sót các hàm tạo sau nó);
-- cầu nối chỉ gọi 4 hàm (docs/01); web_svc chỉ gọi các hàm bên dưới
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA agent FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.web_login(text, text, text, text), agent.web_me(), agent.web_create_task(text, text, text, date, text),
  agent.web_task(bigint), agent.web_cancel_task(bigint, text), agent.web_my_tokens(), agent.web_token_issue(text, text, text[], int),
  agent.web_token_revoke(uuid), agent.web_admin_overview(), agent.web_admin_tokens(), agent.web_admin_calls(int, boolean),
  agent.mcp_my_tasks(text, text, int), agent.mcp_my_day(), agent.mcp_comment(bigint, text, text),
  agent.accept_result(bigint, text), agent.reject_result(bigint, text) TO web_svc;
COMMIT;
