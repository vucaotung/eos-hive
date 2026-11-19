// Văn bản pháp luật lấy từ nguồn chính thống DO MÁY CHỦ tải và chuyển Markdown (eos_law_save_from_source):
// agent không phải chép lại nguyên văn (luật dài ~140.000 ký tự vượt khả năng gõ lại và dễ sai chữ).
// Chặn SSRF: chỉ https, chỉ tên miền nguồn chính thống (kiểm lại ở mỗi lần chuyển hướng), không IP nội bộ, trần dung lượng và thời gian.
import { spawn } from 'node:child_process';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { lookup as dnsLookup } from 'node:dns/promises';
import { isIP } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { sourceAllowed, lawDomains, LAW_REQUIRED } from './law.mjs';

export const FILE_MAX_BYTES = 30 * 1024 * 1024;
export const LAW_OPTIONAL = ['loai', 'ngay_hieu_luc', 'thay_the', 'sua_doi', 'linh_vuc', 'buoc'];
// Tệp toàn văn của cổng Chính phủ nằm ở tên miền con (datafiles.chinhphu.vn) và CDN của cổng (*.cdnchinhphu.vn)
export const DEFAULT_FILE_EXTRA = ['*.chinhphu.vn', '*.cdnchinhphu.vn'];

export const fileDomains = () => {
  const env = (process.env.LAW_FILE_DOMAINS || '').split(',').map((d) => d.trim().toLowerCase()).filter(Boolean);
  return env.length ? env : [...new Set([...lawDomains(), ...DEFAULT_FILE_EXTRA])];
};

// IP nội bộ/đặc biệt (v4 và v6) không bao giờ được tải
export function privateIp(ip) {
  const v = isIP(ip);
  if (v === 4) {
    const [a, b] = ip.split('.').map(Number);
    return a === 0 || a === 10 || a === 127 || (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31)
      || (a === 192 && b === 168) || (a === 198 && (b === 18 || b === 19)) || a >= 224;
  }
  if (v === 6) {
    const s = ip.toLowerCase();
    if (s.startsWith('::ffff:')) return privateIp(s.slice(7));
    return s === '::' || s === '::1' || /^f[cd]/.test(s) || /^fe[89ab]/.test(s) || s.startsWith('ff');
  }
  return true;
}

async function checkHost(url, domains, lookup) {
  const s = sourceAllowed(url, domains);
  if (!s.ok) throw new Error(s.reason.replace(/^Nguồn/, 'Tệp nguồn'));
  const host = new URL(url).hostname;
  if (isIP(host)) throw new Error('Tệp nguồn phải dùng tên miền, không dùng địa chỉ IP');
  const addrs = await lookup(host, { all: true });
  if (!addrs.length || addrs.some((a) => privateIp(a.address))) throw new Error(`Tên miền ${host} trỏ tới địa chỉ nội bộ; không tải`);
}

// Tải tệp: chuyển hướng tự xử lý (tối đa 5 lần), mỗi chặng kiểm lại tên miền; đọc dần, dừng khi quá trần.
export async function fetchOfficial(url, { domains = fileDomains(), fetchImpl = fetch, lookup = dnsLookup, maxBytes = FILE_MAX_BYTES, timeoutMs = 90_000, maxRedirects = 5 } = {}) {
  let cur = String(url);
  const signal = AbortSignal.timeout(timeoutMs);
  for (let hop = 0; hop <= maxRedirects; hop++) {
    await checkHost(cur, domains, lookup);
    const r = await fetchImpl(cur, { redirect: 'manual', signal, headers: { 'User-Agent': 'EnterpriseOS-Law/1.0 (+https://work.enterpriseos.bond)', Accept: '*/*' } });
    if (r.status >= 300 && r.status < 400) {
      const loc = r.headers.get('location');
      if (!loc) throw new Error(`Chuyển hướng ${r.status} không có đích`);
      cur = new URL(loc, cur).toString();
      continue;
    }
    if (r.status !== 200) throw new Error(`Máy chủ nguồn trả mã ${r.status} cho ${cur}`);
    const len = Number(r.headers.get('content-length') || 0);
    if (len > maxBytes) throw new Error(`Tệp ${Math.round(len / 1048576)} MB vượt trần ${maxBytes / 1048576} MB`);
    const chunks = []; let size = 0;
    for await (const ch of r.body) {
      size += ch.length;
      if (size > maxBytes) throw new Error(`Tệp vượt trần ${maxBytes / 1048576} MB`);
      chunks.push(Buffer.from(ch));
    }
    return { bytes: Buffer.concat(chunks), contentType: (r.headers.get('content-type') || '').toLowerCase(), finalUrl: cur };
  }
  throw new Error(`Quá ${maxRedirects} lần chuyển hướng`);
}

// Nhận dạng loại tệp theo nội dung (không tin đuôi URL)
export function sniffKind(buf, contentType = '') {
  if (buf.length >= 5 && buf.subarray(0, 5).toString('latin1') === '%PDF-') return 'pdf';
  if (buf.length >= 4 && buf.readUInt32BE(0) === 0x504b0304) return buf.includes('word/document.xml') ? 'docx' : null;
  if (buf.length >= 8 && buf.subarray(0, 8).equals(Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]))) return 'doc';
  const head = buf.subarray(0, 2048).toString('utf8').replace(/^﻿/, '').trimStart().toLowerCase();
  if (contentType.includes('text/html') || head.startsWith('<!doctype html') || head.startsWith('<html') || /<html[\s>]/.test(head)) return 'html';
  return null;
}

