"""Benchmark OCR tiếng Việt: Tesseract `vie` so với PP-OCRv5 `vi` và PP-OCRv6.

Chạy (Z2 Windows, venv riêng .venv-bench):
  python -m pipeline.bench.ocr_bench --scan-dir "G:\\My Drive\\<thư mục có PDF scan>" --n 20      # chọn trang scan để đo tốc độ/RAM
  python -m pipeline.bench.ocr_bench --pages pipeline/bench/out/pages.json --models tesseract,ppocrv5,ppocrv6

pages.json: [{"id": "kdc-001", "pdf": "đường/dẫn.pdf", "page": 3, "truth": "đường/dẫn/kdc-001.txt" (tùy chọn)}]
CER, lỗi dấu và số tiền/số văn bản chỉ tính được cho trang có `truth` (bản gõ đúng do người cung cấp).
Số đo giây/trang và RAM đỉnh trên Z2 chỉ mang tính tham khảo: production là CPU của VPS 169.
"""
import argparse
import json
import os
import statistics
import sys
import tempfile
import threading
import time
from pathlib import Path

from . import engines, metrics


class PeakRss:
    """Đo RAM đỉnh của tiến trình bằng lấy mẫu (psutil; không dùng module `resource` vì chỉ có trên Unix)."""

    def __init__(self, interval=0.05):
        import psutil
        self.p, self.interval, self.peak, self._stop = psutil.Process(), interval, 0, threading.Event()
        self._t = threading.Thread(target=self._run, daemon=True)

    def _run(self):
        while not self._stop.is_set():
            try:
                self.peak = max(self.peak, self.p.memory_info().rss)
            except Exception:  # noqa: BLE001
                pass
            time.sleep(self.interval)

    def __enter__(self):
        self._t.start()
        return self

    def __exit__(self, *a):
        self._stop.set()
        self._t.join(1)
        self.peak = max(self.peak, self.p.memory_info().rss)

    @property
    def mb(self):
        return round(self.peak / 1048576)


def render(pdf, page, dpi, out):
    import pymupdf
    doc = pymupdf.open(str(pdf))
    try:
        doc[page - 1].get_pixmap(dpi=dpi).save(str(out))
    finally:
        doc.close()


def pick_scan_pages(root, n, min_chars=30, max_pdfs=60, max_side_pts=1300):
    """Chọn n trang không có lớp chữ (scan) từ các PDF dưới `root`, rải đều qua nhiều tệp.
    Bỏ trang khổ lớn (cạnh dài > max_side_pts, ~A3): bản đồ/bản vẽ không đại diện cho văn bản scan và rất nặng."""
    import pymupdf
    pdfs = sorted(Path(root).rglob('*.pdf'))[:max_pdfs * 3]
    per_file, out = {}, []
    for pdf in pdfs:
        try:
            doc = pymupdf.open(str(pdf))
        except Exception:  # noqa: BLE001
            continue
        try:
            cand = [i + 1 for i in range(min(doc.page_count, 40))
                    if len(doc[i].get_text().strip()) < min_chars and doc[i].get_images() and max(doc[i].rect.width, doc[i].rect.height) <= max_side_pts]
        finally:
            doc.close()
        if cand:
            per_file[pdf] = cand
        if sum(len(v) for v in per_file.values()) >= n * 3:
            break
    while len(out) < n and any(per_file.values()):
        for pdf, cand in per_file.items():
            if cand and len(out) < n:
                pg = cand.pop(0)
                out.append({'id': f'p{len(out) + 1:03d}', 'pdf': str(pdf), 'page': pg, 'truth': None})
    return out


def run(pages, model_names, out_dir, dpi=300, log=print):
    out_dir = Path(out_dir)
    imgs = Path(tempfile.mkdtemp(prefix='ocrbench-'))
    results, summary = [], {}
    try:
        for p in pages:
            render(p['pdf'], p['page'], dpi, imgs / f"{p['id']}.png")
        for name in model_names:
            try:
                eng = engines.available(name)
            except ValueError as e:
                summary[name] = {'status': 'lỗi', 'reason': str(e)}
                continue
            with PeakRss() as mem:
                t0 = time.perf_counter()
                try:
                    eng.load()
                except engines.EngineUnavailable as e:
                    summary[eng.name] = {'status': 'không dùng được', 'reason': str(e)}
                    log(f'[{eng.name}] {e}')
                    continue
                load_s = time.perf_counter() - t0
                rows = []
                for p in pages:
                    t = time.perf_counter()
                    try:
                        text, conf = eng.ocr(imgs / f"{p['id']}.png")
                        err = ''
                    except Exception as e:  # noqa: BLE001
                        text, conf, err = '', None, f'{type(e).__name__}: {str(e)[:200]}'
                    sec = time.perf_counter() - t
                    d = out_dir / eng.name
                    d.mkdir(parents=True, exist_ok=True)
                    (d / f"{p['id']}.txt").write_text(text, encoding='utf-8', newline='\n')
                    row = {'model': eng.name, 'id': p['id'], 'sec': round(sec, 2), 'conf': None if conf is None else round(conf, 3),
                           'chars': len(text), 'error': err}
                    if p.get('truth'):
                        truth = Path(p['truth']).read_text(encoding='utf-8')
                        row['metrics'] = metrics.compare(truth, text)
                        row['tokens'] = {k: list(v) for k, v in metrics.token_misses(truth, text).items()}
                    rows.append(row)
                    log(f"[{eng.name}] {p['id']}: {sec:.1f}s conf={row['conf']}")
            results += rows
            summary[eng.name] = summarize(rows, load_s, mem.mb, getattr(eng, 'rec_model', ''), getattr(eng, 'version', ''))
    finally:
        import shutil
        shutil.rmtree(imgs, ignore_errors=True)
    return results, summary


