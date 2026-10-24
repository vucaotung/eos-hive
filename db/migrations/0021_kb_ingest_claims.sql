-- 0021 · Nạp kho song song: giữ chỗ từng tài liệu và việc tạo kho (agent.kb_ingest_claims), hàm mcp_kb_ingest_claim / mcp_kb_ingest_finish.
-- Nguồn chính: db/62_workflow.sql. Idempotent. down: DROP TABLE agent.kb_ingest_claims; DROP FUNCTION agent.mcp_kb_ingest_claim(bigint,jsonb), agent.mcp_kb_ingest_finish(bigint,jsonb).
BEGIN;
-- ---------- Nạp kho song song: giữ chỗ từng tài liệu (agent.kb_ingest_claims) ----------
-- Hai lần eos_kb_ingest cùng lúc cho một tài liệu: chỉ lần giữ chỗ trước được nạp, lần sau nhận "busy". Khóa theo (kho, tài liệu); kho thuộc đúng một công ty (company_id lưu kèm).
-- Giữ chỗ treo quá 30 phút (tiến trình chết giữa chừng) được lấy lại. Dòng đặc biệt '__create__' giữ chỗ việc TẠO kho tri thức để hai lần gọi không tạo hai kho.
CREATE TABLE IF NOT EXISTS agent.kb_ingest_claims (
  base_id     uuid NOT NULL REFERENCES kb.bases(id) ON DELETE CASCADE,
  drive_id    text NOT NULL,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  task_id     bigint REFERENCES work.tasks(id) ON DELETE SET NULL,
  state       text NOT NULL DEFAULT 'claiming' CHECK (state IN ('claiming','done')),
  claimed_at  timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  PRIMARY KEY (base_id, drive_id)
);
REVOKE ALL ON agent.kb_ingest_claims FROM PUBLIC;

CREATE OR REPLACE FUNCTION agent.mcp_kb_ingest_claim(p_task bigint, p_drive_ids jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE a agent.agents := agent._agent_for_task(p_task); r agent.workflow_runs := agent._kb_ingest_ctx(p_task); b kb.bases; fid text; got text;
        claimed text[] := '{}'; busy jsonb := '[]'; create_kb boolean := false;
BEGIN
  SELECT * INTO b FROM kb.bases WHERE id = r.kb_base_id;
  IF jsonb_typeof(coalesce(p_drive_ids, '[]')) <> 'array' OR jsonb_array_length(coalesce(p_drive_ids, '[]')) > 20 THEN RAISE EXCEPTION 'Tối đa 20 tài liệu mỗi lần'; END IF;
  IF b.weknora_kb_id LIKE 'pending:%' THEN   -- kho chưa tạo: chỉ một lần gọi được tạo
    INSERT INTO agent.kb_ingest_claims (base_id, drive_id, company_id, task_id) VALUES (b.id, '__create__', r.company_id, p_task)
    ON CONFLICT (base_id, drive_id) DO UPDATE SET task_id = p_task, claimed_at = now(), state = 'claiming'
      WHERE agent.kb_ingest_claims.claimed_at < now() - interval '30 minutes'
    RETURNING drive_id INTO got;
    create_kb := got IS NOT NULL;
  END IF;
  FOR fid IN SELECT jsonb_array_elements_text(coalesce(p_drive_ids, '[]')) LOOP
    IF fid !~ '^[A-Za-z0-9_-]{10,}$' THEN RAISE EXCEPTION 'file_id không hợp lệ'; END IF;
    IF EXISTS (SELECT 1 FROM kb.sources s JOIN core.files f ON f.id = s.file_id WHERE s.base_id = b.id AND s.state = 'loaded' AND f.drive_id = fid) THEN
      busy := busy || jsonb_build_object('file_id', fid, 'reason', 'đã nạp trước đó'); CONTINUE;
    END IF;
    got := NULL;
    INSERT INTO agent.kb_ingest_claims (base_id, drive_id, company_id, task_id) VALUES (b.id, fid, r.company_id, p_task)
    ON CONFLICT (base_id, drive_id) DO UPDATE SET task_id = p_task, claimed_at = now(), state = 'claiming', finished_at = NULL
      WHERE agent.kb_ingest_claims.state = 'done' OR agent.kb_ingest_claims.claimed_at < now() - interval '30 minutes'   -- 'done' mà nguồn đã bị xóa khỏi kho: cho nạp lại
    RETURNING drive_id INTO got;
    IF got IS NULL THEN busy := busy || jsonb_build_object('file_id', fid, 'reason', 'đang được nạp bởi lần gọi khác');
    ELSE claimed := claimed || fid; END IF;
  END LOOP;
  RETURN jsonb_build_object('claimed', to_jsonb(claimed), 'busy', busy, 'create_kb', create_kb, 'kb_ready', b.weknora_kb_id NOT LIKE 'pending:%');
END $$;

-- Kết thúc: done = đã nạp xong (giữ dòng để lần sau báo "đã nạp"); release = bỏ giữ chỗ (lỗi, tệp bỏ qua, hoặc đã tạo xong kho) để lần sau nạp lại được
CREATE OR REPLACE FUNCTION agent.mcp_kb_ingest_finish(p_task bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE a agent.agents := agent._agent_for_task(p_task); r agent.workflow_runs := agent._kb_ingest_ctx(p_task); n_done int; n_rel int;
BEGIN
  UPDATE agent.kb_ingest_claims SET state = 'done', finished_at = now()
   WHERE base_id = r.kb_base_id AND task_id = p_task AND state = 'claiming' AND drive_id IN (SELECT jsonb_array_elements_text(coalesce(p->'done', '[]')));
  GET DIAGNOSTICS n_done = ROW_COUNT;
  DELETE FROM agent.kb_ingest_claims
   WHERE base_id = r.kb_base_id AND task_id = p_task AND state = 'claiming' AND drive_id IN (SELECT jsonb_array_elements_text(coalesce(p->'release', '[]')));
  GET DIAGNOSTICS n_rel = ROW_COUNT;
  RETURN jsonb_build_object('done', n_done, 'released', n_rel);
END $$;

GRANT EXECUTE ON FUNCTION agent.mcp_kb_ingest_claim(bigint, jsonb), agent.mcp_kb_ingest_finish(bigint, jsonb) TO mcp_svc;
COMMIT;
