"""Front matter của mỗi tệp .md — hợp đồng với MCP (`mcp/src/tools.mjs`, `weknora.mjs`).

Mỗi khóa một dòng, dạng `khóa: giá trị`. MCP đọc: drive_link, duong_dan (hoặc source_path), buoc, giai_doan,
so_trang (hoặc pages). `buoc` và `giai_doan` LUÔN để trống: mã bước do agent `quan-tri-du-lieu` gắn sau (lưu ở CSDL).
"""
from .paths import nfc

ORDER = ['project', 'drive_id', 'drive_link', 'duong_dan', 'md5', 'converter', 'route', 'converted_at',
         'modified_time', 'so_trang', 'ocr_conf_tb', 'buoc', 'giai_doan']
ALWAYS_EMPTY = ('buoc', 'giai_doan')


def drive_link(drive_id):
    return f'https://drive.google.com/file/d/{drive_id}/view' if drive_id else ''


def build(meta):
    """meta: dict các khóa trong ORDER (khóa thiếu = rỗng). Trả khối '---\\n…\\n---\\n\\n'."""
    m = dict(meta)
    m['drive_link'] = m.get('drive_link') or drive_link(m.get('drive_id'))
    for k in ALWAYS_EMPTY:
        m[k] = ''
    lines = []
    for k in ORDER:
        v = m.get(k)
        v = '' if v is None else str(v)
        v = ' '.join(nfc(v).split())                 # một dòng, không xuống dòng trong giá trị
        lines.append(f'{k}: ""' if v == '' else f'{k}: {v}')
    return '---\n' + '\n'.join(lines) + '\n---\n\n'


def parse(text):
    """Tách front matter (cùng cách MCP `weknora.prepare` đọc). Trả (dict, thân)."""
    t = text.replace('\r\n', '\n').lstrip('﻿')
    if not t.startswith('---\n'):
        return {}, t
    e = t.find('\n---', 4)
    if e == -1:
        return {}, t
    meta = {}
    for line in t[4:e].split('\n'):
        i = line.find(': ')
        if i > 0:
            meta[line[:i].strip()] = line[i + 2:].strip().strip('"')
    return meta, t[e + 4:].lstrip('\n')
