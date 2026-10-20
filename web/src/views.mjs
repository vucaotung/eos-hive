// Các trang giao diện (HTML dựng bằng mẫu tự thoát ký tự). Văn bản hiển thị bằng tiếng Việt.
import { html, join, raw, esc, fmtDT, fmtD, ago, statusBadge, badge, safeLink, actorLabel, STATUS, PRIORITY, CONFIDENCE, VERDICT, COMMENT_KIND } from './html.mjs';

const csrfInput = (csrf) => html`<input type="hidden" name="_csrf" value="${csrf}">`;
const taskNum = (id) => String(id).replace(/^T-/i, '');
export const taskHref = (id) => `/app/tasks/${taskNum(id)}`;

export function layout({ title, me, csrf, active = '', body, refresh = false }) {
  const nav = [['/app/', 'Hộp việc', 'inbox'], ['/app/tasks', 'Việc', 'tasks'], ['/app/tasks/new', 'Tạo việc', 'new'], ['/app/tokens', 'Kết nối AI', 'tokens']];
  if (me?.is_admin) nav.push(['/app/admin', 'Quản trị', 'admin']);
  return html`<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title} · Tổ Ong</title><link rel="stylesheet" href="/app/static/app.css"></head>
<body${refresh ? raw(' data-refresh="30"') : ''}><header class="top"><a class="brand" href="/app/">🐝 Tổ Ong</a>
<nav>${nav.map(([h, l, k]) => html`<a href="${h}" class="${k === active ? 'on' : ''}">${l}</a>`)}</nav>
<form method="post" action="/app/logout" class="logout">${csrfInput(csrf)}<span class="me">${me?.user?.name || ''}</span><button class="link">Đăng xuất</button></form></header>
<main>${body}</main><script src="/app/static/app.js" defer></script></body></html>`;
}

export const loginPage = ({ enabled, next, notice }) => html`<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Đăng nhập · Tổ Ong</title><link rel="stylesheet" href="/app/static/app.css"></head><body class="center"><main class="card narrow">
<h1>🐝 Tổ Ong</h1><p class="muted">Enterprise OS có AI agent làm việc cùng người.</p>${notice ? html`<p class="alert">${notice}</p>` : ''}
${enabled ? html`<p><a class="btn primary wide" href="/app/auth/google?next=${encodeURIComponent(next || '/app/')}">Đăng nhập bằng Google</a></p>
<p class="muted small">Chỉ tài khoản đã được cấp quyền mới vào được.</p>` : html`<p class="alert">Đăng nhập Google chưa được cấu hình trên máy chủ.</p>`}
</main></body></html>`;

export const errorPage = ({ title, message, me, csrf }) => layout({ title, me, csrf, body: html`<section class="card narrow"><h1>${title}</h1><p>${message}</p><p><a class="btn" href="/app/">Về hộp việc</a></p></section>` });

const priorityLabel = (p) => PRIORITY[p] || p;
const dueCell = (t) => html`${t.due_date ? fmtD(t.due_date) : '—'}${t.overdue ? html` ${badge('Quá hạn', 'bad')}` : ''}`;

export function taskTable(tasks, { empty = 'Không có việc nào.' } = {}) {
  if (!tasks?.length) return html`<p class="muted empty">${empty}</p>`;
  return html`<div class="tablewrap"><table><thead><tr><th>Mã</th><th>Việc</th><th>Trạng thái</th><th>Ưu tiên</th><th>Hạn</th><th>Agent</th></tr></thead><tbody>
${tasks.map((t) => html`<tr><td><a href="${taskHref(t.id)}">${t.id}</a></td><td class="title"><a href="${taskHref(t.id)}">${t.title}</a></td>
<td>${statusBadge(t.status)}${t.waiting_on_human ? html` ${badge('Chờ bạn', 'warn')}` : ''}</td><td>${priorityLabel(t.priority)}</td><td>${dueCell(t)}</td><td>${t.agent ? `🤖 ${t.agent}` : '—'}</td></tr>`)}
</tbody></table></div>`;
}

