#!/usr/bin/env python3
"""Kiểm thử nghiệp vụ + phân quyền trực tiếp trên Postgres (đóng vai từng người qua JWT claims).
Chạy: python3 test_db.py "host=/tmp/pgtest port=5544 user=postgres dbname=deo_work"
"""
import json, sys, psycopg

DSN = sys.argv[1] if len(sys.argv) > 1 else "host=/tmp/pgtest port=5544 user=postgres dbname=deo_work"
conn = psycopg.connect(DSN, autocommit=True)
ok = fail = 0

def q(sql, args=(), role=None, sub=None):
    with conn.transaction():
        with conn.cursor() as cur:
            if role:
                cur.execute("select set_config('request.jwt.claims', %s, true)", (json.dumps({"role": role, "sub": sub}),))
                cur.execute(f"set local role {role}")
            cur.execute("set local search_path = app, public")
            cur.execute(sql, args)
            return cur.fetchall() if cur.description else None

def check(name, cond):
    global ok, fail
    if cond: ok += 1; print("  ok  ", name)
    else: fail += 1; print("  FAIL", name)

def expect_error(name, fn, contains):
    global ok, fail
    try:
        fn(); fail += 1; print("  FAIL", name, "(không lỗi)")
    except psycopg.Error as e:
        msg = str(e).split("\n")[0]
        if contains in msg: ok += 1; print("  ok  ", name, "→", msg)
        else: fail += 1; print("  FAIL", name, "→", msg)

def login(sub, email, name, code=None):
    return q("select app.auth_login(%s,%s,%s,null,%s)", (sub, email, name, code), role="auth_svc")[0][0]

S = ""
print("Khởi tạo công ty")
code = q("select app.bootstrap_company('5balance','5Balance', 'tung@gmail.com', %s)",
         (json.dumps([{"code": "A", "name": "Pháp chế"}, {"code": "B", "name": "Tài chính"}, {"code": "C", "name": "Dự án"}]),))[0][0]
check("bootstrap trả mã mời 8 ký tự", len(code) == 8)
co = q("select id from app.companies where slug='5balance'")[0][0]
dA, dB = [r[0] for r in q("select id from app.departments where company_id=%s order by code limit 2", (co,))]

print("Đăng nhập + mã mời")
expect_error("người lạ không có mã bị chặn", lambda: login("g-x", "x@gmail.com", "Lạ"), "INVITE_REQUIRED")
expect_error("mã của email khác bị chặn", lambda: login("g-y", "y@gmail.com", "Y", code), "email khác")
tung = login("g-tung", "Tung@Gmail.com", "Tùng", code)
check("owner vào được bằng mã", tung is not None)
expect_error("mã 1 lượt không dùng lại được", lambda: login("g-z", "tung@gmail.com", "Z", code), "hết lượt")
check("lần sau đăng nhập không cần mã", login("g-tung", "tung@gmail.com", "Tùng") == tung)

inv_mgr = q(S + "select code from create_invite(%s,'manager',%s,null,1,7,'TP pháp chế')", (co, dA), "app_user", str(tung))[0][0]
inv_mem = q(S + "select code from create_invite(%s,'member',%s,null,5,7,null)", (co, dA), "app_user", str(tung))[0][0]
inv_b = q(S + "select code from create_invite(%s,'member',%s,null,5,7,null)", (co, dB), "app_user", str(tung))[0][0]
minh = login("g-minh", "minh@gmail.com", "Minh", inv_mgr)
an = login("g-an", "an@gmail.com", "An", inv_mem)
binh = login("g-binh", "binh@gmail.com", "Bình", inv_b)
check("3 người vào bằng mã mời", all([minh, an, binh]))
expect_error("thành viên không tạo được mã mời", lambda: q(S + "select create_invite(%s,'member',%s)", (co, dA), "app_user", str(an)), "không có quyền")
expect_error("trưởng phòng không mời vào phòng khác", lambda: q(S + "select create_invite(%s,'member',%s)", (co, dB), "app_user", str(minh)), "phòng của mình")

