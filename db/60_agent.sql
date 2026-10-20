-- =====================================================================
-- Enterprise OS — 60 AI agent (schema agent)
-- Agent hệ thống chạy trên Hermes Agent (VPS 173), làm việc qua Hermes Kanban.
-- Enterprise OS là sổ gốc (work.tasks); Kanban chỉ là hàng đợi thực thi của agent.
-- Cầu nối eos-kanban-bridge đọc agent.outbox và đẩy sự kiện Kanban về agent.ingest_event.
-- Agent cá nhân của từng người vào hệ thống qua MCP (agent.mcp_*), mang danh tính người đó.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS agent;
SET search_path = agent, work, core, public;

-- ---------- Tiện ích chung: người gọi hiện tại (từ JWT của PostgREST hoặc MCP) ----------
CREATE FUNCTION core.current_user_id() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(nullif(current_setting('request.jwt.claims', true), '')::json->>'sub', '')::uuid
$$;
CREATE FUNCTION core.current_via() RETURNS text LANGUAGE sql STABLE AS $$   -- app | mcp:<mã token> | agent:<mã>
  SELECT coalesce(nullif(current_setting('request.jwt.claims', true), '')::json->>'via', 'app')
$$;

-- Phạm vi cao nhất của một quyền mà người dùng có ở công ty: NULL = không có quyền
CREATE FUNCTION core.perm_scope_of(p_user uuid, p_company uuid, p_perm text)
RETURNS core.perm_scope LANGUAGE sql STABLE AS $$
  SELECT max(rp.scope) FROM core.user_roles ur
    JOIN core.role_permissions rp ON rp.role_id = ur.role_id AND rp.permission = p_perm
   WHERE ur.user_id = p_user AND ur.company_id = p_company
$$;

