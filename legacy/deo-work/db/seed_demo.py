#!/usr/bin/env python3
"""Dữ liệu thử nghiệm qua đúng đường người dùng: đăng nhập (DEV_LOGIN) → mã mời → giao việc → nộp → duyệt.
Chạy sau reset.sh, khi PostgREST (:3300) và deo-auth (:8090, DEV_LOGIN=1) đang chạy.
  python3 seed_demo.py "host=/tmp/pgtest port=5544 user=postgres dbname=deo_work"
"""
import json, sys, datetime as dt, urllib.request, psycopg

DSN = sys.argv[1] if len(sys.argv) > 1 else "host=/tmp/pgtest port=5544 user=postgres dbname=deo_work"
API, AUTH = "http://localhost:3300", "http://localhost:8090"
db = psycopg.connect(DSN, autocommit=True)

def http(url, body=None, token=None, single=True):
    h = {"Content-Type": "application/json", "Accept": "application/vnd.pgrst.object+json" if single else "application/json"}
    if token: h["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=h, method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(req) as r:
            t = r.read().decode(); return json.loads(t) if t else None
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{url} → {e.code} {e.read().decode()}")

def login(email, name, code=None):
    return http(AUTH + "/auth/google", {"credential": f"dev:{email}:{name}", **({"invite": code} if code else {})})["token"]
def rpc(tok, fn, **args): return http(f"{API}/rpc/{fn}", args, tok)
def d(n): return (dt.date.today() + dt.timedelta(days=n)).isoformat()

code = db.execute("select app.bootstrap_company('5balance','5Balance', 'tung@gmail.com', %s)", (json.dumps([
    {"code": "PC", "name": "Pháp chế"}, {"code": "TC", "name": "Tài chính"}, {"code": "DA", "name": "Quản lý dự án"}, {"code": "HC", "name": "Hành chính"}]),)).fetchone()[0]
tung = login("tung@gmail.com", "Vũ Tùng", code)
co = db.execute("select id from app.companies where slug='5balance'").fetchone()[0].__str__()
dept = {r[0]: str(r[1]) for r in db.execute("select code, id from app.departments where company_id=%s", (co,))}

def invite(role, dcode, uses=1):
    return rpc(tung, "create_invite", p_company=co, p_role=role, p_department=dept[dcode], p_max_uses=uses, p_days=14)["code"]
people = {}
for email, name, role, dc in [("minh@gmail.com", "Trần Minh", "manager", "PC"), ("an@gmail.com", "Nguyễn Thu An", "member", "PC"),
                              ("binh@gmail.com", "Lê Bình", "manager", "TC"), ("ha@gmail.com", "Phạm Thu Hà", "member", "DA"),
                              ("quan@gmail.com", "Đỗ Quân", "manager", "DA"), ("lan@gmail.com", "Hoàng Lan", "member", "HC")]:
    people[name.split()[-1]] = login(email, name, invite(role, dc))
uid = {r[0]: str(r[1]) for r in db.execute("select split_part(email,'@',1), id from app.users")}

flow2 = rpc(tung, "save_flow", p_company=co, p_name="Văn bản gửi cơ quan nhà nước", p_steps=[{"name": "Trưởng phòng", "approver_role": "manager"}, {"name": "Giám đốc", "approver_role": "owner"}])["id"]
flow1 = rpc(tung, "save_flow", p_company=co, p_name="Trưởng phòng duyệt", p_steps=[{"name": "Trưởng phòng", "approver_role": "manager"}])["id"]
proj = {}
for slug, name, dc in [("kdc-thanh-lap", "KDC Thành Lập", "DA"), ("phu-dong-central-home", "Phù Đổng Central Home", "PC"), ("thanh-my-loi-14-3ha", "Thạnh Mỹ Lợi 14,3 ha", "TC")]:
    proj[slug] = rpc(tung, "save_project", p_company=co, p_slug=slug, p_name=name, p_department=dept[dc])["id"]

def task(tok, title, dc, who=None, due=None, pri="medium", project=None, flow=None, agent=None, desc=None, parent=None):
    return rpc(tok, "create_task", p_company=co, p_title=title, p_description=desc, p_department=dept[dc], p_assignee=uid.get(who) if who else None,
               p_due=due, p_priority=pri, p_project=proj.get(project), p_parent=parent, p_agent_role=agent, p_flow=flow)["id"]

M, A, B, H, Q, L = people["Minh"], people["An"], people["Bình"], people["Hà"], people["Quân"], people["Lan"]
t1 = task(tung, "Chuẩn bị hồ sơ xin gia hạn tiến độ KDC Thành Lập", "DA", "quan", d(2), "urgent", "kdc-thanh-lap",
          desc="Nộp UBND tỉnh trước hạn. Gồm công văn, bảng tiến độ thực hiện, bảng tổng hợp kinh phí bồi thường.")
t2 = task(Q, "Soạn công văn xin gia hạn tiến độ", "PC", "an", d(2), "high", "kdc-thanh-lap", flow2, parent=t1, desc="Căn cứ pháp lý liệt kê ở cuối văn bản.")
rpc(A, "add_link", p_task=t2, p_url="https://docs.google.com/document/d/1cv-gia-han", p_title="Công văn gia hạn v2")
rpc(A, "submit_task", p_task=t2, p_note="Bản nháp 2 trang gửi UBND tỉnh, kèm bảng tiến độ thực hiện đến nay. Căn cứ pháp lý ở cuối văn bản.")
rpc(M, "decide", p_task=t2, p_approve=True)                       # qua bước 1, chờ Giám đốc
t3 = task(Q, "Tổng hợp kinh phí bồi thường đã chi trả theo từng đợt", "TC", None, d(3), "high", "kdc-thanh-lap", flow1, "tai-chinh", parent=t1)
t4 = task(M, "Đối chiếu diện tích chuyển đổi mục đích sử dụng đất", "PC", "an", d(-1), "high", "phu-dong-central-home", agent="phap-che")
t5 = task(B, "Rà soát điều khoản góp vốn trong MOU hợp tác", "TC", "binh", d(5), "medium", "thanh-my-loi-14-3ha", flow1)
rpc(B, "submit_task", p_task=t5, p_note="Đã rà soát 14 điều khoản, đánh dấu 3 điểm cần đàm phán lại trong bản nhận xét.")
t6 = task(H, "Cập nhật tiến độ thi công phần thô tuần 42", "DA", "ha", d(1))
t7 = task(Q, "Nghiệm thu cốp pha sàn tầng 2", "DA", "ha", d(0), "high")
t8 = task(L, "Gia hạn hợp đồng thuê văn phòng tầng 5", "HC", "lan", d(-3), "medium")
t9 = task(tung, "Lập kế hoạch nhân sự quý IV", "HC", "lan", d(12), "low")
t10 = task(A, "Tra cứu ngày cấp GCN đầu tư, đối chiếu KL 21", "PC", "an", d(1), "medium", "kdc-thanh-lap", flow1, "tra-cuu")
t11 = task(B, "Lập bảng dòng tiền dự án Thạnh Mỹ Lợi", "TC", "binh", d(-2), "urgent", "thanh-my-loi-14-3ha")
t12 = task(tung, "Duyệt danh sách nhà thầu phụ phần điện nước", "DA", "quan", d(6), "medium", "kdc-thanh-lap", flow2)
rpc(Q, "update_task", p_task=t12, p={"status": "in_progress"})
rpc(H, "update_task", p_task=t6, p={"status": "in_progress"})
rpc(L, "update_task", p_task=t8, p={"status": "blocked"})
rpc(L, "add_comment", p_task=t8, p_body="Chủ nhà chưa gửi phụ lục giá mới, đã nhắc qua email.", p_kind="note")
done = task(M, "Duyệt fact kdc-thanh-lap (69 fact)", "PC", "minh", d(-4), "medium", "kdc-thanh-lap")
rpc(M, "submit_task", p_task=done, p_note="Đã đối chiếu 69 fact với PDF gốc.")
done2 = task(B, "Đối soát công nợ nhà cung cấp tháng 9", "TC", "binh", d(-6))
rpc(B, "submit_task", p_task=done2, p_note="Khớp số liệu, không có chênh lệch.")

# Agent làm việc
def agent(tok_sub): return {"role": "agent", "sub": tok_sub}
import base64, hmac, hashlib, time
def jwt(claims, secret="dev-secret-dev-secret-dev-secret-0123456789"):
    b = lambda x: base64.urlsafe_b64encode(json.dumps(x, separators=(",", ":")).encode()).rstrip(b"=")
    h, p = b({"alg": "HS256", "typ": "JWT"}), b({**claims, "exp": int(time.time()) + 3600})
    return (h + b"." + p + b"." + base64.urlsafe_b64encode(hmac.new(secret.encode(), h + b"." + p, hashlib.sha256).digest()).rstrip(b"=")).decode()
G = jwt({"role": "agent", "sub": "hermes:ops-admin"})
http(f"{API}/rpc/agent_claim", {"p_role": "phap-che"}, G, single=False)
rpc(G, "agent_ask", p_task=t4, p_question="Diện tích chuyển đổi trong quyết định giao đất khác với số trên bản đồ địa chính kèm theo. Anh chị xác nhận lấy theo văn bản nào?")
http(f"{API}/rpc/agent_claim", {"p_role": "tai-chinh"}, G, single=False)
rpc(G, "agent_ask", p_task=t3, p_question="Bảng kê bồi thường đợt 3 có hai bản, ngày 14/06 và 02/07, tổng tiền khác nhau. Dùng bản nào?")
http(f"{API}/rpc/agent_claim", {"p_role": "tra-cuu"}, G, single=False)
rpc(G, "submit_task", p_task=t10, p_note="Ngày cấp GCN đầu tư là 05/01/2012, theo KL 21 trang 3. Văn bản A.2 ghi 05/01/2013 do lỗi OCR.")

# Drive
rpc(A, "set_drive_folder", p_url="https://drive.google.com/drive/folders/1AnFolderAbcdEfgh")
rpc(M, "set_drive_folder", p_url="https://drive.google.com/drive/folders/1MinhFolderAbcdEf")
rpc(G, "agent_drive_result", p_user=uid["an"], p_ok=True, p_note="Tên thư mục và quyền chỉnh sửa đúng")
rpc(G, "agent_drive_files", p_user=uid["an"], p_files=[{"file_id": "f-an-1", "name": f"T-{t2} Cong van gia han ban ky.pdf", "web_url": "https://drive.google.com/file/d/f-an-1", "mime_type": "application/pdf"}])
rpc(tung, "set_drive_folder", p_url="https://drive.google.com/drive/folders/1TungFolderAbcdEf")
rpc(G, "agent_drive_result", p_user=uid["tung"], p_ok=True, p_note="Tên thư mục và quyền chỉnh sửa đúng")

# Công ty thứ hai (để thấy chuyển công ty)
code2 = db.execute("select app.bootstrap_company('valnex','Valnex', 'tung@gmail.com', %s)", (json.dumps([{"code": "TK", "name": "Thiết kế"}, {"code": "TC", "name": "Thi công"}]),)).fetchone()[0]
login("tung@gmail.com", "Vũ Tùng", code2)
print("Đã tạo dữ liệu thử nghiệm.", {"tasks": db.execute("select count(*) from app.tasks").fetchone()[0], "users": len(uid)})