def summarize(rows, load_s, peak_mb, rec_model='', version=''):
    ok = [r for r in rows if not r['error']]
    s = {'status': 'ok', 'pages': len(rows), 'errors': len(rows) - len(ok), 'load_s': round(load_s, 1), 'peak_rss_mb': peak_mb,
         'sec_per_page': round(statistics.mean(r['sec'] for r in ok), 2) if ok else None,
         'conf_mean': round(statistics.mean(r['conf'] for r in ok if r['conf'] is not None), 3) if any(r['conf'] is not None for r in ok) else None,
         'rec_model': rec_model, 'version': version}
    ev = [r for r in ok if 'metrics' in r]
    if ev:
        chars = sum(r['metrics']['chars'] for r in ev) or 1
        err = sum(r['metrics']['sub'] + r['metrics']['del'] + r['metrics']['ins'] for r in ev)
        s.update(pages_with_truth=len(ev), cer=round(err / chars, 4), dia_rate=round(sum(r['metrics']['dia'] for r in ev) / chars, 4))
        for kind in ('tien', 'so_van_ban'):
            tot = sum(r['tokens'][kind][0] for r in ev)
            miss = sum(r['tokens'][kind][1] for r in ev)
            s[f'{kind}_sai'] = f'{miss}/{tot}'
    return s


def report_md(summary, n_pages):
    lines = [f'# Benchmark OCR ({n_pages} trang)', '',
             '| Model | Trạng thái | Giây/trang | RAM đỉnh MB | Tin cậy TB | CER | Lỗi dấu | Số tiền sai | Số văn bản sai | Ghi chú |',
             '|---|---|---|---|---|---|---|---|---|---|']
    for name, s in summary.items():
        if s.get('status') != 'ok':
            lines.append(f"| {name} | {s['status']} | | | | | | | | {s.get('reason', '')[:140]} |")
            continue
        lines.append(f"| {name} | ok | {s['sec_per_page']} | {s['peak_rss_mb']} | {s['conf_mean']} | {s.get('cer', 'chưa có bản đúng')} | "
                     f"{s.get('dia_rate', '')} | {s.get('tien_sai', '')} | {s.get('so_van_ban_sai', '')} | nạp {s['load_s']}s; lỗi {s['errors']}; {s['rec_model'] or s['version']} |")
    return '\n'.join(lines) + '\n'


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--pages')
    ap.add_argument('--scan-dir')
    ap.add_argument('--n', type=int, default=20)
    ap.add_argument('--models', default='tesseract,ppocrv5,ppocrv6')
    ap.add_argument('--out', default=str(Path(__file__).parent / 'out'))
    ap.add_argument('--dpi', type=int, default=300)
    ap.add_argument('--limit', type=int)
    a = ap.parse_args(argv)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    if a.scan_dir:
        pages = pick_scan_pages(a.scan_dir, a.n)
        (out / 'pages.json').write_text(json.dumps(pages, ensure_ascii=False, indent=1), encoding='utf-8')
        print(f'Đã chọn {len(pages)} trang scan → {out / "pages.json"} (thêm "truth" cho trang đã có bản gõ đúng)')
        if not a.pages:
            a.pages = str(out / 'pages.json')
    if not a.pages:
        ap.error('cần --pages hoặc --scan-dir')
    pages = json.loads(Path(a.pages).read_text(encoding='utf-8'))
    if a.limit:
        pages = pages[:a.limit]
    results, summary = run(pages, [m.strip() for m in a.models.split(',') if m.strip()], out, a.dpi)
    (out / 'results.json').write_text(json.dumps({'summary': summary, 'rows': results}, ensure_ascii=False, indent=1), encoding='utf-8')
    (out / 'results.md').write_text(report_md(summary, len(pages)), encoding='utf-8')
    print(report_md(summary, len(pages)))
    return 0


if __name__ == '__main__':
    os.environ.setdefault('PYTHONUTF8', '1')
    sys.exit(main())
