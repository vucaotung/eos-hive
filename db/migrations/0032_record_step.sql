-- 0032 · Mã bước 01–20 của quản lý dự án đầu tư xây dựng cho hồ sơ: cột doc.records.buoc (CHECK 00–20), eos_catalog_upsert nhận `buoc`.
-- Nguồn chính: db/20_doc.sql, db/62_workflow.sql. Idempotent.
-- down: DROP INDEX doc.records_buoc_idx; ALTER TABLE doc.records DROP COLUMN buoc; nạp lại agent.mcp_catalog_upsert bản 0008 (không có buoc).
BEGIN;
ALTER TABLE doc.records ADD COLUMN IF NOT EXISTS buoc text CHECK (buoc IS NULL OR buoc ~ '^(0[0-9]|1[0-9]|20)$');   -- 01–20; 00 = văn bản chung / chưa chắc
CREATE INDEX IF NOT EXISTS records_buoc_idx ON doc.records (project_id, buoc) WHERE buoc IS NOT NULL;

CREATE OR REPLACE FUNCTION agent.mcp_catalog_upsert(p_task bigint, p_items jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, doc, public AS $$
DECLARE a agent.agents := agent._agent_for_task(p_task); rid bigint := agent._run_of_task(p_task); r agent.workflow_runs; pr core.projects; it jsonb; cat uuid; rec bigint; fid bigint;
        n_new int := 0; n_upd int := 0; cname text; rno text; ttl text;
BEGIN
  IF rid IS NULL THEN RAISE EXCEPTION 'Việc T-% không thuộc quy trình dự án nào', p_task; END IF;
  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 50 THEN RAISE EXCEPTION 'Gửi từ 1 đến 50 hồ sơ mỗi lần'; END IF;
  SELECT * INTO r FROM agent.workflow_runs WHERE id = rid; SELECT * INTO pr FROM core.projects WHERE id = r.project_id;
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    cname := left(btrim(coalesce(it->>'category', '')), 80); ttl := left(btrim(coalesce(it->>'title', '')), 300); rno := nullif(left(btrim(coalesce(it->>'record_no', '')), 120), '');
    IF cname = '' OR length(ttl) < 3 THEN RAISE EXCEPTION 'Mỗi hồ sơ cần category và title (từ 3 ký tự)'; END IF;
    IF coalesce(it->>'buoc', '') <> '' AND (it->>'buoc') !~ '^(0[0-9]|1[0-9]|20)$' THEN RAISE EXCEPTION 'buoc phải từ 00 đến 20 (00 = văn bản chung hoặc chưa chắc)'; END IF;
    SELECT id INTO cat FROM doc.record_categories WHERE company_id = r.company_id AND name = cname;
    IF cat IS NULL THEN INSERT INTO doc.record_categories (company_id, name) VALUES (r.company_id, cname) RETURNING id INTO cat; END IF;
    rec := NULL;
    IF rno IS NOT NULL THEN SELECT id INTO rec FROM doc.records WHERE company_id = r.company_id AND project_id = r.project_id AND record_no = rno; END IF;
    IF rec IS NULL THEN
      INSERT INTO doc.records (company_id, category_id, record_no, title, description, department_id, project_id, owner_id, issued_on, expires_on, contract_value, executed_value, status, buoc, created_by)
      VALUES (r.company_id, cat, rno, ttl, left(it->>'description', 4000), pr.department_id, r.project_id, r.supervisor,
              nullif(it->>'issued_on', '')::date, nullif(it->>'expires_on', '')::date, nullif(it->>'contract_value', '')::bigint, nullif(it->>'executed_value', '')::bigint,
              coalesce(nullif(it->>'status', ''), 'active'), nullif(it->>'buoc', ''), a.user_id) RETURNING id INTO rec;
      n_new := n_new + 1;
    ELSE
      UPDATE doc.records SET category_id = cat, title = ttl, description = coalesce(left(it->>'description', 4000), description), issued_on = coalesce(nullif(it->>'issued_on', '')::date, issued_on),
             expires_on = coalesce(nullif(it->>'expires_on', '')::date, expires_on), contract_value = coalesce(nullif(it->>'contract_value', '')::bigint, contract_value),
             executed_value = coalesce(nullif(it->>'executed_value', '')::bigint, executed_value), buoc = coalesce(nullif(it->>'buoc', ''), buoc), updated_at = now() WHERE id = rec;
      n_upd := n_upd + 1;
    END IF;
    -- tệp nguồn: chỉ tệp đã được runner đăng ký cho công ty này
    IF coalesce(it->>'drive_id', '') <> '' THEN
      SELECT id INTO fid FROM core.files WHERE company_id = r.company_id AND drive_id = it->>'drive_id';
      IF fid IS NOT NULL THEN
        INSERT INTO core.attachments (company_id, file_id, entity_type, entity_id, role, added_by, actor) VALUES (r.company_id, fid, 'record', rec::text, 'source', a.user_id, 'agent:' || a.code) ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END LOOP;
  INSERT INTO core.audit_log (company_id, actor, user_id, module, action, entity_type, entity_id, summary)
  VALUES (r.company_id, 'agent:' || a.code, a.user_id, 'doc', 'catalog_upsert', 'task', p_task::text, 'Danh mục hồ sơ dự án ' || pr.name || ': +' || n_new || ' mới, ' || n_upd || ' cập nhật');
  RETURN jsonb_build_object('created', n_new, 'updated', n_upd);
END $$;
COMMIT;