-- Ai được xem một việc: người làm, người giao, người theo dõi, người đang phải duyệt,
-- hoặc có quyền work.task.view theo phòng / cả công ty.
CREATE FUNCTION work.can_view_task(p_user uuid, p_task bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = work, core, public AS $$
  SELECT EXISTS (
    SELECT 1 FROM work.tasks t
      JOIN core.memberships m ON m.user_id = p_user AND m.company_id = t.company_id AND m.active
     WHERE t.id = p_task AND (
           t.assignee_id = p_user OR t.created_by = p_user
        OR EXISTS (SELECT 1 FROM work.task_watchers w WHERE w.task_id = t.id AND w.user_id = p_user)
        OR EXISTS (SELECT 1 FROM core.approval_requests r JOIN core.approval_decisions d ON d.request_id = r.id AND d.round = r.round
                    WHERE r.entity_type = 'task' AND r.entity_id = t.id AND r.state = 'pending'
                      AND d.approver_user = p_user AND d.decision = 'pending')
        OR core.perm_scope_of(p_user, t.company_id, 'work.task.view') = 'company'
        OR (core.perm_scope_of(p_user, t.company_id, 'work.task.view') = 'department' AND t.department_id = m.department_id)
        OR (m.is_dept_head AND t.department_id = m.department_id)))
$$;

-- ---------- 1. Danh mục agent hệ thống ----------
-- Mỗi agent = một profile Hermes, có một tài khoản core.users kind='agent' để đứng tên trong nhật ký.
CREATE TABLE agent.agents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL UNIQUE REFERENCES core.users(id),
  code          text NOT NULL UNIQUE CHECK (code ~ '^[a-z][a-z-]{1,31}$'),   -- dieu-phoi, van-thu, nhan-su, quan-tri-du-lieu, phap-che
  name          text NOT NULL,                                -- "Văn thư AI"
  kind          text NOT NULL CHECK (kind IN ('orchestrator','module','specialist')),
  module        text NOT NULL CHECK (module IN ('core','work','doc','hr','kb','crm')),
  hermes_profile text NOT NULL CHECK (hermes_profile ~ '^[a-z0-9_-]{2,40}$'),
  skills        text[] NOT NULL DEFAULT '{}',                 -- skill Hermes gắn vào thẻ Kanban
  max_level     smallint NOT NULL DEFAULT 1 CHECK (max_level BETWEEN 0 AND 2),   -- L3 không bao giờ cho agent
  can_delegate  boolean NOT NULL DEFAULT false,               -- được chia việc con cho agent khác (mặc định chỉ dieu-phoi)
  description   text,
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ---------- 2. Cấu hình agent theo công ty ----------
CREATE TABLE agent.company_settings (
  company_id      uuid PRIMARY KEY REFERENCES core.companies(id) ON DELETE CASCADE,
  enabled         boolean NOT NULL DEFAULT false,
  kanban_board    text NOT NULL UNIQUE CHECK (kanban_board ~ '^[a-z0-9-]{2,40}$'),  -- một board Hermes mỗi công ty
  hermes_host     text NOT NULL DEFAULT 'vps173',
  digest_time     time NOT NULL DEFAULT '08:00',
  default_reviewer uuid REFERENCES core.users(id),            -- người duyệt kết quả khi việc không có người giao
  max_rework      smallint NOT NULL DEFAULT 2 CHECK (max_rework BETWEEN 0 AND 5),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE agent.company_agents (
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  agent_id      uuid NOT NULL REFERENCES agent.agents(id) ON DELETE CASCADE,
  enabled       boolean NOT NULL DEFAULT true,
  auto_done     boolean NOT NULL DEFAULT false,               -- true: kết quả L0–L1 đóng việc luôn, không qua người xem
  max_running   smallint NOT NULL DEFAULT 3 CHECK (max_running BETWEEN 1 AND 20),
  config        jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (company_id, agent_id)
);

-- ---------- 3. Mức tự chủ cho từng hành động (L0 đọc · L1 tự làm · L2 xin xác nhận · L3 chỉ người) ----------
CREATE TABLE agent.action_levels (
  action        text PRIMARY KEY CHECK (action ~ '^[a-z]+(\.[a-z_]+)+$'),   -- work.task.assign_other
  level         smallint NOT NULL CHECK (level BETWEEN 0 AND 3),
  name          text NOT NULL,
  note          text
);

-- Agent xin xác nhận trước hành động L2 (giao việc cho người khác, gửi ra ngoài, đổi hạn của người khác…)
CREATE TABLE agent.confirmations (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  agent_id      uuid NOT NULL REFERENCES agent.agents(id),
  task_id       bigint REFERENCES work.tasks(id) ON DELETE CASCADE,
  card_id       text,
  action        text NOT NULL REFERENCES agent.action_levels(action),
  summary       text NOT NULL CHECK (length(summary) <= 1000),   -- câu hỏi hiện cho người: "Giao 3 việc cho Minh, hạn 20/10?"
  payload       jsonb NOT NULL,                                  -- hành động sẽ chạy khi được đồng ý
  ask_user      uuid NOT NULL REFERENCES core.users(id),
  state         text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','approved','rejected','expired','done')),
  decided_by    uuid REFERENCES core.users(id),
  decided_at    timestamptz,
  decision_note text,
  expires_at    timestamptz NOT NULL DEFAULT now() + interval '3 days',
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX confirmations_pending_idx ON agent.confirmations (ask_user) WHERE state = 'pending';

-- ---------- 4. Thẻ Kanban ↔ việc ----------
CREATE TABLE agent.cards (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  task_id         bigint REFERENCES work.tasks(id) ON DELETE SET NULL,   -- NULL = thẻ nội bộ (bước con của agent)
  agent_id        uuid NOT NULL REFERENCES agent.agents(id),
  board           text NOT NULL,
  card_id         text,                                       -- id Hermes (t_xxxx), có sau khi cầu nối tạo thẻ
  parent_card_id  text,
  idempotency_key text NOT NULL UNIQUE,                       -- eos-<task>-<lượt>
  kind            text NOT NULL DEFAULT 'task' CHECK (kind IN ('task','rework','synthesis','routine')),
  attempt         smallint NOT NULL DEFAULT 1,
  status          text NOT NULL DEFAULT 'queued'
                  CHECK (status IN ('queued','triage','todo','ready','running','blocked','review','done','archived','gave_up','crashed','timed_out','cancelled')),
  last_event_at   timestamptz,
  completed_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (board, card_id)
);
CREATE INDEX cards_task_idx ON agent.cards (task_id, attempt DESC);

-- ---------- 5. Hộp thư đi: Enterprise OS → cầu nối → Hermes Kanban ----------
CREATE TABLE agent.outbox (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  kind        text NOT NULL CHECK (kind IN ('dispatch','answer','rework','cancel','routine')),
  task_id     bigint REFERENCES work.tasks(id) ON DELETE CASCADE,
  card_ref    bigint REFERENCES agent.cards(id) ON DELETE CASCADE,
  payload     jsonb NOT NULL DEFAULT '{}',
  created_at  timestamptz NOT NULL DEFAULT now(),
  picked_at   timestamptz,
  done_at     timestamptz,
  tries       int NOT NULL DEFAULT 0,
  error       text
);
CREATE INDEX outbox_open_idx ON agent.outbox (id) WHERE done_at IS NULL;

-- ---------- 6. Sự kiện nhận về từ Kanban (chống trùng theo event_key) ----------
CREATE TABLE agent.events (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  card_ref    bigint NOT NULL REFERENCES agent.cards(id) ON DELETE CASCADE,
  event       text NOT NULL CHECK (event IN ('created','claimed','heartbeat','comment','blocked','review','completed','gave_up','crashed','timed_out','archived')),
  event_key   text NOT NULL UNIQUE,                           -- <board>:<card>:<id sự kiện Hermes hoặc hook>
  payload     jsonb NOT NULL DEFAULT '{}',
  received_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX events_card_idx ON agent.events (card_ref, received_at);

-- ---------- 7. Báo cáo hoàn thành của agent (hợp đồng bàn giao) ----------
CREATE TABLE agent.reports (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  task_id       bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  card_ref      bigint REFERENCES agent.cards(id) ON DELETE SET NULL,
  agent_id      uuid NOT NULL REFERENCES agent.agents(id),
  summary       text NOT NULL CHECK (length(summary) BETWEEN 10 AND 4000),
  outputs       jsonb NOT NULL DEFAULT '[]',                  -- [{drive_id, name, url}] tệp kết quả trên Drive
  sources       jsonb NOT NULL DEFAULT '[]',                  -- [{title, page, url}] căn cứ đã dùng
  checks        jsonb NOT NULL DEFAULT '{}',                  -- {"kiem-tra":"dat"} kết quả sub-agent kiểm tra
  confidence    text CHECK (confidence IN ('cao','trung_binh','thap')),
  residual_risk text,
  next_actions  text,
  verdict       text NOT NULL DEFAULT 'pending' CHECK (verdict IN ('pending','accepted','rework','auto_done')),
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX reports_task_idx ON agent.reports (task_id, created_at DESC);

-- ---------- 8. Luật tự động chuyển việc cho agent ----------
CREATE TABLE agent.routing_rules (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,
  trigger     text NOT NULL CHECK (trigger IN ('task_created','incoming_doc','outgoing_draft','hr_request','kb_gap','record_ingest')),
  match       jsonb NOT NULL DEFAULT '{}',                    -- {"source":"incoming_doc","doc_type":"CV"} | {"title_has":"đối chiếu"}
  agent_id    uuid NOT NULL REFERENCES agent.agents(id),
  agent_role  text CHECK (agent_role ~ '^[a-z-]{2,32}$'),     -- sub-agent / skill chuyên môn
  sort        int NOT NULL DEFAULT 100,
  active      boolean NOT NULL DEFAULT true,
  created_by  uuid REFERENCES core.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------- 9. Việc định kỳ của agent (nhắc hạn, bản tin, nháp KPI…) ----------
CREATE TABLE agent.routines (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  agent_id    uuid NOT NULL REFERENCES agent.agents(id),
  code        text NOT NULL CHECK (code ~ '^[a-z_]{3,40}$'),  -- daily_digest, deadline_watch, kpi_draft
  name        text NOT NULL,
  cron        text NOT NULL,                                  -- 5 trường, theo giờ của công ty
  params      jsonb NOT NULL DEFAULT '{}',
  enabled     boolean NOT NULL DEFAULT true,
  last_run_at timestamptz,
  last_status text,
  UNIQUE (company_id, code)
);

-- ---------- 10. MCP cho agent cá nhân: mã truy cập theo người ----------
CREATE TABLE agent.mcp_tokens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  company_id   uuid REFERENCES core.companies(id) ON DELETE CASCADE,   -- NULL = mọi công ty người đó thuộc
  name         text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 60),   -- "Claude trên laptop"
  client       text NOT NULL DEFAULT 'other' CHECK (client IN ('claude','chatgpt','gemini','hermes','cursor','other')),
  prefix       text NOT NULL UNIQUE,                          -- 8 ký tự đầu, hiện trên màn hình để nhận ra
  token_hash   text NOT NULL UNIQUE,                          -- sha256 hex; không lưu mã gốc
  agent_id     uuid REFERENCES agent.agents(id) ON DELETE CASCADE,   -- NULL = mã của người; có giá trị = mã của worker agent hệ thống
  scopes       text[] NOT NULL CHECK (scopes <@ ARRAY['read','write','drive','hr_self','kb','delegate']::text[] AND cardinality(scopes) > 0),
  expires_at   timestamptz NOT NULL,
  last_used_at timestamptz,
  last_ip      inet,
  revoked_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_at <= created_at + interval '366 days'),
  -- mã của agent hệ thống chỉ đọc (và chia việc nếu được phép); mã của người không có quyền chia việc
  CHECK (CASE WHEN agent_id IS NULL THEN NOT 'delegate' = ANY (scopes) ELSE scopes <@ ARRAY['read','kb','delegate']::text[] END)
);
CREATE INDEX mcp_tokens_user_idx ON agent.mcp_tokens (user_id) WHERE revoked_at IS NULL;

-- Nhật ký gọi MCP: chỉ tên công cụ và tham số tóm tắt, không lưu nội dung tệp
CREATE TABLE agent.mcp_calls (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  token_id    uuid NOT NULL REFERENCES agent.mcp_tokens(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  tool        text NOT NULL,
  args        jsonb NOT NULL DEFAULT '{}',
  outcome     text NOT NULL CHECK (outcome IN ('ok','denied','invalid','error')),
  entity_type text,
  entity_id   text,
  ms          int,
  at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX mcp_calls_user_idx ON agent.mcp_calls (user_id, at DESC);

-- Tệp được ghi vào Drive cá nhân qua MCP hoặc agent hệ thống (nội dung đi thẳng lên Drive, không lưu trên máy chủ)
CREATE TABLE agent.drive_writes (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES core.users(id),        -- chủ thư mục Drive
  file_id     bigint NOT NULL REFERENCES core.files(id) ON DELETE CASCADE,
  task_id     bigint REFERENCES work.tasks(id) ON DELETE SET NULL,
  folder_path text NOT NULL,                                  -- Ket qua/2026-10
  via         text NOT NULL,                                  -- mcp:<prefix> | agent:<mã>
  bytes       bigint NOT NULL CHECK (bytes BETWEEN 0 AND 26214400),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Thứ tự giữa các việc con do agent chia: task_id chỉ chạy khi after_task_id đã Xong
CREATE TABLE agent.task_deps (
  task_id       bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  after_task_id bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, after_task_id),
  CHECK (task_id <> after_task_id)
);

-- ---------- Liên kết việc ↔ agent ----------
ALTER TABLE work.tasks ADD COLUMN agent_id uuid REFERENCES agent.agents(id);   -- agent thực hiện; assignee_id vẫn là người chịu trách nhiệm
CREATE INDEX tasks_agent_idx ON work.tasks (agent_id, status) WHERE agent_id IS NOT NULL;

-- =====================================================================
-- Hàm
-- =====================================================================

-- Ghi bình luận + nhật ký cho một việc
CREATE FUNCTION agent._log(p_task work.tasks, p_actor text, p_user uuid, p_kind work.comment_kind, p_body text, p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
BEGIN
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task.id, p_user, p_actor, p_kind, left(p_body, 8000));
  INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
  VALUES (p_task.company_id, p_actor, p_user, 'work', p_action, 'task', p_task.id::text, left('T-' || p_task.id || ' · ' || p_body, 300));
END $$;

CREATE FUNCTION agent._notify(p_company uuid, p_user uuid, p_kind text, p_title text, p_task bigint)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = core, public AS $$
  INSERT INTO core.notifications (company_id, user_id, kind, title, link, entity_type, entity_id)
  SELECT p_company, p_user, p_kind, p_title, '#/work/tasks/' || p_task, 'task', p_task::text WHERE p_user IS NOT NULL
$$;

-- Đưa một việc của agent vào hộp thư đi (thẻ mới). p_kind = 'synthesis' cho lượt tổng hợp sau khi việc con xong.
CREATE FUNCTION agent._dispatch(p_task bigint, p_kind text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE t work.tasks; s agent.company_settings; ca agent.company_agents; c agent.cards; kind text; key text; prev text; kids jsonb;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  SELECT * INTO s FROM agent.company_settings WHERE company_id = t.company_id AND enabled;
  SELECT * INTO ca FROM agent.company_agents WHERE company_id = t.company_id AND agent_id = t.agent_id AND enabled;
  IF s.company_id IS NULL OR ca.agent_id IS NULL THEN
    RAISE EXCEPTION 'Agent chưa được bật cho công ty này' USING ERRCODE = 'P0001';
  END IF;
  -- đã có thẻ đang chạy thì không tạo thẻ mới
  IF EXISTS (SELECT 1 FROM agent.cards WHERE task_id = t.id AND status NOT IN ('done','archived','gave_up','crashed','timed_out','cancelled')) THEN
    RETURN;
  END IF;
  -- việc con còn chờ việc đứng trước
  IF EXISTS (SELECT 1 FROM agent.task_deps d JOIN work.tasks b ON b.id = d.after_task_id WHERE d.task_id = t.id AND b.status <> 'done') THEN
    RETURN;
  END IF;
  kind := coalesce(p_kind, CASE WHEN t.attempts > 0 THEN 'rework' ELSE 'task' END);
  key := 'eos-' || t.id || '-' || (t.attempts + 1) || CASE WHEN kind = 'synthesis' THEN '-s' ELSE '' END;
  SELECT card_id INTO prev FROM agent.cards WHERE task_id = t.id ORDER BY id DESC LIMIT 1;
  IF kind = 'synthesis' THEN
    SELECT jsonb_agg(jsonb_build_object('id', 'T-' || k.id, 'title', k.title, 'status', k.status) ORDER BY k.id) INTO kids
      FROM work.tasks k WHERE k.parent_id = t.id;
  END IF;
  INSERT INTO agent.cards (company_id, task_id, agent_id, board, idempotency_key, kind, attempt, parent_card_id)
  VALUES (t.company_id, t.id, t.agent_id, s.kanban_board, key, kind, t.attempts + 1, CASE WHEN kind = 'synthesis' THEN prev END)
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING * INTO c;
  IF c.id IS NULL THEN RETURN; END IF;
  INSERT INTO agent.outbox (company_id, kind, task_id, card_ref, payload)
  VALUES (t.company_id, 'dispatch', t.id, c.id,
          jsonb_strip_nulls(jsonb_build_object(
            'title', CASE WHEN kind = 'synthesis' THEN 'Tổng hợp ' ELSE '' END || 'T-' || t.id || ' ' || t.title,
            'profile', (SELECT hermes_profile FROM agent.agents WHERE id = t.agent_id),
            'skills', (SELECT to_jsonb(skills) FROM agent.agents WHERE id = t.agent_id)
                      || CASE WHEN t.agent_role IS NULL THEN '[]'::jsonb ELSE to_jsonb(ARRAY[t.agent_role]) END,
            'tenant', coalesce((SELECT code FROM core.departments WHERE id = t.department_id), 'chung'),
            'board', s.kanban_board,
            'idempotency_key', c.idempotency_key,
            'card_kind', kind,
            'children', kids,
            'parent_task', CASE WHEN t.parent_id IS NOT NULL THEN 'T-' || t.parent_id END,
            'due_date', t.due_date,
            'priority', t.priority)));
END $$;

CREATE FUNCTION agent.tasks_dispatch_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
BEGIN
  IF NEW.agent_id IS NULL OR NEW.status <> 'todo' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.agent_id IS NOT DISTINCT FROM NEW.agent_id AND OLD.status = NEW.status THEN RETURN NEW; END IF;
  PERFORM agent._dispatch(NEW.id);
  RETURN NEW;
END $$;
CREATE TRIGGER tasks_dispatch AFTER INSERT OR UPDATE OF agent_id, status ON work.tasks
  FOR EACH ROW EXECUTE FUNCTION agent.tasks_dispatch_trg();

-- Một việc Xong: chạy các việc con đang chờ nó; nếu mọi việc con của việc cha đã xong thì tạo thẻ tổng hợp cho agent cha
CREATE FUNCTION agent.tasks_done_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE nxt bigint; p work.tasks;
BEGIN
  IF NEW.status NOT IN ('done','cancelled') OR OLD.status = NEW.status THEN RETURN NEW; END IF;
  FOR nxt IN SELECT d.task_id FROM agent.task_deps d JOIN work.tasks k ON k.id = d.task_id
              WHERE d.after_task_id = NEW.id AND k.status = 'todo' AND k.agent_id IS NOT NULL LOOP
    PERFORM agent._dispatch(nxt);
  END LOOP;
  IF NEW.parent_id IS NOT NULL AND NEW.source = 'agent' THEN
    SELECT * INTO p FROM work.tasks WHERE id = NEW.parent_id;
    IF p.agent_id IS NOT NULL AND p.status = 'in_progress'
       AND NOT EXISTS (SELECT 1 FROM work.tasks k WHERE k.parent_id = p.id AND k.source = 'agent' AND k.status NOT IN ('done','cancelled')) THEN
      PERFORM agent._dispatch(p.id, 'synthesis');
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tasks_done AFTER UPDATE OF status ON work.tasks FOR EACH ROW EXECUTE FUNCTION agent.tasks_done_trg();

-- Việc bị hủy: dừng thẻ Kanban của nó (cầu nối archive thẻ). Thẻ chưa kịp tạo bên Kanban thì hủy lệnh dispatch đang chờ.
CREATE FUNCTION agent.tasks_cancel_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE c agent.cards;
BEGIN
  IF NEW.status <> 'cancelled' OR OLD.status = 'cancelled' OR NEW.agent_id IS NULL THEN RETURN NEW; END IF;
  FOR c IN SELECT * FROM agent.cards WHERE task_id = NEW.id AND status NOT IN ('done','archived','gave_up','crashed','timed_out','cancelled') LOOP
    IF c.card_id IS NULL THEN
      UPDATE agent.outbox SET done_at = now(), error = 'Việc bị hủy trước khi tạo thẻ' WHERE card_ref = c.id AND kind = 'dispatch' AND done_at IS NULL;
    ELSE
      INSERT INTO agent.outbox (company_id, kind, task_id, card_ref, payload)
      VALUES (c.company_id, 'cancel', NEW.id, c.id, jsonb_build_object('board', c.board, 'card_id', c.card_id));
    END IF;
    UPDATE agent.cards SET status = 'cancelled', last_event_at = now() WHERE id = c.id;
  END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER tasks_cancel AFTER UPDATE OF status ON work.tasks FOR EACH ROW EXECUTE FUNCTION agent.tasks_cancel_trg();

-- Người trả lời câu hỏi của agent, hoặc trả lại kết quả → chuyển tiếp sang Kanban
CREATE FUNCTION agent.comments_relay_trg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE t work.tasks; c agent.cards; s agent.company_settings;
BEGIN
  IF NEW.actor LIKE 'agent:%' OR NEW.kind NOT IN ('answer','reject') THEN RETURN NEW; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = NEW.task_id;
  IF t.agent_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO c FROM agent.cards WHERE task_id = t.id ORDER BY attempt DESC, id DESC LIMIT 1;
  IF NEW.kind = 'answer' AND c.status = 'blocked' THEN
    INSERT INTO agent.outbox (company_id, kind, task_id, card_ref, payload)
    VALUES (t.company_id, 'answer', t.id, c.id, jsonb_build_object('board', c.board, 'card_id', c.card_id, 'body', NEW.body, 'by', NEW.actor));
    UPDATE work.tasks SET status = 'in_progress', waiting_on_human = false, updated_at = now() WHERE id = t.id;
  ELSIF NEW.kind = 'reject' AND t.status = 'in_review' THEN
    SELECT * INTO s FROM agent.company_settings WHERE company_id = t.company_id;
    UPDATE agent.reports SET verdict = 'rework' WHERE task_id = t.id AND verdict = 'pending';
    IF t.attempts + 1 > s.max_rework THEN
      -- quá số lần làm lại: trả việc cho người, agent dừng
      UPDATE work.tasks SET status = 'todo', agent_id = NULL, updated_at = now() WHERE id = t.id;
      PERFORM agent._notify(t.company_id, t.assignee_id, 'agent_gave_back', 'Agent đã làm lại ' || s.max_rework || ' lần, việc chuyển về bạn', t.id);
    ELSE
      UPDATE work.tasks SET attempts = attempts + 1, status = 'todo', result = NULL, updated_at = now() WHERE id = t.id;
      -- trigger tasks_dispatch tạo thẻ rework; ghi lý do vào payload của thẻ mới
      UPDATE agent.outbox SET payload = payload || jsonb_build_object('rework_reason', NEW.body, 'parent_card_id', c.card_id)
       WHERE id = (SELECT max(id) FROM agent.outbox WHERE task_id = t.id AND kind = 'dispatch');
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER comments_relay AFTER INSERT ON work.comments FOR EACH ROW EXECUTE FUNCTION agent.comments_relay_trg();

-- Cầu nối lấy việc cần đẩy sang Kanban (nhiều cầu nối chạy song song không lấy trùng)
CREATE FUNCTION agent.outbox_pull(p_limit int DEFAULT 20) RETURNS SETOF agent.outbox
LANGUAGE sql SECURITY DEFINER SET search_path = agent, public AS $$
  UPDATE agent.outbox o SET picked_at = now(), tries = tries + 1
   WHERE o.id IN (SELECT id FROM agent.outbox
                   WHERE done_at IS NULL AND tries < 10 AND (picked_at IS NULL OR picked_at < now() - interval '5 minutes')
                   ORDER BY id LIMIT least(p_limit, 100) FOR UPDATE SKIP LOCKED)
  RETURNING o.*
$$;

CREATE FUNCTION agent.outbox_ack(p_id bigint, p_card_id text DEFAULT NULL, p_error text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, public AS $$
DECLARE o agent.outbox;
BEGIN
  SELECT * INTO o FROM agent.outbox WHERE id = p_id FOR UPDATE;
  IF p_error IS NOT NULL THEN
    UPDATE agent.outbox SET error = left(p_error, 1000), picked_at = NULL WHERE id = p_id; RETURN;
  END IF;
  UPDATE agent.outbox SET done_at = now(), error = NULL WHERE id = p_id;
  IF o.kind = 'dispatch' AND p_card_id IS NOT NULL THEN
    UPDATE agent.cards SET card_id = p_card_id, status = 'todo', last_event_at = now(),
           parent_card_id = coalesce(parent_card_id, o.payload->>'parent_card_id')
     WHERE id = o.card_ref;
  END IF;
END $$;

-- Nhận một sự kiện từ Hermes Kanban (hook của plugin eos_bridge hoặc lượt đối soát). Gọi lại nhiều lần vẫn an toàn.
CREATE FUNCTION agent.ingest_event(p_board text, p_card text, p_event text, p_event_key text, p_payload jsonb DEFAULT '{}')
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE c agent.cards; t work.tasks; a agent.agents; ca agent.company_agents; actor text; r_id bigint;
        f jsonb; file_id bigint; summary text;
BEGIN
  SELECT * INTO c FROM agent.cards WHERE board = p_board AND card_id = p_card;
  IF c.id IS NULL THEN RETURN 'unknown_card'; END IF;
  BEGIN
    INSERT INTO agent.events (company_id, card_ref, event, event_key, payload) VALUES (c.company_id, c.id, p_event, p_event_key, p_payload);
  EXCEPTION WHEN unique_violation THEN RETURN 'duplicate';
  END;
  SELECT * INTO a FROM agent.agents WHERE id = c.agent_id;
  actor := 'agent:' || a.code;
  -- lượt đối soát có thể gửi lại sự kiện mà hook đã gửi: thẻ đã ở đúng trạng thái thì không làm lại
  IF (p_event = 'claimed' AND c.status = 'running') OR (p_event = 'blocked' AND c.status = 'blocked')
     OR (p_event = 'completed' AND c.status = 'done') THEN
    RETURN 'no_change';
  END IF;
  summary := coalesce(p_payload->>'summary', p_payload->>'result');
  IF p_event = 'completed' AND (summary IS NULL OR length(summary) < 10) THEN
    -- báo xong mà không có tóm tắt: lỗi giao thức, thẻ và việc giữ nguyên
    IF c.task_id IS NOT NULL THEN
      SELECT * INTO t FROM work.tasks WHERE id = c.task_id;
      PERFORM agent._log(t, actor, a.user_id, 'error', 'Agent báo xong nhưng không có tóm tắt kết quả', 'agent_error');
    END IF;
    RETURN 'missing_summary';
  END IF;
  UPDATE agent.cards SET last_event_at = now(),
         status = CASE p_event WHEN 'claimed' THEN 'running' WHEN 'blocked' THEN 'blocked' WHEN 'review' THEN 'review'
                               WHEN 'completed' THEN 'done' WHEN 'gave_up' THEN 'gave_up' WHEN 'crashed' THEN 'crashed'
                               WHEN 'timed_out' THEN 'timed_out' WHEN 'archived' THEN 'archived' ELSE status END,
         completed_at = CASE WHEN p_event = 'completed' THEN now() ELSE completed_at END
   WHERE id = c.id;
  IF c.task_id IS NULL THEN RETURN 'internal'; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = c.task_id FOR UPDATE;
  IF t.status IN ('done','cancelled') THEN RETURN 'task_closed'; END IF;

  IF p_event = 'claimed' THEN
    UPDATE work.tasks SET status = 'in_progress', claimed_by = actor, claimed_at = now(), updated_at = now() WHERE id = t.id;
    PERFORM agent._log(t, actor, a.user_id, 'claim', a.name || ' đã nhận việc (lượt ' || c.attempt || ')', 'agent_claim');

  ELSIF p_event = 'heartbeat' THEN
    IF (p_payload->>'progress') ~ '^\d{1,3}$' THEN
      UPDATE work.tasks SET progress = least(95, (p_payload->>'progress')::int), updated_at = now() WHERE id = t.id;
    END IF;

  ELSIF p_event = 'comment' THEN
    PERFORM agent._log(t, actor, a.user_id, 'note', coalesce(p_payload->>'body', '(trống)'), 'agent_note');

  ELSIF p_event = 'blocked' THEN
    -- agent hỏi lại người: việc sang Vướng, người phụ trách được báo
    UPDATE work.tasks SET status = 'blocked', waiting_on_human = true, updated_at = now() WHERE id = t.id;
    PERFORM agent._log(t, actor, a.user_id, 'question', coalesce(p_payload->>'reason', 'Agent cần thêm thông tin'), 'agent_ask');
    PERFORM agent._notify(t.company_id, coalesce(t.assignee_id, t.created_by), 'agent_question', a.name || ' hỏi về T-' || t.id, t.id);

  ELSIF p_event = 'completed' THEN
    INSERT INTO agent.reports (company_id, task_id, card_ref, agent_id, summary, outputs, sources, checks, confidence, residual_risk, next_actions)
    VALUES (t.company_id, t.id, c.id, a.id, left(summary, 4000),
            coalesce(p_payload->'outputs', '[]'), coalesce(p_payload->'sources', '[]'), coalesce(p_payload->'checks', '{}'),
            p_payload->>'confidence', p_payload->>'residual_risk', p_payload->>'next_actions')
    RETURNING id INTO r_id;
    -- tệp kết quả: chỉ ghi siêu dữ liệu và link Drive
    FOR f IN SELECT * FROM jsonb_array_elements(coalesce(p_payload->'outputs', '[]')) LOOP
      CONTINUE WHEN f->>'drive_id' IS NULL OR coalesce(f->>'url','') !~ '^https://';
      INSERT INTO core.files (company_id, drive_id, name, mime_type, web_url, owner_user, storage)
      VALUES (t.company_id, f->>'drive_id', coalesce(f->>'name', f->>'drive_id'), f->>'mime', f->>'url', t.assignee_id,
              CASE WHEN t.assignee_id IS NULL THEN 'company' ELSE 'personal' END)
      ON CONFLICT (company_id, drive_id) DO UPDATE SET name = EXCLUDED.name, synced_at = now()
      RETURNING id INTO file_id;
      INSERT INTO core.attachments (company_id, file_id, entity_type, entity_id, role, actor)
      VALUES (t.company_id, file_id, 'task', t.id::text, 'result', actor) ON CONFLICT DO NOTHING;
    END LOOP;
    SELECT * INTO ca FROM agent.company_agents WHERE company_id = t.company_id AND agent_id = a.id;
    IF c.kind <> 'synthesis' AND EXISTS (SELECT 1 FROM work.tasks k WHERE k.parent_id = t.id AND k.source = 'agent' AND k.status NOT IN ('done','cancelled')) THEN
      -- điều phối vừa chia việc: chờ các việc con, việc cha vẫn Đang làm
      UPDATE agent.reports SET verdict = 'auto_done' WHERE id = r_id;
      PERFORM agent._log(t, actor, a.user_id, 'note', 'Đã chia việc con, chờ kết quả: ' || summary, 'agent_delegated');
      RETURN 'waiting_children';
    END IF;
    IF (t.source = 'agent' AND t.parent_id IS NOT NULL AND t.approval_flow_id IS NULL)
       OR (ca.auto_done AND a.max_level <= 1 AND t.approval_flow_id IS NULL) THEN
      -- việc con do agent chia, hoặc agent được tự đóng: Xong luôn; người duyệt bản tổng hợp của việc cha
      UPDATE work.tasks SET status = 'done', completed_at = now(), progress = 100, result = left(summary, 4000), updated_at = now() WHERE id = t.id;
      UPDATE agent.reports SET verdict = 'auto_done' WHERE id = r_id;
      PERFORM agent._log(t, actor, a.user_id, 'result', summary, 'agent_done');
    ELSE
      UPDATE work.tasks SET status = 'in_review', progress = 100, result = left(summary, 4000), updated_at = now() WHERE id = t.id;
      PERFORM agent._log(t, actor, a.user_id, 'submit', summary, 'agent_submit');
      PERFORM agent._notify(t.company_id,
              coalesce(t.created_by, (SELECT default_reviewer FROM agent.company_settings WHERE company_id = t.company_id)),
              'agent_result', a.name || ' đã nộp kết quả T-' || t.id, t.id);
    END IF;

  ELSIF p_event IN ('gave_up','crashed','timed_out') THEN
    UPDATE work.tasks SET status = 'blocked', waiting_on_human = true, updated_at = now() WHERE id = t.id;
    PERFORM agent._log(t, actor, a.user_id, 'error', 'Agent dừng (' || p_event || '): ' || coalesce(p_payload->>'reason', 'không rõ lý do'), 'agent_error');
    PERFORM agent._notify(t.company_id, coalesce(t.assignee_id, t.created_by), 'agent_error', a.name || ' gặp lỗi ở T-' || t.id, t.id);
  END IF;
  RETURN 'ok';
END $$;

-- Agent xin xác nhận (L2). L3 bị từ chối thẳng.
CREATE FUNCTION agent.request_confirmation(p_agent text, p_task bigint, p_action text, p_summary text, p_payload jsonb, p_ask uuid)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE a agent.agents; lv smallint; t work.tasks; new_id bigint;
BEGIN
  SELECT * INTO a FROM agent.agents WHERE code = p_agent AND active;
  SELECT level INTO lv FROM agent.action_levels WHERE action = p_action;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF a.id IS NULL OR lv IS NULL THEN RAISE EXCEPTION 'Agent hoặc hành động không tồn tại'; END IF;
  IF lv = 3 THEN RAISE EXCEPTION 'Hành động % chỉ người làm (L3)', p_action USING ERRCODE = '42501'; END IF;
  IF lv > a.max_level + 1 THEN RAISE EXCEPTION 'Agent % không được xin hành động mức L%', p_agent, lv USING ERRCODE = '42501'; END IF;
  INSERT INTO agent.confirmations (company_id, agent_id, task_id, action, summary, payload, ask_user)
  VALUES (t.company_id, a.id, p_task, p_action, p_summary, p_payload, p_ask) RETURNING id INTO new_id;
  PERFORM agent._notify(t.company_id, p_ask, 'agent_confirm', a.name || ' xin xác nhận: ' || left(p_summary, 120), p_task);
  RETURN new_id;
END $$;

CREATE FUNCTION agent.decide_confirmation(p_id bigint, p_approve boolean, p_note text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE c agent.confirmations; me uuid := core.current_user_id();
BEGIN
  SELECT * INTO c FROM agent.confirmations WHERE id = p_id FOR UPDATE;
  IF c.id IS NULL OR c.state <> 'pending' THEN RETURN 'not_pending'; END IF;
  IF c.ask_user <> me THEN RAISE EXCEPTION 'Chỉ người được hỏi mới xác nhận được' USING ERRCODE = '42501'; END IF;
  IF c.expires_at < now() THEN UPDATE agent.confirmations SET state = 'expired' WHERE id = p_id; RETURN 'expired'; END IF;
  UPDATE agent.confirmations SET state = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
         decided_by = me, decided_at = now(), decision_note = p_note WHERE id = p_id;
  IF c.task_id IS NOT NULL THEN
    INSERT INTO agent.outbox (company_id, kind, task_id, payload)
    VALUES (c.company_id, 'answer', c.task_id,
            jsonb_build_object('confirmation_id', c.id, 'approved', p_approve, 'note', p_note,
                               'card_id', (SELECT card_id FROM agent.cards WHERE task_id = c.task_id ORDER BY attempt DESC, id DESC LIMIT 1),
                               'board', (SELECT board FROM agent.cards WHERE task_id = c.task_id ORDER BY attempt DESC, id DESC LIMIT 1)));
  END IF;
  RETURN CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END;
END $$;

-- ---------- MCP: cấp, kiểm tra, thu hồi mã ----------
CREATE FUNCTION agent.mcp_token_issue(p_name text, p_client text, p_scopes text[], p_days int DEFAULT 90, p_company uuid DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me uuid := core.current_user_id(); raw text;
BEGIN
  IF me IS NULL THEN RAISE EXCEPTION 'Chưa đăng nhập' USING ERRCODE = '42501'; END IF;
  IF (SELECT kind FROM core.users WHERE id = me) <> 'person' THEN RAISE EXCEPTION 'Chỉ người dùng mới tạo mã MCP'; END IF;
  IF (SELECT count(*) FROM agent.mcp_tokens WHERE user_id = me AND revoked_at IS NULL AND expires_at > now()) >= 5 THEN
    RAISE EXCEPTION 'Mỗi người tối đa 5 mã đang dùng. Thu hồi mã cũ trước.';
  END IF;
  raw := 'eos_' || encode(gen_random_bytes(24), 'hex');
  INSERT INTO agent.mcp_tokens (user_id, company_id, name, client, prefix, token_hash, scopes, expires_at)
  VALUES (me, p_company, p_name, p_client, substr(raw, 5, 8), encode(digest(raw, 'sha256'), 'hex'), p_scopes,
          now() + make_interval(days => least(greatest(p_days, 1), 365)));
  RETURN raw;   -- chỉ hiện một lần
END $$;

-- Máy chủ MCP gọi bằng vai trò dịch vụ để đổi mã thành danh tính
CREATE FUNCTION agent.mcp_token_verify(p_raw text, p_ip inet DEFAULT NULL)
RETURNS TABLE (token_id uuid, user_id uuid, company_id uuid, scopes text[], prefix text, agent_id uuid, agent_code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
BEGIN
  RETURN QUERY
  UPDATE agent.mcp_tokens k SET last_used_at = now(), last_ip = coalesce(p_ip, k.last_ip)
    FROM core.users u
   WHERE k.token_hash = encode(digest(p_raw, 'sha256'), 'hex') AND k.revoked_at IS NULL AND k.expires_at > now()
     AND u.id = k.user_id AND u.active
     AND (k.agent_id IS NULL OR EXISTS (SELECT 1 FROM agent.agents g WHERE g.id = k.agent_id AND g.active))
  RETURNING k.id, k.user_id, k.company_id, k.scopes, k.prefix, k.agent_id, (SELECT code FROM agent.agents g WHERE g.id = k.agent_id);
END $$;

CREATE FUNCTION agent.mcp_token_revoke(p_id uuid) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = agent, core, public AS $$
  UPDATE agent.mcp_tokens SET revoked_at = now()
   WHERE id = p_id AND revoked_at IS NULL
     AND (user_id = core.current_user_id() OR (SELECT is_system_admin FROM core.users WHERE id = core.current_user_id()))
  RETURNING true
$$;

-- ---------- MCP: đọc (luôn trong quyền của chính người đó) ----------
CREATE FUNCTION agent.mcp_whoami() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, core, public AS $$
  SELECT jsonb_build_object(
    'user', jsonb_build_object('id', u.id, 'name', u.name, 'email', u.email),
    'drive', jsonb_build_object('state', u.drive_state, 'folder_url', u.drive_folder_url),
    'companies', coalesce((SELECT jsonb_agg(jsonb_build_object(
          'company', c.name, 'slug', c.slug, 'modules', c.modules,
          'department', d.name, 'is_dept_head', m.is_dept_head,
          'roles', (SELECT jsonb_agg(r.name) FROM core.user_roles ur JOIN core.roles r ON r.id = ur.role_id
                     WHERE ur.user_id = u.id AND ur.company_id = c.id)))
        FROM core.memberships m JOIN core.companies c ON c.id = m.company_id
        LEFT JOIN core.departments d ON d.id = m.department_id
       WHERE m.user_id = u.id AND m.active), '[]'))
  FROM core.users u WHERE u.id = core.current_user_id()
$$;

-- p_box: assigned (tôi làm) | created (tôi giao) | watching | review (chờ tôi xem kết quả) | agent_questions
CREATE FUNCTION agent.mcp_my_tasks(p_box text DEFAULT 'assigned', p_status text DEFAULT 'open', p_limit int DEFAULT 30)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'due_date' NULLS LAST), '[]') FROM (
    SELECT jsonb_build_object('id', 'T-' || t.id, 'title', t.title, 'status', t.status, 'priority', t.priority,
             'progress', t.progress, 'due_date', t.due_date, 'company', c.slug,
             'overdue', (t.due_date < current_date AND t.status NOT IN ('done','cancelled')),
             'agent', (SELECT code FROM agent.agents WHERE id = t.agent_id),
             'waiting_on_human', t.waiting_on_human) AS x
      FROM work.tasks t JOIN core.companies c ON c.id = t.company_id
     WHERE CASE p_box
             WHEN 'assigned' THEN t.assignee_id = core.current_user_id()
             WHEN 'created'  THEN t.created_by  = core.current_user_id()
             WHEN 'watching' THEN EXISTS (SELECT 1 FROM work.task_watchers w WHERE w.task_id = t.id AND w.user_id = core.current_user_id())
             WHEN 'review'   THEN t.status = 'in_review' AND t.created_by = core.current_user_id()
             WHEN 'agent_questions' THEN t.waiting_on_human AND (t.assignee_id = core.current_user_id() OR t.created_by = core.current_user_id())
             ELSE false END
       AND CASE p_status WHEN 'open' THEN t.status NOT IN ('done','cancelled') WHEN 'all' THEN true
                         ELSE t.status::text = p_status END
     ORDER BY t.due_date NULLS LAST LIMIT least(p_limit, 100)) s
$$;

CREATE FUNCTION agent.mcp_task(p_task bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); out jsonb;
BEGIN
  IF NOT work.can_view_task(me, p_task) THEN RAISE EXCEPTION 'Không có quyền xem T-%', p_task USING ERRCODE = '42501'; END IF;
  SELECT jsonb_build_object(
    'id', 'T-' || t.id, 'title', t.title, 'description', t.description, 'status', t.status, 'priority', t.priority,
    'progress', t.progress, 'start_date', t.start_date, 'due_date', t.due_date, 'result', t.result,
    'assignee', (SELECT name FROM core.users WHERE id = t.assignee_id),
    'created_by', (SELECT name FROM core.users WHERE id = t.created_by),
    'department', (SELECT name FROM core.departments WHERE id = t.department_id),
    'project', (SELECT name FROM core.projects WHERE id = t.project_id),
    'agent', (SELECT jsonb_build_object('code', code, 'name', name) FROM agent.agents WHERE id = t.agent_id),
    'can_submit', (t.assignee_id = me AND t.status IN ('todo','in_progress','blocked')),
    'checklist', (SELECT coalesce(jsonb_agg(jsonb_build_object('title', title, 'done', done) ORDER BY position), '[]') FROM work.checklist_items WHERE task_id = t.id),
    'comments', (SELECT coalesce(jsonb_agg(jsonb_build_object('at', created_at, 'by', actor, 'kind', kind, 'body', body) ORDER BY created_at), '[]')
                   FROM (SELECT * FROM work.comments WHERE task_id = t.id ORDER BY created_at DESC LIMIT 50) cm),
    'files', (SELECT coalesce(jsonb_agg(jsonb_build_object('name', f.name, 'url', f.web_url, 'role', a.role)), '[]')
                FROM core.attachments a JOIN core.files f ON f.id = a.file_id WHERE a.entity_type = 'task' AND a.entity_id = t.id::text),
    'links', (SELECT coalesce(jsonb_agg(jsonb_build_object('title', title, 'url', url)), '[]') FROM work.task_links WHERE task_id = t.id),
    'parent', CASE WHEN t.parent_id IS NOT NULL THEN 'T-' || t.parent_id END,
    'children', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', 'T-' || k.id, 'title', k.title, 'status', k.status, 'result', k.result,
                   'agent', (SELECT code FROM agent.agents WHERE id = k.agent_id)) ORDER BY k.id), '[]') FROM work.tasks k WHERE k.parent_id = t.id),
    'agent_reports', (SELECT coalesce(jsonb_agg(jsonb_build_object('at', created_at, 'summary', summary, 'outputs', outputs, 'verdict', verdict) ORDER BY created_at DESC), '[]')
                        FROM agent.reports WHERE task_id = t.id))
    INTO out FROM work.tasks t WHERE t.id = p_task;
  RETURN out;
END $$;

-- ---------- MCP: ghi (thay mặt người, mức L1) ----------
CREATE FUNCTION agent._mcp_actor() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT 'user:' || core.current_user_id() || CASE WHEN core.current_via() LIKE 'mcp:%' THEN ' via ' || core.current_via() ELSE '' END
$$;

CREATE FUNCTION agent.mcp_comment(p_task bigint, p_body text, p_kind text DEFAULT 'note') RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); new_id bigint;
BEGIN
  IF NOT work.can_view_task(me, p_task) THEN RAISE EXCEPTION 'Không có quyền với T-%', p_task USING ERRCODE = '42501'; END IF;
  IF p_kind NOT IN ('note','answer') THEN RAISE EXCEPTION 'Loại bình luận không hợp lệ'; END IF;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task, me, agent._mcp_actor(), p_kind::work.comment_kind, p_body)
  RETURNING id INTO new_id;
  RETURN new_id;
END $$;

CREATE FUNCTION agent.mcp_update_progress(p_task bigint, p_progress int, p_note text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); t work.tasks;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task FOR UPDATE;
  IF t.assignee_id IS DISTINCT FROM me THEN RAISE EXCEPTION 'Chỉ người được giao mới cập nhật tiến độ T-%', p_task USING ERRCODE = '42501'; END IF;
  IF t.status NOT IN ('todo','in_progress','blocked') THEN RAISE EXCEPTION 'Việc đang ở trạng thái %, không cập nhật được', t.status; END IF;
  UPDATE work.tasks SET progress = least(greatest(p_progress, 0), 99),
         status = CASE WHEN status = 'todo' THEN 'in_progress' ELSE status END, updated_at = now() WHERE id = p_task;
  IF p_note IS NOT NULL THEN
    INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task, me, agent._mcp_actor(), 'note', 'Tiến độ ' || p_progress || '%: ' || p_note);
  END IF;
  RETURN jsonb_build_object('id', 'T-' || p_task, 'progress', least(greatest(p_progress, 0), 99));
END $$;

-- Đăng ký một tệp đã nằm trong Drive cá nhân (do MCP vừa tải lên, hoặc agent cá nhân tự tạo bằng Drive của nó)
CREATE FUNCTION agent.mcp_register_file(p_task bigint, p_drive_id text, p_name text, p_mime text, p_url text,
                                        p_bytes bigint, p_folder text, p_sha256 text DEFAULT NULL) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); t work.tasks; fid bigint;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF NOT work.can_view_task(me, p_task) THEN RAISE EXCEPTION 'Không có quyền với T-%', p_task USING ERRCODE = '42501'; END IF;
  IF p_url !~ '^https://(drive|docs)\.google\.com/' THEN RAISE EXCEPTION 'Chỉ nhận link Google Drive'; END IF;
  INSERT INTO core.files (company_id, drive_id, name, mime_type, size_bytes, sha256, web_url, owner_user, storage, modified_at)
  VALUES (t.company_id, p_drive_id, p_name, p_mime, p_bytes, p_sha256, p_url, me, 'personal', now())
  ON CONFLICT (company_id, drive_id) DO UPDATE SET name = EXCLUDED.name, size_bytes = EXCLUDED.size_bytes,
         sha256 = EXCLUDED.sha256, modified_at = now(), synced_at = now()
  RETURNING id INTO fid;
  INSERT INTO core.attachments (company_id, file_id, entity_type, entity_id, role, added_by, actor)
  VALUES (t.company_id, fid, 'task', p_task::text, 'result', me, agent._mcp_actor()) ON CONFLICT DO NOTHING;
  INSERT INTO agent.drive_writes (company_id, user_id, file_id, task_id, folder_path, via, bytes)
  VALUES (t.company_id, me, fid, p_task, p_folder, core.current_via(), coalesce(p_bytes, 0));
  RETURN fid;
