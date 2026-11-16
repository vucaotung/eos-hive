"""Số đo chất lượng OCR so với bản gõ đúng (thuần hàm, không phụ thuộc engine).

- CER: (thay + xóa + chèn) / số ký tự bản đúng, sau khi chuẩn hóa NFC và gộp khoảng trắng.
- Lỗi dấu: số ký tự bị thay mà chữ cái gốc (bỏ dấu) giống nhau, ví dụ ă→a, ế→ê, ọ→o. Tính trên số ký tự bản đúng.
- Số tiền / số văn bản: đếm token trong bản đúng không xuất hiện (khớp sau khi bỏ khoảng trắng) trong bản OCR.
"""
import re
import unicodedata


def norm(s):
    return ' '.join(unicodedata.normalize('NFC', s or '').split())


def strip_marks(ch):
    """Chữ cái gốc: bỏ dấu thanh và dấu mũ/móc; đ→d."""
    ch = ch.replace('đ', 'd').replace('Đ', 'D')
    return ''.join(c for c in unicodedata.normalize('NFD', ch) if unicodedata.category(c) != 'Mn')


def _ops_dp(a, b):
    """Căn chỉnh Levenshtein thuần Python (dự phòng khi thiếu rapidfuzz; chỉ dùng cho văn bản ngắn)."""
    n, m = len(a), len(b)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1):
        d[i][0] = i
    for j in range(m + 1):
        d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] != b[j - 1]))
    i, j, ops = n, m, []
    while i or j:
        if i and j and d[i][j] == d[i - 1][j - 1] + (a[i - 1] != b[j - 1]):
            ops.append(('equal' if a[i - 1] == b[j - 1] else 'replace', i - 1, j - 1))
            i, j = i - 1, j - 1
        elif i and d[i][j] == d[i - 1][j] + 1:
            ops.append(('delete', i - 1, None))
            i -= 1
        else:
            ops.append(('insert', None, j - 1))
            j -= 1
    return ops[::-1]


def _ops(a, b):
    """Danh sách thao tác theo từng ký tự: (loại, vị trí trong a, vị trí trong b)."""
    try:
        from rapidfuzz.distance import Levenshtein
    except ImportError:
        return _ops_dp(a, b)
    out = []
    for op in Levenshtein.opcodes(a, b):
        if op.tag == 'equal':
            out += [('equal', op.src_start + k, op.dest_start + k) for k in range(op.src_end - op.src_start)]
        elif op.tag == 'replace':
            out += [('replace', op.src_start + k, op.dest_start + k) for k in range(op.src_end - op.src_start)]
        elif op.tag == 'delete':
            out += [('delete', op.src_start + k, None) for k in range(op.src_end - op.src_start)]
        else:
            out += [('insert', None, op.dest_start + k) for k in range(op.dest_end - op.dest_start)]
    return out


def compare(truth, hyp):
    """So bản OCR `hyp` với bản đúng `truth`. Trả dict số đếm và tỉ lệ."""
    a, b = norm(truth), norm(hyp)
    ops = _ops(a, b)
    sub = sum(1 for o in ops if o[0] == 'replace')
    dele = sum(1 for o in ops if o[0] == 'delete')
    ins = sum(1 for o in ops if o[0] == 'insert')
    dia = sum(1 for t, i, j in ops if t == 'replace' and strip_marks(a[i]).lower() == strip_marks(b[j]).lower())
    n = max(len(a), 1)
    return {'chars': len(a), 'sub': sub, 'del': dele, 'ins': ins, 'dia': dia,
            'cer': (sub + dele + ins) / n, 'dia_rate': dia / n}


MONEY = re.compile(r'\d{1,3}(?:[.,]\d{3})+|\d+(?:[.,]\d+)?\s?(?:tỷ|triệu|nghìn)', re.I)   # chỉ phần số (+ đơn vị tỷ/triệu/nghìn), không lấy "đồng"
DOCNO = re.compile(r'\b\d{1,5}(?:/\d{4})?/[A-ZĐ][A-ZĐ0-9\-]*(?:/[A-ZĐ0-9\-]+)*\b|\b\d{1,5}/[A-ZĐ]{2,}\b')


def _squash(s):
    return re.sub(r'\s+', '', unicodedata.normalize('NFC', s)).lower()


def critical_tokens(text):
    """Token quan trọng trong bản đúng: số tiền và số hiệu văn bản."""
    t = unicodedata.normalize('NFC', text or '')
    return {'tien': sorted(set(m.group(0).strip() for m in MONEY.finditer(t))),
            'so_van_ban': sorted(set(m.group(0).strip() for m in DOCNO.finditer(t)))}


def token_misses(truth, hyp):
    """Với mỗi nhóm: (số token trong bản đúng, số token không thấy trong bản OCR, danh sách token sai)."""
    h = _squash(hyp)
    out = {}
    for kind, toks in critical_tokens(truth).items():
        miss = [t for t in toks if _squash(t) not in h]
        out[kind] = (len(toks), len(miss), miss)
    return out