print("Quy trình duyệt 2 cấp")
flow = q(S + "select id from save_flow(%s,'Văn bản ra ngoài',%s,null,null)",
         (co, json.dumps([{"name": "Trưởng phòng", "approver_role": "manager"}, {"name": "Giám đốc", "approver_role": "owner"}])),
         "app_user", str(tung))[0][0]
expect_error("trưởng phòng không tạo được quy trình", lambda: q(S + "select save_flow(%s,'x',%s)", (co, '[{"name":"a","approver_role":"admin"}]'), "app_user", str(minh)), "không có quyền")

print("Giao việc + phân quyền xem")
t1 = q(S + "select id from create_task(%s,'Soạn công văn gia hạn tiến độ','Gửi UBND tỉnh',%s,%s,current_date+3,'high',null,null,null,%s)",
       (co, dA, an, flow), "app_user", str(minh))[0][0]
t2 = q(S + "select id from create_task(%s,'Lập bảng kinh phí bồi thường',null,%s,%s)", (co, dB, binh), "app_user", str(tung))[0][0]
check("An (phòng A) thấy việc phòng A", q(S + "select count(*) from tasks where id=%s", (t1,), "app_user", str(an))[0][0] == 1)
check("An không thấy việc phòng B", q(S + "select count(*) from tasks where id=%s", (t2,), "app_user", str(an))[0][0] == 0)
check("Bình không thấy việc phòng A", q(S + "select count(*) from tasks where id=%s", (t1,), "app_user", str(binh))[0][0] == 0)
check("Owner thấy cả hai", q(S + "select count(*) from tasks where id in (%s,%s)", (t1, t2), "app_user", str(tung))[0][0] == 2)
expect_error("Bình không sửa được việc phòng A", lambda: q(S + "select update_task(%s,'{\"title\":\"x\"}')", (t1,), "app_user", str(binh)), "Không tìm thấy")
expect_error("không ghi bảng trực tiếp", lambda: q(S + "update tasks set title='hack' where id=%s", (t1,), "app_user", str(tung)), "permission denied")
expect_error("không tự đặt Xong", lambda: q(S + "select update_task(%s,'{\"status\":\"done\"}')", (t1,), "app_user", str(an)), "Nộp kết quả")

print("Nộp → duyệt cấp 1 → trả lại → nộp lại → duyệt 2 cấp")
q(S + "select add_link(%s,'https://drive.google.com/file/d/abc','Bản nháp v1')", (t1,), "app_user", str(an))
q(S + "select submit_task(%s,'Đã soạn xong bản nháp')", (t1,), "app_user", str(an))
check("việc chuyển Chờ duyệt bước 1", q("select status, current_step from app.tasks where id=%s", (t1,))[0] == ("in_review", 1))
expect_error("An không tự duyệt", lambda: q(S + "select decide(%s,true)", (t1,), "app_user", str(an)), "không phải người duyệt")
check("Minh thấy trong hộp chờ duyệt", q(S + "select count(*) from my_approvals where task_id=%s", (t1,), "app_user", str(minh))[0][0] == 1)
expect_error("trả lại phải có lý do", lambda: q(S + "select decide(%s,false,'')", (t1,), "app_user", str(minh)), "lý do")
q(S + "select decide(%s,false,'Sửa căn cứ pháp lý')", (t1,), "app_user", str(minh))
check("trả lại → Đang làm, lần nộp 2", q("select status, attempts from app.tasks where id=%s", (t1,))[0] == ("in_progress", 1))
q(S + "select submit_task(%s,'Đã sửa')", (t1,), "app_user", str(an))
q(S + "select decide(%s,true,null)", (t1,), "app_user", str(minh))
check("qua bước 1 → bước 2", q("select status, current_step from app.tasks where id=%s", (t1,))[0] == ("in_review", 2))
expect_error("trưởng phòng không duyệt bước Giám đốc", lambda: q(S + "select decide(%s,true)", (t1,), "app_user", str(minh)), "không phải người duyệt")
q(S + "select decide(%s,true,'Đồng ý')", (t1,), "app_user", str(tung))
check("duyệt xong → Xong", q("select status, completed_at is not null from app.tasks where id=%s", (t1,))[0] == ("done", True))
check("nhật ký có đổi trạng thái", q("select count(*) from app.task_events where task_id=%s and field='status'", (t1,))[0][0] == 4)

