#!/usr/bin/env python3
"""Kiểm định dạng skill Hermes trong deploy/hermes-skills (make test-skills).
Mỗi skill: frontmatter đủ (name = tên thư mục, description, version semver, metadata.hermes.tags), có mục "Giới hạn tuyệt đối", có mục quy trình/quy tắc,
mọi `references/…` được nhắc đều tồn tại, mọi công cụ `eos_*` được nhắc đều là công cụ thật của máy chủ MCP.
Các skill của đợt 0.6 (V06) KHÔNG được đóng cứng số hiệu luật/nghị định/thông tư/quyết định (căn cứ phải tra lúc dùng theo tra-cuu-phap-luat)."""
import os, re, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SK = os.path.join(ROOT, 'deploy', 'hermes-skills')
V06 = {'so-do-20-buoc', 'tra-cuu-phap-luat', 'nap-van-ban-phap-luat', 'qlda-chuan-bi', 'qlda-thuc-hien', 'qlda-ket-thuc', 'bao-tri-wiki', 'ra-hieu-luc-phap-luat'}
# số hiệu văn bản pháp luật: 123/2024/NĐ-CP, 15/2021/TT-BXD, 1475/QĐ-UBND, Luật số 50/2014/QH13, TCVN 5574…
LAW_NO = re.compile(r'\b\d{1,4}/(?:\d{4}/)?(?:NĐ|ND|TT|QĐ|QD|NQ|QH\d*|CT|TTg|UBTVQH)[A-Za-zĐđ\-]*|\b\d{1,4}/\d{4}/[A-ZĐ]{2,}[A-Za-zĐ\-]*|TCVN\s*\d|QCVN\s*\d', re.I)
# công cụ do máy chủ khác cung cấp hoặc của Hermes (không nằm trong tools.mjs)
EXTRA_TOOLS = set()
# enterprise-os-guide là sổ tay hướng dẫn người dùng/bot, không phải skill làm việc: không bắt buộc mục "Giới hạn tuyệt đối" và mục quy trình
GUIDES = {'enterprise-os-guide'}

def tools():
    src = open(os.path.join(ROOT, 'mcp', 'src', 'tools.mjs'), encoding='utf8').read()
    return set(re.findall(r"tool\('(eos_[a-z_]+)'", src)) | {'eos_whoami', 'eos_my_day'} | EXTRA_TOOLS

def frontmatter(text):
    m = re.match(r'---\n(.*?)\n---\n', text, re.S)
    if not m: return None, text
    fm, block = {}, m.group(1)
    for key in ('name', 'description', 'version', 'author', 'license'):
        k = re.search(rf'^{key}:\s*(.+)$', block, re.M)
        if k: fm[key] = k.group(1).strip()
    fm['tags'] = re.search(r'^\s+tags:\s*\[(.+)\]\s*$', block, re.M) is not None
    return fm, text[m.end():]

def check():
    errs, known = [], tools()
    for name in sorted(os.listdir(SK)):
        d = os.path.join(SK, name); f = os.path.join(d, 'SKILL.md')
        if not os.path.isdir(d): continue
        if not os.path.exists(f): errs.append(f'{name}: thiếu SKILL.md'); continue
        text = open(f, encoding='utf8').read(); fm, body = frontmatter(text)
        if fm is None: errs.append(f'{name}: thiếu frontmatter'); continue
        if fm.get('name') != name: errs.append(f'{name}: name "{fm.get("name")}" khác tên thư mục')
        if not (30 <= len(fm.get('description', '')) <= 1500): errs.append(f'{name}: description phải dài 30–1500 ký tự')
        if not re.fullmatch(r'\d+\.\d+\.\d+', fm.get('version', '')): errs.append(f'{name}: version không phải semver')
        for k in ('author', 'license'):
            if not fm.get(k): errs.append(f'{name}: thiếu {k}')
        if not fm['tags']: errs.append(f'{name}: thiếu metadata.hermes.tags')
        if name not in GUIDES and 'Giới hạn tuyệt đối' not in body: errs.append(f'{name}: thiếu mục "Giới hạn tuyệt đối"')
        if name not in GUIDES and not re.search(r'^## (Quy trình|Quy tắc|Hai chế độ|Thứ tự nguồn)', body, re.M): errs.append(f'{name}: thiếu mục quy trình/quy tắc')
        for ref in set(re.findall(r'references/([A-Za-z0-9_.\-]+)', body)):
            if ref[-1] in '_-.' : continue   # tiền tố dạng glob, ví dụ references/vi_du_*.json
            if not os.path.exists(os.path.join(d, 'references', ref)): errs.append(f'{name}: nhắc references/{ref} nhưng không có tệp')
        for t in set(re.findall(r'\beos_[a-z_]+\b', body)):
            if t.endswith('_'): continue   # tiền tố dạng eos_project_*
            if t not in known: errs.append(f'{name}: nhắc công cụ "{t}" không có trong máy chủ MCP')
        if name in V06:
            files = [f] + [os.path.join(d, 'references', x) for x in (os.listdir(os.path.join(d, 'references')) if os.path.isdir(os.path.join(d, 'references')) else [])]
            for p in files:
                for m in LAW_NO.finditer(open(p, encoding='utf8').read()):
                    errs.append(f'{name}: số hiệu văn bản bị đóng cứng "{m.group(0)}" trong {os.path.relpath(p, SK)}')
    return errs

def check_weknora_texts():
    """deploy/weknora/*.txt là nội dung dán vào wiki_config của KB mẫu: content_instructions tối đa 4000 byte (giới hạn WeKnora); giữ cùng giới hạn cho extraction_instructions.
    Không chứa số hiệu văn bản pháp luật; quy tắc gộp trang của KB dự án phải đủ 5 ý theo plan v6."""
    errs, d = [], os.path.join(ROOT, 'deploy', 'weknora')
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if not f.endswith('.txt'): continue
        t = open(os.path.join(d, f), encoding='utf8').read()
        if len(t.encode('utf8')) > 4000: errs.append(f'weknora/{f}: {len(t.encode("utf8"))} byte > 4000')
        for m in LAW_NO.finditer(t): errs.append(f'weknora/{f}: số hiệu bị đóng cứng "{m.group(0)}"')
        if f.startswith('wiki_extraction_'):
            for k in ('cùng chủ thể', 'mâu thuẫn', 'liên kết', 'gộp', 'nguồn'):
                if k not in t: errs.append(f'weknora/{f}: thiếu ý "{k}" trong quy tắc gộp trang')
    return errs

if __name__ == '__main__':
    errs = check() + check_weknora_texts()
    n = len([x for x in os.listdir(SK) if os.path.isdir(os.path.join(SK, x))])
    if errs:
        print('\n'.join(errs), file=sys.stderr); print(f'check_skills: THẤT BẠI ({len(errs)} lỗi)', file=sys.stderr); sys.exit(1)
    print(f'check_skills: ĐẠT ({n} skill)')
