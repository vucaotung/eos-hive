#!/usr/bin/env bash
# Bộ nghiệm thu đầu–cuối trên MÁY THẬT (Z2 điều khiển VPS 169 + VPS 173). Chạy: make acceptance
#   scripts/acceptance.sh [--only A1,A3] [--list]
# Mỗi kịch bản tạo việc gắn nhãn "[ACCEPT <mã-lượt>]" cho agent thật, kiểm từng cổng, rồi DỌN (hủy việc, thu hồi mã,
# archive thẻ, bật lại cầu nối) kể cả khi lỗi giữa chừng. Mã MCP thử sinh trên VPS, nằm trong tệp 600, không bao giờ in.
# Cần: ssh vps169/vps173 không mật khẩu; node ≥ 22 và `npm ci` trong mcp/. Tốn token LLM thật (vài phút mỗi kịch bản).
# Biến: EOS_DB_HOST=vps169 EOS_HERMES_HOST=vps173 EOS_OWNER_EMAIL=… EOS_COMPANY_SLUG=valnex
# Kết thúc: 0 nếu mọi cổng đạt (XFAIL = lỗi đã biết, không tính hỏng), 1 nếu có cổng hỏng.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB_HOST="${EOS_DB_HOST:-vps169}"; H_HOST="${EOS_HERMES_HOST:-vps173}"
OWNER_EMAIL="${EOS_OWNER_EMAIL:-vucaotung@gmail.com}"; SLUG="${EOS_COMPANY_SLUG:-valnex}"
RUN="$(date +%m%d%H%M%S)"; TAG="[ACCEPT $RUN]"
ALL="A1 A2 A3 A4 A5"; ONLY="$ALL"
while [ $# -gt 0 ]; do case "$1" in
  --only) ONLY="$(echo "${2:?}" | tr ',' ' ')"; shift 2;;
  --list) echo "$ALL"; exit 0;;
  *) echo "Dùng: $0 [--only A1,A3] [--list]" >&2; exit 2;;
esac; done
command -v node >/dev/null || { echo "Cần node" >&2; exit 2; }
[ -d "$ROOT/mcp/node_modules" ] || { echo "Chạy: (cd mcp && npm ci)" >&2; exit 2; }

T="$(mktemp -d)"; chmod 700 "$T"
LOG="$ROOT/ops-log/acceptance-$RUN.md"; mkdir -p "$ROOT/ops-log"
PASS=0; FAIL=0; XFAIL=0; XPASS=0
T0=$(date +%s)

