#!/usr/bin/env bash
# Kiểm toán bảo mật theo "Danh sách kiểm tra trước khi cho người dùng thật vào" (docs/06). Chỉ ĐỌC, không sửa gì.
#   scripts/security_audit.sh        (make audit)
# Ký hiệu: ✔ đạt · ✘ hỏng · ⚠ cảnh báo (nên xử lý) · ◌ đã chấp nhận (scripts/security_accepted.txt). Thoát 1 nếu có ✘.
# Không in bí mật: chỉ quyền tệp, tên khóa, ngày hết hạn, mã HTTP.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB_HOST="${EOS_DB_HOST:-vps169}"; H_HOST="${EOS_HERMES_HOST:-vps173}"
H_IP="${EOS_HERMES_IP:-173.249.51.69}"; DB_IP="${EOS_DB_IP:-169.58.107.168}"
T="$(mktemp -d)"; chmod 700 "$T"; trap 'ssh -O exit "${SSHO[@]}" "$DB_HOST" >/dev/null 2>&1; ssh -O exit "${SSHO[@]}" "$H_HOST" >/dev/null 2>&1; rm -rf "$T"' EXIT
SSHO=(-o BatchMode=yes -o ConnectTimeout=15 -o ControlMaster=auto -o "ControlPath=$T/cm-%C" -o ControlPersist=120)
OK=0; BAD=0; WARN=0; ACC=0
accepted() { grep -E "^$1\|" "$ROOT/scripts/security_accepted.txt" 2>/dev/null | head -1; }
ok()   { OK=$((OK+1));   echo "  ✔ $1"; }
bad()  { BAD=$((BAD+1)); echo "  ✘ $1"; }
warn() { WARN=$((WARN+1)); echo "  ⚠ $1"; }
risk() {   # risk <mã-rủi-ro> "mô tả khi hỏng" — nếu đã chấp nhận thì ◌, ngược lại ✘
  local a; a="$(accepted "$1")"
  if [ -n "$a" ]; then ACC=$((ACC+1)); echo "  ◌ $2 — đã chấp nhận ($(echo "$a" | cut -d'|' -f2,3 | tr '|' ' '))"; else bad "$2"; fi
}
sq()  { ssh "${SSHO[@]}" "$DB_HOST" 'docker exec -i eos-postgres psql -U postgres -X -q -At -d eos' <<<"$1"; }
rh()  { ssh "${SSHO[@]}" "$H_HOST" "$@"; }
rd()  { ssh "${SSHO[@]}" "$DB_HOST" "$@"; }
closed() { ! timeout 6 bash -c "exec 3<>/dev/tcp/$1/$2" 2>/dev/null; }

echo "# Kiểm toán bảo mật — $(date '+%F %T')"
echo; echo "1. Mã nguồn và bí mật"
"$ROOT/scripts/check_secrets.sh" >/dev/null 2>&1 && ok "check_secrets sạch" || bad "check_secrets phát hiện bí mật"
if command -v gh >/dev/null 2>&1 && [ "$(PATH=$HOME/.local/bin:$PATH gh repo view vucaotung/eos-hive --json visibility -q .visibility 2>/dev/null)" = PRIVATE ]; then ok "repo GitHub là PRIVATE"; else warn "không xác nhận được repo PRIVATE (gh chưa đăng nhập?)"; fi
[ "$(grep -rEl 'eos_[0-9a-f]{48}|eyJ[A-Za-z0-9_-]{20,}' "$ROOT/ops-log" "$ROOT/docs" "$ROOT/bridge" "$ROOT/deploy" 2>/dev/null | wc -l)" = 0 ] && ok "không mã eos_/JWT trong ops-log, docs, bridge, deploy" || bad "có mã/JWT nằm trong tệp"

echo; echo "2. Quyền tệp bí mật (kỳ vọng 600, hoặc 640 root:eos)"
bad_perm=0
while read -r perm own f; do
  case "$f" in /etc/eos/db_roles.env|/etc/eos/postgrest.conf) [ "$perm $own" = "640 root:eos" ] || { bad_perm=1; echo "     lệch: $perm $own $f"; };;
                *) [ "$perm" = 600 ] || { bad_perm=1; echo "     lệch: $perm $own $f"; };; esac
