#!/usr/bin/env python3
"""Nhập việc còn dùng từ Ever Teams (xuất JSON) vào Enterprise OS khi gỡ Ever Teams (docs/13). Một lần, idempotent (đánh dấu ever-id trong mô tả).
Dùng: scripts/ever_teams_migrate.py <tasks.json> | ssh vps169 'docker exec -i eos-postgres psql -U postgres -X -q -At -d eos -v ON_ERROR_STOP=1'
Bỏ việc thử (tiêu đề bắt đầu [TEST / Thử task). Ánh xạ: open→todo, in-progress→in_progress, done→done; người phụ trách theo email.
Không in bí mật; chỉ sinh SQL."""
import json, re, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
q = lambda s: "$q$" + s.replace("$q$", "") + "$q$"
ST = {'open': 'todo', 'in-progress': 'in_progress', 'done': 'done'}
skip = re.compile(r'^(\[TEST|Thử task)', re.I)
rows = [x for x in d if x['title'] and not skip.match(x['title']) and x['status'] in ST]
out = ["BEGIN;",
       "CREATE TEMP TABLE _c AS SELECT c.id cid, (SELECT id FROM core.departments WHERE company_id=c.id AND code='HC') dept, (SELECT id FROM core.users WHERE email='vucaotung@gmail.com') owner FROM core.companies c WHERE c.slug='valnex';",
       "INSERT INTO core.projects (company_id, department_id, code, slug, name, description, status, manager_id) SELECT cid, dept, 'KDCTL', 'kdc-thanh-lap', 'KDC Thành Lập', 'Khu dân cư Thành Lập: tiến trình thủ tục giao đất (nhập từ Ever Teams)', 'active', owner FROM _c ON CONFLICT (company_id, slug) DO NOTHING;"]
for x in rows:
    proj = {'KDC Thành Lập': 'kdc-thanh-lap'}.get(x['project'])
    who = [e for e in (x['assignees'] or [])]
    asg = f"(SELECT id FROM core.users WHERE lower(email)=lower({q(who[0])}) AND id IN (SELECT user_id FROM core.memberships m JOIN _c ON m.company_id=_c.cid))" if who else "NULL"
    desc = (x['description'] or '').strip()
    desc = (desc + "\n\n" if desc else "") + f"Nhập từ Ever Teams #{x['number']} (ever-id:{x['id']}), cập nhật cuối {str(x['updated'])[:10]}."
    pr = 'urgent' if x.get('priority') == 'urgent' else 'medium'
    due = f"{q(x['due'][:10])}::date" if x.get('due') else "NULL"
    done = ST[x['status']] == 'done'
    out.append(f"""INSERT INTO work.tasks (company_id, department_id, project_id, title, description, status, priority, assignee_id, due_date, created_by, source, completed_at, progress, kpi_counted)
SELECT cid, dept, {"(SELECT id FROM core.projects WHERE company_id=_c.cid AND slug=" + q(proj) + ")" if proj else "NULL"}, left({q(x['title'])}, 300), left({q(desc)}, 8000), '{ST[x['status']]}', '{pr}', {asg}, {due}, owner, 'manual',
       {q(str(x['updated']))}::timestamptz IF_DONE, {100 if done else 0}, false FROM _c
 WHERE NOT EXISTS (SELECT 1 FROM work.tasks t WHERE t.description LIKE '%ever-id:{x['id']}%');""".replace("IF_DONE", "" if done else "").replace(f"{q(str(x['updated']))}::timestamptz ", f"{q(str(x['updated']))}::timestamptz" if done else "NULL"))
out.append("SELECT count(*) AS nhap_tu_ever FROM work.tasks WHERE description LIKE '%ever-id:%';")
out.append("COMMIT;")
print("\n".join(out))
