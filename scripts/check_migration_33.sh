#!/usr/bin/env bash
# Migration 0033 (kb.file_steps): áp hai lần trên CSDL "trước 0033" (62_workflow.sql của HEAD~ khi chưa có file_steps), rồi so hàm với lược đồ dựng mới.
. "$(dirname "$0")/_common.sh"; cd "$ROOT"
: "${EOS_TEST_DSN:?Thiếu EOS_TEST_DSN}"
BASE="${EOS_TEST_DSN%/*}"; OLD="$BASE/eos_mig33_old"; NEW="$BASE/eos_mig33_new"
for d in eos_mig33_old eos_mig33_new; do psql "$BASE/postgres" -X -q -c "DROP DATABASE IF EXISTS $d" -c "CREATE DATABASE $d"; done
EXT="CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS pg_trgm; CREATE EXTENSION IF NOT EXISTS citext;"
for d in "$OLD" "$NEW"; do psql "$d" -X -q -c "$EXT" >/dev/null 2>&1; done
# 62_workflow.sql cũ = bản cắt bỏ khối file_steps (từ dòng "Mã bước" đến trước "Nạp kho song song") và khóa file_steps trong mcp_kb_ingest_target
python3 - "$ROOT/db/62_workflow.sql" > /tmp/62_old.sql <<'PY'
import sys,re
s=open(sys.argv[1],encoding='utf8').read()
a=s.index("-- ---------- Mã bước (01–20) cho từng tệp"); b=s.index("-- ---------- Nạp kho song song: giữ chỗ từng tài liệu")
s=s[:a]+s[b:]
s=re.sub(r",\n    'file_steps', .*?\)\)\);\nEND", ");\nEND", s, count=1, flags=re.S)
s=s.replace(", agent.mcp_tag_step(bigint, jsonb) TO mcp_svc;"," TO mcp_svc;")
sys.stdout.write(s)
PY
for f in "${DB_FILES[@]}"; do
  src="db/$f.sql"; [ "$f" = 62_workflow ] && src=/tmp/62_old.sql
  psql "$OLD" -X -q -v ON_ERROR_STOP=1 -f "$src" >/dev/null || { echo "lỗi nạp $src (bản cũ)" >&2; exit 1; }
  psql "$NEW" -X -q -v ON_ERROR_STOP=1 -f "db/$f.sql" >/dev/null || { echo "lỗi nạp db/$f.sql" >&2; exit 1; }
done
psql "$OLD" -X -Atc "select to_regclass('kb.file_steps') is null" | grep -qx t || { echo "bản cũ vẫn có kb.file_steps (cắt sai)" >&2; exit 1; }
for i in 1 2; do psql "$OLD" -X -q -v ON_ERROR_STOP=1 -f db/migrations/0033_file_steps.sql >/dev/null || { echo "lần $i áp migration lỗi" >&2; exit 1; }; done
Q="select proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('agent','work','kb') order by 1"
diff <(psql "$OLD" -X -At -c "$Q") <(psql "$NEW" -X -At -c "$Q") >/dev/null && echo "hàm: giống hệt lược đồ dựng mới" || { echo "hàm LỆCH giữa migration 0033 và lược đồ mới" >&2; exit 1; }
C="select table_schema||'.'||table_name||'.'||column_name||':'||data_type from information_schema.columns where table_schema in ('kb','agent') order by 1"
diff <(psql "$OLD" -X -At -c "$C") <(psql "$NEW" -X -At -c "$C") >/dev/null && echo "cột: giống hệt" || { echo "cột LỆCH" >&2; exit 1; }
for d in eos_mig33_old eos_mig33_new; do psql "$BASE/postgres" -X -q -c "DROP DATABASE $d"; done
echo "migration 0033: ĐẠT"
