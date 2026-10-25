#!/usr/bin/env bash
# Kiểm thử đầu–cuối máy chủ MCP (Postgres thật + Drive giả lập). Tự dựng lại CSDL thử từ đầu.
. "$(dirname "$0")/_common.sh"; need_dsn
rebuild_db
cd "$ROOT/mcp"; [ -d node_modules ] || npm ci --silent
# seed.sql tạo vai trò eos_mcp (mật khẩu thử), dữ liệu mẫu và in các dòng TOKEN_*; chỉ chạy MỘT lần (mỗi người tối đa 5 mã)
SEED_OUT=$(psql "$EOS_TEST_DSN" -X -q -At -f test/seed.sql)
set -a; eval "$(echo "$SEED_OUT" | grep -E '^(TOKEN_|ROOT_TASK)')"; set +a
HOSTPORT="${EOS_TEST_DSN#*@}"; HOSTPORT="${HOSTPORT%%/*}"; DBN="${EOS_TEST_DSN##*/}"
ADMIN_DSN="$EOS_TEST_DSN" DATABASE_URL="postgres://eos_mcp:test-only@${HOSTPORT}/${DBN}" node test/e2e.mjs | tail -3
# Thể thức văn bản NĐ30 do eos_draft_document sinh ra (không cần Postgres)
node --test test/vanban.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)" | tr '\n' ' '; echo
node --test test/vanban.test.mjs >/dev/null 2>&1 || { echo "vanban: THẤT BẠI" >&2; exit 1; }
# Dữ liệu hồ sơ agent (deploy/setup_agent_profiles.sql): chạy hai lần trên CSDL thử, không tạo trùng, Mai không nhận thẻ Kanban, không đụng max_level
P="psql $EOS_TEST_DSN -X -q -At -v ON_ERROR_STOP=1 -v company=33333333-3333-3333-3333-333333333333 -v owner_email=minh@demo.vn"
$P -f "$ROOT/deploy/setup_agent_profiles.sql" >/dev/null && $P -f "$ROOT/deploy/setup_agent_profiles.sql" >/dev/null
CHK=$(psql "$EOS_TEST_DSN" -X -q -At -c "select (select count(*) from agent.agents where code='mai')||'|'||(select count(*) from agent.company_agents ca join agent.agents g on g.id=ca.agent_id where g.code='mai' and not ca.enabled and ca.title='Trợ lý tiếp nhận' and ca.owner_user_id is not null)||'|'||(select max_level from agent.agents where code='mai')")
[ "$CHK" = "1|1|1" ] && echo "setup_agent_profiles: ĐẠT (chạy lại không trùng)" || { echo "setup_agent_profiles THẤT BẠI: $CHK" >&2; exit 1; }
