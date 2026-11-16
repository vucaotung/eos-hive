-- Kiểm thử việc đứng riêng cho bảo trì dữ liệu (db/66_standalone.sql): việc định kỳ mang agent + phạm vi wiki_lint / law_review, phạm vi chỉ đọc. Chạy sau 00..66. Tự ROLLBACK.
\set ON_ERROR_STOP 1
BEGIN;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $f$
  SELECT set_config('request.jwt.claims', json_build_object('sub', u, 'via', 'web')::text, true) $f$;
CREATE FUNCTION pg_temp.as_agent(p_code text) RETURNS void LANGUAGE sql AS $f$
  SELECT set_config('request.jwt.claims', json_build_object('sub', a.user_id, 'role', 'agent', 'agent', a.id, 'via', 'agent:' || a.code)::text, true) FROM agent.agents a WHERE a.code = p_code $f$;

INSERT INTO core.companies (id, slug, name) VALUES ('99999999-9999-9999-9999-999999999999', 'maint', 'Công ty Bảo trì');
INSERT INTO core.users (id, email, name, kind, is_system_admin) VALUES
 ('99aaaaaa-0000-0000-0000-000000000001', 'chu@maint.vn', 'Chủ', 'person', true),
 ('99aaaaaa-0000-0000-0000-000000000002', 'tv@maint.vn', 'Thành viên', 'person', false),
 ('99bbbbbb-0000-0000-0000-000000000001', 'qt@agent', 'Quản trị dữ liệu AI', 'agent', false),
 ('99bbbbbb-0000-0000-0000-000000000002', 'pc@agent', 'Pháp chế AI', 'agent', false),
 ('99bbbbbb-0000-0000-0000-000000000003', 'vt@agent', 'Văn thư AI', 'agent', false);
INSERT INTO core.memberships (user_id, company_id) SELECT id, '99999999-9999-9999-9999-999999999999' FROM core.users WHERE email IN ('chu@maint.vn', 'tv@maint.vn');
INSERT INTO core.user_roles (company_id, user_id, role_id) VALUES
 ('99999999-9999-9999-9999-999999999999', '99aaaaaa-0000-0000-0000-000000000001', agent._sys_role('owner')),
 ('99999999-9999-9999-9999-999999999999', '99aaaaaa-0000-0000-0000-000000000002', agent._sys_role('member'));
INSERT INTO agent.agents (user_id, code, name, kind, module, hermes_profile, skills, max_level, can_delegate, executor) VALUES
 ('99bbbbbb-0000-0000-0000-000000000001', 'quan-tri-du-lieu', 'Quản trị dữ liệu AI', 'module', 'kb', 'eos-quan-tri-du-lieu', '{}', 1, false, 'hermes'),
 ('99bbbbbb-0000-0000-0000-000000000002', 'phap-che', 'Pháp chế AI', 'specialist', 'doc', 'eos-phap-che', '{}', 1, false, 'hermes'),
 ('99bbbbbb-0000-0000-0000-000000000003', 'van-thu', 'Văn thư AI', 'module', 'doc', 'eos-van-thu', '{}', 1, false, 'hermes');
INSERT INTO agent.company_settings (company_id, enabled, kanban_board, law_md_folder_id) VALUES ('99999999-9999-9999-9999-999999999999', true, 'eos-maint', 'LAWFOLDER0001');
INSERT INTO agent.company_agents (company_id, agent_id) SELECT '99999999-9999-9999-9999-999999999999', id FROM agent.agents WHERE code IN ('quan-tri-du-lieu', 'van-thu');   -- phap-che chưa bật

