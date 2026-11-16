"""Các engine OCR cho benchmark. Mỗi engine: load() một lần, ocr(đường dẫn ảnh PNG) -> (văn bản, độ tin cậy 0..1 hoặc None).

Gọi chương trình ngoài bằng danh sách đối số, có timeout. Không in bí mật (không có bí mật ở đây).
"""
import csv
import io
import os
import subprocess
import time


class EngineUnavailable(RuntimeError):
    """Engine không dùng được trên máy này (thiếu công cụ, không hỗ trợ ngôn ngữ…). Ghi vào báo cáo, không làm hỏng cả lượt chạy."""


class Tesseract:
    def __init__(self, cmd=None, lang='vie', psm='3', timeout=180):
        self.name = f'tesseract-{lang}-psm{psm}'
        self.cmd = cmd or os.environ.get('TESSERACT_CMD') or 'tesseract'
        self.lang, self.psm, self.timeout = lang, psm, timeout
        self.version = ''

    def load(self):
        try:
            p = subprocess.run([self.cmd, '--list-langs'], capture_output=True, text=True, timeout=30)
            v = subprocess.run([self.cmd, '--version'], capture_output=True, text=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as e:
            raise EngineUnavailable(f'Không chạy được Tesseract ({self.cmd}): {e}')
        langs = (p.stdout + p.stderr).split()
        if self.lang not in langs:
            raise EngineUnavailable(f'Tesseract không có dữ liệu ngôn ngữ "{self.lang}" (có: {", ".join(langs[2:]) or "không rõ"})')
        self.version = (v.stdout or v.stderr).splitlines()[0] if (v.stdout or v.stderr) else ''

    def ocr(self, png):
        p = subprocess.run([self.cmd, str(png), 'stdout', '-l', self.lang, '--psm', self.psm, 'tsv'],
                           capture_output=True, text=True, encoding='utf-8', timeout=self.timeout)
        if p.returncode != 0:
            raise RuntimeError(f'tesseract mã {p.returncode}: {p.stderr[-200:]}')
        words, confs, cur, lines = [], [], None, []
        for row in csv.DictReader(io.StringIO(p.stdout), delimiter='\t', quoting=csv.QUOTE_NONE):
            if row.get('level') != '5' or not (row.get('text') or '').strip():
                continue
            key = (row['block_num'], row['par_num'], row['line_num'])
            if cur is not None and key != cur:
                lines.append(' '.join(words)); words = []
            cur = key
            words.append(row['text'])
            try:
                c = float(row['conf'])
                if c >= 0:
                    confs.append(c)
            except ValueError:
                pass
        if words:
            lines.append(' '.join(words))
        return '\n'.join(lines), (sum(confs) / len(confs) / 100 if confs else None)


class Paddle:
    """PaddleOCR 3.x (PP-OCRv5 hoặc PP-OCRv6). `lang` 'vi' chọn mô hình nhận dạng Latin với PP-OCRv5."""

    def __init__(self, version='PP-OCRv5', lang='vi', **kw):
        self.name = f'paddleocr-{version.lower()}-{lang}'
        self.version, self.lang, self.kw = version, lang, kw
        self.engine = None
        self.rec_model = ''

    def load(self):
        try:
            from paddleocr import PaddleOCR
        except ImportError as e:
            raise EngineUnavailable(f'Chưa cài paddleocr: {e}')
        try:
            self.engine = PaddleOCR(lang=self.lang, ocr_version=self.version, use_doc_orientation_classify=False,
                                    use_doc_unwarping=False, use_textline_orientation=False, **self.kw)
        except Exception as e:  # noqa: BLE001 — phiên bản/ngôn ngữ không hỗ trợ cũng là một kết quả đo
            raise EngineUnavailable(f'PaddleOCR {self.version} lang={self.lang} không khởi tạo được: {type(e).__name__}: {str(e)[:300]}')
        self.rec_model = str(getattr(getattr(self.engine, '_paddlex_pipeline', None), 'text_rec_model', '') or '')

    def ocr(self, png):
        res = self.engine.predict(str(png))
        texts, scores = [], []
        for r in res:
            d = r if isinstance(r, dict) else getattr(r, 'json', {}).get('res', {})
            texts += list(d.get('rec_texts') or [])
            scores += [float(s) for s in (d.get('rec_scores') or [])]
        return '\n'.join(texts), (sum(scores) / len(scores) if scores else None)


def available(name, cfg=None):
    """Tạo engine theo tên: tesseract | ppocrv5 | ppocrv6."""
    if name == 'tesseract':
        return Tesseract()
    if name == 'ppocrv5':
        return Paddle('PP-OCRv5', 'vi')
    if name == 'ppocrv6':
        return Paddle('PP-OCRv6', 'vi')
    raise ValueError(f'Engine không rõ: {name}')


def timed(fn, *a):
    t = time.perf_counter()
    r = fn(*a)
    return r, time.perf_counter() - t
