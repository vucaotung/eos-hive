// Máy khách WeKnora (kho tri thức) chạy ở máy chủ MCP trên vps169. Khóa API chỉ nằm trong .env của MCP (WEKNORA_BASE_URL, WEKNORA_API_KEY);
// agent Hermes không bao giờ thấy khóa, và VPS 173 không gọi WeKnora (DEO-INGEST-RULE).
const base = () => (process.env.WEKNORA_BASE_URL || '').replace(/\/+$/, '');
export const configured = () => Boolean(base() && process.env.WEKNORA_API_KEY);
export const TEMPLATE_KB = () => process.env.WEKNORA_TEMPLATE_KB || 'kdc-thanh-lap';   // KB mẫu: sao chép cấu hình mô hình nhúng và chia đoạn
// Ngôn ngữ xử lý tài liệu (Wiki, tóm tắt, câu hỏi gợi ý). WeKnora lấy từ Accept-Language, thiếu thì mặc định zh-CN (Wiki ra tiếng Trung).
// Mã lạ được đưa nguyên vào prompt ("Write in {{.Language}}"), nên gửi tên đầy đủ "Vietnamese". Biến WEKNORA_LANGUAGE trên máy WeKnora (nếu đặt) vẫn thắng.
export const DOC_LANGUAGE = () => process.env.WEKNORA_DOC_LANGUAGE || 'Vietnamese';

// body: object → JSON; FormData → multipart (tự đặt Content-Type kèm boundary)
async function wk(method, path, body) {
  const form = typeof FormData !== 'undefined' && body instanceof FormData;
  const r = await fetch(`${base()}${path}`, {
    method, signal: AbortSignal.timeout(90_000),
    headers: { 'X-API-Key': process.env.WEKNORA_API_KEY, Accept: 'application/json', 'Accept-Language': DOC_LANGUAGE(), ...(body && !form ? { 'Content-Type': 'application/json' } : {}) },
    body: body ? (form ? body : JSON.stringify(body)) : undefined,
  });
  const text = await r.text();
  let j = null; try { j = JSON.parse(text); } catch { /* không phải JSON */ }
  if (!r.ok) { const e = new Error(`WeKnora ${r.status}: ${(j?.error?.message || j?.message || text).toString().slice(0, 200)}`); e.status = r.status; if (r.status === 409) e.existingId = j?.data?.id || j?.data?.knowledge?.id || j?.data?.existing?.id; throw e; }
  return j;
}

export async function listKbs() { return (await wk('GET', '/knowledge-bases'))?.data || []; }

// Cấu hình sao chép từ KB mẫu ngoài mô hình nhúng/chia đoạn: Wiki, chiến lược lập chỉ mục, VLM. KB mẫu thiếu trường nào thì bỏ qua trường đó.
const EXTRA_CONFIG = ['indexing_strategy', 'wiki_config', 'vlm_config'];
export function templateConfig(tpl) {
  const out = { embedding_model_id: tpl.embedding_model_id, summary_model_id: tpl.summary_model_id, chunking_config: tpl.chunking_config };
  const extra = {};
  for (const k of EXTRA_CONFIG) if (tpl[k] !== undefined && tpl[k] !== null) extra[k] = tpl[k];
  return { core: out, extra };
}

// Tìm KB theo tên, chưa có thì tạo với cấu hình sao chép từ KB mẫu. Trả {id, created, extra_config_ignored}.
// WeKnora cũ (v0.8.x) không có Wiki: nếu từ chối trường mở rộng (400/422) thì tạo lại chỉ với cấu hình lõi và ghi log, không làm hỏng lượt nạp.
export async function ensureKb(name, description, log = console.warn, { wiki = false } = {}) {
  const all = await listKbs();
  const same = all.find((k) => k.name === name);
  if (same) return { id: same.id, created: false };
  const tpl = all.find((k) => k.name === TEMPLATE_KB());
  if (!tpl) throw new Error(`Không thấy KB mẫu "${TEMPLATE_KB()}" để sao chép cấu hình (đặt WEKNORA_TEMPLATE_KB)`);
  const { core, extra } = templateConfig(tpl);
  if (wiki) {   // KB pháp luật luôn bật Wiki (nếu bản WeKnora hỗ trợ; bản cũ từ chối thì lùi về cấu hình lõi bên dưới)
    extra.indexing_strategy = { ...(extra.indexing_strategy || {}), wiki_enabled: true };
    extra.wiki_config = extra.wiki_config || { auto_generate: true, extraction_granularity: 'focused' };
  }
  const mk = (body) => wk('POST', '/knowledge-bases', { name, description: description || '', type: 'document', ...core, ...body });
  let j, ignored = false;
  try { j = await mk(extra); }
  catch (e) {
    if (!Object.keys(extra).length || ![400, 422].includes(e.status)) throw e;
    log(`WeKnora từ chối cấu hình mở rộng của KB mẫu (${e.message}); tạo KB chỉ với cấu hình lõi (bản WeKnora cũ?)`);
    j = await mk({}); ignored = true;
  }
  const id = j?.data?.id;
  if (!id) throw new Error('WeKnora không trả mã KB mới');
  return { id, created: true, extra_config_ignored: ignored };
}

