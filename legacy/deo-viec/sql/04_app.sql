-- 04_app.sql — quyền cho app Dẹo Việc (người dùng thật, mỗi người một JWT)
-- Chạy sau 01_schema.sql, 02_functions.sql, 03_roles.sql của PA1.
-- JWT của người: {"role":"human_app","sub":"human:<people.id>","pid":<people.id>,"name":"<tên>","exp":...}
SET search_path = work;

CREATE ROLE human_app NOLOGIN;
GRANT human_app TO authenticator;
GRANT USAGE ON SCHEMA work TO human_app;

-- Đọc: dự án, việc, trao đổi; người chỉ thấy tên + team
GRANT SELECT ON projects, tasks, comments TO human_app;
GRANT SELECT (id, display_name, team) ON people TO human_app;

-- Người đang đăng nhập, lấy từ claim "pid" của JWT (không tin tham số do client gửi)
CREATE FUNCTION app_me() RETURNS people
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = work AS $$
DECLARE p people; v_pid bigint;
BEGIN
  v_pid := nullif(current_setting('request.jwt.claims', true), '')::json->>'pid';
  SELECT * INTO p FROM people WHERE id = v_pid AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tài khoản không còn hoạt động' USING ERRCODE = '42501'; END IF;
  RETURN p;
END $$;

-- Duyệt: dùng lại approve_task (kiểm is_approver, in_review, L3 hai bước)
CREATE FUNCTION app_approve(p_task bigint, p_confirm boolean DEFAULT false) RETURNS tasks
LANGUAGE plpgsql SECURITY DEFINER SET search_path = work AS $$
DECLARE p people := app_me();
BEGIN
  IF p.telegram_id IS NULL THEN RAISE EXCEPTION 'Người duyệt chưa có telegram_id trong bảng people'; END IF;
  RETURN approve_task(p_task, p.telegram_id, p_confirm);
END $$;

CREATE FUNCTION app_reject(p_task bigint, p_reason text) RETURNS tasks
LANGUAGE plpgsql SECURITY DEFINER SET search_path = work AS $$
DECLARE p people := app_me();
BEGIN
  IF coalesce(btrim(p_reason), '') = '' THEN RAISE EXCEPTION 'Cần ghi lý do từ chối'; END IF;
  IF p.telegram_id IS NULL THEN RAISE EXCEPTION 'Người duyệt chưa có telegram_id trong bảng people'; END IF;
  RETURN reject_task(p_task, p.telegram_id, p_reason);
END $$;

-- Trả lời câu hỏi của agent
CREATE FUNCTION app_answer(p_task bigint, p_answer text) RETURNS tasks
LANGUAGE plpgsql SECURITY DEFINER SET search_path = work AS $$
DECLARE p people := app_me(); t tasks;
BEGIN
  UPDATE tasks SET status = 'todo', waiting_on_human = false
   WHERE id = p_task AND waiting_on_human RETURNING * INTO t;
  IF NOT FOUND THEN RAISE EXCEPTION 'T-% không chờ người trả lời', p_task; END IF;
  INSERT INTO comments(task_id, actor, kind, body) VALUES (p_task, 'human:'||p.id, 'TRA-LOI', p_answer);
  RETURN t;
END $$;

-- Ghi chú tự do
CREATE FUNCTION app_comment(p_task bigint, p_body text) RETURNS comments
LANGUAGE plpgsql SECURITY DEFINER SET search_path = work AS $$
DECLARE p people := app_me(); c comments;
BEGIN
  INSERT INTO comments(task_id, actor, kind, body) VALUES (p_task, 'human:'||p.id, 'GHI-CHU', p_body) RETURNING * INTO c;
  RETURN c;
END $$;

REVOKE EXECUTE ON FUNCTION app_me, app_approve, app_reject, app_answer, app_comment FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_me, app_approve, app_reject, app_answer, app_comment TO human_app;

-- Team Valnex chỉ thấy dự án của mình (bật khi có thành viên Valnex dùng app)
-- ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY p_team ON projects FOR SELECT TO human_app
--   USING (team = 'tung' AND (SELECT team FROM people WHERE id = (current_setting('request.jwt.claims',true)::json->>'pid')::bigint) = 'tung'
--          OR team = (SELECT team FROM people WHERE id = (current_setting('request.jwt.claims',true)::json->>'pid')::bigint));
-- (làm tương tự cho tasks, comments qua project_id; các role agent_* cần policy USING (true))
