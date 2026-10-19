-- =====================================================================
-- Enterprise OS — 20 Công văn & Tài liệu (schema doc)
-- Sổ công văn đến, sổ văn bản đi theo NĐ 30; kho hồ sơ tài liệu (hợp đồng, hóa đơn, pháp lý...).
-- Tệp: core.files + core.attachments. Nhật ký: core.audit_log. Ngày nghỉ: core.holidays.
-- Cơ quan gửi/nhận: core.organizations (kinds chứa 'agency').
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS doc;
SET search_path = doc, core, public;

CREATE TYPE doc.numbering   AS ENUM ('shared','per_type');            -- một dãy chung | theo từng loại
CREATE TYPE doc.issue_at    AS ENUM ('on_sign','on_register');        -- cấp số đi khi ký | khi vào sổ
CREATE TYPE doc.channel     AS ENUM ('post','hand','email','gmail','portal','other');
CREATE TYPE doc.handling    AS ENUM ('process','info');               -- xử lý | để biết, lưu
CREATE TYPE doc.origin      AS ENUM ('manual','scan','gmail','import');
CREATE TYPE doc.out_stage   AS ENUM ('draft','in_review','signed','issued');

-- ---------- Cấu hình (một dòng mỗi công ty) ----------
CREATE TABLE doc.settings (
  company_id       uuid PRIMARY KEY REFERENCES core.companies(id) ON DELETE CASCADE,
  org_name         text NOT NULL,                   -- in trên văn bản: CÔNG TY CỔ PHẦN ABC
  parent_org_name  text,                            -- cơ quan chủ quản
  place_name       text NOT NULL,                   -- TP. Hồ Chí Minh
  org_abbr         text NOT NULL CHECK (org_abbr ~ '^[A-ZĐ0-9]{1,15}$'),
  numbering        doc.numbering NOT NULL DEFAULT 'shared',
  issue_at         doc.issue_at  NOT NULL DEFAULT 'on_sign',
  zero_pad         boolean NOT NULL DEFAULT false,  -- 01..09
  soon_days        int NOT NULL DEFAULT 3 CHECK (soon_days BETWEEN 0 AND 30),
  weekend          int[] NOT NULL DEFAULT '{6,7}',
  remind_enabled   boolean NOT NULL DEFAULT false,
  remind_hour      int NOT NULL DEFAULT 7 CHECK (remind_hour BETWEEN 5 AND 11),
  digest_emails    text[] NOT NULL DEFAULT '{}',
  vault_folder_id  text,                            -- thư mục Drive "Kho công văn"
  vault_folder_url text,
  vault_state      core.drive_state NOT NULL DEFAULT 'none',
  vault_note       text,
  gmail_enabled    boolean NOT NULL DEFAULT false,
  gmail_auto_register boolean NOT NULL DEFAULT false,
  gmail_address    text,
  gmail_senders    text[] NOT NULL DEFAULT '{}',    -- chỉ nhận thư chuyển tiếp từ các địa chỉ này
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE doc.doc_types (                        -- loại văn bản
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,                        -- Quyết định
  abbr        text CHECK (abbr ~ '^[A-Za-zĐđ]{1,6}$'),   -- QĐ, TTr; NULL với Công văn
  is_letter   boolean NOT NULL DEFAULT false,       -- là Công văn
  direction   text NOT NULL DEFAULT 'both' CHECK (direction IN ('in','out','both')),
  template    text,                                 -- mẫu dựng sẵn: cong_van, quyet_dinh, to_trinh...
  template_file_id bigint REFERENCES core.files(id),-- mẫu .docx riêng có logo
  sort        int NOT NULL DEFAULT 100,
  active      boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, name),
  CHECK (is_letter OR abbr IS NOT NULL)
);
CREATE UNIQUE INDEX doc_types_abbr_uq ON doc.doc_types (company_id, abbr) WHERE abbr IS NOT NULL;
CREATE UNIQUE INDEX doc_types_letter_uq ON doc.doc_types (company_id) WHERE is_letter;

