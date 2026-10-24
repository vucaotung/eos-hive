#!/usr/bin/env python3
"""Gỡ Ever Teams khỏi các profile Hermes (docs/13). Chạy TRÊN vps173:  python3 hermes_remove_everteams.py [--apply] [--eos-tools]
Mặc định chỉ IN những gì sẽ đổi (dry-run). --apply: sao lưu rồi sửa. --eos-tools: thêm MCP `enterprise-os` cho profile đã có EOS_MCP_TOKEN trong .env.
Việc làm cho mỗi profile (chỉ khi có): bỏ mcp_servers.everteams; bỏ plugin ever-teams-tasks; chuyển skill ever-teams*/ vào skill-backups/ (ngoài cây skills);
đổi văn bản Ever Teams trong persona (config.yaml của Mai/team_admin, SOUL.md của ks-kinh-te-xd) sang Enterprise OS. Không xóa tệp, không đụng .env/bí mật."""
import re, shutil, sys, time
from pathlib import Path

APPLY, EOS = '--apply' in sys.argv, '--eos-tools' in sys.argv
ROOT = Path('/root/.hermes/profiles'); TS = time.strftime('%Y%m%d-%H%M%S')
PROFILES = ['team_admin', 'ks-kinh-te-xd', 'ops-admin']
log = []

def say(p, m): log.append(f'[{p}] {m}'); print(f'[{p}] {m}')

def write(path, text, p):
    if APPLY:
        shutil.copy2(path, f'{path}.bak-everteams-{TS}'); path.write_text(text, encoding='utf-8')
    say(p, f'{"đã sửa" if APPLY else "sẽ sửa"} {path.name} (sao lưu .bak-everteams-{TS})')

MCP_EOS = "  enterprise-os:\n    url: https://work.enterpriseos.bond/mcp\n    headers:\n      Authorization: Bearer ${EOS_MCP_TOKEN}\n    timeout: 60\n    enabled: true\n"
MAI_NEW = '''      ## Hướng dẫn Enterprise OS
      Khi ai đó hỏi cách dùng Enterprise OS (nhận mã mời, đăng nhập, giao việc, duyệt, dự án, kết quả), tải skill enterprise-os-guide và làm theo đúng hướng dẫn trong đó: hướng dẫn từng bước, mỗi tin 1-3 bước, hỏi lại người dùng đã thấy màn hình chưa, không nhận mật khẩu hay mã mời trong chat. Hệ thống không cho tự đăng ký: ai chưa có tài khoản thì nhắn anh Tùng kèm email Google để được mời.

      ## Chi tiết Enterprise OS (thao tác thực tế)
      Web: work.enterpriseos.bond/app (Ever Teams đã gỡ, không còn dùng). Giao diện tiếng Việt.
      - Vào hệ thống: bằng mã mời 8 ký tự hoặc link mời do quản trị gửi, rồi bấm "Đăng nhập với Google".
      - Việc, dự án, duyệt, kết quả: tải skill enterprise-os-guide. Xem hoặc tạo việc bằng công cụ eos_* theo đúng quy tắc trong skill (xác nhận trước khi giao việc cho người khác).
      - Không bao giờ nhận hoặc giữ hộ mật khẩu, mã mời, mã MCP của ai trong chat.
'''

