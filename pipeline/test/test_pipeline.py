"""Kiểm thử pipeline: không cần Drive thật, rclone hay mạng. Chạy: python -m unittest discover -s pipeline/test"""
import json
import os
import re
import shutil
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from pipeline import cli, convert, drive as D, fetch, frontmatter, paths, push, run, toc   # noqa: E402
from pipeline.config import Config, MD_SUBDIR   # noqa: E402

# Biểu thức runner dùng để đọc dòng tổng của mục lục (runner/eos_z2_runner.py)
RUNNER_TOC = re.compile(r'Tổng (\d+) file: (\d+) đã có Markdown, (\d+) file có trang cần soát OCR, (\d+) lỗi')


def make_docx(path, text):
    ns = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                   '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                   '<Default Extension="xml" ContentType="application/xml"/>'
                   '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        z.writestr('_rels/.rels', '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                   '<Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        z.writestr('word/document.xml', f'<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="{ns}"><w:body><w:p><w:r><w:t>{text}</w:t></w:r></w:p></w:body></w:document>')


def make_pdf(path, pages):
    """pages: list 'text' (có lớp chữ) hoặc None (trang trắng chỉ có hình = scan)."""
    import pymupdf
    doc = pymupdf.open()
    for t in pages:
        pg = doc.new_page()
        if t:
            pg.insert_text((72, 100), t, fontsize=12)
        else:
            pix = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, 40, 40), False)
            pix.clear_with(200)
            pg.insert_image(pymupdf.Rect(50, 50, 300, 300), pixmap=pix)
    doc.save(str(path))
    doc.close()


def make_xlsx(path):
    import openpyxl
    wb = openpyxl.Workbook()
    wb.active.append(['STT', 'Nội dung'])
    wb.active.append([1, 'Đơn xin giao đất'])
    wb.save(path)


def long_text(n):
    return ' '.join(['Nội dung kiểm thử tiếng Việt'] * n)


class Base(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='eos-pl-'))
        # TESSERACT_CMD rỗng: kết quả không phụ thuộc máy có Tesseract hay không (OCR có test riêng)
        self.cfg = Config({'WORK_DIR': str(self.root / 'work'), 'SOFFICE_BIN': '', 'TESSERACT_CMD': ''})
        self.addCleanup(shutil.rmtree, self.root, True)

    def src(self):
        s = self.root / 'nguon'
        (s / 'Thư mục con').mkdir(parents=True)
        make_docx(s / 'Thư mục con' / 'Đơn xin.docx', 'Đơn xin giao đất')
        make_xlsx(s / 'Phụ lục.xlsx')
        make_pdf(s / 'Văn bản.pdf', [long_text(5), None])
        (s / 'ghi chú.txt').write_text('Ghi chú tiếng Việt\n', encoding='utf-8')
        (s / 'Bản vẽ.dwg').write_bytes(b'AC1027fake')
        (s / MD_SUBDIR).mkdir()
        (s / MD_SUBDIR / 'cu.md').write_text('đầu ra cũ')
        (s / 'desktop.ini').write_text('x')
        return s


class PathsTest(unittest.TestCase):
    def test_safe_name_windows_rules(self):
        self.assertEqual(paths.safe_name('Báo cáo: tháng 10?.docx'), ('Báo cáo_ tháng 10_.docx', True))
        self.assertEqual(paths.safe_name('tên cuối.  '), ('tên cuối', True))
        self.assertEqual(paths.safe_name('CON.txt')[0], '_CON.txt')
        self.assertEqual(paths.safe_name('nul')[0], '_nul')
        self.assertEqual(paths.safe_name('bình thường.pdf'), ('bình thường.pdf', False))

    def test_nfc_normalisation(self):
        decomposed = 'Đơn xin giao đất'
        self.assertEqual(paths.nfc(decomposed), paths.nfc(paths.nfc(decomposed)))
        self.assertTrue(paths.safe_name(decomposed)[0].isascii() is False)

    def test_long_component_truncated_with_hash(self):
        s, changed = paths.safe_name('a' * 300 + '.pdf')
        self.assertTrue(changed and len(s) <= paths.MAX_COMPONENT and s.endswith('.pdf'))

    def test_safe_rel_uses_posix_and_keeps_vietnamese(self):
        rel, _ = paths.safe_rel('Giao đất/Đợt 1: mới/a?.doc')
        self.assertEqual(rel, 'Giao đất/Đợt 1_ mới/a_.doc')
        self.assertNotIn('\\', rel)

    def test_md_name_collision(self):
        self.assertEqual(paths.md_name('a/b.docx', False), 'a/b.md')
        self.assertEqual(paths.md_name('a/b.docx', True), 'a/b.docx.md')


