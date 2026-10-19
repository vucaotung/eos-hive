-- =====================================================================
-- Enterprise OS — 31 Lương & KPI (schema hr)
-- Cấu hình lương theo phiên bản hiệu lực, khoản lương, lương từng người,
-- kỳ lương 5 bước, phiếu lương, thưởng/khấu trừ, phản hồi phiếu lương;
-- KPI tính từ việc hoàn thành / không hoàn thành trong tháng.
-- =====================================================================
SET search_path = hr, core, public;

-- ---------- Cấu hình lương (có hiệu lực theo ngày: luật đổi thì thêm dòng mới) ----------
CREATE TABLE hr.payroll_settings (
  company_id          uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  effective_from      date NOT NULL,
  ins_employee_pct    jsonb NOT NULL,   -- {"bhxh":8,"bhyt":1.5,"bhtn":1}   — nhập theo quy định hiện hành
  ins_employer_pct    jsonb NOT NULL,   -- {"bhxh":17.5,"bhyt":3,"bhtn":1,"kpcd":2}
  ins_salary_cap      bigint NOT NULL,  -- trần lương đóng bảo hiểm
  personal_deduction  bigint NOT NULL,  -- giảm trừ bản thân / tháng
  dependent_deduction bigint NOT NULL,  -- giảm trừ mỗi người phụ thuộc / tháng
  pit_brackets        jsonb NOT NULL,   -- [{"up_to":10000000,"rate":5}, ..., {"up_to":null,"rate":35}]
  ot_multipliers      jsonb NOT NULL DEFAULT '{"weekday":1.5,"weekend":2.0,"holiday":3.0,"night":0.3}',
  late_penalty        jsonb,            -- {"per_minute":0} hoặc bậc phạt đi muộn, NULL = không trừ
  round_to            int NOT NULL DEFAULT 1000,   -- làm tròn lương thực nhận
  payslip_email       boolean NOT NULL DEFAULT false,
  note                text,             -- căn cứ pháp lý của phiên bản này
  PRIMARY KEY (company_id, effective_from)
);

CREATE TABLE hr.salary_components (                 -- khoản thu nhập / khấu trừ
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  code        text NOT NULL CHECK (code ~ '^[a-z_]{2,30}$'),   -- base, lunch, phone, responsibility, kpi_bonus, advance...
  name        text NOT NULL,                        -- Lương cơ bản, Phụ cấp ăn trưa, Thưởng KPI, Tạm ứng
  kind        text NOT NULL CHECK (kind IN ('earning','deduction')),
  calc        text NOT NULL CHECK (calc IN ('fixed','per_workday','kpi','overtime','manual')),
  taxable     boolean NOT NULL DEFAULT true,        -- chịu thuế TNCN
  tax_free_cap bigint,                              -- phần miễn thuế tối đa / tháng (vd ăn trưa)
  insurable   boolean NOT NULL DEFAULT false,       -- tính vào lương đóng bảo hiểm
  sort        int NOT NULL DEFAULT 100,
  active      boolean NOT NULL DEFAULT true,
  UNIQUE (company_id, code)
);

CREATE TABLE hr.employee_components (               -- khai lương: số tiền từng khoản của từng người, có hiệu lực
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id     uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  employee_id    uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  component_id   uuid NOT NULL REFERENCES hr.salary_components(id),
  amount         bigint NOT NULL CHECK (amount >= 0),   -- với kpi: mức thưởng KPI tối đa
  effective_from date NOT NULL,
  effective_to   date,
  created_by     uuid REFERENCES core.users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  CHECK (effective_to IS NULL OR effective_to >= effective_from)
);
CREATE INDEX employee_components_idx ON hr.employee_components (employee_id, component_id, effective_from DESC);