END $$;

-- Nộp kết quả: có quy trình duyệt → Chờ duyệt; không có → Xong (tính KPI cho người được giao)
CREATE FUNCTION agent.mcp_submit(p_task bigint, p_summary text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); t work.tasks; new_status work.task_status;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task FOR UPDATE;
  IF t.assignee_id IS DISTINCT FROM me THEN RAISE EXCEPTION 'Chỉ người được giao mới nộp kết quả T-%', p_task USING ERRCODE = '42501'; END IF;
  IF t.status NOT IN ('todo','in_progress','blocked') THEN RAISE EXCEPTION 'Việc đang ở trạng thái %, không nộp được', t.status; END IF;
  IF length(btrim(coalesce(p_summary, ''))) < 10 THEN RAISE EXCEPTION 'Tóm tắt kết quả quá ngắn'; END IF;
  new_status := CASE WHEN t.approval_flow_id IS NOT NULL THEN 'in_review' ELSE 'done' END;
  UPDATE work.tasks SET status = new_status, result = left(p_summary, 4000), progress = 100, waiting_on_human = false,
         completed_at = CASE WHEN new_status = 'done' THEN now() END, updated_at = now() WHERE id = p_task;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task, me, agent._mcp_actor(), 'submit', p_summary);
  INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
  VALUES (t.company_id, agent._mcp_actor(), me, 'work', 'submit', 'task', p_task::text, 'Nộp kết quả T-' || p_task || ' qua ' || core.current_via());
  RETURN jsonb_build_object('id', 'T-' || p_task, 'status', new_status);
