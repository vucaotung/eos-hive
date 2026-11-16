"""Mục lục 00_MUC_LUC.md. Dòng tổng PHẢI khớp biểu thức của runner (đọc 2000 ký tự đầu):
    Tổng (\\d+) file: (\\d+) đã có Markdown, (\\d+) file có trang cần soát OCR, (\\d+) lỗi
"""
REASON = {
    'khong_tai': 'Không tải (dwg, video, nén, tệp thiết kế): chỉ ghi tên, đường dẫn, link',
    'lien_ket_google': 'Lối tắt Google (.gdoc…): không có nội dung cục bộ',
    'anh_cho_pha_3': 'Ảnh: chưa xử lý (nén và nạp ảnh thuộc Pha 3)',
    'dinh_dang_chua_ho_tro': 'Định dạng chưa hỗ trợ',
    'qua_lon': 'Tệp quá lớn, không tải',
    'loi_tai': 'Không tải được từ Drive',
}


def _cell(s):
    return str(s if s is not None else '').replace('|', '\\|').replace('\n', ' ')


def build(slug, records, renames=()):
    """records: list dict {path, status(ok|skip|error), route, pages, scan_pages, ocr_conf, reason, drive_link}.
    renames: list (tên gốc, tên an toàn)."""
    ok = [r for r in records if r['status'] == 'ok']
    err = [r for r in records if r['status'] == 'error']
    skip = [r for r in records if r['status'] == 'skip']
    need = [r for r in ok if r.get('scan_pages')]
    out = [f'# Mục lục Markdown — {slug}', '',
           f'Tổng {len(records)} file: {len(ok)} đã có Markdown, {len(need)} file có trang cần soát OCR, {len(err)} lỗi.',
           f'Không chuyển đổi: {len(skip)} file (xem mục "Không chuyển đổi").', '',
           '| File nguồn | Trang | Route | OCR tin cậy % | Trang cần soát |', '|---|---|---|---|---|']
    for r in sorted(ok, key=lambda x: x['path']):
        conf = '' if r.get('ocr_conf') is None else f"{r['ocr_conf'] * 100:.0f}"
        out.append(f"| {_cell(r['path'])} | {r.get('pages') or ''} | {r.get('route', '')} | {conf} | {','.join(map(str, r.get('scan_pages') or []))} |")
    if need:
        out += ['', '## Cần soát', '', '| File nguồn | Trang scan chưa có chữ |', '|---|---|']
        out += [f"| {_cell(r['path'])} | {','.join(map(str, r['scan_pages']))} |" for r in sorted(need, key=lambda x: x['path'])]
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
