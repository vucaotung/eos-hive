"""Kiểm thử số đo benchmark OCR (thuần hàm; không cần PaddleOCR hay Tesseract)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from pipeline.bench import metrics, ocr_bench   # noqa: E402


class MetricsTest(unittest.TestCase):
    def test_identical_text_is_zero(self):
        r = metrics.compare('Quyết định số 12/QĐ-UBND', 'Quyết  định số 12/QĐ-UBND')   # khoảng trắng thừa không tính
        self.assertEqual((r['cer'], r['dia']), (0.0, 0))

    def test_diacritic_error_counted_separately(self):
        r = metrics.compare('đất nông nghiệp', 'dat nong nghiep')      # mất dấu
        self.assertEqual(r['sub'], 4); self.assertEqual(r['dia'], 4)      # đ, ấ, ô, ệ
        self.assertGreater(r['cer'], 0); self.assertEqual(r['cer'], r['dia_rate'])

    def test_non_diacritic_substitution_is_not_diacritic_error(self):
        r = metrics.compare('hồ sơ', 'hồ sở')
        self.assertEqual(r['sub'], 1); self.assertEqual(r['dia'], 1, 'ơ→ở cùng chữ gốc o: lỗi dấu')
        r = metrics.compare('hồ sơ', 'hồ sxơ')
        self.assertEqual((r['ins'], r['dia']), (1, 0))
        r = metrics.compare('abc', 'abd')
        self.assertEqual((r['sub'], r['dia']), (1, 0))

    def test_deletion_insertion(self):
        r = metrics.compare('abcd', 'abd')
        self.assertEqual((r['del'], r['ins']), (1, 0))
        self.assertAlmostEqual(r['cer'], 0.25)

    def test_nfc_equivalence(self):
        self.assertEqual(metrics.compare('á', 'á')['cer'], 0.0, 'dạng NFD và NFC coi là giống nhau')

    def test_dp_fallback_matches_default(self):
        a, b = 'hồ sơ giao đất', 'ho so giao dat'
        self.assertEqual([o[0] for o in metrics._ops_dp(a, b)].count('replace'),
                         [o[0] for o in metrics._ops(a, b)].count('replace'))

    def test_critical_tokens_and_misses(self):
        truth = 'Tổng mức 12.345.678.000 đồng theo Quyết định số 1234/QĐ-UBND và 56/2024/NĐ-CP, thêm 3,5 tỷ đồng.'
        t = metrics.critical_tokens(truth)
        self.assertTrue(any('12.345.678.000' in x for x in t['tien']))
        self.assertTrue(any('3,5 tỷ' in x for x in t['tien']))
        self.assertIn('1234/QĐ-UBND', t['so_van_ban']); self.assertIn('56/2024/NĐ-CP', t['so_van_ban'])
        hyp = 'Tong muc 12.345.678.000 dong theo Quyet dinh so 1234/QĐ-UBND va 56/2O24/NĐ-CP, them 3,5 ty dong.'
        m = metrics.token_misses(truth, hyp)
        self.assertEqual(m['so_van_ban'][1], 1, 'số 56/2024 bị đọc sai O thay 0')
        self.assertEqual(m['tien'][1], 1, '"3,5 tỷ" mất dấu → sai; số 12.345.678.000 đúng')


class ReportTest(unittest.TestCase):
    def test_summarize_and_markdown(self):
        rows = [{'model': 'm', 'id': 'a', 'sec': 2.0, 'conf': 0.9, 'chars': 10, 'error': '',
                 'metrics': {'chars': 100, 'sub': 3, 'del': 1, 'ins': 1, 'dia': 2}, 'tokens': {'tien': [2, 1, ['x']], 'so_van_ban': [1, 0, []]}},
                {'model': 'm', 'id': 'b', 'sec': 4.0, 'conf': 0.7, 'chars': 5, 'error': ''}]
        s = ocr_bench.summarize(rows, 1.23, 500, 'rec-x')
        self.assertEqual((s['sec_per_page'], s['cer'], s['dia_rate'], s['tien_sai']), (3.0, 0.05, 0.02, '1/2'))
        self.assertEqual(s['pages_with_truth'], 1)
        md = ocr_bench.report_md({'m': s, 'x': {'status': 'không dùng được', 'reason': 'thiếu vie'}}, 2)
        self.assertIn('| m | ok | 3.0 | 500 |', md); self.assertIn('thiếu vie', md)

    def test_no_truth_means_no_cer(self):
        s = ocr_bench.summarize([{'model': 'm', 'id': 'a', 'sec': 1.0, 'conf': None, 'chars': 1, 'error': ''}], 0.1, 100)
        self.assertNotIn('cer', s)
        self.assertIn('chưa có bản đúng', ocr_bench.report_md({'m': s}, 1))


if __name__ == '__main__':
    unittest.main()
