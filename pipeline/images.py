"""Ảnh nguồn → JPEG nén: cạnh dài ≤ 2000 px, chất lượng 85, HEIC đổi sang JPEG, giữ ngày chụp EXIF.

MCP nạp ảnh ≤ 10 MB; quá mức đó thì giảm chất lượng/kích thước cho tới khi vừa.
Chỉ đọc nguồn và ghi byte JPEG: không sửa ảnh gốc.
"""
import io

EXIF_ORIENTATION = 0x0112
EXIF_DATE_TAGS = (0x9003, 0x9004, 0x0132)     # DateTimeOriginal, DateTimeDigitized, DateTime


def compress(path, cfg):
    """Trả (bytes JPEG, mô tả). Ném ngoại lệ nếu không đọc được ảnh."""
    from PIL import Image, ImageOps
    try:
        import pillow_heif
        pillow_heif.register_heif_opener()
    except ImportError:
        pass                                    # không có pillow-heif thì HEIC báo lỗi ở Image.open
    with Image.open(path) as im:
        im.seek(0)                              # TIFF/GIF nhiều khung: lấy khung đầu
        src_size, fmt = im.size, im.format
        exif = im.getexif()
        date = next((exif.get(t) for t in EXIF_DATE_TAGS if exif.get(t)), None)
        if not date:                            # ngày chụp có thể nằm trong IFD con của EXIF
            sub = exif.get_ifd(0x8769) if hasattr(exif, 'get_ifd') else {}
            date = next((sub.get(t) for t in EXIF_DATE_TAGS if sub.get(t)), None)
        img = ImageOps.exif_transpose(im)       # xoay đúng chiều rồi bỏ cờ xoay
        if img.mode != 'RGB':
            img = img.convert('RGB')
        if EXIF_ORIENTATION in exif:
            exif[EXIF_ORIENTATION] = 1
        img.load()
    side = max(img.size)
    if side > cfg.image_max_side:
        k = cfg.image_max_side / side
        img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    q = cfg.image_quality
    while True:
        buf = io.BytesIO()
        img.save(buf, 'JPEG', quality=q, optimize=True, exif=exif.tobytes())
        if buf.tell() <= cfg.image_max_bytes:
            break
        if q > 50:
            q -= 10
        elif max(img.size) > 600:
            img = img.resize((round(img.width * 0.8), round(img.height * 0.8)), Image.LANCZOS)
        else:
            raise ValueError(f'Không nén được ảnh xuống {cfg.image_max_bytes // 1048576} MB')
    return buf.getvalue(), {'format': fmt, 'src_size': src_size, 'out_size': img.size, 'quality': q, 'exif_date': date}
