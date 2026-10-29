// Tạo nhanh bằng một dòng: "Gửi báo giá @minh mai 17h !cao #báo-giá ^Dự án A ~90p"
//   @tên   người phụ trách (khớp phần đầu/giữa tên hoặc phần trước @ của email; mơ hồ thì để trống và báo)
//   #nhãn  ·  ^dự án  ·  ~90p / ~2h / ~1h30  thời lượng
//   !thap !tb !cao !khan  ưu tiên · !qt quan trọng · !kc khẩn cấp
//   ngày: hôm nay, mai, ngày mai, ngày kia, thứ 2…thứ 7, cn, tuần sau, 15/11, 15/11/2030, +3 (sau 3 ngày)
//   giờ: 17h, 17h30, 17:30 → giờ nhắc vào ngày hạn (không có ngày thì hôm nay nếu còn kịp, không thì mai)
const fold = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/đ/g, "d").replace(/Đ/g, "D").toLowerCase();
const pad = (n) => String(n).padStart(2, "0");
const iso = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const addDays = (d, n) => { const x = new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); return x; };
const PRIO = { thap: "low", tb: "medium", cao: "high", khan: "urgent" };
const WD = { "2": 1, "3": 2, "4": 3, "5": 4, "6": 5, "7": 6 };   // thứ 2…7 → getDay()

export function parseQuick(text, { members = [], projects = [], today = new Date() } = {}) {
  const out = { title: "", assignee_id: null, due_date: "", time: "", priority: null, important: false, urgent: false, tags: [], project_id: null, est: "", unknown: [] };
  const base = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  const words = String(text || "").trim().split(/\s+/).filter(Boolean), keep = [];
  const norm = words.map(fold);
  const findPerson = (q) => {
    const k = fold(q); if (!k) return null;
    const hit = members.filter((m) => { const n = fold(m.name || ""), e = fold((m.email || "").split("@")[0]);
      return n.split(/\s+/).some((w) => w === k) || e === k; });
    const loose = hit.length ? hit : members.filter((m) => fold(m.name || "").includes(k) || fold((m.email || "").split("@")[0]).startsWith(k));
    return loose.length === 1 ? loose[0] : (loose.length > 1 ? "ambiguous" : null);
  };
  for (let i = 0; i < words.length; i++) {
    const w = words[i], n = norm[i], nx = norm[i + 1] || "";
    let m;
    if (w[0] === "@" && w.length > 1) { const p = findPerson(w.slice(1)); if (p && p !== "ambiguous") out.assignee_id = p.id; else out.unknown.push(w); continue; }
    if (w[0] === "#" && w.length > 1) { const t = w.slice(1).replace(/[^\p{L}\p{N}_-]/gu, ""); if (t && !out.tags.some((x) => fold(x) === fold(t)) && out.tags.length < 8) out.tags.push(t.slice(0, 30)); continue; }
    if (w[0] === "^" && w.length > 1) { const k = fold(w.slice(1).replace(/_/g, " ")); const ps = projects.filter((p) => fold(p.name).includes(k)); if (ps.length === 1) out.project_id = ps[0].id; else out.unknown.push(w); continue; }
    if (w[0] === "!" && w.length > 1) { const k = n.slice(1); if (PRIO[k]) out.priority = PRIO[k]; else if (k === "qt") out.important = true; else if (k === "kc") out.urgent = true; else keep.push(w); continue; }
    if ((m = /^~(?:(\d+)h(\d+)?|(\d+)p?)$/.exec(n))) { const mins = m[1] ? Number(m[1]) * 60 + Number(m[2] || 0) : Number(m[3]); if (mins >= 1 && mins <= 43200) { out.est = String(mins); continue; } }
    if ((m = /^(\d{1,2})(?:h|:)(\d{2})?$/.exec(n)) && Number(m[1]) < 24 && Number(m[2] || 0) < 60) { out.time = `${pad(Number(m[1]))}:${pad(Number(m[2] || 0))}`; continue; }
    if ((m = /^(\d{1,2})\/(\d{1,2})(?:\/(\d{4}))?$/.exec(n))) {
      const y = m[3] ? Number(m[3]) : base.getFullYear(), d = new Date(y, Number(m[2]) - 1, Number(m[1]));
      if (d.getMonth() === Number(m[2]) - 1 && d.getDate() === Number(m[1])) { out.due_date = iso(!m[3] && d < base ? new Date(y + 1, d.getMonth(), d.getDate()) : d); continue; }
    }
    if ((m = /^\+(\d{1,3})$/.exec(n))) { out.due_date = iso(addDays(base, Number(m[1]))); continue; }
    if (n === "hom" && nx === "nay") { out.due_date = iso(base); i++; continue; }
    if (n === "ngay" && nx === "mai") { out.due_date = iso(addDays(base, 1)); i++; continue; }
    if (n === "ngay" && nx === "kia") { out.due_date = iso(addDays(base, 2)); i++; continue; }
    if (n === "tuan" && nx === "sau") { out.due_date = iso(addDays(base, ((8 - base.getDay()) % 7) || 7)); i++; continue; }
    if (n === "mai" && w === w.toLowerCase()) { out.due_date = iso(addDays(base, 1)); continue; }   // "Mai" viết hoa là tên người, giữ trong tiêu đề
    if (n === "thu" && WD[nx] !== undefined) { out.due_date = iso(addDays(base, ((WD[nx] - base.getDay() + 7) % 7) || 7)); i++; continue; }
    if (n === "cn" || (n === "chu" && nx === "nhat")) { out.due_date = iso(addDays(base, ((7 - base.getDay()) % 7) || 7)); if (n === "chu") i++; continue; }
    keep.push(w);
  }
  out.title = keep.join(" ").replace(/\s+/g, " ").trim();
  if (out.time && !out.due_date) {   // chỉ có giờ: hôm nay nếu còn kịp, nếu không thì ngày mai
    const [h, mi] = out.time.split(":").map(Number), now = today;
    out.due_date = iso(now.getHours() * 60 + now.getMinutes() < h * 60 + mi ? base : addDays(base, 1));
  }
  return out;
}

