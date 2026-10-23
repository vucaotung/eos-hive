-- 0011 · Màn hình "Kết quả" của dự án: hàm agent.app_project_results (tiến độ và kết quả từng việc của lần chạy, danh mục hồ sơ, báo cáo/tài liệu, kho tri thức).
-- Nguồn chính: db/62_workflow.sql. Idempotent. down: DROP FUNCTION agent.app_project_results(jsonb).
BEGIN;
CREATE OR REPLACE FUNCTION agent.app_project_results(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, doc, kb, public AS $$
DECLARE me core.users := agent._web_me(); pr core.projects; r agent.workflow_runs; b kb.bases; my text;
BEGIN
  SELECT * INTO pr FROM core.projects WHERE id = agent._uuid(p, 'project_id');
  IF pr.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy dự án'; END IF;
  my := agent._need_role(me.id, pr.company_id, ARRAY['owner','admin','manager','member']);
  SELECT * INTO r FROM agent.workflow_runs WHERE project_id = pr.id ORDER BY id DESC LIMIT 1;
  IF NOT (my IN ('owner','admin') OR agent._can_manage_project(me.id, pr) OR r.supervisor = me.id
          OR EXISTS (SELECT 1 FROM core.project_members m WHERE m.project_id = pr.id AND m.user_id = me.id)) THEN
    RAISE EXCEPTION 'Bạn không có quyền xem kết quả của dự án này' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO b FROM kb.bases WHERE project_id = pr.id AND scope = 'project' ORDER BY created_at DESC LIMIT 1;
  RETURN jsonb_build_object(
    'project', jsonb_build_object('id', pr.id, 'name', pr.name, 'slug', pr.slug),
    'run', CASE WHEN r.id IS NULL THEN NULL ELSE jsonb_build_object('id', r.id, 'state', r.state, 'root_task', r.root_task, 'created_at', r.created_at, 'supervisor', r.supervisor,
        'source_url', 'https://drive.google.com/drive/folders/' || r.drive_folder_id, 'md_url', CASE WHEN r.md_folder_id IS NULL THEN NULL ELSE 'https://drive.google.com/drive/folders/' || r.md_folder_id END) END,
    'tasks', coalesce((SELECT jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'status', t.status, 'agent', (SELECT code FROM agent.agents WHERE id = t.agent_id), 'skill', x.skill,
                'stage', x.scope->>'stage', 'result', t.result, 'completed_at', t.completed_at) ORDER BY t.id)
              FROM agent.task_scopes x JOIN work.tasks t ON t.id = x.task_id WHERE x.run_id = r.id), '[]'),
    'files', coalesce((SELECT jsonb_agg(jsonb_build_object('name', f.name, 'url', f.web_url, 'task_id', a.entity_id::bigint, 'at', f.synced_at) ORDER BY f.synced_at DESC)
              FROM core.attachments a JOIN core.files f ON f.id = a.file_id JOIN agent.task_scopes x ON x.task_id = a.entity_id::bigint AND a.entity_type = 'task'
             WHERE x.run_id = r.id AND f.name ~* '^T-[0-9]+ - '), '[]'),
    'records', coalesce((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'category', c.name, 'record_no', d.record_no, 'title', d.title, 'description', d.description, 'issued_on', d.issued_on,
                'expires_on', d.expires_on, 'contract_value', d.contract_value, 'executed_value', d.executed_value, 'status', d.status,
                'file_url', (SELECT f.web_url FROM core.attachments a JOIN core.files f ON f.id = a.file_id WHERE a.entity_type = 'record' AND a.entity_id = d.id::text ORDER BY a.id LIMIT 1),
                'file_name', (SELECT f.name FROM core.attachments a JOIN core.files f ON f.id = a.file_id WHERE a.entity_type = 'record' AND a.entity_id = d.id::text ORDER BY a.id LIMIT 1))
                ORDER BY c.sort, c.name, d.issued_on NULLS LAST, d.id)
              FROM doc.records d JOIN doc.record_categories c ON c.id = d.category_id WHERE d.project_id = pr.id), '[]'),
    'kb', CASE WHEN b.id IS NULL THEN NULL ELSE jsonb_build_object('name', b.name, 'ready', b.weknora_kb_id NOT LIKE 'pending:%', 'sources', (SELECT count(*) FROM kb.sources s WHERE s.base_id = b.id AND s.state = 'loaded')) END);
END $$;
REVOKE ALL ON FUNCTION agent.app_project_results(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.app_project_results(jsonb) TO web_svc;
COMMIT;
