# Dùng chung cho các script. Nạp bằng: . "$(dirname "$0")/_common.sh"
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Thứ tự nạp lược đồ. Đổi thứ tự = hỏng khóa ngoại.
DB_FILES=(00_core 10_work 20_doc 30_hr 31_payroll_kpi 40_crm 45_kb 50_views 60_agent 61_app 62_workflow 63_features 64_creation)
# EOS_TEST_DSN: chuỗi kết nối tới Postgres 16 (tài khoản superuser) dùng để thử. Cơ sở dữ liệu trong đó sẽ bị XÓA và dựng lại.
need_dsn() {
  [ -n "${EOS_TEST_DSN:-}" ] || { echo "Thiếu EOS_TEST_DSN, ví dụ: postgres://postgres:pw@127.0.0.1:5432/eos_test" >&2; exit 2; }
  case "$EOS_TEST_DSN" in *eos_test*|*eos4*|*_test*) ;; *) echo "Từ chối: tên CSDL trong EOS_TEST_DSN phải chứa '_test' để khỏi xóa nhầm CSDL thật" >&2; exit 2;; esac
}
# Tách tên CSDL và DSN quản trị (trỏ sang CSDL 'postgres')
split_dsn() {
  DBNAME="${EOS_TEST_DSN##*/}"; DBNAME="${DBNAME%%\?*}"
  ADMIN_DSN="${EOS_TEST_DSN%/*}/postgres"
}
# Xóa và dựng lại CSDL thử từ các tệp lược đồ db/*.sql (mỗi bộ kiểm thử bắt đầu từ trạng thái sạch, chạy thứ tự nào cũng được)
rebuild_db() {
  split_dsn
  psql "$ADMIN_DSN" -X -q -c "DROP DATABASE IF EXISTS \"$DBNAME\"" -c "CREATE DATABASE \"$DBNAME\""
  local out rc
  for f in "${DB_FILES[@]}"; do
    rc=0; out=$(psql "$EOS_TEST_DSN" -X -q -v ON_ERROR_STOP=1 -f "$ROOT/db/$f.sql" 2>&1) || rc=$?
    [ "$rc" = 0 ] || { echo "Nạp $f.sql THẤT BẠI:" >&2; echo "$out" | grep -v NOTICE | head -5 >&2; exit 1; }
  done
}
