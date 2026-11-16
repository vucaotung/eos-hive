"""Bước 1 — Tải thư mục nguồn về WORK_DIR/src/<slug> và ghi manifest.

Hai nguồn: thư mục cục bộ (Drive for Desktop trên Z2, dùng để phát triển) hoặc Drive API (VPS 169).
Manifest liệt kê MỌI tệp nguồn, kể cả tệp không tải (dwg, video…): chỉ ghi tên, đường dẫn, link.
Thư mục `_md_deo` (đầu ra của chính pipeline) luôn bị bỏ qua để không nạp lại đầu ra.
"""
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from . import drive as D
from .config import MD_SUBDIR
from .convert import classify
from .frontmatter import drive_link
from .paths import long_path, nfc, safe_rel

HIDDEN = ('~$', '.~lock.', 'desktop.ini', 'thumbs.db', '.ds_store')


def _is_temp(name):
    n = name.lower()
    return n.startswith(HIDDEN[:2]) or n in HIDDEN[2:]


def _md5(path):
    h = hashlib.md5()                                     # noqa: S324 — định danh nội dung, không phải bảo mật
    with open(long_path(path), 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def _reset(dir_, work):
    """Xóa thư mục src/<slug> cũ — chỉ khi nằm trong WORK_DIR (pipeline tạo ra nó)."""
    d = Path(dir_).resolve()
    if Path(work).resolve() not in d.parents:
        raise ValueError(f'Từ chối xóa thư mục ngoài WORK_DIR: {d}')
    if d.exists():
        shutil.rmtree(long_path(d))
    d.mkdir(parents=True)


def _save(manifest_path, slug, source, items):
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps({'project': slug, 'source': source, 'files': items}, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    return len(items)


def _unique(rel, taken, tag):
    """Hai tệp trùng đường dẫn an toàn (do đổi tên) → thêm hậu tố ổn định."""
    if rel.lower() in taken:
        stem, dot, ext = rel.rpartition('.')
        rel = f'{stem}~{tag}.{ext}' if dot else f'{rel}~{tag}'
    taken.add(rel.lower())
    return rel


def fetch_local(slug, source_dir, cfg):
    """Chép cây thư mục cục bộ. Trả số tệp trong manifest."""
    root = Path(source_dir)
    if not root.is_dir():
        raise FileNotFoundError(f'Không có thư mục nguồn: {root}')
    dest = cfg.src(slug)
    _reset(dest, cfg.work)
    items, taken = [], set()
    limit = cfg.max_source_mb * 1048576
    for p in sorted(root.rglob('*')):
        rel_parts = p.relative_to(root).parts
        if MD_SUBDIR in rel_parts or any(x.startswith('.') and len(x) > 1 for x in rel_parts) or not p.is_file():
            continue
        orig = nfc('/'.join(rel_parts))
        if _is_temp(p.name):
            continue
        st = p.stat()
        size = st.st_size
        item = {'path': orig, 'size': size, 'drive_id': '', 'md5': '', 'local': '',
                'modified': datetime.fromtimestamp(st.st_mtime, timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}
        why = classify(p.name)
        if not why and size > limit:
            why = 'qua_lon'
        if why:
            item['skip'] = why
        else:
            safe, _ = safe_rel(orig)
            safe = _unique(safe, taken, hashlib.sha1(orig.encode()).hexdigest()[:6])
            tgt = dest / safe
            Path(long_path(tgt.parent)).mkdir(parents=True, exist_ok=True)
            shutil.copy2(long_path(p), long_path(tgt))
            item.update(local=safe, md5=_md5(tgt))
        items.append(item)
    return _save(cfg.manifest(slug), slug, {'type': 'local', 'dir': root.name}, items)


def fetch_drive(slug, folder_id, cfg, client):
    """Tải đệ quy một thư mục Drive. Tệp Google gốc được xuất sang Office."""
    dest = cfg.src(slug)
    _reset(dest, cfg.work)
    items, taken = [], set()
    limit = cfg.max_source_mb * 1048576
    stack = [(folder_id, '')]
    while stack:
        fid, prefix = stack.pop()
        for f in client.children(fid):
            name, mime = f['name'], f.get('mimeType', '')
            rel = nfc(f'{prefix}{name}')
            if mime == D.FOLDER:
                if name != MD_SUBDIR and not name.startswith('.'):
                    stack.append((f['id'], rel + '/'))
                continue
            if mime == D.SHORTCUT or _is_temp(name):
                continue
            item = {'path': rel, 'size': int(f.get('size') or 0), 'drive_id': f['id'], 'md5': f.get('md5Checksum', ''),
                    'modified': f.get('modifiedTime', ''), 'local': '', 'drive_link': drive_link(f['id'])}
            exp = D.EXPORT.get(mime)
            why = classify(name)
            if not why and not exp and item['size'] > limit:
                why = 'qua_lon'
            if why:
                item['skip'] = why
            elif mime.startswith('application/vnd.google-apps.') and not exp:
                item['skip'] = 'lien_ket_google'
            else:
                save_rel = rel + (exp[1] if exp and not rel.lower().endswith(exp[1]) else '')
                safe, _ = safe_rel(save_rel)
                safe = _unique(safe, taken, f['id'][:6])
                tgt = dest / safe
                try:
                    client.download(f['id'], Path(long_path(tgt)), exp[0] if exp else None)
                    item['local'] = safe
                    item['md5'] = item['md5'] or _md5(tgt)
                except D.DriveError as e:
                    item['skip'] = 'loi_tai'
                    item['error'] = str(e)[:200]
            items.append(item)
    return _save(cfg.manifest(slug), slug, {'type': 'drive', 'folder': folder_id}, items)
