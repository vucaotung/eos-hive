#!/bin/sh
# Cài Dẹo Work: sinh bí mật, build web, khởi động, nạp schema, khởi tạo công ty đầu tiên.
set -eu
cd "$(dirname "$0")"
[ -f .env ] || cp .env.example .env
chmod 600 .env
gen() { openssl rand -base64 48 | tr -d '/+=\n' | cut -c1-48; }
for k in AUTHENTICATOR_PW AUTH_SVC_PW JWT_SECRET; do
  v=$(grep "^$k=" .env | cut -d= -f2-)
  [ -n "$v" ] || sed -i "s|^$k=.*|$k=$(gen)|" .env
done
mkdir -p secrets && [ -s secrets/pg_pw ] || gen > secrets/pg_pw; chmod 600 secrets/pg_pw
. ./.env
[ -n "$GOOGLE_CLIENT_ID" ] || { echo "Điền GOOGLE_CLIENT_ID trong deploy/.env trước (README mục 2)"; exit 1; }

echo "== Build web"
(cd ../web && npm ci && npm run build)

echo "== Khởi động CSDL"
docker compose up -d db
until docker compose exec -T db pg_isready -U postgres -d deo_work >/dev/null 2>&1; do sleep 1; done

if [ "$(docker compose exec -T db psql -U postgres -d deo_work -tAc "select count(*) from pg_namespace where nspname='app'")" = "0" ]; then
  echo "== Nạp schema"
  for f in 01_schema.sql 02_functions.sql; do docker compose exec -T db psql -U postgres -d deo_work -v ON_ERROR_STOP=1 -q < ../db/$f; done
  docker compose exec -T db psql -U postgres -d deo_work -v ON_ERROR_STOP=1 -q \
    -v authenticator_pw="$AUTHENTICATOR_PW" -v auth_svc_pw="$AUTH_SVC_PW" < ../db/03_security.sql
fi

echo "== Khởi động API, đăng nhập, web"
docker compose up -d --build api auth web
sleep 3
curl -fsS http://127.0.0.1:8095/auth/health && echo

if [ "$(docker compose exec -T db psql -U postgres -d deo_work -tAc "select count(*) from app.companies")" = "0" ]; then
  printf "Mã công ty (chữ thường, vd 5balance): "; read -r slug
  printf "Tên công ty: "; read -r cname
  printf "Gmail của chủ sở hữu: "; read -r owner
  code=$(printf "select app.bootstrap_company(:'slug', :'cname', :'owner');\n" | docker compose exec -T db psql -U postgres -d deo_work -tA -v slug="$slug" -v cname="$cname" -v owner="$owner")
  echo "Mã mời chủ sở hữu (dùng 1 lần, 14 ngày): $code"
  echo "Mở https://work.enterpriseos.bond/#/join?code=$code và đăng nhập bằng $owner"
fi
