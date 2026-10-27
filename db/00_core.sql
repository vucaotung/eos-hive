-- =====================================================================
-- Enterprise OS — 00 Nền tảng (schema core)
-- Tổ chức, người dùng, vai trò & quyền, duyệt nhiều cấp, tệp, nhật ký,
-- thông báo, đối tác, dự án, ngày nghỉ, ứng dụng.
-- Quy ước: uuid cho dữ liệu danh mục; bigint identity cho dữ liệu phát sinh nhiều.
-- Tiền: bigint, đơn vị đồng. Ngày giờ: timestamptz; ngày: date (giờ Việt Nam).
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE SCHEMA IF NOT EXISTS core;
SET search_path = core, public;

-- Chữ không dấu, chữ thường: dùng cho cột tìm kiếm
CREATE FUNCTION core.norm(t text) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT lower(regexp_replace(public.unaccent('public.unaccent'::regdictionary, coalesce(t,'')), '\s+', ' ', 'g'))
$$;

-- ---------- Kiểu dùng chung ----------
CREATE TYPE core.perm_scope    AS ENUM ('own','department','company');
CREATE TYPE core.approval_state AS ENUM ('draft','pending','approved','rejected','cancelled');
CREATE TYPE core.decision      AS ENUM ('pending','approved','rejected','skipped');
CREATE TYPE core.drive_state   AS ENUM ('none','pending','ok','error');
CREATE TYPE core.org_kind      AS ENUM ('supplier','customer','agency','partner');

-- ---------- Tổ chức ----------
CREATE TABLE core.companies (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text UNIQUE NOT NULL CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name        text NOT NULL,                       -- Công ty Cổ phần 5Balance
  short_name  text,
  tax_code    text,
  address     text,
  phone       text,
  logo_url    text,
  timezone    text NOT NULL DEFAULT 'Asia/Ho_Chi_Minh',
  modules     text[] NOT NULL DEFAULT '{work}',    -- phân hệ đã bật: work, doc, hr, crm
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE core.departments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  parent_id   uuid REFERENCES core.departments(id) ON DELETE SET NULL,   -- cây phòng ban
  code        text NOT NULL CHECK (code ~ '^[A-Za-z0-9_-]{1,12}$'),
  doc_abbr    text CHECK (doc_abbr ~ '^[A-Za-zĐđ0-9]{1,12}$'),           -- viết tắt trong ký hiệu văn bản (LĐ)
  name        text NOT NULL,
  description text,
  active      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, code),
  UNIQUE (company_id, id)
);

CREATE TABLE core.positions (                       -- chức vụ
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,                       -- Trưởng phòng, Nhân viên
  level       int  NOT NULL DEFAULT 50 CHECK (level BETWEEN 0 AND 100),  -- 100 = cao nhất
  active      boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, name)
);

-- ---------- Người dùng (tài khoản đăng nhập Google) ----------
CREATE TABLE core.users (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  google_sub       text UNIQUE,                     -- NULL với tài khoản thiết bị (kiosk)
  email            text NOT NULL,
  name             text NOT NULL,
  avatar_url       text,
  phone            text,
  kind             text NOT NULL DEFAULT 'person' CHECK (kind IN ('person','device','agent')),
  is_system_admin  boolean NOT NULL DEFAULT false,
  telegram_chat_id text,
  drive_folder_id  text,                            -- thư mục Drive cá nhân (đã có trong Dẹo Work)
  drive_folder_url text,
  drive_state      core.drive_state NOT NULL DEFAULT 'none',
  drive_note       text,
  drive_checked_at timestamptz,
  active           boolean NOT NULL DEFAULT true,
  created_at       timestamptz NOT NULL DEFAULT now(),
  last_login_at    timestamptz
);
CREATE UNIQUE INDEX users_email_uq ON core.users (lower(email));

-- Thành viên công ty: ai thuộc công ty nào, phòng nào, chức vụ gì
CREATE TABLE core.memberships (
  user_id       uuid NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  department_id uuid REFERENCES core.departments(id) ON DELETE SET NULL,
  position_id   uuid REFERENCES core.positions(id) ON DELETE SET NULL,
  is_dept_head  boolean NOT NULL DEFAULT false,      -- trưởng phòng của department_id
  title         text,
  active        boolean NOT NULL DEFAULT true,
  joined_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, company_id)
);
CREATE INDEX memberships_company_idx ON core.memberships (company_id, department_id);

