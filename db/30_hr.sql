-- =====================================================================
-- Enterprise OS — 30 Nhân sự (schema hr)
-- Hồ sơ nhân viên, hợp đồng, biến động; địa điểm, ca, mẫu lịch, xếp ca;
-- chấm công (GPS, QR, máy, từ xa, chấm hộ); công ngày; đơn từ; phép năm; kỳ công & bảng công.
-- Lương và KPI ở 31_payroll_kpi.sql.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS hr;
SET search_path = hr, core, public;

CREATE TYPE hr.emp_status AS ENUM ('probation','official','suspended','resigned');   -- thử việc, chính thức, tạm nghỉ, đã nghỉ
CREATE TYPE hr.punch_method AS ENUM ('gps','qr','device','remote','proxy','import');
CREATE TYPE hr.day_status AS ENUM ('full','late','early','late_early','absent','leave','holiday','off','missing_punch','remote','business_trip');

-- ---------- Hồ sơ nhân viên ----------
CREATE TABLE hr.employees (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  user_id          uuid REFERENCES core.users(id) ON DELETE SET NULL,   -- tài khoản đăng nhập (có thể chưa có)
  code             text NOT NULL CHECK (code ~ '^[A-Za-z0-9_-]{2,20}$'),  -- NV0009
  full_name        text NOT NULL,
  gender           text CHECK (gender IN ('male','female','other')),
  birth_date       date,
  phone            text,
  personal_email   text,
  work_email       text,
  address          text,
  department_id    uuid REFERENCES core.departments(id) ON DELETE SET NULL,
  position_id      uuid REFERENCES core.positions(id) ON DELETE SET NULL,
  manager_id       uuid REFERENCES hr.employees(id) ON DELETE SET NULL,
  status           hr.emp_status NOT NULL DEFAULT 'probation',
  hire_date        date NOT NULL,
  probation_end    date,
  official_date    date,
  leave_date       date,
  leave_reason     text,
  location_id      uuid,                            -- nơi làm việc mặc định (FK thêm sau)
  -- dữ liệu nhạy cảm: chỉ vai trò có quyền hr.employee.sensitive mới đọc (view che cột)
  id_number        text,                            -- CCCD
  tax_code         text,
  insurance_no     text,
  bank_name        text,
  bank_account     text,
  dependents       int NOT NULL DEFAULT 0 CHECK (dependents BETWEEN 0 AND 20),   -- người phụ thuộc (giảm trừ thuế)
  avatar_url       text,
  notes            text,
  search_key       text GENERATED ALWAYS AS (core.norm(code || ' ' || full_name || ' ' || coalesce(work_email,'') || ' ' || coalesce(phone,''))) STORED,
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, code),
  CHECK (leave_date IS NULL OR leave_date >= hire_date)
);
CREATE UNIQUE INDEX employees_user_uq ON hr.employees (company_id, user_id) WHERE user_id IS NOT NULL;
CREATE INDEX employees_dept_idx ON hr.employees (company_id, department_id, status);
CREATE INDEX employees_search_idx ON hr.employees USING gin (search_key gin_trgm_ops);

