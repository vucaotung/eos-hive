-- =====================================================================
-- Enterprise OS — 10 Công việc (schema work)
-- Việc, việc con, việc lặp lại, bình luận, liên kết, người theo dõi, đề nghị.
-- Dự án nằm ở core.projects; duyệt dùng core.approval_*.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS work;
SET search_path = work, core, public;

CREATE TYPE work.task_status   AS ENUM ('todo','in_progress','blocked','in_review','done','cancelled');
CREATE TYPE work.task_priority AS ENUM ('low','medium','high','urgent');          -- Thấp, Trung bình, Cao, Khẩn cấp
CREATE TYPE work.comment_kind  AS ENUM ('note','question','answer','result','submit','approve','reject','claim','error','system');

-- Mẫu việc lặp lại (Tần suất: hằng ngày, hằng tuần, hằng tháng)
CREATE TABLE work.recurrences (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  title         text NOT NULL,
  description   text,
  department_id uuid REFERENCES core.departments(id) ON DELETE SET NULL,
  project_id    uuid REFERENCES core.projects(id) ON DELETE SET NULL,
  assignee_id   uuid REFERENCES core.users(id),
  priority      work.task_priority NOT NULL DEFAULT 'medium',
  kpi_weight    numeric(4,2),
  freq          text NOT NULL CHECK (freq IN ('daily','weekly','monthly')),
  interval_n    int  NOT NULL DEFAULT 1 CHECK (interval_n BETWEEN 1 AND 12),
  weekdays      int[],                              -- ISO 1..7, cho hằng tuần
  month_day     int CHECK (month_day BETWEEN 1 AND 31),   -- cho hằng tháng; 31 = ngày cuối tháng
  due_offset    int NOT NULL DEFAULT 0 CHECK (due_offset BETWEEN 0 AND 60),  -- hạn = ngày tạo + n ngày
  skip_holidays boolean NOT NULL DEFAULT true,
  next_run      date NOT NULL,
  until_date    date,
  active        boolean NOT NULL DEFAULT true,
  created_by    uuid REFERENCES core.users(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE work.tasks (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id       uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  department_id    uuid REFERENCES core.departments(id) ON DELETE SET NULL,
  project_id       uuid REFERENCES core.projects(id) ON DELETE SET NULL,
  parent_id        bigint REFERENCES work.tasks(id) ON DELETE SET NULL,
  recurrence_id    uuid REFERENCES work.recurrences(id) ON DELETE SET NULL,
  source           text NOT NULL DEFAULT 'manual'
                   CHECK (source IN ('manual','recurrence','incoming_doc','outgoing_doc','crm','agent','hr')),
  title            text NOT NULL CHECK (length(btrim(title)) BETWEEN 2 AND 300),
  description      text CHECK (length(description) <= 8000),
  status           work.task_status   NOT NULL DEFAULT 'todo',
  priority         work.task_priority NOT NULL DEFAULT 'medium',
  progress         int NOT NULL DEFAULT 0 CHECK (progress BETWEEN 0 AND 100),
  assignee_id      uuid REFERENCES core.users(id),
  agent_role       text CHECK (agent_role ~ '^[a-z-]{2,32}$'),
  waiting_on_human boolean NOT NULL DEFAULT false,
  start_date       date,
  due_date         date,
  est_minutes      int CHECK (est_minutes IS NULL OR est_minutes BETWEEN 1 AND 43200),   -- thời lượng ước tính (phút)
  completed_at     timestamptz,
  result           text CHECK (length(result) <= 4000),       -- Kết quả
  -- KPI
  important        boolean NOT NULL DEFAULT false,  -- ma trận Eisenhower: quan trọng
  urgent           boolean NOT NULL DEFAULT false,  -- ma trận Eisenhower: khẩn cấp
  kpi_counted      boolean NOT NULL DEFAULT true,   -- có tính vào KPI tháng không
  kpi_weight       numeric(4,2) CHECK (kpi_weight BETWEEN 0 AND 10),   -- NULL = theo mức ưu tiên
  kpi_confirmed_by uuid REFERENCES core.users(id),  -- trưởng phòng xác nhận việc tự giao cho mình
  -- duyệt & agent
  approval_flow_id uuid REFERENCES core.approval_flows(id) ON DELETE SET NULL,
  attempts         int NOT NULL DEFAULT 0,
  claimed_by       text,
  claimed_at       timestamptz,
  created_by       uuid REFERENCES core.users(id),
  created_by_agent text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  search_key       text GENERATED ALWAYS AS (core.norm(title || ' ' || coalesce(description,''))) STORED,
  CHECK (due_date IS NULL OR start_date IS NULL OR due_date >= start_date),
  CHECK ((status = 'done') = (completed_at IS NOT NULL))
);
CREATE INDEX tasks_company_status_idx ON work.tasks (company_id, status, due_date);
CREATE INDEX tasks_assignee_idx ON work.tasks (assignee_id, status) WHERE status NOT IN ('done','cancelled');
CREATE INDEX tasks_project_idx ON work.tasks (project_id);
CREATE INDEX tasks_kpi_idx ON work.tasks (company_id, assignee_id, due_date) WHERE kpi_counted;
CREATE INDEX tasks_search_idx ON work.tasks USING gin (search_key gin_trgm_ops);

CREATE TABLE work.checklist_items (                  -- Việc con dạng đánh dấu
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  task_id     bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  position    int NOT NULL,
  title       text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 300),
  done        boolean NOT NULL DEFAULT false,
  done_by     uuid REFERENCES core.users(id),
  done_at     timestamptz,
  UNIQUE (task_id, position)
);

-- Mẫu checklist của công ty (vd. "Hồ sơ đất đai"): chèn vào việc bằng agent.app_checklist_apply
CREATE TABLE work.checklist_templates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 120),
  items       text[] NOT NULL CHECK (cardinality(items) BETWEEN 1 AND 50),
  uses        int NOT NULL DEFAULT 0,
  created_by  uuid REFERENCES core.users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, name)
);