// Thêm một tài liệu Markdown (nội dung văn bản) vào KB. Trả mã tài liệu.
export async function addMarkdown(kbId, title, content) {
  const j = await wk('POST', `/knowledge-bases/${encodeURIComponent(kbId)}/knowledge/manual`, { title, content, status: 'publish' });
  const id = j?.data?.id;
  if (!id) throw new Error('WeKnora không trả mã tài liệu');
  return id;
}

// Tải một tệp (ảnh…) lên KB bằng knowledge/file. Trùng nội dung (409) thì WeKnora trả bản đã có: coi như đã nạp. Trả {id, duplicate}.
export async function addFile(kbId, fileName, bytes, mime) {
  const fd = new FormData();
  fd.append('file', new Blob([bytes], { type: mime || 'application/octet-stream' }), fileName);
  fd.append('fileName', fileName);
  try {
    const j = await wk('POST', `/knowledge-bases/${encodeURIComponent(kbId)}/knowledge/file`, fd);
    const id = j?.data?.id;
    if (!id) throw new Error('WeKnora không trả mã tài liệu');
    return { id, duplicate: false };
  } catch (e) {
    if (e.status === 409 && e.existingId) return { id: e.existingId, duplicate: true };
    throw e;
  }
}

// custom_metadata của tài liệu (WeKnora ≥ 0.9): tối đa 20 khóa, khóa 1–64 ký tự, giá trị string/number/boolean/null ≤ 1000 ký tự; GHI ĐÈ CẢ OBJECT.
// Bản cũ không có (404/400/405…): đặt cờ metadataUnsupported, ghi log MỘT lần, các lần sau bỏ qua. Không bao giờ làm lỗi tệp.
export const state = { metadataUnsupported: false, logged: false };
export function cleanMetadata(m) {
  const out = {};
  for (const [k, v] of Object.entries(m || {})) {
    if (Object.keys(out).length >= 20) break;
    const key = String(k).slice(0, 64); if (!key) continue;
    if (v === null || typeof v === 'number' || typeof v === 'boolean') out[key] = v;
    else if (v !== undefined) out[key] = String(v).slice(0, 1000);
  }
  return out;
}
export async function setMetadata(docId, meta, log = console.warn) {
  if (state.metadataUnsupported) return { ok: false, reason: 'unsupported' };
  try {
    await wk('PUT', `/knowledge/${encodeURIComponent(docId)}`, { custom_metadata: cleanMetadata(meta) });
    return { ok: true };
  } catch (e) {
    if ([400, 404, 405, 422].includes(e.status)) {
      state.metadataUnsupported = true;
      if (!state.logged) { state.logged = true; log(`WeKnora không hỗ trợ custom_metadata (${e.message}); bỏ qua metadata cho các tệp sau`); }
      return { ok: false, reason: 'unsupported' };
    }
    return { ok: false, reason: e.message };   // lỗi tạm thời: báo lại nhưng không làm hỏng tệp
  }
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
  return { title: name.replace(/\.md$/i, '').slice(0, 200), content: `Nguồn: ${src}\n\n${t}`, pages: /^\d+$/.test(meta.pages || '') ? Number(meta.pages) : (/^\d+$/.test(meta.so_trang || '') ? Number(meta.so_trang) : null), meta };
}