CREATE TABLE doc.urgencies (                        -- độ khẩn → số ngày xử lý
  company_id  uuid REFERENCES core.companies(id) ON DELETE CASCADE,
  code        text CHECK (code ~ '^[a-z_]{2,20}$'), -- normal, urgent, very_urgent, flash
  name        text NOT NULL,                        -- Thường, Khẩn, Thượng khẩn, Hỏa tốc
  days        int  NOT NULL CHECK (days BETWEEN 0 AND 90),
  sort        int  NOT NULL,
  PRIMARY KEY (company_id, code)
);

CREATE TABLE doc.secrecies (                        -- độ mật
  company_id   uuid REFERENCES core.companies(id) ON DELETE CASCADE,
  code         text CHECK (code IN ('normal','confidential','secret','top_secret')),
  name         text NOT NULL,
  own_sequence boolean NOT NULL,                    -- dãy số riêng
  digitize     boolean NOT NULL,                    -- false: cấm tệp, OCR, Gmail
  PRIMARY KEY (company_id, code)
);

CREATE TABLE doc.signers (                          -- người ký văn bản đi
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  user_id     uuid REFERENCES core.users(id),
  full_name   text NOT NULL,
  title       text NOT NULL,                        -- PHÓ GIÁM ĐỐC
  authority   text NOT NULL DEFAULT '' CHECK (authority IN ('','KT.','TM.','TL.','TUQ.')),
  on_behalf   text,                                 -- GIÁM ĐỐC
  active      boolean NOT NULL DEFAULT true
);

CREATE TABLE doc.register_columns (                 -- cột của sổ khi in (NULL company = mặc định)
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid REFERENCES core.companies(id) ON DELETE CASCADE,
  book        text NOT NULL CHECK (book IN ('in','out')),
  sort        int  NOT NULL,
  heading     text NOT NULL,
  source      text NOT NULL,                        -- trường trong danh sách cho phép
  width_mm    numeric(5,1) NOT NULL
);

-- ---------- Sổ công văn đến ----------
CREATE TABLE doc.incoming (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  year            smallint NOT NULL,
  sequence        text NOT NULL DEFAULT 'shared',   -- shared | secret
  number          int  NOT NULL CHECK (number > 0), -- số đến
  received_on     date NOT NULL DEFAULT current_date,
  sender_name     text NOT NULL,                    -- tác giả / cơ quan gửi
  sender_org_id   uuid REFERENCES core.organizations(id),
  ref_number      text,                             -- 1502/SNV-LĐ
  doc_date        date,
  type_id         uuid NOT NULL REFERENCES doc.doc_types(id),
  summary         text NOT NULL CHECK (length(btrim(summary)) BETWEEN 3 AND 1000),   -- trích yếu
  urgency         text NOT NULL DEFAULT 'normal',
  secrecy         text NOT NULL DEFAULT 'normal',
  channel         doc.channel NOT NULL DEFAULT 'post',
  handling        doc.handling NOT NULL DEFAULT 'process',
  needs_reply     boolean NOT NULL DEFAULT false,
  department_id   uuid REFERENCES core.departments(id) ON DELETE SET NULL,
  handler_id      uuid REFERENCES core.users(id),
  directive       text CHECK (length(directive) <= 2000),   -- ý kiến chỉ đạo
  assigned_on     date,                             -- ngày chuyển
  deadline_in_doc date,
  deadline        date,                             -- hạn chốt, lưu cố định
  deadline_source text CHECK (deadline_source IN ('document','urgency','directive')),
  completed_on    date,
  outcome         text CHECK (length(outcome) <= 2000),
  task_id         bigint REFERENCES work.tasks(id) ON DELETE SET NULL,
  cancelled       boolean NOT NULL DEFAULT false,
  cancel_reason   text,
  note            text,
  origin          doc.origin NOT NULL DEFAULT 'manual',
  search_key      text GENERATED ALWAYS AS (core.norm(number::text || ' ' || coalesce(ref_number,'') || ' ' || sender_name || ' ' || summary || ' ' || coalesce(directive,'') || ' ' || coalesce(note,''))) STORED,
  created_by      uuid REFERENCES core.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, year, sequence, number),
  FOREIGN KEY (company_id, urgency) REFERENCES doc.urgencies(company_id, code),
  FOREIGN KEY (company_id, secrecy) REFERENCES doc.secrecies(company_id, code),
  CHECK (completed_on IS NULL OR completed_on >= received_on),
  CHECK (NOT cancelled OR cancel_reason IS NOT NULL)
);
CREATE INDEX incoming_open_idx ON doc.incoming (company_id, deadline) WHERE completed_on IS NULL AND NOT cancelled;
CREATE INDEX incoming_handler_idx ON doc.incoming (handler_id) WHERE completed_on IS NULL;
CREATE INDEX incoming_search_idx ON doc.incoming USING gin (search_key gin_trgm_ops);

