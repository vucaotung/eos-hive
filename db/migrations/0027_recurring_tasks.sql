-- 0027 · Việc định kỳ: cột est_minutes, recur_next, run_recurrences (job ngày), app_recurrences/save/set; _task_json trả recurrence_id và est_minutes.
-- Nguồn chính: db/63_features.sql (PHẦN B). Idempotent.
BEGIN;
ALTER TABLE work.tasks ADD COLUMN IF NOT EXISTS est_minutes int;
ALTER TABLE work.tasks DROP CONSTRAINT IF EXISTS tasks_est_minutes_check;
ALTER TABLE work.tasks ADD CONSTRAINT tasks_est_minutes_check CHECK (est_minutes IS NULL OR est_minutes BETWEEN 1 AND 43200);
-- ==== PHẦN B: VIỆC ĐỊNH KỲ ====
-- Bảng work.recurrences có sẵn từ lược đồ gốc. Mỗi lần chạy sinh MỘT việc cho lần xuất hiện gần nhất đến hạn (không dồn đống sau khi hệ thống ngừng); job ngày: scripts/housekeeping.sh.
CREATE OR REPLACE FUNCTION agent._task_json(t work.tasks) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  SELECT jsonb_build_object(
    'id', t.id, 'company_id', t.company_id, 'title', t.title, 'description', t.description, 'status', t.status, 'priority', t.priority,
    'assignee_id', t.assignee_id, 'department_id', t.department_id, 'project_id', t.project_id, 'parent_id', t.parent_id,
    'due_date', t.due_date, 'start_date', t.start_date, 'important', t.important, 'urgent', t.urgent, 'recurrence_id', t.recurrence_id, 'est_minutes', t.est_minutes, 'created_by', t.created_by, 'created_by_agent', t.created_by_agent, 'waiting_on_human', t.waiting_on_human,
    'agent_role', (SELECT g.code FROM agent.agents g WHERE g.id = t.agent_id), 'attempts', t.attempts, 'approval_flow_id', t.approval_flow_id, 'approval_status', t.approval_status,
    'claimed_by', t.claimed_by, 'progress', t.progress, 'result', t.result, 'completed_at', t.completed_at, 'created_at', t.created_at, 'updated_at', t.updated_at,
    'current_step', (SELECT r.current_step FROM core.approval_requests r WHERE r.entity_type = 'task' AND r.entity_id = t.id AND r.state = 'pending' ORDER BY r.id DESC LIMIT 1))
$$;

-- Lần xuất hiện kế tiếp SAU p_from theo quy tắc (hằng ngày / hằng tuần theo thứ ISO / hằng tháng theo ngày, 31 = ngày cuối tháng)
CREATE OR REPLACE FUNCTION work.recur_next(r work.recurrences, p_from date) RETURNS date
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE d date; wk int[] := coalesce(r.weekdays, ARRAY[extract(isodow FROM p_from)::int]); base date := date_trunc('week', r.created_at)::date; m date; last_d int; want int;
BEGIN
  IF r.freq = 'daily' THEN RETURN p_from + r.interval_n; END IF;
  IF r.freq = 'weekly' THEN
    d := p_from + 1;
    FOR i IN 1..(7 * r.interval_n + 7) LOOP
      IF extract(isodow FROM d)::int = ANY (wk) AND ((date_trunc('week', d)::date - base) / 7) % r.interval_n = 0 THEN RETURN d; END IF;
      d := d + 1;
    END LOOP;
    RETURN p_from + 7 * r.interval_n;
  END IF;
  want := coalesce(r.month_day, extract(day FROM p_from)::int);
  m := date_trunc('month', p_from)::date;
  FOR i IN 0..24 LOOP
    last_d := extract(day FROM (m + interval '1 month - 1 day'))::int;
    d := m + (least(want, last_d) - 1);
    IF d > p_from AND (i = 0 OR ((extract(year FROM m) * 12 + extract(month FROM m)) - (extract(year FROM date_trunc('month', p_from)) * 12 + extract(month FROM date_trunc('month', p_from)))) % r.interval_n = 0) THEN RETURN d; END IF;
    m := (m + interval '1 month')::date;
  END LOOP;
  RETURN p_from + 30;
