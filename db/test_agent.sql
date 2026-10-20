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

SELECT 'test_agent: tất cả kiểm thử đều đạt' AS ket_qua;
ROLLBACK;
