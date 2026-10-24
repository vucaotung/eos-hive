#!/usr/bin/env bash
# Dọn định kỳ lớp MCP (docs/16 §4, §6): đánh dấu lượt tải Drive treo, liệt kê tệp mồ côi (KHÔNG xóa), dọn bảng tạm. Chạy trên máy CSDL (vps169) bằng root/cron.
# Dùng: scripts/housekeeping.sh        (ghi kết quả JSON ra stdout; cron chuyển vào /var/log/eos-housekeeping.log)
set -euo pipefail
PSQL="${PSQL:-docker exec -i eos-postgres psql -U postgres -X -q -At -d eos}"
$PSQL <<'SQL'
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', (SELECT id FROM core.users WHERE is_system_admin AND kind = 'person' ORDER BY created_at LIMIT 1))::text, true) \g /dev/null
SELECT now()::text || ' upload_sweep ' || agent.upload_sweep(1)::text;
SELECT now()::text || ' prune ' || agent.housekeeping_prune(1)::text;
COMMIT;
SQL