export function inboxPage({ me, csrf, day, open, msg }) {
  const q = day.agent_questions || [], r = day.agent_results_to_review || [];
  const card = (n, label, cls, href) => html`<a class="stat ${cls}" href="${href}"><b>${n}</b><span>${label}</span></a>`;
  const list = (items, empty) => (items.length ? html`<ul class="plain">${items.map((t) => html`<li><a href="${taskHref(t.id)}"><b>${t.id}</b> ${t.title}</a></li>`)}</ul>` : html`<p class="muted empty">${empty}</p>`);
  return layout({ title: 'Hộp việc', me, csrf, active: 'inbox', refresh: true, body: html`
${msg ? html`<p class="alert ok">${msg}</p>` : ''}
<h1>Xin chào ${me.user.name}</h1>
<div class="stats">${card(r.length, 'Kết quả chờ bạn xem', r.length ? 'accent' : '', '/app/tasks?box=review')}${card(q.length, 'Agent đang hỏi bạn', q.length ? 'warn' : '', '/app/tasks?box=agent_questions')}
${card(open.length, 'Việc của tôi đang mở', '', '/app/tasks')}${card((day.overdue || []).length, 'Việc quá hạn', (day.overdue || []).length ? 'bad' : '', '/app/tasks')}</div>
<section class="card"><h2>Chờ bạn xem kết quả</h2><p class="muted small">Agent đã nộp; việc chỉ Xong khi bạn chấp nhận.</p>${list(r, 'Không có kết quả nào đang chờ.')}</section>
<section class="card"><h2>Agent đang hỏi bạn</h2><p class="muted small">Agent dừng lại vì thiếu thông tin; trả lời để nó làm tiếp.</p>${list(q, 'Không có câu hỏi nào.')}</section>
<section class="card"><h2>Việc của tôi</h2>${taskTable(open.slice(0, 15), { empty: 'Chưa có việc nào đang mở.' })}${open.length > 15 ? html`<p><a href="/app/tasks">Xem tất cả ${open.length} việc</a></p>` : ''}</section>
<p><a class="btn primary" href="/app/tasks/new">+ Tạo việc, giao cho agent</a></p>`});
}

const BOXES = [['assigned', 'Giao cho tôi'], ['created', 'Tôi giao'], ['review', 'Chờ tôi xem'], ['agent_questions', 'Agent hỏi'], ['watching', 'Tôi theo dõi']];
export function tasksPage({ me, csrf, box, status, tasks }) {
  const tab = (b, l) => html`<a class="tab ${b === box ? 'on' : ''}" href="/app/tasks?box=${b}&status=${status}">${l}</a>`;
  return layout({ title: 'Việc', me, csrf, active: 'tasks', body: html`<h1>Việc</h1>
<div class="tabs">${BOXES.map(([b, l]) => tab(b, l))}<span class="spacer"></span>
<a class="tab ${status === 'open' ? 'on' : ''}" href="/app/tasks?box=${box}&status=open">Đang mở</a><a class="tab ${status === 'all' ? 'on' : ''}" href="/app/tasks?box=${box}&status=all">Tất cả</a></div>
<section class="card">${taskTable(tasks)}</section>`});
}

export function newTaskPage({ me, csrf, error, form = {} }) {
  const agents = me.agents || [];
  return layout({ title: 'Tạo việc', me, csrf, active: 'new', body: html`<h1>Tạo việc</h1>${error ? html`<p class="alert">${error}</p>` : ''}
<form method="post" action="/app/tasks" class="card form">${csrfInput(csrf)}
<label>Tiêu đề<input name="title" required minlength="3" maxlength="300" value="${form.title || ''}" autofocus></label>
<label>Mô tả<textarea name="description" rows="8" maxlength="8000" placeholder="Nêu rõ cần làm gì, gửi ai, ai ký, hạn, thông tin cần thiết…">${form.description || ''}</textarea></label>
<div class="row"><label>Giao cho agent<select name="agent"><option value="">Không giao agent (tự làm)</option>
${agents.map((a) => html`<option value="${a.code}" ${form.agent === a.code ? raw('selected') : ''}>${a.name}</option>`)}</select></label>
<label>Hạn<input type="date" name="due" value="${form.due || ''}"></label>
<label>Ưu tiên<select name="priority">${Object.entries(PRIORITY).map(([k, v]) => html`<option value="${k}" ${(form.priority || 'medium') === k ? raw('selected') : ''}>${v}</option>`)}</select></label></div>
<p class="muted small">Agent sẽ nhận việc trong vòng 1–2 phút. Việc được giao cho bạn làm người phụ trách; kết quả agent nộp sẽ chờ bạn duyệt.</p>
<p><button class="btn primary">Tạo việc</button></p></form>`});
}

