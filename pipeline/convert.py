"""Chuyển một tệp nguồn thành Markdown. Gọi chương trình ngoài bằng danh sách đối số, có timeout.

Kết quả (Result.status): ok | skip | error.
Phân loại (route): A_native (có chữ sẵn), A_soffice (qua LibreOffice), C_scan (PDF có trang scan chưa OCR), text.
OCR trang scan và ảnh thuộc Pha 3; ở đây trang scan chỉ được đánh dấu để mục lục báo "cần soát".
"""
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from .paths import long_path

SKIP_EXT = {'.dwg', '.dxf', '.dgn', '.dwf', '.dwt', '.ifc', '.bak', '.zip', '.rar', '.7z', '.tar', '.gz', '.mp4', '.mov', '.avi', '.mkv', '.wmv', '.mp3', '.wav',
            '.psd', '.ai', '.indd', '.skp', '.rvt', '.rfa', '.3ds', '.max', '.exe', '.dll', '.tmp', '.lnk', '.db', '.ini'}
IMG_EXT = {'.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.tif', '.tiff', '.gif', '.bmp'}
GOOGLE_LINK_EXT = {'.gdoc', '.gsheet', '.gslides', '.gform', '.gmap', '.gdraw', '.gsite'}
OFFICE_EXT = {'.docx', '.xlsx', '.pptx', '.csv'}
LEGACY = {'.doc': 'docx', '.xls': 'xlsx', '.ppt': 'pptx', '.rtf': 'docx', '.odt': 'docx', '.ods': 'xlsx', '.odp': 'pptx'}
TEXT_EXT = {'.md', '.txt'}


@dataclass
class Result:
    status: str                       # ok | skip | error
    route: str = ''
    converter: str = ''
    reason: str = ''
    text: str = ''
    pages: int | None = None
    scan_pages: list = field(default_factory=list)
    ocr_conf: float | None = None


def ext_of(name):
    return Path(name).suffix.lower()


def classify(name):
    """Trả mã lý do không chuyển được, hoặc '' nếu cần chuyển đổi."""
    e = ext_of(name)
    if e in SKIP_EXT:
        return 'khong_tai'                 # dwg, video, nén, tệp thiết kế: chỉ liệt kê
    if e in GOOGLE_LINK_EXT:
        return 'lien_ket_google'
    if e in IMG_EXT:
        return 'anh_cho_pha_3'
    return ''


def _version(pkg):
    from importlib.metadata import version
    try:
        return version(pkg)
    except Exception:  # noqa: BLE001
        return '?'


def _markitdown(path):
    from markitdown import MarkItDown
    return MarkItDown().convert(str(path)).text_content or ''


def _read_text(path):
    raw = Path(long_path(path)).read_bytes()
    for enc in ('utf-8-sig', 'utf-8', 'cp1258', 'latin-1'):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode('utf-8', 'replace')


def _soffice(path, target_ext, cfg, tmpdir):
    if not cfg.soffice:
        raise RuntimeError('Chưa cấu hình SOFFICE_BIN (cần LibreOffice để đọc .doc/.xls/.ppt)')
    prof = Path(tempfile.mkdtemp(prefix='lo-', dir=tmpdir))
    argv = [cfg.soffice, f'-env:UserInstallation={prof.resolve().as_uri()}', '--headless', '--convert-to', target_ext,
            '--outdir', str(tmpdir), str(path)]
    p = subprocess.run(argv, capture_output=True, text=True, timeout=cfg.soffice_timeout)
    out = Path(tmpdir) / (Path(path).stem + '.' + target_ext)
    if p.returncode != 0 or not out.exists():
        raise RuntimeError(f'LibreOffice không chuyển được (mã {p.returncode}): {(p.stderr or p.stdout)[-200:]}')
    return out


def convert_pdf(path, cfg):
    """Từng trang: có lớp chữ (≥ cfg.text_min_chars) lấy chữ bằng pymupdf4llm; còn lại đánh dấu trang scan."""
    import pymupdf
    import pymupdf4llm
    doc = pymupdf.open(str(path))
    try:
        if doc.needs_pass:
            raise RuntimeError('PDF có mật khẩu')
        parts, scan = [], []
        for i in range(doc.page_count):
            n = i + 1
            txt = doc[i].get_text().strip()
            if len(txt) >= cfg.text_min_chars:
                body = pymupdf4llm.to_markdown(doc, pages=[i], use_ocr=False).strip() or txt   # OCR do Pha 3 điều khiển
                parts.append(f'[[trang {n}]]\n\n{body}')
            else:
                scan.append(n)
                parts.append(f'[[trang {n}]]\n\n_(trang scan, chưa có chữ: cần OCR)_')
        total = doc.page_count
    finally:
        doc.close()
    route = 'C_scan' if scan else 'A_native'
    return Result('ok', route, f'pymupdf4llm {_version("pymupdf4llm")}', text='\n\n'.join(parts), pages=total, scan_pages=scan)


def convert_file(path, name, cfg, tmpdir):
    """Chuyển tệp `path` (tên gốc `name`). Mọi ngoại lệ thành Result('error')."""
    e = ext_of(name)
    why = classify(name)
    if why:
        return Result('skip', reason=why)
    try:
        if e == '.pdf':
            return convert_pdf(path, cfg)
        if e in TEXT_EXT:
            return Result('ok', 'text', 'văn bản gốc', text=_read_text(path))
        if e in OFFICE_EXT:
            return Result('ok', 'A_native', f'markitdown {_version("markitdown")}', text=_markitdown(path))
        if e in LEGACY:
            mid = _soffice(path, LEGACY[e], cfg, tmpdir)
            return Result('ok', 'A_soffice', f'soffice+markitdown {_version("markitdown")}', text=_markitdown(mid))
        return Result('skip', reason='dinh_dang_chua_ho_tro')
    except Exception as ex:  # noqa: BLE001 — một tệp lỗi không làm hỏng cả dự án
        return Result('error', reason=f'{type(ex).__name__}: {str(ex)[:300]}')