CREATE TABLE hr.contracts (                         -- hợp đồng lao động
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  employee_id      uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  contract_no      text NOT NULL,
  kind             text NOT NULL CHECK (kind IN ('probation','fixed_term','indefinite','service','seasonal')),
  start_date       date NOT NULL,
  end_date         date,
  signed_on        date,
  base_salary      bigint NOT NULL CHECK (base_salary >= 0),
  insurance_salary bigint CHECK (insurance_salary >= 0),     -- lương đóng BHXH
  salary_ratio     numeric(5,2) NOT NULL DEFAULT 100 CHECK (salary_ratio BETWEEN 0 AND 100),  -- % lương thử việc
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','ended','terminated')),
  note             text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, contract_no),
  CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE TABLE hr.lifecycle_events (                  -- nhận việc, điều chuyển, tăng lương, khen thưởng, kỷ luật, nghỉ việc
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  employee_id   uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  kind          text NOT NULL CHECK (kind IN ('onboard','transfer','promotion','salary_change','reward','discipline','offboard')),
  effective_on  date NOT NULL,
  before_value  jsonb,
  after_value   jsonb,
  note          text,
  created_by    uuid REFERENCES core.users(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE hr.onboarding_items (                  -- danh sách việc khi nhận / tiễn nhân viên
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employee_id   uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  phase         text NOT NULL CHECK (phase IN ('onboard','offboard')),
  title         text NOT NULL,                      -- Cấp laptop, Thu hồi thẻ
  owner_id      uuid REFERENCES core.users(id),
  due_date      date,
  done_at       timestamptz,
  done_by       uuid REFERENCES core.users(id)
);

-- ---------- Địa điểm, ca, lịch ----------
CREATE TABLE hr.locations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,                        -- Văn phòng chính
  address     text,
  lat         numeric(9,6),
  lng         numeric(9,6),
  radius_m    int NOT NULL DEFAULT 150 CHECK (radius_m BETWEEN 20 AND 5000),
  qr_secret   text NOT NULL DEFAULT encode(gen_random_bytes(16),'hex'),  -- sinh mã QR đổi mỗi 45 giây
  active      boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, name)
);
ALTER TABLE hr.employees ADD FOREIGN KEY (location_id) REFERENCES hr.locations(id) ON DELETE SET NULL;

CREATE TABLE hr.shifts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  code            text NOT NULL CHECK (code ~ '^[A-Za-z0-9_-]{1,12}$'),
  name            text NOT NULL,                    -- Hành chính, Sáng, Chiều, Đêm, Ca gãy
  start_time      time NOT NULL,
  end_time        time NOT NULL,                    -- nhỏ hơn start_time = qua đêm
  break_minutes   int NOT NULL DEFAULT 0 CHECK (break_minutes BETWEEN 0 AND 240),
  work_value      numeric(3,2) NOT NULL DEFAULT 1 CHECK (work_value BETWEEN 0 AND 2),   -- số công của ca
  late_grace_min  int NOT NULL DEFAULT 5,
  early_grace_min int NOT NULL DEFAULT 5,
  night_shift     boolean NOT NULL DEFAULT false,
  color           text CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
  active          boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, code)
);

CREATE TABLE hr.schedule_templates (                -- mẫu lịch lặp lại theo tuần
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,
  pattern     jsonb NOT NULL,                       -- {"1":"<shift_id>", ..., "6":null, "7":null}
  UNIQUE (company_id, name)
);

CREATE TABLE hr.schedules (                         -- xếp ca: mỗi người mỗi ngày một ca
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  work_date   date NOT NULL,
  shift_id    uuid NOT NULL REFERENCES hr.shifts(id),
  location_id uuid REFERENCES hr.locations(id),
  note        text,
  set_by      uuid REFERENCES core.users(id),
  set_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (employee_id, work_date)
);
CREATE INDEX schedules_company_day_idx ON hr.schedules (company_id, work_date);