// Chữ Việt có dấu trên tổng số chữ cái: văn bản tiếng Việt thường > 0,1; bản lỗi font (TCVN3/VNI hiển thị sai) gần 0.
const VIET = /[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]/giu;
// Ký tự Latin-1 không thuộc bảng chữ Việt (§ ¬ ® © ¹ Ë Ò ­ …): dấu hiệu chữ TCVN3/VNI hiển thị sai; văn bản Unicode đúng gần như không có.
const ODD = /[¡-¿Ä-ÇËÎ-ÑÖØÛÜÞßä-çëî-ñöøûüþÿ]/gu;
const KEEP = /[°«»·±]/gu;   // có thể gặp trong văn bản đúng
export function vietQuality(text) {
  const t = String(text).normalize('NFC');
  const letters = (t.match(/\p{L}/gu) || []).length;
  const viet = (t.match(VIET) || []).length;
  const odd = (t.replace(KEEP, '').match(ODD) || []).length;
  return { letters, viet, odd, ratio: letters ? viet / letters : 0, oddRatio: letters ? odd / letters : 0 };
}

const fold = (s) => String(s).normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[đĐ]/g, 'd').toLowerCase().replace(/\s+/g, '');
export const bodyHasSoHieu = (soHieu, body) => fold(body).includes(fold(soHieu));

// Số điều khác nhau có tiêu đề ("Điều 1.", "# **Điều 1.**", "**Điều 39.** dính cuối đoạn trước"); bỏ qua dẫn chiếu giữa câu ("theo Điều 4 của …")
export const countDieu = (body) => new Set([...String(body).matchAll(/(?:^|\n|\*\*)[ \t#*_]*Điều\s+(\d+)[a-zđ]?[\s*_]*[.:]/gu)].map((m) => +m[1])).size;

// Ghép front matter (chỉ khóa đã biết, một dòng mỗi khóa) với thân văn bản
export function buildLawMarkdown(meta, body) {
  const one = (v) => String(v ?? '').replace(/[\r\n]+/g, ' ').trim();
  const lines = [...LAW_REQUIRED, ...LAW_OPTIONAL].filter((k) => one(meta[k]) !== '').map((k) => `${k}: ${one(meta[k])}`);
  return `---\n${lines.join('\n')}\n---\n\n${String(body).replace(/^﻿/, '').trim()}\n`;
}

// Gọi bộ chuyển của pipeline (Python, cùng venv với runner): python -m pipeline.law_convert <tệp> <loại> → một dòng JSON
export async function convertFile(buf, kind, { python = process.env.LAW_CONVERT_PYTHON || '/opt/apps/enterprise-os/venv/bin/python',
  cwd = process.env.LAW_CONVERT_CWD || '/opt/apps/enterprise-os', timeoutMs = 240_000, spawnImpl = spawn } = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'eos-law-'));
  try {
    const file = join(dir, `van-ban.${kind}`);
    await writeFile(file, buf);
    const env = { PATH: process.env.PATH || '/usr/bin:/bin', HOME: dir, PYTHONUTF8: '1', LANG: 'C.UTF-8', TESSERACT_CMD: '',
      SOFFICE_BIN: process.env.SOFFICE_BIN || '/usr/bin/soffice', WORK_DIR: dir };
    const out = await new Promise((resolve, reject) => {
      const p = spawnImpl(python, ['-m', 'pipeline.law_convert', file, kind], { cwd, env, stdio: ['ignore', 'pipe', 'pipe'] });
      let so = '', se = '', big = false;
      const t = setTimeout(() => { p.kill('SIGKILL'); reject(new Error(`Chuyển đổi quá ${timeoutMs / 1000} giây`)); }, timeoutMs);
      p.stdout.on('data', (d) => { if (so.length < 40_000_000) so += d; else big = true; });
      p.stderr.on('data', (d) => { if (se.length < 4000) se += d; });
      p.on('error', (e) => { clearTimeout(t); reject(new Error(`Không chạy được bộ chuyển đổi (${e.code || e.message}); kiểm LAW_CONVERT_PYTHON`)); });
      p.on('close', () => { clearTimeout(t); big ? reject(new Error('Kết quả chuyển đổi quá lớn')) : resolve({ so, se }); });
    });
    const line = out.so.trim().split('\n').pop() || '';
    let j; try { j = JSON.parse(line); } catch { throw new Error(`Bộ chuyển đổi không trả JSON: ${(out.se || line).slice(-300)}`); }
    if (!j.ok) throw new Error(j.error || 'Chuyển đổi thất bại');
    return j;
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

// Kiểm chất lượng nguyên văn sau chuyển đổi; trả danh sách lỗi (rỗng = đạt)
export function checkConverted(soHieu, body) {
  const errors = [];
  const q = vietQuality(body);
  if (q.letters > 1500 && (q.ratio < 0.04 || q.oddRatio > 0.02))
    errors.push(`Chữ trong tệp có vẻ lỗi font (${(q.ratio * 100).toFixed(1)}% chữ có dấu tiếng Việt, ${(q.oddRatio * 100).toFixed(1)}% ký tự lạ kiểu TCVN3/VNI). Bản PDF trên vanban.chinhphu.vn/moc.gov.vn của luật mới hay bị lỗi này: dùng bản Công báo số (congbao.chinhphu.vn, tệp DOCX/PDF có lớp chữ Unicode).`);
  if (!bodyHasSoHieu(soHieu, body)) errors.push(`Không thấy số hiệu "${soHieu}" trong nội dung tệp: có thể sai tệp, hoặc so_hieu cần ghi đúng như trong văn bản (vd. "135/2025/QH15", không kèm "Luật số").`);
  return errors;
}
