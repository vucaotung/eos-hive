-- Kiểm thử lớp AI agent: chạy sau 00..60. Dữ liệu thử, tự ROLLBACK.
\set ON_ERROR_STOP 1
BEGIN;
INSERT INTO core.companies (id, slug, name) VALUES ('22222222-2222-2222-2222-222222222222','agt','Công ty Agent');
INSERT INTO core.departments (id, company_id, code, name) VALUES ('dddddddd-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','HC','Hành chính');
INSERT INTO core.users (id, google_sub, email, name, kind) VALUES
 ('bbbbbbbb-0000-0000-0000-000000000001','ga','minh@test.vn','Minh (người làm)','person'),
 ('bbbbbbbb-0000-0000-0000-000000000002','gm','lan@test.vn','Lan (người giao)','person'),
 ('bbbbbbbb-0000-0000-0000-000000000003','go','out@test.vn','Người ngoài','person'),
 ('bbbbbbbb-0000-0000-0000-0000000000a1',NULL,'van-thu@agent','Văn thư AI','agent');
INSERT INTO core.memberships (user_id, company_id, department_id) VALUES
 ('bbbbbbbb-0000-0000-0000-000000000001','22222222-2222-2222-2222-222222222222','dddddddd-0000-0000-0000-000000000001'),
 ('bbbbbbbb-0000-0000-0000-000000000002','22222222-2222-2222-2222-222222222222','dddddddd-0000-0000-0000-000000000001'),
 ('bbbbbbbb-0000-0000-0000-000000000003','22222222-2222-2222-2222-222222222222',NULL);
INSERT INTO agent.agents (id, user_id, code, name, kind, module, hermes_profile, skills, max_level) VALUES
 ('a0000000-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-0000000000a1','van-thu','Văn thư AI','module','doc','eos-van-thu','{nd30-van-thu}',1);

-- 1. Công ty chưa bật agent → giao việc cho agent bị chặn
DO $$ BEGIN
  INSERT INTO work.tasks (company_id, title, agent_id, created_by) VALUES ('22222222-2222-2222-2222-222222222222','Thử','a0000000-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002');
  RAISE EXCEPTION 'phải bị chặn';
EXCEPTION WHEN raise_exception THEN
  IF SQLERRM = 'phải bị chặn' THEN RAISE; END IF;
END $$;

INSERT INTO agent.company_settings (company_id, enabled, kanban_board, default_reviewer) VALUES ('22222222-2222-2222-2222-222222222222', true, 'eos-agt','bbbbbbbb-0000-0000-0000-000000000002');
INSERT INTO agent.company_agents (company_id, agent_id) VALUES ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000001');

-- 2. Giao việc → thẻ chờ + hộp thư đi
INSERT INTO work.tasks (id, company_id, department_id, title, assignee_id, agent_id, agent_role, created_by, due_date)
OVERRIDING SYSTEM VALUE VALUES
 (9001,'22222222-2222-2222-2222-222222222222','dddddddd-0000-0000-0000-000000000001','Trích xuất công văn đến số 12','bbbbbbbb-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001','tra-cuu','bbbbbbbb-0000-0000-0000-000000000002','2026-10-25');

DO $$ DECLARE o agent.outbox; n int; BEGIN
  SELECT count(*) INTO n FROM agent.outbox_pull(10);
  ASSERT n = 1, format('pull %s', n);
  SELECT * INTO o FROM agent.outbox WHERE task_id = 9001;
  ASSERT o.kind = 'dispatch' AND o.payload->>'profile' = 'eos-van-thu' AND o.payload->>'tenant' = 'HC', 'payload dispatch';
  ASSERT o.payload->'skills' = '["nd30-van-thu","tra-cuu"]'::jsonb, format('skills %s', o.payload->'skills');
  ASSERT o.payload->>'idempotency_key' = 'eos-9001-1', 'idempotency';
  SELECT count(*) INTO n FROM agent.outbox_pull(10);
  ASSERT n = 0, 'không lấy trùng';
  PERFORM agent.outbox_ack(o.id, 't_aaaa');
  ASSERT (SELECT status FROM agent.cards WHERE card_id = 't_aaaa') = 'todo', 'thẻ todo';
END $$;

