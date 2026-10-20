-- 0004 · agent._mcp_actor(): lời gọi của agent (via 'agent:<mã>') ghi actor là agent, không ghi nhầm người phụ trách.
-- Phát hiện ở nghiệm thu A7: tệp do Văn thư AI soạn bị gắn vào việc với actor 'user:<người phụ trách>'.
-- Idempotent. down: nạp lại bản cũ: SELECT 'user:' || core.current_user_id() || CASE WHEN core.current_via() LIKE 'mcp:%' THEN ' via ' || core.current_via() ELSE '' END
BEGIN;
CREATE OR REPLACE FUNCTION agent._mcp_actor() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN core.current_via() LIKE 'agent:%' THEN core.current_via()   -- việc do agent làm: nhật ký ghi agent, không ghi nhầm người phụ trách
              ELSE 'user:' || core.current_user_id() || CASE WHEN core.current_via() LIKE 'mcp:%' THEN ' via ' || core.current_via() ELSE '' END END
$$;
COMMIT;