CREATE TABLE work.task_watchers (
  task_id     bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  PRIMARY KEY (task_id, user_id)
);

CREATE TABLE work.comments (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  task_id     bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  user_id     uuid REFERENCES core.users(id),
  actor       text NOT NULL,
  kind        work.comment_kind NOT NULL DEFAULT 'note',
  body        text NOT NULL CHECK (length(body) BETWEEN 1 AND 8000),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX comments_task_idx ON work.comments (task_id, created_at);

CREATE TABLE work.task_links (                      -- Link kết quả
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  task_id     bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  url         text NOT NULL CHECK (url ~ '^https://'),
  title       text NOT NULL,
  added_by    uuid REFERENCES core.users(id),
  actor       text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Việc liên quan tới bản ghi ở phân hệ khác (khách hàng, hồ sơ, nhân viên...)
CREATE TABLE work.task_relations (
  task_id     bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  entity_type text NOT NULL CHECK (entity_type IN ('incoming_doc','outgoing_doc','record','customer','deal','employee')),
  entity_id   text NOT NULL,
  PRIMARY KEY (task_id, entity_type, entity_id)
);

-- Đề nghị (chi phí, công tác, thay đổi quy trình...) đi qua core.approval_*
CREATE TABLE work.proposal_types (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,                        -- Đề nghị chi phí, Đề nghị công tác
  has_amount  boolean NOT NULL DEFAULT false,
  flow_id     uuid REFERENCES core.approval_flows(id),
  active      boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, name)
);

CREATE TABLE work.proposals (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  code          text NOT NULL,                      -- DN001, cấp theo công ty
  type_id       uuid NOT NULL REFERENCES work.proposal_types(id),
  in_plan       boolean NOT NULL DEFAULT true,      -- Trong / Ngoài kế hoạch
  project_id    uuid REFERENCES core.projects(id) ON DELETE SET NULL,
  task_id       bigint REFERENCES work.tasks(id) ON DELETE SET NULL,
  department_id uuid REFERENCES core.departments(id),
  title         text NOT NULL,
  content       text NOT NULL CHECK (length(content) <= 8000),
  amount        bigint CHECK (amount >= 0),
  state         core.approval_state NOT NULL DEFAULT 'draft',
  approval_id   bigint REFERENCES core.approval_requests(id),
  note          text,
  requested_by  uuid NOT NULL REFERENCES core.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, code)
);
