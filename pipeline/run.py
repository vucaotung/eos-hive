"""Bước 2 — Chuyển Markdown theo manifest, ghi md/<slug>/ cùng đường dẫn con với nguồn, dựng 00_MUC_LUC.md.

Ảnh được nén thành JPEG và chép vào cùng cây thư mục (cạnh tệp .md của dự án) để runner đẩy lên `_md_deo`.
Thư mục tạm xóa sau mỗi dự án kể cả khi lỗi (try/finally).
"""
import json
import shutil
import sys
import tempfile
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

from . import frontmatter, toc
from .config import TOC_NAME
from .convert import convert_file
from .paths import long_path, out_name, safe_rel


def _key(path):
    """(thư mục, tên gốc không đuôi) viết thường: hai nguồn trùng khóa này sẽ trùng tên đầu ra."""
    d, _, base = path.rpartition('/')
    return d.lower(), (base.rpartition('.')[0] or base).lower()


def _short(path, tmpdir, limit=240):
    """Windows: các thư viện đọc tệp không chịu đường dẫn > 260 ký tự → chép sang tên ngắn trong thư mục tạm."""
    if sys.platform != 'win32' or len(str(Path(path).resolve())) <= limit:
        return path
    dst = Path(tmpdir) / f'long-{abs(hash(str(path))) % 10**8}{Path(path).suffix}'
    shutil.copy2(long_path(path), dst)
    return dst


def _reset_md(md_root, work):
    d = Path(md_root).resolve()
    if Path(work).resolve() not in d.parents:
        raise ValueError(f'Từ chối xóa thư mục ngoài WORK_DIR: {d}')
    if d.exists():
        shutil.rmtree(long_path(d))
    d.mkdir(parents=True)


def run_project(slug, cfg, convert=convert_file, now=None):
    mf = json.loads(cfg.manifest(slug).read_text(encoding='utf-8'))
    items = mf['files']
    now = now or datetime.now(timezone.utc)
    stamp = now.strftime('%Y-%m-%dT%H:%M:%S+00:00')
    md_root, src_root = cfg.md(slug), cfg.src(slug)
    _reset_md(md_root, cfg.work)

    # Cùng thư mục có a.docx và a.pdf (hoặc a.png) → a.docx.md, a.pdf.md, a.png.jpg: không đè nhau
    stems = Counter(_key(it['path']) for it in items)

    cfg.tmp().mkdir(parents=True, exist_ok=True)
    tmpdir = Path(tempfile.mkdtemp(prefix=f'{slug}-', dir=cfg.tmp()))
    records, renames, used = [], [], set()
    try:
        for it in items:
            rec = {'path': it['path'], 'drive_link': it.get('drive_link', '')}
            if it.get('skip'):
                rec.update(status='skip', reason=it['skip'])
                records.append(rec)
                continue
            res = convert(_short(src_root / it['local'], tmpdir), it['path'], cfg, tmpdir)
            rec.update(status=res.status, reason=res.reason, route=res.route, pages=res.pages, scan_pages=res.scan_pages,
                       review_pages=res.review_pages, ocr_pages=res.ocr_pages, ocr_conf=res.ocr_conf, kind=res.kind, note=res.note)
            if res.status == 'ok':
                ext = '.jpg' if res.kind == 'image' else '.md'
                collide = stems[_key(it['path'])] > 1
                want = out_name(it['path'], collide, ext)
                rel, changed = safe_rel(want)
                if rel.lower() in used:                                     # đụng tên sau khi làm an toàn
                    rel = rel[:-len(ext)] + f"~{it.get('md5', '')[:6] or len(used)}{ext}"
                used.add(rel.lower())
                if changed:
                    renames.append((want, rel))
                out = md_root / rel
                Path(long_path(out.parent)).mkdir(parents=True, exist_ok=True)
                if res.kind == 'image':
                    Path(long_path(out)).write_bytes(res.data)
                    rec.update(out=rel, bytes=len(res.data), src_bytes=it.get('size', 0))
                else:
                    fm = frontmatter.build({
                        'project': slug, 'drive_id': it.get('drive_id', ''), 'drive_link': it.get('drive_link', ''), 'duong_dan': it['path'],
                        'md5': it.get('md5', ''), 'converter': res.converter, 'route': res.route, 'converted_at': stamp,
                        'modified_time': it.get('modified', ''), 'so_trang': res.pages if res.pages is not None else '',
                        'ocr_conf_tb': '' if res.ocr_conf is None else f'{res.ocr_conf:.2f}'})
                    with open(long_path(out), 'w', encoding='utf-8', newline='\n') as f:
                        f.write(fm + res.text.replace('\r\n', '\n').strip() + '\n')
                    rec['out'] = rel
            records.append(rec)
        (md_root / TOC_NAME).write_text(toc.build(slug, records, renames), encoding='utf-8', newline='\n')
    finally:
        shutil.rmtree(long_path(tmpdir), ignore_errors=True)
        try:
            cfg.tmp().rmdir()                                               # chỉ xóa được khi đã rỗng
        except OSError:
            pass
    return toc.counts(records)