const kv = (k, v) => html`<div class="kv"><span>${k}</span><b>${v}</b></div>`;
const list = (items) => (items?.length ? html`<ul class="tight">${items.map((x) => html`<li>${typeof x === 'string' ? x : JSON.stringify(x)}</li>`)}</ul>` : '');

function reportBlock(rep) {
  const conf = CONFIDENCE[rep.confidence];
  const outs = (rep.outputs || []).filter((o) => o && (o.url || o.name));
  return html`<article class="report"><header><b>🤖 ${rep.agent || 'agent'}</b> · ${fmtDT(rep.at)} ${conf ? badge(`Tin cậy: ${conf[0]}`, conf[1]) : ''} ${rep.verdict ? badge(VERDICT[rep.verdict] || rep.verdict, rep.verdict === 'accepted' ? 'ok' : rep.verdict === 'rework' ? 'warn' : 'muted') : ''}</header>
<p class="pre">${rep.summary}</p>
${outs.length ? html`<h4>Tệp kết quả</h4><ul class="tight">${outs.map((o) => html`<li>${safeLink(o.url, o.name || o.url)}</li>`)}</ul>` : ''}
${rep.residual_risk ? html`<h4>Rủi ro còn lại</h4><p class="pre">${rep.residual_risk}</p>` : ''}
${rep.next_actions ? html`<h4>Việc tiếp theo</h4><p class="pre">${rep.next_actions}</p>` : ''}
${Array.isArray(rep.checks) && rep.checks.length ? html`<h4>Đã kiểm tra</h4>${list(rep.checks)}` : ''}
${Array.isArray(rep.sources) && rep.sources.length ? html`<h4>Nguồn</h4>${list(rep.sources.map((s) => (typeof s === 'string' ? s : s.title || s.url || JSON.stringify(s))))}` : ''}</article>`;
}