END $$;

-- Xử lý một mẫu: tạo việc cho lần xuất hiện gần nhất ≤ p_today (bỏ ngày lễ/cuối tuần nếu skip_holidays), rồi đặt next_run. Trả id việc đã tạo hoặc NULL.
CREATE OR REPLACE FUNCTION work._run_recurrence(p_id uuid, p_today date) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = work, core, agent, public AS $$
DECLARE r work.recurrences; occ date; nxt date; made bigint; guard int := 0;
BEGIN
  SELECT * INTO r FROM work.recurrences WHERE id = p_id AND active FOR UPDATE;
  IF r.id IS NULL OR r.next_run > p_today THEN RETURN NULL; END IF;
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
  END IF;
  nxt := work.recur_next(r, occ);
  IF r.until_date IS NOT NULL AND nxt > r.until_date THEN UPDATE work.recurrences SET active = false, next_run = nxt WHERE id = r.id;
  ELSE UPDATE work.recurrences SET next_run = nxt WHERE id = r.id; END IF;
  RETURN made;
END $$;

-- Job ngày (chỉ quản trị hệ thống; scripts/housekeeping.sh gọi lúc 03:30): chạy mọi mẫu đến hạn
CREATE OR REPLACE FUNCTION work.run_recurrences(p_today date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = work, core, agent, public AS $$
DECLARE r record; made bigint; n int := 0; today date := coalesce(p_today, (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date);
BEGIN
  IF NOT coalesce((SELECT is_system_admin FROM core.users WHERE id = core.current_user_id()), false) THEN
    RAISE EXCEPTION 'Chỉ quản trị hệ thống chạy việc định kỳ' USING ERRCODE = '42501';
  END IF;
  FOR r IN SELECT id FROM work.recurrences WHERE active AND next_run <= today ORDER BY next_run LOOP
    made := work._run_recurrence(r.id, today); IF made IS NOT NULL THEN n := n + 1; END IF;
  END LOOP;
  RETURN jsonb_build_object('created', n, 'today', today);
END $$;

CREATE OR REPLACE FUNCTION agent.app_recurrences(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); my text;
BEGIN
  my := agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id', r.id, 'title', r.title, 'description', r.description, 'department_id', r.department_id, 'project_id', r.project_id,
            'assignee_id', r.assignee_id, 'priority', r.priority, 'freq', r.freq, 'interval_n', r.interval_n, 'weekdays', r.weekdays, 'month_day', r.month_day, 'due_offset', r.due_offset,
            'skip_holidays', r.skip_holidays, 'next_run', r.next_run, 'until_date', r.until_date, 'active', r.active, 'created_by', r.created_by,
            'can_edit', my IN ('owner','admin') OR r.created_by = me.id,
            'last_task', (SELECT jsonb_build_object('id', t.id, 'status', t.status, 'due_date', t.due_date) FROM work.tasks t WHERE t.recurrence_id = r.id ORDER BY t.id DESC LIMIT 1))
            ORDER BY r.active DESC, r.freq, r.title)
     FROM work.recurrences r WHERE r.company_id = cid AND (my IN ('owner','admin','manager') OR r.created_by = me.id OR r.assignee_id = me.id)), '[]');
END $$;

