-- 0030 · Tạo việc nâng cao: nhãn, phụ thuộc, nhắc hạn, mẫu việc, đính kèm lúc tạo, nhân bản, tạo hàng loạt, gợi ý trùng, việc định kỳ hằng năm/giới hạn số lần
-- Nguồn chính: db/64_creation.sql (chép nguyên văn). Idempotent. Down: không cần (chỉ thêm); gỡ tính năng = bỏ gọi RPC mới, cột/bảng mới để nguyên.
BEGIN;
-- =====================================================================
-- Enterprise OS — 64 Tạo việc nâng cao (nhãn, phụ thuộc, nhắc hạn, mẫu việc, nhân bản, tạo hàng loạt, gợi ý trùng, đính kèm lúc tạo, việc định kỳ có giới hạn)
-- Chạy sau 63. Toàn bộ file là MỘT migration (0030) và áp dụng được nhiều lần.
-- =====================================================================
SET search_path = agent, work, core, public;

-- ==== PHẦN A: NHÃN ====
CREATE TABLE IF NOT EXISTS work.tags (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL CHECK (length(name) BETWEEN 1 AND 30 AND name = btrim(name)),
  created_by  uuid REFERENCES core.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS tags_name_uq ON work.tags (company_id, lower(name));
CREATE TABLE IF NOT EXISTS work.task_tags (
  task_id bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  tag_id  bigint NOT NULL REFERENCES work.tags(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, tag_id)
);
CREATE INDEX IF NOT EXISTS task_tags_tag_idx ON work.task_tags (tag_id);

-- Chuẩn hóa tên nhãn: bỏ '#', gộp khoảng trắng, tối đa 30 ký tự
CREATE OR REPLACE FUNCTION agent._tag_name(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT left(btrim(regexp_replace(regexp_replace(coalesce(p, ''), '^\s*#+', ''), '\s+', ' ', 'g')), 30) $$;

-- Gắn nhãn cho việc (tạo nhãn mới nếu chưa có); thay toàn bộ nhãn của việc. Tối đa 8 nhãn/việc.
CREATE OR REPLACE FUNCTION agent._tags_apply(p_task bigint, p_company uuid, p_names jsonb, p_user uuid) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE nm text; ids bigint[] := '{}'; tid bigint;
BEGIN
  IF p_names IS NULL OR jsonb_typeof(p_names) <> 'array' THEN RETURN 0; END IF;
  FOR nm IN SELECT DISTINCT ON (lower(x)) x FROM (SELECT agent._tag_name(v) AS x FROM jsonb_array_elements_text(p_names) v) q WHERE x <> '' LOOP
    SELECT id INTO tid FROM work.tags WHERE company_id = p_company AND lower(name) = lower(nm);
    IF tid IS NULL THEN INSERT INTO work.tags (company_id, name, created_by) VALUES (p_company, nm, p_user) RETURNING id INTO tid; END IF;
    ids := ids || tid;
  END LOOP;
  IF cardinality(ids) > 8 THEN RAISE EXCEPTION 'Tối đa 8 nhãn cho mỗi việc'; END IF;
  DELETE FROM work.task_tags WHERE task_id = p_task AND NOT (tag_id = ANY (ids));
  INSERT INTO work.task_tags (task_id, tag_id) SELECT p_task, x FROM unnest(ids) x ON CONFLICT DO NOTHING;
  RETURN cardinality(ids);
END $$;

CREATE OR REPLACE FUNCTION agent.app_task_tags_set(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks := agent._task_editor((p->>'task')::bigint); n int;
BEGIN
  n := agent._tags_apply(t.id, t.company_id, p->'tags', me.id);
  PERFORM agent._audit(t.company_id, me.id, 'tags', 'task', t.id::text, 'Đặt nhãn cho T-' || t.id);
  RETURN jsonb_build_object('tags', n);
END $$;

-- Danh sách nhãn của công ty kèm số việc đang dùng
CREATE OR REPLACE FUNCTION agent.app_tags(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id');
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'uses', (SELECT count(*) FROM work.task_tags x WHERE x.tag_id = g.id)) ORDER BY g.name)
                     FROM work.tags g WHERE g.company_id = cid), '[]');
END $$;

-- Nhãn của các việc tôi thấy: {"<id việc>": ["nhãn", ...]} (để lọc và hiển thị ở danh sách)
CREATE OR REPLACE FUNCTION agent.app_task_tags_map(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id');
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  RETURN coalesce((SELECT jsonb_object_agg(q.tid::text, q.names) FROM (
           SELECT x.task_id AS tid, jsonb_agg(g.name ORDER BY g.name) AS names
             FROM work.task_tags x JOIN work.tags g ON g.id = x.tag_id
            WHERE g.company_id = cid AND x.task_id IN (SELECT v.id FROM agent._visible_tasks(me.id, cid, 400, 1500) v)
            GROUP BY x.task_id) q), '{}');
END $$;

-- Việc đang mở giống tiêu đề đang gõ (cảnh báo trùng). Chỉ trả việc người dùng được xem.
CREATE OR REPLACE FUNCTION agent.app_task_similar(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); q text := core.norm(coalesce(p->>'title', '')); ex bigint := nullif(p->>'exclude', '')::bigint;
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  IF length(q) < 4 THEN RETURN '[]'; END IF;
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id', s.id, 'title', s.title, 'status', s.status, 'due_date', s.due_date, 'assignee_id', s.assignee_id, 'score', round(s.sc::numeric, 2)) ORDER BY s.sc DESC)
    FROM (SELECT v.id, v.title, v.status, v.due_date, v.assignee_id, greatest(similarity(core.norm(v.title), q), CASE WHEN position(q IN core.norm(v.title)) > 0 THEN 0.9 ELSE 0 END) AS sc
            FROM agent._visible_tasks(me.id, cid, NULL, 800) v
           WHERE v.status NOT IN ('done','cancelled') AND v.id IS DISTINCT FROM ex AND v.parent_id IS NULL
             AND NOT EXISTS (SELECT 1 FROM agent.ai_requests r WHERE r.task_id = v.id)) s
    WHERE s.sc >= 0.45 LIMIT 5), '[]');
