-- Kiểm thử luồng nạp văn bản pháp luật (db/65_law.sql): chạy sau 00..65. Dữ liệu thử, tự ROLLBACK.
\set ON_ERROR_STOP 1
BEGIN;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $f$
  SELECT set_config('request.jwt.claims', json_build_object('sub', u, 'via', 'web')::text, true) $f$;
CREATE FUNCTION pg_temp.as_agent(p_code text) RETURNS void LANGUAGE sql AS $f$
  SELECT set_config('request.jwt.claims', json_build_object('sub', a.user_id, 'role', 'agent', 'agent', a.id, 'via', 'agent:' || a.code)::text, true) FROM agent.agents a WHERE a.code = p_code $f$;

INSERT INTO core.companies (id, slug, name) VALUES ('88888888-8888-8888-8888-888888888888', 'law', 'Công ty Pháp luật');
INSERT INTO core.users (id, email, name, kind, is_system_admin) VALUES
 ('88aaaaaa-0000-0000-0000-000000000001', 'chu@law.vn', 'Chủ', 'person', true),
 ('88aaaaaa-0000-0000-0000-000000000002', 'tv@law.vn', 'Thành viên', 'person', false),
 ('88aaaaaa-0000-0000-0000-000000000003', 'qt@law.vn', 'Quản trị', 'person', false),
 ('88bbbbbb-0000-0000-0000-000000000001', 'pc@agent', 'Pháp chế AI', 'agent', false),
 ('88bbbbbb-0000-0000-0000-000000000002', 'vt@agent', 'Văn thư AI', 'agent', false);
INSERT INTO core.memberships (user_id, company_id) SELECT id, '88888888-8888-8888-8888-888888888888' FROM core.users WHERE email IN ('chu@law.vn', 'tv@law.vn', 'qt@law.vn');
INSERT INTO core.user_roles (company_id, user_id, role_id) VALUES
 ('88888888-8888-8888-8888-888888888888', '88aaaaaa-0000-0000-0000-000000000001', agent._sys_role('owner')),
 ('88888888-8888-8888-8888-888888888888', '88aaaaaa-0000-0000-0000-000000000002', agent._sys_role('member')),
 ('88888888-8888-8888-8888-888888888888', '88aaaaaa-0000-0000-0000-000000000003', agent._sys_role('admin'));
INSERT INTO agent.agents (user_id, code, name, kind, module, hermes_profile, skills, max_level, can_delegate, executor) VALUES
 ('88bbbbbb-0000-0000-0000-000000000001', 'phap-che', 'Pháp chế AI', 'specialist', 'doc', 'eos-phap-che', '{}', 1, false, 'hermes'),
 ('88bbbbbb-0000-0000-0000-000000000002', 'van-thu', 'Văn thư AI', 'module', 'doc', 'eos-van-thu', '{}', 1, false, 'hermes');
INSERT INTO agent.company_settings (company_id, enabled, kanban_board) VALUES ('88888888-8888-8888-8888-888888888888', true, 'eos-law');
INSERT INTO agent.company_agents (company_id, agent_id) SELECT '88888888-8888-8888-8888-888888888888', id FROM agent.agents WHERE code = 'van-thu';   -- phap-che chưa bật

DO $$ DECLARE c constant uuid := '88888888-8888-8888-8888-888888888888'; own constant uuid := '88aaaaaa-0000-0000-0000-000000000001'; tv constant uuid := '88aaaaaa-0000-0000-0000-000000000002'; qt constant uuid := '88aaaaaa-0000-0000-0000-000000000003';
              r jsonb; tid bigint; ob bigint; res jsonb; tk text; sc text[]; md5a constant text := repeat('a', 32); md5b constant text := repeat('b', 32); n int; fid text := 'LAWFILE000001';
              item jsonb := jsonb_build_object('so_hieu', '123/2024/NĐ-CP', 'ten', 'Nghị định mẫu', 'loai', 'nghị định', 'co_quan', 'Chính phủ', 'ngay_ban_hanh', '2024-01-02', 'tinh_trang', 'con_hieu_luc',
                'linh_vuc', 'xây dựng', 'buoc', jsonb_build_array('06', '09'), 'nguon', 'https://vbpl.vn/x', 'ngay_tra', '2026-11-01', 'drive_id', 'LAWFILE000001', 'weknora_doc_id', 'wkdoc-law-1', 'phien_ban', repeat('a', 32));