CREATE OR REPLACE FUNCTION agent.app_recurrence_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); rid uuid := agent._uuid(p, 'id'); r work.recurrences; my text; v_title text; v_freq text; v_int int; v_wd int[];
        v_md int; v_off int; v_start date; v_until date; v_asg uuid; v_dept uuid; v_proj uuid; v_prio work.task_priority; v_desc text; today date := (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date; made bigint;
BEGIN
  IF rid IS NOT NULL THEN
    SELECT * INTO r FROM work.recurrences WHERE id = rid FOR UPDATE;
    IF r.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy việc định kỳ'; END IF;
    cid := r.company_id;
  END IF;
  my := agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  IF rid IS NOT NULL AND NOT (my IN ('owner','admin') OR r.created_by = me.id) THEN RAISE EXCEPTION 'Chỉ người tạo hoặc quản trị sửa được việc định kỳ này' USING ERRCODE = '42501'; END IF;
  v_title := btrim(coalesce(p->>'title', r.title, '')); v_freq := coalesce(p->>'freq', r.freq);
  v_int := coalesce((p->>'interval_n')::int, r.interval_n, 1); v_off := coalesce((p->>'due_offset')::int, r.due_offset, 0);
  v_desc := CASE WHEN p ? 'description' THEN nullif(btrim(coalesce(p->>'description', '')), '') ELSE r.description END;
  v_start := coalesce(nullif(p->>'start', '')::date, r.next_run, today);
  v_until := CASE WHEN p ? 'until_date' THEN nullif(p->>'until_date', '')::date ELSE r.until_date END;
  v_asg := CASE WHEN p ? 'assignee_id' THEN agent._uuid(p, 'assignee_id') ELSE r.assignee_id END;
  v_dept := CASE WHEN p ? 'department_id' THEN agent._uuid(p, 'department_id') ELSE r.department_id END;
  v_proj := CASE WHEN p ? 'project_id' THEN agent._uuid(p, 'project_id') ELSE r.project_id END;
  v_prio := coalesce((p->>'priority')::work.task_priority, r.priority, 'medium');
  IF length(v_title) < 2 OR length(v_title) > 300 THEN RAISE EXCEPTION 'Tên việc từ 2 đến 300 ký tự'; END IF;
  IF v_freq NOT IN ('daily','weekly','monthly') THEN RAISE EXCEPTION 'Tần suất phải là hằng ngày, hằng tuần hoặc hằng tháng'; END IF;
  IF v_int NOT BETWEEN 1 AND 12 THEN RAISE EXCEPTION 'Chu kỳ từ 1 đến 12'; END IF;
  IF v_off NOT BETWEEN 0 AND 60 THEN RAISE EXCEPTION 'Hạn sau ngày tạo từ 0 đến 60 ngày'; END IF;
  v_wd := CASE WHEN v_freq <> 'weekly' THEN NULL WHEN p ? 'weekdays' THEN (SELECT array_agg(DISTINCT x::int ORDER BY x::int) FROM jsonb_array_elements_text(p->'weekdays') x) ELSE coalesce(r.weekdays, ARRAY[extract(isodow FROM v_start)::int]) END;
  IF v_freq = 'weekly' AND (v_wd IS NULL OR cardinality(v_wd) = 0 OR EXISTS (SELECT 1 FROM unnest(v_wd) x WHERE x NOT BETWEEN 1 AND 7)) THEN RAISE EXCEPTION 'Chọn ít nhất một thứ trong tuần (T2 = 1 ... CN = 7)'; END IF;
  v_md := CASE WHEN v_freq <> 'monthly' THEN NULL WHEN p ? 'month_day' THEN (p->>'month_day')::int ELSE coalesce(r.month_day, extract(day FROM v_start)::int) END;
  IF v_freq = 'monthly' AND v_md NOT BETWEEN 1 AND 31 THEN RAISE EXCEPTION 'Ngày trong tháng từ 1 đến 31 (31 = ngày cuối tháng)'; END IF;
  IF v_until IS NOT NULL AND v_until < v_start THEN RAISE EXCEPTION 'Ngày kết thúc phải sau ngày bắt đầu'; END IF;
  IF v_asg IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.memberships WHERE user_id = v_asg AND company_id = cid AND active) THEN RAISE EXCEPTION 'Người phụ trách không thuộc công ty này'; END IF;
  IF v_dept IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.departments WHERE id = v_dept AND company_id = cid) THEN RAISE EXCEPTION 'Phòng ban không thuộc công ty này'; END IF;
  IF v_proj IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.projects WHERE id = v_proj AND company_id = cid) THEN RAISE EXCEPTION 'Dự án không thuộc công ty này'; END IF;
  IF rid IS NULL THEN
    INSERT INTO work.recurrences (company_id, title, description, department_id, project_id, assignee_id, priority, freq, interval_n, weekdays, month_day, due_offset, skip_holidays, next_run, until_date, created_by)
    VALUES (cid, v_title, v_desc, v_dept, v_proj, v_asg, v_prio, v_freq, v_int, v_wd, v_md, v_off, coalesce((p->>'skip_holidays')::boolean, true), v_start, v_until, me.id) RETURNING id INTO rid;
  ELSE
    UPDATE work.recurrences SET title = v_title, description = v_desc, department_id = v_dept, project_id = v_proj, assignee_id = v_asg, priority = v_prio, freq = v_freq, interval_n = v_int,
           weekdays = v_wd, month_day = v_md, due_offset = v_off, skip_holidays = coalesce((p->>'skip_holidays')::boolean, skip_holidays), next_run = v_start, until_date = v_until,
           active = coalesce((p->>'active')::boolean, active) WHERE id = rid;
  END IF;
  PERFORM agent._audit(cid, me.id, 'recurrence_save', 'recurrence', rid::text, 'Lưu việc định kỳ ' || v_title);
  made := work._run_recurrence(rid, today);   -- đến hạn ngay thì tạo việc đầu tiên luôn
  RETURN jsonb_build_object('id', rid, 'created_task', made);