CREATE TABLE core.invites (
  code          text PRIMARY KEY CHECK (code ~ '^[A-Z0-9]{8}$'),
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  department_id uuid REFERENCES core.departments(id) ON DELETE SET NULL,
  role_ids      uuid[] NOT NULL DEFAULT '{}',        -- vai trò gán khi nhận lời mời
  email         text,
  note          text,
  max_uses      int  NOT NULL DEFAULT 1 CHECK (max_uses BETWEEN 1 AND 200),
  uses          int  NOT NULL DEFAULT 0,
  expires_at    timestamptz NOT NULL,
  revoked       boolean NOT NULL DEFAULT false,
  created_by    uuid REFERENCES core.users(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ---------- Vai trò & quyền ----------
-- Quyền là danh mục cố định do hệ thống định nghĩa (seed), nhóm theo khu việc.
CREATE TABLE core.permissions (
  code        text PRIMARY KEY CHECK (code ~ '^[a-z]+(\.[a-z_]+)+$'),   -- hr.payroll.run
  module      text NOT NULL CHECK (module IN ('core','work','doc','hr','crm','kb','agent')),
  area        text NOT NULL,                       -- khu việc hiện trên thẻ vai trò: Nhân sự, Lương, Báo cáo...
  name        text NOT NULL,
  scoped      boolean NOT NULL DEFAULT true,       -- có phân phạm vi own/department/company
  sort        int NOT NULL DEFAULT 100
);

CREATE TABLE core.roles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid REFERENCES core.companies(id) ON DELETE CASCADE,  -- NULL = vai trò mẫu của hệ thống
  code        text NOT NULL CHECK (code ~ '^[a-z_]{2,32}$'),
  name        text NOT NULL,
  description text,
  builtin     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX roles_code_uq ON core.roles (coalesce(company_id,'00000000-0000-0000-0000-000000000000'::uuid), code);

CREATE TABLE core.role_permissions (
  role_id     uuid NOT NULL REFERENCES core.roles(id) ON DELETE CASCADE,
  permission  text NOT NULL REFERENCES core.permissions(code) ON DELETE CASCADE,
  scope       core.perm_scope NOT NULL DEFAULT 'company',
  PRIMARY KEY (role_id, permission)
);

CREATE TABLE core.user_roles (                      -- một người mang nhiều vai trò
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  role_id     uuid NOT NULL REFERENCES core.roles(id) ON DELETE CASCADE,
  granted_by  uuid REFERENCES core.users(id),
  granted_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (company_id, user_id, role_id)
);

-- ---------- Cấu hình chung theo khóa ----------
CREATE TABLE core.settings (
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  key         text NOT NULL CHECK (key ~ '^[a-z]+(\.[a-zA-Z_]+)+$'),   -- work.remindDays
  value       jsonb NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid REFERENCES core.users(id),
  PRIMARY KEY (company_id, key)
);

-- ---------- Lịch: ngày nghỉ lễ, ngày làm bù (dùng chung công văn & nhân sự) ----------
CREATE TABLE core.holidays (
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  day         date NOT NULL,
  kind        text NOT NULL CHECK (kind IN ('holiday','makeup')),   -- nghỉ lễ | làm bù
  name        text NOT NULL,
  paid        boolean NOT NULL DEFAULT true,       -- nghỉ lễ có hưởng lương
  PRIMARY KEY (company_id, day)
);

-- ---------- Đối tác: nhà cung cấp, khách hàng doanh nghiệp, cơ quan gửi/nhận công văn ----------
CREATE TABLE core.organizations (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id     uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  kinds          core.org_kind[] NOT NULL DEFAULT '{partner}',
  short_name     text,                              -- HB
  name           text NOT NULL,                     -- Công ty CP Xây dựng Hòa Bình
  tax_code       text,
  address        text,
  phone          text,
  email          text,
  representative text,
  bank_name      text,
  bank_account   text,
  industry       text,
  notes          text,
  search_key     text GENERATED ALWAYS AS (core.norm(coalesce(short_name,'') || ' ' || name || ' ' || coalesce(tax_code,''))) STORED,
  use_count      int NOT NULL DEFAULT 0,            -- xếp gợi ý khi gõ
  active         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX organizations_search_idx ON core.organizations USING gin (search_key gin_trgm_ops);
CREATE UNIQUE INDEX organizations_tax_uq ON core.organizations (company_id, tax_code) WHERE tax_code IS NOT NULL;

-- ---------- Dự án (dùng bởi việc, tài liệu, CRM, đề nghị) ----------
CREATE TABLE core.projects (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  department_id uuid REFERENCES core.departments(id) ON DELETE SET NULL,
  code          text NOT NULL CHECK (code ~ '^[A-Za-z0-9_-]{2,20}$'),   -- DA001, GP
  slug          text NOT NULL CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name          text NOT NULL,
  description   text,
  address       text,
  manager_id    uuid REFERENCES core.users(id),
  client_org_id uuid REFERENCES core.organizations(id),
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('planned','active','paused','done','cancelled')),
  start_date    date,
  end_date      date,
  budget        bigint CHECK (budget >= 0),
  drive_url     text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, code),
  UNIQUE (company_id, slug),
  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

CREATE TABLE core.project_members (
  project_id  uuid NOT NULL REFERENCES core.projects(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  role        text NOT NULL DEFAULT 'member' CHECK (role IN ('manager','member','viewer')),
  PRIMARY KEY (project_id, user_id)
);

-- ---------- Duyệt nhiều cấp: một bộ máy cho việc, đề nghị, đơn từ, văn bản đi, lương ----------
CREATE TABLE core.approval_flows (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  applies_to    text NOT NULL CHECK (applies_to IN ('task','proposal','hr_request','outgoing_doc','payroll','any')),
  department_id uuid REFERENCES core.departments(id) ON DELETE CASCADE,  -- NULL: cả công ty
  name          text NOT NULL,
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE core.approval_steps (
  flow_id        uuid NOT NULL REFERENCES core.approval_flows(id) ON DELETE CASCADE,
  step_no        int  NOT NULL CHECK (step_no BETWEEN 1 AND 6),
  name           text NOT NULL,                     -- Trưởng phòng duyệt
  approver_kind  text NOT NULL CHECK (approver_kind IN ('dept_head','role','user','project_manager','creator')),
  approver_role  uuid REFERENCES core.roles(id),
  approver_user  uuid REFERENCES core.users(id),
  PRIMARY KEY (flow_id, step_no),
  CHECK (approver_kind <> 'role' OR approver_role IS NOT NULL),
  CHECK (approver_kind <> 'user' OR approver_user IS NOT NULL)
);

CREATE TABLE core.approval_requests (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  flow_id       uuid NOT NULL REFERENCES core.approval_flows(id),
  entity_type   text NOT NULL CHECK (entity_type IN ('task','proposal','hr_request','outgoing_doc','payroll')),
  entity_id     bigint NOT NULL,
  title         text NOT NULL,                      -- hiện trong hộp "Chờ tôi duyệt"
  department_id uuid REFERENCES core.departments(id),
  state         core.approval_state NOT NULL DEFAULT 'pending',
  round         int NOT NULL DEFAULT 1,             -- trả lại rồi nộp lại thì sang vòng mới
  current_step  int,
  requested_by  uuid REFERENCES core.users(id),
  requested_at  timestamptz NOT NULL DEFAULT now(),
  closed_at     timestamptz
);
CREATE UNIQUE INDEX approval_open_uq ON core.approval_requests (entity_type, entity_id) WHERE state = 'pending';
CREATE INDEX approval_inbox_idx ON core.approval_requests (company_id, state, current_step);

CREATE TABLE core.approval_decisions (
  request_id    bigint NOT NULL REFERENCES core.approval_requests(id) ON DELETE CASCADE,
  round         int  NOT NULL,
  step_no       int  NOT NULL,
  step_name     text NOT NULL,
  decision      core.decision NOT NULL DEFAULT 'pending',
  approver_user uuid REFERENCES core.users(id),     -- người được chỉ định (nếu có)
  decided_by    uuid REFERENCES core.users(id),
  decided_at    timestamptz,
  note          text,
  PRIMARY KEY (request_id, round, step_no)
);

-- ---------- Tệp: chỉ siêu dữ liệu, nội dung nằm trên Google Drive ----------
CREATE TABLE core.files (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  drive_id    text NOT NULL,                        -- file id trên Drive
  name        text NOT NULL,
  mime_type   text,
  size_bytes  bigint,
  sha256      text,
  web_url     text NOT NULL CHECK (web_url ~ '^https://'),
  owner_user  uuid REFERENCES core.users(id),       -- tệp nằm trong Drive của ai (nếu là thư mục cá nhân)
  storage     text NOT NULL DEFAULT 'company' CHECK (storage IN ('company','personal')),
  modified_at timestamptz,
  synced_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, drive_id)
);
CREATE INDEX files_sha_idx ON core.files (company_id, sha256);

-- Gắn tệp vào bất kỳ bản ghi nào (đa hình, kiểm tra loại bằng CHECK; tồn tại bản ghi do trigger từng phân hệ)
CREATE TABLE core.attachments (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  file_id     bigint NOT NULL REFERENCES core.files(id) ON DELETE CASCADE,
  entity_type text NOT NULL CHECK (entity_type IN
               ('task','proposal','incoming_doc','outgoing_doc','record','employee','contract','hr_request','payslip','customer','deal','punch')),
  entity_id   text NOT NULL,
  role        text NOT NULL DEFAULT 'attachment',   -- scan, signed, draft, appendix, photo, payslip_pdf...
  added_by    uuid REFERENCES core.users(id),
  actor       text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (file_id, entity_type, entity_id)
);
CREATE INDEX attachments_entity_idx ON core.attachments (entity_type, entity_id);

-- ---------- Nhật ký hệ thống: ai sửa gì, lúc nào (thay task_events, vb_nhat_ky) ----------
CREATE TABLE core.audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  at          timestamptz NOT NULL DEFAULT now(),
  company_id  uuid NOT NULL,
  actor       text NOT NULL,                        -- user:<uuid> | agent:<vai-trò> | system
  user_id     uuid,
  module      text NOT NULL,
  action      text NOT NULL,                        -- create, update, approve, number_issued, payroll_lock...
  entity_type text NOT NULL,
  entity_id   text NOT NULL,
  summary     text NOT NULL,                        -- "Tạo phiếu lương 2026-10 · Nguyễn Minh Anh"
  changes     jsonb,                                -- {field: [cũ, mới]}
  PRIMARY KEY (at, id)
) PARTITION BY RANGE (at);
CREATE TABLE core.audit_log_2026 PARTITION OF core.audit_log FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
CREATE TABLE core.audit_log_2027 PARTITION OF core.audit_log FOR VALUES FROM ('2027-01-01') TO ('2028-01-01');
CREATE INDEX audit_entity_idx ON core.audit_log (entity_type, entity_id, at DESC);
CREATE INDEX audit_company_idx ON core.audit_log (company_id, at DESC);

-- ---------- Thông báo (chuông trên thanh trên cùng) ----------
CREATE TABLE core.notifications (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
  kind        text NOT NULL,                        -- task_assigned, approval_waiting, deadline, payslip_published...
  title       text NOT NULL,
  body        text,
  link        text,                                 -- đường dẫn trong app: #/hr/payslips/123
  entity_type text,
  entity_id   text,
  actor       text,                                 -- user:<uuid> | agent:<mã> | system (ai làm ra sự kiện)
  is_ai       boolean NOT NULL DEFAULT false,       -- sự kiện do agent AI tạo (hiện nhãn AI, lọc "Từ AI")
  created_at  timestamptz NOT NULL DEFAULT now(),
  read_at     timestamptz,
  sent_email_at    timestamptz,
  sent_telegram_at timestamptz
);
CREATE INDEX notifications_unread_idx ON core.notifications (user_id, created_at DESC) WHERE read_at IS NULL;

-- ---------- Ứng dụng liên kết (màn Quản lý App) ----------
CREATE TABLE core.apps (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  group_name  text NOT NULL,                        -- Kế toán, Nhân sự, Tài chính
  name        text NOT NULL,
  description text,
  url         text NOT NULL CHECK (url ~ '^https://'),
  icon        text,
  color       text CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
  sort        int NOT NULL DEFAULT 100,
  visible_to  text NOT NULL DEFAULT 'all' CHECK (visible_to IN ('all','listed')),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE core.app_access (
  app_id      uuid NOT NULL REFERENCES core.apps(id) ON DELETE CASCADE,
  user_id     uuid REFERENCES core.users(id) ON DELETE CASCADE,
  role_id     uuid REFERENCES core.roles(id) ON DELETE CASCADE,
  CHECK ((user_id IS NULL) <> (role_id IS NULL))
);
CREATE UNIQUE INDEX app_access_uq ON core.app_access (app_id, coalesce(user_id, role_id));

-- ---------- Hàm lịch: cộng N ngày làm việc (bỏ cuối tuần & ngày lễ, tính ngày làm bù) ----------
CREATE FUNCTION core.is_workday(p_company uuid, p_day date, p_weekend int[] DEFAULT '{6,7}')
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM core.holidays h WHERE h.company_id = p_company AND h.day = p_day AND h.kind = 'makeup') THEN true
    WHEN EXISTS (SELECT 1 FROM core.holidays h WHERE h.company_id = p_company AND h.day = p_day AND h.kind = 'holiday') THEN false
    ELSE NOT (extract(isodow FROM p_day)::int = ANY (p_weekend)) END
$$;

CREATE FUNCTION core.add_workdays(p_company uuid, p_from date, p_n int, p_weekend int[] DEFAULT '{6,7}')
RETURNS date LANGUAGE plpgsql STABLE AS $$
DECLARE d date := p_from; left_n int := p_n;
BEGIN
  IF p_n <= 0 THEN RETURN p_from; END IF;
  WHILE left_n > 0 LOOP
    d := d + 1;
    IF core.is_workday(p_company, d, p_weekend) THEN left_n := left_n - 1; END IF;
  END LOOP;
  RETURN d;
END $$;

CREATE FUNCTION core.count_workdays(p_company uuid, p_from date, p_to date, p_weekend int[] DEFAULT '{6,7}')
RETURNS int LANGUAGE sql STABLE AS $$
  SELECT count(*)::int FROM generate_series(p_from, p_to, interval '1 day') g(d)
   WHERE core.is_workday(p_company, g.d::date, p_weekend)
$$;