# ---------- tiện ích ----------
say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
dbq()  { ssh -o BatchMode=yes -o ConnectTimeout=15 "$DB_HOST" 'docker exec -i eos-postgres psql -U postgres -X -q -At -d eos -v ON_ERROR_STOP=1'; }
hk()   { ssh -o BatchMode=yes -o ConnectTimeout=15 "$H_HOST" "timeout 40 hermes kanban --board $BOARD $*"; }
mcp()  { node "$ROOT/scripts/acceptance/mcp.mjs" "$@"; }
sqlv() { dbq <<<"$1"; }                                   # câu SQL một giá trị
as_owner() {                                              # as_owner "<SQL>" — chạy với danh tính chủ sở hữu
  dbq <<SQL
BEGIN;
SELECT set_config('request.jwt.claims', json_build_object('sub','$OWNER_ID')::text, true) \g /dev/null
$1
COMMIT;
SQL
}
check() {   # check "tên" lệnh… — cổng phải đạt
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); say "  ✔ $name"; else FAIL=$((FAIL+1)); say "  ✘ $name"; fi
}
xcheck() {  # xcheck "tên" "lý do đã biết" lệnh… — lỗi đã biết: hỏng là bình thường, bỗng đạt thì báo để gỡ nhãn
  local name="$1" why="$2"; shift 2
  if "$@" >/dev/null 2>&1; then XPASS=$((XPASS+1)); say "  ⚠ $name — ĐÃ ĐẠT, hãy đổi xcheck thành check"
  else XFAIL=$((XFAIL+1)); say "  ◌ $name — lỗi đã biết: $why"; fi
}
new_task() {   # new_task "tiêu đề" "mô tả" mã-agent  → in id
  local title="$1" desc="$2" agent="$3"
  dbq <<SQL
INSERT INTO work.tasks (company_id, department_id, title, description, assignee_id, agent_id, created_by)
SELECT c.id, d.id, \$q\$$TAG $title\$q\$, \$q\$$desc\$q\$, u.id, a.id, u.id
  FROM core.companies c JOIN core.departments d ON d.company_id = c.id AND d.code = 'HC'
  JOIN core.users u ON u.email = '$OWNER_EMAIL' JOIN agent.agents a ON a.code = '$agent'
 WHERE c.slug = '$SLUG' RETURNING id;
SQL
}
tstatus() { sqlv "select status from work.tasks where id=$1"; }
wait_until() {   # wait_until <giây> lệnh… — thăm dò 5 s/lần
  local limit="$1"; shift; local end=$(( $(date +%s) + limit ))
  while [ "$(date +%s)" -lt "$end" ]; do "$@" >/dev/null 2>&1 && return 0; sleep 5; done; return 1
}
is_status()   { [ "$(tstatus "$1")" = "$2" ]; }
has_card()    { [ "$(sqlv "select count(*) from agent.cards where task_id=$1 and card_id is not null")" -ge 1 ]; }
card_of()     { sqlv "select card_id from agent.cards where task_id=$1 order by id desc limit 1"; }
card_status() { sqlv "select status from agent.cards where task_id=$1 order by id desc limit 1"; }
mcp_out()     { mcp "$@" 2>&1 || true; }                    # in đầu ra kể cả khi công cụ trả lỗi (mã 3)
hermes_has_card()  { hk list --json 2>/dev/null | grep -q "\"$(card_of "$1")\""; }
hermes_card_archived() { ssh -o BatchMode=yes "$H_HOST" "timeout 40 hermes kanban --board $BOARD show $(card_of "$1") --json" 2>/dev/null | grep -q '"status": "archived"'; }
answer_acked()     { [ "$(sqlv "select count(*) from agent.outbox where task_id=$1 and kind='answer' and done_at is not null")" -ge 1 ]; }
cancel_queued()    { [ "$(sqlv "select count(*) from agent.outbox where task_id=$1 and kind='cancel'")" -ge 1 ]; }
cancel_acked()     { [ "$(sqlv "select count(*) from agent.outbox where task_id=$1 and kind='cancel' and done_at is not null")" -ge 1 ]; }
sees_question()    { mcp_out eos_get_task "{\"task\":\"T-$1\"}" | grep -q question; }
wrong_token_rejected() { ( EOS_ACCEPT_TOKEN="eos_$(printf '0%.0s' $(seq 48))"; mcp --list >/dev/null 2>&1; [ $? -eq 4 ] ); }
hr_denied()        { mcp_out eos_my_hr '{"what":"leave"}' | grep -q hr_self; }
missing_task_err() { mcp eos_get_task '{"task":"T-999999"}' >/dev/null 2>&1; [ $? -eq 3 ]; }
whoami_ok()        { mcp_out eos_whoami '{}' | grep -q "$OWNER_EMAIL"; }

cleanup() {
  local rc=$?
  say ""; say "— Dọn dẹp —"
  ssh -o BatchMode=yes -o ConnectTimeout=15 "$H_HOST" 'systemctl --user start eos-kanban-bridge' >/dev/null 2>&1 \
    && say "  cầu nối: bảo đảm đang chạy"
  if [ -n "${OWNER_ID:-}" ]; then
    local cards; cards="$(dbq <<SQL 2>/dev/null
SELECT c.board || ' ' || c.card_id FROM agent.cards c WHERE c.card_id IS NOT NULL AND c.task_id IN
  (SELECT id FROM work.tasks WHERE title LIKE \$q\$$TAG%\$q\$ OR parent_id IN (SELECT id FROM work.tasks WHERE title LIKE \$q\$$TAG%\$q\$));
SQL
)"
    dbq >/dev/null 2>&1 <<SQL
UPDATE work.tasks SET status='cancelled', completed_at=NULL, kpi_counted=false, updated_at=now()
 WHERE (title LIKE \$q\$$TAG%\$q\$ OR parent_id IN (SELECT id FROM work.tasks WHERE title LIKE \$q\$$TAG%\$q\$)) AND status <> 'cancelled';
UPDATE agent.cards SET status='cancelled' WHERE status NOT IN ('done','archived','gave_up','crashed','timed_out','cancelled')
   AND task_id IN (SELECT id FROM work.tasks WHERE title LIKE \$q\$$TAG%\$q\$ OR parent_id IN (SELECT id FROM work.tasks WHERE title LIKE \$q\$$TAG%\$q\$));
