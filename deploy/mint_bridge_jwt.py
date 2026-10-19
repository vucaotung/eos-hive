#!/usr/bin/env python3
"""Cấp JWT vai trò agent_bridge cho cầu nối Kanban (chạy trên VPS 169, nơi có JWT_SECRET của PostgREST).
  JWT_SECRET=... python3 mint_bridge_jwt.py 90      → in JWT hạn 90 ngày ra stdout
Bí mật đi qua biến môi trường, không đưa vào đối số dòng lệnh (tránh lộ trong lịch sử shell).
Lưu kết quả vào ~/.hermes/eos_bridge/.env (EOS_BRIDGE_TOKEN), chmod 600. Không dán vào chat, không đưa vào git."""
import base64, hashlib, hmac, json, os, sys, time
secret = os.environ.get("JWT_SECRET") or sys.exit("Thiếu biến môi trường JWT_SECRET")
days = int(sys.argv[1]) if len(sys.argv) > 1 else 90
if not 1 <= days <= 365: sys.exit("Số ngày phải từ 1 đến 365")
b = lambda x: base64.urlsafe_b64encode(json.dumps(x, separators=(",", ":")).encode()).rstrip(b"=")
h = b({"alg": "HS256", "typ": "JWT"})
p = b({"role": "agent_bridge", "sub": "bridge", "iat": int(time.time()), "exp": int(time.time()) + days * 86400})
print((h + b"." + p + b"." + base64.urlsafe_b64encode(hmac.new(secret.encode(), h + b"." + p, hashlib.sha256).digest()).rstrip(b"=")).decode())
