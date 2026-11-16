-- =====================================================================
-- 66 · Việc đứng riêng cho bảo trì dữ liệu: việc định kỳ có thể mang agent + phạm vi (wiki_lint, law_review); công cụ đọc danh mục pháp luật cho law_review
-- Chạy sau 65. Toàn bộ file (cùng agent._standalone_scope/mcp_project_scope trong 62) là migration 0034; áp dụng được nhiều lần.
-- =====================================================================
SET search_path = agent, work, core, kb, public;

ALTER TABLE work.recurrences ADD COLUMN IF NOT EXISTS agent_code text CHECK (agent_code IS NULL OR agent_code ~ '^[a-z][a-z-]{1,31}$');
ALTER TABLE work.recurrences ADD COLUMN IF NOT EXISTS scope jsonb CHECK (scope IS NULL OR jsonb_typeof(scope) = 'object');
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'work.recurrences'::regclass AND conname = 'recurrences_agent_scope_chk') THEN
    ALTER TABLE work.recurrences ADD CONSTRAINT recurrences_agent_scope_chk
      CHECK (agent_code IS NULL OR (scope IS NOT NULL AND scope->>'stage' IN ('law_review', 'wiki_lint')));   -- việc định kỳ chỉ được giao agent ở các giai đoạn chỉ đọc
  END IF;
END $$;

-- Như bản 0030, thêm: việc định kỳ mang agent + phạm vi
CREATE OR REPLACE FUNCTION work._run_recurrence(p_id uuid, p_today date) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = work, core, agent, public AS $$
DECLARE r work.recurrences; occ date; nxt date; made bigint; guard int := 0; ag uuid;
BEGIN
  SELECT * INTO r FROM work.recurrences WHERE id = p_id AND active FOR UPDATE;
  IF r.id IS NULL OR r.next_run > p_today THEN RETURN NULL; END IF;
  IF r.max_runs IS NOT NULL AND r.run_count >= r.max_runs THEN UPDATE work.recurrences SET active = false WHERE id = r.id; RETURN NULL; END IF;
  occ := r.next_run;
  LOOP   -- lần xuất hiện mới nhất không quá hôm nay (bỏ các lần đã lỡ để không dồn việc)
    nxt := work.recur_next(r, occ);
    EXIT WHEN nxt > p_today OR guard > 800;
    occ := nxt; guard := guard + 1;
  END LOOP;
  IF r.until_date IS NOT NULL AND occ > r.until_date THEN UPDATE work.recurrences SET active = false WHERE id = r.id; RETURN NULL; END IF;
  IF NOT (r.skip_holidays AND NOT core.is_workday(r.company_id, occ)) THEN
    INSERT INTO work.tasks (company_id, department_id, project_id, recurrence_id, source, title, description, priority, assignee_id, kpi_weight, due_date, created_by)
    VALUES (r.company_id, r.department_id, r.project_id, r.id, 'recurrence', r.title, r.description, r.priority, r.assignee_id, r.kpi_weight, occ + r.due_offset, r.created_by) RETURNING id INTO made;
    INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
    VALUES (r.company_id, 'system', r.created_by, 'work', 'recurrence_run', 'task', made::text, 'Việc định kỳ "' || r.title || '" tạo T-' || made || ' cho ngày ' || occ);
    UPDATE work.recurrences SET run_count = run_count + 1 WHERE id = r.id;
    r.run_count := r.run_count + 1;
    -- việc định kỳ giao cho agent (rà Wiki, rà hiệu lực): ghi phạm vi (không gắn lần chạy) rồi giao; agent chưa bật cho công ty thì việc vẫn tạo cho người phụ trách
    IF r.agent_code IS NOT NULL THEN
      SELECT g.id INTO ag FROM agent.agents g JOIN agent.company_agents ca ON ca.agent_id = g.id AND ca.company_id = r.company_id AND ca.enabled WHERE g.code = r.agent_code AND g.active;
      IF ag IS NOT NULL THEN
        INSERT INTO agent.task_scopes (task_id, run_id, skill, scope, created_by) VALUES (made, NULL, r.scope->>'skill', (r.scope - 'skill') || jsonb_build_object('agent', r.agent_code), 'recurrence:' || r.id);
        UPDATE work.tasks SET agent_id = ag, agent_role = coalesce(r.scope->>'skill', r.agent_code) WHERE id = made;
      END IF;
    END IF;
  END IF;
  nxt := work.recur_next(r, occ);
  IF (r.until_date IS NOT NULL AND nxt > r.until_date) OR (r.max_runs IS NOT NULL AND r.run_count >= r.max_runs) THEN UPDATE work.recurrences SET active = false, next_run = nxt WHERE id = r.id;
  ELSE UPDATE work.recurrences SET next_run = nxt WHERE id = r.id; END IF;
  RETURN made;
END $$;

-- ---------- eos_law_list: phap-che đọc danh mục văn bản đã nạp (law_ingest hoặc law_review); chỉ đọc ----------
CREATE OR REPLACE FUNCTION agent.mcp_law_list(p_task bigint, p_kb text, p jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE a agent.agents := agent._agent_for_task(p_task); t work.tasks; ts agent.task_scopes; cr core.users; b kb.bases; lim int := least(greatest(coalesce((p->>'limit')::int, 100), 1), 200); off int := greatest(coalesce((p->>'offset')::int, 0), 0); total int;
BEGIN
  IF a.code <> 'phap-che' THEN RAISE EXCEPTION 'Chỉ agent phap-che đọc danh mục văn bản pháp luật' USING ERRCODE = '42501'; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF NOT EXISTS (SELECT 1 FROM agent.cards c WHERE c.task_id = p_task AND c.agent_id = a.id AND c.status IN ('ready', 'running')) THEN RAISE EXCEPTION 'Agent % chưa có thẻ đang chạy cho chính việc T-%', a.code, p_task USING ERRCODE = '42501'; END IF;
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

REVOKE ALL ON FUNCTION agent.mcp_law_list(bigint, text, jsonb), agent._standalone_scope(bigint, agent.agents, agent.task_scopes) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.mcp_law_list(bigint, text, jsonb) TO mcp_svc;
