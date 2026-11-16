"""Kiểm thử bộ kiểm Wiki (ops/wiki_lint.py, skill bao-tri-wiki): fixture Wiki giả có sẵn một liên kết hỏng và một mâu thuẫn số liệu; kiểm bắt được cả hai, và báo cáo đúng định dạng.
Không gọi model. Chạy: python3 -I ops/test/test_wiki_lint.py"""
import copy, importlib.util, json, os, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('wiki_lint', os.path.join(HERE, '..', 'wiki_lint.py'))
wl = importlib.util.module_from_spec(spec); spec.loader.exec_module(wl)
FIX = json.load(open(os.path.join(HERE, 'fixtures', 'wiki_demo.json'), encoding='utf8'))


def kinds(w): return [(f[0], f[1], f[2], f[3]) for f in wl.lint(w)[0]]


class WikiLint(unittest.TestCase):
    def test_bat_link_hong_va_mau_thuan_so_lieu(self):
        k = kinds(FIX)
        broken = [x for x in k if x[1] == 'link_hong']
        self.assertEqual(len(broken), 1); self.assertEqual(broken[0][2], 'Khảo sát địa chất'); self.assertIn('Báo cáo đánh giá tác động môi trường', broken[0][3])
        conflict = [x for x in k if x[1] == 'so_lieu_mau_thuan']
        self.assertEqual(len(conflict), 1); self.assertEqual(conflict[0][0], 'Cao')
        self.assertIn('120 tỷ', conflict[0][3]); self.assertIn('135 tỷ', conflict[0][3]); self.assertIn('QD-01.md', conflict[0][3])
        self.assertIn('Quyết định phê duyệt dự án', conflict[0][2])
        self.assertFalse([x for x in k if 'diện tích' in x[3].lower()], 'diện tích giống nhau không phải mâu thuẫn')

    def test_cac_loai_con_lai_tren_fixture(self):
        k = kinds(FIX)
        self.assertTrue(any(x[1] == 'orphan' and x[2] == 'Biên bản họp giao ban' and x[0] == 'Thấp' for x in k))
        self.assertTrue(any(x[1] == 'chi_muc_lech' and x[3] == 'HD-05.md' for x in k), 'tài liệu mới nạp không trang nào nhắc')
        self.assertTrue(any(x[1] == 'thieu_buoc' and x[3] == 'Bước 02' and x[0] == 'Cao' for x in k), '"đã có" không dẫn văn bản')
        self.assertFalse(any(x[1] == 'thieu_buoc' and x[3] in ('Bước 01', 'Bước 09') for x in k), 'bước có dẫn trang/tệp thì không báo')

    def test_mau_thuan_da_danh_dau_thi_khong_bao_lai(self):
        w = copy.deepcopy(FIX); w['pages'][2]['body'] += '\nGhi chú: tổng mức đầu tư mâu thuẫn với trang tổng quan, chờ chốt.\n'
        self.assertFalse([x for x in kinds(w) if x[1] == 'so_lieu_mau_thuan'])

    def test_trang_cu_trung_chu_the_tai_lieu_bi_thay(self):
        w = copy.deepcopy(FIX)
        w['documents'][1]['ingested'] = '2026-11-12'                         # KS-01 mới hơn trang Khảo sát địa chất
        w['documents'].append({'name': 'QD-01-v2.md', 'ingested': '2026-11-13', 'superseded_by': None}); w['documents'][0]['superseded_by'] = 'QD-01-v2.md'
        w['pages'].append({'title': 'khao sat dia chat', 'kind': 'page', 'updated': '2026-11-14', 'sources': ['KS-01.md'], 'body': 'Bản trùng. [[Tổng quan dự án KDC Thành Lập]]'})
        k = kinds(w)
        self.assertTrue(any(x[1] == 'trang_cu' and x[2] == 'Khảo sát địa chất' for x in k))
        self.assertTrue(any(x[1] == 'trung_chu_the' for x in k))
        self.assertTrue(any(x[1] == 'chi_muc_lech' and x[3] == 'QD-01.md' and 'bị thay' in ' '.join(map(str, wl.lint(w)[0])) for x in k), 'trang trích tài liệu đã bị thay')

    def test_wiki_sach_khong_co_phat_hien(self):
        w = {'kb': 'KB sạch', 'date': '2026-11-16', 'documents': [{'name': 'A.md', 'ingested': '2026-10-01', 'superseded_by': None}],
             'pages': [{'title': 'Tổng quan', 'kind': 'overview', 'updated': '2026-10-02', 'sources': ['A.md'], 'body': '\n'.join(f'- Bước {i:02d}: chưa có hồ sơ' for i in range(1, 21)) + '\n[[Chi tiết]]'},
                       {'title': 'Chi tiết', 'kind': 'page', 'updated': '2026-10-02', 'sources': ['A.md'], 'body': '[[Tổng quan]]'}]}
        self.assertEqual(wl.lint(w)[0], [])

    def test_bao_cao_dung_dinh_dang(self):
        txt = wl.report(FIX)
        self.assertEqual(wl.validate_report(txt), [])
        self.assertLess(txt.index('## Mức Cao'), txt.index('## Mức Trung bình')); self.assertLess(txt.index('## Mức Trung bình'), txt.index('## Mức Thấp'))
        self.assertIn('Cao: 2 · Trung bình: 2 · Thấp: 1', txt)
        self.assertRegex(txt, r'\| tổng mức đầu tư \| 120 tỷ đồng ← QD-01\.md; 135 tỷ đồng ← QD-01\.md \|')   # đề xuất đưa vào Fact Registry
        self.assertEqual(wl.validate_report(wl.report({'kb': 'x', 'date': 'd', 'pages': [], 'documents': []})), [])

    def test_validator_bat_loi_dinh_dang(self):
        txt = wl.report(FIX)
        self.assertTrue(wl.validate_report(txt.replace('## Mức Trung bình', '## Mức vừa')))
        self.assertTrue(wl.validate_report(txt.replace('- Nguồn: [[Báo cáo', '- Nguồn:\n[[Báo cáo')))
        self.assertTrue(wl.validate_report(txt.replace('loại: link_hong', 'loại: la')))
        self.assertTrue(wl.validate_report('# vô nghĩa'))


if __name__ == '__main__':
    unittest.main()
