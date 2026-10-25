#!/usr/bin/env bash
# Cấp mã MCP cho một agent hệ thống (để worker đọc việc) và ghi vào .env của profile Hermes tương ứng, KHÔNG in ra.
# Dùng: scripts/issue_agent_token.sh [--revoke-old] vps169 vps173 <mã-agent> <profile-hermes> [số-ngày=90]
#   --revoke-old: SAU KHI mã mới đã ghi thành công vào .env của profile, thu hồi mọi mã còn hiệu lực KHÁC của cùng agent (mã agent gắn với đúng một profile Hermes,
#   bảng mã không lưu profile). Thu hồi sau cùng, nên ghi .env lỗi thì mã cũ vẫn dùng được. Chỉ dùng khi agent có MỘT nơi dùng mã (đúng profile này): nơi khác đang dùng mã cũ sẽ mất quyền.
#   In số mã đã thu hồi và tiền tố của chúng (không in mã đầy đủ, không in hash). Thiếu cờ thì giữ nguyên hành vi cũ (không thu hồi gì).
set -euo pipefail
REVOKE_OLD=0; if [ "${1:-}" = "--revoke-old" ]; then REVOKE_OLD=1; shift; fi
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
echo "PREFIX=${T:4:8}"
EOS
)
ENC=$(printf '%s' "$REMOTE" | base64 -w0)     # chuyển script bằng đối số để stdin của ssh dành cho mã
OUT=$(ssh -o BatchMode=yes "$A" "set -euo pipefail; $PSQL" <<<"$SQL" \
 | ssh -o BatchMode=yes "$B" "PROFILE='$PROFILE' bash -c \"\$(echo $ENC | base64 -d)\"")
echo "$OUT" | grep -v '^PREFIX='
if [ "$REVOKE_OLD" = 1 ]; then
  NEW=$(echo "$OUT" | sed -n 's/^PREFIX=\([0-9a-f]\{8\}\)$/\1/p' | head -1)
  [[ "$NEW" =~ ^[0-9a-f]{8}$ ]] || { echo "Không biết tiền tố mã mới, KHÔNG thu hồi mã cũ." >&2; exit 1; }
  # chỉ thu hồi mã khác của đúng agent này; không đụng mã vừa cấp
  REV=$(ssh -o BatchMode=yes "$A" "set -euo pipefail; $PSQL" <<<"UPDATE agent.mcp_tokens SET revoked_at = now() WHERE revoked_at IS NULL AND prefix <> '$NEW' AND agent_id = (SELECT id FROM agent.agents WHERE code = '$CODE') RETURNING prefix;")
  echo "Đã thu hồi $(printf '%s' "$REV" | grep -c .) mã cũ của agent $CODE${REV:+: $(echo $REV | tr ' ' ',')} (mã mới có tiền tố $NEW)"
fi
