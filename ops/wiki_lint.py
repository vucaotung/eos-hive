#!/usr/bin/env python3
"""Bộ kiểm Wiki tham chiếu (skill bao-tri-wiki): kiểm 7 loại vấn đề trên bản xuất Wiki dạng JSON và sinh báo cáo Markdown theo mẫu của skill.

Agent không có terminal; script này là **bản mô tả chính xác từng phép kiểm** (để người xem trước kết quả, để test kiểm định dạng báo cáo mà không gọi model).
CHỈ ĐỌC: không sửa Wiki. Dùng: python3 ops/wiki_lint.py wiki.json [> bao-cao.md]

Định dạng đầu vào:
{"kb": "Tên KB", "date": "YYYY-MM-DD",
 "pages": [{"title": "...", "kind": "overview|page", "subject": "chủ thể (tùy chọn)", "updated": "YYYY-MM-DD", "sources": ["tên-tệp.md"], "body": "Markdown, liên kết nội bộ dạng [[Tên trang]]"}],
 "documents": [{"name": "tên-tệp.md", "ingested": "YYYY-MM-DD", "superseded_by": null | "tên-tệp-mới.md"}]}
"""
import json, re, sys, unicodedata

STEPS = [f"{i:02d}" for i in range(1, 21)]
LABELS = {  # chỉ tiêu cần cảnh báo khi hai trang ghi giá trị khác nhau mà chưa đánh dấu "mâu thuẫn"
    'tong_muc_dau_tu': r'tổng mức đầu tư', 'dien_tich': r'diện tích', 'ngay_cap_phep': r'ngày cấp phép',
}
SEV = ('Cao', 'Trung bình', 'Thấp')
KINDS = {'orphan': 'trang mồ côi', 'link_hong': 'liên kết hỏng', 'chi_muc_lech': 'chỉ mục lệch', 'trung_chu_the': 'trùng chủ thể',
         'so_lieu_mau_thuan': 'số liệu mâu thuẫn', 'trang_cu': 'trang cũ hơn tài liệu', 'thieu_buoc': 'tổng quan thiếu bước / ghi "đã có" không dẫn văn bản'}


def norm(s):
    s = unicodedata.normalize('NFD', s.lower().replace('đ', 'd'))
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9 ]+', ' ', ''.join(c for c in s if unicodedata.category(c) != 'Mn'))).strip()


def links(p):
    return [m.strip() for m in re.findall(r'\[\[([^\]]+)\]\]', p.get('body', ''))]


