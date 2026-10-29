#!/usr/bin/env bash
# Job ngày: dọn lớp MCP (docs/16 §4, §6): đánh dấu lượt tải Drive treo, liệt kê tệp mồ côi (KHÔNG xóa), dọn bảng tạm; sinh việc định kỳ đến hạn. Chạy trên máy CSDL (vps169) bằng root/cron.
# Dùng: scripts/housekeeping.sh              (job ngày; ghi kết quả ra stdout; cron chuyển vào /var/log/eos-housekeeping.log)
#       scripts/housekeeping.sh --reminders  (job 10 phút: gửi nhắc việc đến giờ; chỉ in dòng khi có nhắc, cron → /var/log/eos-reminders.log)
set -euo pipefail
PSQL="${PSQL:-docker exec -i eos-postgres psql -U postgres -X -q -At -d eos}"
if [ "${1:-}" = "--reminders" ]; then
$PSQL <<'SQL'
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', (SELECT id FROM core.users WHERE is_system_admin AND kind = 'person' ORDER BY created_at LIMIT 1))::text, true) \g /dev/null
SELECT now()::text || ' reminders ' || r::text FROM (SELECT work.run_reminders() AS r) x WHERE (r->>'sent')::int > 0;
COMMIT;
SQL
exit 0
fi
$PSQL <<'SQL'
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub', (SELECT id FROM core.users WHERE is_system_admin AND kind = 'person' ORDER BY created_at LIMIT 1))::text, true) \g /dev/null
SELECT now()::text || ' upload_sweep ' || agent.upload_sweep(1)::text;
SELECT now()::text || ' prune ' || agent.housekeeping_prune(1)::text;
SELECT now()::text || ' recurrences ' || work.run_recurrences()::text;   -- sinh việc định kỳ đến hạn (docs/18)
COMMIT;
SQL