END $$;

CREATE OR REPLACE FUNCTION agent.app_recurrence_set(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); r work.recurrences; my text; today date := (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date;
BEGIN
  SELECT * INTO r FROM work.recurrences WHERE id = agent._uuid(p, 'id') FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy việc định kỳ'; END IF;
  my := agent._need_role(me.id, r.company_id, ARRAY['owner','admin','manager','member']);
  IF NOT (my IN ('owner','admin') OR r.created_by = me.id) THEN RAISE EXCEPTION 'Chỉ người tạo hoặc quản trị đổi được việc định kỳ này' USING ERRCODE = '42501'; END IF;
  IF coalesce((p->>'delete')::boolean, false) THEN
    DELETE FROM work.recurrences WHERE id = r.id;   -- các việc đã sinh giữ nguyên (recurrence_id thành NULL)
    PERFORM agent._audit(r.company_id, me.id, 'recurrence_delete', 'recurrence', r.id::text, 'Xóa việc định kỳ ' || r.title);
    RETURN jsonb_build_object('deleted', true);
  END IF;
  UPDATE work.recurrences SET active = coalesce((p->>'active')::boolean, active),
         next_run = CASE WHEN coalesce((p->>'active')::boolean, active) AND NOT active THEN greatest(next_run, today) ELSE next_run END WHERE id = r.id;   -- bật lại không sinh bù những lần đã lỡ
  PERFORM agent._audit(r.company_id, me.id, 'recurrence_set', 'recurrence', r.id::text, (CASE WHEN coalesce((p->>'active')::boolean, r.active) THEN 'Bật' ELSE 'Tạm dừng' END) || ' việc định kỳ ' || r.title);
  RETURN jsonb_build_object('ok', true);
END $$;
-- ==== HẾT PHẦN B ====
GRANT EXECUTE ON FUNCTION agent.app_recurrences(jsonb), agent.app_recurrence_save(jsonb), agent.app_recurrence_set(jsonb) TO web_svc;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA agent FROM PUBLIC;
COMMIT;