END $$;

CREATE FUNCTION agent.mcp_log(p_token uuid, p_tool text, p_args jsonb, p_outcome text, p_entity_type text, p_entity_id text, p_ms int)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = agent, public AS $$
  INSERT INTO agent.mcp_calls (token_id, user_id, tool, args, outcome, entity_type, entity_id, ms)
  SELECT p_token, k.user_id, p_tool, p_args, p_outcome, p_entity_type, p_entity_id, p_ms FROM agent.mcp_tokens k WHERE k.id = p_token
$$;

-- ---------- Danh mục mặc định ----------
INSERT INTO agent.action_levels (action, level, name, note) VALUES
 ('work.task.read',          0, 'Đọc việc, bình luận, tệp', NULL),
 ('kb.ask',                  0, 'Hỏi Kho dữ liệu chung', 'chỉ KB người hỏi được xem'),
 ('work.task.comment',       1, 'Ghi bình luận, hỏi lại', NULL),
 ('work.task.progress',      1, 'Cập nhật tiến độ', NULL),
 ('work.task.submit',        1, 'Nộp kết quả việc mình làm', 'kết quả vào Chờ xem/duyệt'),
 ('work.task.create_self',   1, 'Tạo việc con cho chính agent', NULL),
 ('drive.write_personal',    1, 'Ghi tệp vào Drive cá nhân của người giao', NULL),
 ('doc.incoming.draft',      1, 'Điền nháp thông tin công văn đến từ bản scan', 'văn thư xác nhận'),
 ('work.task.assign_other',  2, 'Giao việc cho người khác', NULL),
 ('work.task.change_due',    2, 'Đổi hạn việc của người khác', NULL),
 ('doc.outgoing.draft',      2, 'Soạn công văn đi để trình ký', NULL),
 ('kb.page.propose',         2, 'Đề xuất trang wiki', 'qua quy trình duyệt trang'),
 ('hr.kpi.draft',            2, 'Tính nháp KPI tháng', 'trưởng phòng xem trước khi chốt'),
 ('send.external',           2, 'Gửi email ra ngoài công ty', 'chỉ soạn nháp, người bấm gửi'),
 ('work.approval.decide',    3, 'Duyệt / trả lại', 'chỉ người'),
 ('doc.number.issue',        3, 'Cấp số công văn đi', 'chỉ khi văn bản đã ký'),
 ('hr.payroll.lock',         3, 'Chốt bảng lương', 'chỉ người'),
 ('core.member.role',        3, 'Đổi vai trò, khóa tài khoản', 'chỉ người'),
 ('any.delete',              3, 'Xóa dữ liệu', 'chỉ người');

