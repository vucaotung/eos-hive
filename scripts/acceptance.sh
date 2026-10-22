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
ALL="A1 A2 A3 A4 A5 A6 A7 A8 A9"; ONLY="$ALL"
while [ $# -gt 0 ]; do case "$1" in
  --only) ONLY="$(echo "${2:?}" | tr ',' ' ')"; shift 2;;
  --list) echo "$ALL"; exit 0;;
  *) echo "Dùng: $0 [--only A1,A3] [--list]" >&2; exit 2;;
esac; done
command -v node >/dev/null || { echo "Cần node" >&2; exit 2; }
[ -d "$ROOT/mcp/node_modules" ] || { echo "Chạy: (cd mcp && npm ci)" >&2; exit 2; }

T="$(mktemp -d)"; chmod 700 "$T"
SSHO=(-o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=auto -o "ControlPath=$T/cm-%C" -o ControlPersist=300)   # một kết nối dùng chung: tránh nghẽn sshd khi gọi dồn dập
LOG="$ROOT/ops-log/acceptance-$RUN.md"; mkdir -p "$ROOT/ops-log"
PASS=0; FAIL=0; XFAIL=0; XPASS=0
T0=$(date +%s)

# ---------- tiện ích ----------
say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
dbq() {   # đọc SQL từ stdin; ssh lỗi kết nối (255) thì thử lại tối đa 3 lần
  local in rc i; in="$(cat)"
  for i in 1 2 3; do
    ssh "${SSHO[@]}" "$DB_HOST" 'docker exec -i eos-postgres psql -U postgres -X -q -At -d eos -v ON_ERROR_STOP=1' <<<"$in"; rc=$?
    [ "$rc" -ne 255 ] && return "$rc"; sleep 2
  done; return 255
}
hk()   { ssh "${SSHO[@]}" "$H_HOST" "timeout 40 hermes kanban --board $BOARD $*"; }
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
hermes_card_archived() { ssh "${SSHO[@]}" "$H_HOST" "timeout 40 hermes kanban --board $BOARD show $(card_of "$1") --json" 2>/dev/null | grep -q '"status": "archived"'; }
answer_acked()     { [ "$(sqlv "select count(*) from agent.outbox where task_id=$1 and kind='answer' and done_at is not null")" -ge 1 ]; }
cancel_queued()    { [ "$(sqlv "select count(*) from agent.outbox where task_id=$1 and kind='cancel'")" -ge 1 ]; }
cancel_acked()     { [ "$(sqlv "select count(*) from agent.outbox where task_id=$1 and kind='cancel' and done_at is not null")" -ge 1 ]; }
sees_question()    { mcp_out eos_get_task "{\"task\":\"T-$1\"}" | grep -q question; }
children_agents() { sqlv "select coalesce(string_agg(a.code, ',' order by a.code), '') from work.tasks k join agent.agents a on a.id = k.agent_id where k.parent_id = $1 and k.source = 'agent'"; }
children_done()   { [ "$(sqlv "select count(*) from work.tasks where parent_id = $1 and source = 'agent' and status = 'done'")" = 2 ]; }
two_children()    { [ "$(children_agents "$1")" = "nhan-su,van-thu" ]; }
child_profiles_ok() { [ "$(sqlv "select coalesce(string_agg(o.payload->>'profile', ',' order by o.payload->>'profile'), '') from agent.outbox o join work.tasks k on k.id = o.task_id where k.parent_id = $1 and o.kind = 'dispatch'")" = "eos-nhan-su,eos-van-thu" ]; }
synthesis_cards() { sqlv "select count(*) from agent.cards where task_id = $1 and kind = 'synthesis'"; }
has_synthesis()   { [ "$(synthesis_cards "$1")" -ge 1 ]; }
draft_attached()  { [ "$(sqlv "select count(*) from core.attachments a join core.files f on f.id = a.file_id where a.entity_type='task' and a.entity_id='$1' and a.role='result' and a.actor='agent:van-thu' and f.name like 'T-$1 - Du thao - Cong van%.docx' and f.mime_type like '%wordprocessingml%' and f.size_bytes > 5000")" = 1 ]; }
draft_call_clean() { [ "$(sqlv "select count(*) from agent.mcp_calls c join agent.mcp_tokens t on t.id=c.token_id where c.tool='eos_draft_document' and c.entity_id='$1' and c.outcome='ok' and t.agent_id is not null and (c.args->>'ngay_dien')::boolean = false and (c.args->>'du_thao')::boolean = true")" -ge 1 ]; }
report_has_draft() { [ "$(sqlv "select count(*) from agent.reports where task_id=$1 and jsonb_array_length(outputs) >= 1 and outputs->0->>'drive_id' is not null and outputs->0->>'url' like 'https://%'")" = 1 ]; }
question_mentions() { sqlv "select body from work.comments where task_id=$1 and kind='question' order by id desc limit 1" | grep -qi -E "$2"; }
wrong_token_rejected() { ( EOS_ACCEPT_TOKEN="eos_$(printf '0%.0s' $(seq 48))"; mcp --list >/dev/null 2>&1; [ $? -eq 4 ] ); }
hr_denied()        { mcp_out eos_my_hr '{"what":"leave"}' | grep -q hr_self; }
missing_task_err() { mcp eos_get_task '{"task":"T-999999"}' >/dev/null 2>&1; [ $? -eq 3 ]; }
whoami_ok()        { mcp_out eos_whoami '{}' | grep -q "$OWNER_EMAIL"; }

