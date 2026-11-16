"""Kiểm thử Pha 3: OCR theo trang, ảnh (nén, HEIC, EXIF), ngưỡng cần soát, tên trùng. Không cần Drive hay mạng."""
import io
import json
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_pipeline import Base, long_text, make_docx, make_pdf   # noqa: E402
from pipeline import convert, fetch, frontmatter, images, ocr, run, toc   # noqa: E402
from pipeline.config import Config   # noqa: E402

RUNNER_TOC = __import__('re').compile(r'Tổng (\d+) file: (\d+) đã có Markdown, (\d+) file có trang cần soát OCR, (\d+) lỗi')


class FakeOcr:
    """OCR giả: trả lần lượt kết quả định sẵn cho từng trang scan."""
    def __init__(self, results):
        self.results, self.calls = list(results), 0

    def page(self, png):
        self.calls += 1
        assert Path(png).exists(), 'ảnh trang phải tồn tại lúc OCR'
        r = self.results.pop(0)
        if isinstance(r, Exception):
            raise r
        return r


def find_font():
    for p in ('C:/Windows/Fonts/arial.ttf', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', '/usr/share/fonts/dejavu/DejaVuSans.ttf'):
        if Path(p).exists():
            return p
    return None


def real_ocr_cfg():
    """Cấu hình dùng Tesseract thật nếu máy có Tesseract kèm dữ liệu vie; ngược lại None."""
    cfg = Config({'WORK_DIR': str(Path(os.environ.get('TEMP', '/tmp')) / 'eos-ocr-test'), 'TESSERACT_CMD': Config().tesseract,
                  'TESSDATA_DIR': os.environ.get('TESSDATA_DIR', '')})
    try:
        ocr.Tesseract(cfg).check()
    except ocr.OcrUnavailable:
        return None
    return cfg


class OcrParseTest(unittest.TestCase):
    def test_parse_tsv_lines_paragraphs_and_conf(self):
        head = 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n'
        rows = ['1\t1\t0\t0\t0\t0\t0\t0\t10\t10\t-1\t',
                '5\t1\t1\t1\t1\t1\t0\t0\t5\t5\t90\tQuyết', '5\t1\t1\t1\t1\t2\t0\t0\t5\t5\t80\tđịnh',
                '5\t1\t1\t1\t2\t1\t0\t0\t5\t5\t70\tsố 12',
                '5\t1\t2\t1\t1\t1\t0\t0\t5\t5\t100\tĐoạn hai',
                '5\t1\t2\t1\t1\t2\t0\t0\t5\t5\t-1\t   ']
        r = ocr.parse_tsv(head + '\n'.join(rows) + '\n')
        self.assertEqual(r.text, 'Quyết định\nsố 12\n\nĐoạn hai')
        self.assertAlmostEqual(r.conf, (90 + 80 + 70 + 100) / 4 / 100)

    def test_blank_page_has_no_conf(self):
        r = ocr.parse_tsv('level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext\n')
        self.assertEqual((r.text, r.conf), ('', None))

    def test_page_dpi_caps_large_pages(self):
        class R: width, height = 2400, 3300          # ~A0, đơn vị point
        cfg = Config({'TESSERACT_CMD': ''})
        self.assertLessEqual(page_px(R, cfg), cfg.ocr_max_side_px + 50)
        class A4: width, height = 595, 842
        self.assertEqual(convert.page_dpi(A4, cfg), 300)


def page_px(rect, cfg):
    return round(max(rect.width, rect.height) / 72 * convert.page_dpi(rect, cfg))


class PdfOcrTest(Base):
    def pdf(self, pages):
        p = self.root / 'x.pdf'
        make_pdf(p, pages)
        return p

    def test_review_threshold_blank_and_mean(self):
        pdf = self.pdf([long_text(5), None, None, None])
        eng = FakeOcr([ocr.PageOcr('Văn bản scan tốt', 0.90), ocr.PageOcr('Văn bản scan kém', 0.50), ocr.PageOcr('', None)])
        r = convert.convert_pdf(pdf, self.cfg, self.root, ocr_engine=eng)
        self.assertEqual((r.route, r.pages), ('B_ocr', 4))
        self.assertEqual(r.ocr_pages, [2, 3, 4]); self.assertEqual(r.review_pages, [3], 'chỉ trang dưới 0,80')
        self.assertEqual(r.scan_pages, [])
        self.assertAlmostEqual(r.ocr_conf, 0.70, places=3, msg='trung bình các trang có chữ, bỏ trang trắng')
        self.assertIn('Văn bản scan tốt', r.text); self.assertIn(convert.BLANK, r.text)
        for n in (1, 2, 3, 4):
            self.assertIn(f'[[trang {n}]]', r.text)
        self.assertEqual(eng.calls, 3, 'trang có lớp chữ không OCR')

    def test_ocr_error_on_one_page_keeps_the_rest(self):
        pdf = self.pdf([None, None])
        eng = FakeOcr([RuntimeError('tesseract hỏng'), ocr.PageOcr('Trang hai', 0.95)])
        r = convert.convert_pdf(pdf, self.cfg, self.root, ocr_engine=eng)
        self.assertEqual((r.route, r.scan_pages, r.ocr_pages), ('C_scan', [1], [2]))
        self.assertIn('OCR trang 1 lỗi', r.note); self.assertIn('Trang hai', r.text)

    def test_png_temp_removed_after_ocr(self):
        pdf = self.pdf([None])
        convert.convert_pdf(pdf, self.cfg, self.root, ocr_engine=FakeOcr([ocr.PageOcr('x', 0.9)]))
        self.assertEqual(list(self.root.glob('ocr-*.png')), [])

    def test_toc_flags_review_and_unresolved_pages(self):
        recs = [{'path': 'a.pdf', 'status': 'ok', 'kind': 'md', 'route': 'B_ocr', 'pages': 3, 'review_pages': [3], 'scan_pages': [], 'ocr_conf': 0.7},
                {'path': 'b.pdf', 'status': 'ok', 'kind': 'md', 'route': 'C_scan', 'pages': 2, 'review_pages': [], 'scan_pages': [1, 2], 'note': 'thiếu Tesseract'},
                {'path': 'c.docx', 'status': 'ok', 'kind': 'md', 'route': 'A_native'},
                {'path': 'd.jpg', 'status': 'ok', 'kind': 'image', 'out': 'd.jpg', 'bytes': 2048, 'src_bytes': 9000, 'note': 'JPEG'},
                {'path': 'e.dwg', 'status': 'skip', 'reason': 'khong_tai'}]
        t = toc.build('p', recs)
        m = RUNNER_TOC.search(t[:2000])
        self.assertEqual(m.groups(), ('5', '3', '2', '0'), 'tổng 5; 3 có .md; 2 có trang cần soát; 0 lỗi')
        self.assertIn('Ảnh đã nén: 1', t); self.assertIn('## Ảnh', t); self.assertIn('9 → 2', t)
        self.assertIn('| a.pdf | 3 |', t); self.assertIn('thiếu Tesseract', t)

    @unittest.skipUnless(real_ocr_cfg() and find_font(), 'cần Tesseract kèm dữ liệu vie và một phông có chữ Việt')
    def test_real_tesseract_reads_vietnamese_scan(self):
        import pymupdf
        cfg = real_ocr_cfg()
        src = pymupdf.open()
        pg = src.new_page()
        pg.insert_font(fontname='vn', fontfile=find_font())
        pg.insert_text((72, 120), 'Quyết định số 123/QĐ-UBND', fontname='vn', fontsize=26)
        pg.insert_text((72, 180), 'Hồ sơ giao đất đợt hai', fontname='vn', fontsize=26)
        pix = pg.get_pixmap(dpi=200)
        scan = pymupdf.open()
        sp = scan.new_page()
        sp.insert_image(sp.rect, pixmap=pix)                      # trang chỉ có hình = scan
        path = self.root / 'scan.pdf'
        scan.save(str(path))
        r = convert.convert_pdf(path, cfg, self.root)
        self.assertEqual((r.route, r.ocr_pages, r.scan_pages), ('B_ocr', [1], []))
        low = r.text.lower()
        self.assertIn('123', r.text)
        self.assertTrue('quyết định' in low or 'quyet dinh' in low, r.text)
        self.assertGreater(r.ocr_conf, 0.5)


class ImagesTest(Base):
    def png(self, name, size=(3000, 1500), mode='RGB', color=(200, 40, 40), exif=None):
        from PIL import Image
        p = self.root / name
        im = Image.new(mode, size, color)
        kw = {'exif': exif.tobytes()} if exif else {}
        im.save(p, **kw)
        return p

    def test_png_resized_to_2000_and_jpeg(self):
        from PIL import Image
        r = convert.convert_file(self.png('a.png'), 'a.png', self.cfg, self.root)
        self.assertEqual((r.status, r.kind, r.route), ('ok', 'image', 'image'))
        im = Image.open(io.BytesIO(r.data))
        self.assertEqual(im.format, 'JPEG'); self.assertEqual(max(im.size), 2000); self.assertEqual(im.size, (2000, 1000), 'giữ tỉ lệ')

    def test_small_image_not_upscaled_and_rgba_ok(self):
        from PIL import Image
        r = convert.convert_file(self.png('b.png', (400, 300), 'RGBA', (0, 0, 255, 128)), 'b.png', self.cfg, self.root)
        im = Image.open(io.BytesIO(r.data))
        self.assertEqual((im.format, im.mode, im.size), ('JPEG', 'RGB', (400, 300)))

    def test_exif_date_kept_and_orientation_applied(self):
        from PIL import Image
        ex = Image.Exif(); ex[0x0132] = '2025:08:27 10:15:00'; ex[0x0112] = 6        # xoay 90°
        p = self.png('c.jpg', (800, 400), exif=ex)
        r = convert.convert_file(p, 'c.jpg', self.cfg, self.root)
        out = Image.open(io.BytesIO(r.data))
        self.assertEqual(out.size, (400, 800), 'đã xoay đúng chiều')
        self.assertEqual(out.getexif().get(0x0132), '2025:08:27 10:15:00', 'giữ ngày chụp')
        self.assertEqual(out.getexif().get(0x0112), 1, 'không xoay lần hai')
        self.assertIn('2025:08:27', r.note)

    def test_heic_converted_to_jpeg_keeping_date(self):
        from PIL import Image
        try:
            import pillow_heif
            pillow_heif.register_heif_opener()
            ex = Image.Exif(); ex[0x0132] = '2024:12:01 08:00:00'
            p = self.root / 'd.heic'
            Image.new('RGB', (1200, 900), (10, 120, 200)).save(p, exif=ex.tobytes())
        except Exception as e:  # noqa: BLE001
            self.skipTest(f'pillow-heif không ghi được HEIC mẫu: {e}')
        r = convert.convert_file(p, 'd.heic', self.cfg, self.root)
        self.assertEqual(r.status, 'ok', r.reason)
        out = Image.open(io.BytesIO(r.data))
        self.assertEqual(out.format, 'JPEG'); self.assertEqual(out.getexif().get(0x0132), '2024:12:01 08:00:00')

    def test_size_cap_forces_more_compression(self):
        import random
        from PIL import Image
        random.seed(1)
        im = Image.frombytes('RGB', (1500, 1500), bytes(random.getrandbits(8) for _ in range(1500 * 1500 * 3)))   # nhiễu: khó nén
        p = self.root / 'noise.png'; im.save(p)
        cfg = Config({'TESSERACT_CMD': '', 'IMAGE_MAX_MB': '1'})
        r = convert.convert_file(p, 'noise.png', cfg, self.root)
        self.assertEqual(r.status, 'ok'); self.assertLessEqual(len(r.data), 1048576)

    def test_corrupt_image_is_error(self):
        p = self.root / 'hong.jpg'; p.write_bytes(b'khong phai anh')
        self.assertEqual(convert.convert_file(p, 'hong.jpg', self.cfg, self.root).status, 'error')

    def test_images_flow_through_run_next_to_markdown(self):
        s = self.root / 'n'; (s / 'ảnh hiện trường').mkdir(parents=True)
        self.png('x.png'); (self.root / 'x.png').replace(s / 'ảnh hiện trường' / 'IMG 01.png')
        make_docx(s / 'ảnh hiện trường' / 'IMG 01.docx', 'biên bản')            # trùng tên gốc với ảnh
        make_docx(s / 'Biên bản.docx', 'nội dung'); self.png('y.jpg', (500, 500)); (self.root / 'y.jpg').replace(s / 'Hiện trạng.jpg')
        fetch.fetch_local('p', s, self.cfg)
        st = run.run_project('p', self.cfg)
        self.assertEqual((st['total'], st['ok'], st['images'], st['error']), (4, 2, 2, 0))
        md = self.cfg.md('p')
        got = sorted(p.relative_to(md).as_posix() for p in md.rglob('*') if p.is_file())
        self.assertEqual(got, ['00_MUC_LUC.md', 'Biên bản.md', 'Hiện trạng.jpg', 'ảnh hiện trường/IMG 01.docx.md', 'ảnh hiện trường/IMG 01.png.jpg'])
        meta, _ = frontmatter.parse((md / 'ảnh hiện trường' / 'IMG 01.docx.md').read_text(encoding='utf-8'))
        self.assertEqual(meta['duong_dan'], 'ảnh hiện trường/IMG 01.docx')
        t = (md / '00_MUC_LUC.md').read_text(encoding='utf-8')
        self.assertIn('## Ảnh', t); self.assertIn('Ảnh đã nén: 2', t)
        from PIL import Image
        with Image.open(md / 'ảnh hiện trường' / 'IMG 01.png.jpg') as im:
            self.assertLessEqual(max(im.size), 2000)
        self.assertLessEqual(os.path.getsize(md / 'ảnh hiện trường' / 'IMG 01.png.jpg'), 10 * 1048576)

    def test_dwg_still_listed_not_downloaded(self):
        s = self.root / 'n2'; s.mkdir()
        (s / 'Bản vẽ.dwg').write_bytes(b'AC1027'); (s / 'Mặt bằng.dxf').write_bytes(b'0\nSECTION')
        fetch.fetch_local('q', s, self.cfg)
        mf = json.loads(self.cfg.manifest('q').read_text(encoding='utf-8'))['files']
        self.assertTrue(all(f['skip'] == 'khong_tai' and f['local'] == '' for f in mf))
        self.assertFalse((self.cfg.src('q') / 'Bản vẽ.dwg').exists())
        self.assertEqual(run.run_project('q', self.cfg)['skip'], 2)


if __name__ == '__main__':
    unittest.main()
