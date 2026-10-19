#!/usr/bin/env python3
"""Cấp JWT cho agent (Hermes) gọi Dẹo Work. Chạy trên VPS 169 trong thư mục deploy/.
  python3 mint_jwt.py hermes:ops-admin 90      → role agent, sub hermes:ops-admin, hạn 90 ngày
Không dùng thư viện ngoài. Lưu kết quả vào .env của profile Hermes (DEO_AGENT_TOKEN), không dán vào chat."""
import base64, hashlib, hmac, json, sys, time
secret = next(l.split("=", 1)[1].strip() for l in open(".env") if l.startswith("JWT_SECRET="))
sub, days = (sys.argv[1] if len(sys.argv) > 1 else "hermes:ops-admin"), int(sys.argv[2] if len(sys.argv) > 2 else 90)
b = lambda x: base64.urlsafe_b64encode(json.dumps(x, separators=(",", ":")).encode()).rstrip(b"=")
h, p = b({"alg": "HS256", "typ": "JWT"}), b({"role": "agent", "sub": sub, "iat": int(time.time()), "exp": int(time.time()) + days * 86400})
print((h + b"." + p + b"." + base64.urlsafe_b64encode(hmac.new(secret.encode(), h + b"." + p, hashlib.sha256).digest()).rstrip(b"=")).decode())
