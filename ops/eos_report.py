#!/usr/bin/env python3
"""eos_report — bản tin hằng ngày / tổng kết tuần của Enterprise OS cho cron của Hermes (thay báo cáo Ever Teams; docs/13).
Không dùng LLM: gọi công cụ MCP `eos_company_digest` bằng mã MCP chỉ-đọc, định dạng văn bản tiếng Việt, in ra stdout (Hermes cron gửi stdout qua Telegram).
Dùng:  eos_report.py daily | weekly       Biến: EOS_REPORT_TOKEN (bắt buộc), EOS_MCP_URL (mặc định https://work.enterpriseos.bond/mcp)
Lỗi: in một dòng cảnh báo rõ ràng (không lộ mã) và thoát 0 để cron vẫn gửi cảnh báo thay vì im lặng."""
import json, os, re, sys, urllib.request, urllib.error, datetime

APP = 'https://work.enterpriseos.bond/app/'


def digest(url, token, days):
    body = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'tools/call', 'params': {'name': 'eos_company_digest', 'arguments': {'days': days}}}).encode()
    req = urllib.request.Request(url, data=body, method='POST', headers={'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream', 'Authorization': f'Bearer {token}'})
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read().decode()
    if raw.lstrip().startswith(('event:', 'data:')):
        raw = next((l[5:].strip() for l in raw.splitlines() if l.startswith('data:')), '{}')
    msg = json.loads(raw)
    res = msg.get('result', {})
    text = (res.get('content') or [{}])[0].get('text', '')
    if res.get('isError') or 'error' in msg:
        raise RuntimeError((text or str(msg.get('error')))[:200])
    return json.loads(text)


def fmt_date(s):
    try:
        return datetime.date.fromisoformat(str(s)[:10]).strftime('%d/%m')
    except ValueError:
        return str(s)


def lines(items, fn, limit=8):
    out = [f' • {fn(i)}' for i in items[:limit]]
    if len(items) > limit:
        out.append(f' … và {len(items) - limit} việc nữa')
    return out


def render(d, weekly=False):
    c = d['counts']
    head = f"📊 Enterprise OS · {'Tổng kết tuần' if weekly else 'Bản tin sáng'} {fmt_date(d['date'])} · {d['scope']}"
    per = 'trong tuần' if weekly else 'hôm qua'
    out = [head, '',
           f"Công việc đang thực hiện {c['open']} · Quá hạn {c['overdue']} · Đến hạn hôm nay {c['due_today']} · 3 ngày tới {c['due_3d']}",
           f"Chờ bạn {c['ask_human'] + c['in_review']} (agent hỏi {c['ask_human']}, chờ duyệt {c['in_review']}) · Vướng {c['blocked']}",
           f"Xong {per}: {c['done_period']} · Mới tạo {per}: {c['created_period']}"]
    if d['overdue']:
        out += ['', '⚠ Quá hạn:'] + lines(d['overdue'], lambda i: f"{i['id']} {i['title']}" + (f" ({i['who']}, trễ {i['days_late']} ngày)" if i.get('who') else f" (chưa giao, trễ {i['days_late']} ngày)"))
    if d['due_today'] and not weekly:
        out += ['', '📅 Đến hạn hôm nay:'] + lines(d['due_today'], lambda i: f"{i['id']} {i['title']}" + (f" ({i['who']})" if i.get('who') else ''))
    if d['need_you']:
        out += ['', '🙋 Cần bạn xem:'] + lines(d['need_you'], lambda i: f"{i['id']} {i['title']} [{i['kind']}]")
    if d['done_period']:
        out += ['', f'✅ Đã xong {per}:'] + lines(d['done_period'], lambda i: f"{i['id']} {i['title']}" + (f" ({i['who']})" if i.get('who') else ''), 6 if not weekly else 10)
    if d['by_dept']:
        out += ['', '🏢 Theo phòng: ' + ' · '.join(f"{x['dept']} {x['open']} công việc, {x['overdue']} quá hạn" for x in d['by_dept'])]
    if weekly and d['by_person']:
        out += ['', '👥 Theo người: ' + ' · '.join(f"{x['who']} {x['open']} công việc, {x['overdue']} quá hạn" for x in d['by_person'][:6])]
    if d['projects']:
        out += ['', '📁 Dự án: ' + ' · '.join(f"{x['name']} {x['open']} công việc" + (f", {x['overdue']} quá hạn" if x['overdue'] else '') + (' (đang nạp hồ sơ)' if x.get('run') == 'running' else '') for x in d['projects'][:6])]
    a = d.get('agents')
    if a:
        flag = ' ⚠' if a['stuck_2h'] or a['blocked'] else ''
        out += ['', f"🤖 Agent: đang chạy {a['running']}, đang chờ người {a['blocked']}, kẹt >2 giờ {a['stuck_2h']}, lệnh chờ đẩy {a['outbox_pending']}{flag}"]
    out += ['', f'Truy cập: {APP}']
    return '\n'.join(out)[:3900]


def main(argv):
    mode = argv[0] if argv else 'daily'
    if mode not in ('daily', 'weekly'):
        print('Dùng: eos_report.py daily|weekly', file=sys.stderr)
        return 2
    token = os.environ.get('EOS_REPORT_TOKEN', '')
    if not re.match(r'^eos_[0-9a-f]{48}$', token):
        print('⚠ Bản tin Enterprise OS không gửi được: thiếu EOS_REPORT_TOKEN hợp lệ trong .env của profile.')
        return 0
    try:
        d = digest(os.environ.get('EOS_MCP_URL', 'https://work.enterpriseos.bond/mcp'), token, 7 if mode == 'weekly' else 1)
        print(render(d, mode == 'weekly'))
    except (urllib.error.URLError, OSError, RuntimeError, ValueError, KeyError) as e:
        msg = re.sub(r'(eos_[0-9a-f]{20,}|Bearer\s+\S+)', '[ẩn]', str(e))[:160]
        print(f'⚠ Bản tin Enterprise OS không lấy được dữ liệu ({type(e).__name__}: {msg}). Kiểm tra https://work.enterpriseos.bond/app/healthz và mã EOS_REPORT_TOKEN (còn hạn?).')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
