#!/usr/bin/env python3
"""eos_z2_runner — dịch vụ trên Z2 nhận việc "xử lý hồ sơ dự án" từ Enterprise OS (docs/12).

Runner là một agent kiểu `runner` (không phải Hermes): nó dùng MÃ MCP riêng (phạm vi `runner`) để
  eos_runner_claim   nhận thẻ sẵn sàng cũ nhất (kèm kỹ năng, phạm vi, thư mục nguồn)
  eos_runner_report  báo heartbeat / hỏi người (blocked) / xong (completed) / lỗi (crashed)
  eos_runner_setup   đăng ký thư mục Markdown, tệp, mã kho tri thức vào CSDL
và chạy pipeline có sẵn của Z2 (~/work/deo-sync: fetch_drive.sh, run_project.sh) cho các giai đoạn:
  fetch_convert  tải thư mục nguồn → Markdown + OCR + mục lục → đẩy Markdown lên Drive (thư mục _md_deo) → đăng ký tệp
  kb_ingest      nạp kho tri thức WeKnora: HIỆN LÀ THAO TÁC CÓ NGƯỜI (DEO-INGEST-RULE): runner chuẩn bị thư mục upload rồi hỏi người,
                 nhận lại mã KB người trả lời (dạng kb:<mã>) và ghi vào CSDL.
Không có bí mật trong mã: mã MCP đọc từ biến môi trường / tệp env (quyền 600). Lệnh ngoài chạy bằng danh sách đối số, không qua shell.
"""
import json, os, re, signal, subprocess, sys, time, traceback, urllib.request, urllib.error
from pathlib import Path

SAFE_ID = re.compile(r'^[A-Za-z0-9_-]{10,}$')
SLUG = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*$')
KB_ANSWER = re.compile(r'\bkb:([A-Za-z0-9_-]{8,64})\b', re.I)
MD_SUBDIR = '_md_deo'


class McpError(Exception):
    pass


class Mcp:
    """Máy khách MCP tối giản: máy chủ chạy không giữ phiên (stateless Streamable HTTP, trả JSON)."""
    def __init__(self, url, token, timeout=120):
        self.url, self.token, self.timeout, self.n = url, token, timeout, 0

    def call(self, name, args=None):
        self.n += 1
        body = json.dumps({'jsonrpc': '2.0', 'id': self.n, 'method': 'tools/call', 'params': {'name': name, 'arguments': args or {}}}).encode()
        req = urllib.request.Request(self.url, data=body, method='POST', headers={
            'Content-Type': 'application/json', 'Accept': 'application/json, text/event-stream', 'Authorization': f'Bearer {self.token}'})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as r:
                raw = r.read().decode()
        except urllib.error.HTTPError as e:
            raise McpError(f'HTTP {e.code} khi gọi {name}')
        except OSError as e:
            raise McpError(f'Không kết nối được MCP: {e}')
        if raw.lstrip().startswith('event:') or raw.lstrip().startswith('data:'):
            raw = next((l[5:].strip() for l in raw.splitlines() if l.startswith('data:')), '{}')
        msg = json.loads(raw)
        if 'error' in msg:
            raise McpError(msg['error'].get('message', 'lỗi MCP'))
        res = msg.get('result', {})
        text = (res.get('content') or [{}])[0].get('text', '')
        if res.get('isError'):
            raise McpError(text[:400])
        try:
            return json.loads(text)
        except ValueError:
            return text


def run_cmd(argv, timeout=6 * 3600, cwd=None):
    """Chạy lệnh bằng danh sách đối số; trả (mã thoát, đầu ra gộp). Không dùng shell."""
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, cwd=cwd)
    return p.returncode, (p.stdout or '') + (p.stderr or '')


def scrub(text, limit=500):
    """Rút gọn lỗi để báo lên CSDL: bỏ mã/khóa trông giống bí mật, giữ vài dòng cuối."""
    t = re.sub(r'(eos_[0-9a-f]{20,}|ya29\.[\w-]+|eyJ[\w-]{20,}\.[\w.-]+|Bearer\s+\S+)', '[ẩn]', text or '')
    return t.strip()[-limit:]