-- ---------- Người giao chấp nhận hoặc trả lại kết quả của agent ----------
CREATE FUNCTION agent.accept_result(p_task bigint, p_note text DEFAULT NULL) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); t work.tasks;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task FOR UPDATE;
  IF t.status <> 'in_review' OR t.agent_id IS NULL THEN RETURN 'not_in_review'; END IF;
  IF me IS DISTINCT FROM coalesce(t.created_by, (SELECT default_reviewer FROM agent.company_settings WHERE company_id = t.company_id)) THEN
    RAISE EXCEPTION 'Chỉ người giao mới chấp nhận kết quả T-%', p_task USING ERRCODE = '42501';
  END IF;
  UPDATE agent.reports SET verdict = 'accepted' WHERE task_id = p_task AND verdict = 'pending';
  IF t.approval_flow_id IS NOT NULL THEN
    -- còn quy trình duyệt: giữ Chờ duyệt, bước duyệt do core.approval_* xử lý
    INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task, me, 'user:' || me, 'note', coalesce(p_note, 'Đã xem kết quả của agent, chuyển duyệt'));
    RETURN 'to_approval';
  END IF;
  UPDATE work.tasks SET status = 'done', completed_at = now(), updated_at = now() WHERE id = p_task;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task, me, 'user:' || me, 'approve', coalesce(p_note, 'Chấp nhận kết quả'));
  RETURN 'done';