class FrontMatterTest(unittest.TestCase):
    def test_contract_keys_and_empty_step(self):
        fm = frontmatter.build({'project': 'p', 'drive_id': 'ID123456789', 'duong_dan': 'A/b: c.pdf', 'md5': 'x', 'so_trang': 7,
                                'buoc': '05', 'giai_doan': 'I'})
        meta, body = frontmatter.parse(fm + 'nội dung')
        self.assertEqual(body, 'nội dung')
        for k in ('drive_id', 'drive_link', 'duong_dan', 'md5', 'converter', 'ocr_conf_tb', 'so_trang', 'buoc', 'giai_doan'):
            self.assertIn(k, meta)
        self.assertEqual(meta['buoc'], ''); self.assertEqual(meta['giai_doan'], '', 'mã bước luôn để trống')
        self.assertEqual(meta['duong_dan'], 'A/b: c.pdf')
        self.assertEqual(meta['drive_link'], 'https://drive.google.com/file/d/ID123456789/view')
        self.assertEqual(meta['so_trang'], '7')

    def test_one_line_per_key(self):
        fm = frontmatter.build({'duong_dan': 'a\nb'})
        self.assertEqual(sum(1 for l in fm.split('\n') if l.startswith('duong_dan:')), 1)
        self.assertNotIn('a\nb', fm)


class TocTest(unittest.TestCase):
    def test_summary_line_matches_runner_regex(self):
        recs = [{'path': 'a.docx', 'status': 'ok', 'route': 'A_native'},
                {'path': 'b.pdf', 'status': 'ok', 'route': 'C_scan', 'pages': 3, 'scan_pages': [2, 3]},
                {'path': 'c.dwg', 'status': 'skip', 'reason': 'khong_tai'},
                {'path': 'd.doc', 'status': 'error', 'reason': 'x'}]
        text = toc.build('p', recs, [('a:b', 'a_b')])
        m = RUNNER_TOC.search(text[:2000])
        self.assertEqual(m.groups(), ('4', '2', '1', '1'))
        for h in ('## Cần soát', '## Lỗi', '## Không chuyển đổi', '## Đã đổi tên'):
            self.assertIn(h, text)


class ConvertTest(Base):
    def conv(self, name, builder):
        p = self.root / name
        builder(p)
        return convert.convert_file(p, name, self.cfg, self.root)

    def test_docx_xlsx_txt(self):
        r = self.conv('a.docx', lambda p: make_docx(p, 'Xin chào'))
        self.assertEqual((r.status, r.route), ('ok', 'A_native')); self.assertIn('Xin chào', r.text)
        r = self.conv('b.xlsx', make_xlsx)
        self.assertEqual(r.status, 'ok'); self.assertIn('Đơn xin giao đất', r.text)
        r = self.conv('c.txt', lambda p: p.write_text('Đây là văn bản', encoding='utf-8'))
        self.assertEqual((r.status, r.route), ('ok', 'text'))

    def test_pdf_pages_text_and_scan(self):
        r = self.conv('d.pdf', lambda p: make_pdf(p, [long_text(5), None, long_text(4)]))
        self.assertEqual((r.status, r.route, r.pages, r.scan_pages), ('ok', 'C_scan', 3, [2]), 'không có Tesseract: trang scan được đánh dấu, không im lặng')
        self.assertIn('[[trang 1]]', r.text); self.assertIn('[[trang 2]]', r.text); self.assertIn('[[trang 3]]', r.text)
        self.assertIn('cần OCR', r.text); self.assertIn('TESSERACT_CMD', r.note)

    def test_pdf_all_text_is_native(self):
        r = self.conv('e.pdf', lambda p: make_pdf(p, [long_text(5)]))
        self.assertEqual((r.route, r.scan_pages), ('A_native', []))

    def test_skip_rules(self):
        for n, why in [('x.dwg', 'khong_tai'), ('x.DGN', 'khong_tai'), ('v.mp4', 'khong_tai'), ('z.zip', 'khong_tai'),
                       ('l.gdoc', 'lien_ket_google')]:
            r = convert.convert_file(self.root / n, n, self.cfg, self.root)
            self.assertEqual((r.status, r.reason), ('skip', why), n)

    def test_corrupt_file_is_error_not_crash(self):
        r = self.conv('hong.pdf', lambda p: p.write_bytes(b'khong phai pdf'))
        self.assertEqual(r.status, 'error')

    def test_legacy_without_soffice_is_error(self):
        r = self.conv('cu.doc', lambda p: p.write_bytes(b'x'))
        self.assertEqual(r.status, 'error'); self.assertIn('SOFFICE_BIN', r.reason)

    @unittest.skipUnless(Config().soffice, 'không có LibreOffice')
    def test_legacy_doc_with_soffice(self):
        cfg = Config()
        src = self.root / 'm.docx'; make_docx(src, 'Văn bản cũ')
        import subprocess
        subprocess.run([cfg.soffice, '--headless', '--convert-to', 'doc', '--outdir', str(self.root), str(src)], capture_output=True, timeout=180)
        doc = self.root / 'm.doc'
        if not doc.exists():
            self.skipTest('LibreOffice không tạo được .doc mẫu')
        r = convert.convert_file(doc, 'm.doc', cfg, self.root)
        self.assertEqual((r.status, r.route), ('ok', 'A_soffice')); self.assertIn('Văn bản cũ', r.text)


