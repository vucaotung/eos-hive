#!/usr/bin/env bash
# Kiểm thử đầu–cuối giao diện web (Postgres thật + Google giả lập). Tự dựng lại CSDL thử từ đầu.
. "$(dirname "$0")/_common.sh"; need_dsn
rebuild_db
cd "$ROOT/web"; [ -d node_modules ] || npm ci --silent
psql "$EOS_TEST_DSN" -X -q -At -v ON_ERROR_STOP=1 -f test/seed.sql >/dev/null
HOSTPORT="${EOS_TEST_DSN#*@}"; HOSTPORT="${HOSTPORT%%/*}"; DBN="${EOS_TEST_DSN##*/}"
node "$ROOT/web/test/quickadd.mjs" >/dev/null || { echo "quickadd: LỖI" >&2; exit 1; }
DATABASE_URL="postgres://eos_web:test-only@${HOSTPORT}/${DBN}" ADMIN_DSN="$EOS_TEST_DSN" node test/e2e.mjs | tail -${WEB_TEST_TAIL:-4}
