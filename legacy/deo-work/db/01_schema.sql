-- Dẹo Work — cơ sở dữ liệu siêu dữ liệu công việc, nhiều công ty, nhiều phòng ban.
-- Nguyên tắc: chỉ lưu SIÊU DỮ LIỆU (ai, việc gì, trạng thái, hạn, ai duyệt, link).
-- Tài liệu và nội dung làm việc nằm trong thư mục Google Drive của từng người; ở đây chỉ có link và tên tệp.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS app;
SET search_path = app, public;

CREATE TYPE member_role   AS ENUM ('owner','admin','manager','member');
CREATE TYPE task_status   AS ENUM ('todo','in_progress','blocked','in_review','done','cancelled');
CREATE TYPE task_priority AS ENUM ('low','medium','high','urgent');
CREATE TYPE comment_kind  AS ENUM ('note','question','answer','result','submit','approve','reject','claim','error','system');
CREATE TYPE decision      AS ENUM ('pending','approved','rejected','skipped');
CREATE TYPE drive_state   AS ENUM ('none','pending','ok','error');

-- ===== Tổ chức =====
CREATE TABLE companies (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text UNIQUE NOT NULL CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE departments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  code        text NOT NULL CHECK (code ~ '^[A-Za-z0-9_-]{1,12}$'),
  name        text NOT NULL,
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, code)
);

CREATE TABLE users (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  google_sub       text UNIQUE NOT NULL,
  email            text NOT NULL,
  name             text NOT NULL,
  avatar_url       text,
  is_system_admin  boolean NOT NULL DEFAULT false,
  active           boolean NOT NULL DEFAULT true,
  -- Thư mục Drive cá nhân (người dùng tạo, chia sẻ quyền Editor cho tài khoản agent)
  drive_folder_url text,
  drive_folder_id  text,
  drive_status     drive_state NOT NULL DEFAULT 'none',
  drive_note       text,
  drive_checked_at timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  last_login_at    timestamptz
);

CREATE TABLE memberships (
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  company_id    uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  department_id uuid REFERENCES departments(id) ON DELETE SET NULL,
  role          member_role NOT NULL DEFAULT 'member',
  title         text,
  active        boolean NOT NULL DEFAULT true,
  joined_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, company_id)
);
CREATE INDEX memberships_company_idx ON memberships (company_id, department_id) WHERE active;

