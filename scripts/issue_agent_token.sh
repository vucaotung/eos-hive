#!/usr/bin/env bash
# Cấp mã MCP cho một agent hệ thống (để worker đọc việc) và ghi vào .env của profile Hermes tương ứng, KHÔNG in ra.
# Dùng: scripts/issue_agent_token.sh vps169 vps173 <mã-agent> <profile-hermes> [số-ngày=90]
set -euo pipefail
A="${1:?máy CSDL}"; B="${2:?máy Hermes}"; CODE="${3:?mã agent, ví dụ quan-tri-du-lieu}"; PROFILE="${4:?profile Hermes}"; DAYS="${5:-90}"
[[ "$CODE" =~ ^[a-z][a-z-]{1,30}$ ]] || { echo "mã agent không hợp lệ" >&2; exit 2; }
[[ "$PROFILE" =~ ^[A-Za-z0-9_-]{1,40}$ ]] || { echo "tên profile không hợp lệ" >&2; exit 2; }
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "số ngày không hợp lệ" >&2; exit 2; }
PSQL="${PSQL:-sudo docker exec -i eos-postgres psql -U postgres -X -q -At -d eos}"   # -q để chỉ in mã
# Hàm chỉ cho quản trị hệ thống cấp: đặt danh tính quản trị đầu tiên trong cùng giao dịch
SQL="BEGIN; SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT id FROM core.users WHERE is_system_admin AND kind='person' ORDER BY created_at LIMIT 1))::text, true) \\g /dev/null
SELECT agent.mcp_token_issue_agent('$CODE', $DAYS); COMMIT;"
REMOTE=$(cat <<'EOS'
set -euo pipefail; umask 077
T=$(cat); [[ "$T" =~ ^eos_[0-9a-f]{48}$ ]] || { echo "Không nhận được mã hợp lệ" >&2; exit 1; }
F=~/.hermes/profiles/$PROFILE/.env; mkdir -p "$(dirname "$F")"; touch "$F"; chmod 600 "$F"
grep -v '^EOS_MCP_TOKEN=' "$F" > "$F.new" || true
{ cat "$F.new"; printf 'EOS_MCP_TOKEN=%s\n' "$T"; } > "$F"; rm -f "$F.new"
echo "Đã ghi EOS_MCP_TOKEN vào $F (độ dài ${#T})"
EOS
)
ENC=$(printf '%s' "$REMOTE" | base64 -w0)     # chuyển script bằng đối số để stdin của ssh dành cho mã
ssh -o BatchMode=yes "$A" "set -euo pipefail; $PSQL" <<<"$SQL" \
 | ssh -o BatchMode=yes "$B" "PROFILE='$PROFILE' bash -c \"\$(echo $ENC | base64 -d)\""