-- ---------- Sổ văn bản đi ----------
CREATE TABLE doc.outgoing (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  stage           doc.out_stage NOT NULL DEFAULT 'draft',
  year            smallint,
  sequence        text,                             -- shared | viết tắt loại | secret
  number          int CHECK (number > 0),
  ref_number      text,                             -- 4/ABC-KD, 1/QĐ-ABC
  doc_date        date,                             -- ngày ký ban hành
  type_id         uuid NOT NULL REFERENCES doc.doc_types(id),
  summary         text NOT NULL CHECK (length(btrim(summary)) BETWEEN 3 AND 1000),
  department_id   uuid REFERENCES core.departments(id) ON DELETE SET NULL,   -- đơn vị soạn
  drafter_id      uuid REFERENCES core.users(id),
  signer_id       uuid REFERENCES doc.signers(id),
  addressee       text,                             -- Kính gửi
  recipients      text[] NOT NULL DEFAULT '{}',     -- Nơi nhận
  archive_note    text,                             -- Lưu: VT, KD.
  copies          int CHECK (copies BETWEEN 1 AND 999),
  urgency         text NOT NULL DEFAULT 'normal',
  secrecy         text NOT NULL DEFAULT 'normal',
  sent_on         date,
  sent_via        doc.channel[] NOT NULL DEFAULT '{}',
  draft_file_id   bigint REFERENCES core.files(id), -- Google Docs dự thảo
  task_id         bigint REFERENCES work.tasks(id) ON DELETE SET NULL,
  approval_id     bigint REFERENCES core.approval_requests(id),
  cancelled       boolean NOT NULL DEFAULT false,
  cancel_reason   text,
  note            text,
  search_key      text GENERATED ALWAYS AS (core.norm(coalesce(ref_number,'') || ' ' || summary || ' ' || coalesce(addressee,'') || ' ' || coalesce(note,''))) STORED,
  created_by      uuid REFERENCES core.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (company_id, urgency) REFERENCES doc.urgencies(company_id, code),
  FOREIGN KEY (company_id, secrecy) REFERENCES doc.secrecies(company_id, code),
  CHECK ((number IS NULL) = (ref_number IS NULL) AND (number IS NULL) = (year IS NULL)),
  CHECK (number IS NULL OR doc_date IS NOT NULL),
  CHECK (sent_on IS NULL OR number IS NOT NULL)
);
CREATE UNIQUE INDEX outgoing_number_uq ON doc.outgoing (company_id, year, sequence, number) WHERE number IS NOT NULL;
CREATE UNIQUE INDEX outgoing_ref_uq ON doc.outgoing (company_id, year, ref_number) WHERE ref_number IS NOT NULL;
CREATE INDEX outgoing_search_idx ON doc.outgoing USING gin (search_key gin_trgm_ops);

CREATE TABLE doc.counters (                         -- số cuối đã cấp
  company_id  uuid REFERENCES core.companies(id) ON DELETE CASCADE,
  year        smallint,
  book        text CHECK (book IN ('in','out')),
  sequence    text,
  last_number int NOT NULL DEFAULT 0,
  PRIMARY KEY (company_id, year, book, sequence)
);

CREATE TABLE doc.replies (                          -- văn bản đi trả lời công văn đến
  incoming_id bigint REFERENCES doc.incoming(id) ON DELETE CASCADE,
  outgoing_id bigint REFERENCES doc.outgoing(id) ON DELETE CASCADE,
  actor       text NOT NULL,
  PRIMARY KEY (incoming_id, outgoing_id)
);

