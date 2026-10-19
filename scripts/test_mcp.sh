#!/usr/bin/env bash
# Kiểm thử đầu–cuối máy chủ MCP (Postgres thật + Drive giả lập). Tự dựng lại CSDL thử từ đầu.
. "$(dirname "$0")/_common.sh"; need_dsn
rebuild_db
cd "$ROOT/mcp"; [ -d node_modules ] || npm ci --silent
# seed.sql tạo vai trò eos_mcp (mật khẩu thử), dữ liệu mẫu và in các dòng TOKEN_*; chỉ chạy MỘT lần (mỗi người tối đa 5 mã)
SEED_OUT=$(psql "$EOS_TEST_DSN" -X -q -At -f test/seed.sql)
set -a; eval "$(echo "$SEED_OUT" | grep '^TOKEN_')"; set +a
HOSTPORT="${EOS_TEST_DSN#*@}"; HOSTPORT="${HOSTPORT%%/*}"; DBN="${EOS_TEST_DSN##*/}"
DATABASE_URL="postgres://eos_mcp:test-only@${HOSTPORT}/${DBN}" node test/e2e.mjs | tail -3