BEGIN
  -- 1. Tạo việc: quyền, đầu vào, điều kiện
  PERFORM pg_temp.as_user(tv);
  BEGIN PERFORM agent.app_law_task_create(jsonb_build_object('company_id', c, 'kb_name', 'phap-luat', 'items', '["123/2024/NĐ-CP"]'::jsonb)); ASSERT false, 'thành viên thường không tạo được'; EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM pg_temp.as_user(own);
  BEGIN PERFORM agent.app_law_task_create(jsonb_build_object('company_id', c, 'kb_name', 'phap-luat', 'items', '["123/2024/NĐ-CP"]'::jsonb)); ASSERT false, 'chưa cấu hình thư mục pháp luật'; EXCEPTION WHEN raise_exception THEN NULL; END;
  UPDATE agent.company_settings SET law_md_folder_id = 'LAWFOLDER0001' WHERE company_id = c;
  BEGIN PERFORM agent.app_law_task_create(jsonb_build_object('company_id', c, 'kb_name', 'phap-luat', 'items', '["123/2024/NĐ-CP"]'::jsonb)); ASSERT false, 'phap-che chưa bật cho công ty'; EXCEPTION WHEN raise_exception THEN NULL; END;
  INSERT INTO agent.company_agents (company_id, agent_id) SELECT c, id FROM agent.agents WHERE code = 'phap-che';
  BEGIN PERFORM agent.app_law_task_create(jsonb_build_object('company_id', c, 'kb_name', 'du-an-x', 'items', '["a"]'::jsonb)); ASSERT false, 'KB ngoài danh sách bị từ chối'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.app_law_task_create(jsonb_build_object('company_id', c, 'kb_name', 'phap-luat', 'items', '[]'::jsonb)); ASSERT false, 'danh sách rỗng'; EXCEPTION WHEN raise_exception THEN NULL; END;
  r := agent.app_law_task_create(jsonb_build_object('company_id', c, 'kb_name', 'phap-luat', 'items', '["123/2024/NĐ-CP", " https://vbpl.vn/abc ", ""]'::jsonb));
  tid := (r->>'task_id')::bigint; ASSERT (r->>'count')::int = 2, 'bỏ dòng trống: ' || r::text;
  ASSERT (SELECT run_id IS NULL AND scope->>'stage' = 'law_ingest' AND scope->>'kb' = 'phap-luat' AND jsonb_array_length(scope->'items') = 2 FROM agent.task_scopes WHERE task_id = tid), 'phạm vi law_ingest không gắn lần chạy';
  ASSERT (SELECT agent_id = (SELECT id FROM agent.agents WHERE code = 'phap-che') FROM work.tasks WHERE id = tid), 'giao cho phap-che';
  SELECT id INTO ob FROM agent.outbox WHERE task_id = tid AND kind = 'dispatch'; ASSERT ob IS NOT NULL, 'có thẻ chờ gửi cho phap-che';
  -- quản trị (admin) cũng tạo được
  PERFORM pg_temp.as_user(qt);
  PERFORM agent.app_law_task_create(jsonb_build_object('company_id', c, 'kb_name', 'tieu-chuan', 'items', '["TCVN 1"]'::jsonb));
  -- scope run_id NULL chỉ cho stage đứng riêng
  BEGIN INSERT INTO agent.task_scopes (task_id, run_id, scope, created_by) VALUES (tid, NULL, '{"stage":"kb_ingest"}', 'x'); ASSERT false, 'run_id NULL chỉ cho stage đứng riêng'; EXCEPTION WHEN unique_violation OR check_violation THEN NULL; END;

  -- 2. Chưa có thẻ chạy thì agent chưa gọi được; sau khi nhận thẻ thì gọi được
  PERFORM pg_temp.as_agent('phap-che');
  BEGIN PERFORM agent.mcp_law_target(tid, 'phap-luat'); ASSERT false, 'chưa có thẻ đang chạy'; EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM agent.outbox_ack(ob, 't_law1');
  -- thẻ đã có trên Hermes (todo) nhưng cầu nối chưa kịp ghi running: worker đã chạy thì vẫn gọi được (0036)
  ASSERT (SELECT status FROM agent.cards WHERE task_id = tid) = 'todo', 'thẻ todo sau khi cầu nối tạo';
  PERFORM agent.mcp_law_target(tid, 'phap-luat');
  PERFORM agent.ingest_event('eos-law', 't_law1', 'claimed', 'k-law-1');

  -- 3. Agent khác không gọi được (kể cả khi có thẻ cho việc khác); KB ngoài danh sách bị từ chối
  PERFORM pg_temp.as_agent('van-thu');
  BEGIN PERFORM agent.mcp_law_target(tid, 'phap-luat'); ASSERT false, 'van-thu không được dùng luồng pháp luật'; EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM pg_temp.as_agent('phap-che');
  BEGIN PERFORM agent.mcp_law_target(tid, 'du-an-x'); ASSERT false, 'KB ngoài danh sách'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_target(tid, 'phap-luat; drop table x'); ASSERT false, 'tên KB lạ'; EXCEPTION WHEN OTHERS THEN NULL; END;
  res := agent.mcp_law_target(tid, 'phap-luat');
  ASSERT res->>'law_md_folder_id' = 'LAWFOLDER0001' AND (res->>'kb_ready')::boolean = false AND res->>'kb_name' = 'phap-luat', 'đích chưa tạo: ' || res::text;
  ASSERT (SELECT scope = 'shared_legal' FROM kb.bases WHERE company_id = c AND name = 'phap-luat'), 'kb.bases scope shared_legal';

  -- 4. Lưu tệp: thư mục đích, đăng ký, trùng nội dung
  res := agent.mcp_law_save_target(tid, '123-2024-ND-CP.md', md5a);
  ASSERT res->>'law_md_folder_id' = 'LAWFOLDER0001' AND res->>'existing_drive_id' IS NULL AND (res->>'name_taken')::boolean = false, 'lần đầu: ' || res::text;
  BEGIN PERFORM agent.mcp_law_save_target(tid, '../x.md', md5a); ASSERT false, 'tên tệp xấu'; EXCEPTION WHEN raise_exception THEN NULL; END;
  PERFORM agent.mcp_law_save_done(tid, jsonb_build_object('drive_id', fid, 'name', '123-2024-ND-CP.md', 'url', 'https://drive.google.com/file/d/LAWFILE000001/view', 'sha256', md5a, 'bytes', 100, 'so_hieu', '123/2024/NĐ-CP'));
  res := agent.mcp_law_save_target(tid, '123-2024-ND-CP.md', md5a);
  ASSERT res->>'existing_drive_id' = fid, 'cùng tên và nội dung: dùng lại tệp đã có';
  res := agent.mcp_law_save_target(tid, '123-2024-ND-CP.md', md5b);
  ASSERT res->>'existing_drive_id' IS NULL AND (res->>'name_taken')::boolean, 'cùng tên khác nội dung: báo tên đã dùng (không ghi đè)';

  -- 5. Nạp: giữ chỗ → ghi → chạy lại không nạp trùng
  res := agent.mcp_law_ingest_claim(tid, 'phap-luat', to_jsonb(ARRAY[fid]));
  ASSERT (res->>'create_kb')::boolean AND res->'claimed' = to_jsonb(ARRAY[fid]), 'giữ chỗ lần đầu: ' || res::text;
  res := agent.mcp_law_ingest_claim(tid, 'phap-luat', to_jsonb(ARRAY[fid]));
  ASSERT jsonb_array_length(res->'claimed') = 0 AND jsonb_array_length(res->'busy') = 1, 'gọi song song: bị giữ chỗ';
  res := agent.mcp_law_version(tid, 'phap-luat', '123/2024/NĐ-CP', md5a); ASSERT res->>'same' IS NULL AND jsonb_array_length(res->'earlier') = 0, 'chưa nạp';
  BEGIN PERFORM agent.mcp_law_ingest_commit(tid, 'phap-luat', jsonb_build_object('items', jsonb_build_array(item))); ASSERT false, 'KB chưa tạo trên WeKnora'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_ingest_commit(tid, 'phap-luat', jsonb_build_object('weknora_kb_id', 'bad id', 'items', '[]'::jsonb)); ASSERT false, 'mã KB xấu'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_ingest_commit(tid, 'phap-luat', jsonb_build_object('weknora_kb_id', 'lawkb-0001', 'items', jsonb_build_array(item || '{"tinh_trang":"khac"}'))); ASSERT false, 'tình trạng lạ'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_ingest_commit(tid, 'phap-luat', jsonb_build_object('weknora_kb_id', 'lawkb-0001', 'items', jsonb_build_array(item || '{"nguon":"http://vbpl.vn/x"}'))); ASSERT false, 'nguồn không https'; EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_ingest_commit(tid, 'phap-luat', jsonb_build_object('weknora_kb_id', 'lawkb-0001', 'items', jsonb_build_array(item || '{"buoc":["21"]}'))); ASSERT false, 'mã bước 21'; EXCEPTION WHEN check_violation THEN NULL; END;
  res := agent.mcp_law_ingest_commit(tid, 'phap-luat', jsonb_build_object('weknora_kb_id', 'lawkb-0001', 'items', jsonb_build_array(item)));
  ASSERT (res->>'registered')::int = 1 AND res->>'weknora_kb_id' = 'lawkb-0001', 'ghi: ' || res::text;
  PERFORM agent.mcp_law_ingest_finish(tid, 'phap-luat', jsonb_build_object('done', jsonb_build_array(fid), 'release', jsonb_build_array('__create__')));
  PERFORM agent.mcp_law_ingest_commit(tid, 'phap-luat', jsonb_build_object('items', jsonb_build_array(item)));   -- ghi lại cùng phiên bản
  SELECT count(*) INTO n FROM kb.law_sources WHERE so_hieu = '123/2024/NĐ-CP'; ASSERT n = 1, 'ghi lại không tạo dòng trùng: ' || n;
  SELECT count(*) INTO n FROM kb.sources WHERE weknora_doc_id = 'wkdoc-law-1' AND state = 'loaded'; ASSERT n = 1, 'kb.sources';
  res := agent.mcp_law_ingest_claim(tid, 'phap-luat', to_jsonb(ARRAY[fid]));
  ASSERT jsonb_array_length(res->'claimed') = 0 AND res->'busy'->0->>'reason' = 'đã nạp trước đó', 'chạy lại: đã nạp trước đó';
  res := agent.mcp_law_version(tid, 'phap-luat', '123/2024/NĐ-CP', md5a); ASSERT res->>'same' = 'wkdoc-law-1', 'cùng số hiệu cùng nội dung: biết là đã nạp';
  res := agent.mcp_law_version(tid, 'phap-luat', '123/2024/NĐ-CP', md5b); ASSERT res->>'same' IS NULL AND jsonb_array_length(res->'earlier') = 1, 'nội dung mới: có phiên bản trước';
  -- phiên bản mới của cùng số hiệu: bản cũ chuyển 'superseded' ở CSDL, không xóa
  PERFORM agent.mcp_law_save_done(tid, jsonb_build_object('drive_id', 'LAWFILE000002', 'name', '123-2024-ND-CP-b.md', 'url', 'https://drive.google.com/file/d/LAWFILE000002/view', 'sha256', md5b, 'bytes', 120));
  PERFORM agent.mcp_law_ingest_commit(tid, 'phap-luat', jsonb_build_object('items', jsonb_build_array(item || jsonb_build_object('phien_ban', md5b, 'weknora_doc_id', 'wkdoc-law-2', 'drive_id', 'LAWFILE000002'))));
  SELECT count(*) INTO n FROM kb.law_sources WHERE so_hieu = '123/2024/NĐ-CP'; ASSERT n = 2, 'hai phiên bản';
  ASSERT (SELECT state FROM kb.sources WHERE weknora_doc_id = 'wkdoc-law-1') = 'superseded' AND (SELECT state FROM kb.sources WHERE weknora_doc_id = 'wkdoc-law-2') = 'loaded', 'bản cũ superseded, bản mới loaded';

  -- 6. Đánh dấu hết hiệu lực (không xóa)
  res := agent.mcp_law_mark(tid, 'phap-luat', '{"so_hieu":"123/2024/NĐ-CP","tinh_trang":"het_hieu_luc","thay_the":"99/2025/NĐ-CP"}');
  ASSERT (res->>'updated')::int = 2 AND jsonb_array_length(res->'docs') = 2 AND res->'docs'->0->>'thay_the' = '99/2025/NĐ-CP' AND res->'docs'->0->>'buoc' = '06,09', 'đánh dấu: ' || res::text;
  ASSERT (SELECT bool_and(tinh_trang = 'het_hieu_luc') FROM kb.law_sources WHERE so_hieu = '123/2024/NĐ-CP'), 'tình trạng đã đổi';
  BEGIN PERFORM agent.mcp_law_mark(tid, 'phap-luat', '{"so_hieu":"123/2024/NĐ-CP","tinh_trang":"bi_xoa"}'); ASSERT false, 'tình trạng lạ'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_mark(tid, 'phap-luat', '{"so_hieu":"chua-nap/2020","tinh_trang":"het_hieu_luc"}'); ASSERT false, 'văn bản chưa nạp'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_mark(tid, 'tieu-chuan', '{"so_hieu":"123/2024/NĐ-CP","tinh_trang":"het_hieu_luc"}'); ASSERT false, 'KB khác: không có văn bản này'; EXCEPTION WHEN raise_exception THEN NULL; END;

  -- 7. Việc do người không có quyền / do agent tạo: bị từ chối dù giao đúng phap-che và có thẻ chạy
  PERFORM pg_temp.as_user(own);
  INSERT INTO work.tasks (company_id, title, assignee_id, created_by, source) VALUES (c, 'Nạp (do thành viên tạo)', tv, tv, 'manual') RETURNING id INTO tid;
  INSERT INTO agent.task_scopes (task_id, run_id, skill, scope, created_by) VALUES (tid, NULL, 'nap-van-ban-phap-luat', '{"stage":"law_ingest","agent":"phap-che","kb":"phap-luat","items":["x"]}', 'user:tv');
  UPDATE work.tasks SET agent_id = (SELECT id FROM agent.agents WHERE code = 'phap-che') WHERE id = tid;
  SELECT id INTO ob FROM agent.outbox WHERE task_id = tid AND kind = 'dispatch';
  PERFORM agent.outbox_ack(ob, 't_law2'); PERFORM agent.ingest_event('eos-law', 't_law2', 'claimed', 'k-law-2');
  PERFORM pg_temp.as_agent('phap-che');
  BEGIN PERFORM agent.mcp_law_target(tid, 'phap-luat'); ASSERT false, 'người tạo là thành viên thường'; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN PERFORM agent.mcp_law_ingest_claim(tid, 'phap-luat', to_jsonb(ARRAY[fid])); ASSERT false, 'claim cũng bị chặn'; EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM pg_temp.as_user(own);
  INSERT INTO work.tasks (company_id, title, assignee_id, created_by, source) VALUES (c, 'Nạp (do agent tạo)', own, '88bbbbbb-0000-0000-0000-000000000002', 'manual') RETURNING id INTO tid;
  INSERT INTO agent.task_scopes (task_id, run_id, skill, scope, created_by) VALUES (tid, NULL, 'nap-van-ban-phap-luat', '{"stage":"law_ingest","agent":"phap-che","kb":"phap-luat","items":["x"]}', 'agent:van-thu');
  UPDATE work.tasks SET agent_id = (SELECT id FROM agent.agents WHERE code = 'phap-che') WHERE id = tid;
  SELECT id INTO ob FROM agent.outbox WHERE task_id = tid AND kind = 'dispatch';
  PERFORM agent.outbox_ack(ob, 't_law3'); PERFORM agent.ingest_event('eos-law', 't_law3', 'claimed', 'k-law-3');
  PERFORM pg_temp.as_agent('phap-che');
  BEGIN PERFORM agent.mcp_law_target(tid, 'phap-luat'); ASSERT false, 'người tạo là agent'; EXCEPTION WHEN OTHERS THEN NULL; END;
  -- việc có stage khác (vd. wiki_lint) bị từ chối
  PERFORM pg_temp.as_user(own);
  UPDATE agent.task_scopes SET scope = '{"stage":"wiki_lint","agent":"phap-che"}' WHERE task_id = tid;
  PERFORM pg_temp.as_agent('phap-che');
  BEGIN PERFORM agent.mcp_law_target(tid, 'phap-luat'); ASSERT false, 'sai giai đoạn'; EXCEPTION WHEN OTHERS THEN NULL; END;

  -- 8. Phạm vi mã law_ingest chỉ cấp cho phap-che; không có hàm xóa
  PERFORM pg_temp.as_user(own);
  tk := agent.mcp_token_issue_agent('phap-che', 30);
  SELECT scopes INTO sc FROM agent.mcp_tokens WHERE agent_id = (SELECT id FROM agent.agents WHERE code = 'phap-che') ORDER BY created_at DESC LIMIT 1;
  ASSERT 'law_ingest' = ANY (sc) AND 'project' = ANY (sc), 'mã phap-che có law_ingest: ' || sc::text;
  tk := agent.mcp_token_issue_agent('van-thu', 30);
  SELECT scopes INTO sc FROM agent.mcp_tokens WHERE agent_id = (SELECT id FROM agent.agents WHERE code = 'van-thu') ORDER BY created_at DESC LIMIT 1;
  ASSERT NOT ('law_ingest' = ANY (sc)), 'mã van-thu không có law_ingest';
  BEGIN UPDATE agent.mcp_tokens SET scopes = scopes || '{law_ingest}' WHERE agent_id = (SELECT id FROM agent.agents WHERE code = 'van-thu'); ASSERT false, 'không thêm law_ingest cho van-thu'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE agent.agents SET token_scopes = '{read,law_ingest}' WHERE code = 'van-thu'; ASSERT false, 'token_scopes van-thu không có law_ingest'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.mcp_token_issue('thử', 'other', '{read,law_ingest}', 30); ASSERT false, 'mã của người không có law_ingest'; EXCEPTION WHEN OTHERS THEN NULL; END;
  ASSERT NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'agent' AND p.proname ~ 'law' AND p.proname ~* '(delete|remove|drop|purge|xoa)'), 'không có hàm xóa pháp luật';
  ASSERT NOT has_table_privilege('mcp_svc', 'kb.law_sources', 'DELETE') AND NOT has_table_privilege('mcp_svc', 'kb.law_sources', 'UPDATE') AND NOT has_table_privilege('web_svc', 'kb.law_sources', 'SELECT'), 'bảng law_sources chỉ ghi qua hàm';
  ASSERT NOT has_function_privilege('web_svc', 'agent.mcp_law_mark(bigint,text,jsonb)', 'EXECUTE') AND NOT has_function_privilege('mcp_svc', 'agent.app_law_task_create(jsonb)', 'EXECUTE'), 'phân quyền hàm';
  -- unique (kb, số hiệu, phiên bản)
  BEGIN INSERT INTO kb.law_sources (company_id, so_hieu, ten, co_quan, ngay_ban_hanh, tinh_trang, nguon_url, ngay_tra, weknora_kb_id, weknora_doc_id, phien_ban, created_by)
        VALUES (c, '123/2024/NĐ-CP', 'trùng', 'x', '2024-01-01', 'con_hieu_luc', 'https://vbpl.vn/y', '2026-11-01', 'lawkb-0001', 'z', md5a, 'test'); ASSERT false, 'trùng (kb, số hiệu, phiên bản)'; EXCEPTION WHEN unique_violation THEN NULL; END;
  RAISE NOTICE 'Pháp luật ok';
END $$;
DO $$ BEGIN RAISE NOTICE 'test_law: tất cả kiểm thử đều đạt'; END $$;
ROLLBACK;
