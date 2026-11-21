-- 0037 · Pháp chế nạp văn bản pháp luật theo LỆNH TRỰC TIẾP (không qua thẻ Kanban): việc thường trực law_ingest (scope.standing = true, in_progress, không thẻ)
-- do chủ sở hữu/quản trị bật bằng agent.app_law_standing_enable; eos_law_* không truyền task thì máy chủ dùng agent.mcp_law_standing().
-- Chỉ các hàm pháp luật và agent.mcp_upload_begin chấp nhận việc thường trực (agent._law_agent); agent._agent_for_task không đổi nên các công cụ khác vẫn đòi thẻ.
-- Nguồn chính: db/65_law.sql, db/66_standalone.sql, db/62_workflow.sql. Không đổi bảng.
-- down: DROP FUNCTION agent.mcp_law_standing(), agent.app_law_standing_enable(jsonb); nạp lại các hàm còn lại từ 0036 (_law_ctx, mcp_law_list), 0031 (mcp_law_*), 0020 (mcp_upload_begin);
--       sau đó DROP FUNCTION agent._law_agent(bigint), agent._law_standing_ok(bigint, agent.agents). Việc thường trực đã tạo: hủy (cancelled).
BEGIN;
SET search_path = agent, work, core, kb, public;

CREATE OR REPLACE FUNCTION agent._law_standing_ok(p_task bigint, a agent.agents) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  SELECT a.id IS NOT NULL AND a.code = 'phap-che' AND EXISTS (
    SELECT 1 FROM work.tasks t JOIN agent.task_scopes ts ON ts.task_id = t.id
     WHERE t.id = p_task AND t.agent_id = a.id AND t.status NOT IN ('done', 'cancelled')
       AND ts.scope->>'stage' = 'law_ingest' AND ts.scope->>'agent' = a.code AND ts.scope->>'standing' = 'true')
$$;

CREATE OR REPLACE FUNCTION agent._law_agent(p_task bigint) RETURNS agent.agents
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE a agent.agents := agent.current_agent();
BEGIN
  IF a.id IS NULL THEN RAISE EXCEPTION 'Chỉ dành cho agent hệ thống' USING ERRCODE = '42501'; END IF;
  IF agent._law_standing_ok(p_task, a) THEN RETURN a; END IF;
  RETURN agent._agent_for_task(p_task);
END $$;

CREATE OR REPLACE FUNCTION agent._law_ctx(p_task bigint) RETURNS work.tasks
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE a agent.agents := agent._law_agent(p_task); t work.tasks; ts agent.task_scopes; cr core.users;
BEGIN
  IF a.code <> 'phap-che' THEN RAISE EXCEPTION 'Chỉ agent phap-che được nạp văn bản pháp luật' USING ERRCODE = '42501'; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF NOT agent._law_standing_ok(p_task, a) AND NOT EXISTS (SELECT 1 FROM agent.cards c WHERE c.task_id = p_task AND c.agent_id = a.id AND c.status IN ('todo', 'ready', 'running')) THEN
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

