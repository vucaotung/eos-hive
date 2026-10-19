#!/usr/bin/env bash
# Cấp JWT vai trò agent_bridge trên máy CSDL và ghi thẳng vào .env của cầu nối trên máy Hermes, KHÔNG in ra màn hình.
# Dùng: scripts/issue_bridge_token.sh vps169 vps173 [số-ngày=90]
# Bí mật đi qua đường ống ssh → ssh; shell của bạn (và Claude Code) không nhìn thấy nó.
set -euo pipefail
A="${1:?alias máy CSDL (vps169)}"; B="${2:?alias máy Hermes (vps173)}"; DAYS="${3:-90}"
[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "số ngày không hợp lệ" >&2; exit 2; }
API="${EOS_API:-https://work.enterpriseos.bond/api}"; APP="${EOS_APP_URL:-https://work.enterpriseos.bond}"
PGRST_CONF="${PGRST_CONF:-/etc/eos/postgrest.conf}"; MINT="${MINT:-/opt/apps/enterprise-os/deploy/mint_bridge_jwt.py}"
ssh -o BatchMode=yes "$A" "set -euo pipefail; S=\$(sudo awk -F'\"' '/^jwt-secret/{print \$2}' '$PGRST_CONF'); [ -n \"\$S\" ]; JWT_SECRET=\"\$S\" python3 '$MINT' $DAYS" \
 | ssh -o BatchMode=yes "$B" 'umask 077; mkdir -p ~/.hermes/eos_bridge; cat > ~/.hermes/eos_bridge/token.tmp'
ssh -o BatchMode=yes "$B" "API='$API' APP='$APP' bash -s" <<'REMOTE'
set -euo pipefail; umask 077; D=~/.hermes/eos_bridge
[ -s "$D/token.tmp" ] || { echo "Không nhận được JWT" >&2; exit 1; }
HB=$(command -v hermes || true)
{ echo "EOS_API=$API"; echo "EOS_APP_URL=$APP"; echo "HERMES_BIN=${HB:-hermes}"; echo "BRIDGE_INTERVAL=15"; echo "RECONCILE_EVERY=600"
  printf 'EOS_BRIDGE_TOKEN='; tr -d '\n' < "$D/token.tmp"; echo; } > "$D/.env"
rm -f "$D/token.tmp"; chmod 600 "$D/.env"
echo "Đã ghi $D/.env (khóa và độ dài giá trị):"; awk -F= '{print "  " $1, length(substr($0, index($0,"=")+1))}' "$D/.env"
REMOTE