def patch_config(p, cfg):
    t = cfg.read_text(encoding='utf-8'); o = t
    m = re.search(r'^  everteams:\n(?:    .*\n|\n)*', t, re.M)
    if m: t = t.replace(m.group(0), ''); say(p, 'bỏ mcp_servers.everteams')
    if re.search(r'^    - ever-teams-tasks\n', t, re.M): t = re.sub(r'^    - ever-teams-tasks\n', '', t, flags=re.M); say(p, 'bỏ plugin ever-teams-tasks')
    if EOS and 'enterprise-os:' not in t and 'EOS_MCP_TOKEN=' in (cfg.parent / '.env').read_text(encoding='utf-8'):
        m2 = re.search(r'^mcp_servers:\n', t, re.M)
        if m2: t = t[:m2.end()] + MCP_EOS + t[m2.end():]; say(p, 'thêm mcp_servers.enterprise-os (token trong .env)')
    a = t.find('      ## Hướng dẫn Ever Teams')
    b = t.find('      - Chủ đề khác (task, dự án, team, kế hoạch ngày, lỗi thường gặp): tải skill ever-teams-guide và làm theo.\n')
    if a != -1 and b != -1:
        t = t[:a] + MAI_NEW + t[b + len('      - Chủ đề khác (task, dự án, team, kế hoạch ngày, lỗi thường gặp): tải skill ever-teams-guide và làm theo.\n'):]
        t = t.replace('hướng dẫn dùng Ever Teams, xem công việc của team, chỉ cách tạo hoặc cập nhật việc qua bot Telegram Staff Work', 'hướng dẫn dùng Enterprise OS, xem và giao việc trên Enterprise OS, bản tin công việc hằng ngày')
        say(p, 'viết lại phần Ever Teams trong persona (Mai) sang Enterprise OS')
    if t != o: write(cfg, t, p)

def patch_soul(p, soul):
    t = soul.read_text(encoding='utf-8'); o = t
    rep = [
        ('thì tạo task trên **Ever Teams**.', 'thì tạo task trên **Enterprise OS** (công cụ `eos_task_save`).'),
        ('"everteams_task_id": "<nếu đã có>"', '"eos_task_id": "<nếu đã có, dạng T-123>"'),
        ('gắn hoặc tạo task Ever Teams ở trạng thái `In progress`.', 'gắn hoặc tạo task Enterprise OS ở trạng thái `in_progress` (`eos_task_save`).'),
        ('1. Nhận việc. ACK. Gắn task Ever Teams.', '1. Nhận việc. ACK. Gắn task Enterprise OS.'),
        ('không gọi Ever Teams', 'không gọi Enterprise OS'),
        ('tạo task Ever giao cho người', 'tạo task Enterprise OS giao cho người'),
        ('Ever (luồng F8)', 'Enterprise OS (luồng F8)'),
        ('(Ever Teams nếu có tool, không thì kanban giao `team_admin`)', '(Enterprise OS qua `eos_task_save` nếu có tool, không thì kanban giao `team_admin`)'),
        ('không gọi Ever Teams"', 'không gọi Enterprise OS"'),
    ]
    for a, b in rep:
        if a in t: t = t.replace(a, b)
    m = re.search(r'^\*\*Tạo/cập nhật task Ever Teams.*\n', t, re.M)
    if m:
        t = t.replace(m.group(0), "**Tạo/cập nhật task Enterprise OS (công cụ có sẵn, dùng luôn):** `eos_task_save(title, description, assignee_email, project, priority, due_date, approval)` để tạo; `eos_task_save(id=\"T-123\", status | due_date | ...)` để sửa. Việc cần người duyệt kết quả: `approval: true`. Tra email người nhận bằng `eos_list_members`; hỏi lại khi mơ hồ. Không có công cụ duyệt hay xóa cho bot.\n")
    if t != o: write(soul, t, p)
    left = len(re.findall(r'ever[ _-]?teams|everteams', t, re.I))
    if left: say(p, f'⚠ còn {left} chỗ nhắc Ever Teams trong {soul.name}, cần xem tay')

for p in PROFILES:
    d = ROOT / p
    if not d.exists(): continue
    if (d / 'config.yaml').exists(): patch_config(p, d / 'config.yaml')
    if p == 'ks-kinh-te-xd' and (d / 'SOUL.md').exists(): patch_soul(p, d / 'SOUL.md')
    for sk in list((d / 'skills').rglob('ever-teams*')):
        if sk.is_dir() and '.bak' not in sk.name:
            dst = d / 'skill-backups' / f'{sk.name}-{TS}'
            if APPLY: dst.parent.mkdir(exist_ok=True); shutil.move(str(sk), str(dst))
            say(p, f'{"chuyển" if APPLY else "sẽ chuyển"} skill {sk.name} vào skill-backups/')
print('XONG' if APPLY else 'DRY-RUN (thêm --apply để sửa)')