CREATE TABLE doc.ocr_jobs (                         -- hàng đợi đọc file scan (chỉ lưu trường đã bóc)
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  file_id     bigint NOT NULL REFERENCES core.files(id),
  origin      text NOT NULL CHECK (origin IN ('upload','gmail')),
  state       text NOT NULL DEFAULT 'queued' CHECK (state IN ('queued','reading','done','error','registered','skipped')),
  result      jsonb,                                -- {fields:{...}, confidence:{...}, pages, sha256}
  maybe_dupes bigint[],
  error       text,
  claimed_by  text,
  claimed_at  timestamptz,
  incoming_id bigint REFERENCES doc.incoming(id),
  email_meta  jsonb,
  created_by  uuid REFERENCES core.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ocr_queue_idx ON doc.ocr_jobs (state, id) WHERE state IN ('queued','reading');

CREATE TABLE doc.gmail_messages (
  message_id  text PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  sender      text, subject text, received_at timestamptz,
  outcome     text NOT NULL CHECK (outcome IN ('queued','no_attachment','ignored','error')),
  ocr_job_ids bigint[]
);

CREATE TABLE doc.register_prints (                  -- lần in sổ cuối năm
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  year        smallint NOT NULL,
  book        text NOT NULL CHECK (book IN ('in','out')),
  volume      text NOT NULL,                        -- quyển số
  from_number int, to_number int, row_count int,
  checks      jsonb NOT NULL,                       -- lủng số, trùng số... lúc in
  docx_file_id bigint REFERENCES core.files(id),
  pdf_file_id  bigint REFERENCES core.files(id),
  created_by  uuid REFERENCES core.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------- Kho hồ sơ tài liệu (hợp đồng, phụ lục, hóa đơn, nghiệm thu, pháp lý...) ----------
CREATE TABLE doc.record_categories (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,                        -- Hợp đồng
  icon        text,                                 -- tên icon: description, receipt_long
  color       text CHECK (color ~ '^#[0-9A-Fa-f]{6}$'),
  description text,
  has_value   boolean NOT NULL DEFAULT false,       -- có giá trị hợp đồng / thực hiện
  sort        int NOT NULL DEFAULT 100,
  active      boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, name)
);

CREATE TABLE doc.category_access (                  -- "Quyền danh mục"
  category_id uuid NOT NULL REFERENCES doc.record_categories(id) ON DELETE CASCADE,
  role_id     uuid REFERENCES core.roles(id) ON DELETE CASCADE,
  user_id     uuid REFERENCES core.users(id) ON DELETE CASCADE,
  can_edit    boolean NOT NULL DEFAULT false,
  CHECK ((role_id IS NULL) <> (user_id IS NULL))
);
CREATE UNIQUE INDEX category_access_uq ON doc.category_access (category_id, coalesce(role_id, user_id));

CREATE TABLE doc.records (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  category_id     uuid NOT NULL REFERENCES doc.record_categories(id),
  record_no       text,                             -- số hồ sơ / số hợp đồng
  title           text NOT NULL,
  description     text,
  department_id   uuid REFERENCES core.departments(id) ON DELETE SET NULL,
  project_id      uuid REFERENCES core.projects(id) ON DELETE SET NULL,
  org_id          uuid REFERENCES core.organizations(id),   -- nhà cung cấp / đối tác
  owner_id        uuid REFERENCES core.users(id),           -- người phụ trách
  issued_on       date,                             -- ngày ban hành / ký
  expires_on      date,                             -- ngày kết thúc hiệu lực
  contract_value  bigint CHECK (contract_value >= 0),
  executed_value  bigint CHECK (executed_value >= 0),
  variance        bigint GENERATED ALWAYS AS (executed_value - contract_value) STORED,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','expiring','expired','closed','cancelled')),
  incoming_id     bigint REFERENCES doc.incoming(id),   -- hồ sơ hình thành từ công văn đến (nếu có)
  outgoing_id     bigint REFERENCES doc.outgoing(id),
  search_key      text GENERATED ALWAYS AS (core.norm(coalesce(record_no,'') || ' ' || title || ' ' || coalesce(description,''))) STORED,
  created_by      uuid REFERENCES core.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_on IS NULL OR issued_on IS NULL OR expires_on >= issued_on)
);
CREATE INDEX records_company_idx ON doc.records (company_id, category_id, status);
CREATE INDEX records_expiry_idx ON doc.records (company_id, expires_on) WHERE status IN ('active','expiring');
CREATE INDEX records_search_idx ON doc.records USING gin (search_key gin_trgm_ops);
