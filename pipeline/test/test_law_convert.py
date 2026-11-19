"""Chuyển văn bản pháp luật cho máy chủ MCP (pipeline.law_convert): bỏ dấu trang, từ chối trang scan, JSON ra stdout."""
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from pipeline import law_convert
from pipeline.convert import Result

BODY = 'Điều 1. Phạm vi điều chỉnh\n\nLuật này quy định về hoạt động đầu tư xây dựng. ' * 6


class Judge(unittest.TestCase):
    def test_bo_dau_trang_va_dong_trong(self):
        ok, text = law_convert.judge(Result('ok', text=f'[[trang 1]]\n\n{BODY}\n\n\n\n[[trang 2]]\n\nĐiều 2. Đối tượng áp dụng   \n'))
        self.assertTrue(ok)
        self.assertNotIn('[[trang', text)
        self.assertNotIn('\n\n\n', text)
        self.assertIn('Điều 2. Đối tượng áp dụng\n', text)

    def test_bo_tieu_de_trang_lap(self):
        pages = ''.join(f'[[trang {n}]]\n\nCÔNG BÁO/Số 37/Ngày 22-01-2026\n\n{44 + n}\n\nĐiều {n}. Nội dung điều {n}\n\n{BODY}\n\n' for n in range(1, 7))
        ok, text = law_convert.judge(Result('ok', text=pages))
        self.assertTrue(ok)
        self.assertNotIn('CÔNG BÁO/Số 37', text)
        self.assertNotIn('\n46\n', text)
        self.assertIn('Điều 6. Nội dung điều 6', text)
        # dòng lặp nằm GIỮA trang (nội dung thật) không bị bỏ; ít hơn 3 trang thì giữ nguyên
        mid = ''.join(f'[[trang {n}]]\n\nĐầu {n}\n\n{BODY}\n\nKhoản này áp dụng chung.\n\n{BODY}\n\nCuối {n}\n\n' for n in range(1, 5))
        self.assertEqual(law_convert.clean(mid).count('Khoản này áp dụng chung.'), 4)
        two = '[[trang 1]]\n\nCÔNG BÁO\n\nA\n\n[[trang 2]]\n\nCÔNG BÁO\n\nB\n'
        self.assertIn('CÔNG BÁO', law_convert.clean(two))

    def test_tu_choi_trang_scan(self):
        ok, why = law_convert.judge(Result('ok', text=BODY, scan_pages=[3, 4], pages=5))
        self.assertFalse(ok)
        self.assertIn('2 trang scan', why)
        self.assertIn('trang 3, 4', why)

    def test_tu_choi_trang_da_ocr(self):
        ok, why = law_convert.judge(Result('ok', text=BODY, ocr_pages=[1]))
        self.assertFalse(ok)
        self.assertIn('Không dùng OCR', why)

    def test_tu_choi_loi_va_qua_ngan(self):
        self.assertFalse(law_convert.judge(Result('error', reason='hỏng'))[0])
        self.assertFalse(law_convert.judge(Result('ok', text='Điều 1.'))[0])


class Cli(unittest.TestCase):
    def call(self, *argv):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = law_convert.main(['law_convert', *argv])
        return code, json.loads(buf.getvalue())

    def test_sai_doi_so_va_loai(self):
        code, out = self.call('x')
        self.assertEqual((code, out['ok']), (2, False))
        with tempfile.NamedTemporaryFile(suffix='.bin', delete=False) as f:
            f.write(b'x')
        code, out = self.call(f.name, 'exe')
        Path(f.name).unlink()
        self.assertFalse(out['ok'])
        self.assertIn('không hỗ trợ', out['error'])

    @unittest.skipUnless(importlib.util.find_spec('markitdown'), 'cần markitdown')
    def test_html_thanh_markdown(self):
        html = '<html><body><h1>LUẬT XÂY DỰNG</h1>' + ''.join(f'<h2>Điều {i}. Nội dung</h2><p>{BODY}</p>' for i in range(1, 4)) + '</body></html>'
        with tempfile.NamedTemporaryFile(suffix='.html', delete=False, mode='w', encoding='utf-8') as f:
            f.write(html)
        code, out = self.call(f.name, 'html')
        Path(f.name).unlink()
        self.assertEqual(code, 0, out)
        self.assertIn('Điều 3. Nội dung', out['text'])


if __name__ == '__main__':
    unittest.main()
