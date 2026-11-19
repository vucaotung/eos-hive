"""Chuyển MỘT tệp văn bản pháp luật (đã tải từ nguồn chính thống) sang Markdown cho máy chủ MCP.

Dùng: python -m pipeline.law_convert <đường dẫn tệp> <pdf|docx|doc|html>
In ra stdout đúng một dòng JSON: {"ok": true, "text": ..., "converter": ..., "refs": [số hiệu dẫn chiếu]} hoặc {"ok": false, "error": ...}.

Khác với chuyển hồ sơ dự án: văn bản pháp luật phải là NGUYÊN VĂN có lớp chữ. Trang scan cần OCR bị từ chối
(OCR không đủ tin cậy cho nguyên văn luật). Trọng tâm là CẤU TRÚC: # Chương / Phụ lục, ## Mục, ### Điều, khoản và điểm
mỗi cái một đoạn, bảng giữ dạng bảng Markdown. Không giữ số trang, tiêu đề/chân trang của bản in.
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


ROMAN = r'[IVXLC]+'
RE_CHUONG = re.compile(rf'^(?:Chương|CHƯƠNG)\s+({ROMAN}|\d+)\b\.?\s*(.*)$')
RE_MUC = re.compile(r'^(?:Mục|MỤC)\s+(\d+)\b\.?\s*(.*)$')
RE_DIEU = re.compile(r'^(?:Điều|ĐIỀU)\s+(\d+[a-zđ]?)\s*[.:]\s*(.*)$')
RE_PHULUC = re.compile(rf'^(PHỤ LỤC|Phụ lục)(\s+({ROMAN}|\d+[A-Za-z]?))?\b\.?\s*(.*)$')
RE_KHOAN = re.compile(r'^\d+[a-zđ]?\.\s+\S')
RE_DIEM = re.compile(r'^[a-zđ]\)\s+\S')
SO_HIEU = re.compile(r'\b\d{1,4}/\d{4}/[A-ZĐ][A-ZĐa-z0-9]*(?:-[A-ZĐ][A-ZĐa-z0-9]*)*\b')


def _plain(line):
    """Bỏ dấu tiêu đề và nhấn mạnh Markdown để nhận dạng."""
    t = re.sub(r'^\s*#+\s*', '', line.strip())
    return re.sub(r'(\*\*|__|(?<!\w)[*_](?!\s)|(?<!\s)[*_](?!\w))', '', t).strip()


def _is_caps_title(s):
    letters = [c for c in s if c.isalpha()]
    return bool(letters) and len(s) <= 200 and sum(c.isupper() for c in letters) / len(letters) > 0.9


def structure(text):
    """Dựng lại cấu trúc văn bản pháp luật: # Chương / Phụ lục, ## Mục, ### Điều; khoản (1.) và điểm (a)) mỗi cái một đoạn, không thụt lề;
    bảng giữ nguyên; bỏ dấu # sai do bộ chuyển PDF gắn cho dòng in đậm (quốc hiệu, chữ ký). Không đổi chữ của văn bản."""
    t = re.sub(r'(?<=\S)[ \t]+(\*\*Điều\s+\d+[a-zđ]?\s*[.:])', r'\n\n\1', text)       # "…sử dụng. **Điều 39. …" dính cuối đoạn trước
    lines = t.split('\n')
    out, i, n = [], 0, len(lines)

    def next_nonempty(j):
        while j < n and not lines[j].strip():
            j += 1
        return j

    while i < n:
        raw = lines[i]
        if raw.lstrip().startswith('|'):                                   # bảng: giữ nguyên, cách dòng trước/sau
            if out and out[-1] and not out[-1].lstrip().startswith('|'):
                out.append('')
            out.append(raw.strip())
            if i + 1 >= n or not lines[i + 1].lstrip().startswith('|'):
                out.append('')
            i += 1
            continue
        p = _plain(raw)
        if not p:
            out.append('')
            i += 1
            continue
        m_c, m_m, m_d, m_p = RE_CHUONG.match(p), RE_MUC.match(p), RE_DIEU.match(p), RE_PHULUC.match(p)
        head = None
        if m_c or m_m or (m_p and (m_p.group(3) or _is_caps_title(p))):
            if m_c:
                lvl, label, rest = '#', f'Chương {m_c.group(1)}', m_c.group(2)
            elif m_m:
                lvl, label, rest = '##', f'Mục {m_m.group(1)}', m_m.group(2)
            else:
                lvl, label, rest = '#', (m_p.group(1) + (m_p.group(2) or '')).strip(), m_p.group(4)
            rest = rest.strip(' .:-–')
            parts = [rest] if rest else []
            # tên chương/mục/phụ lục ở dòng kế, có thể xuống 2–3 dòng (chữ in hoa); tên đã trọn trên cùng dòng thì chỉ nối khi kết thúc bằng dấu phẩy
            while len(parts) < 4 and (not parts or not rest or parts[-1].endswith(',')) :
                j = next_nonempty(i + 1)
                q = _plain(lines[j]) if j < n else ''
                if not q or not _is_caps_title(q) or RE_DIEU.match(q) or RE_CHUONG.match(q) or RE_MUC.match(q) or RE_PHULUC.match(q):
                    break
                parts.append(q)
                i = j
            rest = ' '.join(parts)
            head = f'{lvl} {label}' + (f'. {rest}' if rest else '')
        elif m_d:
            head = f'### Điều {m_d.group(1)}.' + (f' {m_d.group(2).strip()}' if m_d.group(2).strip() else '')
        if head:
            out += ['', head, '']
        elif RE_KHOAN.match(p) or RE_DIEM.match(p):
            out += ['', re.sub(r'^\s*#+\s*', '', raw.strip()), '']
        else:
            out.append(re.sub(r'^\s*#+\s*', '', raw.strip()))           # dòng thường: bỏ # sai và thụt lề (tránh thành khối mã)
        i += 1
    return '\n'.join(out)