-- ---------- Chấm công ----------
CREATE TABLE hr.attendance_settings (
  company_id        uuid PRIMARY KEY REFERENCES core.companies(id) ON DELETE CASCADE,
  gps_enabled       boolean NOT NULL DEFAULT true,
  require_photo     boolean NOT NULL DEFAULT true,
  qr_screen         boolean NOT NULL DEFAULT true,  -- màn hình tại cửa, mã đổi mỗi 45 giây
  qr_printed        boolean NOT NULL DEFAULT false, -- mã in dán cửa (nên kèm GPS)
  qr_manager_scan   boolean NOT NULL DEFAULT false, -- quản lý quét mã trên máy nhân viên
  remote_enabled    boolean NOT NULL DEFAULT false,
  device_enabled    boolean NOT NULL DEFAULT false, -- máy vân tay / khuôn mặt đẩy dữ liệu
  proxy_enabled     boolean NOT NULL DEFAULT true,  -- quản lý chấm hộ, bắt buộc lý do
  qr_rotate_sec     int NOT NULL DEFAULT 45,
  max_gps_accuracy_m int NOT NULL DEFAULT 100,
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE hr.devices (                           -- máy chấm công, màn hình QR (kiosk)
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  location_id uuid REFERENCES hr.locations(id),
  kind        text NOT NULL CHECK (kind IN ('qr_kiosk','fingerprint','face')),
  name        text NOT NULL,
  user_id     uuid REFERENCES core.users(id),       -- tài khoản kind='device' của máy
  api_key_hash text,
  last_seen_at timestamptz,
  active      boolean NOT NULL DEFAULT true
);

CREATE TABLE hr.punches (                           -- lượt chấm thô, không sửa, không xóa
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  employee_id   uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  at            timestamptz NOT NULL,
  direction     text NOT NULL CHECK (direction IN ('in','out')),
  method        hr.punch_method NOT NULL,
  location_id   uuid REFERENCES hr.locations(id),
  lat           numeric(9,6),
  lng           numeric(9,6),
  accuracy_m    int,
  distance_m    int,                                -- cách tâm địa điểm
  in_range      boolean,
  photo_file_id bigint REFERENCES core.files(id),   -- ảnh lúc chấm, lưu Drive công ty
  device_id     uuid REFERENCES hr.devices(id),
  proxy_by      uuid REFERENCES core.users(id),     -- người chấm hộ
  reason        text,                               -- bắt buộc khi chấm hộ / từ xa
  work_note     text,                               -- đang làm việc gì (chấm từ xa)
  valid         boolean NOT NULL DEFAULT true,      -- false khi ngoài vùng, mã QR hết hạn...
  invalid_reason text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (method <> 'proxy' OR (proxy_by IS NOT NULL AND reason IS NOT NULL))
);
CREATE INDEX punches_emp_idx ON hr.punches (employee_id, at);
CREATE INDEX punches_company_idx ON hr.punches (company_id, at);

CREATE TABLE hr.attendance_days (                   -- công ngày: tính từ lượt chấm + ca + đơn từ
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  employee_id     uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  work_date       date NOT NULL,
  shift_id        uuid REFERENCES hr.shifts(id),
  first_in        timestamptz,
  last_out        timestamptz,
  late_minutes    int NOT NULL DEFAULT 0,
  early_minutes   int NOT NULL DEFAULT 0,
  worked_minutes  int NOT NULL DEFAULT 0,
  work_value      numeric(3,2) NOT NULL DEFAULT 0,  -- công thực tế của ngày
  leave_value     numeric(3,2) NOT NULL DEFAULT 0,  -- phần ngày nghỉ có phép
  ot_minutes      int NOT NULL DEFAULT 0,
  ot_kind         text CHECK (ot_kind IN ('weekday','weekend','holiday','night')),
  status          hr.day_status NOT NULL,
  request_id      bigint,                           -- đơn từ đã áp vào ngày này
  adjusted        boolean NOT NULL DEFAULT false,
  adjust_reason   text,
  adjusted_by     uuid REFERENCES core.users(id),
  computed_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (employee_id, work_date),
  CHECK (NOT adjusted OR adjust_reason IS NOT NULL)
);
CREATE INDEX attendance_days_company_idx ON hr.attendance_days (company_id, work_date);

-- ---------- Đơn từ & phép năm ----------
CREATE TABLE hr.request_types (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  code          text NOT NULL CHECK (code ~ '^[a-z_]{2,30}$'),
  name          text NOT NULL,                      -- Nghỉ phép, Nghỉ ốm, Công tác, Đăng ký tăng ca, Bổ sung chấm công
  effect        text NOT NULL CHECK (effect IN ('paid_leave','unpaid_leave','sick_leave','business_trip','overtime','punch_fix','remote','late_early')),
  uses_balance  boolean NOT NULL DEFAULT false,     -- trừ phép năm
  unit          text NOT NULL DEFAULT 'day' CHECK (unit IN ('day','half_day','hour')),
  needs_file    boolean NOT NULL DEFAULT false,
  flow_id       uuid REFERENCES core.approval_flows(id),
  active        boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, code)
);