print("Agent")
t3 = q(S + "select id from create_task(%s,'Tra cứu ngày cấp GCN',null,%s,%s,null,'medium',null,null,'tra-cuu')", (co, dA, an), "app_user", str(an))[0][0]
got = q(S + "select id from agent_claim('tra-cuu')", (), "agent", "hermes:ops-admin")
check("agent nhận đúng việc", got and got[0][0] == t3)
check("lần nhận thứ hai không có việc", not q(S + "select id from agent_claim('tra-cuu')", (), "agent", "hermes:ops-admin"))
q(S + "select agent_ask(%s,'Dùng KL 21 hay A.2?')", (t3,), "agent", "hermes:ops-admin")
q(S + "select answer_agent(%s,'Dùng KL 21')", (t3,), "app_user", str(an))
check("trả lời → agent nhận lại được", q(S + "select id from agent_claim('tra-cuu')", (), "agent", "hermes:ops-admin")[0][0] == t3)
q(S + "select submit_task(%s,'05/01/2012 theo KL 21 trang 3')", (t3,), "agent", "hermes:ops-admin")
check("không có quy trình → Xong", q("select status from app.tasks where id=%s", (t3,))[0][0] == "done")
expect_error("người dùng không gọi được hàm agent", lambda: q(S + "select agent_claim('tra-cuu')", (), "app_user", str(an)), "permission denied")

print("Drive")
expect_error("link sai dạng bị chặn", lambda: q(S + "select set_drive_folder('https://example.com/x')", (), "app_user", str(an)), "Google Drive")
q(S + "select set_drive_folder('https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOp?usp=sharing')", (), "app_user", str(an))
qq = q(S + "select user_id, folder_id, expected_names from agent_drive_queue()", (), "agent", "hermes:drive")
check("agent thấy thư mục chờ kiểm tra với tên chuẩn", qq and qq[0][1] == "1AbCdEfGhIjKlMnOp" and qq[0][2] == ["DEO - 5balance - A - An"])
q(S + "select agent_drive_result(%s,true,'Tên và quyền đúng')", (an,), "agent", "hermes:drive")
n = q(S + "select agent_drive_files(%s,%s)", (an, json.dumps([
    {"file_id": "f1", "name": f"T-{t1} Cong van v2.docx", "web_url": "https://docs.google.com/document/d/f1", "mime_type": "doc"},
    {"file_id": "f2", "name": "Ghi chu rieng.txt", "web_url": "https://drive.google.com/file/d/f2"}])), "agent", "hermes:drive")[0][0]
check("agent ghi 2 tệp, tự gắn T-xx", n == 2 and q("select task_id from app.drive_files where file_id='f1'")[0][0] == t1)
check("Minh thấy tệp đã gắn việc", q(S + "select count(*) from drive_files", (), "app_user", str(minh))[0][0] == 1)
check("Bình không thấy tệp nào của An", q(S + "select count(*) from drive_files", (), "app_user", str(binh))[0][0] == 0)

print("Báo cáo")
rep = q(S + "select department_id, done_30d from report_departments where company_id=%s", (co,), "app_user", str(tung))
check("owner thấy báo cáo 2 phòng", len(rep) == 2)
rep_b = q(S + "select count(*) from report_departments", (), "app_user", str(binh))[0][0]
check("Bình chỉ thấy báo cáo phòng mình", rep_b == 1)

print("Quản trị thành viên")
expect_error("owner cuối cùng không tự hạ quyền", lambda: q(S + "select set_member(%s,%s,'admin')", (co, tung), "app_user", str(tung)), "chính mình")
q(S + "select set_member(%s,%s,'member',%s,null,false)", (co, binh, dB), "app_user", str(tung))
expect_error("người bị khóa khỏi công ty không đăng nhập được", lambda: login("g-binh", "binh@gmail.com", "Bình"), "chưa thuộc công ty")
check("me() trả về công ty và vai trò", json.loads(json.dumps(q(S + "select me()", (), "app_user", str(minh))[0][0]))["memberships"][0]["role"] == "manager")

print(f"\n{ok} đạt, {fail} lỗi")
sys.exit(1 if fail else 0)