UPDATE agent.mcp_tokens SET revoked_at = now() WHERE name = 'ACCEPT $RUN' AND revoked_at IS NULL;
SQL
    local n=0 b c
    while read -r b c; do [ -n "$c" ] || continue
      ssh -n -o BatchMode=yes "$H_HOST" "timeout 40 hermes kanban --board $b archive $c" >/dev/null 2>&1; n=$((n+1)); done <<<"$cards"
    say "  việc [ACCEPT $RUN] đã hủy; mã thử đã thu hồi; $n thẻ Kanban đã archive"
  fi
  rm -rf "$T"
  local secs=$(( $(date +%s) - T0 ))
  say ""; say "KẾT QUẢ: ✔ $PASS đạt · ✘ $FAIL hỏng · ◌ $XFAIL lỗi đã biết · ⚠ $XPASS bỗng đạt · ${secs}s · nhật ký $LOG"
  if [ "$FAIL" -gt 0 ] || [ "$rc" -ne 0 ]; then exit 1; fi
  exit 0
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ---------- chuẩn bị ----------
say "# Nghiệm thu $RUN — $(date '+%F %T') — kịch bản: $ONLY"
OWNER_ID="$(sqlv "select id from core.users where email='$OWNER_EMAIL' and kind='person'")"
[ -n "$OWNER_ID" ] || { say "Không thấy người dùng $OWNER_EMAIL"; exit 1; }
BOARD="$(sqlv "select kanban_board from agent.company_settings s join core.companies c on c.id=s.company_id where c.slug='$SLUG'")"
[ -n "$BOARD" ] || { say "Công ty $SLUG chưa bật agent"; exit 1; }
say "người thử: $OWNER_EMAIL · công ty: $SLUG · board: $BOARD"
( umask 077; as_owner "SELECT agent.mcp_token_issue('ACCEPT $RUN','other','{read,write}', 1);" > "$T/token" )
grep -qE '^eos_[0-9a-f]{48}$' "$T/token" || { say "Không cấp được mã MCP thử"; exit 1; }
export EOS_ACCEPT_TOKEN; EOS_ACCEPT_TOKEN="$(cat "$T/token")"