CREATE TABLE hr.requests (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  employee_id   uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  type_id       uuid NOT NULL REFERENCES hr.request_types(id),
  start_at      timestamptz NOT NULL,
  end_at        timestamptz NOT NULL,
  days          numeric(5,2),                       -- số ngày (trừ ngày nghỉ) hệ thống tính
  hours         numeric(6,2),
  reason        text NOT NULL CHECK (length(btrim(reason)) BETWEEN 2 AND 1000),
  punch_time    timestamptz,                        -- giờ cần bổ sung (punch_fix)
  state         core.approval_state NOT NULL DEFAULT 'pending',
  approval_id   bigint REFERENCES core.approval_requests(id),
  created_by    uuid REFERENCES core.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (end_at >= start_at)
);
CREATE INDEX requests_emp_idx ON hr.requests (employee_id, start_at);
ALTER TABLE hr.attendance_days ADD FOREIGN KEY (request_id) REFERENCES hr.requests(id) ON DELETE SET NULL;

CREATE TABLE hr.leave_policies (
  company_id        uuid PRIMARY KEY REFERENCES core.companies(id) ON DELETE CASCADE,
  base_days         numeric(4,1) NOT NULL DEFAULT 12,
  seniority_years   int NOT NULL DEFAULT 5,          -- cứ 5 năm thâm niên
  seniority_bonus   numeric(3,1) NOT NULL DEFAULT 1, -- cộng 1 ngày
  carryover_max     numeric(4,1) NOT NULL DEFAULT 5,
  carryover_expires text,                            -- MM-DD hết hạn phép tồn, NULL = không hết
  prorate_new_hire  boolean NOT NULL DEFAULT true,
  probation_accrues boolean NOT NULL DEFAULT false
);

CREATE TABLE hr.leave_balances (
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  employee_id   uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  year          smallint NOT NULL,
  entitled      numeric(5,2) NOT NULL,              -- phép năm
  carried_over  numeric(5,2) NOT NULL DEFAULT 0,    -- chuyển từ năm trước
  adjusted      numeric(5,2) NOT NULL DEFAULT 0,    -- điều chỉnh tay (có nhật ký)
  granted_at    timestamptz NOT NULL DEFAULT now(),
  granted_by    uuid REFERENCES core.users(id),
  PRIMARY KEY (employee_id, year)
);
-- Đã dùng và đang chờ duyệt tính động từ hr.requests (view hr.leave_balance_v), không lưu.

-- ---------- Kỳ công & bảng công tháng ----------
CREATE TABLE hr.timesheet_periods (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  period        date NOT NULL CHECK (extract(day FROM period) = 1),   -- ngày đầu tháng
  start_date    date NOT NULL,                      -- cho phép kỳ công 26 → 25
  end_date      date NOT NULL,
  standard_days numeric(4,1) NOT NULL,              -- công chuẩn
  state         text NOT NULL DEFAULT 'open' CHECK (state IN ('open','summarized','locked')),
  summarized_at timestamptz,
  locked_at     timestamptz,
  locked_by     uuid REFERENCES core.users(id),
  UNIQUE (company_id, period),
  CHECK (end_date > start_date)
);

CREATE TABLE hr.timesheets (                        -- dòng bảng công của từng người trong kỳ
  period_id       uuid NOT NULL REFERENCES hr.timesheet_periods(id) ON DELETE CASCADE,
  employee_id     uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  standard_days   numeric(4,1) NOT NULL,
  actual_days     numeric(5,2) NOT NULL DEFAULT 0,  -- công thực tế
  paid_leave_days numeric(5,2) NOT NULL DEFAULT 0,  -- phép
  unpaid_days     numeric(5,2) NOT NULL DEFAULT 0,
  absent_days     numeric(5,2) NOT NULL DEFAULT 0,  -- vắng
  holiday_days    numeric(5,2) NOT NULL DEFAULT 0,
  late_count      int NOT NULL DEFAULT 0,
  late_minutes    int NOT NULL DEFAULT 0,
  ot_minutes      jsonb NOT NULL DEFAULT '{}',      -- {"weekday":120,"weekend":0,"holiday":0,"night":0}
  confirm_state   text NOT NULL DEFAULT 'waiting' CHECK (confirm_state IN ('waiting','confirmed','disputed')),
  confirmed_at    timestamptz,
  dispute_note    text,
  PRIMARY KEY (period_id, employee_id)
);
