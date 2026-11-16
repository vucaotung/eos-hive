#!/usr/bin/env bash
# Migration 0.6 (0031, 0032, 0033…): áp hai lần trên CSDL dựng từ lược đồ của main (v0.5.x), rồi so hàm, cột, ràng buộc với lược đồ dựng mới từ db/*.sql hiện tại.
. "$(dirname "$0")/_common.sh"; cd "$ROOT"
: "${EOS_TEST_DSN:?Thiếu EOS_TEST_DSN}"
BASE_REV="${BASE_REV:-$(git merge-base HEAD origin/main 2>/dev/null || git rev-parse main)}"
BASE="${EOS_TEST_DSN%/*}"; OLD="$BASE/eos_mig06_old"; NEW="$BASE/eos_mig06_new"
for d in eos_mig06_old eos_mig06_new; do psql "$BASE/postgres" -X -q -c "DROP DATABASE IF EXISTS $d" -c "CREATE DATABASE $d"; done
EXT="CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS pg_trgm; CREATE EXTENSION IF NOT EXISTS citext;"
for d in "$OLD" "$NEW"; do psql "$d" -X -q -c "$EXT" >/dev/null 2>&1; done
for f in "${DB_FILES[@]}"; do
  git show "$BASE_REV:db/$f.sql" > /tmp/mig06_old.sql 2>/dev/null && { psql "$OLD" -X -q -v ON_ERROR_STOP=1 -f /tmp/mig06_old.sql >/dev/null 2>&1 || { echo "lỗi nạp $f (bản $BASE_REV)" >&2; exit 1; }; }
  psql "$NEW" -X -q -v ON_ERROR_STOP=1 -f "db/$f.sql" >/dev/null 2>&1 || { echo "lỗi nạp db/$f.sql" >&2; exit 1; }
done
for m in $(ls db/migrations/003[1-9]_*.sql db/migrations/00[4-9]*.sql 2>/dev/null | sort); do
  for i in 1 2; do psql "$OLD" -X -q -v ON_ERROR_STOP=1 -f "$m" >/dev/null 2>&1 || { echo "lần $i áp $m lỗi" >&2; psql "$OLD" -X -q -v ON_ERROR_STOP=1 -f "$m" 2>&1 | grep ERROR | head -3 >&2; exit 1; }; done
done
Q="select p.oid::regprocedure::text || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('agent','work','kb') order by 1"
diff <(psql "$OLD" -X -At -c "$Q") <(psql "$NEW" -X -At -c "$Q") >/dev/null && echo "hàm: giống hệt lược đồ dựng mới" || { echo "hàm LỆCH giữa migration và lược đồ mới" >&2; diff <(psql "$OLD" -X -At -c "$Q") <(psql "$NEW" -X -At -c "$Q") | cut -c1-150 | head -6 >&2; exit 1; }
C="select table_schema||'.'||table_name||'.'||column_name||':'||data_type||':'||is_nullable from information_schema.columns where table_schema in ('kb','agent','doc') order by 1"
diff <(psql "$OLD" -X -At -c "$C") <(psql "$NEW" -X -At -c "$C") >/dev/null && echo "cột: giống hệt" || { echo "cột LỆCH" >&2; diff <(psql "$OLD" -X -At -c "$C") <(psql "$NEW" -X -At -c "$C") | head -6 >&2; exit 1; }
K="select conrelid::regclass::text||':'||pg_get_constraintdef(oid) from pg_constraint where connamespace in ('kb'::regnamespace,'agent'::regnamespace,'doc'::regnamespace) and contype in ('c','u') order by 1"
diff <(psql "$OLD" -X -At -c "$K") <(psql "$NEW" -X -At -c "$K") >/dev/null && echo "ràng buộc: giống hệt" || { echo "ràng buộc LỆCH" >&2; diff <(psql "$OLD" -X -At -c "$K") <(psql "$NEW" -X -At -c "$K") | cut -c1-200 | head -6 >&2; exit 1; }
PB="select md5(playbook) from agent.workflows where code = 'project-intake'"
[ "$(psql "$OLD" -X -At -c "$PB")" = "$(psql "$NEW" -X -At -c "$PB")" ] && echo "playbook: giống hệt" || { echo "playbook LỆCH giữa migration và lược đồ mới" >&2; exit 1; }
[ -n "${KEEP:-}" ] || for d in eos_mig06_old eos_mig06_new; do psql "$BASE/postgres" -X -q -c "DROP DATABASE $d"; done
echo "migration 0.6 (0031…): ĐẠT"
