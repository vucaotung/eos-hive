-- =====================================================================
-- Enterprise OS — 40 CRM (schema crm) — dựng ở giai đoạn sau
-- Khách hàng, giai đoạn, nguồn, khu vực, hoạt động chăm sóc & cuộc gọi, cơ hội, chỉ tiêu.
-- Khách doanh nghiệp nối core.organizations; việc chăm sóc tạo work.tasks (source = 'crm').
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS crm;
SET search_path = crm, core, public;

CREATE TABLE crm.stages (                           -- trạng thái khách: Khách hàng mới ... Đã chốt, Không quan tâm
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,
  color       text NOT NULL CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
  sort        int NOT NULL,
  outcome     text NOT NULL DEFAULT 'open' CHECK (outcome IN ('open','won','lost')),
  active      boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, name)
);

CREATE TABLE crm.sources (                          -- nguồn khách: Facebook, Website, Zalo OA...
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,
  description text,
  active      boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, name)
);

CREATE TABLE crm.regions (                          -- khu vực
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,
  description text,
  UNIQUE (company_id, name)
);

CREATE TABLE crm.customers (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id       uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  code             text,                            -- KH000123
  kind             text NOT NULL DEFAULT 'person' CHECK (kind IN ('person','business')),
  name             text NOT NULL,
  phone            text,
  phone_norm       text GENERATED ALWAYS AS (regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g')) STORED,
  email            text,
  address          text,
  org_id           uuid REFERENCES core.organizations(id),   -- khách doanh nghiệp
  region_id        uuid REFERENCES crm.regions(id),
  source_id        uuid REFERENCES crm.sources(id),
  stage_id         uuid NOT NULL REFERENCES crm.stages(id),
  owner_id         uuid REFERENCES core.users(id),           -- người phụ trách
  department_id    uuid REFERENCES core.departments(id),
  tags             text[] NOT NULL DEFAULT '{}',
  notes            text,
  first_contact_on date NOT NULL DEFAULT current_date,       -- ngày tạo
  last_activity_at timestamptz,
  next_follow_up   date,
  search_key       text GENERATED ALWAYS AS (core.norm(coalesce(code,'') || ' ' || name || ' ' || coalesce(phone,'') || ' ' || coalesce(email,''))) STORED,
  created_by       uuid REFERENCES core.users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX customers_phone_uq ON crm.customers (company_id, phone_norm) WHERE phone_norm <> '';
CREATE INDEX customers_owner_idx ON crm.customers (company_id, owner_id, stage_id);
CREATE INDEX customers_followup_idx ON crm.customers (company_id, next_follow_up);
CREATE INDEX customers_search_idx ON crm.customers USING gin (search_key gin_trgm_ops);

CREATE TABLE crm.activities (                       -- lịch sử chăm sóc + cuộc gọi (thay hai cột JSON)
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  customer_id   bigint NOT NULL REFERENCES crm.customers(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES core.users(id),
  kind          text NOT NULL CHECK (kind IN ('call','meeting','zalo','email','quote','note','visit')),
  at            timestamptz NOT NULL DEFAULT now(),
  duration_sec  int CHECK (duration_sec >= 0),
  call_result   text CHECK (call_result IN ('answered','no_answer','busy','wrong_number','callback')),
  content       text CHECK (length(content) <= 4000),
  stage_from    uuid REFERENCES crm.stages(id),
  stage_to      uuid REFERENCES crm.stages(id),
  next_follow_up date,
  task_id       bigint REFERENCES work.tasks(id) ON DELETE SET NULL   -- việc hẹn gọi lại
);
CREATE INDEX activities_customer_idx ON crm.activities (customer_id, at DESC);
CREATE INDEX activities_user_idx ON crm.activities (company_id, user_id, at);

CREATE TABLE crm.deals (                            -- cơ hội / báo giá
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  customer_id   bigint NOT NULL REFERENCES crm.customers(id) ON DELETE CASCADE,
  title         text NOT NULL,
  value         bigint CHECK (value >= 0),
  stage_id      uuid NOT NULL REFERENCES crm.stages(id),
  owner_id      uuid REFERENCES core.users(id),
  project_id    uuid REFERENCES core.projects(id),
  expected_close date,
  closed_on     date,
  lost_reason   text,
  record_id     bigint REFERENCES doc.records(id),  -- hợp đồng khi chốt
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE crm.targets (                          -- chỉ tiêu tháng: số cuộc gọi, lần chăm sóc, khách mới
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  period          date NOT NULL CHECK (extract(day FROM period) = 1),
  calls           int NOT NULL DEFAULT 0,
  care_actions    int NOT NULL DEFAULT 0,
  new_customers   int NOT NULL DEFAULT 0,
  revenue         bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (company_id, user_id, period)
);
