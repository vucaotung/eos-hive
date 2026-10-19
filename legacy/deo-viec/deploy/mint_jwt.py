#!/usr/bin/env python3
"""Cấp JWT cho deo_work (thay mint_jwt.py của PA1, thêm mã cho người dùng app).

Agent:  python3 mint_jwt.py agent agent_admin hermes:ops-admin 90
Người:  python3 mint_jwt.py human 1 180            # 1 = people.id
        → in ra mã và link đăng nhập một lần https://<host>/#t=<mã>
Cần: pip install pyjwt  (chạy trên VPS 169, đọc PGRST_JWT_SECRET từ .env)
"""
import sys, time, subprocess, jwt

ENV = "/opt/apps/deo-work/.env"
APP_URL = "https://vps169.TAILNET.ts.net"   # sửa theo tên máy Tailscale thật

def secret():
    for line in open(ENV):
        if line.startswith("PGRST_JWT_SECRET="):
            return line.split("=", 1)[1].strip()
    sys.exit("Không thấy PGRST_JWT_SECRET trong " + ENV)

def person(pid):
    q = f"SELECT display_name, active FROM work.people WHERE id = {int(pid)}"
    out = subprocess.run(["docker", "exec", "deo-work-deo-pg-1", "psql", "-U", "postgres", "-d", "deo_work",
                          "-tAF|", "-c", q], capture_output=True, text=True, check=True).stdout.strip()
    if not out:
        sys.exit(f"Không có people.id = {pid}")
    name, active = out.split("|")
    if active != "t":
        sys.exit(f"{name} đang bị khóa (active = false)")
    return name

def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("agent", "human"):
        sys.exit(__doc__)
    now = int(time.time())
    if sys.argv[1] == "agent":
        _, _, role, sub, days = sys.argv
        claims = {"role": role, "sub": sub}
    else:
        _, _, pid, days = sys.argv
        claims = {"role": "human_app", "sub": f"human:{int(pid)}", "pid": int(pid), "name": person(pid)}
    claims.update(iat=now, exp=now + int(days) * 86400)
    tok = jwt.encode(claims, secret(), algorithm="HS256")
    print(tok)
    if sys.argv[1] == "human":
        print(f"\nLink đăng nhập (mở trên điện thoại đã bật Tailscale, chỉ gửi trực tiếp cho người đó):\n{APP_URL}/#t={tok}")

if __name__ == "__main__":
    main()
