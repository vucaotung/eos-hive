#!/usr/bin/env bash
# Kiểm thử cầu nối với Hermes giả lập. Cần: postgrest trong PATH (hoặc POSTGREST_BIN), python3 + requests, psql.
# Tự dựng lại CSDL thử từ đầu rồi nạp seed_bridge.sql.
. "$(dirname "$0")/_common.sh"; need_dsn
PGRST="${POSTGREST_BIN:-postgrest}"; command -v "$PGRST" >/dev/null || { echo "Không thấy postgrest. Tải từ github.com/PostgREST/postgrest/releases" >&2; exit 2; }
rebuild_db
T=$(mktemp -d); trap 'kill ${PID:-0} 2>/dev/null || true; rm -rf "$T"' EXIT
psql "$EOS_TEST_DSN" -X -q -v ON_ERROR_STOP=1 -f "$ROOT/bridge/test/seed_bridge.sql" >/dev/null
HOSTPORT="${EOS_TEST_DSN#*@}"; HOSTPORT="${HOSTPORT%%/*}"; DBN="${EOS_TEST_DSN##*/}"
SECRET="test-only-secret-at-least-32-characters-long"
psql "$EOS_TEST_DSN" -X -q -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN CREATE ROLE authenticator LOGIN PASSWORD 'test-only' NOINHERIT; END IF; IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='nobody_anon') THEN CREATE ROLE nobody_anon NOLOGIN; END IF; END \$\$; GRANT agent_bridge, nobody_anon TO authenticator;"
cat > "$T/pgrst.conf" <<CONF
db-uri = "postgres://authenticator:test-only@${HOSTPORT}/${DBN}"
db-schemas = "agent"
db-anon-role = "nobody_anon"
jwt-secret = "$SECRET"
server-port = 3901
CONF
"$PGRST" "$T/pgrst.conf" >"$T/pgrst.log" 2>&1 & PID=$!; sleep 3
TOKEN=$(SECRET="$SECRET" python3 - <<'PY'
import hmac,hashlib,base64,json,time,os
b=lambda d: base64.urlsafe_b64encode(d).rstrip(b'=')
h=b(b'{"alg":"HS256","typ":"JWT"}'); p=b(json.dumps({"role":"agent_bridge","sub":"bridge","exp":int(time.time())+3600}).encode())
print((h+b'.'+p+b'.'+b(hmac.new(os.environ["SECRET"].encode(),h+b'.'+p,hashlib.sha256).digest())).decode())
PY
)
echo '{"tasks":{},"calls":[],"seq":0}' > "$T/fake.json"
cd "$ROOT/bridge/test"
EOS_API=http://127.0.0.1:3901 EOS_BRIDGE_TOKEN="$TOKEN" BRIDGE_STATE_DIR="$T/state" FAKE_HERMES_DB="$T/fake.json" \
  HERMES_BIN="python3 $ROOT/bridge/test/fake_hermes.py" python3 test_bridge.py | tail -3