def references(text, own=''):
    """Số hiệu văn bản được dẫn chiếu trong thân (khác chính văn bản), theo thứ tự xuất hiện, tối đa 50."""
    seen = []
    for m in SO_HIEU.finditer(text):
        s = m.group(0)
        if s != own and s not in seen:
            seen.append(s)
    return seen[:50]


END_OK = '.;:!?…"”)]'


def join_broken(text):
    """Nối đoạn bị cắt khi sang trang: đoạn trước không kết thúc bằng dấu câu và đoạn sau bắt đầu bằng chữ thường."""
    paras = re.split(r'\n{2,}', text)
    out = []
    for p in paras:
        prev = out[-1] if out else ''
        tail = prev.rstrip().rstrip('*_').rstrip()
        if (prev and p and p[0].islower() and tail and tail[-1] not in END_OK and not RE_DIEM.match(p.lstrip())
                and not prev.lstrip().startswith(('#', '|')) and not p.lstrip().startswith('|')):
            out[-1] = prev.rstrip() + ' ' + p.lstrip()
        else:
            out.append(p)
    return '\n\n'.join(out)


def clean(text):
    """Bỏ tiêu đề/chân trang lặp và dấu trang (không giữ số trang), nối đoạn bị cắt khi sang trang,
    dựng cấu trúc chương/mục/điều/khoản/điểm/phụ lục, gộp dòng trống thừa."""
    t = strip_running_heads(text.replace('\r\n', '\n'))
    t = PAGE_MARK.sub('', t)
    t = structure(t)
    t = re.sub(r'\n{3,}', '\n\n', '\n'.join(line.rstrip() for line in t.split('\n')))
    t = join_broken(t)
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
    return {'ok': True, 'text': out, 'converter': res.converter, 'refs': references(out)} if ok else {'ok': False, 'error': out}


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