done < <(rd 'stat -c "%a %U:%G %n" /etc/eos/* /opt/apps/enterprise-os/mcp/.env /root/.deo_backup_pass 2>/dev/null')
[ "$bad_perm" = 0 ] && ok "vps169: /etc/eos/*, mcp/.env, mật khẩu sao lưu đúng quyền" || bad "vps169: có tệp bí mật sai quyền"
bp2=0; while read -r perm own f; do [ "$perm" = 600 ] || { bp2=1; echo "     lệch: $perm $own $f"; }; done < <(rh 'stat -c "%a %U %n" /root/.hermes/eos_bridge/.env /root/.hermes/profiles/eos-*/.env /root/.hermes/profiles/eos-*/config.yaml 2>/dev/null')
[ "$bp2" = 0 ] && ok "vps173: .env và config.yaml của cầu nối và 4 profile eos-* đều 600" || bad "vps173: có tệp sai quyền"
bp3=0; for f in ~/.config/eos-hive/*.env; do [ -e "$f" ] || continue; [ "$(stat -c %a "$f")" = 600 ] || { bp3=1; echo "     lệch: $f"; }; done
[ "$bp3" = 0 ] && ok "Z2: ~/.config/eos-hive/*.env đều 600" || bad "Z2: tệp bí mật sai quyền"

echo; echo "3. Bề mặt mạng"
ext169="$(rd 'ss -ltnH | awk "{print \$4}" | grep -E "^(0\.0\.0\.0|\*|\[::\]):" | sed -E "s/.*://" | sort -un | tr "\n" " "')"
[ "$ext169" = "22 80 443 " ] && ok "vps169 chỉ nghe ra ngoài ở 22/80/443" || bad "vps169 nghe ra ngoài ở cổng lạ: $ext169"
for p in 5434 3200 8790 3000; do closed "$DB_IP" "$p" || bad "vps169:$p mở từ ngoài"; done; ok "vps169: 5434/3200/8790/3000 không vào được từ ngoài"
for p in 8644 8646 9119 20128; do closed "$H_IP" "$p" || bad "vps173:$p mở từ ngoài"; done; ok "vps173: 8644/8646/9119/20128 không vào được từ ngoài"
[ "$(rh 'ufw status | head -1')" = "Status: active" ] && ok "UFW vps173 đang bật" || bad "UFW vps173 tắt"
[ "$(rd 'ufw status | head -1')" = "Status: active" ] && ok "UFW vps169 đang bật" || risk ufw_vps169 "UFW vps169 tắt"
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST https://work.enterpriseos.bond/api/rpc/outbox_pull)"; [ "$code" = 403 ] && ok "/api từ IP lạ → 403" || bad "/api từ IP lạ trả $code (kỳ vọng 403)"
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST https://work.enterpriseos.bond/mcp -H 'Authorization: Bearer eos_sai' -H 'Content-Type: application/json' -d '{}')"; [ "$code" = 401 ] && ok "/mcp với mã sai → 401" || bad "/mcp mã sai trả $code"
[ "$(rd 'grep -c "^MCP_RATE_PER_MIN=" /opt/apps/enterprise-os/mcp/.env')" = 1 ] && ok "giới hạn tốc độ MCP ở tầng ứng dụng đã đặt" || bad "thiếu MCP_RATE_PER_MIN"
[ "$(rd 'caddy list-modules 2>/dev/null | grep -c rate_limit')" -ge 1 ] && ok "Caddy có module giới hạn tốc độ" || warn "Caddy vps169 không có module rate_limit (chỉ có giới hạn ở tầng MCP; /api đã khóa theo IP)"

echo; echo "4. Truy cập SSH"
for h in "$DB_HOST" "$H_HOST"; do
  [ "$(ssh "${SSHO[@]}" "$h" 'sshd -T 2>/dev/null | grep -c "^passwordauthentication no"')" = 1 ] && ok "$h: tắt đăng nhập mật khẩu" || risk ssh_password "$h: đăng nhập bằng mật khẩu còn bật"
done

echo; echo "5. Sao lưu"
age169="$(rd 'echo $(( ( $(date +%s) - $(stat -c %Y $(ls -1t /var/backups/deo/deo169-*.tar.gpg | head -1)) ) / 3600 ))')"
[ "${age169:-999}" -le 36 ] && ok "bản sao lưu mới nhất trên vps169 cách ${age169} giờ" || bad "bản sao lưu vps169 đã ${age169} giờ"
newest="$(ls -1t ~/backups/deo169/deo169-*.tar.gpg 2>/dev/null | head -1)"
if [ -n "$newest" ]; then ageZ=$(( ( $(date +%s) - $(stat -c %Y "$newest") ) / 3600 )); [ "$ageZ" -le 48 ] && ok "bản sao lưu mới nhất trên Z2 cách ${ageZ} giờ" || bad "bản sao lưu trên Z2 đã ${ageZ} giờ (cron kéo hỏng?)"; else bad "Z2 không có bản sao lưu"; fi
tail -1 ~/backups/pull.log 2>/dev/null | grep -q " OK " && ok "lần kéo sao lưu gần nhất trên Z2 báo OK" || warn "dòng cuối ~/backups/pull.log không phải OK"
rd 'grep -q "eos-postgres" /opt/backup/backup.sh' && ok "backup.sh có dump CSDL eos" || bad "backup.sh không dump CSDL eos"

echo; echo "6. Mã và hạn dùng"
over="$(sq "select count(*) from agent.mcp_tokens where revoked_at is null and expires_at > now() + interval '91 days'")"
[ "$over" = 0 ] && ok "không mã MCP nào còn hạn > 90 ngày" || bad "$over mã MCP có hạn > 90 ngày"
min_days="$(sq "select coalesce(min(extract(day from expires_at - now())::int), 999) from agent.mcp_tokens where revoked_at is null and agent_id is not null")"
if [ "${min_days:-0}" -le 0 ]; then bad "có mã agent đã hết hạn"; elif [ "$min_days" -le 14 ]; then warn "mã agent gần hết hạn nhất còn $min_days ngày — cấp lại (docs/03 §3.5)"; else ok "mã agent gần hết hạn nhất còn $min_days ngày"; fi
exp="$(rh "python3 - <<'PY'
import base64, json, re, time
t = ''
for l in open('/root/.hermes/eos_bridge/.env'):
    if l.startswith('EOS_BRIDGE_TOKEN='): t = l.strip().split('=', 1)[1]
p = t.split('.')[1]; p += '=' * (-len(p) % 4)
print(int((json.loads(base64.urlsafe_b64decode(p))['exp'] - time.time()) // 86400))
PY")"
if [ "${exp:-0}" -le 0 ] 2>/dev/null; then bad "JWT cầu nối đã hết hạn"; elif [ "$exp" -le 14 ]; then warn "JWT cầu nối còn $exp ngày — cấp lại (docs/03 §3.2)"; else ok "JWT cầu nối còn $exp ngày"; fi
live_person="$(sq "select count(*) from agent.mcp_tokens t join core.users u on u.id=t.user_id where t.revoked_at is null and t.expires_at > now() and u.kind='person'")"
[ "$live_person" = 0 ] && ok "không còn mã MCP thử của người dùng" || warn "$live_person mã MCP của người dùng đang còn hạn (kiểm tra có phải mã thử bỏ quên không)"
[ "$(sq "select count(*) from agent.company_agents where auto_done")" = 0 ] && ok "auto_done tắt cho mọi agent" || bad "có agent bật auto_done"

[ "$(sq "select count(*) from agent.mcp_tokens t join agent.agents a on a.id=t.agent_id where a.executor='runner' and t.revoked_at is null and t.scopes <> '{runner}'")" = 0 ] && ok "mã của runner chỉ có phạm vi runner" || bad "mã runner có phạm vi thừa"
[ "$(sq "select count(*) from agent.mcp_tokens where agent_id is null and scopes && array['project','runner','delegate','draft']")" = 0 ] && ok "mã của người không có phạm vi project/runner/delegate/draft" || bad "mã của người có phạm vi dành riêng cho agent"
echo; echo "7. Agent Hermes (profile eos-*)"
res="$(rh "python3 - <<'PY'
import glob, yaml
bad = []
for f in sorted(glob.glob('/root/.hermes/profiles/eos-*/config.yaml')):
    d = yaml.safe_load(open(f)); n = f.split('/')[-2]
    en = set((d.get('platform_toolsets') or {}).get('cli') or [])
    danger = en & {'terminal', 'file', 'code_execution', 'browser', 'web', 'computer_use', 'cronjob', 'delegation'}
    if danger: bad.append(n + ': bật ' + ','.join(sorted(danger)))
    if (d.get('approvals') or {}).get('mode') != 'manual': bad.append(n + ': approvals không phải manual')
    if d.get('platforms'): bad.append(n + ': có nền tảng chat')
