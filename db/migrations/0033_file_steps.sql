-- 0033 · Mã bước cho từng tệp (kb.file_steps), hàm mcp_tag_step (stage data_quality), mcp_kb_ingest_target trả thêm file_steps.
-- Nguồn chính: db/62_workflow.sql. Idempotent. down: DROP FUNCTION agent.mcp_tag_step(bigint,jsonb), agent._data_quality_ctx(bigint), kb.step_phase(text); DROP TABLE kb.file_steps; rồi khôi phục mcp_kb_ingest_target từ 0009/0021 (bỏ khóa file_steps).
BEGIN;
-- ---------- Mã bước (01–20) cho từng tệp: agent quan-tri-du-lieu đề xuất ở giai đoạn data_quality, eos_kb_ingest đọc khi nạp ----------
-- Front matter nằm trên Drive và runner không sửa lại được, nên mã bước lưu ở đây theo (lần chạy, drive_id). 00 = văn bản chung / chưa chắc.
CREATE TABLE IF NOT EXISTS kb.file_steps (
  run_id      bigint NOT NULL REFERENCES agent.workflow_runs(id) ON DELETE CASCADE,
  drive_id    text NOT NULL CHECK (drive_id ~ '^[A-Za-z0-9_-]{6,}$'),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  buoc        text NOT NULL CHECK (buoc ~ '^(0[0-9]|1[0-9]|20)$'),
  note        text CHECK (length(note) <= 300),
  set_by      text NOT NULL,
  set_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (run_id, drive_id)
);
REVOKE ALL ON kb.file_steps FROM PUBLIC;

-- Giai đoạn theo mã bước: I = 01–09, II = 10–15, III = 16–20; 00 = chưa xác định ('')
CREATE OR REPLACE FUNCTION kb.step_phase(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p ~ '^0[1-9]$' THEN 'I' WHEN p ~ '^1[0-5]$' THEN 'II' WHEN p ~ '^(1[6-9]|20)$' THEN 'III' ELSE '' END $$;

-- Ngữ cảnh giai đoạn data_quality: việc giao đúng agent quan-tri-du-lieu, thẻ đang chạy, lần chạy còn chạy
CREATE OR REPLACE FUNCTION agent._data_quality_ctx(p_task bigint) RETURNS agent.workflow_runs
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE a agent.agents := agent._agent_for_task(p_task); ts agent.task_scopes; r agent.workflow_runs;
BEGIN
  SELECT * INTO ts FROM agent.task_scopes WHERE task_id = p_task;
  IF ts.task_id IS NULL OR ts.scope->>'stage' <> 'data_quality' THEN RAISE EXCEPTION 'Chỉ gắn mã bước trong việc có giai đoạn data_quality trong phạm vi'; END IF;
  IF a.code <> 'quan-tri-du-lieu' OR ts.scope->>'agent' IS DISTINCT FROM a.code THEN RAISE EXCEPTION 'Chỉ agent quan-tri-du-lieu được gắn mã bước' USING ERRCODE = '42501'; END IF;
  SELECT * INTO r FROM agent.workflow_runs WHERE id = ts.run_id;
  IF r.state <> 'running' THEN RAISE EXCEPTION 'Lần chạy đã dừng'; END IF;
  RETURN r;
END $$;

-- Ghi 1–200 cặp {drive_id, buoc, note?}; tệp phải đã được runner đăng ký (core.files) cho công ty này. Ghi lại thì cập nhật.
CREATE OR REPLACE FUNCTION agent.mcp_tag_step(p_task bigint, p_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE a agent.agents := agent._agent_for_task(p_task); r agent.workflow_runs := agent._data_quality_ctx(p_task); it jsonb; n int := 0; unknown jsonb := '[]';
BEGIN
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'Gửi từ 1 đến 200 tệp mỗi lần'; END IF;
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    IF coalesce(it->>'buoc', '') !~ '^(0[0-9]|1[0-9]|20)$' THEN RAISE EXCEPTION 'Mã bước phải từ 00 đến 20 (00 = chưa chắc)'; END IF;
    IF NOT EXISTS (SELECT 1 FROM core.files WHERE company_id = r.company_id AND drive_id = it->>'drive_id') THEN
      unknown := unknown || to_jsonb(coalesce(it->>'drive_id', '?')); CONTINUE;
    END IF;
    INSERT INTO kb.file_steps (run_id, drive_id, company_id, buoc, note, set_by)
    VALUES (r.id, it->>'drive_id', r.company_id, it->>'buoc', left(it->>'note', 300), 'agent:' || a.code)
    ON CONFLICT (run_id, drive_id) DO UPDATE SET buoc = EXCLUDED.buoc, note = EXCLUDED.note, set_by = EXCLUDED.set_by, set_at = now();
    n := n + 1;
  END LOOP;
  INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
  VALUES (r.company_id, 'agent:' || a.code, a.user_id, 'kb', 'tag_step', 'task', p_task::text, 'Gắn mã bước cho ' || n || ' tệp');
  RETURN jsonb_build_object('tagged', n, 'unknown_files', unknown);
END $$;

CREATE OR REPLACE FUNCTION agent.mcp_kb_ingest_target(p_task bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE r agent.workflow_runs := agent._kb_ingest_ctx(p_task); b kb.bases;
BEGIN
  SELECT * INTO b FROM kb.bases WHERE id = r.kb_base_id;
  RETURN jsonb_build_object('base_id', b.id, 'kb_name', b.name, 'weknora_kb_id', b.weknora_kb_id, 'kb_ready', b.weknora_kb_id NOT LIKE 'pending:%',
    'description', b.description, 'md_folder_id', r.md_folder_id, 'project', (SELECT slug FROM core.projects WHERE id = r.project_id),
    'loaded_drive_ids', coalesce((SELECT jsonb_agg(f.drive_id) FROM kb.sources s JOIN core.files f ON f.id = s.file_id WHERE s.base_id = b.id AND s.state = 'loaded'), '[]'),
    'file_steps', coalesce((SELECT jsonb_object_agg(fs.drive_id, jsonb_build_object('buoc', fs.buoc, 'giai_doan', kb.step_phase(fs.buoc))) FROM kb.file_steps fs WHERE fs.run_id = r.id), '{}'));
END $$;

-- Hàm mới mặc định cho PUBLIC chạy (Postgres): thu lại, chỉ mcp_svc gọi mcp_tag_step (phát hiện bằng scripts/security_audit.sh khi triển khai 0.6.0)
REVOKE ALL ON FUNCTION agent._data_quality_ctx(bigint), agent.mcp_tag_step(bigint, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.mcp_tag_step(bigint, jsonb) TO mcp_svc;
COMMIT;