-- 3. Kanban: nhận việc, sự kiện trùng, hỏi lại, người trả lời
DO $$ DECLARE r text; t work.tasks; BEGIN
  r := agent.ingest_event('eos-agt','t_aaaa','claimed','eos-agt:t_aaaa:1');
  ASSERT r = 'ok', r;
  r := agent.ingest_event('eos-agt','t_aaaa','claimed','eos-agt:t_aaaa:1');
  ASSERT r = 'duplicate', 'chống trùng';
  r := agent.ingest_event('eos-agt','t_aaaa','claimed','eos-agt:t_aaaa:reconcile');
  ASSERT r = 'no_change', 'đối soát không làm lại';
  SELECT * INTO t FROM work.tasks WHERE id = 9001;
  ASSERT t.status = 'in_progress' AND t.claimed_by = 'agent:van-thu', 'claimed';
  r := agent.ingest_event('eos-agt','t_aaaa','blocked','eos-agt:t_aaaa:2','{"reason":"Bản scan thiếu trang 2, gửi lại được không?"}');
  SELECT * INTO t FROM work.tasks WHERE id = 9001;
  ASSERT t.status = 'blocked' AND t.waiting_on_human, 'blocked';
  ASSERT EXISTS (SELECT 1 FROM core.notifications WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000001' AND kind = 'agent_question'), 'báo người làm';
END $$;
INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (9001,'bbbbbbbb-0000-0000-0000-000000000001','user:minh','answer','Đã tải lại bản đủ trang vào Drive');
DO $$ BEGIN
  ASSERT (SELECT status FROM work.tasks WHERE id = 9001) = 'in_progress', 'trả lời → làm tiếp';
  ASSERT EXISTS (SELECT 1 FROM agent.outbox WHERE task_id = 9001 AND kind = 'answer' AND payload->>'card_id' = 't_aaaa'), 'answer → outbox';
END $$;

-- 4. Báo xong: thiếu tóm tắt bị từ chối; đủ thì vào Chờ xem, có báo cáo và tệp
DO $$ DECLARE r text; t work.tasks; BEGIN
  r := agent.ingest_event('eos-agt','t_aaaa','completed','eos-agt:t_aaaa:3','{"summary":"xong"}');
  ASSERT r = 'missing_summary', r;
  r := agent.ingest_event('eos-agt','t_aaaa','completed','eos-agt:t_aaaa:4',
     '{"summary":"Đã trích xuất: số 12/UBND-TNMT, hạn trả lời 25/10, đề xuất giao phòng Kỹ thuật.","confidence":"cao",
       "outputs":[{"drive_id":"1AbC","name":"T-9001 - Trich xuat.md","url":"https://drive.google.com/file/d/1AbC"}],
       "checks":{"kiem-tra":"dat"}}');
  ASSERT r = 'ok', r;
  SELECT * INTO t FROM work.tasks WHERE id = 9001;
  ASSERT t.status = 'in_review' AND t.completed_at IS NULL AND t.progress = 100, 'in_review, chưa tính KPI';
  ASSERT (SELECT count(*) FROM agent.reports WHERE task_id = 9001) = 1, 'report';
  ASSERT EXISTS (SELECT 1 FROM core.attachments a JOIN core.files f ON f.id = a.file_id WHERE a.entity_id = '9001' AND f.drive_id = '1AbC' AND f.storage = 'personal'), 'tệp gắn việc';
  ASSERT EXISTS (SELECT 1 FROM core.notifications WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000002' AND kind = 'agent_result'), 'báo người giao';
END $$;

-- 5. Người giao trả lại → thẻ làm lại lượt 2 có lý do; quá 2 lần → việc về người
INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (9001,'bbbbbbbb-0000-0000-0000-000000000002','user:lan','reject','Thiếu tên người ký');
DO $$ DECLARE o agent.outbox; BEGIN
  ASSERT (SELECT status FROM work.tasks WHERE id = 9001) = 'todo', 'về todo';
  SELECT * INTO o FROM agent.outbox WHERE task_id = 9001 AND kind = 'dispatch' ORDER BY id DESC LIMIT 1;
  ASSERT o.payload->>'idempotency_key' = 'eos-9001-2' AND o.payload->>'rework_reason' = 'Thiếu tên người ký'
     AND o.payload->>'parent_card_id' = 't_aaaa', format('rework %s', o.payload);
  ASSERT (SELECT verdict FROM agent.reports WHERE task_id = 9001) = 'rework', 'verdict rework';
  PERFORM agent.outbox_ack(o.id, 't_bbbb');
  PERFORM agent.ingest_event('eos-agt','t_bbbb','completed','eos-agt:t_bbbb:1','{"summary":"Bổ sung người ký: Phó Chủ tịch Nguyễn Văn B."}');
END $$;
INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (9001,'bbbbbbbb-0000-0000-0000-000000000002','user:lan','reject','Vẫn sai chức danh');
DO $$ DECLARE o agent.outbox; BEGIN
  SELECT * INTO o FROM agent.outbox WHERE task_id = 9001 AND kind = 'dispatch' ORDER BY id DESC LIMIT 1;
  PERFORM agent.outbox_ack(o.id, 't_cccc');
  PERFORM agent.ingest_event('eos-agt','t_cccc','completed','eos-agt:t_cccc:1','{"summary":"Sửa chức danh: Chủ tịch UBND xã."}');
END $$;
INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (9001,'bbbbbbbb-0000-0000-0000-000000000002','user:lan','reject','Vẫn chưa đúng');
DO $$ DECLARE t work.tasks; BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = 9001;
  ASSERT t.agent_id IS NULL AND t.status = 'todo' AND t.attempts = 2, format('trả về người: agent %s, attempts %s', t.agent_id, t.attempts);
  ASSERT EXISTS (SELECT 1 FROM core.notifications WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000001' AND kind = 'agent_gave_back'), 'báo người làm';
END $$;

-- 6. Xác nhận L2 được, L3 bị từ chối; chỉ người được hỏi mới quyết
DO $$ DECLARE cid bigint; r text; BEGIN
  cid := agent.request_confirmation('van-thu', 9001, 'work.task.assign_other', 'Giao xử lý cho phòng Kỹ thuật, hạn 25/10?', '{"assignee":"kt"}', 'bbbbbbbb-0000-0000-0000-000000000002');
  BEGIN
    PERFORM agent.request_confirmation('van-thu', 9001, 'doc.number.issue', 'Cấp số', '{}', 'bbbbbbbb-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'L3 phải bị chặn';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}', true);
  BEGIN
    PERFORM agent.decide_confirmation(cid, true);
    RAISE EXCEPTION 'người khác không được quyết';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002"}', true);
  r := agent.decide_confirmation(cid, true, 'Đồng ý');
  ASSERT r = 'approved', r;
END $$;


-- 6b. Người giao chấp nhận kết quả → Xong, tính KPI; người khác không chấp nhận được
INSERT INTO work.tasks (id, company_id, title, assignee_id, agent_id, created_by)
OVERRIDING SYSTEM VALUE VALUES (9003,'22222222-2222-2222-2222-222222222222','Tóm tắt NQ 29','bbbbbbbb-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002');
DO $$ DECLARE o agent.outbox; r text; BEGIN
  SELECT * INTO o FROM agent.outbox WHERE task_id = 9003 AND kind = 'dispatch';
  PERFORM agent.outbox_ack(o.id, 't_dddd');
  PERFORM agent.ingest_event('eos-agt','t_dddd','completed','eos-agt:t_dddd:1','{"summary":"Tóm tắt 5 điểm chính của NQ 29/2026/QH16."}');
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}', true);
  BEGIN PERFORM agent.accept_result(9003); RAISE EXCEPTION 'người làm không tự chấp nhận';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002"}', true);
  r := agent.accept_result(9003);
  ASSERT r = 'done' AND (SELECT completed_at IS NOT NULL FROM work.tasks WHERE id = 9003), r;
  ASSERT (SELECT verdict FROM agent.reports WHERE task_id = 9003) = 'accepted', 'accepted';
END $$;

-- 7. MCP cho agent cá nhân của Minh
INSERT INTO work.tasks (id, company_id, department_id, title, assignee_id, created_by, due_date)
OVERRIDING SYSTEM VALUE VALUES
 (9002,'22222222-2222-2222-2222-222222222222','dddddddd-0000-0000-0000-000000000001','Báo cáo tuần 42','bbbbbbbb-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002','2026-10-23');
DO $$ DECLARE raw text; v record; j jsonb; BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}', true);
  raw := agent.mcp_token_issue('Claude trên laptop', 'claude', '{read,write,drive}', 90);
  ASSERT raw ~ '^eos_[0-9a-f]{48}$', 'dạng mã';
  ASSERT NOT EXISTS (SELECT 1 FROM agent.mcp_tokens WHERE token_hash = raw), 'không lưu mã gốc';
  SELECT * INTO v FROM agent.mcp_token_verify(raw, '10.0.0.5');
  ASSERT v.user_id = 'bbbbbbbb-0000-0000-0000-000000000001' AND v.scopes = '{read,write,drive}', 'verify';
  ASSERT NOT EXISTS (SELECT 1 FROM agent.mcp_token_verify('eos_sai')), 'mã sai';

  PERFORM set_config('request.jwt.claims', format('{"sub":"bbbbbbbb-0000-0000-0000-000000000001","via":"mcp:%s"}', v.prefix), true);
  j := agent.mcp_whoami();
  ASSERT j->'companies'->0->>'department' = 'Hành chính', 'whoami';
  j := agent.mcp_my_tasks('assigned');
  ASSERT jsonb_array_length(j) = 2, format('my tasks %s', j);   -- 9001 (đã về Minh) + 9002; 9003 đã xong
  ASSERT jsonb_array_length(agent.mcp_search('bao cao tuan')) = 1, 'tìm không dấu';
  j := agent.mcp_task(9002);
  ASSERT (j->>'can_submit')::boolean, 'can_submit';
  j := agent.mcp_update_progress(9002, 60, 'Đã có số liệu 3/5 phòng');
  ASSERT (SELECT status FROM work.tasks WHERE id = 9002) = 'in_progress', 'progress → in_progress';
  PERFORM agent.mcp_register_file(9002, '1XyZ', 'T-9002 - Bao cao tuan 42.docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                                  'https://docs.google.com/document/d/1XyZ', 18000, 'Ket qua/2026-10');
  j := agent.mcp_submit(9002, 'Báo cáo tuần 42 đã xong, tệp trong thư mục Kết quả.');
  ASSERT j->>'status' = 'done', 'không có quy trình → xong';
  ASSERT (SELECT completed_at IS NOT NULL FROM work.tasks WHERE id = 9002), 'completed_at cho KPI';
  ASSERT (SELECT actor FROM work.comments WHERE task_id = 9002 AND kind = 'submit') LIKE 'user:bbbbbbbb-0000-0000-0000-000000000001 via mcp:%', 'ghi rõ qua MCP';
  ASSERT (SELECT count(*) FROM agent.drive_writes WHERE task_id = 9002) = 1, 'drive_writes';

  -- người ngoài không đọc được việc của phòng khác
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000003","via":"mcp:x"}', true);
  BEGIN
    PERFORM agent.mcp_task(9002);
    RAISE EXCEPTION 'người ngoài phải bị chặn';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM agent.mcp_submit(9001, 'Nộp hộ người khác xem sao');
    RAISE EXCEPTION 'không được nộp hộ';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;


-- 8. Điều phối chia việc, thứ tự việc con, tổng hợp; worker đọc bằng quyền người phụ trách
INSERT INTO core.users (id, email, name, kind) VALUES
 ('bbbbbbbb-0000-0000-0000-0000000000a2','dieu-phoi@agent','Điều phối AI','agent'),
 ('bbbbbbbb-0000-0000-0000-0000000000a3','kiem-tra@agent','Kiểm tra AI','agent');
INSERT INTO agent.agents (id, user_id, code, name, kind, module, hermes_profile, can_delegate) VALUES
 ('a0000000-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-0000000000a2','dieu-phoi','Điều phối AI','orchestrator','work','ops-admin', true),
 ('a0000000-0000-0000-0000-000000000003','bbbbbbbb-0000-0000-0000-0000000000a3','kiem-tra','Kiểm tra AI','specialist','work','eos-kiem-tra', false);
INSERT INTO agent.company_agents (company_id, agent_id) VALUES
 ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000002'),
 ('22222222-2222-2222-2222-222222222222','a0000000-0000-0000-0000-000000000003');
INSERT INTO work.tasks (id, company_id, department_id, title, assignee_id, agent_id, created_by, due_date)
OVERRIDING SYSTEM VALUE VALUES (9100,'22222222-2222-2222-2222-222222222222','dddddddd-0000-0000-0000-000000000001',
  'Hồ sơ gia hạn tiến độ KDC','bbbbbbbb-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002','bbbbbbbb-0000-0000-0000-000000000002','2026-10-30');
DO $$ DECLARE o agent.outbox; r jsonb; k1 bigint; k2 bigint; res text; BEGIN
  SELECT * INTO o FROM agent.outbox WHERE task_id = 9100;
  PERFORM agent.outbox_ack(o.id, 't_p1');
  PERFORM agent.ingest_event('eos-agt','t_p1','claimed','eos-agt:t_p1:1');
  -- Văn thư AI không được chia việc
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-0000000000a1","agent":"a0000000-0000-0000-0000-000000000001"}', true);
  BEGIN PERFORM agent.delegate(9100, '[{"agent":"kiem-tra","title":"x"}]'); RAISE EXCEPTION 'van-thu không được chia';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- Điều phối chia 2 việc: kiểm tra chạy sau tra cứu
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-0000000000a2","agent":"a0000000-0000-0000-0000-000000000002"}', true);
  r := agent.delegate(9100, '[{"agent":"van-thu","title":"Tra cứu văn bản liên quan","skill":"tra-cuu"},{"agent":"kiem-tra","title":"Kiểm tra bản tổng hợp","after":[0]}]');
  k1 := replace(r->'children'->>0, 'T-', '')::bigint; k2 := replace(r->'children'->>1, 'T-', '')::bigint;
  ASSERT (SELECT assignee_id FROM work.tasks WHERE id = k1) = 'bbbbbbbb-0000-0000-0000-000000000001', 'việc con cùng người phụ trách';
  ASSERT NOT (SELECT kpi_counted FROM work.tasks WHERE id = k1), 'việc con không tính KPI';
  ASSERT EXISTS (SELECT 1 FROM agent.outbox WHERE task_id = k1 AND kind = 'dispatch'), 'việc 1 vào hàng đợi';
  ASSERT NOT EXISTS (SELECT 1 FROM agent.outbox WHERE task_id = k2), 'việc 2 chờ việc 1';
  -- điều phối báo xong lượt chia: việc cha vẫn Đang làm
  res := agent.ingest_event('eos-agt','t_p1','completed','eos-agt:t_p1:2','{"summary":"Chia 2 việc: tra cứu rồi kiểm tra."}');
  ASSERT res = 'waiting_children', res;
  ASSERT (SELECT status FROM work.tasks WHERE id = 9100) = 'in_progress', 'cha vẫn đang làm';
  -- việc 1 xong → Xong luôn (việc con), việc 2 được đưa vào hàng đợi
  SELECT * INTO o FROM agent.outbox WHERE task_id = k1 AND kind = 'dispatch';
  PERFORM agent.outbox_ack(o.id, 't_k1');
  PERFORM agent.ingest_event('eos-agt','t_k1','completed','eos-agt:t_k1:1','{"summary":"Tìm được 3 văn bản: QĐ 12, CV 45, NQ 29."}');
  ASSERT (SELECT status FROM work.tasks WHERE id = k1) = 'done', 'việc con xong luôn';
  SELECT * INTO o FROM agent.outbox WHERE task_id = k2 AND kind = 'dispatch';
  ASSERT o.id IS NOT NULL, 'việc 2 được chạy sau khi việc 1 xong';
  PERFORM agent.outbox_ack(o.id, 't_k2');
  -- Kiểm tra AI đọc việc của mình và việc cha, bằng quyền người phụ trách; Văn thư AI (thẻ đã xong) thì không
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-0000000000a3","agent":"a0000000-0000-0000-0000-000000000003"}', true);
  ASSERT agent.mcp_agent_task(k2)->>'parent' = 'T-9100', 'đọc việc của mình';
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-0000000000a3","agent":"a0000000-0000-0000-0000-000000000003"}', true);
  ASSERT jsonb_array_length(agent.mcp_agent_task(9100)->'children') = 2, 'đọc việc cha thấy việc con';
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-0000000000a1","agent":"a0000000-0000-0000-0000-000000000001"}', true);
  BEGIN PERFORM agent.mcp_agent_task(k2); RAISE EXCEPTION 'van-thu không còn thẻ chạy';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- việc 2 xong → thẻ tổng hợp cho điều phối, kèm danh sách việc con
  PERFORM agent.ingest_event('eos-agt','t_k2','completed','eos-agt:t_k2:1','{"summary":"Bản tổng hợp đạt, thiếu chữ ký phụ lục 2."}');
  SELECT * INTO o FROM agent.outbox WHERE task_id = 9100 AND payload->>'card_kind' = 'synthesis';
  ASSERT o.id IS NOT NULL AND jsonb_array_length(o.payload->'children') = 2 AND o.payload->>'idempotency_key' = 'eos-9100-1-s', format('synthesis %s', o.payload);
  PERFORM agent.outbox_ack(o.id, 't_p2');
  ASSERT (SELECT parent_card_id FROM agent.cards WHERE card_id = 't_p2') = 't_p1', 'thẻ tổng hợp nối thẻ chia việc';
  PERFORM agent.ingest_event('eos-agt','t_p2','completed','eos-agt:t_p2:1','{"summary":"Hồ sơ gia hạn: 3 căn cứ, còn thiếu chữ ký phụ lục 2."}');
  ASSERT (SELECT status FROM work.tasks WHERE id = 9100) = 'in_review', 'bản tổng hợp chờ người xem';
  RAISE NOTICE 'Chia việc ok: T-% → T-%, T-% → tổng hợp', 9100, k1, k2;
END $$;

-- 9. MCP cho người: hôm nay, chờ duyệt, công văn (văn bản mật bị che), KPI của mình
INSERT INTO doc.urgencies VALUES ('22222222-2222-2222-2222-222222222222','normal','Thường',7,1);
INSERT INTO doc.secrecies VALUES ('22222222-2222-2222-2222-222222222222','normal','Thường',false,true), ('22222222-2222-2222-2222-222222222222','confidential','Mật',true,false);
INSERT INTO doc.doc_types (id, company_id, name, is_letter) VALUES ('dddddddd-0000-0000-0000-0000000000c1','22222222-2222-2222-2222-222222222222','Công văn',true);
INSERT INTO doc.incoming (company_id, year, number, sender_name, type_id, summary, deadline, handler_id, secrecy)
VALUES ('22222222-2222-2222-2222-222222222222',2026,1,'UBND xã','dddddddd-0000-0000-0000-0000000000c1','V/v đo đạc ranh giới', current_date - 1,'bbbbbbbb-0000-0000-0000-000000000001','normal'),
       ('22222222-2222-2222-2222-222222222222',2026,2,'Công an tỉnh','dddddddd-0000-0000-0000-0000000000c1','Nội dung mật', current_date + 3,'bbbbbbbb-0000-0000-0000-000000000001','confidential');
DO $$ DECLARE j jsonb; BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000001","via":"mcp:test"}', true);
  j := agent.mcp_my_day();
  ASSERT j ? 'overdue' AND j ? 'agent_questions' AND (j->>'approvals_waiting')::int = 0, format('my_day %s', j);
  j := agent.mcp_incoming('mine');
  ASSERT jsonb_array_length(j) = 2, format('incoming %s', j);
  ASSERT (SELECT count(*) FROM jsonb_array_elements(j) x WHERE x->>'summary' = 'V/v đo đạc ranh giới' AND x->>'status' LIKE 'Quá hạn%') = 1, 'công văn thường';
  ASSERT (SELECT count(*) FROM jsonb_array_elements(j) x WHERE (x->>'secret')::boolean AND NOT x ? 'summary') = 1, 'văn bản mật bị che';
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000003","via":"mcp:test"}', true);
  ASSERT jsonb_array_length(agent.mcp_incoming('all')) = 0, 'người ngoài không thấy công văn';
  RAISE NOTICE 'MCP đọc ok: hôm nay, công văn, che văn bản mật';
END $$;

-- Hủy việc → dừng thẻ Kanban (migration 0001)
INSERT INTO work.tasks (id, company_id, department_id, title, assignee_id, agent_id, created_by)
OVERRIDING SYSTEM VALUE VALUES
 (9101,'22222222-2222-2222-2222-222222222222','dddddddd-0000-0000-0000-000000000001','Hủy khi thẻ đã chạy','bbbbbbbb-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002'),
 (9102,'22222222-2222-2222-2222-222222222222','dddddddd-0000-0000-0000-000000000001','Hủy trước khi tạo thẻ','bbbbbbbb-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002');
DO $$ DECLARE o agent.outbox; BEGIN
  PERFORM agent.outbox_ack((SELECT id FROM agent.outbox WHERE task_id = 9101 AND kind = 'dispatch'), 't_cancel9101');
  UPDATE agent.cards SET status = 'running' WHERE task_id = 9101;
  UPDATE work.tasks SET status = 'cancelled' WHERE id IN (9101, 9102);
  SELECT * INTO o FROM agent.outbox WHERE task_id = 9101 AND kind = 'cancel';
  ASSERT o.id IS NOT NULL AND o.payload->>'card_id' = 't_cancel9101' AND o.payload->>'board' IS NOT NULL, format('cancel outbox %s', o.payload);
  ASSERT (SELECT status FROM agent.cards WHERE task_id = 9101) = 'cancelled', 'thẻ đã chạy → cancelled';
  ASSERT NOT EXISTS (SELECT 1 FROM agent.outbox WHERE task_id = 9102 AND kind = 'cancel'), 'thẻ chưa tạo: không cần cancel';
  ASSERT (SELECT done_at IS NOT NULL FROM agent.outbox WHERE task_id = 9102 AND kind = 'dispatch'), 'dispatch chờ bị hủy';
  UPDATE work.tasks SET status = 'cancelled' WHERE id = 9101;   -- cập nhật lặp không phát thêm
  ASSERT (SELECT count(*) FROM agent.outbox WHERE task_id = 9101 AND kind = 'cancel') = 1, 'cancel chỉ một lần';
  RAISE NOTICE 'Hủy việc ok: thẻ đã chạy → outbox cancel; thẻ chưa tạo → hủy dispatch';
END $$;

-- Chuẩn hóa độ tin cậy do LLM điền (migration 0002)
DO $$ DECLARE r record; got text; BEGIN
  FOR r IN SELECT * FROM (VALUES ('cao','cao'),('High','cao'),('trung bình','trung_binh'),('MEDIUM','trung_binh'),('thấp','thap'),('low','thap'),
                                 ('1','cao'),('0.9','cao'),('0.5','trung_binh'),('0.2','thap'),('85','cao'),('60%','trung_binh'),
                                 ('5',NULL),('khá tốt',NULL),('',NULL)) v(inp, want) LOOP
    got := agent._norm_confidence(r.inp);
    ASSERT got IS NOT DISTINCT FROM r.want, format('_norm_confidence(%L) = %L, cần %L', r.inp, got, r.want);
  END LOOP;
  ASSERT agent._norm_confidence(NULL) IS NULL, 'NULL giữ NULL';
  INSERT INTO agent.reports (company_id, task_id, card_ref, agent_id, summary, confidence)
    SELECT company_id, task_id, id, agent_id, 'Tóm tắt đủ dài để qua ràng buộc độ dài', 'high' FROM agent.cards WHERE task_id = 9001 LIMIT 1;
  ASSERT (SELECT confidence FROM agent.reports WHERE task_id = 9001 ORDER BY id DESC LIMIT 1) = 'cao', 'trigger chuẩn hóa khi chèn báo cáo';
  INSERT INTO agent.reports (company_id, task_id, card_ref, agent_id, summary, confidence)
    SELECT company_id, task_id, id, agent_id, 'Tóm tắt đủ dài để qua ràng buộc độ dài', 'khá tốt' FROM agent.cards WHERE task_id = 9001 LIMIT 1;
  ASSERT (SELECT confidence FROM agent.reports WHERE task_id = 9001 ORDER BY id DESC LIMIT 1) IS NULL, 'giá trị lạ -> NULL, không lỗi';
  RAISE NOTICE 'Chuẩn hóa độ tin cậy ok';
END $$;

-- Nhật ký ghi đúng ai làm (migration 0004)
DO $$ BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000001","via":"agent:van-thu","agent":"a0000000-0000-0000-0000-000000000001"}', true);
  ASSERT agent._mcp_actor() = 'agent:van-thu', format('actor của agent: %s', agent._mcp_actor());
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000001","via":"mcp:abc12345"}', true);
  ASSERT agent._mcp_actor() = 'user:bbbbbbbb-0000-0000-0000-000000000001 via mcp:abc12345', format('actor của người qua MCP: %s', agent._mcp_actor());
  PERFORM set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000001"}', true);
  ASSERT agent._mcp_actor() = 'user:bbbbbbbb-0000-0000-0000-000000000001', 'actor của người trực tiếp';
  RAISE NOTICE 'Actor ok: agent ghi agent, người ghi người';
END $$;

-- ===== Web: đăng nhập, tạo/hủy việc, mã MCP, quản trị, phân quyền hàm (migration 0005) =====
INSERT INTO core.users (id, email, name, kind, active, is_system_admin) VALUES
 ('eeeeeeee-0000-0000-0000-000000000001', 'Web.Test@Demo.vn', 'Web Test', 'person', true, false),
 ('eeeeeeee-0000-0000-0000-000000000002', 'web.admin@demo.vn', 'Web Admin', 'person', true, true),
 ('eeeeeeee-0000-0000-0000-000000000003', 'web.khoa@demo.vn', 'Web Khóa', 'person', false, false),
 ('eeeeeeee-0000-0000-0000-000000000004', 'web.agent@demo.vn', 'Web Agent', 'agent', true, false);
INSERT INTO core.memberships (user_id, company_id, department_id) VALUES
 ('eeeeeeee-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'dddddddd-0000-0000-0000-000000000001'),
 ('eeeeeeee-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'dddddddd-0000-0000-0000-000000000001');

-- ----- Lớp ứng dụng web (db/61_app.sql): đăng nhập + mã mời, vai trò, việc, duyệt nhiều bước, quản trị -----
CREATE FUNCTION pg_temp.as_user(u uuid) RETURNS void LANGUAGE sql AS $f$
  SELECT set_config('request.jwt.claims', CASE WHEN u IS NULL THEN '{"via":"web"}' ELSE json_build_object('sub', u, 'via', 'web')::text END, true) $f$;

INSERT INTO core.departments (id, company_id, code, name) VALUES ('dddddddd-0000-0000-0000-000000000002','22222222-2222-2222-2222-222222222222','KT','Kế toán');
INSERT INTO core.users (id, google_sub, email, name, kind) VALUES
 ('eeeeeeee-0000-0000-0000-000000000011', 'g-mgr', 'truongphong@demo.vn', 'Trưởng phòng HC', 'person'),
 ('eeeeeeee-0000-0000-0000-000000000012', 'g-kt',  'ketoan@demo.vn',      'Kế toán viên', 'person');
INSERT INTO core.memberships (user_id, company_id, department_id, is_dept_head) VALUES
 ('eeeeeeee-0000-0000-0000-000000000011', '22222222-2222-2222-2222-222222222222', 'dddddddd-0000-0000-0000-000000000001', true),
 ('eeeeeeee-0000-0000-0000-000000000012', '22222222-2222-2222-2222-222222222222', 'dddddddd-0000-0000-0000-000000000002', false);
INSERT INTO core.user_roles (company_id, user_id, role_id) VALUES
 ('22222222-2222-2222-2222-222222222222', 'eeeeeeee-0000-0000-0000-000000000001', agent._sys_role('member')),
 ('22222222-2222-2222-2222-222222222222', 'eeeeeeee-0000-0000-0000-000000000002', agent._sys_role('owner')),
 ('22222222-2222-2222-2222-222222222222', 'eeeeeeee-0000-0000-0000-000000000011', agent._sys_role('member')),
 ('22222222-2222-2222-2222-222222222222', 'eeeeeeee-0000-0000-0000-000000000012', agent._sys_role('member'));

DO $$ DECLARE c constant uuid := '22222222-2222-2222-2222-222222222222'; BEGIN
  ASSERT agent._role_of('eeeeeeee-0000-0000-0000-000000000002', c) = 'owner', 'owner';
  ASSERT agent._role_of('eeeeeeee-0000-0000-0000-000000000011', c) = 'manager', 'trưởng phòng';
  ASSERT agent._role_of('eeeeeeee-0000-0000-0000-000000000001', c) = 'member', 'thành viên';
  ASSERT agent._role_of('bbbbbbbb-0000-0000-0000-000000000003', c) = 'member', 'thành viên không có dòng user_roles vẫn là member';
  ASSERT agent._role_of('eeeeeeee-0000-0000-0000-000000000003', c) IS NULL, 'người ngoài/khóa không có vai trò';
  ASSERT (SELECT count(*) FROM core.roles WHERE company_id IS NULL AND builtin) = 3, '3 vai trò mẫu';
  ASSERT core.perm_scope_of('eeeeeeee-0000-0000-0000-000000000002', c, 'work.task.view') = 'company'
     AND core.perm_scope_of('eeeeeeee-0000-0000-0000-000000000001', c, 'work.task.view') = 'department', 'phạm vi quyền xem việc theo vai trò';
  RAISE NOTICE 'Vai trò và quyền mẫu ok';
END $$;

-- Đăng nhập và mã mời
DO $$ DECLARE r jsonb; inv jsonb; c constant uuid := '22222222-2222-2222-2222-222222222222'; u uuid; BEGIN
  r := agent.app_login(jsonb_build_object('email', 'web.test@demo.vn', 'sub', 'sub-1', 'name', 'Web Test', 'avatar', 'https://x/a.png'));
  ASSERT (r->>'ok')::boolean AND r->>'user_id' = 'eeeeeeee-0000-0000-0000-000000000001', format('login ok (không phân biệt hoa thường): %s', r);
  ASSERT (SELECT google_sub FROM core.users WHERE id = 'eeeeeeee-0000-0000-0000-000000000001') = 'sub-1', 'sub gắn lần đầu';
  ASSERT (agent.app_login(jsonb_build_object('email', 'web.test@demo.vn', 'sub', 'sub-1'))->>'ok')::boolean, 'cùng sub: vào được';
  ASSERT agent.app_login(jsonb_build_object('email', 'web.test@demo.vn', 'sub', 'sub-KHAC'))->>'reason' = 'sub_mismatch', 'sub khác bị chặn';
  ASSERT agent.app_login(jsonb_build_object('email', 'nguoi.la@demo.vn', 'sub', 'sub-9'))->>'reason' = 'invite_required', 'email lạ cần mã mời';
  ASSERT agent.app_login(jsonb_build_object('email', 'web.khoa@demo.vn', 'sub', 'sub-3'))->>'reason' = 'not_allowed', 'tài khoản bị khóa không vào được';
  ASSERT agent.app_login(jsonb_build_object('email', 'web.agent@demo.vn', 'sub', 'sub-4'))->>'reason' = 'not_allowed', 'tài khoản agent không đăng nhập web';
  ASSERT agent.app_login(jsonb_build_object('email', '', 'sub', 'sub'))->>'reason' = 'invalid', 'thiếu email';
  ASSERT agent.app_login(jsonb_build_object('email', 'nguoi.la@demo.vn', 'sub', 'sub-9', 'invite', 'KHONGCO1'))->>'reason' = 'invite_invalid', 'mã mời sai';
  ASSERT NOT EXISTS (SELECT 1 FROM core.users WHERE email = 'nguoi.la@demo.vn'), 'mã sai không để lại tài khoản';

  -- chủ sở hữu tạo mã; người mới vào bằng mã
  PERFORM pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000002');
  inv := agent.app_invite_create(jsonb_build_object('company_id', c, 'role', 'member', 'department_id', 'dddddddd-0000-0000-0000-000000000002', 'max_uses', 1, 'days', 7, 'note', 'Nhân viên mới'));
  ASSERT inv->>'code' ~ '^[A-Z0-9]{8}$', format('mã mời: %s', inv);
  r := agent.app_login(jsonb_build_object('email', 'moi@demo.vn', 'sub', 'sub-new', 'name', 'Người Mới', 'invite', lower(inv->>'code')));
  ASSERT (r->>'ok')::boolean, format('vào bằng mã: %s', r);
  u := (r->>'user_id')::uuid;
  ASSERT agent._role_of(u, c) = 'member' AND (SELECT department_id FROM core.memberships WHERE user_id = u AND company_id = c) = 'dddddddd-0000-0000-0000-000000000002', 'vai trò và phòng theo mã';
  ASSERT (SELECT uses FROM core.invites WHERE code = inv->>'code') = 1, 'mã đã dùng 1 lượt';
  ASSERT agent.app_login(jsonb_build_object('email', 'khac@demo.vn', 'sub', 'sub-new2', 'invite', inv->>'code'))->>'reason' = 'invite_invalid', 'mã hết lượt';
  -- mã gắn email
  inv := agent.app_invite_create(jsonb_build_object('company_id', c, 'role', 'member', 'email', 'Rieng@Demo.vn'));
  ASSERT agent.app_login(jsonb_build_object('email', 'sai@demo.vn', 'sub', 'sub-x', 'invite', inv->>'code'))->>'reason' = 'invite_invalid', 'mã gắn email, người khác không dùng được';
  ASSERT (agent.app_login(jsonb_build_object('email', 'rieng@demo.vn', 'sub', 'sub-r', 'invite', inv->>'code'))->>'ok')::boolean, 'đúng email dùng được';
  -- thu hồi, hết hạn
  inv := agent.app_invite_create(jsonb_build_object('company_id', c, 'role', 'member', 'max_uses', 5));
  PERFORM agent.app_invite_revoke(jsonb_build_object('code', inv->>'code'));
  ASSERT agent.app_login(jsonb_build_object('email', 'thuhoi@demo.vn', 'sub', 's1', 'invite', inv->>'code'))->>'reason' = 'invite_invalid', 'mã đã thu hồi';
  inv := agent.app_invite_create(jsonb_build_object('company_id', c, 'role', 'member'));
  UPDATE core.invites SET expires_at = now() - interval '1 minute' WHERE code = inv->>'code';
  ASSERT agent.app_login(jsonb_build_object('email', 'hethan@demo.vn', 'sub', 's2', 'invite', inv->>'code'))->>'reason' = 'invite_invalid', 'mã hết hạn';
  -- quyền tạo mã: trưởng phòng chỉ mời thành viên vào phòng mình; admin không tạo mã owner
  PERFORM pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000011');
  inv := agent.app_invite_create(jsonb_build_object('company_id', c, 'role', 'member', 'department_id', 'dddddddd-0000-0000-0000-000000000001'));
  ASSERT inv ? 'code', 'trưởng phòng mời vào phòng mình';
  BEGIN PERFORM agent.app_invite_create(jsonb_build_object('company_id', c, 'role', 'member', 'department_id', 'dddddddd-0000-0000-0000-000000000002')); ASSERT false, 'phòng khác'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.app_invite_create(jsonb_build_object('company_id', c, 'role', 'admin', 'department_id', 'dddddddd-0000-0000-0000-000000000001')); ASSERT false, 'manager mời admin'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000001');
  BEGIN PERFORM agent.app_invite_create(jsonb_build_object('company_id', c, 'role', 'member')); ASSERT false, 'thành viên không tạo mã'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- chỉ vào thêm công ty: người đã có tài khoản dùng mã công ty khác
  RAISE NOTICE 'Đăng nhập + mã mời ok';
END $$;

-- Việc, quyền xem, nộp việc không quy trình
DO $$ DECLARE c constant uuid := '22222222-2222-2222-2222-222222222222'; r jsonb; tid bigint; t jsonb; me constant uuid := 'eeeeeeee-0000-0000-0000-000000000001'; BEGIN
  PERFORM pg_temp.as_user(me);
  r := agent.app_me('{}');
  ASSERT r->'user'->>'email' = 'Web.Test@Demo.vn' AND r->'memberships'->0->>'role' = 'member' AND r->'memberships'->0->>'department_code' = 'HC', format('app_me %s', r);
  ASSERT jsonb_array_length(r->'agents') >= 1, 'danh sách agent bật cho công ty';
  r := agent.app_task_save(jsonb_build_object('company_id', c, 'title', 'Việc từ web thử', 'description', 'Mô tả', 'agent_role', 'van-thu', 'due_date', current_date + 3, 'priority', 'high'));
  tid := (r->>'id')::bigint;
  ASSERT EXISTS (SELECT 1 FROM agent.outbox WHERE task_id = tid AND kind = 'dispatch'), 'giao agent → dispatch';
  ASSERT (SELECT created_by = assignee_id AND priority = 'high' AND agent_role = 'van-thu' AND department_id = 'dddddddd-0000-0000-0000-000000000001' FROM work.tasks WHERE id = tid), 'người tạo = người phụ trách, mặc định phòng của mình';
  t := agent.app_task(jsonb_build_object('id', tid));
  ASSERT (t->>'can_edit')::boolean AND NOT (t->>'can_review')::boolean AND t->'task'->>'agent_role' = 'van-thu', format('cờ thao tác: %s', left(t::text, 300));
  ASSERT jsonb_typeof(t->'reports') = 'array' AND jsonb_typeof(t->'files') = 'array', 'chi tiết có reports, files';
  BEGIN PERFORM agent.app_task_save(jsonb_build_object('company_id', c, 'title', 'a')); ASSERT false, 'tiêu đề ngắn'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.app_task_save(jsonb_build_object('company_id', c, 'title', 'Ưu tiên sai', 'priority', 'khan')); ASSERT false, 'ưu tiên sai'; EXCEPTION WHEN invalid_text_representation THEN NULL; END;
  BEGIN PERFORM agent.app_task_save(jsonb_build_object('company_id', c, 'title', 'Agent lạ', 'agent_role', 'khong-co')); ASSERT false, 'agent lạ'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.app_task_save(jsonb_build_object('company_id', c, 'title', 'Phòng lạ', 'department_id', gen_random_uuid())); ASSERT false, 'phòng không thuộc công ty'; EXCEPTION WHEN raise_exception THEN NULL; END;
  -- đổi trạng thái và hủy
  PERFORM agent.app_task_save(jsonb_build_object('id', tid, 'status', 'in_progress'));
  PERFORM agent.app_task_save(jsonb_build_object('id', tid, 'status', 'cancelled'));
  ASSERT (SELECT status = 'cancelled' FROM work.tasks WHERE id = tid), 'hủy việc';
  BEGIN PERFORM agent.app_task_save(jsonb_build_object('id', tid, 'status', 'todo')); ASSERT false, 'đã hủy không mở lại'; EXCEPTION WHEN raise_exception THEN NULL; END;
  -- nộp việc không có quy trình → Xong
  r := agent.app_task_save(jsonb_build_object('company_id', c, 'title', 'Việc không quy trình'));
  tid := (r->>'id')::bigint;
  ASSERT agent.app_submit(jsonb_build_object('task', tid, 'note', 'Đã xong'))->>'status' = 'done', 'không quy trình → Xong';
  ASSERT (SELECT status = 'done' AND completed_at IS NOT NULL AND result = 'Đã xong' FROM work.tasks WHERE id = tid), 'completed_at, result';
  BEGIN PERFORM agent.app_submit(jsonb_build_object('task', tid)); ASSERT false, 'nộp lại việc đã xong'; EXCEPTION WHEN raise_exception THEN NULL; END;
  -- bình luận, link
  PERFORM agent.app_comment(jsonb_build_object('task', tid, 'body', 'Ghi chú thử'));
  r := agent.app_link_add(jsonb_build_object('task', tid, 'url', 'https://drive.google.com/file/d/abc', 'title', 'Bản nháp'));
  BEGIN PERFORM agent.app_link_add(jsonb_build_object('task', tid, 'url', 'http://khong-an-toan.vn/x')); ASSERT false, 'link http bị từ chối'; EXCEPTION WHEN raise_exception THEN NULL; END;
  t := agent.app_task(jsonb_build_object('id', tid));
  ASSERT jsonb_array_length(t->'links') = 1 AND jsonb_array_length(t->'comments') >= 2, 'link và trao đổi hiện trong chi tiết';
  PERFORM agent.app_link_remove(jsonb_build_object('link', (r->>'id')::bigint));
  -- quyền xem: người phòng khác (Kế toán) không thấy việc phòng Hành chính; người ngoài công ty bị chặn
  PERFORM pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000012');
  ASSERT NOT EXISTS (SELECT 1 FROM jsonb_array_elements(agent.app_tasks(jsonb_build_object('company_id', c))) x WHERE (x->>'id')::bigint = tid), 'phòng khác không thấy';
  BEGIN PERFORM agent.app_task(jsonb_build_object('id', tid)); ASSERT false, 'chi tiết việc phòng khác'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.app_comment(jsonb_build_object('task', tid, 'body', 'xâm nhập')); ASSERT false, 'bình luận việc phòng khác'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.app_task_save(jsonb_build_object('id', tid, 'title', 'Bị sửa')); ASSERT false, 'sửa việc phòng khác'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000011');
  ASSERT EXISTS (SELECT 1 FROM jsonb_array_elements(agent.app_tasks(jsonb_build_object('company_id', c))) x WHERE (x->>'id')::bigint = tid), 'trưởng phòng thấy việc phòng mình';
  PERFORM pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000003');
  BEGIN PERFORM agent.app_tasks(jsonb_build_object('company_id', '99999999-0000-0000-0000-000000000009')); ASSERT false, 'công ty lạ'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000003');
  BEGIN PERFORM agent.app_me('{}'); ASSERT false, 'tài khoản khóa không dùng được'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user(NULL);
  BEGIN PERFORM agent.app_me('{}'); ASSERT false, 'chưa đăng nhập không dùng được'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RAISE NOTICE 'Việc, link, quyền xem ok';
END $$;

-- Quy trình duyệt 2 bước: trưởng phòng rồi chủ sở hữu; nộp, trả lại, nộp lại
DO $$ DECLARE c constant uuid := '22222222-2222-2222-2222-222222222222'; own constant uuid := 'eeeeeeee-0000-0000-0000-000000000002'; mgr constant uuid := 'eeeeeeee-0000-0000-0000-000000000011';
              me constant uuid := 'eeeeeeee-0000-0000-0000-000000000001'; kt constant uuid := 'eeeeeeee-0000-0000-0000-000000000012'; fid uuid; tid bigint; r jsonb; ap jsonb; BEGIN
  PERFORM pg_temp.as_user(own);
  fid := (agent.app_flow_save(jsonb_build_object('company_id', c, 'name', 'Công văn đi', 'steps', jsonb_build_array(
            jsonb_build_object('name', 'Trưởng phòng duyệt', 'approver_role', 'manager'), jsonb_build_object('name', 'Giám đốc duyệt', 'approver_role', 'owner'))))->>'id')::uuid;
  ASSERT (SELECT count(*) FROM core.approval_steps WHERE flow_id = fid) = 2, '2 bước';
  ASSERT (SELECT approver_kind FROM core.approval_steps WHERE flow_id = fid AND step_no = 1) = 'dept_head', 'manager → dept_head';
  PERFORM pg_temp.as_user(me);
  r := agent.app_task_save(jsonb_build_object('company_id', c, 'title', 'Soạn công văn gia hạn', 'approval_flow_id', fid));
  tid := (r->>'id')::bigint;
  BEGIN PERFORM agent.app_decide(jsonb_build_object('task', tid, 'approve', true)); ASSERT false, 'chưa nộp mà duyệt'; EXCEPTION WHEN raise_exception THEN NULL; END;
  r := agent.app_submit(jsonb_build_object('task', tid, 'note', 'Bản nháp v1'));
  ASSERT r->>'status' = 'in_review', 'nộp → Chờ duyệt';
  ASSERT (SELECT state = 'pending' AND round = 1 AND current_step = 1 AND entity_id = tid FROM core.approval_requests WHERE entity_type = 'task' AND entity_id = tid), 'yêu cầu duyệt vòng 1';
  ASSERT (SELECT count(*) FROM core.approval_decisions WHERE request_id = (SELECT id FROM core.approval_requests WHERE entity_id = tid)) = 2, 'có 2 dòng quyết định';
  BEGIN PERFORM agent.app_submit(jsonb_build_object('task', tid)); ASSERT false, 'nộp hai lần'; EXCEPTION WHEN raise_exception THEN NULL; END;
  -- người làm không tự duyệt; người phòng khác không duyệt; chủ sở hữu chưa tới lượt (bước 1 là trưởng phòng, phòng có trưởng phòng)
  BEGIN PERFORM agent.app_decide(jsonb_build_object('task', tid, 'approve', true)); ASSERT false, 'tự duyệt'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user(kt);
  BEGIN PERFORM agent.app_decide(jsonb_build_object('task', tid, 'approve', true)); ASSERT false, 'người phòng khác duyệt'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user(own);
  BEGIN PERFORM agent.app_decide(jsonb_build_object('task', tid, 'approve', true)); ASSERT false, 'chủ sở hữu duyệt thay bước trưởng phòng'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- hộp duyệt của trưởng phòng
  PERFORM pg_temp.as_user(mgr);
  ap := agent.app_my_approvals('{}');
  ASSERT EXISTS (SELECT 1 FROM jsonb_array_elements(ap->'items') x WHERE (x->>'task_id')::bigint = tid AND x->>'kind' = 'approval' AND (x->>'step_no')::int = 1 AND (x->>'steps')::int = 2
                  AND x->'result'->>'body' = 'Bản nháp v1'), format('hộp duyệt: %s', left(ap::text, 300));
  -- trả lại bắt buộc có lý do; sau đó việc về Đang làm, attempts + 1, nộp lại là vòng 2
  BEGIN PERFORM agent.app_decide(jsonb_build_object('task', tid, 'approve', false)); ASSERT false, 'trả lại không lý do'; EXCEPTION WHEN raise_exception THEN NULL; END;
  r := agent.app_decide(jsonb_build_object('task', tid, 'approve', false, 'note', 'Thiếu căn cứ pháp lý'));
  ASSERT (SELECT status = 'in_progress' AND attempts = 1 FROM work.tasks WHERE id = tid), 'trả lại → Đang làm, attempts 1';
  ASSERT (SELECT state = 'rejected' FROM core.approval_requests WHERE entity_id = tid AND round = 1), 'vòng 1 bị từ chối';
  ASSERT EXISTS (SELECT 1 FROM work.comments WHERE task_id = tid AND kind = 'reject' AND body LIKE '%Thiếu căn cứ%'), 'lý do trả lại ghi vào trao đổi';
  PERFORM pg_temp.as_user(me);
  PERFORM agent.app_submit(jsonb_build_object('task', tid, 'note', 'Bản v2'));
  ASSERT (SELECT round = 2 AND current_step = 1 AND state = 'pending' FROM core.approval_requests WHERE entity_id = tid ORDER BY id DESC LIMIT 1), 'vòng 2';
  PERFORM pg_temp.as_user(mgr);
  r := agent.app_decide(jsonb_build_object('task', tid, 'approve', true));
  ASSERT r->>'status' = 'in_review' AND (r->>'step')::int = 2, format('qua bước 2: %s', r);
  ASSERT (SELECT status = 'in_review' FROM work.tasks WHERE id = tid), 'vẫn Chờ duyệt';
  BEGIN PERFORM agent.app_decide(jsonb_build_object('task', tid, 'approve', true)); ASSERT false, 'trưởng phòng duyệt bước chủ sở hữu'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user(own);
  r := agent.app_decide(jsonb_build_object('task', tid, 'approve', true));
  ASSERT r->>'status' = 'done', 'bước cuối → Xong';
  ASSERT (SELECT status = 'done' AND completed_at IS NOT NULL FROM work.tasks WHERE id = tid), 'completed_at';
  ASSERT (SELECT state = 'approved' AND closed_at IS NOT NULL FROM core.approval_requests WHERE entity_id = tid ORDER BY id DESC LIMIT 1), 'yêu cầu đã duyệt';
  ap := agent.app_task(jsonb_build_object('id', tid));
  ASSERT jsonb_array_length(ap->'approvals') = 2 AND ap->'approvals'->0->>'decision' = 'approved' AND ap->'approvals'->1->>'decision' = 'approved', 'chi tiết hiện đủ 2 bước đã duyệt';
  PERFORM pg_temp.as_user(mgr);
  ASSERT jsonb_array_length(agent.app_my_approvals('{}')->'recent') >= 1, 'mục "đã xử lý" có việc vừa duyệt';
  -- không sửa bước khi đang có việc chờ duyệt
  PERFORM pg_temp.as_user(me);
  r := agent.app_task_save(jsonb_build_object('company_id', c, 'title', 'Việc chờ duyệt khác', 'approval_flow_id', fid));
  PERFORM agent.app_submit(jsonb_build_object('task', (r->>'id')::bigint));
  PERFORM pg_temp.as_user(own);
  BEGIN PERFORM agent.app_flow_save(jsonb_build_object('company_id', c, 'id', fid, 'name', 'Sửa', 'steps', jsonb_build_array(jsonb_build_object('approver_role', 'admin')))); ASSERT false, 'sửa quy trình đang dùng'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.app_flow_save(jsonb_build_object('company_id', c, 'name', 'Quá dài', 'steps', jsonb_build_array(1,2,3,4,5,6,7))); ASSERT false, '7 bước'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.app_flow_save(jsonb_build_object('company_id', c, 'name', 'Thiếu người', 'steps', jsonb_build_array(jsonb_build_object('name', 'x')))); ASSERT false, 'bước thiếu người duyệt'; EXCEPTION WHEN raise_exception THEN NULL; END;
  -- phòng chưa có trưởng phòng: quản trị duyệt thay bước "trưởng phòng"
  r := agent.app_task_save(jsonb_build_object('company_id', c, 'title', 'Việc phòng Kế toán', 'department_id', 'dddddddd-0000-0000-0000-000000000002', 'assignee_id', kt, 'approval_flow_id', fid));
  PERFORM pg_temp.as_user(kt);
  PERFORM agent.app_submit(jsonb_build_object('task', (r->>'id')::bigint));
  PERFORM pg_temp.as_user(own);
  ASSERT agent.app_decide(jsonb_build_object('task', (r->>'id')::bigint, 'approve', true))->>'status' = 'in_review', 'phòng không có trưởng phòng: chủ sở hữu duyệt bước 1';
  RAISE NOTICE 'Duyệt nhiều bước ok';
END $$;

-- Việc của agent có quy trình: người giao chấp nhận → mở yêu cầu duyệt (accept_result trả to_approval); người duyệt trả lại → agent làm lại
DO $$ DECLARE c constant uuid := '22222222-2222-2222-2222-222222222222'; own constant uuid := 'eeeeeeee-0000-0000-0000-000000000002'; me constant uuid := 'eeeeeeee-0000-0000-0000-000000000001';
              fid uuid := (SELECT id FROM core.approval_flows WHERE name = 'Công văn đi'); tid bigint; r jsonb; ap jsonb; BEGIN
  PERFORM pg_temp.as_user(me);
  tid := (agent.app_task_save(jsonb_build_object('company_id', c, 'title', 'Agent soạn công văn', 'agent_role', 'van-thu', 'approval_flow_id', fid))->>'id')::bigint;
  UPDATE work.tasks SET status = 'in_review', progress = 100, result = 'Đã soạn' WHERE id = tid;   -- như thể agent vừa nộp (agent.ingest_event completed)
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (tid, NULL, 'agent:van-thu', 'submit', 'Đã soạn xong công văn');
  ap := agent.app_my_approvals('{}');
  ASSERT EXISTS (SELECT 1 FROM jsonb_array_elements(ap->'items') x WHERE (x->>'task_id')::bigint = tid AND x->>'kind' = 'review'), 'kết quả agent chờ người giao xem';
  ASSERT (agent.app_task(jsonb_build_object('id', tid))->>'can_review')::boolean, 'can_review';
  PERFORM pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000012');
  BEGIN PERFORM agent.app_accept(jsonb_build_object('task', tid)); ASSERT false, 'người khác chấp nhận'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user(me);
  r := agent.app_accept(jsonb_build_object('task', tid, 'note', 'Ổn'));
  ASSERT r->>'status' = 'to_approval', format('accept → to_approval: %s', r);
  ASSERT (SELECT state = 'pending' AND current_step = 1 FROM core.approval_requests WHERE entity_id = tid ORDER BY id DESC LIMIT 1), 'đã mở yêu cầu duyệt';
  ASSERT NOT (agent.app_task(jsonb_build_object('id', tid))->>'can_review')::boolean, 'đang trong quy trình thì không còn "xem kết quả agent"';
  PERFORM pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000011');
  r := agent.app_decide(jsonb_build_object('task', tid, 'approve', false, 'note', 'Sai thể thức văn bản'));
  ASSERT (SELECT status = 'todo' AND attempts = 1 FROM work.tasks WHERE id = tid), format('agent làm lại: %s', (SELECT row_to_json(x) FROM (SELECT status, attempts, agent_id FROM work.tasks WHERE id = tid) x));
  RAISE NOTICE 'Duyệt kết quả agent ok';
END $$;

-- Quản trị: phòng ban, thành viên, dự án, Drive, báo cáo
DO $$ DECLARE c constant uuid := '22222222-2222-2222-2222-222222222222'; own constant uuid := 'eeeeeeee-0000-0000-0000-000000000002'; me constant uuid := 'eeeeeeee-0000-0000-0000-000000000001';
              mgr constant uuid := 'eeeeeeee-0000-0000-0000-000000000011'; r jsonb; d uuid; rp jsonb; BEGIN
  PERFORM pg_temp.as_user(own);
  d := (agent.app_dept_save(jsonb_build_object('company_id', c, 'code', 'ph', 'name', 'Pháp chế'))->>'id')::uuid;
  ASSERT (SELECT code FROM core.departments WHERE id = d) = 'PH', 'mã phòng viết hoa';
  BEGIN PERFORM agent.app_dept_save(jsonb_build_object('company_id', c, 'code', 'PH', 'name', 'Trùng')); ASSERT false, 'trùng mã'; EXCEPTION WHEN raise_exception THEN NULL; END;
  PERFORM agent.app_dept_save(jsonb_build_object('company_id', c, 'id', d, 'code', 'PH', 'name', 'Pháp chế & Tuân thủ', 'active', false));
  ASSERT (SELECT NOT active FROM core.departments WHERE id = d), 'ngừng phòng';
  PERFORM pg_temp.as_user(me);
  BEGIN PERFORM agent.app_dept_save(jsonb_build_object('company_id', c, 'code', 'X', 'name', 'Xxx')); ASSERT false, 'thành viên tạo phòng'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  -- thành viên: không tự đổi mình, không để mất chủ sở hữu cuối cùng, admin không đụng owner
  PERFORM pg_temp.as_user(own);
  BEGIN PERFORM agent.app_member_set(jsonb_build_object('company_id', c, 'user_id', own, 'role', 'member')); ASSERT false, 'tự hạ vai trò'; EXCEPTION WHEN raise_exception THEN NULL; END;
  r := agent.app_member_set(jsonb_build_object('company_id', c, 'user_id', me, 'role', 'admin', 'department_id', 'dddddddd-0000-0000-0000-000000000001', 'title', 'Phó phòng'));
  ASSERT agent._role_of(me, c) = 'admin' AND (SELECT title FROM core.memberships WHERE user_id = me AND company_id = c) = 'Phó phòng', 'nâng lên admin';
  PERFORM pg_temp.as_user(me);
  BEGIN PERFORM agent.app_member_set(jsonb_build_object('company_id', c, 'user_id', own, 'role', 'member')); ASSERT false, 'admin hạ owner'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.app_member_set(jsonb_build_object('company_id', c, 'user_id', mgr, 'role', 'owner')); ASSERT false, 'admin phong owner'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  r := agent.app_member_set(jsonb_build_object('company_id', c, 'user_id', 'eeeeeeee-0000-0000-0000-000000000012', 'role', 'manager', 'department_id', 'dddddddd-0000-0000-0000-000000000002'));
  ASSERT agent._role_of('eeeeeeee-0000-0000-0000-000000000012', c) = 'manager', 'đặt trưởng phòng';
  BEGIN PERFORM agent.app_member_set(jsonb_build_object('company_id', c, 'user_id', mgr, 'role', 'manager')); ASSERT false, 'trưởng phòng thiếu phòng'; EXCEPTION WHEN raise_exception THEN NULL; END;
  PERFORM agent.app_member_set(jsonb_build_object('company_id', c, 'user_id', 'eeeeeeee-0000-0000-0000-000000000012', 'role', 'member', 'department_id', 'dddddddd-0000-0000-0000-000000000002', 'active', false));
  ASSERT agent._role_of('eeeeeeee-0000-0000-0000-000000000012', c) IS NULL, 'khóa thành viên';
  PERFORM pg_temp.as_user('eeeeeeee-0000-0000-0000-000000000012');
  BEGIN PERFORM agent.app_tasks(jsonb_build_object('company_id', c)); ASSERT false, 'thành viên bị khóa không xem được việc'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user(own);
  BEGIN PERFORM agent.app_member_set(jsonb_build_object('company_id', c, 'user_id', own, 'role', 'owner', 'active', false)); ASSERT false, 'tự khóa'; EXCEPTION WHEN raise_exception THEN NULL; END;
  -- dự án
  r := agent.app_project_save(jsonb_build_object('company_id', c, 'slug', 'du-an-a', 'name', 'Dự án A', 'drive_url', 'https://drive.google.com/drive/folders/abcdefghij'));
  ASSERT (SELECT code = 'DUANA' FROM core.projects WHERE id = (r->>'id')::uuid), 'sinh mã dự án';
  BEGIN PERFORM agent.app_project_save(jsonb_build_object('company_id', c, 'slug', 'Sai Slug', 'name', 'x')); ASSERT false, 'slug sai'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.app_project_save(jsonb_build_object('company_id', c, 'slug', 'du-an-a', 'name', 'Trùng')); ASSERT false, 'trùng slug'; EXCEPTION WHEN raise_exception THEN NULL; END;
  PERFORM agent.app_project_save(jsonb_build_object('company_id', c, 'id', r->>'id', 'slug', 'du-an-a', 'name', 'Dự án A', 'active', false));
  ASSERT (SELECT status = 'done' FROM core.projects WHERE id = (r->>'id')::uuid), 'đóng dự án';
  -- cài đặt, thành viên, xóa dự án
  PERFORM agent.app_project_save(jsonb_build_object('id', r->>'id', 'description', 'Mô tả', 'status', 'paused', 'manager_id', 'eeeeeeee-0000-0000-0000-000000000011', 'start_date', '2026-01-01', 'end_date', '2026-12-31'));
  ASSERT (SELECT status = 'paused' AND manager_id = 'eeeeeeee-0000-0000-0000-000000000011' AND description = 'Mô tả' FROM core.projects WHERE id = (r->>'id')::uuid), 'cài đặt dự án';
  ASSERT EXISTS (SELECT 1 FROM core.project_members WHERE project_id = (r->>'id')::uuid AND user_id = 'eeeeeeee-0000-0000-0000-000000000011' AND role = 'manager'), 'người quản lý thành thành viên';
  BEGIN PERFORM agent.app_project_save(jsonb_build_object('id', r->>'id', 'status', 'xong-roi')); ASSERT false, 'trạng thái sai'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.app_project_save(jsonb_build_object('id', r->>'id', 'start_date', '2026-05-01', 'end_date', '2026-01-01')); ASSERT false, 'ngày ngược'; EXCEPTION WHEN raise_exception THEN NULL; END;
  PERFORM agent.app_project_member_set(jsonb_build_object('project_id', r->>'id', 'user_id', me, 'role', 'member'));
  PERFORM agent.app_project_member_set(jsonb_build_object('project_id', r->>'id', 'user_id', me, 'role', 'viewer'));
  ASSERT (SELECT role FROM core.project_members WHERE project_id = (r->>'id')::uuid AND user_id = me) = 'viewer', 'đổi vai trò thành viên dự án';
  BEGIN PERFORM agent.app_project_member_set(jsonb_build_object('project_id', r->>'id', 'user_id', 'bbbbbbbb-0000-0000-0000-000000000003', 'role', 'member')); ASSERT NOT EXISTS (SELECT 1 FROM core.memberships WHERE user_id = 'bbbbbbbb-0000-0000-0000-000000000003' AND company_id = c AND NOT active), 'x'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.app_project_member_remove(jsonb_build_object('project_id', r->>'id', 'user_id', mgr)); ASSERT false, 'không gỡ người quản lý'; EXCEPTION WHEN raise_exception THEN NULL; END;
  PERFORM agent.app_project_member_remove(jsonb_build_object('project_id', r->>'id', 'user_id', me));
  ASSERT NOT EXISTS (SELECT 1 FROM core.project_members WHERE project_id = (r->>'id')::uuid AND user_id = me), 'gỡ thành viên dự án';
  -- người quản lý dự án (thành viên thường) sửa được dự án mình nhưng không đổi phòng, không xóa; người khác không sửa được
  PERFORM pg_temp.as_user(mgr);
  PERFORM agent.app_project_save(jsonb_build_object('id', r->>'id', 'name', 'Dự án A (đổi tên)'));
  BEGIN PERFORM agent.app_project_save(jsonb_build_object('id', r->>'id', 'department_id', 'dddddddd-0000-0000-0000-000000000002')); ASSERT false, 'trưởng phòng đặt dự án sang phòng khác'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  ASSERT (SELECT name = 'Dự án A (đổi tên)' FROM core.projects WHERE id = (r->>'id')::uuid), 'quản lý dự án sửa tên';
  PERFORM agent.app_project_member_set(jsonb_build_object('project_id', r->>'id', 'user_id', me, 'role', 'member'));
  PERFORM pg_temp.as_user('bbbbbbbb-0000-0000-0000-000000000001');
  BEGIN PERFORM agent.app_project_save(jsonb_build_object('id', r->>'id', 'name', 'Chiếm quyền')); ASSERT false, 'thành viên thường sửa dự án'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.app_project_member_remove(jsonb_build_object('project_id', r->>'id', 'user_id', me)); ASSERT false, 'thành viên thường gỡ người'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.app_project_delete(jsonb_build_object('id', r->>'id')); ASSERT false, 'thành viên thường xóa dự án'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.app_project_save(jsonb_build_object('company_id', c, 'slug', 'moi', 'name', 'Tạo thử')); ASSERT false, 'thành viên thường tạo dự án'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM pg_temp.as_user(own);
  -- xóa dự án: việc giữ nguyên, chỉ mất liên kết
  INSERT INTO work.tasks (id, company_id, title, project_id, created_by) OVERRIDING SYSTEM VALUE VALUES (9500, c, 'Việc trong dự án', (r->>'id')::uuid, own);
  ASSERT (agent.app_project_delete(jsonb_build_object('id', r->>'id'))->>'tasks_unlinked')::int = 1, 'xóa dự án';
  ASSERT (SELECT project_id IS NULL FROM work.tasks WHERE id = 9500) AND NOT EXISTS (SELECT 1 FROM core.projects WHERE id = (r->>'id')::uuid), 'việc còn, mất liên kết';
  r := agent.app_project_save(jsonb_build_object('company_id', c, 'slug', 'du-an-b', 'name', 'Dự án B'));
  PERFORM agent.app_project_save(jsonb_build_object('id', r->>'id', 'active', false));
  -- thông tin tổ chức
  r := agent.app_org(jsonb_build_object('company_id', c));
  ASSERT jsonb_array_length(r->'departments') >= 3 AND jsonb_array_length(r->'members') >= 4 AND jsonb_array_length(r->'projects') = 1 AND jsonb_array_length(r->'flows') >= 1, format('app_org: %s', left(r::text, 200));
  ASSERT r->'flows'->0->'steps'->0->>'approver_role' = 'manager' AND r->'flows'->0->'steps'->1->>'approver_role' = 'owner', 'bước quy trình trả về dạng cũ (manager/owner)';
  -- Drive
  PERFORM pg_temp.as_user(me);
  r := agent.app_drive_set(jsonb_build_object('url', 'https://drive.google.com/drive/u/0/folders/1AbCdEfGhIjKlM?usp=sharing'));
  ASSERT (SELECT drive_state = 'pending' AND drive_folder_url = 'https://drive.google.com/drive/folders/1AbCdEfGhIjKlM' FROM core.users WHERE id = me), 'lưu thư mục Drive đã chuẩn hóa';
  BEGIN PERFORM agent.app_drive_set(jsonb_build_object('url', 'https://evil.example/drive/folders/1AbCdEfGhIjKlM')); ASSERT false, 'chỉ nhận drive.google.com'; EXCEPTION WHEN raise_exception THEN NULL; END;
  ASSERT agent.app_drive_names('{}')->>0 = 'DEO - agt - HC - Web Test', format('tên thư mục: %s', agent.app_drive_names('{}'));
  -- báo cáo (admin xem cả công ty)
  rp := agent.app_report(jsonb_build_object('company_id', c));
  ASSERT jsonb_typeof(rp->'depts') = 'array' AND jsonb_typeof(rp->'people') = 'array' AND (SELECT sum((x->>'done_30d')::int) FROM jsonb_array_elements(rp->'depts') x) >= 2, format('báo cáo: %s', left(rp::text, 300));
  RAISE NOTICE 'Quản trị + báo cáo ok';
END $$;

DO $$ DECLARE r jsonb; pre text; BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-000000000001","via":"web"}', true);
  r := agent.web_token_issue('Claude của tôi', 'claude', ARRAY['read', 'write'], 30);
  pre := r->>'prefix';
  ASSERT r->>'token' ~ '^eos_[0-9a-f]{48}$' AND substr(r->>'token', 5, 8) = pre, 'cấp mã';
  ASSERT jsonb_array_length(agent.web_my_tokens()) = 1 AND (agent.web_my_tokens()->0->>'active')::boolean AND NOT agent.web_my_tokens()->0 ? 'token_hash', 'liệt kê mã, không lộ băm';
  BEGIN PERFORM agent.web_token_issue('Quá hạn', 'claude', ARRAY['read'], 365); ASSERT false, '> 90 ngày phải lỗi'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.web_token_issue('Delegate', 'claude', ARRAY['read', 'delegate'], 30); ASSERT false, 'phạm vi delegate phải lỗi'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.web_token_issue('Draft', 'claude', ARRAY['draft'], 30); ASSERT false, 'phạm vi draft phải lỗi'; EXCEPTION WHEN raise_exception THEN NULL; END;
  BEGIN PERFORM agent.web_admin_overview(); ASSERT false, 'người thường không xem quản trị'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM agent.web_admin_tokens(); ASSERT false, 'người thường không xem mọi mã'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-000000000002","via":"web"}', true);
  ASSERT NOT agent.web_token_revoke((SELECT id FROM agent.mcp_tokens WHERE prefix = pre)) IS NOT TRUE, 'quản trị thu hồi được mã của người khác';
  PERFORM set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-000000000001","via":"web"}', true);
  ASSERT NOT (agent.web_my_tokens()->0->>'active')::boolean, 'mã đã thu hồi';
  RAISE NOTICE 'Web mã MCP ok';
END $$;

DO $$ DECLARE r jsonb; BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"eeeeeeee-0000-0000-0000-000000000002","via":"web"}', true);
  r := agent.web_admin_overview();
  ASSERT r ? 'agents' AND r ? 'bridge' AND r ? 'tasks' AND r->'bridge' ? 'outbox_pending' AND r->'mcp' ? 'calls_24h', format('tổng quan quản trị: %s', left(r::text, 200));
  ASSERT jsonb_typeof(agent.web_admin_tokens()) = 'array' AND jsonb_typeof(agent.web_admin_calls(10, true)) = 'array', 'danh sách mã, nhật ký gọi';
  ASSERT NOT (agent.web_admin_tokens()::text LIKE '%token_hash%'), 'không lộ băm mã';
  RAISE NOTICE 'Web quản trị ok';
END $$;

-- Phân quyền hàm: không hàm nào trong schema agent cho PUBLIC chạy; cầu nối chỉ gọi 4 hàm; web_svc không gọi hàm cấp mã agent
DO $$ DECLARE bad text; bridge text; BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO bad FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'agent' AND p.prokind = 'f' AND has_function_privilege('public', p.oid, 'EXECUTE');
  ASSERT bad IS NULL, format('PUBLIC còn chạy được: %s', bad);
  SELECT string_agg(p.proname, ',' ORDER BY p.proname) INTO bridge FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'agent' AND p.prokind = 'f' AND has_function_privilege('agent_bridge', p.oid, 'EXECUTE');
  ASSERT bridge = 'ingest_event,outbox_ack,outbox_pull,request_confirmation', format('cầu nối chỉ gọi 4 hàm, thực tế: %s', bridge);
  ASSERT has_function_privilege('web_svc', 'agent.app_login(jsonb)', 'EXECUTE') AND has_function_privilege('web_svc', 'agent.app_decide(jsonb)', 'EXECUTE'), 'web_svc gọi được app_*';
  ASSERT NOT has_function_privilege('web_svc', 'agent.web_login(text,text,text,text)', 'EXECUTE') AND NOT has_function_privilege('web_svc', 'agent.accept_result(bigint,text)', 'EXECUTE'), 'web_svc không gọi hàm cũ';
  ASSERT NOT has_function_privilege('mcp_svc', 'agent.app_decide(jsonb)', 'EXECUTE') AND NOT has_function_privilege('agent_bridge', 'agent.app_login(jsonb)', 'EXECUTE'), 'MCP và cầu nối không gọi app_*';
  ASSERT NOT has_function_privilege('web_svc', 'agent.mcp_token_issue_agent(text,integer)', 'EXECUTE'), 'web_svc không cấp mã agent';
  ASSERT NOT has_function_privilege('web_svc', 'agent.outbox_pull(integer)', 'EXECUTE'), 'web_svc không kéo hộp thư đi';
  ASSERT NOT has_function_privilege('mcp_svc', 'agent.web_admin_overview()', 'EXECUTE'), 'MCP không gọi hàm quản trị web';
  RAISE NOTICE 'Phân quyền hàm ok';
END $$;

SELECT 'test_agent: tất cả kiểm thử đều đạt' AS ket_qua;
ROLLBACK;