print('; '.join(bad) if bad else 'OK')
PY")"
[ "$res" = OK ] && ok "4 profile eos-*: không terminal/file/web/chạy mã, approval manual, không nền tảng chat" || bad "profile eos-*: $res"
[ "$(sq "select count(*) from agent.agents where executor = 'hermes' and hermes_profile not like 'eos-%'")" = 0 ] && ok "không agent Hermes nào ánh xạ vào profile ngoài eos-* (ví dụ ops-admin); runner Z2 không dùng Hermes" || bad "có agent ánh xạ vào profile không phải eos-*"

echo; echo "8. Dữ liệu"
yr="$(date +%Y)"; mo="$(date +%m)"
need=$yr; [ "$mo" -ge 10 ] && need=$((yr+1))
[ "$(sq "select count(*) from pg_class where relname='audit_log_$need'")" = 1 ] && ok "phân vùng nhật ký audit_log_$need đã có" || bad "thiếu phân vùng audit_log_$need (docs/03 §4.1)"

echo; echo "9. Giao diện web (/app) và quyền hàm CSDL"
[ "$(rd 'systemctl is-active eos-web 2>/dev/null')" = active ] && ok "dịch vụ eos-web đang chạy" || bad "eos-web không chạy"
[ "$(curl -s -o /dev/null -w '%{http_code}' https://work.enterpriseos.bond/app/healthz)" = 200 ] && ok "/app/healthz qua HTTPS trả 200" || bad "/app/healthz không trả 200"
hdr="$(curl -s -D - -o /dev/null https://work.enterpriseos.bond/app/api/me | tr -d '\r' | tr 'A-Z' 'a-z')"
csp="$(curl -s -D - -o /dev/null https://work.enterpriseos.bond/app/ | tr -d '\r' | tr 'A-Z' 'a-z' | grep '^content-security-policy:')"
{ echo "$csp" | grep -q "default-src 'none'" && echo "$csp" | grep -q "script-src 'self'" && ! echo "$csp" | grep -Eq "script-src[^;]*unsafe|unsafe-eval"; } && ok "/app/ có CSP chặt (script chỉ self, không eval)" || bad "thiếu CSP chặt ở /app/"
echo "$csp" | grep -q "style-src[^;]*unsafe-inline" && warn "style-src có 'unsafe-inline' (thư viện giao diện đặt style theo phần tử; chỉ ảnh hưởng kiểu dáng, không thực thi mã; docs/10 §Bảo mật)" || ok "style-src không cần unsafe-inline"
echo "$hdr" | grep -q "^x-frame-options: deny" && echo "$hdr" | grep -q "^cache-control: no-store" && ok "chống nhúng khung; API không lưu đệm" || bad "thiếu X-Frame-Options hoặc no-store ở API"
webopen=0; for p in /app/api/me; do [ "$(curl -s -o /dev/null -w '%{http_code}' https://work.enterpriseos.bond$p)" = 401 ] || webopen=1; done
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -H 'X-Requested-With: eos' -d '{}' https://work.enterpriseos.bond/app/api/rpc/app_tasks)" = 401 ] || webopen=1
[ "$webopen" = 0 ] && ok "chưa đăng nhập: API web trả 401, không trả dữ liệu" || bad "API web trả nội dung khi chưa đăng nhập"
closed "$DB_IP" 8791 && ok "cổng 8791 của web không vào được từ ngoài" || bad "cổng 8791 mở ra ngoài"
[ "$(rd 'stat -c "%a %U" /opt/apps/enterprise-os/web/.env 2>/dev/null')" = "600 eos" ] && ok "web/.env quyền 600, chủ eos" || bad "web/.env sai quyền"
[ "$(rd 'grep -c "^GOOGLE_LOGIN_CLIENT_ID=.\+" /opt/apps/enterprise-os/web/.env')" = 1 ] && ok "đăng nhập Google đã cấu hình" || warn "đăng nhập Google chưa cấu hình (chưa ai vào được web)"
[ "$(sq "select count(*) from pg_roles where rolname='eos_web' and (rolsuper or rolcreatedb or rolcreaterole or rolreplication or rolbypassrls)")" = 0 ] && ok "eos_web không có quyền đặc biệt" || bad "eos_web có quyền đặc biệt"
[ "$(sq "select string_agg(r.rolname, ',' order by r.rolname) from pg_auth_members m join pg_roles r on r.oid=m.roleid join pg_roles u on u.oid=m.member where u.rolname='eos_web'")" = web_svc ] && ok "eos_web chỉ thuộc vai trò web_svc" || bad "eos_web thuộc vai trò khác"
[ "$(sq "select count(*) from information_schema.role_table_grants where grantee='web_svc'")" = 0 ] && ok "web_svc không có quyền trên bảng nào (chỉ gọi hàm)" || bad "web_svc có quyền bảng"
[ "$(sq "select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='agent' and p.prokind='f' and has_function_privilege('public', p.oid, 'EXECUTE')")" = 0 ] && ok "không hàm nào trong schema agent cho PUBLIC chạy" || bad "có hàm schema agent cho PUBLIC chạy"
[ "$(sq "select string_agg(p.proname, ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='agent' and p.prokind='f' and has_function_privilege('agent_bridge', p.oid, 'EXECUTE')")" = "ingest_event,outbox_ack,outbox_pull,request_confirmation" ] && ok "cầu nối (agent_bridge) chỉ gọi 4 hàm" || bad "agent_bridge gọi được hàm ngoài 4 hàm"
echo; echo "KẾT QUẢ: ✔ $OK đạt · ✘ $BAD hỏng · ⚠ $WARN cảnh báo · ◌ $ACC đã chấp nhận"
[ "$BAD" = 0 ]
