-- =====================================================================
-- Enterprise OS — 45 Kho dữ liệu chung (schema kb)
-- Lớp quản lý phía trên WeKnora: KB nào thuộc ai, ai được hỏi, trang wiki có duyệt,
-- nguồn đã nạp (để hiện trích dẫn), lịch sử hỏi đáp.
-- Nội dung đã cắt đoạn và chỉ mục vector nằm trong WeKnora, không nằm ở đây.
-- Ngoại lệ có chủ đích với nguyên tắc "máy chủ chỉ giữ siêu dữ liệu": nội dung trang wiki
-- và nội dung đã nạp WeKnora nằm trên máy chủ. Văn bản mật không bao giờ được nạp.
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS kb;
SET search_path = kb, core, public;

CREATE TABLE kb.bases (                             -- ánh xạ một KB của WeKnora
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  weknora_kb_id   text NOT NULL,                    -- id KB bên WeKnora
  name            text NOT NULL,                    -- KDC Thành Lập, Pháp luật chung, Quy trình nội bộ
  scope           text NOT NULL CHECK (scope IN ('project','team','company','shared_legal')),
  project_id      uuid REFERENCES core.projects(id) ON DELETE SET NULL,   -- KB theo dự án (quyết định Z2)
  description     text,
  accepts_wiki    boolean NOT NULL DEFAULT false,   -- trang wiki được xuất bản vào KB này
  active          boolean NOT NULL DEFAULT true,
  last_synced_at  timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, weknora_kb_id),
  UNIQUE (company_id, name),
  CHECK (scope <> 'project' OR project_id IS NOT NULL)
);

CREATE TABLE kb.base_access (                       -- ai được hỏi / quản lý KB nào (vd Team Valnex chỉ đọc vài KB)
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  base_id       uuid NOT NULL REFERENCES kb.bases(id) ON DELETE CASCADE,
  role_id       uuid REFERENCES core.roles(id) ON DELETE CASCADE,
  department_id uuid REFERENCES core.departments(id) ON DELETE CASCADE,
  user_id       uuid REFERENCES core.users(id) ON DELETE CASCADE,
  can_manage    boolean NOT NULL DEFAULT false,
  CHECK (num_nonnulls(role_id, department_id, user_id) = 1)
);
CREATE UNIQUE INDEX base_access_uq ON kb.base_access (base_id, coalesce(role_id, department_id, user_id));

CREATE TABLE kb.page_categories (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  name        text NOT NULL,                        -- Quy trình, Hướng dẫn, Quy chế, Biểu mẫu, Câu hỏi thường gặp
  sort        int NOT NULL DEFAULT 100,
  UNIQUE (company_id, name)
);

CREATE TABLE kb.pages (                             -- trang wiki
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  base_id       uuid NOT NULL REFERENCES kb.bases(id),           -- KB nhận bản xuất bản
  category_id   uuid REFERENCES kb.page_categories(id) ON DELETE SET NULL,
  department_id uuid REFERENCES core.departments(id) ON DELETE SET NULL,   -- phòng sở hữu nội dung
  slug          text NOT NULL CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title         text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 200),
  body_md       text NOT NULL DEFAULT '' CHECK (length(body_md) <= 200000),   -- bản nháp hiện tại
  state         text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','in_review','published','archived')),
  published_version int,                            -- phiên bản đang có hiệu lực
  owner_id      uuid REFERENCES core.users(id),
  review_due    date,                             -- hạn rà soát lại nội dung
  approval_id   bigint REFERENCES core.approval_requests(id),
  weknora_doc_id text,                            -- tài liệu tương ứng bên WeKnora (bản đã xuất bản)
  search_key    text GENERATED ALWAYS AS (core.norm(title || ' ' || left(body_md, 4000))) STORED,
  created_by    uuid REFERENCES core.users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, slug)
);
CREATE INDEX pages_search_idx ON kb.pages USING gin (search_key gin_trgm_ops);

CREATE TABLE kb.page_versions (                     -- mỗi lần xuất bản là một phiên bản, không sửa
  page_id       bigint NOT NULL REFERENCES kb.pages(id) ON DELETE CASCADE,
  version       int NOT NULL CHECK (version > 0),
  title         text NOT NULL,
  body_md       text NOT NULL,
  change_note   text NOT NULL,
  published_by  uuid REFERENCES core.users(id),
  published_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (page_id, version)
);

CREATE TABLE kb.sources (                           -- tài liệu đã nạp vào WeKnora, để hiện và mở trích dẫn
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  base_id         uuid NOT NULL REFERENCES kb.bases(id) ON DELETE CASCADE,
  weknora_doc_id  text NOT NULL,
  origin          text NOT NULL CHECK (origin IN ('z2_pipeline','wiki','record','incoming_doc','manual')),
  title           text NOT NULL,
  file_id         bigint REFERENCES core.files(id),            -- tệp gốc trên Drive (nếu có)
  page_id         bigint REFERENCES kb.pages(id) ON DELETE CASCADE,
  record_id       bigint REFERENCES doc.records(id) ON DELETE SET NULL,
  pages           int,
  locked          boolean NOT NULL DEFAULT false,              -- PDF / văn bản đã ký: nạp một lần (quyết định Z2)
  state           text NOT NULL DEFAULT 'loaded' CHECK (state IN ('loaded','superseded','drive_removed','locked_changed','error')),
  ingested_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (base_id, weknora_doc_id)
);
CREATE INDEX sources_file_idx ON kb.sources (file_id);

CREATE TABLE kb.questions (                         -- lịch sử hỏi đáp
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id    uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  user_id       uuid REFERENCES core.users(id) ON DELETE SET NULL,
  actor         text NOT NULL,                      -- user:<uuid> | agent:<vai-trò>
  base_ids      uuid[] NOT NULL,                    -- các KB đã tìm (chỉ trong phạm vi được xem)
  question      text NOT NULL CHECK (length(btrim(question)) BETWEEN 2 AND 2000),
  answer        text,
  citations     jsonb NOT NULL DEFAULT '[]',        -- [{source_id, page, quote}]
  found         boolean NOT NULL DEFAULT true,      -- false = "Không tìm thấy trong kho"
  feedback      text CHECK (feedback IN ('helpful','wrong','incomplete')),
  feedback_note text,
  latency_ms    int,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX questions_user_idx ON kb.questions (company_id, user_id, created_at DESC);
CREATE INDEX questions_gap_idx ON kb.questions (company_id, created_at DESC) WHERE NOT found OR feedback IN ('wrong','incomplete');

-- KB một người được hỏi: theo vai trò, phòng, chỉ định riêng; quản trị thấy hết
CREATE VIEW kb.my_bases_v WITH (security_invoker = true) AS
SELECT DISTINCT b.*
FROM kb.bases b
JOIN core.memberships m ON m.company_id = b.company_id AND m.active
                       AND m.user_id::text = nullif(current_setting('request.jwt.claims', true), '')::json->>'sub'
WHERE b.active AND (
      b.scope IN ('company','shared_legal')
   OR EXISTS (SELECT 1 FROM kb.base_access a WHERE a.base_id = b.id AND (
                a.user_id = m.user_id
             OR a.department_id = m.department_id
             OR a.role_id IN (SELECT ur.role_id FROM core.user_roles ur WHERE ur.user_id = m.user_id AND ur.company_id = b.company_id))));
