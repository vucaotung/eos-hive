// Máy khách WeKnora (kho tri thức) chạy ở máy chủ MCP trên vps169. Khóa API chỉ nằm trong .env của MCP (WEKNORA_BASE_URL, WEKNORA_API_KEY);
// agent Hermes không bao giờ thấy khóa, và VPS 173 không gọi WeKnora (DEO-INGEST-RULE).
const base = () => (process.env.WEKNORA_BASE_URL || '').replace(/\/+$/, '');
export const configured = () => Boolean(base() && process.env.WEKNORA_API_KEY);
export const TEMPLATE_KB = () => process.env.WEKNORA_TEMPLATE_KB || 'kdc-thanh-lap';   // KB mẫu: sao chép cấu hình mô hình nhúng và chia đoạn

async function wk(method, path, body) {
  const r = await fetch(`${base()}${path}`, {
    method, signal: AbortSignal.timeout(90_000),
    headers: { 'X-API-Key': process.env.WEKNORA_API_KEY, Accept: 'application/json', ...(body ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let j = null; try { j = JSON.parse(text); } catch { /* không phải JSON */ }
  if (!r.ok) { const e = new Error(`WeKnora ${r.status}: ${(j?.error?.message || j?.message || text).toString().slice(0, 200)}`); e.status = r.status; throw e; }
  return j;
}

export async function listKbs() { return (await wk('GET', '/knowledge-bases'))?.data || []; }

// Tìm KB theo tên, chưa có thì tạo với cấu hình sao chép từ KB mẫu. Trả {id, created}.
export async function ensureKb(name, description) {
  const all = await listKbs();
  const same = all.find((k) => k.name === name);
  if (same) return { id: same.id, created: false };
  const tpl = all.find((k) => k.name === TEMPLATE_KB());
  if (!tpl) throw new Error(`Không thấy KB mẫu "${TEMPLATE_KB()}" để sao chép cấu hình (đặt WEKNORA_TEMPLATE_KB)`);
  const j = await wk('POST', '/knowledge-bases', {
    name, description: description || '', type: 'document',
    embedding_model_id: tpl.embedding_model_id, summary_model_id: tpl.summary_model_id, chunking_config: tpl.chunking_config,
  });
  const id = j?.data?.id;
  if (!id) throw new Error('WeKnora không trả mã KB mới');
  return { id, created: true };
}

// Thêm một tài liệu Markdown (nội dung văn bản) vào KB. Trả mã tài liệu.
export async function addMarkdown(kbId, title, content) {
  const j = await wk('POST', `/knowledge-bases/${encodeURIComponent(kbId)}/knowledge/manual`, { title, content, status: 'publish' });
  const id = j?.data?.id;
  if (!id) throw new Error('WeKnora không trả mã tài liệu');
  return id;
}

// Bỏ front-matter YAML của Markdown do deo_md.py sinh (sha256, drive_id… không đưa vào đoạn chia), giữ một dòng nguồn ngắn.
export function prepare(name, text) {
  let t = text, meta = {};
  if (t.startsWith('---\n')) {
    const e = t.indexOf('\n---', 4);
    if (e !== -1) {
      for (const l of t.slice(4, e).split('\n')) { const i = l.indexOf(': '); if (i > 0) meta[l.slice(0, i).trim()] = l.slice(i + 2).trim().replace(/^"|"$/g, ''); }
      t = t.slice(e + 4).replace(/^\n+/, '');
    }
  }
  const src = (meta.source_path || name).split('/').pop();
  return { title: name.replace(/\.md$/i, '').slice(0, 200), content: `Nguồn: ${src}\n\n${t}`, pages: /^\d+$/.test(meta.pages || '') ? Number(meta.pages) : null };
}
