-- 0034 · Việc đứng riêng cho bảo trì dữ liệu: work.recurrences.agent_code/scope (việc định kỳ giao agent: wiki_lint, law_review), _run_recurrence mang phạm vi, mcp_project_scope và _standalone_scope cho việc không thuộc lần chạy, mcp_law_list.
-- down: DROP FUNCTION agent.mcp_law_list(bigint,text,jsonb), agent._standalone_scope(bigint,agent.agents,agent.task_scopes); ALTER TABLE work.recurrences DROP CONSTRAINT recurrences_agent_scope_chk, DROP COLUMN scope, DROP COLUMN agent_code;
--       nạp lại work._run_recurrence bản 0030 và agent.mcp_project_scope bản 0008/0017.
BEGIN;
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

-- ---------- Phạm vi việc đứng riêng (nguồn: db/62_workflow.sql) ----------
-- Phạm vi của việc đứng riêng (không thuộc lần chạy): wiki_lint (quan-tri-du-lieu, theo dự án) và law_review (phap-che, theo KB pháp luật). Chỉ ĐỌC.
CREATE OR REPLACE FUNCTION agent._standalone_scope(p_task bigint, a agent.agents, ts agent.task_scopes) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE t work.tasks; pr core.projects; b kb.bases; r agent.workflow_runs; stg text := ts.scope->>'stage'; s agent.company_settings;
BEGIN
  IF ts.scope->>'agent' IS DISTINCT FROM a.code OR (stg = 'wiki_lint' AND a.code <> 'quan-tri-du-lieu') OR (stg = 'law_review' AND a.code <> 'phap-che') THEN
    RAISE EXCEPTION 'Việc % không giao cho agent %', stg, a.code USING ERRCODE = '42501';
  END IF;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF stg = 'wiki_lint' THEN
    SELECT * INTO pr FROM core.projects WHERE company_id = t.company_id AND slug = ts.scope->>'project';
    IF pr.id IS NULL THEN RAISE EXCEPTION 'Phạm vi wiki_lint cần "project" (slug dự án) thuộc công ty'; END IF;
    SELECT * INTO b FROM kb.bases WHERE company_id = t.company_id AND project_id = pr.id AND scope = 'project' ORDER BY created_at DESC LIMIT 1;
    SELECT * INTO r FROM agent.workflow_runs WHERE project_id = pr.id ORDER BY id DESC LIMIT 1;
    RETURN jsonb_build_object('standalone', true, 'run', NULL, 'project', jsonb_build_object('id', pr.id, 'name', pr.name, 'slug', pr.slug, 'code', pr.code),
      'task', jsonb_build_object('id', p_task, 'skill', ts.skill, 'scope', ts.scope), 'agent', a.code,
      'md_folder_id', r.md_folder_id,   -- thư mục Markdown của lần nạp gần nhất (chỉ đọc, để đối chiếu Wiki với tài liệu)
      'kb', CASE WHEN b.id IS NULL THEN NULL ELSE jsonb_build_object('name', b.name, 'weknora_kb_id', b.weknora_kb_id, 'ready', b.weknora_kb_id NOT LIKE 'pending:%') END,
      'supervisor', (SELECT name FROM core.users WHERE id = coalesce(r.supervisor, t.assignee_id)), 'playbook', 'Rà Wiki KB dự án: chỉ đọc Wiki (MCP WeKnora chỉ đọc), không sửa Wiki; báo cáo bằng eos_project_save_report.', 'tasks', '[]'::jsonb);
  END IF;
  SELECT * INTO s FROM agent.company_settings WHERE company_id = t.company_id;
  RETURN jsonb_build_object('standalone', true, 'run', NULL, 'project', NULL, 'task', jsonb_build_object('id', p_task, 'skill', ts.skill, 'scope', ts.scope), 'agent', a.code,
    'md_folder_id', NULL, 'law_md_folder_id', s.law_md_folder_id, 'law_kb_names', to_jsonb(s.law_kb_names),
    'kb', (SELECT jsonb_agg(jsonb_build_object('name', k.name, 'weknora_kb_id', k.weknora_kb_id, 'ready', k.weknora_kb_id NOT LIKE 'pending:%')) FROM kb.bases k WHERE k.company_id = t.company_id AND k.scope = 'shared_legal'),
    'supervisor', (SELECT name FROM core.users WHERE id = t.assignee_id),
    'playbook', 'Rà hiệu lực KB pháp luật: đối chiếu từng dòng kb.law_sources (eos_law_list) với nguồn chính thống theo skill tra-cuu-phap-luat; CHỈ báo cáo và đề xuất (eos_project_save_report). Đánh dấu hay nạp mới cần việc law_ingest do chủ sở hữu tạo.', 'tasks', '[]'::jsonb);
