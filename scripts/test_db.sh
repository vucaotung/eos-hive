#!/usr/bin/env bash
# Dựng lại CSDL thử từ đầu, nạp các tệp lược đồ, chạy test_schema.sql, test_agent.sql và test_workflow.sql.
# Cần: psql, Postgres 16 với extension pgcrypto, unaccent, pg_trgm.
. "$(dirname "$0")/_common.sh"; need_dsn
rebuild_db
SCH=$(psql "$EOS_TEST_DSN" -X -q -v ON_ERROR_STOP=1 -f "$ROOT/db/test_schema.sql" 2>&1) || { echo "test_schema THẤT BẠI" >&2; echo "$SCH" | tail -8 >&2; exit 1; }
echo "$SCH" | grep -E "ok" || true
OUT=$(psql "$EOS_TEST_DSN" -X -q -v ON_ERROR_STOP=1 -f "$ROOT/db/test_agent.sql" 2>&1) || { echo "test_agent THẤT BẠI" >&2; echo "$OUT" | tail -12 >&2; exit 1; }
echo "$OUT" | grep -E "ERROR|ok:|đạt" | tail -5
echo "$OUT" | grep -q "tất cả kiểm thử đều đạt" || { echo "test_agent THẤT BẠI" >&2; echo "$OUT" | tail -20 >&2; exit 1; }
WF=$(psql "$EOS_TEST_DSN" -X -q -v ON_ERROR_STOP=1 -f "$ROOT/db/test_workflow.sql" 2>&1) || { echo "test_workflow THẤT BẠI" >&2; echo "$WF" | tail -12 >&2; exit 1; }
echo "$WF" | grep -E "ok$" | sed "s/.*NOTICE: *//"
echo "$WF" | grep -q "tất cả kiểm thử đều đạt" || { echo "test_workflow THẤT BẠI" >&2; echo "$WF" | tail -20 >&2; exit 1; }
T=$(psql "$EOS_TEST_DSN" -X -At -c "select count(*) from information_schema.tables where table_type='BASE TABLE' and table_schema in ('core','work','doc','hr','crm','kb','agent') and table_name not like 'audit_log_20%'")
V=$(psql "$EOS_TEST_DSN" -X -At -c "select count(*) from information_schema.views where table_schema in ('core','work','doc','hr','crm','kb','agent')")
echo "Bảng: $T, view: $V (chuẩn 0.5.x: 120 và 5)"
[ "$T" = 120 ] && [ "$V" = 5 ] || { echo "Số bảng/view lệch chuẩn" >&2; exit 1; }
echo "test_db: ĐẠT"