def lint(w):
    pages, docs = w.get('pages', []), {d['name']: d for d in w.get('documents', [])}
    titles = {norm(p['title']): p for p in pages}
    F = []  # (mức, loại, trang, nguồn, mô tả, đề nghị)
    add = lambda sev, kind, page, src, desc, fix: F.append((sev, kind, page, src, desc, fix))
    overview = [p for p in pages if p.get('kind') == 'overview']
    inbound = {norm(p['title']): 0 for p in pages}
    for p in pages:
        for l in links(p):
            if norm(l) in titles and titles[norm(l)] is not p: inbound[norm(l)] += 1
    # 1. mồ côi: không trang nào liên kết tới và không nối về tổng quan
    for p in pages:
        if p.get('kind') == 'overview': continue
        back = any(norm(l) == norm(o['title']) for o in overview for l in links(p))
        if inbound[norm(p['title'])] == 0 and not back:
            add('Thấp', 'orphan', p['title'], ', '.join(p.get('sources') or ['(không ghi nguồn)']), 'Không trang nào liên kết tới và trang không nối về trang tổng quan dự án.', 'Thêm liên kết từ trang tổng quan hoặc trang cùng chủ đề (người quản trị Wiki thực hiện).')
    # 2. liên kết hỏng
    for p in pages:
        for l in links(p):
            if norm(l) not in titles:
                add('Trung bình', 'link_hong', p['title'], f'[[{l}]]', f'Liên kết tới trang "{l}" không tồn tại.', 'Tạo trang còn thiếu hoặc sửa liên kết.')
    # 3. chỉ mục lệch: tài liệu hiện hành không trang nào trích; trang trích tài liệu đã bị thay bằng bản mới
    cited = {s for p in pages for s in (p.get('sources') or [])}
    for n, d in docs.items():
        if not d.get('superseded_by') and n not in cited:
            add('Trung bình', 'chi_muc_lech', '(không trang nào)', n, 'Tài liệu đã nạp nhưng không trang Wiki nào nhắc tới.', 'Kiểm tài liệu có được Wiki xử lý chưa; nếu chưa, chạy lại bước tạo Wiki cho tài liệu này.')
    for p in pages:
        for s in p.get('sources') or []:
            d = docs.get(s)
            if d and d.get('superseded_by'):
                add('Trung bình', 'chi_muc_lech', p['title'], s, f'Trang trích tài liệu đã bị thay bằng bản mới ({d["superseded_by"]}).', 'Cập nhật trang theo bản mới.')
    # 4. trùng chủ thể
    seen = {}
    for p in pages:
        key = norm(p.get('subject') or p['title'])
        if key in seen:
            add('Trung bình', 'trung_chu_the', f'{seen[key]["title"]} / {p["title"]}', ', '.join((seen[key].get('sources') or []) + (p.get('sources') or [])), 'Hai trang cùng chủ thể.', 'Gộp vào một trang, giữ một nguồn chính và liệt kê nguồn phụ.')
        else: seen[key] = p
    # 5. số liệu mâu thuẫn chưa đánh dấu
    vals = {}
    for p in pages:
        for line in p.get('body', '').splitlines():
            for k, pat in LABELS.items():
                m = re.search(pat + r'\s*[:\-–]\s*([^\n|;]+)', line, re.I)
                if m: vals.setdefault(k, []).append((p, re.sub(r'\s+', ' ', m.group(1)).strip().rstrip('.'), line))
    for k, lst in vals.items():
        distinct = {norm(v) for _, v, _ in lst}
        if len(distinct) > 1 and not any(re.search(r'mâu thuẫn', ln, re.I) or re.search(r'mâu thuẫn', p.get('body', ''), re.I) for p, _, ln in lst):
            pg = ' / '.join(dict.fromkeys(p['title'] for p, _, _ in lst))
            src = '; '.join(f'{v} ← {", ".join(p.get("sources") or [p["title"]])}' for p, v, _ in lst)
            add('Cao', 'so_lieu_mau_thuan', pg, src, f'Chỉ tiêu "{LABELS[k]}" có giá trị khác nhau giữa các trang và chưa được đánh dấu "mâu thuẫn".', 'Ghi cả hai giá trị kèm nguồn, đánh dấu "mâu thuẫn"; đề xuất đưa vào Fact Registry để người có thẩm quyền chốt.')
    # 6. trang cũ hơn tài liệu liên quan mới nạp
    for p in pages:
        for s in p.get('sources') or []:
            d = docs.get(s)
            if d and d.get('ingested') and p.get('updated') and d['ingested'] > p['updated']:
                add('Trung bình', 'trang_cu', p['title'], s, f'Trang cập nhật {p["updated"]} nhưng tài liệu liên quan nạp {d["ingested"]}.', 'Cập nhật trang theo tài liệu mới.')
    # 7. tổng quan thiếu bước / "đã có" không dẫn văn bản
    for o in overview:
        found = {}
        for line in o.get('body', '').splitlines():
            m = re.match(r'\s*[-*]?\s*(?:Bước\s*)?(\d{2})\b[^:]*:\s*(.*)', line)
            if m and m.group(1) in STEPS: found[m.group(1)] = m.group(2)
        miss = [s for s in STEPS if s not in found]
        if miss: add('Trung bình', 'thieu_buoc', o['title'], '—', f'Trang tổng quan thiếu bước: {", ".join(miss)}.', 'Bổ sung đủ 20 bước (ghi "chưa có hồ sơ" nếu chưa có).')
        for s, txt in found.items():
            if re.search(r'đã có', txt, re.I) and not re.search(r'\[\[|\[[^\]]+\.(md|pdf)\]|https?://', txt):
                add('Cao', 'thieu_buoc', o['title'], f'Bước {s}', f'Bước {s} ghi "đã có" nhưng không dẫn văn bản.', 'Dẫn số hiệu/tên tệp hoặc trang Wiki chứng minh, hoặc đổi thành "chưa có hồ sơ".')
    return F, vals


