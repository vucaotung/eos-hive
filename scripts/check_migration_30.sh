#!/usr/bin/env bash
# Kiểm tra migration 0030 trên CSDL "trước 0030" (00…63): áp dụng hai lần không lỗi, rồi đối chiếu với lược đồ dựng mới.
. "$(dirname "$0")/_common.sh"; cd "$ROOT"
: "${EOS_TEST_DSN:?Thiếu EOS_TEST_DSN}"
BASE="${EOS_TEST_DSN%/*}"; OLD="$BASE/eos_mig30_old"; NEW="$BASE/eos_mig30_new"
for d in eos_mig30_old eos_mig30_new; do psql "$BASE/postgres" -X -q -c "DROP DATABASE IF EXISTS $d" -c "CREATE DATABASE $d"; done
load() { local dsn="$1"; shift; for f in "$@"; do psql "$dsn" -X -q -v ON_ERROR_STOP=1 -f "db/$f.sql" >/dev/null || { echo "lỗi nạp db/$f.sql" >&2; exit 1; }; done; }
head -n 1 db/test_schema.sql >/dev/null
EXT="CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS pg_trgm; CREATE EXTENSION IF NOT EXISTS citext;"
for d in "$OLD" "$NEW"; do psql "$d" -X -q -c "$EXT" >/dev/null 2>&1; done
load "$OLD" "${DB_FILES[@]:0:12}"
load "$NEW" "${DB_FILES[@]}"
for i in 1 2; do psql "$OLD" -X -q -v ON_ERROR_STOP=1 -f db/migrations/0030_creation_features.sql >/dev/null || { echo "lần $i áp migration lỗi" >&2; exit 1; }; done
Q="select proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('agent','work') order by 1"
diff <(psql "$OLD" -X -At -c "$Q") <(psql "$NEW" -X -At -c "$Q") >/dev/null && echo "hàm: giống hệt lược đồ dựng mới" || { echo "hàm LỆCH giữa migration và lược đồ mới" >&2; exit 1; }
C="select table_schema||'.'||table_name||'.'||column_name||':'||data_type from information_schema.columns where table_schema in ('work','agent','core') order by 1"
diff <(psql "$OLD" -X -At -c "$C") <(psql "$NEW" -X -At -c "$C") >/dev/null && echo "cột: giống hệt" || { echo "cột LỆCH" >&2; exit 1; }
for d in eos_mig30_old eos_mig30_new; do psql "$BASE/postgres" -X -q -c "DROP DATABASE $d"; done
echo "migration 0030: ĐẠT"
