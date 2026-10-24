-- 0020 · Theo dõi tải tệp lên Drive: ghi bản ghi trước khi tải, đánh dấu sau; job dọn đánh dấu lượt treo và liệt kê tệp mồ côi (không xóa tệp).
-- Nguồn chính: db/62_workflow.sql. Idempotent. down: DROP TABLE agent.drive_uploads; DROP FUNCTION agent.mcp_upload_begin(bigint,text), agent.mcp_upload_finish(bigint,text,text,text), agent.upload_sweep(int).
BEGIN;
-- ---------- Theo dõi tải tệp lên Drive (tránh tệp mồ côi) ----------
-- Luồng: begin (pending) → tải lên → ghi drive_id (uploaded) → đăng ký vào việc → done. Hỏng giữa chừng: failed (chưa có tệp) hoặc orphan (tệp đã lên Drive nhưng chưa gắn vào việc).
-- KHÔNG BAO GIỜ tự xóa tệp trên Drive: agent.upload_sweep chỉ đổi trạng thái và trả danh sách tệp mồ côi để người quyết.
CREATE TABLE IF NOT EXISTS agent.drive_uploads (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  task_id     bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES core.users(id),                 -- danh tính đang gọi (người, hoặc tài khoản agent)
  filename    text NOT NULL,
  state       text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','uploaded','done','failed','orphan')),
  drive_id    text,
  error       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz
);
CREATE INDEX IF NOT EXISTS drive_uploads_state_idx ON agent.drive_uploads (state, created_at);
REVOKE ALL ON agent.drive_uploads FROM PUBLIC;

CREATE OR REPLACE FUNCTION agent.mcp_upload_begin(p_task bigint, p_filename text) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); t work.tasks; new_id bigint;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'Chưa đăng nhập' USING ERRCODE = '42501'; END IF;
  IF (agent.current_agent()).id IS NOT NULL THEN PERFORM agent._agent_for_task(p_task);   -- agent: phải có thẻ đang chạy cho việc này
  ELSIF NOT work.can_view_task(me, p_task) THEN RAISE EXCEPTION 'Không có quyền với T-%', p_task USING ERRCODE = '42501';
  END IF;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  INSERT INTO agent.drive_uploads (company_id, task_id, user_id, filename) VALUES (t.company_id, p_task, me, left(coalesce(p_filename, ''), 200)) RETURNING id INTO new_id;
  RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION agent.mcp_upload_finish(p_id bigint, p_state text, p_drive_id text DEFAULT NULL, p_error text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me uuid := core.current_user_id();
BEGIN
  IF p_state NOT IN ('uploaded','done','failed','orphan') THEN RAISE EXCEPTION 'Trạng thái không hợp lệ'; END IF;
  UPDATE agent.drive_uploads SET state = p_state, drive_id = coalesce(p_drive_id, drive_id), error = left(p_error, 500),
         finished_at = CASE WHEN p_state = 'uploaded' THEN NULL ELSE now() END
   WHERE id = p_id AND user_id = me AND state IN ('pending','uploaded');
  IF NOT FOUND THEN RAISE EXCEPTION 'Không có lượt tải này đang mở' USING ERRCODE = '42501'; END IF;
END $$;

-- Dọn (chạy theo lịch, xem docs/16): lượt `pending` quá p_hours giờ → failed; lượt `uploaded` quá p_hours giờ (tệp đã lên Drive, chưa gắn) → orphan.
-- Trả danh sách tệp mồ côi (drive_id) cho người xem và quyết; KHÔNG xóa tệp. Chỉ quản trị hệ thống.
CREATE OR REPLACE FUNCTION agent.upload_sweep(p_hours int DEFAULT 1) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE n_fail int; n_orph int;
BEGIN
  IF NOT coalesce((SELECT is_system_admin FROM core.users WHERE id = core.current_user_id()), false) THEN
    RAISE EXCEPTION 'Chỉ quản trị hệ thống chạy dọn tải tệp' USING ERRCODE = '42501';
  END IF;
  UPDATE agent.drive_uploads SET state = 'failed', error = coalesce(error, 'treo quá ' || p_hours || ' giờ, chưa tải xong'), finished_at = now()
   WHERE state = 'pending' AND created_at < now() - make_interval(hours => p_hours);
  GET DIAGNOSTICS n_fail = ROW_COUNT;
  UPDATE agent.drive_uploads SET state = 'orphan', error = coalesce(error, 'tệp đã lên Drive nhưng chưa gắn vào việc'), finished_at = now()
   WHERE state = 'uploaded' AND created_at < now() - make_interval(hours => p_hours);
  GET DIAGNOSTICS n_orph = ROW_COUNT;
  RETURN jsonb_build_object('marked_failed', n_fail, 'marked_orphan', n_orph,
    'orphans', coalesce((SELECT jsonb_agg(jsonb_build_object('upload', u.id, 'task', 'T-' || u.task_id, 'file', u.filename, 'drive_id', u.drive_id,
                                  'url', 'https://drive.google.com/file/d/' || u.drive_id || '/view', 'at', u.created_at, 'error', u.error) ORDER BY u.id)
                           FROM agent.drive_uploads u WHERE u.state = 'orphan' AND u.drive_id IS NOT NULL), '[]'));
END $$;

GRANT EXECUTE ON FUNCTION agent.mcp_upload_begin(bigint, text), agent.mcp_upload_finish(bigint, text, text, text) TO mcp_svc;
COMMIT;