END $$;

CREATE FUNCTION agent.reject_result(p_task bigint, p_reason text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me uuid := core.current_user_id(); t work.tasks;
BEGIN
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF t.status <> 'in_review' OR t.agent_id IS NULL THEN RETURN 'not_in_review'; END IF;
  IF me IS DISTINCT FROM coalesce(t.created_by, (SELECT default_reviewer FROM agent.company_settings WHERE company_id = t.company_id)) THEN
    RAISE EXCEPTION 'Chỉ người giao mới trả lại kết quả T-%', p_task USING ERRCODE = '42501';
  END IF;
  IF length(btrim(coalesce(p_reason, ''))) < 5 THEN RAISE EXCEPTION 'Cần ghi lý do trả lại'; END IF;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body) VALUES (p_task, me, 'user:' || me, 'reject', p_reason);  -- trigger tạo thẻ làm lại
  RETURN (SELECT CASE WHEN agent_id IS NULL THEN 'returned_to_human' ELSE 'rework' END FROM work.tasks WHERE id = p_task);
END $$;

-- ---------- MCP: tìm việc và xem KB được hỏi ----------
CREATE FUNCTION agent.mcp_search(p_q text, p_limit int DEFAULT 20) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', 'T-' || t.id, 'title', t.title, 'status', t.status, 'due_date', t.due_date)), '[]')
    FROM (SELECT * FROM work.tasks t
           WHERE t.search_key LIKE '%' || core.norm(p_q) || '%' AND work.can_view_task(core.current_user_id(), t.id)
           ORDER BY t.updated_at DESC LIMIT least(p_limit, 50)) t
