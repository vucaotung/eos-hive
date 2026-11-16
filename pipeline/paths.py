"""Tên tệp và đường dẫn: an toàn trên Windows, ổn định trên mọi hệ điều hành.

- `duong_dan` (đường dẫn gốc trên Drive) luôn dùng dấu `/` và NFC, KHÔNG đổi ký tự.
- Tên dùng để ghi xuống đĩa/đầu ra (`safe_name`) bỏ ký tự Windows cấm, dấu chấm/khoảng trắng cuối, tên dành riêng.
  Phép đổi tên được ghi vào mục lục.
"""
import hashlib
import re
import sys
import unicodedata
from pathlib import PurePosixPath

_FORBIDDEN = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
_RESERVED = {'CON', 'PRN', 'AUX', 'NUL', *(f'COM{i}' for i in range(1, 10)), *(f'LPT{i}' for i in range(1, 10))}
MAX_COMPONENT = 200


def nfc(s):
    return unicodedata.normalize('NFC', s)


def safe_name(name):
    """Trả (tên an toàn, đã đổi?). Giữ nguyên chữ tiếng Việt."""
    original = nfc(name)
    s = _FORBIDDEN.sub('_', original).rstrip(' .')
    if not s:
        s = '_'
    if s.split('.')[0].upper() in _RESERVED:
        s = '_' + s
    if len(s) > MAX_COMPONENT:
        stem, dot, ext = s.rpartition('.')
        h = hashlib.sha1(original.encode('utf-8')).hexdigest()[:8]
        keep = MAX_COMPONENT - len(h) - 1 - (len(ext) + 1 if dot and len(ext) < 12 else 0)
        s = (stem if dot and len(ext) < 12 else s)[:keep] + '~' + h + ('.' + ext if dot and len(ext) < 12 else '')
    return s, s != original


def safe_rel(rel_posix):
    """Làm an toàn từng thành phần của đường dẫn tương đối kiểu posix. Trả (đường dẫn an toàn, đã đổi?)."""
    parts, changed = [], False
    for p in PurePosixPath(nfc(rel_posix)).parts:
        s, c = safe_name(p)
        parts.append(s)
        changed = changed or c
    return '/'.join(parts), changed


def long_path(path):
    """Windows: thêm tiền tố \\\\?\\ để vượt giới hạn 260 ký tự. Nơi khác giữ nguyên."""
    p = str(path)
    if sys.platform != 'win32' or p.startswith('\\\\?\\'):
        return p
    import os
    p = os.path.abspath(p)
    return '\\\\?\\UNC\\' + p[2:] if p.startswith('\\\\') else '\\\\?\\' + p


def md_name(rel_posix, collide):
    """Tên tệp Markdown cho một nguồn. `collide`=True khi cùng thư mục có nguồn khác trùng tên gốc
    (ví dụ a.docx và a.pdf): giữ cả phần mở rộng, thành `a.docx.md` / `a.pdf.md`."""
    d, _, base = rel_posix.rpartition('/')
    stem = base if collide else (base.rpartition('.')[0] or base)
    return (d + '/' if d else '') + stem + '.md'
