"""Thử drive_sync với Drive giả lập + PostgREST thật (cục bộ)."""
import base64, hashlib, hmac, json, os, time, importlib
def jwt(claims, secret):
    b = lambda x: base64.urlsafe_b64encode(json.dumps(x, separators=(",", ":")).encode()).rstrip(b"=")
    h, p = b({"alg": "HS256", "typ": "JWT"}), b({**claims, "exp": int(time.time()) + 600})
    return (h + b"." + p + b"." + base64.urlsafe_b64encode(hmac.new(secret.encode(), h + b"." + p, hashlib.sha256).digest()).rstrip(b"=")).decode()
os.environ.update(DEO_API="http://localhost:3300", DEO_AGENT_TOKEN=jwt({"role": "agent", "sub": "hermes:drive"}, "dev-secret-dev-secret-dev-secret-0123456789"),
                  GOOGLE_CLIENT_ID="x", GOOGLE_CLIENT_SECRET="x", GOOGLE_REFRESH_TOKEN="x")
ds = importlib.import_module("drive_sync")
FOLDERS = {"1MinhFolderAbcdEf": {"id": "1MinhFolderAbcdEf", "name": "Thu muc cua Minh", "mimeType": ds.FOLDER, "capabilities": {"canEdit": True}}}
def fake_drive(path, **params):
    if path.startswith("files/"):
        fid = path.split("/")[1]
        return (200, FOLDERS[fid]) if fid in FOLDERS else (404, {})
    return 200, {"files": []}
ds.drive, ds.gtoken = fake_drive, (lambda: "t")
q = ds.deo("agent_drive_queue")
print("hàng đợi:", [(i["email"], i["expected_names"]) for i in q])
ds.run()
FOLDERS["1MinhFolderAbcdEf"]["name"] = "DEO - 5balance - PC - Trần Minh"
ds.deo("agent_drive_result", p_user=[i for i in q if i["email"] == "minh@gmail.com"][0]["user_id"], p_ok=False, p_note="đặt lại")
import psycopg; psycopg.connect("host=/tmp/pgtest port=5544 user=postgres dbname=deo_work", autocommit=True).execute("update app.users set drive_status='pending' where email='minh@gmail.com'")
ds.run()