$$;

CREATE FUNCTION agent.mcp_my_kbs() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = kb, core, public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('name', name, 'scope', scope, 'description', description, 'weknora_kb_id', weknora_kb_id)), '[]')
    FROM kb.my_bases_v
$$;

-- ---------- Vai trò cho dịch vụ ----------
-- mcp_svc: máy chủ MCP (đổi mã thành danh tính rồi gọi hàm mcp_* với claims của người đó)
-- agent_bridge: cầu nối Hermes Kanban trên VPS 173
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mcp_svc') THEN CREATE ROLE mcp_svc NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'agent_bridge') THEN CREATE ROLE agent_bridge NOLOGIN; END IF;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA agent FROM PUBLIC;
GRANT USAGE ON SCHEMA agent, core, work TO mcp_svc, agent_bridge;
GRANT EXECUTE ON FUNCTION agent.mcp_token_verify(text, inet), agent.mcp_log(uuid, text, jsonb, text, text, text, int),
  agent.mcp_whoami(), agent.mcp_my_tasks(text, text, int), agent.mcp_task(bigint), agent.mcp_search(text, int), agent.mcp_my_kbs(),
  agent.mcp_comment(bigint, text, text), agent.mcp_update_progress(bigint, int, text),
  agent.mcp_register_file(bigint, text, text, text, text, bigint, text, text), agent.mcp_submit(bigint, text),
  agent.accept_result(bigint, text), agent.reject_result(bigint, text), agent.decide_confirmation(bigint, boolean, text),
  core.current_user_id(), core.current_via()
  TO mcp_svc;
GRANT SELECT (id, drive_folder_id, drive_folder_url, drive_state, name) ON core.users TO mcp_svc;
GRANT EXECUTE ON FUNCTION agent.outbox_pull(int), agent.outbox_ack(bigint, text, text),
  agent.ingest_event(text, text, text, text, jsonb), agent.request_confirmation(text, bigint, text, text, jsonb, uuid)
  TO agent_bridge;

-- Mã MCP cho agent hệ thống (worker đọc chi tiết việc với danh tính agent). Chỉ quản trị hệ thống cấp, chỉ phạm vi đọc.
-- Agent cần membership + vai trò có work.task.view ở công ty để thấy việc. Agent ghi kết quả qua Kanban, không qua MCP.
CREATE FUNCTION agent.mcp_token_issue_agent(p_agent text, p_days int DEFAULT 90) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE a agent.agents; raw text;
BEGIN
  IF NOT coalesce((SELECT is_system_admin FROM core.users WHERE id = core.current_user_id()), false) THEN
    RAISE EXCEPTION 'Chỉ quản trị hệ thống cấp mã cho agent' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO a FROM agent.agents WHERE code = p_agent AND active;
  IF a.id IS NULL THEN RAISE EXCEPTION 'Không có agent %', p_agent; END IF;
  raw := 'eos_' || encode(gen_random_bytes(24), 'hex');
  INSERT INTO agent.mcp_tokens (user_id, agent_id, name, client, prefix, token_hash, scopes, expires_at)
  VALUES (a.user_id, a.id, 'Agent ' || a.code, 'hermes', substr(raw, 5, 8), encode(digest(raw, 'sha256'), 'hex'),
          CASE WHEN a.can_delegate THEN '{read,kb,delegate}'::text[] ELSE '{read,kb}'::text[] END,
          now() + make_interval(days => least(greatest(p_days, 1), 365)));
  RETURN raw;
END $$;

-- =====================================================================
-- Worker agent hệ thống đọc qua MCP và chia việc
-- Máy chủ MCP đặt claims {sub: tài khoản agent, agent: <agent_id>, via: agent:<mã>}.
-- =====================================================================
CREATE FUNCTION agent.current_agent() RETURNS agent.agents LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, public AS $$
  SELECT * FROM agent.agents
   WHERE id = nullif(nullif(current_setting('request.jwt.claims', true), '')::json->>'agent', '')::uuid AND active
$$;

-- Worker chỉ đọc được việc mà nó đang có thẻ chạy (hoặc việc con / việc cha của việc đó),
-- và đọc bằng quyền của người phụ trách: agent không thấy nhiều hơn người giao việc cho nó.
CREATE FUNCTION agent.mcp_agent_task(p_task bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE a agent.agents := agent.current_agent(); t work.tasks; owner uuid;
BEGIN
  IF a.id IS NULL THEN RAISE EXCEPTION 'Chỉ dành cho agent hệ thống' USING ERRCODE = '42501'; END IF;
  SELECT * INTO t FROM work.tasks WHERE id = p_task;
  IF NOT EXISTS (
       SELECT 1 FROM agent.cards c JOIN work.tasks x ON x.id = c.task_id
        WHERE c.agent_id = a.id AND c.status IN ('todo','ready','running','blocked','review')
          AND (x.id = t.id OR x.id = t.parent_id OR x.parent_id = t.id)) THEN
    RAISE EXCEPTION 'Agent % không có thẻ đang chạy cho T-%', a.code, p_task USING ERRCODE = '42501';
  END IF;
  owner := coalesce(t.assignee_id, t.created_by);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', owner, 'via', 'agent:' || a.code, 'agent', a.id)::text, true);
  RETURN agent.mcp_task(p_task);
END $$;

-- Điều phối chia việc: mỗi phần tử {agent, title, description?, after?: [chỉ số phần tử đứng trước]}.
-- Việc con là việc thật trong Enterprise OS (cùng người phụ trách, cùng hạn, không tính KPI).
CREATE FUNCTION agent.delegate(p_parent bigint, p_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE a agent.agents := agent.current_agent(); p work.tasks; it jsonb; i int := 0; ids bigint[] := '{}'; tgt agent.agents;
        dep jsonb; new_id bigint; depth int := 0; anc bigint;
BEGIN
  IF a.id IS NULL OR NOT a.can_delegate THEN RAISE EXCEPTION 'Agent này không được chia việc' USING ERRCODE = '42501'; END IF;
  SELECT * INTO p FROM work.tasks WHERE id = p_parent FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM agent.cards WHERE task_id = p.id AND agent_id = a.id AND status IN ('running','ready','todo')) THEN
    RAISE EXCEPTION 'Agent không có thẻ đang chạy cho T-%', p_parent USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 8 THEN
    RAISE EXCEPTION 'Chia từ 1 đến 8 việc con';
  END IF;
  anc := p.parent_id;
  WHILE anc IS NOT NULL LOOP depth := depth + 1; SELECT parent_id INTO anc FROM work.tasks WHERE id = anc; END LOOP;
  IF depth >= 2 THEN RAISE EXCEPTION 'Tối đa 2 tầng việc con'; END IF;
  IF EXISTS (SELECT 1 FROM work.tasks WHERE parent_id = p.id AND source = 'agent' AND status NOT IN ('done','cancelled')) THEN
    RAISE EXCEPTION 'T-% đang có việc con chưa xong', p_parent;
  END IF;
  -- tạo việc con (chưa gắn agent, để thứ tự được ghi trước khi đưa vào hộp thư đi)
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO tgt FROM agent.agents g
     WHERE g.code = it->>'agent' AND g.active
       AND EXISTS (SELECT 1 FROM agent.company_agents ca WHERE ca.company_id = p.company_id AND ca.agent_id = g.id AND ca.enabled);
    IF tgt.id IS NULL THEN RAISE EXCEPTION 'Agent % chưa bật cho công ty', it->>'agent'; END IF;
    IF tgt.id = a.id THEN RAISE EXCEPTION 'Không tự giao việc con cho chính mình'; END IF;
    INSERT INTO work.tasks (company_id, department_id, project_id, parent_id, source, title, description, priority,
                            assignee_id, due_date, kpi_counted, created_by, created_by_agent)
    VALUES (p.company_id, p.department_id, p.project_id, p.id, 'agent', left(it->>'title', 300), left(it->>'description', 8000), p.priority,
            p.assignee_id, p.due_date, false, p.created_by, a.code)
    RETURNING id INTO new_id;
    ids := ids || new_id;
  END LOOP;
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    i := i + 1;
    FOR dep IN SELECT * FROM jsonb_array_elements(coalesce(it->'after', '[]')) LOOP
      IF (dep::text)::int NOT BETWEEN 0 AND array_length(ids, 1) - 1 OR (dep::text)::int = i - 1 THEN
        RAISE EXCEPTION 'after không hợp lệ ở việc con thứ %', i;
      END IF;
      INSERT INTO agent.task_deps (task_id, after_task_id) VALUES (ids[i], ids[(dep::text)::int + 1]) ON CONFLICT DO NOTHING;
    END LOOP;
  END LOOP;
  i := 0;
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    i := i + 1;
    UPDATE work.tasks SET agent_id = (SELECT id FROM agent.agents WHERE code = it->>'agent'),
                          agent_role = nullif(it->>'skill', '') WHERE id = ids[i];   -- trigger đưa vào hộp thư đi nếu không phải chờ
  END LOOP;
  INSERT INTO work.comments (task_id, user_id, actor, kind, body)
  VALUES (p.id, a.user_id, 'agent:' || a.code, 'note',
          'Chia ' || array_length(ids, 1) || ' việc con: ' || (SELECT string_agg('T-' || x, ', ') FROM unnest(ids) x));
  RETURN jsonb_build_object('parent', 'T-' || p.id, 'children', (SELECT jsonb_agg('T-' || x) FROM unnest(ids) x));
END $$;

-- =====================================================================
-- MCP cho người: thêm công cụ đọc
-- =====================================================================
-- Yêu cầu đang chờ chính người dùng duyệt ở bước hiện tại (chỉ đọc; duyệt làm trên web)
CREATE FUNCTION agent.mcp_approvals_pending() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('request', v.id, 'kind', v.entity_type, 'ref', v.entity_id, 'title', v.title,
           'step', v.step_name, 'since', v.requested_at) ORDER BY v.requested_at), '[]')
    FROM core.approval_inbox_v v
   WHERE v.approver_user = core.current_user_id()
      OR (v.approver_kind = 'role' AND EXISTS (SELECT 1 FROM core.user_roles ur WHERE ur.user_id = core.current_user_id()
                                                AND ur.company_id = v.company_id AND ur.role_id = v.approver_role))
      OR (v.approver_kind = 'dept_head' AND EXISTS (SELECT 1 FROM core.memberships m WHERE m.user_id = core.current_user_id()
                                                AND m.company_id = v.company_id AND m.is_dept_head AND m.department_id = v.department_id))