export function taskPage({ me, csrf, t, error, msg }) {
  const f = t.flags || {}; const reports = t.reports || [];
  const latest = reports[0];
  const act = (action, label, cls, extra = '') => html`<form method="post" action="/app/tasks/${taskNum(t.id)}/${action}" ${extra ? raw(extra) : ''}>${csrfInput(csrf)}`;
  return layout({ title: `${t.id} ${t.title}`, me, csrf, active: 'tasks', refresh: ['todo', 'in_progress', 'blocked'].includes(t.status) && !!t.agent, body: html`
<p class="crumbs"><a href="/app/tasks">← Việc</a></p>
${error ? html`<p class="alert">${error}</p>` : ''}${msg ? html`<p class="alert ok">${msg}</p>` : ''}
<h1><span class="muted">${t.id}</span> ${t.title}</h1>
<div class="meta">${statusBadge(t.status)} ${badge(`Ưu tiên: ${priorityLabel(t.priority)}`, 'muted')} ${t.agent ? badge(`🤖 ${t.agent.name}`, 'info') : ''}</div>
<div class="grid2">
<section class="card"><h2>Thông tin</h2>${kv('Người phụ trách', t.assignee || '—')}${kv('Người giao', t.created_by || '—')}${kv('Phòng', t.department || '—')}${kv('Hạn', fmtD(t.due_date))}${kv('Tiến độ', `${t.progress ?? 0}%`)}${t.parent ? kv('Việc cha', html`<a href="${taskHref(t.parent)}">${t.parent}</a>`) : ''}</section>
<section class="card"><h2>Mô tả</h2><p class="pre">${t.description || '—'}</p></section></div>

${f.can_answer ? html`<section class="card action warn"><h2>Agent đang hỏi, cần bạn trả lời</h2>
<form method="post" action="/app/tasks/${taskNum(t.id)}/comment" class="form">${csrfInput(csrf)}<input type="hidden" name="kind" value="answer">
<label>Câu trả lời của bạn<textarea name="body" rows="4" required maxlength="8000" placeholder="Trả lời cụ thể để agent làm tiếp"></textarea></label><p><button class="btn primary">Gửi câu trả lời</button></p></form></section>` : ''}

${f.can_review ? html`<section class="card action accent"><h2>Kết quả chờ bạn duyệt</h2>${latest ? reportBlock(latest) : html`<p class="muted">Chưa có báo cáo.</p>`}
<div class="row split"><form method="post" action="/app/tasks/${taskNum(t.id)}/accept" class="form">${csrfInput(csrf)}<label>Ghi chú (tùy chọn)<input name="note" maxlength="500"></label><p><button class="btn ok">✔ Chấp nhận, đóng việc</button></p></form>
<form method="post" action="/app/tasks/${taskNum(t.id)}/reject" class="form">${csrfInput(csrf)}<label>Lý do trả lại (bắt buộc)<textarea name="reason" rows="3" required minlength="5" maxlength="2000" placeholder="Thiếu gì, sai gì, cần sửa thế nào"></textarea></label><p><button class="btn warn">↩ Trả lại để làm lại</button></p></form></div></section>`
 : (latest ? html`<section class="card"><h2>Báo cáo của agent</h2>${reports.slice(0, 3).map(reportBlock)}</section>` : '')}

${(t.files || []).length ? html`<section class="card"><h2>Tệp</h2><ul class="tight">${t.files.map((x) => html`<li>${safeLink(x.url, x.name)} <span class="muted small">${x.role || ''}</span></li>`)}</ul></section>` : ''}
${(t.children || []).length ? html`<section class="card"><h2>Việc con</h2><ul class="tight">${t.children.map((c) => html`<li><a href="${taskHref(c.id)}">${c.id}</a> ${c.title} ${statusBadge(c.status)} ${c.agent ? `🤖 ${c.agent}` : ''}</li>`)}</ul></section>` : ''}

<section class="card"><h2>Trao đổi</h2>${(t.comments || []).length ? html`<ol class="timeline">${t.comments.map((c) => html`<li class="k-${c.kind}"><header>${actorLabel(c.by, me.user.id)} <span class="muted small">${fmtDT(c.at)} · ${COMMENT_KIND[c.kind] || c.kind}</span></header><p class="pre">${c.body}</p></li>`)}</ol>` : html`<p class="muted empty">Chưa có trao đổi.</p>`}
<form method="post" action="/app/tasks/${taskNum(t.id)}/comment" class="form">${csrfInput(csrf)}<input type="hidden" name="kind" value="note"><label>Thêm ghi chú<textarea name="body" rows="3" required maxlength="8000"></textarea></label><p><button class="btn">Gửi</button></p></form></section>

${f.can_cancel ? html`<section class="card danger"><h2>Hủy việc</h2><form method="post" action="/app/tasks/${taskNum(t.id)}/cancel" class="form" data-confirm="Hủy việc này? Thẻ của agent cũng sẽ được dừng.">${csrfInput(csrf)}<label>Lý do (tùy chọn)<input name="reason" maxlength="500"></label><p><button class="btn bad">Hủy việc</button></p></form></section>` : ''}
${(t.cards || []).length ? html`<details class="card"><summary>Chi tiết kỹ thuật (thẻ Kanban)</summary><div class="tablewrap"><table><thead><tr><th>Thẻ</th><th>Loại</th><th>Lượt</th><th>Trạng thái</th><th>Cập nhật</th></tr></thead><tbody>${t.cards.map((c) => html`<tr><td><code>${c.card_id || '—'}</code></td><td>${c.kind}</td><td>${c.attempt}</td><td>${c.status}</td><td>${ago(c.last_event_at)}</td></tr>`)}</tbody></table></div></details>` : ''}`});
}

