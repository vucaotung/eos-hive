#!/usr/bin/env python3
"""Đóng gói PWA: web/app.html (+ vỏ HTML, icon, manifest, sw) → dist/.  Chạy: python3 build.py"""
import pathlib, shutil
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).parent
WEB, DIST = ROOT / "web", ROOT / "dist"
shutil.rmtree(DIST, ignore_errors=True); DIST.mkdir()

HEAD = """<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#EDEFEB" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#0F1217" media="(prefers-color-scheme: dark)">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="Dẹo Việc">
<meta name="format-detection" content="telephone=no">
<link rel="manifest" href="/manifest.webmanifest">
<link rel="icon" href="/icon-192.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
"""
TAIL = """<script src="/register-sw.js" defer></script>
</body>
</html>
"""
app = (WEB / "app.html").read_text(encoding="utf-8")
# Tách CSS và JS ra tệp riêng: cache được, và CSP không cần 'unsafe-inline'
css = app[app.index("<style>") + 7:app.index("</style>")]
js = app[app.index("<script>") + 8:app.index("</script>")]
head_part = app[:app.index("<style>")] + '<link rel="stylesheet" href="/app.css">\n<script src="/app.js" defer></script>\n'
body_part = app[app.index("</style>") + 8:app.index("<script>")]
BASE = ":root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0}img{max-width:100%}[hidden]{display:none!important}\n"
(DIST / "app.css").write_text(BASE + css.strip() + "\n", encoding="utf-8")
(DIST / "app.js").write_text(js.strip() + "\n", encoding="utf-8")
(DIST / "index.html").write_text(HEAD + head_part + "</head>\n<body>\n" + body_part + TAIL, encoding="utf-8")
for f in ("sw.js", "manifest.webmanifest"):
    shutil.copy(WEB / f, DIST / f)

def icon(size, pad, path):
    s = size * 4
    im = Image.new("RGBA", (s, s), (179, 38, 30, 255))
    d = ImageDraw.Draw(im)
    inset = int(s * pad)
    # ô vuông + dấu tích: "việc đã duyệt"
    r = s - 2 * inset
    d.rounded_rectangle([inset + r * .18, inset + r * .18, inset + r * .82, inset + r * .82], radius=int(r * .12), outline=(255, 255, 255, 255), width=int(r * .07))
    d.line([(inset + r * .33, inset + r * .51), (inset + r * .46, inset + r * .64), (inset + r * .69, inset + r * .38)], fill=(255, 255, 255, 255), width=int(r * .08), joint="curve")
    im.resize((size, size), Image.LANCZOS).save(path)

icon(192, 0.0, DIST / "icon-192.png")
icon(512, 0.0, DIST / "icon-512.png")
icon(512, 0.12, DIST / "icon-maskable-512.png")
icon(180, 0.0, DIST / "apple-touch-icon.png")
(DIST / "register-sw.js").write_text('if("serviceWorker" in navigator){addEventListener("load",()=>navigator.serviceWorker.register("/sw.js").catch(()=>{}))}\n', encoding="utf-8")
print("dist:", sorted(p.name for p in DIST.iterdir()))
