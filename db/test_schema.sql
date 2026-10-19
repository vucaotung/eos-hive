-- Kiểm thử lược đồ Enterprise OS: chạy sau 00..50. Mọi dữ liệu ở đây là dữ liệu thử.
\set ON_ERROR_STOP 1
BEGIN;
INSERT INTO core.companies (id, slug, name, modules) VALUES ('11111111-1111-1111-1111-111111111111','test','Công ty Thử','{work,doc,hr,crm}');
INSERT INTO core.users (id, google_sub, email, name) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','g1','a@test.vn','Nhân viên A'),
 ('aaaaaaaa-0000-0000-0000-000000000002','g2','b@test.vn','Nhân viên B'),
 ('aaaaaaaa-0000-0000-0000-000000000003','g3','m@test.vn','Trưởng phòng');
INSERT INTO hr.employees (id, company_id, user_id, code, full_name, hire_date, status) VALUES
 ('eeeeeeee-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-000000000001','NV001','Nhân viên A','2025-01-01','official'),
 ('eeeeeeee-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','aaaaaaaa-0000-0000-0000-000000000002','NV002','Nhân viên B','2025-01-01','official');
INSERT INTO hr.kpi_policies (company_id, effective_from) VALUES ('11111111-1111-1111-1111-111111111111','2026-01-01');

-- Việc của A trong tháng 10/2026
INSERT INTO work.tasks (company_id, title, priority, assignee_id, created_by, due_date, status, completed_at, kpi_confirmed_by) VALUES
 ('11111111-1111-1111-1111-111111111111','1 đúng hạn','medium','aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000003','2026-10-10','done','2026-10-09 10:00+07',NULL),
 ('11111111-1111-1111-1111-111111111111','2 trễ 3 ngày','high','aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000003','2026-10-15','done','2026-10-18 10:00+07',NULL),
 ('11111111-1111-1111-1111-111111111111','3 chưa xong','urgent','aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000003','2026-10-20','in_progress',NULL,NULL),
 ('11111111-1111-1111-1111-111111111111','4 đúng hạn thấp','low','aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000003','2026-10-25','done','2026-10-25 16:00+07',NULL),
 ('11111111-1111-1111-1111-111111111111','5 đã hủy','medium','aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000003','2026-10-28','cancelled',NULL,NULL),
 ('11111111-1111-1111-1111-111111111111','6 tự giao chưa xác nhận','medium','aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','2026-10-12','done','2026-10-11 10:00+07',NULL),
 ('11111111-1111-1111-1111-111111111111','7 tự giao đã xác nhận','medium','aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','2026-10-13','done','2026-10-12 10:00+07','aaaaaaaa-0000-0000-0000-000000000003'),
 ('11111111-1111-1111-1111-111111111111','8 trễ 15 ngày','high','aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000003','2026-10-05','done','2026-10-20 10:00+07',NULL),
 ('11111111-1111-1111-1111-111111111111','B1','medium','aaaaaaaa-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000003','2026-10-10','done','2026-10-09 10:00+07',NULL),
 ('11111111-1111-1111-1111-111111111111','B2','medium','aaaaaaaa-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000003','2026-10-11','done','2026-10-10 10:00+07',NULL),
 ('11111111-1111-1111-1111-111111111111','A tháng sau','medium','aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000003','2026-11-03','todo',NULL,NULL);

SELECT hr.compute_kpi('11111111-1111-1111-1111-111111111111','2026-10-01','2026-11-05') AS employees_scored;

DO $$
DECLARE a hr.kpi_scores; b hr.kpi_scores;
BEGIN
  SELECT * INTO a FROM hr.kpi_scores WHERE employee_id = 'eeeeeeee-0000-0000-0000-000000000001';
  SELECT * INTO b FROM hr.kpi_scores WHERE employee_id = 'eeeeeeee-0000-0000-0000-000000000002';
  ASSERT a.tasks_total = 6,          format('A tasks_total %s', a.tasks_total);
  ASSERT a.done_on_time = 3 AND a.done_late = 2 AND a.not_done = 1, 'A outcomes';
  ASSERT a.points_earned = 4.00,     format('A earned %s', a.points_earned);
  ASSERT a.points_possible = 7.50,   format('A possible %s', a.points_possible);
  ASSERT a.score = 53.33,            format('A score %s', a.score);
  ASSERT a.grade = 'D' AND a.bonus_pct = 0, format('A grade %s', a.grade);
  ASSERT b.tasks_total = 2 AND b.score IS NULL AND b.grade IS NULL, 'B chưa đủ dữ liệu';
  RAISE NOTICE 'KPI ok: A % điểm, hạng %; B chưa đủ dữ liệu', a.score, a.grade;
END $$;

-- Trưởng phòng cộng 10 điểm (có ghi chú) rồi tính lại: điểm cuối 63.33 → hạng C, thưởng 40%
UPDATE hr.kpi_scores SET adjustment = 10, adjustment_note = 'Hỗ trợ dự án gấp ngoài kế hoạch'
 WHERE employee_id = 'eeeeeeee-0000-0000-0000-000000000001';
SELECT hr.compute_kpi('11111111-1111-1111-1111-111111111111','2026-10-01','2026-11-05');
DO $$ DECLARE a hr.kpi_scores; BEGIN
  SELECT * INTO a FROM hr.kpi_scores WHERE employee_id = 'eeeeeeee-0000-0000-0000-000000000001';
  ASSERT a.final_score = 63.33 AND a.grade = 'C' AND a.bonus_pct = 40, format('A sau điều chỉnh %s %s', a.final_score, a.grade);
  RAISE NOTICE 'KPI điều chỉnh ok: % → hạng %', a.final_score, a.grade;
END $$;

