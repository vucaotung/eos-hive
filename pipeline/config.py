"""Cấu hình qua biến môi trường. Không có đường dẫn cứng, không có bí mật trong mã."""
import os
import re
import sys
from pathlib import Path

SLUG = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)*$')           # khớp mẫu của runner
SAFE_ID = re.compile(r'^[A-Za-z0-9_-]{10,}$')              # id thư mục Drive
MD_SUBDIR = '_md_deo'                                       # thư mục đầu ra trong thư mục nguồn
TOC_NAME = '00_MUC_LUC.md'


def _int(name, default):
    try:
        return int(os.environ.get(name, default))
    except ValueError:
        return default


class Config:
    """Đọc cấu hình tại thời điểm tạo (để test đổi được bằng env)."""

    def __init__(self, env=None):
        e = os.environ if env is None else env
        if e.get('WORK_DIR'):
            self.work = Path(e['WORK_DIR']).expanduser()
        else:
            self.work = Path('C:/eos-work') if sys.platform == 'win32' else Path.home() / 'work'
        # SOFFICE_BIN đặt (kể cả rỗng) thì dùng đúng giá trị đó; không đặt thì tự dò đường dẫn thông dụng
        self.soffice = e['SOFFICE_BIN'] if 'SOFFICE_BIN' in e else _find_soffice()
        self.pandoc = e.get('PANDOC_BIN') or ''
        self.tesseract = e.get('TESSERACT_CMD') or ''
        self.max_source_mb = int(e.get('MAX_SOURCE_MB', '300') or 300)
        self.text_min_chars = int(e.get('PDF_TEXT_MIN_CHARS', '30') or 30)   # trang có ≥ ngần này ký tự = có lớp chữ
        self.soffice_timeout = int(e.get('SOFFICE_TIMEOUT', '300') or 300)

    # Bố cục thư mục làm việc: src/<slug>, md/<slug>, manifest/<slug>.json, push/<slug>.json, tmp/
    def src(self, slug):
        return self.work / 'src' / slug

    def md(self, slug):
        return self.work / 'md' / slug

    def manifest(self, slug):
        return self.work / 'manifest' / f'{slug}.json'

    def push_result(self, slug):
        return self.work / 'push' / f'{slug}.json'

    def tmp(self):
        return self.work / 'tmp'


def _find_soffice():
    for p in ('C:/Program Files/LibreOffice/program/soffice.exe', '/usr/bin/soffice', '/usr/bin/libreoffice'):
        if Path(p).exists():
            return p
    return ''


def load_env_file(path):
    """Nạp tệp .env đơn giản (KEY=VALUE) vào os.environ mà không ghi đè biến đã có. Không in giá trị."""
    p = Path(path).expanduser()
    if not p.is_file():
        return 0
    n = 0
    for line in p.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        k = k.strip()
        if k and k not in os.environ:
            os.environ[k] = v.strip().strip('"\'')
            n += 1
    return n