// Giờ nhắc (ISO UTC) từ ngày hạn + "HH:MM" theo giờ máy người dùng; null nếu thiếu
export function remindAt(dueDate, time) {
  if (!dueDate || !time) return null;
  const [y, m, d] = dueDate.split("-").map(Number), [h, mi] = time.split(":").map(Number);
  return new Date(y, m - 1, d, h, mi, 0).toISOString();
}

// Một dòng CSV tối giản (có hỗ trợ dấu nháy kép và dấu phẩy/chấm phẩy/tab); trả mảng ô
export function splitCsvLine(line) {
  const sep = line.includes("\t") ? "\t" : (line.split(";").length > line.split(",").length ? ";" : ",");
  const cells = []; let cur = "", q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) { if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; } else if (c === '"') q = false; else cur += c; }
    else if (c === '"') q = true; else if (c === sep) { cells.push(cur.trim()); cur = ""; } else cur += c;
  }
  cells.push(cur.trim()); return cells;
}

const HEAD = { title: ["tieu de", "ten viec", "title", "viec"], assignee: ["nguoi phu trach", "nguoi lam", "assignee", "email"], due: ["han", "han chot", "due", "ngay het han"], priority: ["uu tien", "priority"], project: ["du an", "project"], tags: ["nhan", "tags", "tag"], description: ["mo ta", "description"] };

// Văn bản dán vào (mỗi dòng một việc, cú pháp tạo nhanh) HOẶC CSV có dòng tiêu đề (tiêu đề, người phụ trách, hạn, ưu tiên, dự án, nhãn, mô tả) → danh sách việc + dòng không hiểu
export function parseBulk(text, ctx) {
  const lines = String(text || "").split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (!lines.length) return [];
  const first = splitCsvLine(lines[0]).map(fold);
  const col = {}; first.forEach((h, i) => { for (const [k, names] of Object.entries(HEAD)) if (names.includes(h) && col[k] === undefined) col[k] = i; });
  if (col.title !== undefined) {   // CSV
    return lines.slice(1).map((l, idx) => {
      const c = splitCsvLine(l), g = (k) => (col[k] === undefined ? "" : (c[col[k]] || ""));
      const r = { row: idx + 2, title: g("title"), description: g("description"), tags: g("tags") ? g("tags").split(/[,;|]/).map((x) => x.replace(/^#/, "").trim()).filter(Boolean) : [], warn: [] };
      const em = g("assignee"); if (em) { const p = (ctx.members || []).find((m) => fold(m.email || "") === fold(em) || fold(m.name || "") === fold(em)); if (p) r.assignee_id = p.id; else r.warn.push(`Không thấy người "${em}"`); }
      const d = g("due"); if (d) { const q = parseQuick(d, ctx); if (q.due_date) r.due_date = q.due_date; else r.warn.push(`Không hiểu hạn "${d}"`); }
      const pr = fold(g("priority")); if (pr) { const v = PRIO[pr] || (["low", "medium", "high", "urgent"].includes(pr) ? pr : null); if (v) r.priority = v; else r.warn.push(`Không hiểu ưu tiên "${g("priority")}"`); }
      const pj = g("project"); if (pj) { const ps = (ctx.projects || []).filter((p) => fold(p.name) === fold(pj)); if (ps.length === 1) r.project_id = ps[0].id; else r.warn.push(`Không thấy dự án "${pj}"`); }
      return r;
    });
  }
  return lines.map((l, idx) => { const q = parseQuick(l.replace(/^[-*•\d.)\s]+(?=\S)/, ""), ctx); return { row: idx + 1, title: q.title, due_date: q.due_date || undefined, assignee_id: q.assignee_id || undefined, priority: q.priority || undefined,
    important: q.important || undefined, urgent: q.urgent || undefined, tags: q.tags, project_id: q.project_id || undefined, est_minutes: q.est ? Number(q.est) : undefined, time: q.time || undefined, warn: q.unknown.map((u) => `Không nhận ra ${u}`) }; });
}
