import io, os, sys, unittest, contextlib
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import eos_report as R

D = {'company': 'Valnex', 'scope': 'Toàn công ty', 'date': '2026-10-24', 'days': 1,
     'counts': {'open': 12, 'overdue': 3, 'due_today': 2, 'due_3d': 1, 'blocked': 1, 'ask_human': 1, 'in_review': 2, 'done_period': 4, 'created_period': 5},
     'overdue': [{'id': 'T-1', 'title': 'Soạn công văn', 'who': 'Minh', 'due': '2026-10-20', 'days_late': 4, 'status': 'todo'}, {'id': 'T-2', 'title': 'Việc chưa giao', 'who': None, 'due': '2026-10-21', 'days_late': 3, 'status': 'todo'}],
     'due_today': [{'id': 'T-3', 'title': 'Họp giao ban', 'who': 'Lan'}], 'need_you': [{'id': 'T-4', 'title': 'Duyệt bảng khối lượng', 'kind': 'chờ duyệt'}],
     'done_period': [{'id': 'T-5', 'title': 'Báo cáo tuần', 'who': 'Minh'}], 'by_dept': [{'dept': 'HC', 'open': 8, 'overdue': 2}], 'by_person': [{'who': 'Minh', 'open': 5, 'overdue': 2}],
     'projects': [{'name': 'Khu nhà ở Phú Hải', 'open': 3, 'overdue': 0, 'run': 'running'}], 'agents': {'running': 1, 'blocked': 2, 'stuck_2h': 0, 'outbox_pending': 0}}


class T(unittest.TestCase):
    def test_daily(self):
        t = R.render(D)
        for s in ['Bản tin sáng 24/10', 'Công việc đang thực hiện 12', 'Quá hạn 3', 'T-1 Soạn công văn (Minh, trễ 4 ngày)', 'chưa giao, trễ 3 ngày', 'Đến hạn hôm nay:', 'T-4 Duyệt bảng khối lượng [chờ duyệt]',
                  'Đã xong hôm qua', 'HC 8 công việc, 2 quá hạn', 'đang nạp hồ sơ', 'đang chờ người 2', 'https://work.enterpriseos.bond/app/']:
            self.assertIn(s, t, s)
        self.assertNotIn('Theo người', t)

    def test_weekly(self):
        t = R.render(D, True)
        self.assertIn('Tổng kết tuần', t); self.assertIn('Theo người: Minh 5 công việc, 2 quá hạn', t); self.assertNotIn('Đến hạn hôm nay:', t); self.assertIn('trong tuần', t)

    def test_limits_and_length(self):
        big = dict(D, overdue=[{'id': f'T-{i}', 'title': 'x' * 90, 'who': 'A', 'days_late': 1} for i in range(12)])
        t = R.render(big)
        self.assertIn('và 4 việc nữa', t); self.assertLessEqual(len(t), 3900)

    def test_member_scope_has_no_agents_or_dept(self):
        d = dict(D, scope='Việc của tôi', agents=None, by_dept=[], by_person=[], projects=[])
        t = R.render(d); self.assertNotIn('Agent:', t); self.assertNotIn('Theo phòng', t)

    def test_missing_token_warns_and_exits_zero(self):
        os.environ.pop('EOS_REPORT_TOKEN', None)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = R.main(['daily'])
        self.assertEqual(rc, 0); self.assertIn('thiếu EOS_REPORT_TOKEN', buf.getvalue())

    def test_network_error_message_hides_token(self):
        os.environ['EOS_REPORT_TOKEN'] = 'eos_' + 'a' * 48
        os.environ['EOS_MCP_URL'] = 'http://127.0.0.1:9/mcp'
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = R.main(['weekly'])
        self.assertEqual(rc, 0); self.assertIn('không lấy được dữ liệu', buf.getvalue()); self.assertNotIn('eos_a', buf.getvalue())

    def test_bad_mode(self):
        self.assertEqual(R.main(['monthly']), 2)


if __name__ == '__main__':
    unittest.main()
