// Kiểm thử bộ phân tích "tạo nhanh một dòng" và nhập hàng loạt (chạy bằng node, không cần trình duyệt)
import assert from 'node:assert/strict';
import { parseQuick, parseBulk, remindAt, splitCsvLine } from '../ui/src/lib/quickadd.js';
const today = new Date(2030, 4, 15, 9, 0);   // Thứ Tư 15/05/2030
const ctx = { today, members: [{ id: 'u1', name: 'Nguyễn Minh Anh', email: 'minh@demo.vn' }, { id: 'u2', name: 'Trần Lan', email: 'lan@demo.vn' }, { id: 'u3', name: 'Lê Minh Tuấn', email: 'tuan@demo.vn' }, { id: 'u4', name: 'Mai Hoa', email: 'hoa@demo.vn' }], projects: [{ id: 'p1', name: 'Dự án Kho A' }, { id: 'p2', name: 'Dự án Kho B' }] };
let n = 0; const t = (name, fn) => { fn(); n++; console.log('  ✓', name); };
t('ví dụ của người dùng', () => { const q = parseQuick('Gửi báo giá @minh mai 17h !cao', ctx);
  assert.equal(q.title, 'Gửi báo giá'); assert.equal(q.assignee_id, null, '"minh" khớp hai người (Minh Anh, Minh Tuấn qua tên) nên mơ hồ'); assert.deepEqual(q.unknown, ['@minh']);
  assert.equal(q.due_date, '2030-05-16'); assert.equal(q.time, '17:00'); assert.equal(q.priority, 'high'); });
t('@ khớp theo phần trước @ của email hoặc từ trọn vẹn', () => { assert.equal(parseQuick('Việc @lan', ctx).assignee_id, 'u2'); assert.equal(parseQuick('Việc @tuan', ctx).assignee_id, 'u3'); assert.equal(parseQuick('Việc @Tuấn', ctx).assignee_id, 'u3'); assert.equal(parseQuick('Việc @anh', ctx).assignee_id, 'u1'); });
t('"Mai" viết hoa là tên người, không phải ngày', () => { const q = parseQuick('Báo cáo cho Mai mai', ctx); assert.equal(q.title, 'Báo cáo cho Mai'); assert.equal(q.due_date, '2030-05-16'); });
t('các cách viết ngày', () => { const d = (s) => parseQuick(`x ${s}`, ctx).due_date;
  assert.equal(d('hôm nay'), '2030-05-15'); assert.equal(d('ngày mai'), '2030-05-16'); assert.equal(d('ngày kia'), '2030-05-17'); assert.equal(d('thứ 6'), '2030-05-17'); assert.equal(d('thứ 4'), '2030-05-22', 'cùng thứ → tuần sau');
  assert.equal(d('thứ 2'), '2030-05-20'); assert.equal(d('cn'), '2030-05-19'); assert.equal(d('chủ nhật'), '2030-05-19'); assert.equal(d('tuần sau'), '2030-05-20'); assert.equal(d('20/5'), '2030-05-20'); assert.equal(d('1/3'), '2031-03-01', 'ngày đã qua → năm sau'); assert.equal(d('20/5/2031'), '2031-05-20'); assert.equal(d('+3'), '2030-05-18'); assert.equal(d('31/2'), ''); });
t('giờ: có/không có ngày', () => { assert.equal(parseQuick('x 17h30', ctx).time, '17:30'); assert.equal(parseQuick('x 17:05', ctx).time, '17:05'); assert.equal(parseQuick('x 17h', ctx).due_date, '2030-05-15', 'còn kịp hôm nay'); assert.equal(parseQuick('x 8h', ctx).due_date, '2030-05-16', 'đã qua giờ → mai'); assert.equal(parseQuick('x 25h', ctx).time, ''); });
t('nhãn, dự án, ước tính, cờ', () => { const q = parseQuick('Soạn #hợp-đồng #HĐ #hợp-đồng ^kho_a ~1h30 !qt !kc !khan', ctx);
  assert.deepEqual(q.tags, ['hợp-đồng', 'HĐ']); assert.equal(q.project_id, 'p1'); assert.equal(q.est, '90'); assert.equal(q.important, true); assert.equal(q.urgent, true); assert.equal(q.priority, 'urgent'); assert.equal(q.title, 'Soạn');
  assert.equal(parseQuick('x ^kho', ctx).project_id, null, 'mơ hồ'); assert.equal(parseQuick('x ~90p', ctx).est, '90'); assert.equal(parseQuick('x ~2h', ctx).est, '120'); });
t('tối đa 8 nhãn, tiêu đề giữ nguyên chữ lạ', () => { assert.equal(parseQuick('x ' + Array.from({ length: 12 }, (_, i) => '#t' + i).join(' '), ctx).tags.length, 8); assert.equal(parseQuick('Gọi 0912 345 678 !zzz', ctx).title, 'Gọi 0912 345 678 !zzz'); });
t('remindAt ghép ngày + giờ', () => { const r = remindAt('2030-05-16', '17:00'); assert.equal(new Date(r).getHours(), 17); assert.equal(remindAt('', '17:00'), null); });
t('CSV: ô có dấu nháy, phân cách ; hoặc tab', () => { assert.deepEqual(splitCsvLine('a,"b, c",d'), ['a', 'b, c', 'd']); assert.deepEqual(splitCsvLine('a;b;c'), ['a', 'b', 'c']); assert.deepEqual(splitCsvLine('a\tb\tc'), ['a', 'b', 'c']); assert.deepEqual(splitCsvLine('"x ""y"""'), ['x "y"']); });
t('dán danh sách: mỗi dòng một việc, bỏ gạch đầu dòng/số thứ tự', () => { const r = parseBulk('- Soạn hợp đồng @lan mai !cao\n2. Gọi khách #crm\n\n* Nộp thuế 20/5', ctx);
  assert.equal(r.length, 3); assert.equal(r[0].title, 'Soạn hợp đồng'); assert.equal(r[0].assignee_id, 'u2'); assert.equal(r[0].priority, 'high'); assert.equal(r[1].title, 'Gọi khách'); assert.deepEqual(r[1].tags, ['crm']); assert.equal(r[2].due_date, '2030-05-20'); });
t('CSV có dòng tiêu đề: cột tiêu đề tiếng Việt/Anh, báo dòng lạ', () => { const r = parseBulk('Tiêu đề,Người phụ trách,Hạn,Ưu tiên,Dự án,Nhãn\nSoạn báo giá,minh@demo.vn,20/5,cao,Dự án Kho A,"a;b"\nViệc lạ,ai-do@x.vn,không rõ,siêu cao,Dự án Z,', ctx);
  assert.equal(r.length, 2); assert.equal(r[0].assignee_id, 'u1'); assert.equal(r[0].due_date, '2030-05-20'); assert.equal(r[0].priority, 'high'); assert.equal(r[0].project_id, 'p1'); assert.deepEqual(r[0].tags, ['a', 'b']); assert.equal(r[0].warn.length, 0);
  assert.equal(r[1].warn.length, 4); assert.equal(r[1].row, 3); });
t('rỗng', () => { assert.deepEqual(parseBulk('', ctx), []); assert.equal(parseQuick('', ctx).title, ''); });
console.log(`quickadd: ${n} nhóm kiểm thử đạt`);
