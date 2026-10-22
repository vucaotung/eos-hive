-- 0007 · Quản lý dự án đầy đủ: cài đặt (mô tả, trạng thái, người quản lý, ngày), thành viên dự án, xóa dự án; app_org trả thêm trường dự án.
-- Idempotent (CREATE OR REPLACE, GRANT lặp được). Việc thuộc dự án bị xóa chỉ mất liên kết dự án (work.tasks.project_id ON DELETE SET NULL).
-- down: DROP FUNCTION agent.app_project_member_set, app_project_member_remove, app_project_delete, agent._can_manage_project; app_org/app_project_save khôi phục từ migration 0006.
BEGIN;
CREATE OR REPLACE FUNCTION agent.app_org(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, work, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id');
BEGIN
  PERFORM agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  RETURN jsonb_build_object(
    'departments', coalesce((SELECT jsonb_agg(jsonb_build_object('id', d.id, 'code', d.code, 'name', d.name, 'active', d.active, 'parent_id', d.parent_id) ORDER BY d.code)
                               FROM core.departments d WHERE d.company_id = cid), '[]'),
    'members', coalesce((SELECT jsonb_agg(jsonb_build_object('user_id', m.user_id, 'department_id', m.department_id, 'role', agent._role_raw(m.user_id, cid), 'title', m.title,
                       'active', m.active, 'user', jsonb_build_object('id', u.id, 'name', u.name, 'email', u.email, 'avatar_url', u.avatar_url, 'drive_status', u.drive_state, 'active', u.active))
                       ORDER BY u.name)
                  FROM core.memberships m JOIN core.users u ON u.id = m.user_id WHERE m.company_id = cid AND u.kind = 'person'), '[]'),
    'projects', coalesce((SELECT jsonb_agg(jsonb_build_object('id', pr.id, 'slug', pr.slug, 'code', pr.code, 'name', pr.name, 'department_id', pr.department_id, 'drive_url', pr.drive_url,
                       'description', pr.description, 'status', pr.status, 'manager_id', pr.manager_id, 'start_date', pr.start_date, 'end_date', pr.end_date,
                       'active', pr.status IN ('planned','active','paused'), 'can_manage', agent._can_manage_project(me.id, pr)) ORDER BY pr.name)
                  FROM core.projects pr WHERE pr.company_id = cid), '[]'),
    'project_members', coalesce((SELECT jsonb_agg(jsonb_build_object('project_id', x.project_id, 'user_id', x.user_id, 'role', x.role))
                  FROM core.project_members x JOIN core.projects pr ON pr.id = x.project_id WHERE pr.company_id = cid), '[]'),
    'flows', coalesce((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'department_id', f.department_id, 'active', f.active,
                       'steps', coalesce((SELECT jsonb_agg(jsonb_build_object('step_no', s.step_no, 'name', s.name, 'approver_user', s.approver_user,
                                 'approver_role', CASE s.approver_kind WHEN 'dept_head' THEN 'manager' WHEN 'project_manager' THEN 'project_manager'
                                                  WHEN 'role' THEN (SELECT r.code FROM core.roles r WHERE r.id = s.approver_role) END) ORDER BY s.step_no)
                                    FROM core.approval_steps s WHERE s.flow_id = f.id), '[]')) ORDER BY f.name)
                  FROM core.approval_flows f WHERE f.company_id = cid AND f.active AND f.applies_to IN ('task','any')), '[]'));
END $$;

-- ---------- Dự án: cài đặt, thành viên, xóa ----------
-- Quản lý được dự án: owner/admin; trưởng phòng của phòng sở hữu dự án; người quản lý dự án (manager_id)
CREATE OR REPLACE FUNCTION agent._can_manage_project(p_user uuid, pr core.projects) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = agent, core, public AS $$
  SELECT CASE WHEN x.r IS NULL THEN false WHEN x.r IN ('owner','admin') THEN true
              WHEN x.r = 'manager' THEN pr.manager_id = p_user OR (pr.department_id IS NOT NULL AND pr.department_id = (SELECT m.department_id FROM core.memberships m WHERE m.user_id = p_user AND m.company_id = pr.company_id))
              ELSE pr.manager_id = p_user END
    FROM (SELECT agent._role_of(p_user, pr.company_id) AS r) x
$$;

CREATE OR REPLACE FUNCTION agent.app_project_save(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); cid uuid := agent._uuid(p, 'company_id'); pid uuid := agent._uuid(p, 'id'); my text; pr core.projects;
        nm text; sl text; dept uuid; du text; st text; mg uuid; cd text; n int := 1; ds text; sd date; ed date;
