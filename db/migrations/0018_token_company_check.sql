-- 0018 · agent.mcp_token_issue: tham số công ty phải được kiểm quyền (trước đây tin tham số, không ai kiểm).
-- Nguồn chính: db/60_agent.sql. Idempotent. down: nạp lại bản 0001 của hàm (không kiểm công ty).
BEGIN;
CREATE OR REPLACE FUNCTION agent.mcp_token_issue(p_name text, p_client text, p_scopes text[], p_days int DEFAULT 90, p_company uuid DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me uuid := core.current_user_id(); raw text;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'Chưa đăng nhập' USING ERRCODE = '42501'; END IF;
  IF (SELECT kind FROM core.users WHERE id = me) <> 'person' THEN RAISE EXCEPTION 'Chỉ người dùng mới tạo mã MCP'; END IF;
  -- Mã gắn một công ty: người phát hành phải là thành viên đang hoạt động có quyền quản trị thành viên ở công ty đó (hoặc quản trị hệ thống)
  IF p_company IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM core.companies WHERE id = p_company) THEN RAISE EXCEPTION 'Không có công ty này'; END IF;
    IF NOT (coalesce((SELECT is_system_admin FROM core.users WHERE id = me), false)
            OR (EXISTS (SELECT 1 FROM core.memberships m WHERE m.user_id = me AND m.company_id = p_company AND m.active)
                AND coalesce(core.perm_scope_of(me, p_company, 'core.member.manage') = 'company', false))) THEN
      RAISE EXCEPTION 'Chỉ quản trị công ty mới cấp mã gắn với công ty này' USING ERRCODE = '42501';
    END IF;
  END IF;
  IF (SELECT count(*) FROM agent.mcp_tokens WHERE user_id = me AND revoked_at IS NULL AND expires_at > now()) >= 5 THEN
    RAISE EXCEPTION 'Mỗi người tối đa 5 mã đang dùng. Thu hồi mã cũ trước.';
  END IF;
  raw := 'eos_' || encode(gen_random_bytes(24), 'hex');
  INSERT INTO agent.mcp_tokens (user_id, company_id, name, client, prefix, token_hash, scopes, expires_at)
  VALUES (me, p_company, p_name, p_client, substr(raw, 5, 8), encode(digest(raw, 'sha256'), 'hex'), p_scopes,
          now() + make_interval(days => least(greatest(p_days, 1), 365)));
  RETURN raw;   -- chỉ hiện một lần
END $$;
COMMIT;
