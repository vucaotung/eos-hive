-- 0036 · Ngữ cảnh pháp luật nhận thẻ còn ở trạng thái todo: cầu nối Kanban chỉ ghi agent.cards.status = running vài giây SAU khi worker
-- đã chạy, nên lần gọi eos_law_* đầu tiên bị từ chối "chưa có thẻ đang chạy" (gặp thật ở T-94, 19/11/2026). Nguồn chính: db/65_law.sql, db/66_standalone.sql.
-- Vẫn bắt buộc: thẻ của CHÍNH việc đó, của CHÍNH agent phap-che, việc law_ingest/law_review do chủ sở hữu/quản trị (người thật) tạo, việc chưa đóng.
-- down: nạp lại hai hàm từ migration 0031 (agent._law_ctx) và 0034 (agent.mcp_law_list).
BEGIN;
SET search_path = agent, work, core, kb, public;

CREATE OR REPLACE FUNCTION agent._law_ctx(p_task bigint) RETURNS work.tasks
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE a agent.agents := agent._agent_for_task(p_task); t work.tasks; ts agent.task_scopes; cr core.users;
BEGIN
  IF a.code <> 'phap-che' THEN RAISE EXCEPTION 'Chỉ agent phap-che được nạp văn bản pháp luật' USING ERRCODE = '42501'; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF NOT EXISTS (SELECT 1 FROM agent.cards c WHERE c.task_id = p_task AND c.agent_id = a.id AND c.status IN ('todo', 'ready', 'running')) THEN
    RAISE EXCEPTION 'Agent % chưa có thẻ đang chạy cho chính việc T-%', a.code, p_task USING ERRCODE = '42501';
  END IF;
  SELECT * INTO ts FROM agent.task_scopes WHERE task_id = p_task;
  IF ts.task_id IS NULL OR ts.scope->>'stage' <> 'law_ingest' THEN RAISE EXCEPTION 'Chỉ nạp văn bản pháp luật trong việc có giai đoạn law_ingest trong phạm vi'; END IF;
  IF ts.scope->>'agent' IS DISTINCT FROM a.code THEN RAISE EXCEPTION 'Việc này không giao cho agent %', a.code USING ERRCODE = '42501'; END IF;
  SELECT * INTO cr FROM core.users WHERE id = t.created_by;
  IF cr.id IS NULL OR cr.kind <> 'person' OR agent._role_of(cr.id, t.company_id) NOT IN ('owner', 'admin') THEN
    RAISE EXCEPTION 'Việc nạp văn bản pháp luật phải do chủ sở hữu hoặc quản trị (người thật) tạo' USING ERRCODE = '42501';
  END IF;
  IF t.status IN ('done', 'cancelled') THEN RAISE EXCEPTION 'Việc T-% đã đóng', p_task; END IF;
  RETURN t;
END $$;

CREATE OR REPLACE FUNCTION agent.mcp_law_list(p_task bigint, p_kb text, p jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE a agent.agents := agent._agent_for_task(p_task); t work.tasks; ts agent.task_scopes; cr core.users; b kb.bases; lim int := least(greatest(coalesce((p->>'limit')::int, 100), 1), 200); off int := greatest(coalesce((p->>'offset')::int, 0), 0); total int;
BEGIN
  IF a.code <> 'phap-che' THEN RAISE EXCEPTION 'Chỉ agent phap-che đọc danh mục văn bản pháp luật' USING ERRCODE = '42501'; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF NOT EXISTS (SELECT 1 FROM agent.cards c WHERE c.task_id = p_task AND c.agent_id = a.id AND c.status IN ('todo', 'ready', 'running')) THEN RAISE EXCEPTION 'Agent % chưa có thẻ đang chạy cho chính việc T-%', a.code, p_task USING ERRCODE = '42501'; END IF;
  SELECT * INTO ts FROM agent.task_scopes WHERE task_id = p_task;
  IF ts.task_id IS NULL OR ts.scope->>'stage' NOT IN ('law_ingest', 'law_review') OR ts.scope->>'agent' IS DISTINCT FROM a.code THEN RAISE EXCEPTION 'Chỉ đọc danh mục pháp luật trong việc law_ingest hoặc law_review' USING ERRCODE = '42501'; END IF;
  SELECT * INTO cr FROM core.users WHERE id = t.created_by;
  IF cr.id IS NULL OR cr.kind <> 'person' OR agent._role_of(cr.id, t.company_id) NOT IN ('owner', 'admin') THEN RAISE EXCEPTION 'Việc phải do chủ sở hữu hoặc quản trị (người thật) tạo' USING ERRCODE = '42501'; END IF;
  b := agent._law_base(t, p_kb);
  SELECT count(*) INTO total FROM kb.law_sources WHERE company_id = t.company_id AND weknora_kb_id = b.weknora_kb_id AND (NOT (p ? 'tinh_trang') OR tinh_trang = p->>'tinh_trang');
  RETURN jsonb_build_object('kb', p_kb, 'total', total, 'offset', off, 'items', coalesce((SELECT jsonb_agg(x ORDER BY x->>'so_hieu') FROM (
    SELECT jsonb_build_object('so_hieu', so_hieu, 'ten', ten, 'loai', loai, 'co_quan', co_quan, 'ngay_ban_hanh', ngay_ban_hanh, 'ngay_hieu_luc', ngay_hieu_luc, 'tinh_trang', tinh_trang,
           'thay_the', thay_the, 'sua_doi', sua_doi, 'linh_vuc', linh_vuc, 'buoc', buoc, 'nguon', nguon_url, 'ngay_tra', ngay_tra, 'weknora_doc_id', weknora_doc_id, 'phien_ban', phien_ban) x
      FROM kb.law_sources WHERE company_id = t.company_id AND weknora_kb_id = b.weknora_kb_id AND (NOT (p ? 'tinh_trang') OR tinh_trang = p->>'tinh_trang')
     ORDER BY so_hieu, created_at LIMIT lim OFFSET off) q), '[]'));
END $$;

COMMIT;