-- ---------- KPI ----------
CREATE TABLE hr.kpi_policies (
  company_id        uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  effective_from    date NOT NULL,
  priority_weights  jsonb NOT NULL DEFAULT '{"low":0.5,"medium":1,"high":1.5,"urgent":2}',
  late_penalty_day  numeric(4,3) NOT NULL DEFAULT 0.10,   -- mỗi ngày trễ mất 10% điểm việc
  late_floor        numeric(4,3) NOT NULL DEFAULT 0.30,   -- việc trễ vẫn giữ tối thiểu 30%
  min_tasks         int NOT NULL DEFAULT 3,              -- dưới số này: "chưa đủ dữ liệu", không xếp loại
  self_assigned     text NOT NULL DEFAULT 'needs_confirm' CHECK (self_assigned IN ('count','needs_confirm','exclude')),
  max_adjustment    numeric(5,2) NOT NULL DEFAULT 10,    -- trưởng phòng cộng/trừ tối đa ±10 điểm
  grade_bands       jsonb NOT NULL DEFAULT
    '[{"min":90,"grade":"A","bonus_pct":100},{"min":75,"grade":"B","bonus_pct":70},{"min":60,"grade":"C","bonus_pct":40},{"min":0,"grade":"D","bonus_pct":0}]',
  PRIMARY KEY (company_id, effective_from)
);

CREATE TABLE hr.kpi_scores (                        -- KPI tháng của từng người (ảnh chụp lúc tính)
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  period          date NOT NULL CHECK (extract(day FROM period) = 1),
  employee_id     uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  tasks_total     int NOT NULL DEFAULT 0,
  done_on_time    int NOT NULL DEFAULT 0,
  done_late       int NOT NULL DEFAULT 0,
  not_done        int NOT NULL DEFAULT 0,           -- quá hạn mà chưa xong
  pending         int NOT NULL DEFAULT 0,           -- chưa tới hạn (chỉ có khi tính giữa tháng)
  points_earned   numeric(8,2) NOT NULL DEFAULT 0,
  points_possible numeric(8,2) NOT NULL DEFAULT 0,
  score           numeric(5,2),                     -- NULL = chưa đủ dữ liệu
  adjustment      numeric(5,2) NOT NULL DEFAULT 0,
  adjustment_note text,
  adjusted_by     uuid REFERENCES core.users(id),
  final_score     numeric(5,2),
  grade           text,
  bonus_pct       numeric(5,2),
  state           text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','locked')),
  computed_at     timestamptz NOT NULL DEFAULT now(),
  locked_at       timestamptz,
  UNIQUE (company_id, period, employee_id),
  CHECK (adjustment = 0 OR adjustment_note IS NOT NULL)
);

CREATE TABLE hr.kpi_items (                         -- từng việc góp vào KPI: minh bạch cho nhân viên
  score_id      bigint NOT NULL REFERENCES hr.kpi_scores(id) ON DELETE CASCADE,
  task_id       bigint NOT NULL REFERENCES work.tasks(id) ON DELETE CASCADE,
  weight        numeric(4,2) NOT NULL,
  due_date      date,
  completed_on  date,
  outcome       text NOT NULL CHECK (outcome IN ('on_time','late','not_done','pending')),
  late_days     int NOT NULL DEFAULT 0,
  points        numeric(6,2) NOT NULL,
  PRIMARY KEY (score_id, task_id)
);

-- ---------- Kỳ lương ----------
CREATE TABLE hr.payroll_runs (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id          uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  period              date NOT NULL CHECK (extract(day FROM period) = 1),
  timesheet_period_id uuid NOT NULL REFERENCES hr.timesheet_periods(id),
  state               text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','calculated','locked','published')),
  calculated_at       timestamptz, calculated_by uuid REFERENCES core.users(id),
  locked_at           timestamptz, locked_by     uuid REFERENCES core.users(id),
  published_at        timestamptz, published_by  uuid REFERENCES core.users(id),
  approval_id         bigint REFERENCES core.approval_requests(id),   -- duyệt bảng lương (tùy chọn)
  note                text,
  UNIQUE (company_id, period)
);