END $$;

-- Gợi ý nhãn: nhãn có tên xuất hiện trong chữ + nhãn hay dùng nhất ở các việc giống
CREATE OR REPLACE FUNCTION agent.app_tag_suggest(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); q text := core.norm(coalesce(p->>'title', '') || ' ' || coalesce(p->>'description', ''));
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  IF length(q) < 3 THEN RETURN '[]'; END IF;
  RETURN coalesce((SELECT jsonb_agg(z.name) FROM (
    SELECT g.name, max(CASE WHEN position(core.norm(g.name) IN q) > 0 THEN 2 ELSE 0 END) + coalesce(sum(w.sc), 0) AS score
      FROM work.tags g
      LEFT JOIN (SELECT x.tag_id, similarity(core.norm(t.title), core.norm(coalesce(p->>'title', ''))) AS sc
                   FROM work.tasks t JOIN work.task_tags x ON x.task_id = t.id
                  WHERE t.company_id = cid AND similarity(core.norm(t.title), core.norm(coalesce(p->>'title', ''))) >= 0.3
                  ORDER BY t.id DESC LIMIT 40) w ON w.tag_id = g.id
     WHERE g.company_id = cid GROUP BY g.id, g.name HAVING max(CASE WHEN position(core.norm(g.name) IN q) > 0 THEN 2 ELSE 0 END) + coalesce(sum(w.sc), 0) >= 0.3
     ORDER BY score DESC, g.name LIMIT 5) z), '[]');
END $$;
-- ==== HẾT PHẦN A ====

-- ==== PHẦN B: PHỤ THUỘC GIỮA CÁC VIỆC ====
-- Việc B "chờ" việc A: B chưa chuyển sang Chờ duyệt/Xong được khi A còn mở (Xong hoặc Hủy là hết chờ). Khi A xong, người làm B được báo.
CREATE TABLE IF NOT EXISTS work.task_deps (
  task_id    bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  depends_on bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, depends_on),
  CHECK (task_id <> depends_on)
);
CREATE INDEX IF NOT EXISTS task_deps_on_idx ON work.task_deps (depends_on);

CREATE OR REPLACE FUNCTION agent._deps_apply(p_task bigint, p_company uuid, p_ids jsonb, p_user uuid) RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE ids bigint[]; d bigint; dt work.tasks;
BEGIN
  IF p_ids IS NULL OR jsonb_typeof(p_ids) <> 'array' THEN RETURN 0; END IF;
  SELECT coalesce(array_agg(DISTINCT replace(x, 'T-', '')::bigint), '{}') INTO ids FROM jsonb_array_elements_text(p_ids) x;
  IF cardinality(ids) > 10 THEN RAISE EXCEPTION 'Một việc chờ tối đa 10 việc khác'; END IF;
  FOREACH d IN ARRAY ids LOOP
    IF d = p_task THEN RAISE EXCEPTION 'Một việc không thể chờ chính nó'; END IF;
    SELECT * INTO dt FROM work.tasks WHERE id = d AND company_id = p_company;
    IF dt.id IS NULL OR NOT agent._can_see(p_user, dt) THEN RAISE EXCEPTION 'Không tìm thấy việc T-% để chờ', d; END IF;
    IF EXISTS (WITH RECURSIVE r(id) AS (SELECT depends_on FROM work.task_deps WHERE task_id = d UNION SELECT x.depends_on FROM work.task_deps x JOIN r ON x.task_id = r.id)
               SELECT 1 FROM r WHERE id = p_task) THEN RAISE EXCEPTION 'T-% đang chờ T-% (trực tiếp hoặc gián tiếp): không tạo vòng chờ nhau', d, p_task; END IF;
  END LOOP;
  DELETE FROM work.task_deps WHERE task_id = p_task AND NOT (depends_on = ANY (ids));
  INSERT INTO work.task_deps (task_id, depends_on) SELECT p_task, x FROM unnest(ids) x ON CONFLICT DO NOTHING;
  RETURN cardinality(ids);
END $$;