cleanup() {
  local rc=$?
  say ""; say "— Dọn dẹp —"
  ssh "${SSHO[@]}" "$H_HOST" 'systemctl --user start eos-kanban-bridge' >/dev/null 2>&1 \
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
      ssh -n "${SSHO[@]}" "$H_HOST" "timeout 40 hermes kanban --board $b archive $c" >/dev/null 2>&1; n=$((n+1)); done <<<"$cards"
    say "  việc [ACCEPT $RUN] đã hủy; mã thử đã thu hồi; $n thẻ Kanban đã archive"
  fi
  ssh -O exit "${SSHO[@]}" "$DB_HOST" >/dev/null 2>&1; ssh -O exit "${SSHO[@]}" "$H_HOST" >/dev/null 2>&1
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
  ssh "${SSHO[@]}" "$H_HOST" 'systemctl --user stop eos-kanban-bridge' >/dev/null 2>&1
  local id; id="$(new_task 'chịu lỗi' "Chỉ để kiểm thử. Hãy gọi kanban_complete ngay với summary: Hoàn tất kiểm thử chịu lỗi, và metadata.confidence='cao'." quan-tri-du-lieu)"
  say "  việc T-$id (cầu nối đang dừng)"
  sleep 45
  check "khi cầu nối dừng, lệnh nằm chờ trong hộp thư đi"    [ "$(sqlv "select count(*) from agent.outbox where task_id=$id and kind='dispatch' and done_at is null")" = 1 ]
  check "khi cầu nối dừng, chưa có thẻ Kanban"               [ "$(sqlv "select count(*) from agent.cards where task_id=$id and card_id is not null")" = 0 ]
  ssh "${SSHO[@]}" "$H_HOST" 'systemctl --user start eos-kanban-bridge' >/dev/null 2>&1
  check "cầu nối chạy lại → thẻ được tạo ≤ 90 s"            wait_until 90 has_card "$id"
  check "chỉ đúng 1 thẻ cho việc này"                        [ "$(sqlv "select count(*) from agent.cards where task_id=$id")" = 1 ]
  check "việc hoàn tất ≤ 6 phút → Chờ xem"                   wait_until 360 is_status "$id" in_review
  as_owner "SELECT agent.accept_result($id,'ACCEPT');" >/dev/null 2>&1
}

