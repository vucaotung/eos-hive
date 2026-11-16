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
# Máy khách WeKnora (KB mẫu, WeKnora cũ, metadata) với máy chủ giả
node --test test/weknora.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)" | tr '\n' ' '; echo
node --test test/weknora.test.mjs >/dev/null 2>&1 || { echo "weknora: THẤT BẠI" >&2; exit 1; }
# Văn bản pháp luật: nguồn chính thống, front matter, tên tệp (thuần hàm)
node --test test/law.test.mjs 2>&1 | grep -E "^# (tests|pass|fail)" | tr '\n' ' '; echo
node --test test/law.test.mjs >/dev/null 2>&1 || { echo "law: THẤT BẠI" >&2; exit 1; }
# Dữ liệu hồ sơ agent (deploy/setup_agent_profiles.sql): chạy hai lần trên CSDL thử, không tạo trùng, Mai không nhận thẻ Kanban, không đụng max_level
P="psql $EOS_TEST_DSN -X -q -At -v ON_ERROR_STOP=1 -v company=33333333-3333-3333-3333-333333333333 -v owner_email=minh@demo.vn"
$P -f "$ROOT/deploy/setup_agent_profiles.sql" >/dev/null && $P -f "$ROOT/deploy/setup_agent_profiles.sql" >/dev/null
# deploy/setup_agents.sql: thêm ks-kinh-te-xd (tắt khi mới tạo), chạy lại không bật/tắt lại; mô tả phap-che/ks theo bảng phân vai
PS="psql $EOS_TEST_DSN -X -q -At -v ON_ERROR_STOP=1 -v company=33333333-3333-3333-3333-333333333333"
$PS -f "$ROOT/deploy/setup_agents.sql" >/dev/null 2>&1; $PS -f "$ROOT/deploy/setup_agent_profiles.sql" -v owner_email=minh@demo.vn >/dev/null
K1=$(psql "$EOS_TEST_DSN" -X -q -At -c "select kind||'|'||module||'|'||hermes_profile||'|'||max_level||'|'||can_delegate||'|'||active from agent.agents where code='ks-kinh-te-xd'")
[ "$K1" = "specialist|doc|ks-kinh-te-xd|1|false|false" ] || { echo "setup_agents ks-kinh-te-xd sai: $K1" >&2; exit 1; }
psql "$EOS_TEST_DSN" -X -q -c "update agent.agents set active = true where code in ('ks-kinh-te-xd')"
$PS -f "$ROOT/deploy/setup_agents.sql" >/dev/null 2>&1; $PS -f "$ROOT/deploy/setup_agent_profiles.sql" -v owner_email=minh@demo.vn >/dev/null
[ "$(psql "$EOS_TEST_DSN" -X -q -At -c "select active from agent.agents where code='ks-kinh-te-xd'")" = "t" ] || { echo "chạy lại setup_agents tắt mất agent đã bật" >&2; exit 1; }
[ "$(psql "$EOS_TEST_DSN" -X -q -At -c "select count(*) from agent.agents a where code in ('ks-kinh-te-xd','phap-che') and (description like '%20 bước%' or description like '%KB pháp luật%')")" = "2" ] || { echo "mô tả phap-che/ks-kinh-te-xd chưa theo bảng phân vai" >&2; exit 1; }
echo "setup_agents (ks-kinh-te-xd, phap-che): ĐẠT"
CHK=$(psql "$EOS_TEST_DSN" -X -q -At -c "select (select count(*) from agent.agents where code='mai')||'|'||(select count(*) from agent.company_agents ca join agent.agents g on g.id=ca.agent_id where g.code='mai' and ca.enabled and ca.auto_done and ca.config->>'internal'='true' and ca.title='Trợ lý tiếp nhận' and ca.owner_user_id is not null)||'|'||(select max_level from agent.agents where code='mai')")
[ "$CHK" = "1|1|1" ] && echo "setup_agent_profiles: ĐẠT (chạy lại không trùng)" || { echo "setup_agent_profiles THẤT BẠI: $CHK" >&2; exit 1; }
# deploy/setup_wiki_maintenance.sql: hai việc định kỳ mẫu, KHÔNG bật sẵn, chạy lại không trùng
SLUG=$(psql "$EOS_TEST_DSN" -X -q -At -c "select slug from core.projects where company_id='33333333-3333-3333-3333-333333333333' limit 1")
PW="psql $EOS_TEST_DSN -X -q -At -v ON_ERROR_STOP=1 -v company=33333333-3333-3333-3333-333333333333 -v project=$SLUG -v owner_email=admin@demo.vn"
$PW -f "$ROOT/deploy/setup_wiki_maintenance.sql" >/dev/null && $PW -f "$ROOT/deploy/setup_wiki_maintenance.sql" >/dev/null
WM=$(psql "$EOS_TEST_DSN" -X -q -At -c "select count(*)||'|'||count(*) filter (where active)||'|'||count(*) filter (where scope->>'stage'='wiki_lint')||'|'||count(*) filter (where scope->>'stage'='law_review') from work.recurrences where company_id='33333333-3333-3333-3333-333333333333' and agent_code is not null")
[ "$WM" = "3|0|1|2" ] || { echo "setup_wiki_maintenance sai (cần 3 mẫu: 1 wiki_lint + 2 law_review, không bật sẵn): $WM" >&2; exit 1; }
echo "setup_wiki_maintenance (2 việc định kỳ mẫu, chưa bật): ĐẠT"
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
echo "issue_agent_token --revoke-old: ĐẠT"
# phap-che nhận phạm vi law_ingest, van-thu/dieu-phoi thì không (script không in mã)
O3=$(RUN h1 h2 phap-che team_test 30); echo "$O3" | grep -q "law_ingest" || { echo "issue_agent_token phap-che: thiếu dòng phạm vi law_ingest" >&2; exit 1; }
[ "$($IQ -c "select 'law_ingest' = any(scopes) from agent.mcp_tokens k join agent.agents g on g.id=k.agent_id where g.code='phap-che' and k.revoked_at is null order by k.created_at desc limit 1")" = "t" ] || { echo "mã phap-che không có law_ingest" >&2; exit 1; }
O4=$(RUN h1 h2 van-thu team_test 30); echo "$O4" | grep -q "law_ingest" && { echo "van-thu không được có law_ingest" >&2; exit 1; }
echo "issue_agent_token phap-che (law_ingest): ĐẠT"
rm -rf "$TMPH"