BEGIN
  IF pid IS NOT NULL THEN
    SELECT * INTO pr FROM core.projects WHERE id = pid;
    IF pr.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy dự án'; END IF;
    cid := pr.company_id;
    IF NOT agent._can_manage_project(me.id, pr) THEN RAISE EXCEPTION 'Bạn không có quyền sửa dự án này' USING ERRCODE = '42501'; END IF;
  END IF;
  my := agent._need_role(me.id, cid, ARRAY['owner','admin','manager','member']);
  IF pid IS NULL AND my = 'member' THEN RAISE EXCEPTION 'Chỉ quản trị hoặc trưởng phòng mới tạo dự án' USING ERRCODE = '42501'; END IF;
  nm := btrim(coalesce(p->>'name', pr.name, '')); sl := btrim(coalesce(p->>'slug', pr.slug, ''));
  du := CASE WHEN p ? 'drive_url' THEN nullif(btrim(coalesce(p->>'drive_url', '')), '') ELSE pr.drive_url END;
  ds := CASE WHEN p ? 'description' THEN nullif(btrim(coalesce(p->>'description', '')), '') ELSE pr.description END;
  sd := CASE WHEN p ? 'start_date' THEN nullif(btrim(coalesce(p->>'start_date', '')), '')::date ELSE pr.start_date END;
  ed := CASE WHEN p ? 'end_date' THEN nullif(btrim(coalesce(p->>'end_date', '')), '')::date ELSE pr.end_date END;
  mg := CASE WHEN p ? 'manager_id' THEN agent._uuid(p, 'manager_id') WHEN pid IS NULL THEN me.id ELSE pr.manager_id END;
  st := coalesce(p->>'status', CASE WHEN p ? 'active' THEN CASE WHEN (p->>'active')::boolean THEN 'active' ELSE 'done' END END, pr.status, 'active');
  -- phòng ban: người chỉ là quản lý dự án không đổi phòng; trưởng phòng chỉ đặt vào phòng mình
  dept := CASE WHEN pid IS NOT NULL AND my NOT IN ('owner','admin') AND my <> 'manager' THEN pr.department_id
               WHEN p ? 'department_id' THEN agent._uuid(p, 'department_id') WHEN pid IS NULL THEN NULL ELSE pr.department_id END;
  IF my = 'manager' AND dept IS DISTINCT FROM (SELECT department_id FROM core.memberships WHERE user_id = me.id AND company_id = cid) AND (pid IS NULL OR dept IS DISTINCT FROM pr.department_id) THEN
    RAISE EXCEPTION 'Trưởng phòng chỉ đặt dự án vào phòng của mình' USING ERRCODE = '42501';
  END IF;
  IF length(nm) < 2 OR length(nm) > 160 THEN RAISE EXCEPTION 'Tên dự án từ 2 đến 160 ký tự'; END IF;
  IF sl !~ '^[a-z0-9]+(-[a-z0-9]+)*$' OR length(sl) > 60 THEN RAISE EXCEPTION 'Mã dự án chỉ gồm chữ thường, số và gạch nối'; END IF;
  IF du IS NOT NULL AND du !~ '^https://' THEN RAISE EXCEPTION 'Link Drive phải bắt đầu bằng https://'; END IF;
  IF length(coalesce(ds, '')) > 4000 THEN RAISE EXCEPTION 'Mô tả tối đa 4000 ký tự'; END IF;
  IF st NOT IN ('planned','active','paused','done','cancelled') THEN RAISE EXCEPTION 'Trạng thái dự án không hợp lệ'; END IF;
  IF sd IS NOT NULL AND ed IS NOT NULL AND ed < sd THEN RAISE EXCEPTION 'Ngày kết thúc phải sau ngày bắt đầu'; END IF;
  IF dept IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.departments WHERE id = dept AND company_id = cid) THEN RAISE EXCEPTION 'Phòng ban không thuộc công ty này'; END IF;
  IF mg IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.memberships WHERE user_id = mg AND company_id = cid AND active) THEN RAISE EXCEPTION 'Người quản lý dự án không thuộc công ty'; END IF;
  IF pid IS NULL THEN
    cd := upper(left(regexp_replace(sl, '[^a-z0-9]', '', 'g'), 16)); IF length(cd) < 2 THEN cd := 'DA' || cd; END IF;
    WHILE EXISTS (SELECT 1 FROM core.projects WHERE company_id = cid AND code = cd) LOOP n := n + 1; cd := upper(left(regexp_replace(sl, '[^a-z0-9]', '', 'g'), 14)) || n; END LOOP;
    INSERT INTO core.projects (company_id, department_id, code, slug, name, description, drive_url, status, manager_id, start_date, end_date)
    VALUES (cid, dept, cd, sl, nm, ds, du, st, mg, sd, ed) RETURNING id INTO pid;
  ELSE
    UPDATE core.projects SET department_id = dept, slug = sl, name = nm, description = ds, drive_url = du, status = st, manager_id = mg, start_date = sd, end_date = ed WHERE id = pid;
  END IF;
  IF mg IS NOT NULL THEN
    INSERT INTO core.project_members (project_id, user_id, role) VALUES (pid, mg, 'manager') ON CONFLICT (project_id, user_id) DO UPDATE SET role = 'manager';
  END IF;
  PERFORM agent._audit(cid, me.id, 'project_save', 'project', pid::text, 'Lưu dự án ' || nm);
  RETURN jsonb_build_object('id', pid);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'Mã dự án % đã có', sl;
