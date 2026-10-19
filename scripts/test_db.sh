#!/usr/bin/env bash
# Dựng lại CSDL thử từ đầu, nạp 9 tệp lược đồ, chạy test_schema.sql và test_agent.sql.
# Cần: psql, Postgres 16 với extension pgcrypto, unaccent, pg_trgm.
. "$(dirname "$0")/_common.sh"; need_dsn
rebuild_db
SCH=$(psql "$EOS_TEST_DSN" -X -q -v ON_ERROR_STOP=1 -f "$ROOT/db/test_schema.sql" 2>&1) || { echo "test_schema THẤT BẠI" >&2; echo "$SCH" | tail -8 >&2; exit 1; }
echo "$SCH" | grep -E "ok" || true
OUT=$(psql "$EOS_TEST_DSN" -X -q -v ON_ERROR_STOP=1 -f "$ROOT/db/test_agent.sql" 2>&1) || { echo "test_agent THẤT BẠI" >&2; echo "$OUT" | tail -12 >&2; exit 1; }
echo "$OUT" | grep -E "ERROR|ok:|đạt" | tail -5
echo "$OUT" | grep -q "tất cả kiểm thử đều đạt" || { echo "test_agent THẤT BẠI" >&2; echo "$OUT" | tail -20 >&2; exit 1; }
T=$(psql "$EOS_TEST_DSN" -X -At -c "select count(*) from information_schema.tables where table_type='BASE TABLE' and table_schema in ('core','work','doc','hr','crm','kb','agent') and table_name not like 'audit_log_20%'")
V=$(psql "$EOS_TEST_DSN" -X -At -c "select count(*) from information_schema.views where table_schema in ('core','work','doc','hr','crm','kb','agent')")
echo "Bảng: $T, view: $V (chuẩn v0.0.0: 108 và 5)"
[ "$T" = 108 ] && [ "$V" = 5 ] || { echo "Số bảng/view lệch chuẩn" >&2; exit 1; }
echo "test_db: ĐẠT"