const SCOPES = [['read', 'Đọc việc, lịch, công văn của tôi'], ['write', 'Ghi bình luận, tiến độ, nộp kết quả'], ['drive', 'Lưu kết quả vào Drive của tôi'], ['kb', 'Hỏi kho dữ liệu chung'], ['hr_self', 'Xem công, phép, KPI của chính tôi']];
export function tokensPage({ me, csrf, tokens, error, msg }) {
  return layout({ title: 'Kết nối AI', me, csrf, active: 'tokens', body: html`<h1>Kết nối AI agent của bạn</h1>
<p class="muted">Mã MCP cho phép agent cá nhân (Claude, ChatGPT, Cursor…) làm việc thay bạn trong phạm vi bạn chọn. Địa chỉ máy chủ: <code>https://work.enterpriseos.bond/mcp</code>. Mã chỉ hiện <b>một lần</b> khi tạo.</p>
${error ? html`<p class="alert">${error}</p>` : ''}${msg ? html`<p class="alert ok">${msg}</p>` : ''}
<section class="card"><h2>Tạo mã mới</h2><form method="post" action="/app/tokens" class="form">${csrfInput(csrf)}
<div class="row"><label>Tên gợi nhớ<input name="name" required minlength="2" maxlength="60" placeholder="Claude trên laptop"></label>
<label>Ứng dụng<select name="client"><option value="claude">Claude</option><option value="chatgpt">ChatGPT</option><option value="gemini">Gemini</option><option value="cursor">Cursor</option><option value="other">Khác</option></select></label>
<label>Hạn<select name="days"><option value="7">7 ngày</option><option value="30" selected>30 ngày</option><option value="90">90 ngày</option></select></label></div>
<fieldset><legend>Quyền (chọn tối thiểu cần thiết)</legend>${SCOPES.map(([k, l]) => html`<label class="check"><input type="checkbox" name="scopes" value="${k}" ${k === 'read' ? raw('checked') : ''}> <code>${k}</code> ${l}</label>`)}</fieldset>
<p><button class="btn primary">Tạo mã</button></p></form></section>
<section class="card"><h2>Mã của bạn</h2>${tokens.length ? html`<div class="tablewrap"><table><thead><tr><th>Tên</th><th>Mã</th><th>Quyền</th><th>Hết hạn</th><th>Dùng gần nhất</th><th></th></tr></thead><tbody>
${tokens.map((k) => html`<tr class="${k.active ? '' : 'dim'}"><td>${k.name}<div class="muted small">${k.client}</div></td><td><code>eos_${k.prefix}…</code></td><td>${(k.scopes || []).join(', ')}</td>
<td>${k.revoked_at ? badge('Đã thu hồi', 'muted') : fmtD(k.expires_at)}</td><td>${k.last_used_at ? ago(k.last_used_at) : 'chưa dùng'}</td>
<td>${k.active ? html`<form method="post" action="/app/tokens/${k.id}/revoke" data-confirm="Thu hồi mã này?">${csrfInput(csrf)}<button class="link bad">Thu hồi</button></form>` : ''}</td></tr>`)}</tbody></table></div>` : html`<p class="muted empty">Bạn chưa có mã nào.</p>`}</section>`});
}

export const tokenCreatedPage = ({ me, csrf, token, name }) => layout({ title: 'Mã mới', me, csrf, active: 'tokens', body: html`
<h1>Đã tạo mã "${name}"</h1><section class="card action warn"><p><b>Sao chép ngay.</b> Mã này chỉ hiện một lần; mất thì phải thu hồi và tạo lại. Đừng gửi qua chat hay lưu vào kho mã nguồn.</p>
<p><input class="mono wide" readonly value="${token}" data-select></p><p class="muted small">Dán vào cấu hình MCP của ứng dụng: máy chủ <code>https://work.enterpriseos.bond/mcp</code>, tiêu đề <code>Authorization: Bearer &lt;mã&gt;</code>.</p>
<p><a class="btn" href="/app/tokens">Xong, về danh sách</a></p></section>`});

const num = (n) => (n ?? 0);
export function adminPage({ me, csrf, ov }) {
  const b = ov.bridge || {}, m = ov.mcp || {}, ts = ov.tasks || {};
  const stat = (n, label, cls) => html`<div class="stat ${cls}"><b>${n}</b><span>${label}</span></div>`;
  const stuck = num(b.cards_stuck_running), errs = num(b.outbox_errors), oldest = num(b.outbox_oldest_pending_s);
  return layout({ title: 'Quản trị', me, csrf, active: 'admin', refresh: true, body: html`<h1>Quản trị</h1>
<p class="tabs"><a class="tab on" href="/app/admin">Tổng quan</a><a class="tab" href="/app/admin/tokens">Mã MCP</a><a class="tab" href="/app/admin/calls">Nhật ký gọi MCP</a></p>
<h2>Cầu nối Hermes</h2><div class="stats">
${stat(num(b.outbox_pending), 'Lệnh chờ đẩy sang Kanban', num(b.outbox_pending) > 0 && oldest > 300 ? 'bad' : '')}${stat(errs, 'Lệnh lỗi', errs ? 'bad' : 'ok')}
${stat(stuck, 'Thẻ kẹt "đang chạy" > 2 giờ', stuck ? 'bad' : 'ok')}${stat(ago(b.last_card_event), 'Sự kiện thẻ gần nhất', '')}
${stat(num(ov.confirmations_pending), 'Xác nhận L2 đang chờ', '')}</div>
<h2>Agent</h2><section class="card"><div class="tablewrap"><table><thead><tr><th>Mã</th><th>Tên</th><th>Module</th><th>Profile Hermes</th><th>Bật</th><th>Cấp</th><th>Việc mở</th><th>Đang chạy</th><th>Skill</th><th>Mã MCP còn</th><th>Quyền mã</th></tr></thead><tbody>
${(ov.agents || []).map((a) => html`<tr class="${a.active ? '' : 'dim'}"><td><code>${a.code}</code></td><td>${a.name}</td><td>${a.module}</td><td><code>${a.profile}</code></td><td>${a.active ? '✔' : '✘'}</td><td>L${a.max_level}</td>
<td>${a.tasks_open}</td><td>${a.cards_running}</td><td>${(a.skills || []).join(', ') || '—'}</td>
<td>${a.token_days_left == null ? (a.active ? badge('chưa có', 'bad') : '—') : (a.token_days_left <= 14 ? badge(`${a.token_days_left} ngày`, 'warn') : `${a.token_days_left} ngày`)}</td><td>${(a.token_scopes || []).join(', ') || '—'}</td></tr>`)}</tbody></table></div></section>
<h2>Việc theo trạng thái</h2><div class="stats">${Object.entries(STATUS).map(([k, [l]]) => stat(num(ts[k]), l, ''))}</div>
<h2>MCP trong 24 giờ</h2><div class="stats">${stat(num(m.calls_24h), 'Lượt gọi', '')}${stat(num(m.denied_24h), 'Bị từ chối', num(m.denied_24h) > 20 ? 'bad' : '')}</div>`});
}

