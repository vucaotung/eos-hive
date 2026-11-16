-- Hai việc định kỳ MẪU cho bảo trì dữ liệu (docs/20): rà Wiki KB dự án hằng tuần (quan-tri-du-lieu) và rà hiệu lực KB pháp luật hằng tháng (phap-che).
-- KHÔNG bật sẵn (active = false). Chạy tay, idempotent:
--   psql -v company=<uuid công ty> -v project=<slug dự án> -v owner_email=<email chủ sở hữu> -f deploy/setup_wiki_maintenance.sql
-- Bật sau khi xem một lần chạy thử:  UPDATE work.recurrences SET active = true WHERE company_id = '<uuid>' AND agent_code IS NOT NULL;
-- Người nhận việc: wiki_lint → người theo dõi dự án (quản lý dự án); law_review → chủ sở hữu. Việc sinh ra mang phạm vi chỉ đọc (db/66_standalone.sql).
-- Yêu cầu: migration 0031–0035; agent quan-tri-du-lieu và phap-che đã bật cho công ty (phap-che: deploy/setup_law.sql).
\set ON_ERROR_STOP 1
BEGIN;
-- 1. Rà Wiki dự án: thứ Hai hằng tuần
INSERT INTO work.recurrences (company_id, title, description, project_id, assignee_id, priority, freq, interval_n, weekdays, due_offset, skip_holidays, next_run, active, agent_code, scope, created_by)
SELECT p.company_id, 'Rà Wiki KB dự án ' || p.name || ' (hằng tuần)',
       'Quản trị dữ liệu AI rà Wiki của KB dự án (skill bao-tri-wiki): trang mồ côi, liên kết hỏng, chỉ mục lệch, trùng chủ thể, số liệu mâu thuẫn, trang cũ, tổng quan thiếu bước. Chỉ báo cáo, không sửa Wiki.',
       p.id, coalesce(p.manager_id, o.id), 'medium', 'weekly', 1, ARRAY[1], 3, true,
       (date_trunc('week', (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date) + interval '7 days')::date, false,
       'quan-tri-du-lieu', jsonb_build_object('stage', 'wiki_lint', 'project', p.slug, 'skill', 'bao-tri-wiki'), o.id
  FROM core.projects p, (SELECT id FROM core.users WHERE lower(email) = lower(:'owner_email') AND kind = 'person') o
 WHERE p.company_id = :'company'::uuid AND p.slug = :'project'
   AND NOT EXISTS (SELECT 1 FROM work.recurrences r WHERE r.company_id = p.company_id AND r.agent_code = 'quan-tri-du-lieu' AND r.scope->>'project' = p.slug);
-- 2. Rà hiệu lực KB pháp luật: ngày 1 hằng tháng, cho từng KB pháp luật của công ty
INSERT INTO work.recurrences (company_id, title, description, assignee_id, priority, freq, interval_n, month_day, due_offset, skip_holidays, next_run, active, agent_code, scope, created_by)
SELECT s.company_id, 'Rà hiệu lực KB pháp luật ' || k || ' (hằng tháng)',
       'Pháp chế AI đối chiếu từng văn bản trong KB với nguồn chính thống và rà Wiki của KB (skill ra-hieu-luc-phap-luat). Chỉ báo cáo và đề xuất; đánh dấu hay nạp mới cần việc law_ingest do chủ sở hữu tạo.',
       o.id, 'medium', 'monthly', 1, 1, 5, false,
       (date_trunc('month', (now() AT TIME ZONE 'Asia/Ho_Chi_Minh')::date) + interval '1 month')::date, false,
       'phap-che', jsonb_build_object('stage', 'law_review', 'kb', k, 'skill', 'ra-hieu-luc-phap-luat'), o.id
  FROM agent.company_settings s CROSS JOIN LATERAL unnest(s.law_kb_names) k, (SELECT id FROM core.users WHERE lower(email) = lower(:'owner_email') AND kind = 'person') o
 WHERE s.company_id = :'company'::uuid
   AND NOT EXISTS (SELECT 1 FROM work.recurrences r WHERE r.company_id = s.company_id AND r.agent_code = 'phap-che' AND r.scope->>'kb' = k);
SELECT title, freq, active, agent_code, scope->>'stage' AS stage FROM work.recurrences WHERE company_id = :'company'::uuid AND agent_code IS NOT NULL ORDER BY title;
COMMIT;
