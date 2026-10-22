-- Kiểm thử quy trình nạp hồ sơ dự án (db/62_workflow.sql): chạy sau 00..62. Dữ liệu thử, tự ROLLBACK.
\set ON_ERROR_STOP 1
BEGIN;
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $f$
  SELECT set_config('request.jwt.claims', json_build_object('sub', u, 'via', 'web')::text, true) $f$;
CREATE FUNCTION pg_temp.as_agent(p_code text) RETURNS void LANGUAGE sql AS $f$
  SELECT set_config('request.jwt.claims', json_build_object('sub', a.user_id, 'role', 'agent', 'agent', a.id, 'via', 'agent:' || a.code)::text, true) FROM agent.agents a WHERE a.code = p_code $f$;

INSERT INTO core.companies (id, slug, name) VALUES ('77777777-7777-7777-7777-777777777777', 'wf', 'Công ty Quy trình');
INSERT INTO core.departments (id, company_id, code, name) VALUES ('dddddddd-7777-0000-0000-000000000001', '77777777-7777-7777-7777-777777777777', 'DA', 'Dự án');
INSERT INTO core.users (id, email, name, kind, is_system_admin) VALUES
 ('77aaaaaa-0000-0000-0000-000000000001', 'chu@wf.vn', 'Chủ', 'person', true),
 ('77aaaaaa-0000-0000-0000-000000000002', 'theodoi@wf.vn', 'Người theo dõi', 'person', false),
 ('77aaaaaa-0000-0000-0000-000000000003', 'khac@wf.vn', 'Người khác', 'person', false),
 ('77bbbbbb-0000-0000-0000-000000000001', 'dp@agent', 'Điều phối AI', 'agent', false),
 ('77bbbbbb-0000-0000-0000-000000000002', 'vt@agent', 'Văn thư AI', 'agent', false),
 ('77bbbbbb-0000-0000-0000-000000000003', 'runner@agent', 'Runner Z2', 'agent', false),
 ('77bbbbbb-0000-0000-0000-000000000004', 'pc@agent', 'Pháp chế AI', 'agent', false);
INSERT INTO core.memberships (user_id, company_id, department_id) SELECT id, '77777777-7777-7777-7777-777777777777', 'dddddddd-7777-0000-0000-000000000001' FROM core.users WHERE email IN ('chu@wf.vn', 'theodoi@wf.vn', 'khac@wf.vn');
INSERT INTO core.user_roles (company_id, user_id, role_id) VALUES
 ('77777777-7777-7777-7777-777777777777', '77aaaaaa-0000-0000-0000-000000000001', agent._sys_role('owner')),
 ('77777777-7777-7777-7777-777777777777', '77aaaaaa-0000-0000-0000-000000000002', agent._sys_role('member')),
 ('77777777-7777-7777-7777-777777777777', '77aaaaaa-0000-0000-0000-000000000003', agent._sys_role('member'));
INSERT INTO agent.agents (user_id, code, name, kind, module, hermes_profile, skills, max_level, can_delegate, executor) VALUES
 ('77bbbbbb-0000-0000-0000-000000000001', 'dieu-phoi', 'Điều phối AI', 'orchestrator', 'work', 'eos-dieu-phoi', '{}', 2, true, 'hermes'),
 ('77bbbbbb-0000-0000-0000-000000000002', 'van-thu', 'Văn thư AI', 'module', 'doc', 'eos-van-thu', '{ho-so-danh-muc}', 1, false, 'hermes'),
 ('77bbbbbb-0000-0000-0000-000000000003', 'ho-so-runner', 'Runner hồ sơ Z2', 'specialist', 'kb', 'z2-runner', '{}', 1, false, 'runner'),
 ('77bbbbbb-0000-0000-0000-000000000004', 'phap-che', 'Pháp chế AI', 'specialist', 'doc', 'eos-phap-che', '{}', 0, false, 'hermes');
INSERT INTO agent.company_settings (company_id, enabled, kanban_board) VALUES ('77777777-7777-7777-7777-777777777777', true, 'eos-wf');
INSERT INTO agent.company_agents (company_id, agent_id) SELECT '77777777-7777-7777-7777-777777777777', id FROM agent.agents WHERE code IN ('dieu-phoi', 'van-thu', 'ho-so-runner');   -- phap-che chưa bật cho công ty