CREATE TABLE invites (
  code          text PRIMARY KEY CHECK (code ~ '^[A-Z0-9]{8}$'),
  company_id    uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  department_id uuid REFERENCES departments(id) ON DELETE SET NULL,
  role          member_role NOT NULL DEFAULT 'member',
  email         text,                      -- nếu đặt: chỉ email này dùng được
  note          text,
  max_uses      int  NOT NULL DEFAULT 1 CHECK (max_uses BETWEEN 1 AND 200),
  uses          int  NOT NULL DEFAULT 0,
  expires_at    timestamptz NOT NULL,
  revoked       boolean NOT NULL DEFAULT false,
  created_by    uuid REFERENCES users(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ===== Dự án và việc =====
CREATE TABLE projects (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  department_id uuid REFERENCES departments(id) ON DELETE SET NULL,
  slug          text NOT NULL CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name          text NOT NULL,
  drive_url     text,
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, slug)
);

CREATE TABLE approval_flows (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  department_id uuid REFERENCES departments(id) ON DELETE CASCADE,  -- NULL: dùng chung cả công ty
  name          text NOT NULL,
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Mỗi bước: người duyệt theo vai trò (trưởng phòng của phòng ban của việc / admin / owner) hoặc một người cụ thể
CREATE TABLE approval_steps (
  flow_id       uuid NOT NULL REFERENCES approval_flows(id) ON DELETE CASCADE,
  step_no       int  NOT NULL CHECK (step_no BETWEEN 1 AND 6),
  name          text NOT NULL,
  approver_role member_role,
  approver_user uuid REFERENCES users(id),
  PRIMARY KEY (flow_id, step_no),
  CHECK ((approver_role IS NULL) <> (approver_user IS NULL)),
  CHECK (approver_role IS NULL OR approver_role <> 'member')
);

CREATE TABLE tasks (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id       uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  department_id    uuid REFERENCES departments(id) ON DELETE SET NULL,
  project_id       uuid REFERENCES projects(id) ON DELETE SET NULL,
  parent_id        bigint REFERENCES tasks(id) ON DELETE SET NULL,
  title            text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 300),
  description      text CHECK (length(description) <= 8000),
  status           task_status   NOT NULL DEFAULT 'todo',
  priority         task_priority NOT NULL DEFAULT 'medium',
  assignee_id      uuid REFERENCES users(id),
  agent_role       text CHECK (agent_role ~ '^[a-z-]{2,32}$'),   -- giao cho agent: tra-cuu, phap-che, ...
  waiting_on_human boolean NOT NULL DEFAULT false,
  due_date         date,
  approval_flow_id uuid REFERENCES approval_flows(id) ON DELETE SET NULL,
  current_step     int,
  attempts         int NOT NULL DEFAULT 0,
  created_by       uuid REFERENCES users(id),
  created_by_agent text,
  claimed_by       text,
  claimed_at       timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  completed_at     timestamptz
);
CREATE INDEX tasks_company_status_idx ON tasks (company_id, status);
CREATE INDEX tasks_dept_idx     ON tasks (department_id, status);
CREATE INDEX tasks_assignee_idx ON tasks (assignee_id, status);
CREATE INDEX tasks_agent_queue  ON tasks (agent_role, priority, created_at)
  WHERE status = 'todo' AND agent_role IS NOT NULL AND NOT waiting_on_human;

CREATE TABLE approvals (
  task_id     bigint NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  round       int    NOT NULL DEFAULT 1,
  step_no     int    NOT NULL,
  step_name   text   NOT NULL,
  approver_role member_role,
  approver_user uuid REFERENCES users(id),
  decision    decision NOT NULL DEFAULT 'pending',
  decided_by  uuid REFERENCES users(id),
  decided_at  timestamptz,
  note        text,
  PRIMARY KEY (task_id, round, step_no)
);

CREATE TABLE comments (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  task_id     bigint NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  user_id     uuid REFERENCES users(id),
  actor       text NOT NULL,                 -- 'user:<uuid>' | 'agent:<vai-trò>'
  kind        comment_kind NOT NULL DEFAULT 'note',
  body        text NOT NULL CHECK (length(body) BETWEEN 1 AND 8000),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX comments_task_idx ON comments (task_id, created_at);

-- Tệp đính kèm = link tới Drive (không lưu tệp)
CREATE TABLE task_links (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  task_id     bigint NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  url         text NOT NULL CHECK (url ~ '^https://'),
  title       text NOT NULL,
  added_by    uuid REFERENCES users(id),
  actor       text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Danh mục tệp trong thư mục Drive của từng người, do agent quét (chỉ siêu dữ liệu)
CREATE TABLE drive_files (
  file_id     text PRIMARY KEY,
  owner_user  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        text NOT NULL,
  mime_type   text,
  web_url     text NOT NULL,
  size_bytes  bigint,
  modified_at timestamptz,
  task_id     bigint REFERENCES tasks(id) ON DELETE SET NULL,   -- agent gắn tệp vào việc (vd tên bắt đầu "T-123")
  synced_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX drive_files_task_idx ON drive_files (task_id);

-- Nhật ký thay đổi
CREATE TABLE task_events (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  task_id    bigint NOT NULL,
  actor      text NOT NULL,
  field      text NOT NULL,
  old_value  text,
  new_value  text,
  at         timestamptz NOT NULL DEFAULT now()
);

-- ===== Hàm ngữ cảnh =====
CREATE FUNCTION jwt_claim(k text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('request.jwt.claims', true), '')::json->>k
$$;
CREATE FUNCTION uid() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN jwt_claim('role') = 'app_user' THEN jwt_claim('sub')::uuid END
$$;
CREATE FUNCTION actor() RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE jwt_claim('role')
    WHEN 'app_user' THEN 'user:' || jwt_claim('sub')
    WHEN 'agent'    THEN coalesce(jwt_claim('sub'), 'agent')
    ELSE current_user END
$$;
CREATE FUNCTION is_agent() RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT coalesce(jwt_claim('role') = 'agent', false)
$$;

-- Vai trò của người đang đăng nhập trong một công ty (NULL nếu không phải thành viên)
CREATE FUNCTION my_role(c uuid) RETURNS member_role LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT m.role FROM memberships m JOIN users u ON u.id = m.user_id
   WHERE m.user_id = uid() AND m.company_id = c AND m.active AND u.active
$$;
CREATE FUNCTION my_dept(c uuid) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT m.department_id FROM memberships m WHERE m.user_id = uid() AND m.company_id = c AND m.active
$$;
CREATE FUNCTION my_companies() RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT m.company_id FROM memberships m JOIN users u ON u.id = m.user_id
   WHERE m.user_id = uid() AND m.active AND u.active
$$;

-- Người đang đăng nhập có duyệt được bước đang chờ của việc này không
CREATE FUNCTION can_approve(t tasks) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT EXISTS (
    SELECT 1 FROM approvals a
     WHERE a.task_id = t.id AND a.round = t.attempts + 1 AND a.step_no = t.current_step AND a.decision = 'pending'
       AND t.status = 'in_review'
       AND (
         a.approver_user = uid()
         OR (a.approver_role = 'manager' AND (
               (my_role(t.company_id) = 'manager' AND my_dept(t.company_id) IS NOT DISTINCT FROM t.department_id)
               OR (my_role(t.company_id) IN ('admin','owner') AND NOT EXISTS (
                     SELECT 1 FROM memberships mm WHERE mm.company_id = t.company_id AND mm.active AND mm.role = 'manager'
                        AND mm.department_id IS NOT DISTINCT FROM t.department_id))))
         OR (a.approver_role = 'admin' AND my_role(t.company_id) IN ('admin','owner'))
         OR (a.approver_role = 'owner' AND my_role(t.company_id) = 'owner')
       )
  )
$$;

-- Ai thấy được việc: admin/owner thấy cả công ty; người khác thấy việc của phòng mình, việc mình giao/được giao, việc mình phải duyệt
CREATE FUNCTION can_see(t tasks) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT is_agent() OR (
    my_role(t.company_id) IS NOT NULL AND (
      my_role(t.company_id) IN ('admin','owner')
      OR t.department_id IS NOT DISTINCT FROM my_dept(t.company_id)
      OR t.assignee_id = uid() OR t.created_by = uid()
      OR can_approve(t)
    ))
$$;

-- Ai sửa được việc
CREATE FUNCTION can_edit(t tasks) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = app, public AS $$
  SELECT is_agent() OR (
    my_role(t.company_id) IS NOT NULL AND (
      my_role(t.company_id) IN ('admin','owner')
      OR t.assignee_id = uid() OR t.created_by = uid()
      OR (my_role(t.company_id) = 'manager' AND t.department_id IS NOT DISTINCT FROM my_dept(t.company_id))
    ))
$$;

-- updated_at + nhật ký
CREATE FUNCTION trg_tasks_touch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  IF NEW.status = 'done' AND OLD.status <> 'done' THEN NEW.completed_at := now(); END IF;
  IF NEW.status <> 'done' THEN NEW.completed_at := NULL; END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO task_events(task_id, actor, field, old_value, new_value) VALUES (NEW.id, actor(), 'status', OLD.status::text, NEW.status::text);
  END IF;
  IF NEW.assignee_id IS DISTINCT FROM OLD.assignee_id THEN
    INSERT INTO task_events(task_id, actor, field, old_value, new_value) VALUES (NEW.id, actor(), 'assignee_id', OLD.assignee_id::text, NEW.assignee_id::text);
  END IF;
  IF NEW.due_date IS DISTINCT FROM OLD.due_date THEN
    INSERT INTO task_events(task_id, actor, field, old_value, new_value) VALUES (NEW.id, actor(), 'due_date', OLD.due_date::text, NEW.due_date::text);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tasks_touch BEFORE UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION trg_tasks_touch();