CREATE TABLE hr.payroll_adjustments (               -- thưởng & khấu trừ trong kỳ
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id        uuid NOT NULL REFERENCES hr.payroll_runs(id) ON DELETE CASCADE,
  employee_id   uuid NOT NULL REFERENCES hr.employees(id) ON DELETE CASCADE,
  component_id  uuid NOT NULL REFERENCES hr.salary_components(id),
  amount        bigint NOT NULL CHECK (amount > 0),
  reason        text NOT NULL,
  created_by    uuid REFERENCES core.users(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE hr.payslips (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id         uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
  run_id             uuid NOT NULL REFERENCES hr.payroll_runs(id) ON DELETE CASCADE,
  employee_id        uuid NOT NULL REFERENCES hr.employees(id),
  contract_id        uuid REFERENCES hr.contracts(id),
  kpi_score_id       bigint REFERENCES hr.kpi_scores(id),
  base_salary        bigint NOT NULL,
  standard_days      numeric(4,1) NOT NULL,
  paid_days          numeric(5,2) NOT NULL,         -- công thực tế + phép + lễ
  gross_income       bigint NOT NULL,               -- tổng thu nhập
  insurance_base     bigint NOT NULL,
  insurance_employee bigint NOT NULL,
  insurance_employer bigint NOT NULL,
  family_deduction   bigint NOT NULL,
  taxable_income     bigint NOT NULL,               -- thu nhập tính thuế
  pit                bigint NOT NULL,               -- thuế TNCN
  other_deductions   bigint NOT NULL DEFAULT 0,
  net_pay            bigint NOT NULL,               -- thực nhận
  state              text NOT NULL DEFAULT 'calculated' CHECK (state IN ('calculated','locked','published')),
  pdf_file_id        bigint REFERENCES core.files(id),
  emailed_at         timestamptz,
  viewed_at          timestamptz,
  calculated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (run_id, employee_id)
);

CREATE TABLE hr.payslip_lines (
  payslip_id    bigint NOT NULL REFERENCES hr.payslips(id) ON DELETE CASCADE,
  sort          int NOT NULL,
  component_id  uuid REFERENCES hr.salary_components(id),
  code          text NOT NULL,                      -- base, ot_weekday, kpi_bonus, bhxh, pit...
  label         text NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('earning','deduction','info')),
  quantity      numeric(8,2),                       -- số công, số giờ
  rate          numeric(14,2),                      -- đơn giá, hệ số
  amount        bigint NOT NULL,
  PRIMARY KEY (payslip_id, sort)
);

CREATE TABLE hr.payslip_feedback (                  -- nhân viên phản hồi phiếu lương ngay trong app
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  payslip_id    bigint NOT NULL REFERENCES hr.payslips(id) ON DELETE CASCADE,
  employee_id   uuid NOT NULL REFERENCES hr.employees(id),
  message       text NOT NULL CHECK (length(btrim(message)) BETWEEN 2 AND 2000),
  state         text NOT NULL DEFAULT 'open' CHECK (state IN ('open','answered','closed')),
  reply         text,
  replied_by    uuid REFERENCES core.users(id),
  replied_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- ---------- Hàm: thuế TNCN lũy tiến theo bậc trong cấu hình ----------
CREATE FUNCTION hr.calc_pit(p_taxable bigint, p_brackets jsonb) RETURNS bigint LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE b jsonb; lower_b bigint := 0; upper_b bigint; tax numeric := 0;
BEGIN
  IF p_taxable <= 0 THEN RETURN 0; END IF;
  FOR b IN SELECT * FROM jsonb_array_elements(p_brackets) LOOP
    upper_b := nullif(b->>'up_to','')::bigint;
    IF upper_b IS NULL OR p_taxable <= upper_b THEN
      tax := tax + (p_taxable - lower_b) * (b->>'rate')::numeric / 100;
      RETURN round(tax);
    END IF;
    tax := tax + (upper_b - lower_b) * (b->>'rate')::numeric / 100;
    lower_b := upper_b;
  END LOOP;
  RETURN round(tax);
END $$;

-- ---------- Hàm: tính KPI tháng cho cả công ty (ghi đè bản nháp, không đụng bản đã khóa) ----------
CREATE FUNCTION hr.compute_kpi(p_company uuid, p_period date, p_as_of date DEFAULT current_date)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE
  pol hr.kpi_policies%ROWTYPE;
  p_start date := date_trunc('month', p_period)::date;
  p_end   date := (date_trunc('month', p_period) + interval '1 month - 1 day')::date;
  eval_d  date := least(p_end, p_as_of);
  e record; n int := 0; sid bigint;
BEGIN
  SELECT * INTO pol FROM hr.kpi_policies
   WHERE company_id = p_company AND effective_from <= p_end ORDER BY effective_from DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chưa cấu hình KPI cho công ty'; END IF;

  FOR e IN SELECT id, user_id FROM hr.employees
            WHERE company_id = p_company AND user_id IS NOT NULL
              AND hire_date <= p_end AND (leave_date IS NULL OR leave_date >= p_start)
  LOOP
    IF EXISTS (SELECT 1 FROM hr.kpi_scores WHERE company_id = p_company AND period = p_start
                AND employee_id = e.id AND state = 'locked') THEN CONTINUE; END IF;

    INSERT INTO hr.kpi_scores (company_id, period, employee_id) VALUES (p_company, p_start, e.id)
    ON CONFLICT (company_id, period, employee_id) DO UPDATE SET computed_at = now()
    RETURNING id INTO sid;
    DELETE FROM hr.kpi_items WHERE score_id = sid;

    INSERT INTO hr.kpi_items (score_id, task_id, weight, due_date, completed_on, outcome, late_days, points)
    SELECT sid, t.id, w.weight, t.due_date, t.completed_at::date, o.outcome, o.late_days,
           round(CASE o.outcome
                   WHEN 'on_time' THEN w.weight
                   WHEN 'late'    THEN w.weight * greatest(pol.late_floor, 1 - pol.late_penalty_day * o.late_days)
                   ELSE 0 END, 2)
      FROM work.tasks t
      CROSS JOIN LATERAL (SELECT coalesce(t.kpi_weight, (pol.priority_weights->>t.priority::text)::numeric) AS weight) w
      CROSS JOIN LATERAL (
        SELECT CASE
                 WHEN t.status = 'done' AND (t.due_date IS NULL OR t.completed_at::date <= t.due_date) THEN 'on_time'
                 WHEN t.status = 'done' THEN 'late'
                 WHEN t.due_date < eval_d THEN 'not_done'
                 ELSE 'pending' END AS outcome,
               CASE WHEN t.status = 'done' AND t.completed_at::date > t.due_date
                    THEN t.completed_at::date - t.due_date ELSE 0 END AS late_days) o
     WHERE t.company_id = p_company
       AND t.assignee_id = e.user_id
       AND t.kpi_counted
       AND t.status <> 'cancelled'
       AND ( (t.due_date BETWEEN p_start AND p_end)
          OR (t.due_date IS NULL AND t.completed_at::date BETWEEN p_start AND p_end) )
       AND ( pol.self_assigned = 'count'
          OR t.created_by IS DISTINCT FROM t.assignee_id
          OR t.source <> 'manual'
          OR (pol.self_assigned = 'needs_confirm' AND t.kpi_confirmed_by IS NOT NULL) );

    UPDATE hr.kpi_scores s SET
      tasks_total     = x.total,
      done_on_time    = x.on_time,
      done_late       = x.late,
      not_done        = x.not_done,
      pending         = x.pending,
      points_earned   = x.earned,
      points_possible = x.possible,
      score           = CASE WHEN x.total - x.pending >= pol.min_tasks AND x.possible > 0
                             THEN round(100 * x.earned / x.possible, 2) END
    FROM (SELECT count(*) AS total,
                 count(*) FILTER (WHERE outcome = 'on_time')  AS on_time,
                 count(*) FILTER (WHERE outcome = 'late')     AS late,
                 count(*) FILTER (WHERE outcome = 'not_done') AS not_done,
                 count(*) FILTER (WHERE outcome = 'pending')  AS pending,
                 coalesce(sum(points), 0) AS earned,
                 coalesce(sum(weight) FILTER (WHERE outcome <> 'pending'), 0) AS possible
            FROM hr.kpi_items WHERE score_id = sid) x
    WHERE s.id = sid;

    UPDATE hr.kpi_scores s SET
      final_score = CASE WHEN s.score IS NULL THEN NULL
                         ELSE least(100, greatest(0, s.score + s.adjustment)) END
    WHERE s.id = sid;

    UPDATE hr.kpi_scores s SET grade = b->>'grade', bonus_pct = (b->>'bonus_pct')::numeric
      FROM (SELECT b FROM jsonb_array_elements(pol.grade_bands) b
             WHERE (b->>'min')::numeric <= (SELECT final_score FROM hr.kpi_scores WHERE id = sid)
             ORDER BY (b->>'min')::numeric DESC LIMIT 1) g
     WHERE s.id = sid;
    UPDATE hr.kpi_scores SET grade = NULL, bonus_pct = NULL WHERE id = sid AND final_score IS NULL;
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;
