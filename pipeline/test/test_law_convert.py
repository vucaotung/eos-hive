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


class Structure(unittest.TestCase):
    SRC = '\n'.join([
        '# **QUỐC HỘI**', '# **Độc lập - Tự do - Hạnh phúc**', 'Luật số: 135/2025/QH15',
        'Căn cứ Hiến pháp; Quốc hội ban hành Luật Xây dựng, thay thế Luật số 50/2014/QH13.',
        '# **Chương I**', '', '# **NHỮNG QUY ĐỊNH CHUNG**', '',
        '# **Điều 1. Phạm vi điều chỉnh**', '', 'Luật này quy định về hoạt động xây dựng.',
        '**Điều 2.** **Giải thích từ ngữ**', '    1. Khoản một có thụt lề.', 'a) Điểm a;', 'b) Điểm b theo Nghị định số 207/2026/NĐ-CP.',
        'Kết thúc điều. **Điều 3. Nguyên tắc**', 'Nội dung điều 3, xem Điều 1 của Luật này.',
        'MỤC 2', 'QUY HOẠCH XÂY DỰNG',
        'Điều 4: Loại quy hoạch',
        '| Cột A | Cột B |', '|---|---|', '| 1 | 2 |', 'Sau bảng.',
        'PHỤ LỤC I', 'DANH MỤC CÔNG TRÌNH', '# **Trần Thanh Mẫn**',
    ])

    def test_tieu_de_phan_cap(self):
        out = law_convert.clean(self.SRC)
        lines = out.split('\n')
        heads = [x for x in lines if x.startswith('#')]
        self.assertEqual(heads, ['# Chương I. NHỮNG QUY ĐỊNH CHUNG', '### Điều 1. Phạm vi điều chỉnh', '### Điều 2. Giải thích từ ngữ',
                                 '### Điều 3. Nguyên tắc', '## Mục 2. QUY HOẠCH XÂY DỰNG', '### Điều 4. Loại quy hoạch', '# PHỤ LỤC I. DANH MỤC CÔNG TRÌNH'])
        self.assertIn('**Độc lập - Tự do - Hạnh phúc**', lines)          # quốc hiệu không còn là tiêu đề
        self.assertIn('**Trần Thanh Mẫn**', lines)
        self.assertIn('Kết thúc điều.', lines)                            # điều dính cuối đoạn được tách
        self.assertIn('Nội dung điều 3, xem Điều 1 của Luật này.', lines)  # dẫn chiếu giữa câu không thành tiêu đề

    def test_khoan_diem_doan_rieng_bang_giu_nguyen(self):
        out = law_convert.clean(self.SRC)
        self.assertIn('\n\n1. Khoản một có thụt lề.\n\n', out)
        self.assertIn('\n\na) Điểm a;\n\nb) Điểm b', out)
        self.assertIn('\n\n| Cột A | Cột B |\n|---|---|\n| 1 | 2 |\n\nSau bảng.', out)
        self.assertNotRegex(out, r'\n {4,}\S')                            # không có dòng thụt lề thành khối mã

    def test_ten_muc_hai_dong_va_doan_cat_trang(self):
        src = ('[[trang 1]]\n\nMỤC 3\n\nQUẢN LÝ CHẤT LƯỢNG, NGHIỆM THU,\n\nBÀN GIAO CÔNG TRÌNH\n\nĐiều 5. Nghiệm thu\n\n'
               '2. Công trình xây dựng là sản phẩm được xây dựng theo thiết kế, vật liệu xây dựng, thiết bị lắp đặt vào công trình,\n\n'
               '[[trang 2]]\n\nđược liên kết định vị với đất.\n\n3. Khoản sau.\n\nb) điểm b vẫn là đoạn riêng;\n\nc) điểm c.\n')
        out = law_convert.clean(src)
        self.assertIn('## Mục 3. QUẢN LÝ CHẤT LƯỢNG, NGHIỆM THU, BÀN GIAO CÔNG TRÌNH\n', out)
        self.assertIn('vào công trình, được liên kết định vị với đất.\n', out)
        self.assertIn('\n\n3. Khoản sau.\n\nb) điểm b vẫn là đoạn riêng;\n\nc) điểm c.', out)

    def test_dan_chieu(self):
        refs = law_convert.references(law_convert.clean(self.SRC))
        self.assertEqual(refs, ['135/2025/QH15', '50/2014/QH13', '207/2026/NĐ-CP'])


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