class FetchRunLocalTest(Base):
    def test_end_to_end_local(self):
        s = self.src()
        n = fetch.fetch_local('du-an-a', s, self.cfg)
        self.assertEqual(n, 5, 'ini và _md_deo bị bỏ; dwg vẫn có trong manifest')
        mf = json.loads(self.cfg.manifest('du-an-a').read_text(encoding='utf-8'))
        paths_ = {f['path'] for f in mf['files']}
        self.assertNotIn('desktop.ini', paths_); self.assertFalse(any(MD_SUBDIR in p for p in paths_))
        dwg = next(f for f in mf['files'] if f['path'].endswith('.dwg'))
        self.assertEqual(dwg['skip'], 'khong_tai'); self.assertEqual(dwg['local'], '', 'tệp không tải thì không chép')
        stats = run.run_project('du-an-a', self.cfg)
        self.assertEqual((stats['total'], stats['ok'], stats['skip'], stats['error'], stats['need_ocr']), (5, 4, 1, 0, 1))
        md = self.cfg.md('du-an-a')
        mds = sorted(p.relative_to(md).as_posix() for p in md.rglob('*.md'))
        self.assertEqual(mds, ['00_MUC_LUC.md', 'Phụ lục.md', 'Thư mục con/Đơn xin.md', 'Văn bản.md', 'ghi chú.md'])
        meta, body = frontmatter.parse((md / 'Thư mục con' / 'Đơn xin.md').read_text(encoding='utf-8'))
        self.assertEqual(meta['duong_dan'], 'Thư mục con/Đơn xin.docx'); self.assertEqual(meta['buoc'], '')
        self.assertEqual(len(meta['md5']), 32); self.assertIn('Đơn xin giao đất', body)
        meta, _ = frontmatter.parse((md / 'Văn bản.md').read_text(encoding='utf-8'))
        self.assertEqual(meta['so_trang'], '2')
        m = RUNNER_TOC.search((md / '00_MUC_LUC.md').read_text(encoding='utf-8')[:2000])
        self.assertEqual(m.groups(), ('5', '4', '1', '0'))
        self.assertFalse(self.cfg.tmp().exists(), 'không còn thư mục tạm')

    def test_same_stem_does_not_overwrite(self):
        s = self.root / 'n'; s.mkdir()
        make_docx(s / 'a.docx', 'bản docx'); make_pdf(s / 'a.pdf', [long_text(5)])
        fetch.fetch_local('p', s, self.cfg); run.run_project('p', self.cfg)
        self.assertEqual(sorted(x.name for x in self.cfg.md('p').glob('a*.md')), ['a.docx.md', 'a.pdf.md'])

    def test_tmp_removed_even_on_failure(self):
        s = self.src(); fetch.fetch_local('p', s, self.cfg)

        def boom(*a, **k):
            raise RuntimeError('hỏng giữa chừng')
        with self.assertRaises(RuntimeError):
            run.run_project('p', self.cfg, convert=boom)
        self.assertFalse(self.cfg.tmp().exists() and any(self.cfg.tmp().iterdir()), 'thư mục tạm phải được dọn')

    def test_refuses_to_delete_outside_work_dir(self):
        with self.assertRaises(ValueError):
            fetch._reset(self.root / 'khac' / 'x', self.cfg.work)


