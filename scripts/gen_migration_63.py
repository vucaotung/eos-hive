#!/usr/bin/env python3
"""Sinh migration từ một PHẦN của db/63_features.sql (giữ migration và tệp nguồn luôn giống nhau).
Dùng: scripts/gen_migration_63.py <chữ-cái-phần> <số-migration> <slug> "<mô tả>" [--pre "<SQL chạy trước>"] [--grant "<SQL cấp quyền>"]"""
import re, sys, pathlib
a = sys.argv[1:]
part, num, slug, desc = a[0], a[1], a[2], a[3]
pre = a[a.index('--pre') + 1] if '--pre' in a else ''
fn61 = a[a.index('--fn61') + 1].split(',') if '--fn61' in a else []   # hàm lấy nguyên văn từ db/61_app.sql (nguồn chính của chúng)
grant = a[a.index('--grant') + 1] if '--grant' in a else ''
src = pathlib.Path(__file__).resolve().parent.parent / 'db' / '63_features.sql'
t = src.read_text(encoding='utf-8')
m = re.search(r'-- ==== PHẦN %s:.*?-- ==== HẾT PHẦN %s ====\n' % (part, part), t, re.S)
if not m: sys.exit('Không thấy PHẦN %s' % part)
t61 = (src.parent / '61_app.sql').read_text(encoding='utf-8'); extra = ''
for fn in fn61:
    i = t61.index('CREATE OR REPLACE FUNCTION ' + fn + '('); j = t61.index('END $$;', i) + len('END $$;'); extra += t61[i:j] + '\n'
out = pathlib.Path(__file__).resolve().parent.parent / 'db' / 'migrations' / f'{num}_{slug}.sql'
out.write_text(f"""-- {num} · {desc}
-- Nguồn chính: db/63_features.sql (PHẦN {part}). Idempotent.
BEGIN;
{pre}
{extra}{m.group(0)}{grant}
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA agent FROM PUBLIC;
COMMIT;
""", encoding='utf-8')
print('đã ghi', out)