CREATE OR REPLACE FUNCTION agent.app_task_deps_set(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks := agent._task_editor((p->>'task')::bigint); n int;
BEGIN
  n := agent._deps_apply(t.id, t.company_id, p->'depends_on', me.id);
  PERFORM agent._audit(t.company_id, me.id, 'deps', 'task', t.id::text, 'Đặt việc phải chờ cho T-' || t.id);
  RETURN jsonb_build_object('depends_on', n);
END $$;

CREATE OR REPLACE FUNCTION work.deps_guard_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = work, core, public AS $$
DECLARE o bigint;
BEGIN
  IF NEW.status IN ('in_review','done') AND NEW.status IS DISTINCT FROM OLD.status THEN
    SELECT d.depends_on INTO o FROM work.task_deps d JOIN work.tasks a ON a.id = d.depends_on WHERE d.task_id = NEW.id AND a.status NOT IN ('done','cancelled') ORDER BY d.depends_on LIMIT 1;
    IF o IS NOT NULL THEN RAISE EXCEPTION 'T-% đang chờ T-% chưa xong, chưa chuyển sang % được', NEW.id, o, CASE NEW.status WHEN 'done' THEN 'Xong' ELSE 'Chờ duyệt' END USING ERRCODE = 'check_violation'; END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS tasks_deps_guard ON work.tasks;
CREATE TRIGGER tasks_deps_guard BEFORE UPDATE OF status ON work.tasks FOR EACH ROW EXECUTE FUNCTION work.deps_guard_trg();

CREATE OR REPLACE FUNCTION work.deps_unblock_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE b record; w record;
BEGIN
  IF NEW.status IN ('done','cancelled') AND NEW.status IS DISTINCT FROM OLD.status THEN
    SELECT * INTO w FROM agent._who();
    FOR b IN SELECT t.id, t.company_id, t.title, t.assignee_id FROM work.task_deps d JOIN work.tasks t ON t.id = d.task_id
              WHERE d.depends_on = NEW.id AND t.status NOT IN ('done','cancelled')
                AND NOT EXISTS (SELECT 1 FROM work.task_deps d2 JOIN work.tasks a ON a.id = d2.depends_on WHERE d2.task_id = t.id AND a.status NOT IN ('done','cancelled')) LOOP
      IF b.assignee_id IS NOT NULL THEN PERFORM agent._notify_from(b.company_id, b.assignee_id, 'unblocked', 'Hết chờ: ' || b.title, 'T-' || NEW.id || ' đã ' || CASE NEW.status WHEN 'done' THEN 'xong' ELSE 'hủy' END || ', bạn làm tiếp T-' || b.id || ' được rồi', b.id, w.actor, w.ai); END IF;
    END LOOP;
  END IF;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS tasks_deps_unblock ON work.tasks;
CREATE TRIGGER tasks_deps_unblock AFTER UPDATE OF status ON work.tasks FOR EACH ROW EXECUTE FUNCTION work.deps_unblock_trg();
-- ==== HẾT PHẦN B ====

-- ==== PHẦN C: NHẮC HẠN RIÊNG TỪNG VIỆC ====
ALTER TABLE work.tasks ADD COLUMN IF NOT EXISTS remind_at timestamptz;
ALTER TABLE work.tasks ADD COLUMN IF NOT EXISTS reminded_at timestamptz;
CREATE INDEX IF NOT EXISTS tasks_remind_idx ON work.tasks (remind_at) WHERE remind_at IS NOT NULL AND reminded_at IS NULL;

CREATE OR REPLACE FUNCTION agent._remind_apply(p_task bigint, p_at text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE v timestamptz := nullif(btrim(coalesce(p_at, '')), '')::timestamptz;
BEGIN
  IF v IS NOT NULL AND (v < now() - interval '2 minutes' OR v > now() + interval '400 days') THEN RAISE EXCEPTION 'Giờ nhắc phải ở tương lai và trong vòng 400 ngày tới'; END IF;
  UPDATE work.tasks SET remind_at = v, reminded_at = NULL WHERE id = p_task;
END $$;

CREATE OR REPLACE FUNCTION agent.app_task_remind(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks := agent._task_editor((p->>'task')::bigint);
BEGIN
  PERFORM agent._remind_apply(t.id, p->>'remind_at');
  PERFORM agent._audit(t.company_id, me.id, 'remind', 'task', t.id::text, CASE WHEN nullif(p->>'remind_at', '') IS NULL THEN 'Bỏ nhắc việc T-' || t.id ELSE 'Đặt nhắc việc T-' || t.id END);
  RETURN jsonb_build_object('remind_at', nullif(p->>'remind_at', ''));
END $$;

-- Job 10 phút/lần (scripts/housekeeping.sh --reminders): báo người phụ trách (hoặc người tạo nếu chưa giao) khi đến giờ nhắc của việc còn mở
CREATE OR REPLACE FUNCTION work.run_reminders() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE r record; n int := 0;
BEGIN
  IF NOT coalesce((SELECT is_system_admin FROM core.users WHERE id = agent._uid()), false) THEN
    RAISE EXCEPTION 'Chỉ quản trị hệ thống chạy nhắc việc' USING ERRCODE = '42501';
  END IF;
  FOR r IN SELECT id, company_id, title, due_date, coalesce(assignee_id, created_by) AS target FROM work.tasks
            WHERE remind_at IS NOT NULL AND reminded_at IS NULL AND remind_at <= now() ORDER BY remind_at LIMIT 500 FOR UPDATE SKIP LOCKED LOOP
    UPDATE work.tasks SET reminded_at = now() WHERE id = r.id;
    IF r.target IS NOT NULL AND (SELECT status FROM work.tasks WHERE id = r.id) NOT IN ('done','cancelled') THEN
      PERFORM agent._notify_from(r.company_id, r.target, 'reminder', 'Nhắc việc: ' || r.title, CASE WHEN r.due_date IS NOT NULL THEN 'Hạn ' || to_char(r.due_date, 'DD/MM/YYYY') END, r.id, 'system', false);
      n := n + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('sent', n);
END $$;
-- ==== HẾT PHẦN C ====

-- ==== PHẦN D: ĐÍNH KÈM LÚC TẠO, MẪU VIỆC, TẠO NÂNG CAO, NHÂN BẢN, HÀNG LOẠT ====
-- Đính kèm bằng liên kết Google Drive (máy chủ web không giữ thông tin đăng nhập Drive nên chưa tải tệp lên trực tiếp được)
CREATE OR REPLACE FUNCTION agent._attach_link(p_task bigint, p_company uuid, p_url text, p_name text, p_user uuid) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE u text := btrim(coalesce(p_url, '')); did text; fid bigint; nm text;
BEGIN
  IF u !~ '^https://(drive|docs)\.google\.com/' THEN RAISE EXCEPTION 'Chỉ nhận liên kết Google Drive/Docs (https://drive.google.com/… hoặc https://docs.google.com/…)'; END IF;
  did := coalesce((regexp_match(u, '/d/([A-Za-z0-9_-]{10,})'))[1], (regexp_match(u, '[?&]id=([A-Za-z0-9_-]{10,})'))[1], (regexp_match(u, '/folders/([A-Za-z0-9_-]{10,})'))[1]);
  IF did IS NULL THEN RAISE EXCEPTION 'Không nhận ra mã tệp trong liên kết Drive'; END IF;
  nm := left(coalesce(nullif(btrim(p_name), ''), 'Tệp Drive ' || left(did, 8)), 200);
  INSERT INTO core.files (company_id, drive_id, name, web_url, storage) VALUES (p_company, did, nm, u, 'company')
    ON CONFLICT (company_id, drive_id) DO UPDATE SET synced_at = now() RETURNING id INTO fid;
  INSERT INTO core.attachments (company_id, file_id, entity_type, entity_id, role, added_by, actor)
    VALUES (p_company, fid, 'task', p_task::text, 'attachment', p_user, 'user:' || p_user) ON CONFLICT DO NOTHING;
  RETURN fid;
END $$;

CREATE OR REPLACE FUNCTION agent.app_task_attach_link(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks := agent._task_editor((p->>'task')::bigint); fid bigint;
BEGIN
  IF (SELECT count(*) FROM core.attachments WHERE entity_type = 'task' AND entity_id = t.id::text) >= 30 THEN RAISE EXCEPTION 'Mỗi việc đính kèm tối đa 30 tệp'; END IF;
  fid := agent._attach_link(t.id, t.company_id, p->>'url', p->>'name', me.id);
  PERFORM agent._audit(t.company_id, me.id, 'attach', 'task', t.id::text, 'Đính kèm tệp Drive vào T-' || t.id);
  RETURN jsonb_build_object('file_id', fid);
END $$;

-- Chi tiết mở rộng của một việc: nhãn, việc phải chờ, việc đang chờ nó, giờ nhắc
CREATE OR REPLACE FUNCTION agent.app_task_extras(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = (p->>'id')::bigint;
  IF t.id IS NULL OR NOT agent._can_see(me.id, t) THEN RAISE EXCEPTION 'Không tìm thấy việc hoặc bạn không có quyền xem' USING ERRCODE = '42501'; END IF;
  RETURN jsonb_build_object(
    'tags', coalesce((SELECT jsonb_agg(g.name ORDER BY g.name) FROM work.task_tags x JOIN work.tags g ON g.id = x.tag_id WHERE x.task_id = t.id), '[]'),
    'depends_on', coalesce((SELECT jsonb_agg(jsonb_build_object('id', a.id, 'title', a.title, 'status', a.status) ORDER BY a.id) FROM work.task_deps d JOIN work.tasks a ON a.id = d.depends_on WHERE d.task_id = t.id AND agent._can_see(me.id, a)), '[]'),
    'blocked_by', coalesce((SELECT jsonb_agg(a.id ORDER BY a.id) FROM work.task_deps d JOIN work.tasks a ON a.id = d.depends_on WHERE d.task_id = t.id AND a.status NOT IN ('done','cancelled')), '[]'),
    'dependents', coalesce((SELECT jsonb_agg(jsonb_build_object('id', b.id, 'title', b.title, 'status', b.status) ORDER BY b.id) FROM work.task_deps d JOIN work.tasks b ON b.id = d.task_id WHERE d.depends_on = t.id AND agent._can_see(me.id, b)), '[]'),
    'remind_at', t.remind_at, 'reminded_at', t.reminded_at);
END $$;

-- Mẫu việc: khung dùng lại để tạo việc (tiêu đề, mô tả, ưu tiên, cờ, ước tính, hạn sau n ngày, nhãn, checklist, việc con)
CREATE TABLE IF NOT EXISTS work.task_templates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  body        jsonb NOT NULL CHECK (jsonb_typeof(body) = 'object' AND pg_column_size(body) < 16000),
  uses        int NOT NULL DEFAULT 0,
  created_by  uuid REFERENCES core.users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, name)
);

-- Chỉ giữ các trường hợp lệ của mẫu (bỏ mọi trường lạ), kiểm giới hạn
CREATE OR REPLACE FUNCTION agent._template_body(p jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE b jsonb := '{}'; v text;
BEGIN
  IF jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'Nội dung mẫu không hợp lệ'; END IF;
  v := btrim(coalesce(p->>'title', ''));
  IF length(v) < 2 OR length(v) > 300 THEN RAISE EXCEPTION 'Tiêu đề mẫu từ 2 đến 300 ký tự'; END IF;
  b := jsonb_build_object('title', v);
  IF length(coalesce(p->>'description', '')) > 8000 THEN RAISE EXCEPTION 'Mô tả tối đa 8000 ký tự'; END IF;
  IF coalesce(p->>'description', '') <> '' THEN b := b || jsonb_build_object('description', p->>'description'); END IF;
  IF coalesce(p->>'priority', '') <> '' THEN IF (p->>'priority') NOT IN ('low','medium','high','urgent') THEN RAISE EXCEPTION 'Ưu tiên không hợp lệ'; END IF; b := b || jsonb_build_object('priority', p->>'priority'); END IF;
  IF coalesce((p->>'important')::boolean, false) THEN b := b || '{"important": true}'; END IF;
  IF coalesce((p->>'urgent')::boolean, false) THEN b := b || '{"urgent": true}'; END IF;
  IF coalesce(p->>'est_minutes', '') <> '' THEN IF (p->>'est_minutes')::int NOT BETWEEN 1 AND 43200 THEN RAISE EXCEPTION 'Thời lượng từ 1 phút đến 30 ngày'; END IF; b := b || jsonb_build_object('est_minutes', (p->>'est_minutes')::int); END IF;
  IF coalesce(p->>'due_in_days', '') <> '' THEN IF (p->>'due_in_days')::int NOT BETWEEN 0 AND 365 THEN RAISE EXCEPTION 'Hạn sau 0 đến 365 ngày'; END IF; b := b || jsonb_build_object('due_in_days', (p->>'due_in_days')::int); END IF;
  IF jsonb_typeof(p->'tags') = 'array' THEN b := b || jsonb_build_object('tags', (SELECT coalesce(jsonb_agg(x), '[]') FROM (SELECT agent._tag_name(v2) x FROM jsonb_array_elements_text(p->'tags') v2 LIMIT 8) q WHERE x <> '')); END IF;
  IF jsonb_typeof(p->'checklist') = 'array' THEN
    IF jsonb_array_length(p->'checklist') > 50 THEN RAISE EXCEPTION 'Checklist tối đa 50 mục'; END IF;
    b := b || jsonb_build_object('checklist', (SELECT coalesce(jsonb_agg(left(btrim(v2), 300)), '[]') FROM jsonb_array_elements_text(p->'checklist') v2 WHERE btrim(v2) <> ''));
  END IF;
  IF jsonb_typeof(p->'subtasks') = 'array' THEN
    IF jsonb_array_length(p->'subtasks') > 20 THEN RAISE EXCEPTION 'Việc con tối đa 20'; END IF;
    b := b || jsonb_build_object('subtasks', (SELECT coalesce(jsonb_agg(left(btrim(v2), 300)), '[]') FROM jsonb_array_elements_text(p->'subtasks') v2 WHERE length(btrim(v2)) >= 2));
  END IF;
  RETURN b;
END $$;

CREATE OR REPLACE FUNCTION agent.app_task_templates(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id');
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id', x.id, 'name', x.name, 'body', x.body, 'uses', x.uses) ORDER BY x.uses DESC, x.name) FROM work.task_templates x WHERE x.company_id = cid), '[]');
END $$;

CREATE OR REPLACE FUNCTION agent.app_task_template_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); tid uuid := agent._uuid(p, 'id'); nm text := btrim(coalesce(p->>'name', '')); b jsonb; x work.task_templates;
BEGIN
  IF tid IS NOT NULL THEN SELECT * INTO x FROM work.task_templates WHERE id = tid; IF x.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy mẫu'; END IF; cid := x.company_id; END IF;
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  IF tid IS NOT NULL AND x.created_by IS DISTINCT FROM me.id AND agent._role_of(me.id, cid) NOT IN ('owner','admin','manager') THEN RAISE EXCEPTION 'Chỉ người tạo hoặc quản lý sửa được mẫu này' USING ERRCODE = '42501'; END IF;
  IF length(nm) < 2 OR length(nm) > 120 THEN RAISE EXCEPTION 'Tên mẫu từ 2 đến 120 ký tự'; END IF;
  b := agent._template_body(p->'body');
  IF tid IS NULL THEN
    IF (SELECT count(*) FROM work.task_templates WHERE company_id = cid) >= 100 THEN RAISE EXCEPTION 'Mỗi công ty tối đa 100 mẫu việc'; END IF;
    INSERT INTO work.task_templates (company_id, name, body, created_by) VALUES (cid, nm, b, me.id) RETURNING id INTO tid;
  ELSE UPDATE work.task_templates SET name = nm, body = b WHERE id = tid; END IF;
  RETURN jsonb_build_object('id', tid);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'Đã có mẫu tên "%"', nm;
END $$;

CREATE OR REPLACE FUNCTION agent.app_task_template_delete(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); x work.task_templates;
BEGIN
  SELECT * INTO x FROM work.task_templates WHERE id = agent._uuid(p, 'id');
  IF x.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy mẫu'; END IF;
  PERFORM agent._need_role(me.id, x.company_id, ARRAY['owner','admin','manager','member']);
  IF x.created_by IS DISTINCT FROM me.id AND agent._role_of(me.id, x.company_id) NOT IN ('owner','admin','manager') THEN RAISE EXCEPTION 'Chỉ người tạo hoặc quản lý xóa được mẫu này' USING ERRCODE = '42501'; END IF;
  DELETE FROM work.task_templates WHERE id = x.id;
  RETURN jsonb_build_object('deleted', true);
END $$;

-- Tạo việc "đầy đủ" trong MỘT giao dịch: app_task_save + nhãn, việc phải chờ, giờ nhắc, đính kèm Drive, checklist, việc con.
-- Trường của việc như app_task_save; thêm: tags[], depends_on[], remind_at, attach[{url,name}], checklist[], subtasks[{title,due_date}|chuỗi], template_id (tăng số lần dùng)
CREATE OR REPLACE FUNCTION agent.app_task_create_ex(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); q jsonb; tid bigint; a jsonb; s jsonb; sid bigint; sq jsonb; n int := 0; items text[]; kids bigint[] := '{}';
BEGIN
  IF (p->>'id') IS NOT NULL THEN RAISE EXCEPTION 'app_task_create_ex chỉ để tạo việc mới'; END IF;
  tid := (agent.app_task_save(p)->>'id')::bigint;          -- kiểm quyền và dữ liệu như khi tự giao
  IF p ? 'tags' THEN PERFORM agent._tags_apply(tid, cid, p->'tags', me.id); END IF;
  IF p ? 'depends_on' THEN PERFORM agent._deps_apply(tid, cid, p->'depends_on', me.id); END IF;
  IF coalesce(p->>'remind_at', '') <> '' THEN PERFORM agent._remind_apply(tid, p->>'remind_at'); END IF;
  IF jsonb_typeof(p->'attach') = 'array' THEN
    IF jsonb_array_length(p->'attach') > 10 THEN RAISE EXCEPTION 'Đính kèm tối đa 10 tệp lúc tạo'; END IF;
    FOR a IN SELECT * FROM jsonb_array_elements(p->'attach') LOOP PERFORM agent._attach_link(tid, cid, a->>'url', a->>'name', me.id); END LOOP;
  END IF;
  IF jsonb_typeof(p->'checklist') = 'array' THEN
    SELECT array_agg(left(btrim(x), 300)) INTO items FROM jsonb_array_elements_text(p->'checklist') x WHERE btrim(x) <> '';
    IF items IS NOT NULL THEN
      IF cardinality(items) > 50 THEN RAISE EXCEPTION 'Checklist tối đa 50 mục'; END IF;
      INSERT INTO work.checklist_items (task_id, position, title) SELECT tid, o - 1, it FROM unnest(items) WITH ORDINALITY u(it, o);
    END IF;
  END IF;
  IF jsonb_typeof(p->'subtasks') = 'array' THEN
    IF jsonb_array_length(p->'subtasks') > 20 THEN RAISE EXCEPTION 'Việc con tối đa 20'; END IF;
    FOR s IN SELECT * FROM jsonb_array_elements(p->'subtasks') LOOP
      sq := jsonb_build_object('company_id', cid, 'parent_id', tid, 'title', CASE WHEN jsonb_typeof(s) = 'string' THEN s #>> '{}' ELSE s->>'title' END,
             'priority', coalesce(p->>'priority', 'medium'));
      IF coalesce(p->>'assignee_id', '') <> '' THEN sq := sq || jsonb_build_object('assignee_id', p->>'assignee_id'); END IF;
      IF coalesce(p->>'project_id', '') <> '' THEN sq := sq || jsonb_build_object('project_id', p->>'project_id'); END IF;
      IF jsonb_typeof(s) = 'object' AND coalesce(s->>'due_date', '') <> '' THEN sq := sq || jsonb_build_object('due_date', s->>'due_date'); END IF;
      sid := (agent.app_task_save(sq)->>'id')::bigint; kids := kids || sid;
    END LOOP;
  END IF;
  IF coalesce(p->>'template_id', '') <> '' THEN UPDATE work.task_templates SET uses = uses + 1 WHERE id = (p->>'template_id')::uuid AND company_id = cid; END IF;
  RETURN jsonb_build_object('id', tid, 'subtasks', to_jsonb(kids));
END $$;

-- Nhân bản một việc: cùng tiêu đề + " (bản sao)", trạng thái Chờ làm, giữ người/dự án/ưu tiên/cờ/ước tính/nhãn/checklist (bỏ dấu tick) và tùy chọn việc con
CREATE OR REPLACE FUNCTION agent.app_task_clone(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); t work.tasks; q jsonb; nid bigint; k work.tasks; kids bigint[] := '{}'; kq jsonb; kid bigint;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = (p->>'task')::bigint;
  IF t.id IS NULL OR NOT agent._can_see(me.id, t) THEN RAISE EXCEPTION 'Không tìm thấy việc hoặc bạn không có quyền xem' USING ERRCODE = '42501'; END IF;
  IF EXISTS (SELECT 1 FROM agent.ai_requests r WHERE r.task_id = t.id) THEN RAISE EXCEPTION 'Không nhân bản được thẻ phân tích của trợ lý AI'; END IF;
  q := jsonb_build_object('company_id', t.company_id, 'title', left(t.title, 285) || ' (bản sao)', 'description', coalesce(t.description, ''), 'priority', t.priority,
        'important', t.important, 'urgent', t.urgent);
  IF t.assignee_id IS NOT NULL THEN q := q || jsonb_build_object('assignee_id', t.assignee_id); END IF;
  IF t.project_id IS NOT NULL THEN q := q || jsonb_build_object('project_id', t.project_id); END IF;
  IF t.department_id IS NOT NULL THEN q := q || jsonb_build_object('department_id', t.department_id); END IF;
  IF t.parent_id IS NOT NULL THEN q := q || jsonb_build_object('parent_id', t.parent_id); END IF;
  IF t.est_minutes IS NOT NULL THEN q := q || jsonb_build_object('est_minutes', t.est_minutes); END IF;
  IF t.due_date IS NOT NULL AND t.due_date >= (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date THEN q := q || jsonb_build_object('due_date', t.due_date); END IF;   -- hạn đã qua thì để trống
  nid := (agent.app_task_save(q)->>'id')::bigint;
  INSERT INTO work.task_tags (task_id, tag_id) SELECT nid, tag_id FROM work.task_tags WHERE task_id = t.id;
  INSERT INTO work.checklist_items (task_id, position, title) SELECT nid, position, title FROM work.checklist_items WHERE task_id = t.id;
  IF coalesce((p->>'subtasks')::boolean, false) THEN
    FOR k IN SELECT * FROM work.tasks WHERE parent_id = t.id AND status <> 'cancelled' AND agent._can_see(me.id, work.tasks.*) ORDER BY id LIMIT 20 LOOP
      kq := jsonb_build_object('company_id', k.company_id, 'title', k.title, 'parent_id', nid, 'priority', k.priority, 'description', coalesce(k.description, ''));
      IF k.assignee_id IS NOT NULL THEN kq := kq || jsonb_build_object('assignee_id', k.assignee_id); END IF;
      IF k.project_id IS NOT NULL THEN kq := kq || jsonb_build_object('project_id', k.project_id); END IF;
      kid := (agent.app_task_save(kq)->>'id')::bigint; kids := kids || kid;
    END LOOP;
  END IF;
  PERFORM agent._audit(t.company_id, me.id, 'clone', 'task', nid::text, 'Nhân bản T-' || t.id || ' thành T-' || nid);
  RETURN jsonb_build_object('id', nid, 'subtasks', to_jsonb(kids));
END $$;

-- Tạo hàng loạt (dán danh sách / nhập CSV): tối đa 100 việc, mỗi việc trong một tiểu giao dịch; việc lỗi được báo theo dòng, không làm hỏng các việc khác.
CREATE OR REPLACE FUNCTION agent.app_tasks_bulk(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); it jsonb; i int := 0; ok bigint[] := '{}'; errs jsonb := '[]'; r jsonb;
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  IF jsonb_typeof(p->'items') <> 'array' OR jsonb_array_length(p->'items') NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'Gửi từ 1 đến 100 việc mỗi lần'; END IF;
  FOR it IN SELECT * FROM jsonb_array_elements(p->'items') LOOP
    i := i + 1;
    BEGIN
      r := agent.app_task_create_ex((it - 'id' - 'company_id' - 'parent_id') || jsonb_build_object('company_id', cid));
      ok := ok || (r->>'id')::bigint;
    EXCEPTION WHEN OTHERS THEN
      errs := errs || jsonb_build_array(jsonb_build_object('row', i, 'error', SQLERRM));
    END;
  END LOOP;
  PERFORM agent._audit(cid, me.id, 'bulk_create', 'task', coalesce(ok[1]::text, '0'), 'Tạo hàng loạt ' || cardinality(ok) || ' việc' || CASE WHEN jsonb_array_length(errs) > 0 THEN ', ' || jsonb_array_length(errs) || ' dòng lỗi' ELSE '' END);
  RETURN jsonb_build_object('created', to_jsonb(ok), 'errors', errs);
END $$;
-- ==== HẾT PHẦN D ====

-- ==== PHẦN E: VIỆC ĐỊNH KỲ — hằng năm, giới hạn số lần, lặp vô hạn ====
ALTER TABLE work.recurrences ADD COLUMN IF NOT EXISTS max_runs int CHECK (max_runs IS NULL OR max_runs BETWEEN 1 AND 1000);   -- NULL = lặp không giới hạn
ALTER TABLE work.recurrences ADD COLUMN IF NOT EXISTS run_count int NOT NULL DEFAULT 0;
DO $$ DECLARE c text; BEGIN
  FOR c IN SELECT conname FROM pg_constraint WHERE conrelid = 'work.recurrences'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%freq%' AND pg_get_constraintdef(oid) NOT LIKE '%yearly%' LOOP
    EXECUTE format('ALTER TABLE work.recurrences DROP CONSTRAINT %I', c);
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'work.recurrences'::regclass AND conname = 'recurrences_freq_chk') THEN
    ALTER TABLE work.recurrences ADD CONSTRAINT recurrences_freq_chk CHECK (freq IN ('daily','weekly','monthly','yearly'));
  END IF;
END $$;

-- Thêm "hằng năm" vào recur_next: cùng ngày/tháng của lần trước, cộng interval_n năm (29/2 lùi về 28/2 năm không nhuận)
CREATE OR REPLACE FUNCTION work.recur_next(r work.recurrences, p_from date) RETURNS date
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE d date; wk int[] := coalesce(r.weekdays, ARRAY[extract(isodow FROM p_from)::int]); base date := date_trunc('week', r.created_at)::date; m date; last_d int; want int;
BEGIN
  IF r.freq = 'yearly' THEN
    RETURN (p_from + make_interval(years => r.interval_n))::date;
  END IF;
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

-- Như bản 0027, thêm: đếm số lần đã sinh (run_count) và tự dừng khi đủ max_runs
CREATE OR REPLACE FUNCTION work._run_recurrence(p_id uuid, p_today date) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = work, core, agent, public AS $$
DECLARE r work.recurrences; occ date; nxt date; made bigint; guard int := 0;
BEGIN
  SELECT * INTO r FROM work.recurrences WHERE id = p_id AND active FOR UPDATE;
  IF r.id IS NULL OR r.next_run > p_today THEN RETURN NULL; END IF;
  IF r.max_runs IS NOT NULL AND r.run_count >= r.max_runs THEN UPDATE work.recurrences SET active = false WHERE id = r.id; RETURN NULL; END IF;
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
    UPDATE work.recurrences SET run_count = run_count + 1 WHERE id = r.id;
    r.run_count := r.run_count + 1;
  END IF;
  nxt := work.recur_next(r, occ);
  IF (r.until_date IS NOT NULL AND nxt > r.until_date) OR (r.max_runs IS NOT NULL AND r.run_count >= r.max_runs) THEN UPDATE work.recurrences SET active = false, next_run = nxt WHERE id = r.id;
  ELSE UPDATE work.recurrences SET next_run = nxt WHERE id = r.id; END IF;
  RETURN made;
END $$;

-- Như bản 0027, thêm "hằng năm" (yearly)
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
  IF v_freq NOT IN ('daily','weekly','monthly','yearly') THEN RAISE EXCEPTION 'Tần suất phải là hằng ngày, hằng tuần, hằng tháng hoặc hằng năm'; END IF;
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

-- Như bản 0027, thêm max_runs/run_count
CREATE OR REPLACE FUNCTION agent.app_recurrences(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); my text;
BEGIN
  my := agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  RETURN coalesce((SELECT jsonb_agg(jsonb_build_object('id', r.id, 'title', r.title, 'description', r.description, 'department_id', r.department_id, 'project_id', r.project_id,
            'assignee_id', r.assignee_id, 'priority', r.priority, 'freq', r.freq, 'interval_n', r.interval_n, 'weekdays', r.weekdays, 'month_day', r.month_day, 'due_offset', r.due_offset,
            'skip_holidays', r.skip_holidays, 'next_run', r.next_run, 'until_date', r.until_date, 'max_runs', r.max_runs, 'run_count', r.run_count, 'active', r.active, 'created_by', r.created_by,
            'can_edit', my IN ('owner','admin') OR r.created_by = me.id,
            'last_task', (SELECT jsonb_build_object('id', t.id, 'status', t.status, 'due_date', t.due_date) FROM work.tasks t WHERE t.recurrence_id = r.id ORDER BY t.id DESC LIMIT 1))
            ORDER BY r.active DESC, r.freq, r.title)
     FROM work.recurrences r WHERE r.company_id = cid AND (my IN ('owner','admin','manager') OR r.created_by = me.id OR r.assignee_id = me.id)), '[]');
END $$;

-- Cách kết thúc việc lặp, gửi lên app_recurrence_save qua "end": {"mode":"never"} | {"mode":"until","date":"YYYY-MM-DD"} | {"mode":"count","n":10}. Hàm này đặt giới hạn sau khi lưu (gọi trong app_recurrence_save_ex).
CREATE OR REPLACE FUNCTION agent.app_recurrence_save_ex(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); e jsonb := p->'end'; mode text := coalesce(e->>'mode', ''); q jsonb := p - 'end'; res jsonb; rid uuid; r work.recurrences; cnt int;
BEGIN
  IF e IS NOT NULL AND jsonb_typeof(e) = 'object' THEN
    IF mode NOT IN ('never','until','count') THEN RAISE EXCEPTION 'Cách kết thúc phải là không bao giờ, đến ngày hoặc sau n lần'; END IF;
    IF mode = 'until' THEN
      IF coalesce(e->>'date', '') = '' THEN RAISE EXCEPTION 'Chọn ngày kết thúc'; END IF;
      q := q || jsonb_build_object('until_date', e->>'date');
    ELSE q := q || jsonb_build_object('until_date', ''); END IF;   -- không bao giờ / theo số lần: bỏ ngày kết thúc
    IF mode = 'count' THEN
      cnt := (e->>'n')::int; IF cnt IS NULL OR cnt NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Số lần lặp từ 1 đến 1000'; END IF;
    END IF;
  END IF;
  -- đặt max_runs TRƯỚC khi lưu để lần chạy đầu (đến hạn ngay) đã tính vào giới hạn
  IF mode <> '' AND (q->>'id') IS NOT NULL THEN
    SELECT * INTO r FROM work.recurrences WHERE id = (q->>'id')::uuid;
    IF r.id IS NOT NULL AND (r.created_by = me.id OR agent._role_of(me.id, r.company_id) IN ('owner','admin')) THEN
      UPDATE work.recurrences SET max_runs = CASE WHEN mode = 'count' THEN cnt END WHERE id = r.id;
    END IF;
  END IF;
  res := agent.app_recurrence_save(q);
  rid := (res->>'id')::uuid;
  IF mode <> '' AND (q->>'id') IS NULL THEN UPDATE work.recurrences SET max_runs = CASE WHEN mode = 'count' THEN cnt END WHERE id = rid;
    -- lần chạy đầu đã diễn ra trong app_recurrence_save: nếu đã đủ số lần thì dừng
    UPDATE work.recurrences SET active = false WHERE id = rid AND max_runs IS NOT NULL AND run_count >= max_runs; END IF;
  RETURN res;
END $$;
-- ==== HẾT PHẦN E ====

-- Quyền
GRANT EXECUTE ON FUNCTION agent.app_task_tags_set(jsonb), agent.app_tags(jsonb), agent.app_task_tags_map(jsonb), agent.app_task_similar(jsonb), agent.app_tag_suggest(jsonb),
  agent.app_task_deps_set(jsonb), agent.app_task_remind(jsonb), agent.app_task_attach_link(jsonb), agent.app_task_extras(jsonb),
  agent.app_task_templates(jsonb), agent.app_task_template_save(jsonb), agent.app_task_template_delete(jsonb),
  agent.app_task_create_ex(jsonb), agent.app_task_clone(jsonb), agent.app_tasks_bulk(jsonb), agent.app_recurrence_save_ex(jsonb) TO web_svc;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA agent FROM PUBLIC;
COMMIT;