class FakeDrive:
    """Drive giả: cây thư mục trong bộ nhớ."""
    def __init__(self, tree):
        self.tree, self.uploads, self.folders = tree, [], {}
        self.next = 0

    def children(self, fid):
        yield from self.tree.get(fid, [])

    def download(self, fid, dest, export_mime=None):
        Path(dest).parent.mkdir(parents=True, exist_ok=True)
        if fid == 'DocX0000000001':
            make_docx(dest, 'Nội dung từ Drive')
        elif fid == 'FailFile00001':
            raise D.DriveError(403, 'không có quyền')
        else:
            Path(dest).write_bytes(b'x')
        return 1

    def ensure_folder(self, parent, name):
        return self.folders.setdefault((parent, name), f'Folder{len(self.folders):08d}')

    def upload(self, parent, name, data, mime):
        self.next += 1
        self.uploads.append((parent, name, mime, len(data)))
        return {'id': f'Up{self.next:010d}', 'mimeType': mime, 'size': len(data)}


def f(id_, name, mime='application/pdf', **kw):
    return {'id': id_, 'name': name, 'mimeType': mime, 'size': '10', 'md5Checksum': 'a' * 32, 'modifiedTime': '2026-10-01T00:00:00Z', **kw}


class DriveModeTest(Base):
    def tree(self):
        deep = 'Thư mục rất dài ' + 'x' * 40
        return {'Root00000000001': [
            f('Sub0000000001', 'Pháp lý: hồ sơ?', D.FOLDER),
            f('DocX0000000001', 'Đơn.docx', 'application/vnd.google-apps.document'),
            f('Shortcut00001', 'lối tắt', D.SHORTCUT),
            f('Dwg0000000001', 'Bản vẽ.dwg', 'application/octet-stream'),
            f('Md00000000001', MD_SUBDIR, D.FOLDER),
            f('FailFile00001', 'cấm.pdf'),
            f('Deep000000001', deep, D.FOLDER)],
            'Sub0000000001': [f('Pdf0000000001', 'Văn bản: số 1?.pdf')],
            'Md00000000001': [f('Old0000000001', 'cu.md', 'text/markdown')],
            'Deep000000001': [f('Deep000000002', deep, D.FOLDER)],
            'Deep000000002': [f('Deep000000003', deep, D.FOLDER)],
            'Deep000000003': [f('Deep000000004', deep, D.FOLDER)],
            'Deep000000004': [f('Deep000000005', 'sâu.pdf')]}

    def test_fetch_drive_names_links_and_skips(self):
        n = fetch.fetch_drive('p', 'Root00000000001', self.cfg, FakeDrive(self.tree()))
        mf = {x['path']: x for x in json.loads(self.cfg.manifest('p').read_text(encoding='utf-8'))['files']}
        self.assertEqual(n, len(mf))
        self.assertIn('Pháp lý: hồ sơ?/Văn bản: số 1?.pdf', mf, '`duong_dan` giữ nguyên tên gốc, dấu /')
        self.assertEqual(mf['Pháp lý: hồ sơ?/Văn bản: số 1?.pdf']['local'], 'Pháp lý_ hồ sơ_/Văn bản_ số 1_.pdf')
        self.assertEqual(mf['Đơn.docx']['local'], 'Đơn.docx'); self.assertTrue(mf['Đơn.docx']['drive_link'].endswith('/DocX0000000001/view'))
        self.assertEqual(mf['Bản vẽ.dwg']['skip'], 'khong_tai')
        self.assertEqual(mf['cấm.pdf']['skip'], 'loi_tai')
        self.assertFalse(any(MD_SUBDIR in p or 'lối tắt' in p for p in mf))
        self.assertTrue(any(p.endswith('sâu.pdf') for p in mf))

    def test_run_after_drive_fetch_has_drive_ids_and_renames(self):
        fetch.fetch_drive('p', 'Root00000000001', self.cfg, FakeDrive(self.tree()))
        stats = run.run_project('p', self.cfg, convert=lambda path, name, cfg, tmp: convert.Result('ok', 'A_native', 't', text='nội dung') if not name.endswith('.dwg') else convert.Result('skip', reason='khong_tai'))
        self.assertEqual(stats['error'], 0)
        md = self.cfg.md('p')
        out = md / 'Pháp lý_ hồ sơ_' / 'Văn bản_ số 1_.md'
        meta, _ = frontmatter.parse(out.read_text(encoding='utf-8'))
        self.assertEqual(meta['drive_id'], 'Pdf0000000001'); self.assertEqual(meta['duong_dan'], 'Pháp lý: hồ sơ?/Văn bản: số 1?.pdf')
        t = (md / '00_MUC_LUC.md').read_text(encoding='utf-8')
        self.assertIn('## Đã đổi tên', t)

    def test_push_uploads_tree_and_writes_result(self):
        fetch.fetch_drive('p', 'Root00000000001', self.cfg, FakeDrive(self.tree()))
        run.run_project('p', self.cfg, convert=lambda path, name, cfg, tmp: convert.Result('ok', 'A_native', 't', text='x') if name.endswith('.pdf') or name.endswith('.docx') else convert.Result('skip', reason='khong_tai'))
        fd = FakeDrive({})
        r = push.push('p', 'Root00000000001', self.cfg, fd)
        self.assertIn(('Root00000000001', MD_SUBDIR), fd.folders)
        res = json.loads(self.cfg.push_result('p').read_text(encoding='utf-8'))
        self.assertEqual(res['md_folder_id'], r['md_folder_id']); self.assertEqual(len(res['files']), r['files'])
        names = [x['name'] for x in res['files']]
        self.assertIn('00_MUC_LUC.md', names); self.assertIn('Pháp lý_ hồ sơ_/Văn bản_ số 1_.md', names)
        self.assertTrue(all(x['url'].startswith('https://drive.google.com/file/d/') and x['mime'] == 'text/markdown' for x in res['files']))