s_A6() {
  say ""; say "A6 · Chia việc con: Điều phối → 2 việc con (Văn thư, Nhân sự) → thẻ tổng hợp → chờ xem"
  local id; id="$(new_task 'chia việc con' "Chỉ để kiểm thử. Bước 1: gọi công cụ eos_delegate với đúng 2 việc con: (1) agent=van-thu, title='Con A kiểm thử', description='Chỉ để kiểm thử: gọi kanban_complete ngay với summary: Hoàn tất việc con A kiểm thử'; (2) agent=nhan-su, title='Con B kiểm thử', description='Chỉ để kiểm thử: gọi kanban_complete ngay với summary: Hoàn tất việc con B kiểm thử'. Bước 2: ngay sau khi chia xong, gọi kanban_complete với summary: Đã chia 2 việc con và chờ kết quả. Bước 3: khi nhận thẻ TỔNG HỢP, đọc T-<số> bằng eos_get_task rồi gọi kanban_complete với summary tổng hợp kết quả hai việc con và metadata.confidence='cao'." dieu-phoi)"
  say "  việc T-$id"
  check "thẻ của Điều phối được tạo ≤ 2 phút"                wait_until 120 has_card "$id"
  check "Điều phối chia đúng 2 việc con (van-thu, nhan-su) ≤ 6 phút" wait_until 360 two_children "$id"
  check "việc con không tính KPI, do agent chia"             [ "$(sqlv "select count(*) from work.tasks where parent_id=$id and source='agent' and kpi_counted=false")" = 2 ]
  check "mỗi việc con có thẻ riêng đúng profile"             wait_until 120 child_profiles_ok "$id"
  check "cả 2 việc con tự Xong ≤ 8 phút (auto_done)"         wait_until 480 children_done "$id"
  check "việc cha sinh đúng một thẻ tổng hợp"                wait_until 120 has_synthesis "$id"
  check "Điều phối nộp bản tổng hợp ≤ 8 phút → Chờ xem"      wait_until 480 is_status "$id" in_review
  check "chỉ một thẻ tổng hợp"                               [ "$(synthesis_cards "$id")" = 1 ]
  check "người chấp nhận bản tổng hợp → Xong"                [ "$(as_owner "SELECT agent.accept_result($id,'ACCEPT');" | tail -1)" = done ]
}

s_A7() {
  say ""; say "A7 · Văn thư soạn công văn theo NĐ 30: đủ thông tin → dự thảo .docx; thiếu thông tin → hỏi, không bịa"
  local id; id="$(new_task 'soạn công văn' "Soạn công văn của Công ty TNHH Valnex gửi Công ty Cổ phần Đầu tư ABC về việc đề nghị cung cấp hồ sơ năng lực dự án (giấy chứng nhận đăng ký doanh nghiệp và báo cáo tài chính hai năm gần nhất). Địa danh: Hà Nội. Ký hiệu: VALNEX-HC. Người ký: Phó giám đốc ký thay Giám đốc (họ tên chưa có). Nơi nhận: Như trên; Giám đốc (để b/c); Lưu: VT, HC." van-thu)"
  say "  việc T-$id (đủ thông tin)"
  check "thẻ của Văn thư được tạo ≤ 2 phút"                  wait_until 120 has_card "$id"
  check "Văn thư nộp dự thảo ≤ 8 phút → Chờ xem"            wait_until 480 is_status "$id" in_review
  check "tệp .docx dự thảo gắn vào việc (do agent:van-thu, MIME docx, > 5 KB)" draft_attached "$id"
  check "gọi công cụ: KHÔNG điền ngày, vẫn là dự thảo (nhật ký MCP)" draft_call_clean "$id"
  check "báo cáo có outputs với drive_id và url"             report_has_draft "$id"
  as_owner "SELECT agent.accept_result($id,'ACCEPT');" >/dev/null 2>&1
  local id2; id2="$(new_task 'soạn công văn thiếu tin' "Soạn một công văn gửi một đối tác về việc đề nghị gia hạn hợp đồng. Chưa có thêm thông tin nào khác." van-thu)"
  say "  việc T-$id2 (cố ý thiếu: địa danh, người nhận, người ký)"
  check "thiếu thông tin → Văn thư chặn hỏi ≤ 6 phút"       wait_until 360 is_status "$id2" blocked
  check "câu hỏi nêu thiếu địa danh/người ký/nơi nhận"       question_mentions "$id2" "địa danh|người ký|ai ký|kính gửi|nơi nhận|tên đối tác"
  check "không tạo tệp khi thiếu thông tin"                  [ "$(sqlv "select count(*) from core.attachments where entity_type='task' and entity_id='$id2'")" = 0 ]
}

