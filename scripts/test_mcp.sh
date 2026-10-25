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
# scripts/issue_agent_token.sh --revoke-old (ssh giả chạy tại chỗ; CSDL thử; HOME tạm). Mã không bao giờ được in ra.
TMPH=$(mktemp -d); mkdir -p "$TMPH/bin"
printf '#!/usr/bin/env bash\nwhile [ "${1:-}" = "-o" ]; do shift 2; done\nshift\nexec bash -c "$1"\n' > "$TMPH/bin/ssh"; chmod +x "$TMPH/bin/ssh"
IQ="psql $EOS_TEST_DSN -X -q -At"; act() { $IQ -c "select count(*) from agent.mcp_tokens k join agent.agents g on g.id=k.agent_id where g.code='$1' and k.revoked_at is null and k.expires_at>now()"; }
RUN() { PSQL="$IQ" HOME="$TMPH" PATH="$TMPH/bin:$PATH" "$ROOT/scripts/issue_agent_token.sh" "$@" 2>&1; }
B_DP=$(act dieu-phoi); B_VT=$(act van-thu)
O1=$(RUN h1 h2 dieu-phoi team_test 30); [ "$(act dieu-phoi)" = "$((B_DP+1))" ] || { echo "issue_agent_token (không cờ) lỗi: giữ nguyên mã cũ + 1" >&2; exit 1; }
echo "$O1" | grep -q "Đã thu hồi" && { echo "không cờ mà vẫn thu hồi" >&2; exit 1; }
TOK=$(sed -n 's/^EOS_MCP_TOKEN=//p' "$TMPH/.hermes/profiles/team_test/.env"); [[ "$TOK" =~ ^eos_[0-9a-f]{48}$ ]] || { echo "không ghi được mã vào .env" >&2; exit 1; }
O2=$(RUN --revoke-old h1 h2 dieu-phoi team_test 30)
[ "$(act dieu-phoi)" = "1" ] && [ "$(act van-thu)" = "$B_VT" ] || { echo "--revoke-old: dieu-phoi còn $(act dieu-phoi) mã (cần 1), van-thu $(act van-thu)/$B_VT" >&2; exit 1; }
NEWTOK=$(sed -n 's/^EOS_MCP_TOKEN=//p' "$TMPH/.hermes/profiles/team_test/.env"); [ "$NEWTOK" != "$TOK" ] || { echo "mã trong .env không đổi" >&2; exit 1; }
[ "$($IQ -c "select count(*) from agent.mcp_tokens where prefix='${NEWTOK:4:8}' and revoked_at is null")" = "1" ] || { echo "mã mới (đang ở .env) bị thu hồi nhầm" >&2; exit 1; }
echo "$O2" | grep -q "Đã thu hồi $((B_DP+1)) mã cũ của agent dieu-phoi" || { echo "thông báo thu hồi sai: $O2" >&2; exit 1; }
echo "$O1$O2" | grep -q -E "eos_[0-9a-f]{48}" && { echo "LỘ MÃ trong đầu ra" >&2; exit 1; }
# ghi .env lỗi (HOME không ghi được) thì KHÔNG thu hồi mã cũ
BEFORE=$(act dieu-phoi); PSQL="$IQ" HOME=/proc/khong-ghi-duoc PATH="$TMPH/bin:$PATH" "$ROOT/scripts/issue_agent_token.sh" --revoke-old h1 h2 dieu-phoi team_test 30 >/dev/null 2>&1 && { echo "ghi .env lỗi mà script vẫn thành công" >&2; exit 1; }
[ "$(act dieu-phoi)" -ge "$BEFORE" ] || { echo "ghi .env lỗi mà vẫn thu hồi mã cũ" >&2; exit 1; }
rm -rf "$TMPH"; echo "issue_agent_token --revoke-old: ĐẠT"
