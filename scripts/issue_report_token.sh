#!/usr/bin/env bash
# Cấp mã MCP CHỈ-ĐỌC cho script báo cáo (ops/eos_report.py) theo danh tính chủ sở hữu và ghi vào .env của một profile Hermes; KHÔNG in mã.
# Dùng: scripts/issue_report_token.sh vps169 vps173 <profile-hermes> [số-ngày=90]     (mã hết hạn tối đa 90 ngày: nhớ cấp lại)
set -euo pipefail
A="${1:?máy CSDL}"; B="${2:?máy Hermes}"; PROFILE="${3:?profile Hermes}"; DAYS="${4:-90}"
[[ "$PROFILE" =~ ^[A-Za-z0-9_-]{1,40}$ ]] || { echo "tên profile không hợp lệ" >&2; exit 2; }
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "số ngày không hợp lệ" >&2; exit 2; }
PSQL="${PSQL:-sudo docker exec -i eos-postgres psql -U postgres -X -q -At -d eos}"
SQL="BEGIN; SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT id FROM core.users WHERE is_system_admin AND kind='person' ORDER BY created_at LIMIT 1))::text, true) \\g /dev/null
SELECT agent.mcp_token_issue('Báo cáo hằng ngày (cron Hermes)', 'other', '{read}', $DAYS); COMMIT;"
REMOTE=$(cat <<'EOS'
set -euo pipefail; umask 077
T=$(cat); [[ "$T" =~ ^eos_[0-9a-f]{48}$ ]] || { echo "Không nhận được mã hợp lệ" >&2; exit 1; }
F=~/.hermes/profiles/$PROFILE/.env; [ -f "$F" ] || { echo "Không có $F" >&2; exit 1; }
cp -p "$F" "$F.bak.$(date +%F-%H%M)"; chmod 600 "$F"
grep -v '^EOS_REPORT_TOKEN=' "$F" > "$F.new" || true
{ cat "$F.new"; printf 'EOS_REPORT_TOKEN=%s\n' "$T"; } > "$F"; rm -f "$F.new"; chmod 600 "$F"
echo "Đã ghi EOS_REPORT_TOKEN vào $F (độ dài ${#T})"
EOS
)
ENC=$(printf '%s' "$REMOTE" | base64 -w0)
ssh -o BatchMode=yes "$A" "set -euo pipefail; $PSQL" <<<"$SQL" | ssh -o BatchMode=yes "$B" "PROFILE='$PROFILE' bash -c \"\$(echo $ENC | base64 -d)\""
