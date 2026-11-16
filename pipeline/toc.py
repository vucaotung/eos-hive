"""Mục lục 00_MUC_LUC.md. Dòng tổng PHẢI khớp biểu thức của runner (đọc 2000 ký tự đầu):
    Tổng (\\d+) file: (\\d+) đã có Markdown, (\\d+) file có trang cần soát OCR, (\\d+) lỗi

Định nghĩa: "Tổng" = mọi tệp nguồn (kể cả ảnh và tệp không chuyển đổi); "đã có Markdown" = tệp cho ra .md;
"cần soát OCR" = tệp .md có trang OCR dưới ngưỡng tin cậy hoặc trang scan chưa OCR được.
"""
REASON = {
    'khong_tai': 'Không tải (dwg, video, nén, tệp thiết kế): chỉ ghi tên, đường dẫn, link',
    'lien_ket_google': 'Lối tắt Google (.gdoc…): không có nội dung cục bộ',
    'dinh_dang_chua_ho_tro': 'Định dạng chưa hỗ trợ',
    'qua_lon': 'Tệp quá lớn, không tải',
    'loi_tai': 'Không tải được từ Drive',
}


def _cell(s):
    return str(s if s is not None else '').replace('|', '\\|').replace('\n', ' ')


def _pages(p):
    return ','.join(map(str, p or []))


def _is_md(r):
    return r['status'] == 'ok' and r.get('kind', 'md') == 'md'


def _flag(r):
    """Trang cần soát: OCR dưới ngưỡng + trang scan chưa OCR được."""
    return sorted(set(r.get('review_pages') or []) | set(r.get('scan_pages') or []))


def counts(records):
    md = [r for r in records if _is_md(r)]
    return {'total': len(records), 'ok': len(md), 'error': sum(1 for r in records if r['status'] == 'error'),
            'skip': sum(1 for r in records if r['status'] == 'skip'),
            'images': sum(1 for r in records if r['status'] == 'ok' and r.get('kind') == 'image'),
            'need_ocr': sum(1 for r in md if _flag(r))}


def build(slug, records, renames=()):
    """records: list dict {path, status, kind, route, pages, scan_pages, review_pages, ocr_conf, reason, note, bytes, src_bytes, drive_link}.
    renames: list (tên gốc, tên an toàn)."""
    c = counts(records)
    md = [r for r in records if _is_md(r)]
    imgs = [r for r in records if r['status'] == 'ok' and r.get('kind') == 'image']
    err = [r for r in records if r['status'] == 'error']
    skip = [r for r in records if r['status'] == 'skip']
    need = [r for r in md if _flag(r)]
    out = [f'# Mục lục Markdown — {slug}', '',
           f"Tổng {c['total']} file: {c['ok']} đã có Markdown, {c['need_ocr']} file có trang cần soát OCR, {c['error']} lỗi.",
           f"Ảnh đã nén: {c['images']}. Không chuyển đổi: {c['skip']} file (xem mục \"Không chuyển đổi\").", '',
           '| File nguồn | Trang | Route | OCR tin cậy % | Trang cần soát |', '|---|---|---|---|---|']
    for r in sorted(md, key=lambda x: x['path']):
        conf = '' if r.get('ocr_conf') is None else f"{r['ocr_conf'] * 100:.0f}"
        out.append(f"| {_cell(r['path'])} | {r.get('pages') or ''} | {r.get('route', '')} | {conf} | {_pages(_flag(r))} |")
    if need:
        out += ['', '## Cần soát', '', 'Trang OCR có độ tin cậy dưới ngưỡng, hoặc trang scan chưa có chữ (không OCR được).', '',
                '| File nguồn | Trang cần soát | Ghi chú |', '|---|---|---|']
        out += [f"| {_cell(r['path'])} | {_pages(_flag(r))} | {_cell(r.get('note'))} |" for r in sorted(need, key=lambda x: x['path'])]
    if imgs:
        out += ['', '## Ảnh', '', '| File nguồn | Tệp đầu ra | KB gốc → KB nén | Ghi chú |', '|---|---|---|---|']
        out += [f"| {_cell(r['path'])} | {_cell(r.get('out'))} | {round((r.get('src_bytes') or 0) / 1024)} → {round((r.get('bytes') or 0) / 1024)} | {_cell(r.get('note'))} |"
                for r in sorted(imgs, key=lambda x: x['path'])]
    if err:
        out += ['', '## Lỗi', '', '| File nguồn | Lỗi |', '|---|---|']
        out += [f"| {_cell(r['path'])} | {_cell(r.get('reason'))} |" for r in sorted(err, key=lambda x: x['path'])]
    if skip:
        out += ['', '## Không chuyển đổi', '', '| File nguồn | Lý do | Link |', '|---|---|---|']
        out += [f"| {_cell(r['path'])} | {_cell(REASON.get(r.get('reason'), r.get('reason')))} | {r.get('drive_link') or ''} |"
                for r in sorted(skip, key=lambda x: x['path'])]
    if renames:
        out += ['', '## Đã đổi tên (ký tự Windows cấm)', '', '| Tên gốc trên Drive | Tên khi ghi |', '|---|---|']
        out += [f'| {_cell(a)} | {_cell(b)} |' for a, b in renames]
    return '\n'.join(out) + '\n'
