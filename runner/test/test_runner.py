"""Kiểm thử runner với MCP giả và lệnh ngoài giả (không cần Drive, rclone, Postgres)."""
import json, os, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import eos_z2_runner as R

TOKEN = 'eos_' + '0' * 48
SRC = '1SourceFolderId0001'


class FakeMcp:
    def __init__(self, jobs):
        self.jobs, self.calls = list(jobs), []

    def call(self, name, args=None):
        self.calls.append((name, args))
        if name == 'eos_runner_claim':
            return self.jobs.pop(0) if self.jobs else {'idle': True}
        return {'result': 'ok'}

    def reports(self, event=None):
        return [a for n, a in self.calls if n == 'eos_runner_report' and (event is None or a['event'] == event)]


def job(stage, feedback=None, slug='du-an-a'):
    return {'card': 'runner-7', 'task': {'id': 42, 'title': 't'}, 'skill': 'xu-ly-ho-so', 'scope': {'stage': stage}, 'feedback': feedback,
            'run': {'id': 1, 'drive_folder_id': SRC, 'md_folder_id': None, 'project': slug}}


class Shell:
    """Giả lập các lệnh: ghi lại và trả đầu ra định sẵn."""
    def __init__(self, home, fail_on=None):
        self.home, self.cmds, self.fail_on = Path(home), [], fail_on

    def __call__(self, argv, **kw):
        self.cmds.append(argv)
        if self.fail_on and self.fail_on in argv:
            return 1, 'token ya29.SECRETSECRETSECRET hết hạn\nlỗi rclone thật'
        if argv[0] == 'bash' and argv[1].endswith('run_project.sh'):
            md = self.home / 'work' / 'md' / argv[2]; md.mkdir(parents=True, exist_ok=True)
            (md / '00_MUC_LUC.md').write_text('# Mục lục\n\nTổng 5 file: 4 đã có Markdown, 2 file có trang cần soát OCR, 1 lỗi.\n', encoding='utf-8')
            return 0, ''
        if argv[0] == 'rclone' and argv[1] == 'lsjson' and '--dirs-only' in argv:
            return 0, json.dumps([{'Name': 'khac', 'ID': 'x'}, {'Name': R.MD_SUBDIR, 'ID': 'MdFolderId000001'}])
        if argv[0] == 'rclone' and argv[1] == 'lsjson':
            return 0, json.dumps([{'ID': f'File{i:08d}', 'Name': f'f{i}.md', 'Path': f'sub/f{i}.md', 'Size': 10, 'MimeType': 'text/markdown'} for i in range(450)])
        return 0, ''


class RunnerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.sh = None

    def runner(self, jobs, **kw):
        self.mcp = FakeMcp(jobs)
        self.sh = Shell(self.tmp, **kw)
        return R.Runner(self.mcp, home=self.tmp, deo_sync='/opt/deo', remote='gdrive', sh=self.sh, log=lambda *_: None)

    def test_idle(self):
        r = self.runner([])
        self.assertFalse(r.once())
        self.assertEqual(self.mcp.reports(), [])

    def test_fetch_convert_happy_path(self):
        r = self.runner([job('fetch_convert')])
        self.assertTrue(r.once())
        first = self.sh.cmds[0]
        self.assertEqual(first[:2], ['bash', '/opt/deo/fetch_drive.sh']); self.assertEqual(first[2:], ['du-an-a', SRC])
        self.assertTrue(all(isinstance(a, str) for c in self.sh.cmds for a in c), 'lệnh là danh sách đối số, không qua shell')
        self.assertIn(['bash', '/opt/deo/run_project.sh', 'du-an-a'], self.sh.cmds)
        copy = next(c for c in self.sh.cmds if c[:2] == ['rclone', 'copy'])
        self.assertIn(f'gdrive:{R.MD_SUBDIR}', copy); self.assertIn(SRC, copy)
        setups = [a for n, a in self.mcp.calls if n == 'eos_runner_setup']
        self.assertEqual(setups[0], {'task': 42, 'md_folder_id': 'MdFolderId000001'})
        self.assertEqual([len(s['files']) for s in setups[1:]], [200, 200, 50], 'đăng ký theo lô 200')
        self.assertTrue(setups[1]['files'][0]['url'].startswith('https://drive.google.com/file/d/'))
        done = self.mcp.reports('completed')[0]['payload']
        self.assertIn('5 tệp nguồn', done['summary']); self.assertIn('450 tệp', done['summary']); self.assertEqual(done['confidence'], 'trung bình')
        keys = [a['key'] for a in self.mcp.reports()]
        self.assertEqual(len(keys), len(set(keys)), 'mỗi sự kiện một khóa riêng')
        self.assertTrue(all(len(k) >= 6 for k in keys))

    def test_failure_reports_crash_and_scrubs_secrets(self):
        r = self.runner([job('fetch_convert')], fail_on='rclone')
        self.assertTrue(r.once())
        crash = self.mcp.reports('crashed')
        self.assertEqual(len(crash), 1)
        self.assertNotIn('ya29', crash[0]['payload']['reason']); self.assertIn('[ẩn]', crash[0]['payload']['reason'])
        self.assertEqual(self.mcp.reports('completed'), [])

    def test_bad_inputs_never_reach_shell(self):
        for slug, src in [('Sai Slug; rm -rf /', SRC), ('du-an', 'ngắn'), ('du-an', 'abc; ls /tmp/xx')]:
            j = job('fetch_convert', slug=slug); j['run']['drive_folder_id'] = src
            r = self.runner([j]); r.once()
            self.assertEqual(self.sh.cmds, [], (slug, src)); self.assertEqual(len(self.mcp.reports('crashed')), 1)

    def test_unknown_stage_blocks(self):
        r = self.runner([job('bay-bo')]); r.once()
        self.assertEqual(len(self.mcp.reports('blocked')), 1); self.assertEqual(self.sh.cmds, [])

    def test_kb_ingest_asks_human_then_registers_answer(self):
        up = Path(self.tmp) / 'work' / 'upload' / 'du-an-a'; up.mkdir(parents=True)
        for i in range(3): (up / f'{i}.md').write_text('x')
        r = self.runner([job('kb_ingest')]); r.once()
        b = self.mcp.reports('blocked')[0]['payload']['reason']
        self.assertIn('3 tệp', b); self.assertIn('kb:<mã KB>', b)
        r2 = self.runner([job('kb_ingest', feedback='Đã tạo KB, kb:AbCd1234Ef')]); r2.once()
        self.assertIn(('eos_runner_setup', {'task': 42, 'weknora_kb_id': 'AbCd1234Ef'}), self.mcp.calls)
        self.assertEqual(len(self.mcp.reports('completed')), 1)

    def test_kb_ingest_without_files_blocks(self):
        r = self.runner([job('kb_ingest')]); r.once()
        self.assertIn('chưa có tệp', self.mcp.reports('blocked')[0]['payload']['reason'])

    def test_scrub(self):
        s = R.scrub('Authorization: Bearer abc.def eos_' + 'a' * 48 + ' ok')
        self.assertNotIn('eos_a', s); self.assertNotIn('abc.def', s)

    def test_main_rejects_missing_token(self):
        os.environ['EOS_RUNNER_ENV'] = '/nonexistent'; os.environ.pop('EOS_RUNNER_TOKEN', None)
        self.assertEqual(R.main(['--once']), 2)


if __name__ == '__main__':
    unittest.main()