CREATE OR REPLACE FUNCTION agent.mcp_law_save_done(p_task bigint, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE t work.tasks := agent._law_ctx(p_task); a agent.agents := agent._law_agent(p_task); fid bigint;
BEGIN
  IF coalesce(p->>'drive_id', '') !~ '^[A-Za-z0-9_-]{6,}$' OR coalesce(p->>'url', '') !~ '^https://' THEN RAISE EXCEPTION 'drive_id hoặc url không hợp lệ'; END IF;
  INSERT INTO core.files (company_id, drive_id, name, mime_type, size_bytes, sha256, web_url, storage)
  VALUES (t.company_id, p->>'drive_id', left(p->>'name', 300), 'text/markdown', nullif(p->>'bytes', '')::bigint, p->>'sha256', p->>'url', 'company')
  ON CONFLICT (company_id, drive_id) DO UPDATE SET name = EXCLUDED.name, size_bytes = EXCLUDED.size_bytes, sha256 = EXCLUDED.sha256, synced_at = now()
  RETURNING id INTO fid;
  INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
  VALUES (t.company_id, 'agent:' || a.code, a.user_id, 'kb', 'law_save', 'task', p_task::text, 'Lưu văn bản pháp luật ' || left(coalesce(p->>'so_hieu', p->>'name'), 120) || ' vào thư mục pháp luật');
  RETURN jsonb_build_object('file_id', fid);
END $$;

CREATE OR REPLACE FUNCTION agent.mcp_law_ingest_commit(p_task bigint, p_kb text, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE t work.tasks := agent._law_ctx(p_task); a agent.agents := agent._law_agent(p_task); b kb.bases := agent._law_base(agent._law_ctx(p_task), p_kb);
        it jsonb; fid bigint; n int := 0; kid text; bu text[];
BEGIN
  IF p ? 'weknora_kb_id' THEN
    kid := p->>'weknora_kb_id';
    IF kid !~ '^[A-Za-z0-9_-]{8,64}$' THEN RAISE EXCEPTION 'weknora_kb_id không hợp lệ'; END IF;
    IF b.weknora_kb_id NOT LIKE 'pending:%' AND b.weknora_kb_id <> kid THEN RAISE EXCEPTION 'KB % đã có mã WeKnora khác, không ghi đè', p_kb; END IF;
    UPDATE kb.bases SET weknora_kb_id = kid, last_synced_at = now() WHERE id = b.id;
    SELECT * INTO b FROM kb.bases WHERE id = b.id;
  END IF;
  IF b.weknora_kb_id LIKE 'pending:%' THEN RAISE EXCEPTION 'KB % chưa được tạo trên WeKnora', p_kb; END IF;
  IF jsonb_array_length(coalesce(p->'items', '[]')) > 20 THEN RAISE EXCEPTION 'Tối đa 20 văn bản mỗi lần'; END IF;
  FOR it IN SELECT * FROM jsonb_array_elements(coalesce(p->'items', '[]')) LOOP
    IF coalesce(it->>'weknora_doc_id', '') = '' OR coalesce(it->>'phien_ban', '') !~ '^[0-9a-f]{32}$' THEN RAISE EXCEPTION 'Mỗi văn bản cần weknora_doc_id và phien_ban (md5)'; END IF;
    SELECT coalesce(array_agg(x), '{}') INTO bu FROM jsonb_array_elements_text(coalesce(it->'buoc', '[]')) x;
    SELECT id INTO fid FROM core.files WHERE company_id = t.company_id AND drive_id = it->>'drive_id';
    INSERT INTO kb.law_sources (company_id, base_id, so_hieu, ten, loai, co_quan, ngay_ban_hanh, ngay_hieu_luc, tinh_trang, thay_the, sua_doi, linh_vuc, buoc, nguon_url, ngay_tra,
                                drive_id, weknora_kb_id, weknora_doc_id, phien_ban, created_by)
    VALUES (t.company_id, b.id, btrim(it->>'so_hieu'), btrim(it->>'ten'), nullif(btrim(coalesce(it->>'loai', '')), ''), btrim(it->>'co_quan'), (it->>'ngay_ban_hanh')::date, nullif(it->>'ngay_hieu_luc', '')::date,
            it->>'tinh_trang', nullif(btrim(coalesce(it->>'thay_the', '')), ''), nullif(btrim(coalesce(it->>'sua_doi', '')), ''), nullif(btrim(coalesce(it->>'linh_vuc', '')), ''), bu,
            it->>'nguon', (it->>'ngay_tra')::date, it->>'drive_id', b.weknora_kb_id, it->>'weknora_doc_id', it->>'phien_ban', 'agent:' || a.code)
    ON CONFLICT (weknora_kb_id, so_hieu, phien_ban) DO UPDATE SET weknora_doc_id = EXCLUDED.weknora_doc_id, tinh_trang = EXCLUDED.tinh_trang, updated_at = now();
    INSERT INTO kb.sources (company_id, base_id, weknora_doc_id, origin, title, file_id, locked)
    VALUES (t.company_id, b.id, it->>'weknora_doc_id', 'manual', left(btrim(it->>'so_hieu') || ' - ' || btrim(it->>'ten'), 300), fid, false)
    ON CONFLICT (base_id, weknora_doc_id) DO UPDATE SET title = EXCLUDED.title, file_id = EXCLUDED.file_id, state = 'loaded';
    -- các phiên bản cũ của cùng số hiệu: đánh dấu "superseded" trong CSDL (KHÔNG xóa gì ở WeKnora)
    UPDATE kb.sources SET state = 'superseded'
     WHERE base_id = b.id AND state = 'loaded' AND weknora_doc_id IN (SELECT weknora_doc_id FROM kb.law_sources WHERE weknora_kb_id = b.weknora_kb_id AND so_hieu = btrim(it->>'so_hieu') AND phien_ban <> it->>'phien_ban');
    n := n + 1;
  END LOOP;
  INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
  VALUES (t.company_id, 'agent:' || a.code, a.user_id, 'kb', 'law_ingest', 'task', p_task::text, 'Nạp ' || n || ' văn bản pháp luật vào KB ' || b.name);
  RETURN jsonb_build_object('registered', n, 'weknora_kb_id', b.weknora_kb_id);
END $$;

CREATE OR REPLACE FUNCTION agent.mcp_law_mark(p_task bigint, p_kb text, p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE t work.tasks := agent._law_ctx(p_task); a agent.agents := agent._law_agent(p_task); b kb.bases := agent._law_base(agent._law_ctx(p_task), p_kb); n int;
BEGIN
  IF coalesce(p->>'tinh_trang', '') NOT IN ('con_hieu_luc', 'het_mot_phan', 'het_hieu_luc', 'chua_hieu_luc') THEN RAISE EXCEPTION 'tinh_trang phải là con_hieu_luc, het_mot_phan, het_hieu_luc hoặc chua_hieu_luc'; END IF;
  IF length(btrim(coalesce(p->>'so_hieu', ''))) < 2 THEN RAISE EXCEPTION 'Thiếu so_hieu'; END IF;
  UPDATE kb.law_sources SET tinh_trang = p->>'tinh_trang', thay_the = coalesce(nullif(btrim(coalesce(p->>'thay_the', '')), ''), thay_the), updated_at = now()
   WHERE company_id = t.company_id AND weknora_kb_id = b.weknora_kb_id AND so_hieu = btrim(p->>'so_hieu');
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RAISE EXCEPTION 'Văn bản % chưa được nạp vào KB %', btrim(p->>'so_hieu'), p_kb; END IF;
  INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
  VALUES (t.company_id, 'agent:' || a.code, a.user_id, 'kb', 'law_mark', 'task', p_task::text, 'Đánh dấu ' || btrim(p->>'so_hieu') || ' → ' || (p->>'tinh_trang') || ' (KB ' || b.name || ')');
  RETURN jsonb_build_object('updated', n, 'docs', (SELECT jsonb_agg(jsonb_build_object('weknora_doc_id', weknora_doc_id, 'so_hieu', so_hieu, 'tinh_trang', tinh_trang, 'nguon', nguon_url,
            'buoc', array_to_string(buoc, ','), 'linh_vuc', coalesce(linh_vuc, ''), 'thay_the', coalesce(thay_the, ''), 'phien_ban', phien_ban, 'drive_id', drive_id))
          FROM kb.law_sources WHERE company_id = t.company_id AND weknora_kb_id = b.weknora_kb_id AND so_hieu = btrim(p->>'so_hieu')));
END $$;

CREATE OR REPLACE FUNCTION agent.mcp_law_list(p_task bigint, p_kb text, p jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE a agent.agents := agent._law_agent(p_task); t work.tasks; ts agent.task_scopes; cr core.users; b kb.bases; lim int := least(greatest(coalesce((p->>'limit')::int, 100), 1), 200); off int := greatest(coalesce((p->>'offset')::int, 0), 0); total int;
BEGIN
  IF a.code <> 'phap-che' THEN RAISE EXCEPTION 'Chỉ agent phap-che đọc danh mục văn bản pháp luật' USING ERRCODE = '42501'; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF NOT agent._law_standing_ok(p_task, a) AND NOT EXISTS (SELECT 1 FROM agent.cards c WHERE c.task_id = p_task AND c.agent_id = a.id AND c.status IN ('todo', 'ready', 'running')) THEN RAISE EXCEPTION 'Agent % chưa có thẻ đang chạy cho chính việc T-%', a.code, p_task USING ERRCODE = '42501'; END IF;
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

CREATE OR REPLACE FUNCTION agent.mcp_upload_begin(p_task bigint, p_filename text) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); t work.tasks; new_id bigint;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'Chưa đăng nhập' USING ERRCODE = '42501'; END IF;
  IF (agent.current_agent()).id IS NOT NULL THEN PERFORM agent._law_agent(p_task);   -- agent: phải có thẻ đang chạy cho việc này (hoặc việc pháp luật thường trực của phap-che, db/65_law.sql)
  ELSIF NOT work.can_view_task(me, p_task) THEN RAISE EXCEPTION 'Không có quyền với T-%', p_task USING ERRCODE = '42501';
  END IF;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  INSERT INTO agent.drive_uploads (company_id, task_id, user_id, filename) VALUES (t.company_id, p_task, me, left(coalesce(p_filename, ''), 200)) RETURNING id INTO new_id;
  RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION agent.app_law_standing_enable(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, kb, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); s agent.company_settings; ag agent.agents; tid bigint;
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner', 'admin']);
  IF me.kind <> 'person' THEN RAISE EXCEPTION 'Chỉ người thật bật nạp pháp luật theo lệnh trực tiếp' USING ERRCODE = '42501'; END IF;
  SELECT * INTO s FROM agent.company_settings WHERE company_id = cid;
  IF s.company_id IS NULL OR NOT s.enabled THEN RAISE EXCEPTION 'Agent chưa được bật cho công ty'; END IF;
  IF s.law_md_folder_id IS NULL THEN RAISE EXCEPTION 'Chưa cấu hình thư mục Drive pháp luật của công ty (law_md_folder_id)'; END IF;
  SELECT g.* INTO ag FROM agent.agents g JOIN agent.company_agents ca ON ca.agent_id = g.id AND ca.company_id = cid AND ca.enabled WHERE g.code = 'phap-che' AND g.active;
  IF ag.id IS NULL THEN RAISE EXCEPTION 'Agent pháp chế (phap-che) chưa được bật cho công ty'; END IF;
  SELECT t.id INTO tid FROM work.tasks t JOIN agent.task_scopes ts ON ts.task_id = t.id
   WHERE t.company_id = cid AND t.agent_id = ag.id AND t.status NOT IN ('done', 'cancelled') AND ts.scope->>'stage' = 'law_ingest' AND ts.scope->>'standing' = 'true' LIMIT 1;
  IF tid IS NOT NULL THEN RETURN jsonb_build_object('id', 'T-' || tid, 'task_id', tid, 'created', false); END IF;
  INSERT INTO work.tasks (company_id, title, description, priority, status, assignee_id, created_by, source)
  VALUES (cid, 'Nạp văn bản pháp luật theo lệnh trực tiếp (thường trực)',
          'Việc neo cho các lần pháp chế nạp văn bản pháp luật khi chủ sở hữu/quản trị nhắn lệnh trực tiếp (không qua thẻ Kanban). Mỗi lần lưu/nạp/đánh dấu được ghi vào nhật ký với mã việc này. Hủy việc để tắt.',
          'low', 'in_progress', me.id, me.id, 'manual') RETURNING id INTO tid;
  INSERT INTO agent.task_scopes (task_id, run_id, skill, scope, created_by)
  VALUES (tid, NULL, 'nap-van-ban-phap-luat', jsonb_build_object('stage', 'law_ingest', 'agent', 'phap-che', 'standing', true, 'items', '[]'::jsonb), 'user:' || me.id);
  UPDATE work.tasks SET agent_id = ag.id, agent_role = 'nap-van-ban-phap-luat' WHERE id = tid;   -- in_progress: trigger điều phối không tạo thẻ
  PERFORM agent._audit(cid, me.id, 'law_standing_enable', 'task', tid::text, 'Bật nạp văn bản pháp luật theo lệnh trực tiếp');
  RETURN jsonb_build_object('id', 'T-' || tid, 'task_id', tid, 'created', true);
END $$;

CREATE OR REPLACE FUNCTION agent.mcp_law_standing() RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE a agent.agents := agent.current_agent(); ids bigint[];
BEGIN
  IF a.id IS NULL OR a.code <> 'phap-che' THEN RAISE EXCEPTION 'Chỉ agent phap-che được nạp văn bản pháp luật' USING ERRCODE = '42501'; END IF;
  SELECT coalesce(array_agg(t.id ORDER BY t.id), '{}') INTO ids FROM work.tasks t
    JOIN agent.company_agents ca ON ca.company_id = t.company_id AND ca.agent_id = a.id AND ca.enabled
   WHERE agent._law_standing_ok(t.id, a);
  IF cardinality(ids) = 0 THEN RAISE EXCEPTION 'Chưa bật nạp văn bản pháp luật theo lệnh trực tiếp cho công ty: chủ sở hữu/quản trị cần bật (agent.app_law_standing_enable), hoặc giao việc nạp trên Dẹo Work' USING ERRCODE = 'P0001'; END IF;
  IF cardinality(ids) > 1 THEN RAISE EXCEPTION 'Agent đang được bật ở nhiều công ty (việc thường trực %): truyền task để chọn', array_to_string(ids, ', ') USING ERRCODE = 'P0001'; END IF;
  RETURN ids[1];
END $$;

REVOKE ALL ON FUNCTION agent._law_standing_ok(bigint, agent.agents), agent._law_agent(bigint), agent.mcp_law_standing(), agent.app_law_standing_enable(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.mcp_law_standing() TO mcp_svc;
GRANT EXECUTE ON FUNCTION agent.app_law_standing_enable(jsonb) TO web_svc;
COMMIT;