def report(w):
    F, vals = lint(w)
    cnt = {s: sum(1 for f in F if f[0] == s) for s in SEV}
    out = [f'# Báo cáo rà Wiki — {w.get("kb", "?")} — {w.get("date", "?")}', '', '## Tóm tắt',
           f'Cao: {cnt["Cao"]} · Trung bình: {cnt["Trung bình"]} · Thấp: {cnt["Thấp"]} · Trang đã rà: {len(w.get("pages", []))} · Tài liệu đối chiếu: {len(w.get("documents", []))}', '']
    n = 0
    for s in SEV:
        out += [f'## Mức {s}', '']
        items = [f for f in F if f[0] == s]
        if not items: out += ['(không có)', '']
        for sev, kind, page, src, desc, fix in items:
            n += 1
            out += [f'### [W-{n:02d}] {KINDS[kind]} — loại: {kind}', f'- Trang: {page}', f'- Nguồn: {src}', f'- Mô tả: {desc}', f'- Đề nghị: {fix}', '']
    out += ['## Đề xuất đưa vào Fact Registry', '', '| Chỉ tiêu | Giá trị (nguồn) | Đề xuất |', '| --- | --- | --- |']
    rows = [f for f in F if f[1] == 'so_lieu_mau_thuan']
    for f in rows: out.append(f'| {f[4].split(chr(34))[1]} | {f[3]} | Người có thẩm quyền chốt giá trị chính thức, ghi nguồn |')
    if not rows: out.append('| (không có) | | |')
    out += ['', '## Không kiểm được', '- (ghi các phép kiểm không làm được và lý do; không có thì ghi "không")', '']
    return '\n'.join(out)


REQUIRED = ['# Báo cáo rà Wiki — ', '## Tóm tắt', '## Mức Cao', '## Mức Trung bình', '## Mức Thấp', '## Đề xuất đưa vào Fact Registry', '## Không kiểm được']


def validate_report(text):
    """Trả danh sách lỗi định dạng (rỗng = đạt): đủ mục theo thứ tự, mỗi phát hiện có loại hợp lệ, tên trang và nguồn."""
    errs = []
    pos = [text.find(h) for h in REQUIRED]
    if -1 in pos: errs += [f'thiếu mục "{h}"' for h, p in zip(REQUIRED, pos) if p == -1]
    elif pos != sorted(pos): errs.append('các mục sai thứ tự')
    for blk in re.split(r'\n(?=### \[W-)', text)[1:]:
        head = blk.splitlines()[0]
        m = re.search(r'loại: (\w+)', head)
        if not m or m.group(1) not in KINDS: errs.append(f'phát hiện sai loại: {head}')
        if not re.search(r'^- Trang: \S', blk, re.M): errs.append(f'thiếu "Trang" ở {head}')
        if not re.search(r'^- Nguồn: \S', blk, re.M): errs.append(f'thiếu "Nguồn" ở {head}')
    # mức nghiêm trọng đúng thứ tự: mọi [W-..] của Cao nằm trước mục Trung bình...
    return errs


if __name__ == '__main__':
    print(report(json.load(open(sys.argv[1], encoding='utf8'))))
