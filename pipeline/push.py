"""Bước 3 — Đẩy md/<slug>/ lên thư mục `_md_deo` trong thư mục nguồn trên Drive, ghi danh sách tệp để runner đăng ký.

Chỉ ghi vào `_md_deo` (do pipeline tạo). Chạy lại thì cập nhật tệp cùng tên, không tạo bản trùng. Không xóa gì trên Drive.
"""
import json
import mimetypes
from pathlib import Path

from .config import MD_SUBDIR
from .frontmatter import drive_link
from .paths import long_path

MIME = {'.md': 'text/markdown', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp', '.csv': 'text/csv'}


def push(slug, folder_id, cfg, client):
    root = cfg.md(slug)
    if not root.is_dir():
        raise FileNotFoundError(f'Chưa có {root}: chạy `run` trước')
    md_id = client.ensure_folder(folder_id, MD_SUBDIR)
    folders = {'': md_id}
    files = []
    for p in sorted(root.rglob('*')):
        if not p.is_file():
            continue
        rel = p.relative_to(root).as_posix()
        parent, _, name = rel.rpartition('/')
        # tạo từng cấp thư mục con
        acc = ''
        for part in [x for x in parent.split('/') if x]:
            nxt = f'{acc}/{part}' if acc else part
            if nxt not in folders:
                folders[nxt] = client.ensure_folder(folders[acc], part)
            acc = nxt
        mime = MIME.get(p.suffix.lower()) or mimetypes.guess_type(name)[0] or 'application/octet-stream'
        data = Path(long_path(p)).read_bytes()
        r = client.upload(folders[acc], name, data, mime)
        files.append({'drive_id': r['id'], 'name': rel, 'mime': r.get('mimeType') or mime, 'bytes': int(r.get('size') or len(data)),
                      'url': drive_link(r['id'])})
    out = cfg.push_result(slug)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({'md_folder_id': md_id, 'files': files}, ensure_ascii=False) + '\n', encoding='utf-8')
    return {'md_folder_id': md_id, 'files': len(files)}