END $$;

CREATE OR REPLACE FUNCTION agent.app_project_member_set(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); pr core.projects; uid uuid := agent._uuid(p, 'user_id'); rl text := coalesce(p->>'role', 'member');
BEGIN
  SELECT * INTO pr FROM core.projects WHERE id = agent._uuid(p, 'project_id');
  IF pr.id IS NULL OR agent._role_of(me.id, pr.company_id) IS NULL THEN RAISE EXCEPTION 'Không tìm thấy dự án' USING ERRCODE = '42501'; END IF;
  IF NOT agent._can_manage_project(me.id, pr) THEN RAISE EXCEPTION 'Bạn không có quyền quản lý thành viên dự án này' USING ERRCODE = '42501'; END IF;
  IF rl NOT IN ('manager','member','viewer') THEN RAISE EXCEPTION 'Vai trò trong dự án không hợp lệ'; END IF;
  IF NOT EXISTS (SELECT 1 FROM core.memberships WHERE user_id = uid AND company_id = pr.company_id AND active) THEN RAISE EXCEPTION 'Người này không thuộc công ty'; END IF;
  IF uid = pr.manager_id AND rl <> 'manager' THEN RAISE EXCEPTION 'Đổi người quản lý dự án trong phần cài đặt trước'; END IF;
  INSERT INTO core.project_members (project_id, user_id, role) VALUES (pr.id, uid, rl) ON CONFLICT (project_id, user_id) DO UPDATE SET role = EXCLUDED.role;
  PERFORM agent._audit(pr.company_id, me.id, 'project_member_set', 'project', pr.id::text, 'Thành viên dự án ' || pr.name || ': ' || rl);
  RETURN jsonb_build_object('ok', true);
END $$;

CREATE OR REPLACE FUNCTION agent.app_project_member_remove(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, public AS $$
DECLARE me core.users := agent._web_me(); pr core.projects; uid uuid := agent._uuid(p, 'user_id');
BEGIN
  SELECT * INTO pr FROM core.projects WHERE id = agent._uuid(p, 'project_id');
  IF pr.id IS NULL OR agent._role_of(me.id, pr.company_id) IS NULL THEN RAISE EXCEPTION 'Không tìm thấy dự án' USING ERRCODE = '42501'; END IF;
  IF NOT agent._can_manage_project(me.id, pr) THEN RAISE EXCEPTION 'Bạn không có quyền quản lý thành viên dự án này' USING ERRCODE = '42501'; END IF;
  IF uid = pr.manager_id THEN RAISE EXCEPTION 'Không gỡ được người quản lý dự án; đổi người quản lý trong phần cài đặt'; END IF;
  DELETE FROM core.project_members WHERE project_id = pr.id AND user_id = uid;
  PERFORM agent._audit(pr.company_id, me.id, 'project_member_remove', 'project', pr.id::text, 'Gỡ thành viên khỏi dự án ' || pr.name);
  RETURN jsonb_build_object('ok', true);
END $$;

-- Xóa dự án: chỉ owner/admin hoặc trưởng phòng của phòng sở hữu. Việc thuộc dự án không bị xóa, chỉ mất liên kết dự án.
CREATE OR REPLACE FUNCTION agent.app_project_delete(p jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = agent, core, work, public AS $$
DECLARE me core.users := agent._web_me(); pr core.projects; my text; n int;
BEGIN
  SELECT * INTO pr FROM core.projects WHERE id = agent._uuid(p, 'id');
  IF pr.id IS NULL THEN RAISE EXCEPTION 'Không tìm thấy dự án'; END IF;
  my := agent._need_role(me.id, pr.company_id, ARRAY['owner','admin','manager']);
  IF my = 'manager' AND pr.department_id IS DISTINCT FROM (SELECT department_id FROM core.memberships WHERE user_id = me.id AND company_id = pr.company_id) THEN
    RAISE EXCEPTION 'Trưởng phòng chỉ xóa dự án của phòng mình' USING ERRCODE = '42501';
  END IF;
  SELECT count(*) INTO n FROM work.tasks WHERE project_id = pr.id;
  DELETE FROM core.projects WHERE id = pr.id;
  PERFORM agent._audit(pr.company_id, me.id, 'project_delete', 'project', pr.id::text, 'Xóa dự án ' || pr.name || ' (' || n || ' việc mất liên kết dự án)');
  RETURN jsonb_build_object('ok', true, 'tasks_unlinked', n);
END $$;

REVOKE ALL ON FUNCTION agent._can_manage_project(uuid, core.projects), agent.app_project_save(jsonb), agent.app_project_member_set(jsonb), agent.app_project_member_remove(jsonb), agent.app_project_delete(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION agent.app_project_save(jsonb), agent.app_project_member_set(jsonb), agent.app_project_member_remove(jsonb), agent.app_project_delete(jsonb) TO web_svc;
COMMIT;