END $$;

CREATE OR REPLACE FUNCTION agent.mcp_project_scope(p_task bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE a agent.agents := agent._agent_for_task(p_task); rid bigint := agent._run_of_task(p_task); r agent.workflow_runs; pr core.projects; wf agent.workflows; ts agent.task_scopes; b kb.bases;
BEGIN
  IF rid IS NULL THEN
    SELECT * INTO ts FROM agent.task_scopes WHERE task_id = p_task;
    IF ts.task_id IS NOT NULL AND ts.scope->>'stage' IN ('wiki_lint', 'law_review') THEN RETURN agent._standalone_scope(p_task, a, ts); END IF;   -- việc định kỳ rà Wiki / rà hiệu lực: không thuộc lần chạy nào
    RAISE EXCEPTION 'Việc T-% không thuộc quy trình dự án nào', p_task;
  END IF;
  SELECT * INTO r FROM agent.workflow_runs WHERE id = rid;
  SELECT * INTO pr FROM core.projects WHERE id = r.project_id;
  SELECT * INTO wf FROM agent.workflows WHERE code = r.workflow_code;
  SELECT * INTO ts FROM agent.task_scopes WHERE task_id = p_task;
  SELECT * INTO b FROM kb.bases WHERE id = r.kb_base_id;
  RETURN jsonb_build_object(
    'run', jsonb_build_object('id', r.id, 'workflow', wf.name, 'state', r.state),
    'project', jsonb_build_object('id', pr.id, 'name', pr.name, 'slug', pr.slug, 'code', pr.code),
    'task', jsonb_build_object('id', p_task, 'skill', ts.skill, 'scope', ts.scope),
    'agent', a.code,
    'source_drive_folder_id', r.drive_folder_id,
    'md_folder_id', r.md_folder_id,
    'kb', CASE WHEN b.id IS NULL THEN NULL ELSE jsonb_build_object('name', b.name, 'weknora_kb_id', b.weknora_kb_id, 'ready', b.weknora_kb_id NOT LIKE 'pending:%') END,
    'supervisor', (SELECT name FROM core.users WHERE id = r.supervisor),
    'playbook', wf.playbook,
    'tasks', coalesce((SELECT jsonb_agg(jsonb_build_object('id', 'T-' || t.id, 'title', t.title, 'status', t.status, 'agent', (SELECT code FROM agent.agents WHERE id = t.agent_id),
                         'skill', x.skill, 'scope', x.scope) ORDER BY t.id)
                       FROM agent.task_scopes x JOIN work.tasks t ON t.id = x.task_id WHERE x.run_id = r.id), '[]'));
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

REVOKE ALL ON FUNCTION agent.mcp_project_scope(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.mcp_project_scope(bigint) TO mcp_svc;
REVOKE ALL ON FUNCTION agent.mcp_law_list(bigint, text, jsonb), agent._standalone_scope(bigint, agent.agents, agent.task_scopes) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.mcp_law_list(bigint, text, jsonb) TO mcp_svc;
COMMIT;