web_code() { curl -s -o /dev/null -m 15 -w '%{http_code}' "$@"; }   # -w ở cuối lệnh gọi sẽ ghi đè định dạng
web_headers() { curl -s -D - -o /dev/null -m 15 "${1:-https://work.enterpriseos.bond/app/}" | tr -d '\r' | tr 'A-Z' 'a-z'; }
# CSP: script chỉ 'self' (không unsafe-inline/eval trong script-src); style-src có unsafe-inline vì thư viện giao diện đặt style theo phần tử (docs/10)
web_csp_strict()  { local h csp; h="$(web_headers)"; csp="$(echo "$h" | grep '^content-security-policy:')"; echo "$csp" | grep -q "default-src 'none'" && echo "$csp" | grep -q "script-src 'self'" && ! echo "$csp" | grep -Eq "script-src[^;]*unsafe" && ! echo "$csp" | grep -q unsafe-eval; }
web_hdr_basic()   { local h; h="$(web_headers https://work.enterpriseos.bond/app/api/me)"; echo "$h" | grep -q strict-transport-security && echo "$h" | grep -q 'x-content-type-options: nosniff' && echo "$h" | grep -q 'x-frame-options: deny' && echo "$h" | grep -q 'cache-control: no-store'; }
web_no_powered()  { ! web_headers | grep -q x-powered-by; }
web_index_ok()    { local t; t="$(curl -s -m 15 https://work.enterpriseos.bond/app/)"; echo "$t" | grep -q '<div id="root">' && echo "$t" | grep -Eq '/app/assets/index-[A-Za-z0-9_-]+\.js'; }
web_asset_ok()    { local js h; js="$(curl -s -m 15 https://work.enterpriseos.bond/app/ | grep -Eo '/app/assets/index-[A-Za-z0-9_-]+\.js' | head -1)"; [ -n "$js" ] && h="$(web_headers "https://work.enterpriseos.bond$js")" && echo "$h" | grep -q 'content-type: .*javascript' && echo "$h" | grep -q 'cache-control: .*immutable'; }
s_A8() {
  say ""; say "A8 · Giao diện web trên Internet: chưa đăng nhập thì API đóng, tiêu đề an toàn, các đường khác vẫn đóng"
  local base="https://work.enterpriseos.bond"
  check "gốc / chuyển sang /app/ (302)"                       [ "$(web_code -w '%{http_code} %{redirect_url}' $base/)" = "302 $base/app/" ]
  check "/app chuyển sang /app/ (308)"                        [ "$(web_code -w '%{http_code} %{redirect_url}' $base/app)" = "308 $base/app/" ]
  check "đường lạ trả 404"                                    [ "$(web_code $base/khong-co-trang-nay)" = 404 ]
  check "/app/healthz trả 200"                                [ "$(web_code $base/app/healthz)" = 200 ]
  check "/app/ trả giao diện (có #root và tệp JS có băm)"     web_index_ok
  check "tệp JS có băm: đúng kiểu, cache dài (immutable)"     web_asset_ok
  check "chưa đăng nhập: /app/api/me trả 401"                 [ "$(web_code $base/app/api/me)" = 401 ]
  check "chưa đăng nhập: gọi thao tác không có phiên trả 401" [ "$(web_code -X POST $base/app/api/rpc/app_tasks -H 'Content-Type: application/json' -H 'X-Requested-With: eos' -d '{}')" = 401 ]
  check "cookie phiên giả không qua được (401)"               [ "$(web_code $base/app/api/me -H 'Cookie: eos_s=giamao.giamao')" = 401 ]
  check "/app/api/config không lộ bí mật Google"              bash -c "! curl -s -m 15 $base/app/api/config | grep -Eiq 'secret|GOCSPX'"
  check "CSP chặt: script chỉ self, không eval"               web_csp_strict
  check "HSTS, nosniff, chống nhúng khung, API no-store"      web_hdr_basic
  check "không lộ X-Powered-By"                               web_no_powered
  check "/app/auth/callback không có state bị từ chối (303 về màn đăng nhập)" [ "$(web_code -w '%{http_code} %{redirect_url}' "$base/app/auth/callback?code=x&state=y")" = "303 $base/app/#/login?e=state" ]
  check "/app/api/join không có phiên Google chờ trả 401"     [ "$(web_code -X POST $base/app/api/join -H 'Content-Type: application/json' -H 'X-Requested-With: eos' -d '{"code":"ABCD2345"}')" = 401 ]
  check "không đọc được mã nguồn qua đường tĩnh"              bash -c "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --path-as-is $base/app/../src/config.mjs)\" != 200 ] && [ \"\$(curl -s -o /dev/null -w '%{http_code}' $base/app/src/config.mjs)\" != 200 ]"
  check "/mcp vẫn từ chối mã sai (401) sau khi thêm /app"     [ "$(web_code -X POST $base/mcp -H 'Authorization: Bearer eos_sai' -H 'Content-Type: application/json' -d '{}')" = 401 ]
  check "/api vẫn khóa theo IP (403)"                          [ "$(web_code -X POST $base/api/rpc/outbox_pull)" = 403 ]
}

runner_active()   { [ "$(systemctl --user is-active eos-z2-runner 2>/dev/null)" = active ]; }
q_mentions()      { sqlv "select string_agg(body, ' ') from work.comments where task_id=$1 and kind='question'" | grep -qiE "$2"; }
s_A9() {
  say ""; say "A9 · Runner Z2: nhận việc qua MCP (không qua Kanban), báo cáo, hỏi người khi gặp giai đoạn lạ"
  check "dịch vụ eos-z2-runner trên Z2 đang chạy"            runner_active
  local id; id="$(new_task "Việc thử runner (giai đoạn lạ)" "Không có phạm vi: runner phải chặn và hỏi, không làm gì." ho-so-runner)"
  check "tạo được việc giao cho runner"                      [ -n "$id" ]
  check "thẻ của runner (mã runner-…), không phải thẻ Hermes"  [ "$(sqlv "select count(*) from agent.cards where task_id=$id and card_id like 'runner-%'")" = 1 ]
  check "không có lệnh nào vào hộp thư đi (cầu nối Hermes)"  [ "$(sqlv "select count(*) from agent.outbox where task_id=$id")" = 0 ]
  check "runner nhận và chặn việc ≤ 2 phút"                  wait_until 120 is_status "$id" blocked
  check "câu hỏi nêu giai đoạn chưa hỗ trợ"                  q_mentions "$id" "chưa hỗ trợ"
  check "việc chờ người trả lời (waiting_on_human)"          [ "$(sqlv "select waiting_on_human from work.tasks where id=$id")" = t ]
  check "nhật ký ghi agent ho-so-runner nhận việc"           [ "$(sqlv "select count(*) from work.comments where task_id=$id and actor='agent:ho-so-runner'")" -ge 1 ]
}

for s in $ONLY; do "s_$s" || true; done