class Runner:
    def __init__(self, mcp, home=None, deo_sync=None, remote='gdrive', sh=run_cmd, log=print):
        self.mcp, self.sh, self.log, self.remote = mcp, sh, log, remote
        self.home = Path(home or os.path.expanduser('~'))
        self.deo = Path(deo_sync or self.home / 'work' / 'deo-sync')
        self.seq = {}

    # ---------- khung chung ----------
    def key(self, card, event):
        self.seq[(card, event)] = self.seq.get((card, event), 0) + 1
        return f'{card}-{event}-{int(time.time())}-{self.seq[(card, event)]}'

    def report(self, card, event, payload=None):
        return self.mcp.call('eos_runner_report', {'card': card, 'event': event, 'key': self.key(card, event), 'payload': payload or {}})

    def beat(self, card, pct, note):
        self.log(f'[{card}] {pct}% {note}')
        try:
            self.report(card, 'heartbeat', {'progress': pct})
            self.report(card, 'comment', {'body': note})
        except McpError as e:
            self.log(f'[{card}] không báo được tiến độ: {e}')

    def once(self):
        """Nhận và xử lý đúng một việc. True nếu có việc."""
        job = self.mcp.call('eos_runner_claim')
        if not isinstance(job, dict) or job.get('idle'):
            return False
        card, stage = job['card'], (job.get('scope') or {}).get('stage')
        self.log(f"[{card}] nhận T-{job['task']['id']} giai đoạn {stage}")
        try:
            fn = {'fetch_convert': self.fetch_convert, 'kb_ingest': self.kb_ingest}.get(stage)
            if fn is None:
                self.report(card, 'blocked', {'reason': f'Runner chưa hỗ trợ giai đoạn "{stage}". Cần người xem phạm vi của việc này.'})
            else:
                fn(job)
        except McpError as e:
            self.log(f'[{card}] lỗi MCP: {e}')
            self.report(card, 'crashed', {'reason': f'Lỗi gọi Enterprise OS: {scrub(str(e))}'})
        except Exception as e:  # noqa: BLE001 — mọi lỗi đều phải báo lên, không để thẻ treo
            self.log(traceback.format_exc())
            self.report(card, 'crashed', {'reason': scrub(f'{type(e).__name__}: {e}')})
        return True

    def need(self, job):
        run = job.get('run') or {}
        slug, src = run.get('project'), run.get('drive_folder_id')
        if not slug or not SLUG.match(slug) or not src or not SAFE_ID.match(src):
            raise ValueError('Thiếu hoặc sai tên dự án/thư mục nguồn trong lần chạy')
        return slug, src

    def step(self, argv, what, **kw):
        code, out = self.sh(argv, **kw)
        if code != 0:
            raise RuntimeError(f'{what} thất bại (mã {code}): {scrub(out)}')
        return out

    # ---------- giai đoạn 1: tải, chuyển Markdown, đẩy lên Drive, đăng ký ----------
    def fetch_convert(self, job):
        card, task = job['card'], job['task']['id']
        slug, src = self.need(job)
        self.beat(card, 5, f'Tải thư mục nguồn của dự án {slug} về Z2')
        self.step(['bash', str(self.deo / 'fetch_drive.sh'), slug, src], 'Tải Drive')
        self.beat(card, 35, 'Chuyển Markdown, OCR trang scan, dựng mục lục')
        self.step(['bash', str(self.deo / 'run_project.sh'), slug], 'Chuyển Markdown')
        md = self.home / 'work' / 'md' / slug
        total = ok = ocr = err = 0
        toc = md / '00_MUC_LUC.md'
        if toc.exists():
            m = re.search(r'Tổng (\d+) file: (\d+) đã có Markdown, (\d+) file có trang cần soát OCR, (\d+) lỗi', toc.read_text(encoding='utf-8')[:2000])
            if m:
                total, ok, ocr, err = map(int, m.groups())
        self.beat(card, 65, 'Đẩy Markdown lên Drive (thư mục _md_deo trong thư mục nguồn)')
        root = ['--drive-root-folder-id', src]
        self.step(['rclone', 'copy', str(md), f'{self.remote}:{MD_SUBDIR}', *root, '--transfers', '2'], 'Đẩy Markdown lên Drive')
        folders = json.loads(self.step(['rclone', 'lsjson', f'{self.remote}:', *root, '--dirs-only'], 'Liệt kê thư mục Drive'))
        md_id = next((f['ID'] for f in folders if f.get('Name') == MD_SUBDIR), None)
        if not md_id:
            raise RuntimeError('Không tìm thấy thư mục _md_deo sau khi đẩy lên (kiểm tra quyền chỉnh sửa của tài khoản rclone trên thư mục nguồn)')
        files = json.loads(self.step(['rclone', 'lsjson', '-R', f'{self.remote}:{MD_SUBDIR}', *root, '--files-only'], 'Liệt kê tệp Markdown'))
        reg = [{'drive_id': f['ID'], 'name': f.get('Path') or f['Name'], 'mime': f.get('MimeType') or 'text/markdown', 'bytes': f.get('Size'),
                'url': f"https://drive.google.com/file/d/{f['ID']}/view"} for f in files if f.get('ID')]
        self.mcp.call('eos_runner_setup', {'task': task, 'md_folder_id': md_id})
        for i in range(0, len(reg), 200):
            self.mcp.call('eos_runner_setup', {'task': task, 'files': reg[i:i + 200]})
        summary = (f'Đã xử lý hồ sơ dự án {slug}: {total} tệp nguồn, {ok} có Markdown, {err} lỗi, {ocr} tệp có trang cần soát OCR. '
                   f'Đã đẩy {len(reg)} tệp lên thư mục Markdown của dự án (_md_deo) và đăng ký vào kho dữ liệu; các agent đọc qua eos_project_files.')
        self.report(card, 'completed', {'summary': summary, 'confidence': 'cao' if err == 0 else 'trung bình',
                    'residual_risk': f'{ocr} tệp có trang scan cần soát tay; {err} tệp lỗi' if (ocr or err) else 'thấp',
                    'checks': [f'mục lục: {total} tệp', f'đăng ký: {len(reg)} tệp']})

    # ---------- giai đoạn 5: nạp kho tri thức (có người) ----------
    def kb_ingest(self, job):
        card, task = job['card'], job['task']['id']
        slug, _ = self.need(job)
        m = KB_ANSWER.search(job.get('feedback') or '')
        if m:
            self.mcp.call('eos_runner_setup', {'task': task, 'weknora_kb_id': m.group(1)})
            self.report(card, 'completed', {'summary': f'Đã ghi mã kho tri thức WeKnora {m.group(1)} cho dự án {slug}. Nguồn từng tài liệu chưa được đăng ký tự động (cần API WeKnora); người nạp đối chiếu tại kb.enterpriseos.bond.',
                        'confidence': 'trung bình', 'residual_risk': 'nguồn từng tài liệu trong kho chưa đăng ký ở CSDL', 'next_actions': 'đăng ký nguồn khi có API WeKnora'})
            return
        up = self.home / 'work' / 'upload' / slug
        n = len(list(up.glob('*.md'))) if up.exists() else 0
        if n == 0:
            self.report(card, 'blocked', {'reason': f'Thư mục upload ~/work/upload/{slug} chưa có tệp (giai đoạn xử lý hồ sơ chưa chạy hoặc không có tệp nạp được). Cần người kiểm tra.'})
            return
        self.report(card, 'blocked', {'reason': (
            f'Sẵn sàng nạp kho tri thức: {n} tệp Markdown trong ~/work/upload/{slug} trên Z2 (đã bỏ mục lục, tệp loại trừ). '
            'Người có quyền tạo KB trên kb.enterpriseos.bond (embedding text-embedding-3-small), tải thư mục này lên, rồi TRẢ LỜI việc này bằng mã KB theo dạng: kb:<mã KB>. '
            'Runner sẽ ghi mã vào hệ thống. (Quy tắc DEO-INGEST-RULE: nạp kho tri thức do người thực hiện.)')})


