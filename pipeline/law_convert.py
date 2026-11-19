"""Chuyển MỘT tệp văn bản pháp luật (đã tải từ nguồn chính thống) sang Markdown cho máy chủ MCP.

Dùng: python -m pipeline.law_convert <đường dẫn tệp> <pdf|docx|doc|html>
In ra stdout đúng một dòng JSON: {"ok": true, "text": ..., "converter": ..., "pages": n} hoặc {"ok": false, "error": ...}.

Khác với chuyển hồ sơ dự án: văn bản pháp luật phải là NGUYÊN VĂN có lớp chữ. Trang scan cần OCR bị từ chối
(OCR không đủ tin cậy cho nguyên văn luật); dấu [[trang N]] của PDF được bỏ để thân văn bản liền mạch.
"""
import json
import re
import sys
import tempfile
from pathlib import Path

from . import convert
from .config import Config

KINDS = {'pdf': '.pdf', 'docx': '.docx', 'doc': '.doc', 'html': '.html'}
PAGE_MARK = re.compile(r'^\[\[trang \d+\]\]\s*$', re.M)


def _key(line):
    return re.sub(r'[\s*_#|]+', ' ', line).strip().lower()


def strip_running_heads(text, edge=3):
    """Bỏ tiêu đề/chân trang lặp của bản in (vd. "CÔNG BÁO/Số 37/Ngày …", số trang): xét `edge` dòng đầu và cuối mỗi trang;
    dòng ngắn xuất hiện ở mép từ 30% số trang trở lên (tối thiểu 3 trang) hoặc dòng chỉ có số thì bỏ. Văn bản không có dấu trang giữ nguyên."""
    pages = re.split(r'^\[\[trang \d+\]\]\s*$', text, flags=re.M)
    pages = [p for p in pages if p.strip()]
    if len(pages) < 3:
        return text
    edges = []
    for p in pages:
        lines = [x for x in p.split('\n') if x.strip()]
        edges.append(lines[:edge] + lines[-edge:])
    freq = {}
    for e in edges:
        for k in {_key(x) for x in e if len(_key(x)) <= 100}:
            freq[k] = freq.get(k, 0) + 1
    need = max(3, int(len(pages) * 0.3))
    heads = {k for k, n in freq.items() if n >= need}
    out = []
    for p, e in zip(pages, edges):
        drop = {x for x in e if _key(x) in heads or re.fullmatch(r'\d{1,4}', _key(x))}
        out.append('\n'.join(x for x in p.split('\n') if x not in drop))
    return '\n\n'.join(out)


def clean(text):
    """Bỏ tiêu đề/chân trang lặp, dấu trang, gộp dòng trống thừa, bỏ khoảng trắng cuối dòng."""
    t = strip_running_heads(text.replace('\r\n', '\n'))
    t = PAGE_MARK.sub('', t)
    t = '\n'.join(line.rstrip() for line in t.split('\n'))
    return re.sub(r'\n{3,}', '\n\n', t).strip() + '\n'


def judge(res):
    """Kết quả chuyển đổi → (ok, text|lý do). Tách riêng để test không cần thư viện chuyển đổi."""
    if res.status != 'ok':
        return False, f'Không chuyển được tệp ({res.reason or res.status})'
    if res.scan_pages or res.ocr_pages:
        pages = sorted(set(res.scan_pages) | set(res.ocr_pages))
        head = ', '.join(map(str, pages[:10])) + ('…' if len(pages) > 10 else '')
        return False, (f'Tệp có {len(pages)} trang scan không có lớp chữ (trang {head}). Không dùng OCR cho nguyên văn pháp luật: '
                       'tìm bản số hoá có lớp chữ (Công báo số DOCX/PDF, vbpl.vn).')
    text = clean(res.text)
    if len(text) < 200:
        return False, 'Tệp gần như không có chữ sau khi chuyển đổi'
    return True, text


def run(path, kind, cfg=None):
    cfg = cfg or Config()
    ext = KINDS.get(kind)
    if not ext:
        return {'ok': False, 'error': f'Loại tệp không hỗ trợ: {kind}'}
    with tempfile.TemporaryDirectory(prefix='law-') as tmp:
        src = Path(tmp) / f'van-ban{ext}'                       # tên có đuôi đúng để bộ chuyển chọn đường
        src.write_bytes(Path(path).read_bytes())
        if kind == 'html':
            try:
                res = convert.Result('ok', 'A_native', f'markitdown {convert._version("markitdown")}', text=convert._markitdown(src))
            except Exception as ex:  # noqa: BLE001
                res = convert.Result('error', reason=f'{type(ex).__name__}: {str(ex)[:300]}')
        else:
            cfg.tesseract = ''                                   # không OCR: trang scan bị báo, không đoán chữ
            res = convert.convert_file(src, src.name, cfg, tmp)
    ok, out = judge(res)
    return {'ok': True, 'text': out, 'converter': res.converter, 'pages': res.pages} if ok else {'ok': False, 'error': out}


def main(argv):
    if len(argv) != 3:
        print(json.dumps({'ok': False, 'error': 'Dùng: python -m pipeline.law_convert <tệp> <pdf|docx|doc|html>'}))
        return 2
    try:
        out = run(argv[1], argv[2])
    except Exception as ex:  # noqa: BLE001 — luôn trả JSON cho máy chủ MCP
        out = {'ok': False, 'error': f'{type(ex).__name__}: {str(ex)[:300]}'}
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + '\n')
    return 0 if out.get('ok') else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv))