# ---------- kịch bản ----------
s_A1() {
  say ""; say "A1 · Vòng đời: giao việc → thẻ → hỏi lại → trả lời → báo xong → chấp nhận"
  local id card; id="$(new_task 'vòng đời' "Chỉ để kiểm thử. Hãy kanban_block hỏi: 'Áp dụng cho dự án nào?'. Sau khi nhận câu trả lời, kanban_complete với summary ≥ 10 ký tự và metadata.confidence='cao'." quan-tri-du-lieu)"
  say "  việc T-$id"
  check "thẻ Kanban được tạo ≤ 2 phút"                      wait_until 120 has_card "$id"
  check "Hermes thấy thẻ trên board $BOARD"                  hermes_has_card "$id"
  check "agent chặn hỏi lại ≤ 4 phút → việc Vướng"          wait_until 240 is_status "$id" blocked
  check "việc đang chờ người (waiting_on_human)"             [ "$(sqlv "select waiting_on_human from work.tasks where id=$id")" = t ]
  check "câu hỏi hiện thành bình luận kind=question"         [ "$(sqlv "select count(*) from work.comments where task_id=$id and kind='question'")" -ge 1 ]
  check "người thử đọc được câu hỏi qua MCP (eos_get_task)"  sees_question "$id"
  mcp eos_comment "{\"task\":\"T-$id\",\"kind\":\"answer\",\"body\":\"Áp dụng cho dự án ACCEPT-$RUN.\"}" >/dev/null 2>&1
  check "câu trả lời được đẩy sang Hermes ≤ 90 s"            wait_until 90 answer_acked "$id"
  check "agent hoàn tất ≤ 5 phút → Chờ xem"                  wait_until 300 is_status "$id" in_review
  check "báo cáo có độ tin cậy 'cao' và có tóm tắt"          [ "$(sqlv "select count(*) from agent.reports where task_id=$id and confidence='cao' and length(summary)>=10")" = 1 ]
  check "người chấp nhận → Xong"                             [ "$(as_owner "SELECT agent.accept_result($id,'ACCEPT');" | tail -1)" = done ]
  check "thẻ Kanban ở trạng thái done"                       [ "$(card_status "$id")" = done ]
  check "không có báo cáo trùng"                             [ "$(sqlv "select count(*) from agent.reports where task_id=$id")" = 1 ]
}
s_A2() {
  say ""; say "A2 · Quyền truy cập MCP"
  check "mã đúng: 15 công cụ"                                [ "$(mcp --list)" = 15 ]
  check "mã sai bị từ chối (kết nối)"                        wrong_token_rejected
  check "thiếu phạm vi hr_self → eos_my_hr bị từ chối"       hr_denied
  check "việc không tồn tại → lỗi, không lộ dữ liệu"         missing_task_err
  check "eos_whoami trả đúng người"                          whoami_ok
}
s_A3() {
  say ""; say "A3 · Làm lại: trả kết quả → thẻ rework mới kèm lý do → xong lượt 2"
  local id; id="$(new_task 'làm lại' "Chỉ để kiểm thử. Hãy gọi kanban_complete ngay với summary: Hoàn tất lượt này để kiểm thử làm lại, và metadata.confidence='cao'." quan-tri-du-lieu)"
  say "  việc T-$id"
  check "lượt 1 hoàn tất ≤ 6 phút → Chờ xem"                wait_until 360 is_status "$id" in_review
  check "trả lại có lý do → hệ thống báo 'rework'"           [ "$(as_owner "SELECT agent.reject_result($id,'Thiếu số liệu, hãy làm lại (ACCEPT).');" | tail -1)" = rework ]
  check "sinh thẻ rework lượt 2"                             [ "$(sqlv "select count(*) from agent.cards where task_id=$id and kind='rework' and attempt=2")" = 1 ]
  check "lý do trả lại nằm trong lệnh dispatch"              [ "$(sqlv "select count(*) from agent.outbox where task_id=$id and kind='dispatch' and payload ? 'rework_reason'")" = 1 ]
  check "báo cáo lượt 1 đánh dấu rework"                     [ "$(sqlv "select count(*) from agent.reports where task_id=$id and verdict='rework'")" = 1 ]
  check "lượt 2 hoàn tất ≤ 6 phút → Chờ xem"                wait_until 360 is_status "$id" in_review
  check "có 2 báo cáo, báo cáo mới đang chờ"                 [ "$(sqlv "select count(*) from agent.reports where task_id=$id")" = 2 ]
  check "chấp nhận lượt 2 → Xong"                            [ "$(as_owner "SELECT agent.accept_result($id,'ACCEPT');" | tail -1)" = done ]
}
s_A4() {
  say ""; say "A4 · Hủy việc đang chạy: thẻ Kanban phải được dừng/lưu trữ"
  local id; id="$(new_task 'hủy việc' "Chỉ để kiểm thử. Hãy kanban_block hỏi: 'Có tiếp tục không?' rồi chờ." quan-tri-du-lieu)"
  say "  việc T-$id"
  check "agent chặn hỏi ≤ 4 phút (thẻ còn sống)"             wait_until 240 is_status "$id" blocked
  as_owner "UPDATE work.tasks SET status='cancelled', completed_at=NULL, updated_at=now() WHERE id=$id;" >/dev/null 2>&1
  check "hủy việc sinh lệnh 'cancel' trong hộp thư đi"       wait_until 40 cancel_queued "$id"
  check "cầu nối xử lý lệnh cancel ≤ 90 s"                   wait_until 90 cancel_acked "$id"
  check "thẻ Kanban được archive sau khi hủy việc"           wait_until 60 hermes_card_archived "$id"
  check "thẻ trong CSDL ở trạng thái cancelled"              [ "$(card_status "$id")" = cancelled ]
}
s_A5() {
  say ""; say "A5 · Chịu lỗi: cầu nối dừng rồi chạy lại — việc không mất, không tạo thẻ đôi"
  ssh -o BatchMode=yes "$H_HOST" 'systemctl --user stop eos-kanban-bridge' >/dev/null 2>&1
  local id; id="$(new_task 'chịu lỗi' "Chỉ để kiểm thử. Hãy gọi kanban_complete ngay với summary: Hoàn tất kiểm thử chịu lỗi, và metadata.confidence='cao'." quan-tri-du-lieu)"
  say "  việc T-$id (cầu nối đang dừng)"
  sleep 45
  check "khi cầu nối dừng, lệnh nằm chờ trong hộp thư đi"    [ "$(sqlv "select count(*) from agent.outbox where task_id=$id and kind='dispatch' and done_at is null")" = 1 ]
  check "khi cầu nối dừng, chưa có thẻ Kanban"               [ "$(sqlv "select count(*) from agent.cards where task_id=$id and card_id is not null")" = 0 ]
  ssh -o BatchMode=yes "$H_HOST" 'systemctl --user start eos-kanban-bridge' >/dev/null 2>&1
  check "cầu nối chạy lại → thẻ được tạo ≤ 90 s"            wait_until 90 has_card "$id"
  check "chỉ đúng 1 thẻ cho việc này"                        [ "$(sqlv "select count(*) from agent.cards where task_id=$id")" = 1 ]
  check "việc hoàn tất ≤ 6 phút → Chờ xem"                   wait_until 360 is_status "$id" in_review
  as_owner "SELECT agent.accept_result($id,'ACCEPT');" >/dev/null 2>&1
}

for s in $ONLY; do "s_$s" || true; done