class DriveClientTest(unittest.TestCase):
    def client(self, responses):
        calls = []

        def http(method, url, headers, body):
            calls.append((method, url))
            return responses.pop(0)
        return D.Drive('cid', 'secret', 'refresh', http=http, sleep=lambda s: None), calls

    def test_token_then_paginated_children(self):
        c, calls = self.client([(200, {}, b'{"access_token":"T","expires_in":3600}'),
                                (200, {}, json.dumps({'files': [{'id': '1'}], 'nextPageToken': 'N'}).encode()),
                                (200, {}, json.dumps({'files': [{'id': '2'}]}).encode())])
        self.assertEqual([x['id'] for x in c.children('F1234567890')], ['1', '2'])
        self.assertIn('pageToken=N', calls[2][1])

    def test_retries_on_429_and_errors_hide_secrets(self):
        c, _ = self.client([(200, {}, b'{"access_token":"T"}'), (429, {}, b''), (200, {}, b'{"files":[]}')])
        self.assertEqual(list(c.children('F1234567890')), [])
        c2, _ = self.client([(400, {}, b'{"error":"invalid_grant refresh secret"}')])
        with self.assertRaises(D.DriveError) as cm:
            c2.token()
        self.assertNotIn('secret', str(cm.exception)); self.assertNotIn('refresh', str(cm.exception))

    def test_from_env_requires_all_three(self):
        for k in ('GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_REFRESH_TOKEN'):
            os.environ.pop(k, None)
        with self.assertRaises(D.DriveError):
            D.Drive.from_env()

    def test_upload_updates_existing_instead_of_duplicating(self):
        c, calls = self.client([(200, {}, b'{"access_token":"T"}'), (200, {}, b'{"files":[{"id":"Old1","name":"a.md"}]}'), (200, {}, b'{"id":"Old1"}')])
        c.upload('P1234567890', 'a.md', b'x', 'text/markdown')
        self.assertEqual(calls[-1][0], 'PATCH'); self.assertIn('/files/Old1', calls[-1][1])


class CliTest(Base):
    def test_rejects_bad_slug_and_id(self):
        self.assertEqual(cli.main(['run', 'Sai Slug; rm -rf /']), 2)
        os.environ['WORK_DIR'] = str(self.cfg.work)
        self.addCleanup(os.environ.pop, 'WORK_DIR', None)
        self.assertEqual(cli.main(['fetch', 'du-an', 'ngắn']), 2)
        self.assertEqual(cli.main(['push', 'du-an', 'abc; ls']), 2)

    def test_fetch_run_via_cli(self):
        s = self.src()
        os.environ['WORK_DIR'] = str(self.cfg.work)
        self.addCleanup(os.environ.pop, 'WORK_DIR', None)
        self.assertEqual(cli.main(['fetch', 'du-an', '--source-dir', str(s)]), 0)
        self.assertEqual(cli.main(['run', 'du-an']), 0)
        self.assertTrue((self.cfg.md('du-an') / '00_MUC_LUC.md').exists())

    def test_push_with_injected_client(self):
        s = self.src()
        os.environ['WORK_DIR'] = str(self.cfg.work)
        self.addCleanup(os.environ.pop, 'WORK_DIR', None)
        cli.main(['fetch', 'du-an', '--source-dir', str(s)]); cli.main(['run', 'du-an'])
        fd = FakeDrive({})
        self.assertEqual(cli.main(['push', 'du-an', 'Root00000000001'], client_factory=lambda: fd), 0)
        self.assertTrue(self.cfg.push_result('du-an').exists())


if __name__ == '__main__':
    unittest.main()