def load_env(path):
    out = {}
    p = Path(path).expanduser()
    if p.exists():
        for line in p.read_text().splitlines():
            if '=' in line and not line.lstrip().startswith('#'):
                k, v = line.split('=', 1)
                out[k.strip()] = v.strip().strip('"\'')
    return out


def main(argv):
    env = {**load_env(os.environ.get('EOS_RUNNER_ENV', '~/.config/eos-hive/runner.env')), **os.environ}
    url, token = env.get('EOS_MCP_URL', 'https://work.enterpriseos.bond/mcp'), env.get('EOS_RUNNER_TOKEN', '')
    if not re.match(r'^eos_[0-9a-f]{48}$', token):
        print('Thiếu EOS_RUNNER_TOKEN hợp lệ (đặt trong ~/.config/eos-hive/runner.env, quyền 600)', file=sys.stderr)
        return 2
    r = Runner(Mcp(url, token), deo_sync=env.get('DEO_SYNC_DIR'), remote=env.get('RCLONE_REMOTE', 'gdrive'))
    if '--once' in argv:
        r.once()
        return 0
    stop = []
    for s in (signal.SIGINT, signal.SIGTERM):
        signal.signal(s, lambda *_: stop.append(1))
    poll = int(env.get('POLL_SECONDS', '30'))
    r.log(f'runner bắt đầu, hỏi việc mỗi {poll}s')
    while not stop:
        try:
            busy = r.once()
        except McpError as e:
            r.log(f'MCP lỗi: {e}'); busy = False
        except Exception as e:  # noqa: BLE001
            r.log(f'lỗi không lường: {type(e).__name__}'); busy = False
        if not busy:
            for _ in range(poll):
                if stop:
                    break
                time.sleep(1)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
