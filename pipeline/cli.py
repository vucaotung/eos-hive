"""Dòng lệnh: python -m pipeline fetch|run|push <slug> ...

  fetch <slug> <id thư mục Drive>            tải qua Drive API (GOOGLE_* trong môi trường)
  fetch <slug> --source-dir <thư mục>        chép từ thư mục cục bộ (Drive for Desktop; để phát triển)
  run   <slug>                               chuyển Markdown + mục lục
  push  <slug> <id thư mục Drive nguồn>      đẩy lên <nguồn>/_md_deo, ghi push/<slug>.json
Mã thoát 0 = xong; 2 = tham số sai; 1 = lỗi. Không in bí mật.
"""
import argparse
import os
import sys
from pathlib import Path

from . import config
from .config import SAFE_ID, SLUG, Config


def _parser():
    p = argparse.ArgumentParser(prog='pipeline', description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    f = sub.add_parser('fetch')
    f.add_argument('slug')
    f.add_argument('folder_id', nargs='?')
    f.add_argument('--source-dir')
    r = sub.add_parser('run')
    r.add_argument('slug')
    u = sub.add_parser('push')
    u.add_argument('slug')
    u.add_argument('folder_id')
    return p


def main(argv=None, client_factory=None):
    args = _parser().parse_args(argv)
    config.load_env_file(os.environ.get('DEO_ENV_FILE') or Path(__file__).with_name('.env'))
    if not SLUG.match(args.slug):
        print('Tên dự án (slug) không hợp lệ', file=sys.stderr)
        return 2
    cfg = Config()
    mk = client_factory or (lambda: __import__('pipeline.drive', fromlist=['Drive']).Drive.from_env())
    try:
        if args.cmd == 'fetch':
            from . import fetch
            if args.source_dir:
                n = fetch.fetch_local(args.slug, args.source_dir, cfg)
            elif args.folder_id and SAFE_ID.match(args.folder_id):
                n = fetch.fetch_drive(args.slug, args.folder_id, cfg, mk())
            else:
                print('Cần id thư mục Drive hợp lệ hoặc --source-dir', file=sys.stderr)
                return 2
            print(f'fetch: {n} tệp trong manifest ({cfg.manifest(args.slug)})')
        elif args.cmd == 'run':
            from .run import run_project
            s = run_project(args.slug, cfg)
            print(f"run: tổng {s['total']}, có Markdown {s['ok']}, ảnh nén {s['images']}, lỗi {s['error']}, không chuyển đổi {s['skip']}, cần soát OCR {s['need_ocr']}")
        else:
            if not SAFE_ID.match(args.folder_id):
                print('id thư mục Drive không hợp lệ', file=sys.stderr)
                return 2
            from .push import push
            r = push(args.slug, args.folder_id, cfg, mk())
            print(f"push: {r['files']} tệp lên _md_deo ({r['md_folder_id']})")
        return 0
    except Exception as e:  # noqa: BLE001
        print(f'LỖI {type(e).__name__}: {str(e)[:300]}', file=sys.stderr)
        return 1