$$;

CREATE FUNCTION agent.mcp_my_day() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, work, core, public AS $$
  WITH me AS (SELECT core.current_user_id() AS id, (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date AS today)
  SELECT jsonb_build_object(
    'today', me.today,
    'overdue', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', 'T-' || id, 'title', title, 'due_date', due_date) ORDER BY due_date), '[]')
                  FROM work.tasks WHERE assignee_id = me.id AND status NOT IN ('done','cancelled','in_review') AND due_date < me.today),
    'due_today', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', 'T-' || id, 'title', title)), '[]')
                  FROM work.tasks WHERE assignee_id = me.id AND status NOT IN ('done','cancelled','in_review') AND due_date = me.today),
    'next_7_days', (SELECT count(*) FROM work.tasks WHERE assignee_id = me.id AND status NOT IN ('done','cancelled') AND due_date BETWEEN me.today + 1 AND me.today + 7),
    'agent_questions', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', 'T-' || id, 'title', title)), '[]')
                  FROM work.tasks WHERE waiting_on_human AND status = 'blocked' AND (assignee_id = me.id OR created_by = me.id)),
    'agent_results_to_review', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', 'T-' || id, 'title', title)), '[]')
                  FROM work.tasks WHERE status = 'in_review' AND agent_id IS NOT NULL AND created_by = me.id),
    'agent_confirmations', (SELECT count(*) FROM agent.confirmations WHERE ask_user = me.id AND state = 'pending' AND expires_at > now()),
    'approvals_waiting', jsonb_array_length(agent.mcp_approvals_pending()))
  FROM me
$$;

-- Công văn đến người dùng được xem: mình xử lý, phòng mình, hoặc có quyền doc.incoming.view.
-- Văn bản mật chỉ trả số, ngày, độ mật — không trả trích yếu, nơi gửi hay tệp.
CREATE FUNCTION agent._can_view_incoming(p_user uuid, i doc.incoming) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = doc, core, public AS $$
  SELECT EXISTS (SELECT 1 FROM core.memberships m WHERE m.user_id = p_user AND m.company_id = i.company_id AND m.active AND (
           i.handler_id = p_user
        OR (i.department_id IS NOT NULL AND i.department_id = m.department_id)
        OR core.perm_scope_of(p_user, i.company_id, 'doc.incoming.view') = 'company'))
$$;

CREATE FUNCTION agent.mcp_incoming(p_box text DEFAULT 'mine', p_limit int DEFAULT 30) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, doc, core, public AS $$
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'deadline' NULLS LAST), '[]') FROM (
    SELECT CASE WHEN v.secrecy <> 'normal'
             THEN jsonb_build_object('id', v.id, 'number', v.number, 'received_on', v.received_on, 'secret', true)
             ELSE jsonb_build_object('id', v.id, 'number', v.number, 'received_on', v.received_on, 'ref_number', v.ref_number,
                    'sender', v.sender_name, 'summary', v.summary, 'deadline', v.deadline, 'status', v.status_label,
                    'task', CASE WHEN v.task_id IS NOT NULL THEN 'T-' || v.task_id END) END AS x
      FROM doc.incoming_v v JOIN doc.incoming i ON i.id = v.id
     WHERE agent._can_view_incoming(core.current_user_id(), i)
       AND CASE p_box WHEN 'mine' THEN v.handler_id = core.current_user_id() AND v.status_code NOT IN ('done','done_late','cancelled')
                      WHEN 'open' THEN v.status_code NOT IN ('done','done_late','cancelled','info')
                      WHEN 'overdue' THEN v.status_code = 'overdue'
                      ELSE true END
     ORDER BY v.deadline NULLS LAST LIMIT least(p_limit, 100)) s
$$;

-- ---------- Nhân sự của chính mình (phạm vi hr_self) ----------
CREATE FUNCTION agent.mcp_my_hr(p_what text, p_month date DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = agent, hr, core, public AS $$
DECLARE e hr.employees; m date := date_trunc('month', coalesce(p_month, (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date))::date;
BEGIN
  SELECT * INTO e FROM hr.employees WHERE user_id = core.current_user_id() ORDER BY hire_date DESC LIMIT 1;
  IF e.id IS NULL THEN RAISE EXCEPTION 'Bạn chưa có hồ sơ nhân viên'; END IF;
  IF p_what = 'attendance' THEN
    RETURN jsonb_build_object('month', to_char(m, 'YYYY-MM'),
      'days', (SELECT coalesce(jsonb_agg(jsonb_build_object('date', work_date, 'status', status, 'in', to_char(first_in AT TIME ZONE 'Asia/Ho_Chi_Minh', 'HH24:MI'),
                 'out', to_char(last_out AT TIME ZONE 'Asia/Ho_Chi_Minh', 'HH24:MI'), 'late_min', late_minutes, 'work', work_value) ORDER BY work_date), '[]')
                 FROM hr.attendance_days WHERE employee_id = e.id AND work_date >= m AND work_date < m + interval '1 month'),
      'total_work', (SELECT coalesce(sum(work_value), 0) FROM hr.attendance_days WHERE employee_id = e.id AND work_date >= m AND work_date < m + interval '1 month'));
  ELSIF p_what = 'leave' THEN
    RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('year', year, 'entitled', entitled + carried_over + adjusted, 'used', used,
                   'pending', pending, 'remaining', remaining)), '[]') FROM hr.leave_balance_v WHERE employee_id = e.id AND year >= extract(year FROM m) - 1);
  ELSIF p_what = 'kpi' THEN
    RETURN (SELECT jsonb_build_object('period', to_char(period, 'YYYY-MM'), 'state', state, 'tasks', tasks_total, 'on_time', done_on_time,
                   'late', done_late, 'not_done', not_done, 'pending', pending, 'score', score, 'adjustment', adjustment,
                   'final_score', final_score, 'grade', grade,
                   'items', (SELECT coalesce(jsonb_agg(jsonb_build_object('task', 'T-' || i.task_id, 'outcome', i.outcome, 'points', i.points, 'weight', i.weight)), '[]')
                               FROM hr.kpi_items i WHERE i.score_id = k.id))
              FROM hr.kpi_scores k WHERE employee_id = e.id AND period = m);
  END IF;
  RAISE EXCEPTION 'p_what phải là attendance, leave hoặc kpi';
END $$;

GRANT EXECUTE ON FUNCTION agent.mcp_agent_task(bigint), agent.delegate(bigint, jsonb), agent.mcp_my_day(), agent.mcp_approvals_pending(),
  agent.mcp_incoming(text, int), agent.mcp_my_hr(text, date) TO mcp_svc;