export function adminTokensPage({ me, csrf, tokens, msg }) {
  return layout({ title: 'Mã MCP (quản trị)', me, csrf, active: 'admin', body: html`<h1>Quản trị</h1>
<p class="tabs"><a class="tab" href="/app/admin">Tổng quan</a><a class="tab on" href="/app/admin/tokens">Mã MCP</a><a class="tab" href="/app/admin/calls">Nhật ký gọi MCP</a></p>
${msg ? html`<p class="alert ok">${msg}</p>` : ''}<section class="card"><div class="tablewrap"><table><thead><tr><th>Của</th><th>Tên</th><th>Mã</th><th>Quyền</th><th>Hết hạn</th><th>Dùng gần nhất</th><th>IP</th><th></th></tr></thead><tbody>
${tokens.map((k) => html`<tr class="${k.active ? '' : 'dim'}"><td>${k.who}</td><td>${k.name}</td><td><code>eos_${k.prefix}…</code></td><td>${(k.scopes || []).join(', ')}</td>
<td>${k.revoked_at ? badge('Đã thu hồi', 'muted') : fmtD(k.expires_at)}</td><td>${k.last_used_at ? ago(k.last_used_at) : '—'}</td><td>${k.last_ip || '—'}</td>
<td>${k.active ? html`<form method="post" action="/app/admin/tokens/${k.id}/revoke" data-confirm="Thu hồi mã của ${k.who}?">${csrfInput(csrf)}<button class="link bad">Thu hồi</button></form>` : ''}</td></tr>`)}</tbody></table></div></section>`});
}

export function adminCallsPage({ me, csrf, calls, denied }) {
  return layout({ title: 'Nhật ký gọi MCP', me, csrf, active: 'admin', body: html`<h1>Quản trị</h1>
<p class="tabs"><a class="tab" href="/app/admin">Tổng quan</a><a class="tab" href="/app/admin/tokens">Mã MCP</a><a class="tab ${denied ? '' : 'on'}" href="/app/admin/calls">Nhật ký gọi MCP</a><a class="tab ${denied ? 'on' : ''}" href="/app/admin/calls?denied=1">Chỉ bị từ chối</a></p>
<section class="card"><div class="tablewrap"><table><thead><tr><th>Lúc</th><th>Của</th><th>Mã</th><th>Công cụ</th><th>Kết quả</th><th>Đối tượng</th><th>ms</th></tr></thead><tbody>
${calls.map((c) => html`<tr><td>${fmtDT(c.at)}</td><td>${c.who || '—'}</td><td><code>${c.prefix ? `eos_${c.prefix}…` : '—'}</code></td><td><code>${c.tool}</code></td><td>${c.outcome === 'ok' ? badge('ok', 'ok') : badge(c.outcome, c.outcome === 'denied' ? 'bad' : 'warn')}</td><td>${c.entity || ''}</td><td>${c.ms}</td></tr>`)}</tbody></table></div></section>`});
}
