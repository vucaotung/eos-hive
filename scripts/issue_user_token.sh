#!/usr/bin/env bash
# Cấp mã MCP CỦA NGƯỜI (chủ sở hữu) cho một profile Hermes/script và ghi vào .env của profile, KHÔNG in mã.
# Dùng: scripts/issue_user_token.sh vps169 vps173 <profile> <TÊN_BIẾN> "<tên mã>" <phạm-vi,cách,dấu-phẩy> [số-ngày=90]
#   ví dụ: scripts/issue_user_token.sh vps169 vps173 ops-admin EOS_REPORT_TOKEN "Báo cáo hằng ngày (cron Hermes)" read 90
# Phạm vi chỉ trong {read,write,drive,hr_self,kb} (mã của người). Mã hết hạn tối đa 90 ngày: ghi lịch cấp lại.
# CẨN THẬN với `write`: mọi việc profile đó tạo mang danh tính chủ sở hữu. Chỉ cấp cho profile đã được chủ sở hữu duyệt (docs/13).
set -euo pipefail
A="${1:?máy CSDL}"; B="${2:?máy Hermes}"; PROFILE="${3:?profile}"; VAR="${4:?tên biến .env}"; NAME="${5:?tên mã}"; SCOPES="${6:?phạm vi}"; DAYS="${7:-90}"
[[ "$PROFILE" =~ ^[A-Za-z0-9_-]{1,40}$ ]] || { echo "tên profile không hợp lệ" >&2; exit 2; }
[[ "$VAR" =~ ^[A-Z][A-Z0-9_]{2,40}$ ]] || { echo "tên biến không hợp lệ" >&2; exit 2; }
[[ "$SCOPES" =~ ^(read|write|drive|hr_self|kb)(,(read|write|drive|hr_self|kb))*$ ]] || { echo "phạm vi không hợp lệ" >&2; exit 2; }
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "số ngày không hợp lệ" >&2; exit 2; }
[[ "$NAME" =~ ^[A-Za-z0-9\ ()_.:-]{2,60}$ ]] || { echo "tên mã không hợp lệ" >&2; exit 2; }
PSQL="${PSQL:-sudo docker exec -i eos-postgres psql -U postgres -X -q -At -d eos}"
SQL="BEGIN; SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT id FROM core.users WHERE is_system_admin AND kind='person' ORDER BY created_at LIMIT 1))::text, true) \\g /dev/null
SELECT agent.mcp_token_issue('$NAME', 'other', '{$SCOPES}', $DAYS); COMMIT;"
REMOTE=$(cat <<'EOS'
set -euo pipefail; umask 077
T=$(cat); [[ "$T" =~ ^eos_[0-9a-f]{48}$ ]] || { echo "Không nhận được mã hợp lệ" >&2; exit 1; }
F=~/.hermes/profiles/$PROFILE/.env; [ -f "$F" ] || { echo "Không có $F" >&2; exit 1; }
cp -p "$F" "$F.bak.$(date +%F-%H%M)"; chmod 600 "$F"
grep -v "^$VAR=" "$F" > "$F.new" || true
{ cat "$F.new"; printf '%s=%s\n' "$VAR" "$T"; } > "$F"; rm -f "$F.new"; chmod 600 "$F"
echo "Đã ghi $VAR vào $F (độ dài ${#T})"
EOS
)
ENC=$(printf '%s' "$REMOTE" | base64 -w0)
ssh -o BatchMode=yes "$A" "set -euo pipefail; $PSQL" <<<"$SQL" | ssh -o BatchMode=yes "$B" "PROFILE='$PROFILE' VAR='$VAR' bash -c \"\$(echo $ENC | base64 -d)\""