-- Tính giữa tháng (ngày 16/10): việc chưa tới hạn là "pending", không tính vào mẫu số
SELECT hr.compute_kpi('11111111-1111-1111-1111-111111111111','2026-10-01','2026-10-16');
DO $$ DECLARE a hr.kpi_scores; BEGIN
  SELECT * INTO a FROM hr.kpi_scores WHERE employee_id = 'eeeeeeee-0000-0000-0000-000000000001';
  ASSERT a.pending = 1, format('pending %s', a.pending);   -- việc 3 (hạn 20/10) chưa tới hạn; việc 4 đã xong
  RAISE NOTICE 'KPI giữa tháng ok: % việc chưa tới hạn', a.pending;
END $$;

-- Thuế TNCN với bảng bậc THỬ (không phải số pháp lý): 20 triệu → 2.350.000
DO $$ BEGIN
  ASSERT hr.calc_pit(20000000, '[{"up_to":5000000,"rate":5},{"up_to":10000000,"rate":10},{"up_to":18000000,"rate":15},{"up_to":32000000,"rate":20},{"up_to":null,"rate":35}]') = 2350000, 'PIT';
  ASSERT hr.calc_pit(0, '[{"up_to":null,"rate":5}]') = 0, 'PIT 0';
  RAISE NOTICE 'Thuế lũy tiến ok';
END $$;

-- Ngày làm việc: 02/09 nghỉ lễ, thứ Bảy 05/09 làm bù
INSERT INTO core.holidays VALUES ('11111111-1111-1111-1111-111111111111','2026-09-02','holiday','Quốc khánh',true),
                                 ('11111111-1111-1111-1111-111111111111','2026-09-05','makeup','Làm bù',true);
DO $$ BEGIN
  ASSERT core.add_workdays('11111111-1111-1111-1111-111111111111','2026-09-01',3) = '2026-09-05', 'add_workdays';
  ASSERT core.add_workdays('11111111-1111-1111-1111-111111111111','2026-09-01',0) = '2026-09-01', 'hỏa tốc';
  ASSERT core.count_workdays('11111111-1111-1111-1111-111111111111','2026-09-01','2026-09-30') = 22, 'count_workdays';
  RAISE NOTICE 'Lịch làm việc ok';
END $$;

-- Công văn đến: số trùng bị chặn, tình trạng tính đúng
INSERT INTO doc.urgencies VALUES ('11111111-1111-1111-1111-111111111111','normal','Thường',7,1);
INSERT INTO doc.secrecies VALUES ('11111111-1111-1111-1111-111111111111','normal','Thường',false,true);
INSERT INTO doc.doc_types (id, company_id, name, is_letter) VALUES ('dddddddd-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','Công văn',true);
INSERT INTO doc.incoming (company_id, year, number, received_on, sender_name, type_id, summary, deadline)
VALUES ('11111111-1111-1111-1111-111111111111',2026,1,current_date - 10,'Sở Tài chính','dddddddd-0000-0000-0000-000000000001','V/v báo cáo giá', current_date - 2),
       ('11111111-1111-1111-1111-111111111111',2026,2,current_date,'Thuế','dddddddd-0000-0000-0000-000000000001','V/v hóa đơn', current_date + 10);
DO $$ DECLARE c1 text; c2 text; BEGIN
  SELECT status_code INTO c1 FROM doc.incoming_v WHERE number = 1;
  SELECT status_code INTO c2 FROM doc.incoming_v WHERE number = 2;
  ASSERT c1 = 'overdue', c1;  ASSERT c2 = 'unassigned', c2;
  BEGIN
    INSERT INTO doc.incoming (company_id, year, number, sender_name, type_id, summary)
    VALUES ('11111111-1111-1111-1111-111111111111',2026,2,'X','dddddddd-0000-0000-0000-000000000001','trùng số');
    RAISE EXCEPTION 'không chặn được số trùng';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  RAISE NOTICE 'Công văn ok: tình trạng %, %; chặn trùng số', c1, c2;
END $$;

-- Việc: đã xong thì phải có completed_at
DO $$ BEGIN
  BEGIN
    INSERT INTO work.tasks (company_id, title, status) VALUES ('11111111-1111-1111-1111-111111111111','sai','done');
    RAISE EXCEPTION 'không chặn được done thiếu completed_at';
  EXCEPTION WHEN check_violation THEN NULL; END;
  RAISE NOTICE 'Ràng buộc việc ok';
END $$;

-- Kho dữ liệu chung: KB toàn công ty ai cũng hỏi được; KB dự án chỉ người được cấp
INSERT INTO core.memberships (user_id, company_id) VALUES
 ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111'),
 ('aaaaaaaa-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111');
INSERT INTO core.projects (id, company_id, code, slug, name) VALUES ('bbbbbbbb-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','KDC','kdc-thanh-lap','KDC Thành Lập');
INSERT INTO kb.bases (id, company_id, weknora_kb_id, name, scope, project_id) VALUES
 ('cccccccc-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','kb-chung','Quy trình nội bộ','company',NULL),
 ('cccccccc-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','kb-kdc','KDC Thành Lập','project','bbbbbbbb-0000-0000-0000-000000000001');
INSERT INTO kb.base_access (base_id, user_id) VALUES ('cccccccc-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001');
DO $$ DECLARE na int; nb int; BEGIN
  PERFORM set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001"}', true);
  SELECT count(*) INTO na FROM kb.my_bases_v;
  PERFORM set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000002"}', true);
  SELECT count(*) INTO nb FROM kb.my_bases_v;
  ASSERT na = 2 AND nb = 1, format('KB: A %s, B %s', na, nb);
  RAISE NOTICE 'Kho dữ liệu chung ok: A hỏi được % KB, B hỏi được % KB', na, nb;
END $$;
ROLLBACK;
