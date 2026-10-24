#!/usr/bin/env bash
# Cấp mã MCP cho agent runner `ho-so-runner` và ghi vào ~/.config/eos-hive/runner.env trên MÁY NÀY (Z2), quyền 600; KHÔNG in mã.
# Dùng: scripts/issue_runner_token.sh vps169 [số-ngày=90]
set -euo pipefail; umask 077
A="${1:?máy CSDL}"; DAYS="${2:-90}"; [[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "số ngày không hợp lệ" >&2; exit 2; }
PSQL="${PSQL:-sudo docker exec -i eos-postgres psql -U postgres -X -q -At -d eos}"
SQL="BEGIN; SELECT set_config('request.jwt.claims', json_build_object('sub',(SELECT id FROM core.users WHERE is_system_admin AND kind='person' ORDER BY created_at LIMIT 1))::text, true) \\g /dev/null
SELECT agent.mcp_token_issue_agent('ho-so-runner', $DAYS); COMMIT;"
T=$(ssh -o BatchMode=yes "$A" "set -euo pipefail; $PSQL" <<<"$SQL")
[[ "$T" =~ ^eos_[0-9a-f]{48}$ ]] || { echo "Không nhận được mã hợp lệ" >&2; exit 1; }
F="${EOS_RUNNER_ENV:-$HOME/.config/eos-hive/runner.env}"; mkdir -p "$(dirname "$F")"; touch "$F"; chmod 600 "$F"
{ grep -v '^EOS_RUNNER_TOKEN=' "$F" || true; printf 'EOS_RUNNER_TOKEN=%s\n' "$T"; } > "$F.new"; mv "$F.new" "$F"; chmod 600 "$F"
grep -q '^EOS_MCP_URL=' "$F" || printf 'EOS_MCP_URL=https://work.enterpriseos.bond/mcp\n' >> "$F"
echo "Đã ghi EOS_RUNNER_TOKEN vào $F (độ dài ${#T}, hạn $DAYS ngày)"
