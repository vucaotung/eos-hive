"""OCR một trang bằng Tesseract (`vie`, bản best), chọn ở Pha 2.

Chọn Tesseract vì bảng ký tự của PaddleOCR (PP-OCRv5/v6) thiếu phần lớn chữ Việt có dấu (xem ops-log/pha2-benchmark.md).
Gọi tesseract bằng danh sách đối số, có timeout. Độ tin cậy = trung bình độ tin cậy từng từ (0..1).
"""
import csv
import io
import subprocess
from dataclasses import dataclass

_cache = {}


class OcrUnavailable(RuntimeError):
    pass


@dataclass
class PageOcr:
    text: str
    conf: float | None      # None = không nhận ra chữ nào (trang trắng)


class Tesseract:
    def __init__(self, cfg):
        self.cmd, self.lang, self.tessdata, self.timeout = cfg.tesseract, cfg.ocr_lang, cfg.tessdata, cfg.ocr_timeout

    def _td(self):
        return ['--tessdata-dir', self.tessdata] if self.tessdata else []

    def check(self):
        """Kiểm Tesseract có chạy được và có dữ liệu ngôn ngữ. Ném OcrUnavailable nếu không."""
        if not self.cmd:
            raise OcrUnavailable('Chưa cấu hình TESSERACT_CMD (cần Tesseract kèm dữ liệu "vie" để OCR trang scan)')
        try:
            p = subprocess.run([self.cmd, *self._td(), '--list-langs'], capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise OcrUnavailable(f'Không chạy được Tesseract: {e}')
        if self.lang not in (p.stdout + p.stderr).split():
            raise OcrUnavailable(f'Tesseract thiếu dữ liệu ngôn ngữ "{self.lang}" (đặt TESSDATA_DIR tới thư mục có {self.lang}.traineddata)')

    def page(self, png):
        p = subprocess.run([self.cmd, *self._td(), str(png), 'stdout', '-l', self.lang, '--psm', '3', 'tsv'],
                           capture_output=True, text=True, encoding='utf-8', timeout=self.timeout)
        if p.returncode != 0:
            raise RuntimeError(f'tesseract mã {p.returncode}: {p.stderr[-200:]}')
        return parse_tsv(p.stdout)


def parse_tsv(tsv):
    """Từ TSV của Tesseract dựng văn bản: dòng nối bằng xuống dòng, đoạn cách nhau một dòng trống."""
    lines, words, confs, cur_line, cur_par = [], [], [], None, None
    out = []

    def flush_line():
        nonlocal words
        if words:
            lines.append(' '.join(words))
            words = []

    def flush_par():
        nonlocal lines
        flush_line()
        if lines:
            out.append('\n'.join(lines))
            lines = []

    for row in csv.DictReader(io.StringIO(tsv), delimiter='\t', quoting=csv.QUOTE_NONE):
        if row.get('level') != '5' or not (row.get('text') or '').strip():
            continue
        par = (row['block_num'], row['par_num'])
        line = par + (row['line_num'],)
        if cur_par is not None and par != cur_par:
            flush_par()
        elif cur_line is not None and line != cur_line:
            flush_line()
        cur_par, cur_line = par, line
        words.append(row['text'])
        try:
            c = float(row['conf'])
            if c >= 0:
                confs.append(c)
        except ValueError:
            pass
    flush_par()
    return PageOcr('\n\n'.join(out), (sum(confs) / len(confs) / 100) if confs else None)


def get(cfg):
    """Tesseract đã kiểm tra, dùng lại giữa các tệp. Ném OcrUnavailable nếu không dùng được (kết quả cũng được nhớ)."""
    key = (cfg.tesseract, cfg.tessdata, cfg.ocr_lang)
    if key not in _cache:
        t = Tesseract(cfg)
        try:
            t.check()
            _cache[key] = t
        except OcrUnavailable as e:
            _cache[key] = e
    r = _cache[key]
    if isinstance(r, OcrUnavailable):
        raise r
    return r