DO $$ DECLARE c constant uuid := '77777777-7777-7777-7777-777777777777'; own constant uuid := '77aaaaaa-0000-0000-0000-000000000001'; sup constant uuid := '77aaaaaa-0000-0000-0000-000000000002';
              r jsonb; run bigint; root bigint; dp agent.outbox; oid bigint; kids jsonb; k_z2 bigint; k_vt bigint; res jsonb; ca jsonb; folder constant text := 'https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOp'; BEGIN
  -- 1. Bắt đầu: quyền, đầu vào
  PERFORM pg_temp.as_user(sup);
  BEGIN PERFORM agent.app_workflow_start(jsonb_build_object('company_id', c, 'project_name', 'Khu đô thị A', 'drive_url', folder, 'supervisor_id', sup)); ASSERT false, 'thành viên thường không bắt đầu'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user(own);
  BEGIN PERFORM agent.app_workflow_start(jsonb_build_object('company_id', c, 'project_name', 'Khu đô thị A', 'drive_url', 'https://evil.example/x', 'supervisor_id', sup)); ASSERT false, 'link lạ'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.app_workflow_start(jsonb_build_object('company_id', c, 'project_name', 'Khu đô thị A', 'drive_url', folder, 'supervisor_id', '77bbbbbb-0000-0000-0000-000000000002')); ASSERT false, 'người theo dõi là agent'; EXCEPTION WHEN raise_exception THEN NULL; END;
  r := agent.app_workflow_start(jsonb_build_object('company_id', c, 'project_name', 'Khu đô thị A', 'drive_url', folder || '?usp=sharing', 'supervisor_id', sup, 'note', 'Dữ liệu mẫu'));
  run := (r->>'run_id')::bigint; root := (r->>'root_task')::bigint;
  ASSERT (SELECT slug = 'khu-do-thi-a' AND manager_id = sup FROM core.projects WHERE id = (r->>'project_id')::uuid), 'dự án tạo với người theo dõi là quản lý';
  ASSERT EXISTS (SELECT 1 FROM kb.bases WHERE project_id = (r->>'project_id')::uuid AND scope = 'project' AND weknora_kb_id = 'pending:khu-do-thi-a'), 'kho tri thức giữ chỗ';
  ASSERT (SELECT assignee_id = sup AND created_by = sup AND agent_role = 'dieu-phoi-du-an' AND agent_id = (SELECT id FROM agent.agents WHERE code = 'dieu-phoi') FROM work.tasks WHERE id = root), 'việc gốc: người theo dõi phụ trách và duyệt, giao điều phối';
  ASSERT (SELECT scope->>'drive_folder_id' = '1AbCdEfGhIjKlMnOp' FROM agent.task_scopes WHERE task_id = root), 'phạm vi việc gốc ghi vào CSDL';
  SELECT * INTO dp FROM agent.outbox WHERE task_id = root AND kind = 'dispatch';
  ASSERT dp.id IS NOT NULL AND dp.payload->>'profile' = 'eos-dieu-phoi', 'điều phối nhận việc qua hộp thư đi';
  BEGIN PERFORM agent.app_workflow_start(jsonb_build_object('company_id', c, 'project_id', r->>'project_id', 'drive_url', folder, 'supervisor_id', sup)); ASSERT false, 'đang chạy rồi'; EXCEPTION WHEN raise_exception THEN NULL; END;
  ASSERT jsonb_array_length(agent.app_workflow_runs(jsonb_build_object('company_id', c))) = 1, 'danh sách lần chạy';
  PERFORM pg_temp.as_user('77aaaaaa-0000-0000-0000-000000000003');
  ASSERT jsonb_array_length(agent.app_workflow_runs(jsonb_build_object('company_id', c))) = 0, 'người không liên quan không thấy lần chạy';

  -- 2. Điều phối nhận thẻ, đọc phạm vi, chia việc
  PERFORM agent.outbox_ack(dp.id, 't_dp1');
  PERFORM agent.ingest_event('eos-wf', 't_dp1', 'claimed', 'k-dp-claim');
  PERFORM pg_temp.as_agent('dieu-phoi');
  res := agent.mcp_project_scope(root);
  ASSERT res->>'md_folder_id' IS NULL AND res->'task'->'scope'->>'stage' = 'orchestrate' AND res->>'source_drive_folder_id' = '1AbCdEfGhIjKlMnOp' AND res->'kb'->>'ready' = 'false'
         AND res->>'supervisor' = 'Người theo dõi' AND length(res->>'playbook') > 100, format('scope điều phối: %s', left(res::text, 300));
  BEGIN PERFORM agent.delegate(root, '[{"agent":"ho-so-runner","title":"Xử lý hồ sơ","skill":"xu-ly-ho-so"}]'); ASSERT false, 'thiếu scope'; EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE '%phạm vi%' THEN RAISE; END IF; END;
  BEGIN PERFORM agent.delegate(root, '[{"agent":"phap-che","title":"Rà pháp lý","skill":"ra-soat-phap-che","scope":{"stage":"legal"}}]'); ASSERT false, 'agent chưa bật cho công ty'; EXCEPTION WHEN raise_exception THEN NULL; END;
  kids := agent.delegate(root, '[
    {"agent":"ho-so-runner","title":"Tải, chuyển Markdown và đăng ký hồ sơ","skill":"xu-ly-ho-so","scope":{"stage":"fetch_convert","paths":["/"]}},
    {"agent":"van-thu","title":"Lập danh mục hồ sơ và tổng hợp văn bản","skill":"ho-so-danh-muc","scope":{"stage":"catalog","doc_types":["hop-dong","phap-ly"]},"after":[0]}]');
  SELECT replace(kids->'children'->>0, 'T-', '')::bigint, replace(kids->'children'->>1, 'T-', '')::bigint INTO k_z2, k_vt;
  ASSERT (SELECT count(*) FROM agent.task_scopes WHERE run_id = run) = 3, 'mỗi việc có một dòng phạm vi';
  ASSERT (SELECT scope->>'agent' = 'ho-so-runner' AND skill = 'xu-ly-ho-so' AND created_by = 'agent:dieu-phoi' FROM agent.task_scopes WHERE task_id = k_z2), 'phạm vi việc con ghi agent và kỹ năng';
  ASSERT (SELECT assignee_id = sup AND created_by = sup AND NOT kpi_counted FROM work.tasks WHERE id = k_z2), 'việc con: người theo dõi phụ trách và duyệt';
  -- runner: thẻ sẵn sàng, không có hộp thư đi; việc phụ thuộc chưa chạy
  ASSERT (SELECT status = 'ready' AND card_id LIKE 'runner-%' FROM agent.cards WHERE task_id = k_z2), 'thẻ runner sẵn sàng';
  ASSERT NOT EXISTS (SELECT 1 FROM agent.outbox WHERE task_id = k_z2), 'runner không đi qua hộp thư đi';
  ASSERT NOT EXISTS (SELECT 1 FROM agent.cards WHERE task_id = k_vt), 'văn thư chờ runner xong';

  -- 3. Runner nhận việc, đăng ký dữ liệu, báo xong
  PERFORM pg_temp.as_agent('van-thu');
  BEGIN PERFORM agent.mcp_runner_claim(); ASSERT false, 'agent thường không nhận việc runner'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.mcp_project_scope(root); ASSERT false, 'văn thư chưa có thẻ'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_agent('ho-so-runner');
  res := agent.mcp_runner_claim();
  ASSERT res->'task'->>'id' = k_z2::text AND res->>'skill' = 'xu-ly-ho-so' AND res->'scope'->>'stage' = 'fetch_convert' AND res->'run'->>'project' = 'khu-do-thi-a', format('claim: %s', left(res::text, 300));
  ASSERT (agent.mcp_runner_claim())->>'idle' = 'true', 'hết việc thì idle';
  ASSERT (SELECT status = 'in_progress' FROM work.tasks WHERE id = k_z2), 'nhận việc → Đang làm';
  ASSERT agent.mcp_runner_report(res->>'card', 'heartbeat', 'hb-0001', '{"progress": 40}') = 'ok', 'heartbeat';
  ASSERT agent.mcp_runner_report(res->>'card', 'heartbeat', 'hb-0001', '{"progress": 40}') = 'duplicate', 'chống lặp sự kiện';
  BEGIN PERFORM agent.mcp_runner_report(res->>'card', 'archived', 'xx-0001'); ASSERT false, 'sự kiện không cho phép'; EXCEPTION WHEN raise_exception THEN NULL; END;
  ca := agent.mcp_runner_setup(k_z2, jsonb_build_object('md_folder_id', '1MdFolderIdAbcdef', 'weknora_kb_id', 'kb-uuid-0001',
        'files', jsonb_build_array(jsonb_build_object('drive_id', 'F1abcdefghij', 'name', 'HD-01.md', 'mime', 'text/markdown', 'url', 'https://drive.google.com/file/d/F1abcdefghij/view', 'bytes', 1200),
                                   jsonb_build_object('drive_id', 'F2abcdefghij', 'name', 'QD-02.md', 'url', 'https://drive.google.com/file/d/F2abcdefghij/view')),
        'sources', jsonb_build_array(jsonb_build_object('weknora_doc_id', 'doc-1', 'title', 'HD-01', 'drive_id', 'F1abcdefghij', 'pages', 12))));
  ASSERT (ca->>'files')::int = 2 AND (ca->>'sources')::int = 1, format('setup: %s', ca);
  ASSERT (SELECT md_folder_id = '1MdFolderIdAbcdef' FROM agent.workflow_runs WHERE id = run) AND (SELECT weknora_kb_id = 'kb-uuid-0001' FROM kb.bases WHERE project_id = (SELECT project_id FROM agent.workflow_runs WHERE id = run)), 'thư mục md và mã KB ghi vào lần chạy';
  ASSERT EXISTS (SELECT 1 FROM kb.sources WHERE weknora_doc_id = 'doc-1' AND file_id IS NOT NULL), 'nguồn KB gắn tệp';
  BEGIN PERFORM agent.mcp_runner_setup(k_z2, '{"files":[{"drive_id":"x1","url":"http://khong-an-toan"}]}'); ASSERT false, 'url http'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.mcp_runner_setup(root, '{"md_folder_id":"1Chiem0Quyenabcdef"}'); ASSERT false, 'không có thẻ cho việc gốc'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  ASSERT agent.mcp_runner_report(res->>'card', 'completed', 'done-0001', '{"summary":"Đã chuyển 2 tệp Markdown, 0 lỗi, đã đăng ký vào kho dữ liệu.","confidence":"cao"}') = 'ok', 'runner báo xong';
  -- việc con do điều phối chia tự đóng khi agent báo xong (người theo dõi duyệt bản tổng hợp ở việc gốc); báo cáo vẫn lưu
  ASSERT (SELECT status = 'done' FROM work.tasks WHERE id = k_z2) AND EXISTS (SELECT 1 FROM agent.reports WHERE task_id = k_z2 AND verdict = 'auto_done'), 'runner xong → việc con đóng, báo cáo lưu';

  -- 4. Runner xong → việc phụ thuộc chạy
  SELECT * INTO dp FROM agent.outbox WHERE task_id = k_vt AND kind = 'dispatch';
  ASSERT dp.id IS NOT NULL AND dp.payload->>'profile' = 'eos-van-thu' AND dp.payload->'skills' = '["ho-so-danh-muc","ho-so-danh-muc"]'::jsonb, format('văn thư được giao sau khi runner xong: %s', dp.payload);

  -- 5. Văn thư đọc phạm vi, lập danh mục
  PERFORM agent.outbox_ack(dp.id, 't_vt1');
  PERFORM agent.ingest_event('eos-wf', 't_vt1', 'claimed', 'k-vt-claim');
  PERFORM pg_temp.as_agent('van-thu');
  res := agent.mcp_project_scope(k_vt);
  ASSERT res->>'md_folder_id' = '1MdFolderIdAbcdef' AND res->'task'->'scope'->>'stage' = 'catalog' AND jsonb_array_length(res->'tasks') = 3, format('văn thư thấy thư mục md và các việc anh em: %s', left(res::text, 300));
  ca := agent.mcp_catalog_upsert(k_vt, '[{"category":"Hợp đồng","record_no":"HD-01/2026","title":"Hợp đồng thi công gói thầu 1","issued_on":"2026-03-01","contract_value":1500000000,"drive_id":"F1abcdefghij"},
                                         {"category":"Pháp lý","title":"Quyết định phê duyệt dự án","issued_on":"2026-01-10","drive_id":"F2abcdefghij"}]');
  ASSERT (ca->>'created')::int = 2 AND (ca->>'updated')::int = 0, format('danh mục: %s', ca);
  ca := agent.mcp_catalog_upsert(k_vt, '[{"category":"Hợp đồng","record_no":"HD-01/2026","title":"Hợp đồng thi công gói thầu 1 (đã sửa)","executed_value":900000000}]');
  ASSERT (ca->>'created')::int = 0 AND (ca->>'updated')::int = 1, 'cập nhật theo số hồ sơ, không nhân đôi';
  ASSERT (SELECT count(*) FROM doc.records WHERE project_id = (SELECT project_id FROM agent.workflow_runs WHERE id = run)) = 2, '2 hồ sơ trong danh mục dự án';
  ASSERT (SELECT contract_value = 1500000000 AND executed_value = 900000000 AND owner_id = sup FROM doc.records WHERE record_no = 'HD-01/2026'), 'giá trị giữ nguyên khi cập nhật; người theo dõi là người phụ trách hồ sơ';
  ASSERT (SELECT count(*) FROM core.attachments WHERE entity_type = 'record' AND role = 'source') = 2, 'hồ sơ gắn tệp nguồn';
  BEGIN PERFORM agent.mcp_catalog_upsert(k_vt, '[{"category":"","title":"x"}]'); ASSERT false, 'thiếu nhóm'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.mcp_catalog_upsert(k_z2, '[{"category":"Khác","title":"Hồ sơ lạ"}]'); ASSERT false, 'văn thư không có thẻ cho việc của runner'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.mcp_catalog_upsert(k_vt, (SELECT jsonb_agg(jsonb_build_object('category','A','title','Hồ sơ ' || g)) FROM generate_series(1, 51) g)); ASSERT false, 'quá 50 mục'; EXCEPTION WHEN raise_exception THEN NULL; END;

  -- 5b. Runner hỏi người (kb_ingest cần người nạp WeKnora): người trả lời → thẻ sẵn sàng lại, không có lệnh gửi cầu nối
  PERFORM pg_temp.as_user(sup);
  INSERT INTO work.tasks (id, company_id, title, assignee_id, created_by, agent_id) OVERRIDING SYSTEM VALUE
  VALUES (9802, c, 'Nạp kho tri thức', sup, sup, (SELECT id FROM agent.agents WHERE code = 'ho-so-runner'));
  PERFORM pg_temp.as_agent('ho-so-runner');
  res := agent.mcp_runner_claim();
  ASSERT res->'task'->>'id' = '9802', 'claim 9802';
  ASSERT agent.mcp_runner_report(res->>'card', 'blocked', 'blk-0001', '{"reason":"Cần người nạp kho tri thức, trả lời mã KB"}') = 'ok', 'runner chặn hỏi người';
  ASSERT (SELECT status = 'blocked' AND waiting_on_human FROM work.tasks WHERE id = 9802), 'việc Vướng, chờ người';
  PERFORM pg_temp.as_user(sup);
  PERFORM agent.app_answer(jsonb_build_object('task', 9802, 'body', 'kb:abc12345'));
  ASSERT (SELECT status = 'ready' FROM agent.cards WHERE task_id = 9802), 'thẻ runner sẵn sàng lại';
  ASSERT NOT EXISTS (SELECT 1 FROM agent.outbox WHERE task_id = 9802 AND kind = 'answer'), 'không gửi câu trả lời qua cầu nối Hermes';
  ASSERT (SELECT status = 'in_progress' AND NOT waiting_on_human FROM work.tasks WHERE id = 9802), 'việc Đang làm lại';
  PERFORM pg_temp.as_agent('ho-so-runner');
  res := agent.mcp_runner_claim();
  ASSERT res->'task'->>'id' = '9802' AND res->>'feedback' LIKE '%kb:abc12345%', format('nhận lại kèm câu trả lời: %s', left(res::text, 200));

  -- 6. Hủy việc của runner → thẻ hủy, runner không nhận nữa
  PERFORM pg_temp.as_user(sup);
  INSERT INTO work.tasks (id, company_id, title, assignee_id, created_by, agent_id) OVERRIDING SYSTEM VALUE
  VALUES (9801, c, 'Việc runner sẽ bị hủy', sup, sup, (SELECT id FROM agent.agents WHERE code = 'ho-so-runner'));
  ASSERT (SELECT status = 'ready' FROM agent.cards WHERE task_id = 9801), 'thẻ runner cho việc 9801';
  PERFORM agent.app_task_save(jsonb_build_object('id', 9801, 'status', 'cancelled'));
  ASSERT (SELECT status = 'cancelled' FROM agent.cards WHERE task_id = 9801) AND NOT EXISTS (SELECT 1 FROM agent.outbox WHERE task_id = 9801), 'hủy việc → thẻ hủy, không có lệnh hủy gửi cầu nối';
  PERFORM pg_temp.as_agent('ho-so-runner');
  ASSERT (agent.mcp_runner_claim())->>'idle' = 'true', 'runner không nhận việc đã hủy';
  RAISE NOTICE 'Quy trình dự án ok';
END $$;

SELECT 'test_workflow: tất cả kiểm thử đều đạt' AS ket_qua;
ROLLBACK;
