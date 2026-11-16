"""Chuyển một tệp nguồn thành Markdown (hoặc JPEG nén cho ảnh). Gọi chương trình ngoài bằng danh sách đối số, có timeout.

Kết quả (Result.status): ok | skip | error. Result.kind: md | image.
Phân loại (route): text (văn bản gốc), A_native (có chữ sẵn), A_soffice (qua LibreOffice),
  B_ocr (PDF có trang scan đã OCR bằng Tesseract), C_scan (còn trang scan chưa OCR được, vì thiếu Tesseract hoặc OCR lỗi), image.

PDF theo từng trang: trang có ≥ PDF_TEXT_MIN_CHARS ký tự lớp chữ lấy chữ bằng pymupdf4llm; trang còn lại render
ở OCR_DPI (giảm cho trang khổ lớn) rồi OCR. Trang có độ tin cậy < OCR_REVIEW_BELOW vào danh sách "Cần soát" của mục lục.
"""
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from . import images, ocr
from .paths import long_path

SKIP_EXT = {'.dwg', '.dxf', '.dgn', '.dwf', '.dwt', '.ifc', '.bak', '.zip', '.rar', '.7z', '.tar', '.gz', '.mp4', '.mov', '.avi', '.mkv',
            '.wmv', '.mp3', '.wav', '.psd', '.ai', '.indd', '.skp', '.rvt', '.rfa', '.3ds', '.max', '.exe', '.dll', '.tmp', '.lnk', '.db', '.ini'}
IMG_EXT = {'.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif', '.tif', '.tiff', '.gif', '.bmp'}
GOOGLE_LINK_EXT = {'.gdoc', '.gsheet', '.gslides', '.gform', '.gmap', '.gdraw', '.gsite'}
OFFICE_EXT = {'.docx', '.xlsx', '.pptx', '.csv'}
LEGACY = {'.doc': 'docx', '.xls': 'xlsx', '.ppt': 'pptx', '.rtf': 'docx', '.odt': 'docx', '.ods': 'xlsx', '.odp': 'pptx'}
TEXT_EXT = {'.md', '.txt'}
BLANK = '_(trang trắng: OCR không thấy chữ)_'


@dataclass
class Result:
    status: str                       # ok | skip | error
    route: str = ''
    converter: str = ''
    reason: str = ''
    text: str = ''
    pages: int | None = None
    scan_pages: list = field(default_factory=list)      # trang scan CHƯA có chữ (không OCR được)
    ocr_pages: list = field(default_factory=list)       # trang đã OCR
    review_pages: list = field(default_factory=list)    # trang OCR có độ tin cậy < ngưỡng
    ocr_conf: float | None = None                       # độ tin cậy trung bình các trang đã OCR
    kind: str = 'md'                                    # md | image
    data: bytes = b''                                   # nội dung JPEG khi kind == image
    note: str = ''


def ext_of(name):
    return Path(name).suffix.lower()


def is_image(name):
    return ext_of(name) in IMG_EXT


def classify(name):
    """Trả mã lý do không chuyển được, hoặc '' nếu cần chuyển đổi."""
    e = ext_of(name)
    if e in SKIP_EXT:
        return 'khong_tai'                 # dwg, video, nén, tệp thiết kế: chỉ liệt kê
    if e in GOOGLE_LINK_EXT:
        return 'lien_ket_google'
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


def page_dpi(rect, cfg):
    """dpi để render: OCR_DPI, giảm cho trang khổ lớn sao cho cạnh dài ≤ OCR_MAX_SIDE_PX."""
    side_in = max(rect.width, rect.height) / 72
    return max(72, min(cfg.ocr_dpi, int(cfg.ocr_max_side_px / side_in)))


def convert_pdf(path, cfg, tmpdir, ocr_engine=None):
    """Từng trang: có lớp chữ → pymupdf4llm; không có → OCR (nếu dùng được). `ocr_engine` chỉ để test."""
    import pymupdf
    import pymupdf4llm
    doc = pymupdf.open(str(path))
    note, engine = '', None
    try:
        if doc.needs_pass:
            raise RuntimeError('PDF có mật khẩu')
        total = doc.page_count
        parts, scan, done, review, confs = [], [], [], [], []
        for i in range(total):
            n = i + 1
            txt = doc[i].get_text().strip()
            if len(txt) >= cfg.text_min_chars:
                body = pymupdf4llm.to_markdown(doc, pages=[i], use_ocr=False).strip() or txt   # OCR do bước này điều khiển, không phải thư viện
                parts.append(f'[[trang {n}]]\n\n{body}')
                continue
            if engine is None and not note:
                try:
                    engine = ocr_engine or ocr.get(cfg)
                except ocr.OcrUnavailable as e:
                    note = str(e)
            res = None
            if engine is not None:
                png = Path(tmpdir) / f'ocr-{n}.png'
                try:
                    doc[i].get_pixmap(dpi=page_dpi(doc[i].rect, cfg)).save(str(png))
                    res = engine.page(png)
                except Exception as e:  # noqa: BLE001 — một trang lỗi không làm hỏng cả tệp
                    note = f'OCR trang {n} lỗi: {type(e).__name__}: {str(e)[:120]}'
                finally:
                    png.unlink(missing_ok=True)
            if res is None:
                scan.append(n)
                parts.append(f'[[trang {n}]]\n\n_(trang scan, chưa có chữ: cần OCR)_')
            elif res.conf is None or not res.text.strip():
                done.append(n)                                   # trang trắng: không cần soát
                parts.append(f'[[trang {n}]]\n\n{BLANK}')
            else:
                done.append(n)
                confs.append(res.conf)
                if res.conf < cfg.ocr_review_below:
                    review.append(n)
                parts.append(f'[[trang {n}]]\n\n{res.text}')
    finally:
        doc.close()
    route = 'C_scan' if scan else ('B_ocr' if done else 'A_native')
    conv = f'pymupdf4llm {_version("pymupdf4llm")}' + (f' + tesseract {cfg.ocr_lang}' if done else '')
    return Result('ok', route, conv, text='\n\n'.join(parts), pages=total, scan_pages=scan, ocr_pages=done, review_pages=review,
                  ocr_conf=(sum(confs) / len(confs)) if confs else None, note=note)


def convert_image(path, cfg):
    data, info = images.compress(path, cfg)
    note = f"{info['format']} {info['src_size'][0]}x{info['src_size'][1]} → JPEG {info['out_size'][0]}x{info['out_size'][1]} q{info['quality']}"
    if info['exif_date']:
        note += f", ngày chụp {info['exif_date']}"
    return Result('ok', 'image', f'pillow {_version("pillow")}', kind='image', data=data, note=note)


def convert_file(path, name, cfg, tmpdir):
    """Chuyển tệp `path` (tên gốc `name`). Mọi ngoại lệ thành Result('error')."""
    e = ext_of(name)
    why = classify(name)
    if why:
        return Result('skip', reason=why)
    try:
        if e in IMG_EXT:
            return convert_image(path, cfg)
        if e == '.pdf':
            return convert_pdf(path, cfg, tmpdir)
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