DO $$ DECLARE c constant uuid := '99999999-9999-9999-9999-999999999999'; own constant uuid := '99aaaaaa-0000-0000-0000-000000000001'; tv constant uuid := '99aaaaaa-0000-0000-0000-000000000002';
              pid uuid; bid uuid; rid uuid; rid2 uuid; tid bigint; tid2 bigint; ob bigint; res jsonb; n int; today date := (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date;
BEGIN
  INSERT INTO core.projects (company_id, code, name, slug, status, manager_id) VALUES (c, 'DAA', 'Dự án A', 'du-an-a', 'active', tv) RETURNING id INTO pid;
  INSERT INTO kb.bases (company_id, weknora_kb_id, name, scope, project_id, accepts_wiki) VALUES (c, 'wkkb-proj-0001', 'Dự án Dự án A', 'project', pid, true) RETURNING id INTO bid;
  INSERT INTO agent.workflow_runs (company_id, workflow_code, project_id, supervisor, drive_folder_id, md_folder_id, kb_base_id, state, created_by) VALUES (c, 'project-intake', pid, tv, 'SRC0000000001', 'MDROOT0000001', bid, 'done', own);

  -- 1. Ràng buộc của việc định kỳ giao agent: chỉ giai đoạn chỉ đọc
  BEGIN INSERT INTO work.recurrences (company_id, title, freq, next_run, agent_code, scope, created_by) VALUES (c, 'x', 'weekly', today, 'quan-tri-du-lieu', '{"stage":"kb_ingest"}', own); ASSERT false, 'stage ghi dữ liệu không được định kỳ'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN INSERT INTO work.recurrences (company_id, title, freq, next_run, agent_code, scope, created_by) VALUES (c, 'x', 'weekly', today, 'phap-che', '{"stage":"law_ingest"}', own); ASSERT false, 'law_ingest không được định kỳ'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN INSERT INTO work.recurrences (company_id, title, freq, next_run, agent_code, created_by) VALUES (c, 'x', 'weekly', today, 'phap-che', own); ASSERT false, 'agent_code cần scope'; EXCEPTION WHEN check_violation THEN NULL; END;

  -- 2. Việc định kỳ rà Wiki: sinh việc giao quan-tri-du-lieu, phạm vi không gắn lần chạy
  INSERT INTO work.recurrences (company_id, title, description, project_id, assignee_id, freq, weekdays, next_run, active, agent_code, scope, created_by)
  VALUES (c, 'Rà Wiki dự án A (hằng tuần)', 'Rà Wiki KB dự án', pid, tv, 'weekly', ARRAY[1], today, true, 'quan-tri-du-lieu', '{"stage":"wiki_lint","project":"du-an-a","skill":"bao-tri-wiki"}', own) RETURNING id INTO rid;
  PERFORM pg_temp.as_user(own);
  tid := work._run_recurrence(rid, today); ASSERT tid IS NOT NULL, 'tạo được việc';
  ASSERT (SELECT run_id IS NULL AND scope->>'stage' = 'wiki_lint' AND scope->>'agent' = 'quan-tri-du-lieu' AND scope->>'project' = 'du-an-a' AND skill = 'bao-tri-wiki' FROM agent.task_scopes WHERE task_id = tid), 'phạm vi wiki_lint';
  ASSERT (SELECT g.code = 'quan-tri-du-lieu' AND t.agent_role = 'bao-tri-wiki' FROM work.tasks t JOIN agent.agents g ON g.id = t.agent_id WHERE t.id = tid), 'giao cho quan-tri-du-lieu';
  SELECT id INTO ob FROM agent.outbox WHERE task_id = tid AND kind = 'dispatch'; ASSERT ob IS NOT NULL, 'có thẻ chờ gửi';
  PERFORM agent.outbox_ack(ob, 't_mt1'); PERFORM agent.ingest_event('eos-maint', 't_mt1', 'claimed', 'k-mt-1');

  -- 3. Phạm vi chỉ đọc: eos_project_scope trả KB và thư mục md; các công cụ ghi bị từ chối
  PERFORM pg_temp.as_agent('quan-tri-du-lieu');
  res := agent.mcp_project_scope(tid);
  ASSERT (res->>'standalone')::boolean AND res->'project'->>'slug' = 'du-an-a' AND res->'kb'->>'weknora_kb_id' = 'wkkb-proj-0001' AND res->>'md_folder_id' = 'MDROOT0000001' AND res->'task'->'scope'->>'stage' = 'wiki_lint', 'phạm vi wiki_lint: ' || res::text;
  BEGIN PERFORM agent.mcp_catalog_upsert(tid, '[{"category":"x","title":"Hồ sơ thử"}]'); ASSERT false, 'wiki_lint không ghi danh mục'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.mcp_tag_step(tid, '[{"drive_id":"ABCDEFGHIJ","buoc":"01"}]'); ASSERT false, 'wiki_lint không gắn mã bước'; EXCEPTION WHEN raise_exception OR insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.mcp_kb_ingest_target(tid); ASSERT false, 'wiki_lint không nạp kho'; EXCEPTION WHEN raise_exception OR insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_target(tid, 'phap-luat'); ASSERT false, 'quan-tri-du-lieu không dùng luồng pháp luật'; EXCEPTION WHEN raise_exception OR insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_agent('van-thu');
  BEGIN PERFORM agent.mcp_project_scope(tid); ASSERT false, 'agent khác không đọc việc wiki_lint'; EXCEPTION WHEN raise_exception OR insufficient_privilege THEN NULL; END;
  -- phạm vi sai project
  PERFORM pg_temp.as_user(own);
  UPDATE agent.task_scopes SET scope = scope || '{"project":"khong-co"}' WHERE task_id = tid;
  PERFORM pg_temp.as_agent('quan-tri-du-lieu');
  BEGIN PERFORM agent.mcp_project_scope(tid); ASSERT false, 'project không tồn tại'; EXCEPTION WHEN raise_exception THEN NULL; END;

  -- 4. Rà hiệu lực pháp luật: phap-che chưa bật cho công ty thì việc vẫn tạo (cho người), không giao agent
  PERFORM pg_temp.as_user(own);
  INSERT INTO work.recurrences (company_id, title, assignee_id, freq, month_day, next_run, active, agent_code, scope, created_by)
  VALUES (c, 'Rà hiệu lực KB pháp luật (hằng tháng)', own, 'monthly', 1, today, true, 'phap-che', '{"stage":"law_review","kb":"phap-luat","skill":"ra-hieu-luc-phap-luat"}', own) RETURNING id INTO rid2;
  tid2 := work._run_recurrence(rid2, today);
  ASSERT tid2 IS NOT NULL AND (SELECT agent_id IS NULL FROM work.tasks WHERE id = tid2) AND NOT EXISTS (SELECT 1 FROM agent.task_scopes WHERE task_id = tid2), 'agent chưa bật: việc vẫn tạo nhưng không giao';
  INSERT INTO agent.company_agents (company_id, agent_id) SELECT c, id FROM agent.agents WHERE code = 'phap-che';
  UPDATE work.recurrences SET next_run = today WHERE id = rid2;
  tid2 := work._run_recurrence(rid2, today);
  ASSERT (SELECT scope->>'stage' = 'law_review' AND run_id IS NULL FROM agent.task_scopes WHERE task_id = tid2), 'phạm vi law_review';
  SELECT id INTO ob FROM agent.outbox WHERE task_id = tid2 AND kind = 'dispatch'; PERFORM agent.outbox_ack(ob, 't_mt2'); PERFORM agent.ingest_event('eos-maint', 't_mt2', 'claimed', 'k-mt-2');

  INSERT INTO kb.bases (company_id, weknora_kb_id, name, scope, description, accepts_wiki) VALUES (c, 'wkkb-law-0001', 'phap-luat', 'shared_legal', 'x', true);
  INSERT INTO kb.law_sources (company_id, so_hieu, ten, co_quan, ngay_ban_hanh, tinh_trang, nguon_url, ngay_tra, weknora_kb_id, weknora_doc_id, phien_ban, created_by) VALUES
   (c, '1/2020/ND-CP', 'Văn bản A', 'Chính phủ', '2020-01-01', 'con_hieu_luc', 'https://vbpl.vn/a', '2026-01-01', 'wkkb-law-0001', 'd1', repeat('a', 32), 'test'),
   (c, '2/2021/ND-CP', 'Văn bản B', 'Chính phủ', '2021-01-01', 'het_hieu_luc', 'https://vbpl.vn/b', '2026-01-01', 'wkkb-law-0001', 'd2', repeat('b', 32), 'test');
  PERFORM pg_temp.as_agent('phap-che');
  res := agent.mcp_project_scope(tid2);
  ASSERT (res->>'standalone')::boolean AND res->'task'->'scope'->>'stage' = 'law_review' AND res->'law_kb_names' = '["phap-luat","tieu-chuan"]'::jsonb, 'phạm vi law_review: ' || res::text;
  res := agent.mcp_law_list(tid2, 'phap-luat', '{}');
  ASSERT (res->>'total')::int = 2 AND jsonb_array_length(res->'items') = 2 AND res->'items'->0->>'so_hieu' = '1/2020/ND-CP', 'danh mục: ' || res::text;
  res := agent.mcp_law_list(tid2, 'phap-luat', '{"tinh_trang":"het_hieu_luc","limit":1}'); ASSERT (res->>'total')::int = 1 AND jsonb_array_length(res->'items') = 1, 'lọc theo tình trạng';
  BEGIN PERFORM agent.mcp_law_list(tid2, 'du-an-x', '{}'); ASSERT false, 'KB ngoài danh sách'; EXCEPTION WHEN OTHERS THEN NULL; END;
  -- law_review CHỈ đọc: không nạp, không đánh dấu, không lưu tệp
  BEGIN PERFORM agent.mcp_law_ingest_claim(tid2, 'phap-luat', '["ABCDEFGHIJK"]'); ASSERT false, 'law_review không nạp'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_mark(tid2, 'phap-luat', '{"so_hieu":"1/2020/ND-CP","tinh_trang":"het_hieu_luc"}'); ASSERT false, 'law_review không đánh dấu'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_save_target(tid2, 'a.md', repeat('a', 64)); ASSERT false, 'law_review không lưu tệp'; EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM pg_temp.as_agent('quan-tri-du-lieu');
  BEGIN PERFORM agent.mcp_law_list(tid2, 'phap-luat', '{}'); ASSERT false, 'chỉ phap-che đọc danh mục'; EXCEPTION WHEN OTHERS THEN NULL; END;
  -- việc law_review do thành viên thường tạo: bị từ chối
  PERFORM pg_temp.as_user(own);
  UPDATE work.tasks SET created_by = tv WHERE id = tid2;
  PERFORM pg_temp.as_agent('phap-che');
  BEGIN PERFORM agent.mcp_law_list(tid2, 'phap-luat', '{}'); ASSERT false, 'người tạo không có quyền'; EXCEPTION WHEN OTHERS THEN NULL; END;

  -- 5. Việc định kỳ đã tạo không bật sẵn nếu mẫu để active = false
  INSERT INTO work.recurrences (company_id, title, freq, next_run, active, agent_code, scope, created_by) VALUES (c, 'Mẫu chưa bật', 'weekly', today, false, 'phap-che', '{"stage":"law_review"}', own) RETURNING id INTO rid;
  ASSERT work._run_recurrence(rid, today) IS NULL, 'mẫu tắt không sinh việc';
  RAISE NOTICE 'Việc đứng riêng ok';
END $$;
DO $$ BEGIN RAISE NOTICE 'test_maint: tất cả kiểm thử đều đạt'; END $$;
ROLLBACK;
