#!/usr/bin/env bash
# Diễn tập khôi phục: lấy `eos.dump` từ bản sao lưu MỚI NHẤT trên vps169, khôi phục vào Postgres rỗng trên Z2, đối chiếu với CSDL thật.
#   scripts/restore_drill.sh [--fresh]     (make restore-drill)     --fresh: chạy backup.sh trước (~6 phút, ~900 MB)
# Giải mã diễn ra TRÊN vps169 (mật khẩu sao lưu không rời khỏi đó); chỉ luồng eos.dump (~0,5 MB) về Z2. Dump tạm 600, xóa sau khi xong.
# Cần: docker, ssh vps169. Thoát 0 nếu khôi phục đúng; ghi kết quả vào ops-log/restore-drill-<ngày>.md.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; DB_HOST="${EOS_DB_HOST:-vps169}"; PORT="${EOS_DRILL_PORT:-5437}"
FRESH=0; [ "${1:-}" = "--fresh" ] && FRESH=1
NAME="eos-restore-drill"; T="$(mktemp -d)"; chmod 700 "$T"; LOG="$ROOT/ops-log/restore-drill-$(date +%F-%H%M).md"; mkdir -p "$ROOT/ops-log"
SSHO=(-o BatchMode=yes -o ConnectTimeout=15)
FAIL=0
say() { printf '%s\n' "$*" | tee -a "$LOG"; }
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1; shred -u "$T"/eos.dump 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
chk() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then say "  ✔ $n"; else say "  ✘ $n"; FAIL=1; fi; }
live() { ssh "${SSHO[@]}" "$DB_HOST" "docker exec eos-postgres psql -U postgres -d eos -Atc \"$1\""; }
rest() { docker exec "$NAME" psql -U postgres -d eos -Atc "$1"; }
Q="select count(*) from information_schema.tables where table_schema in ('core','work','doc','hr','crm','kb','agent') and table_type='BASE TABLE' and table_name not like 'audit_log_20%'"

say "# Diễn tập khôi phục — $(date '+%F %T')"
docker ps -a --format '{{.Names}}' | grep -qx "$NAME" && { say "container $NAME đã tồn tại -> dừng (không ghi đè)"; exit 1; }
if [ "$FRESH" = 1 ]; then say "chạy backup.sh trên $DB_HOST…"; ssh "${SSHO[@]}" "$DB_HOST" '/opt/backup/backup.sh' 2>&1 | tail -1 | tee -a "$LOG"; fi
B="$(ssh "${SSHO[@]}" "$DB_HOST" 'ls -1t /var/backups/deo/deo169-*.tar.gpg | head -1')"
[ -n "$B" ] || { say "Không thấy bản sao lưu"; exit 1; }
say "bản sao lưu: $(basename "$B") — cách $(ssh "${SSHO[@]}" "$DB_HOST" "echo \$(( (\$(date +%s) - \$(stat -c %Y $B)) / 3600 ))") giờ"
( umask 077; ssh "${SSHO[@]}" "$DB_HOST" "cd /var/backups/deo && sha256sum -c \$(basename $B).sha256 >&2 && gpg --batch --pinentry-mode loopback --passphrase-file /root/.deo_backup_pass -d $B 2>/dev/null | tar -xOf - ./eos.dump" > "$T/eos.dump" 2>"$T/err" )
chk "checksum bản sao lưu đúng"                         grep -q ": OK" "$T/err"
chk "eos.dump giải mã được và đúng định dạng pg_dump"  bash -c "[ -s '$T/eos.dump' ] && [ \"\$(head -c 5 '$T/eos.dump')\" = PGDMP ]"
docker run -d --name "$NAME" -e POSTGRES_PASSWORD="$(openssl rand -hex 8)" -p "127.0.0.1:$PORT:5432" postgres:16 >/dev/null
for i in $(seq 30); do docker exec "$NAME" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 2; done; sleep 3
docker exec "$NAME" psql -U postgres -qc "CREATE DATABASE eos"
docker exec -i "$NAME" pg_restore -U postgres -d eos --no-owner --no-privileges < "$T/eos.dump" 2>"$T/rerr"; RC=$?
chk "pg_restore thành công, không lỗi"                  bash -c "[ $RC -eq 0 ] && [ ! -s '$T/rerr' ]"
TL="$(live "$Q")"; TR="$(rest "$Q")"
chk "số bảng khôi phục = số bảng CSDL thật ($TR/$TL)"   [ "$TR" = "$TL" ]
say "  số dòng (khôi phục / thật; khôi phục ≤ thật vì thật có thể đã tăng sau bản sao lưu):"
for t in core.companies core.users work.tasks work.comments agent.agents agent.cards agent.reports agent.events; do
  r="$(rest "select count(*) from $t")"; l="$(live "select count(*) from $t")"
  if [ "$r" -le "$l" ] 2>/dev/null && { [ "$t" != core.companies ] || [ "$r" -ge 1 ]; }; then say "    ✔ $t: $r / $l"; else say "    ✘ $t: $r / $l"; FAIL=1; fi
done
OBJ="select 'trigger '||tgname||' on '||tgrelid::regclass from pg_trigger where not tgisinternal union all select 'function '||p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('core','work','doc','hr','crm','kb','agent') order by 1"
live "$OBJ" | sort > "$T/obj.live"; rest "$OBJ" | sort > "$T/obj.rest"
MISSING="$(comm -23 "$T/obj.live" "$T/obj.rest")"; EXTRA="$(comm -13 "$T/obj.live" "$T/obj.rest")"
if [ -z "$MISSING" ] && [ -z "$EXTRA" ]; then say "  ✔ hàm và trigger khôi phục khớp CSDL thật ($(wc -l < "$T/obj.live") đối tượng)"
elif [ -n "$EXTRA" ]; then say "  ✘ bản khôi phục có đối tượng mà CSDL thật không có:"; echo "$EXTRA" | sed 's/^/      /' | tee -a "$LOG"; FAIL=1
elif [ "$FRESH" = 1 ]; then say "  ✘ bản sao lưu mới tạo mà thiếu đối tượng:"; echo "$MISSING" | sed 's/^/      /' | tee -a "$LOG"; FAIL=1
else say "  ⚠ bản sao lưu cũ hơn lần đổi lược đồ gần nhất; thiếu (chạy --fresh để so khớp tuyệt đối):"; echo "$MISSING" | sed 's/^/      /' | tee -a "$LOG"; fi
say ""; [ "$FAIL" = 0 ] && say "KẾT QUẢ: KHÔI PHỤC ĐÚNG ✔ (nhật ký $LOG)" || say "KẾT QUẢ: CÓ LỖI ✘ (nhật ký $LOG)"
exit "$FAIL"
