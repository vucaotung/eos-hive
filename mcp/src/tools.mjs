// Công cụ MCP của Enterprise OS cho agent cá nhân. Mọi công cụ chạy với danh tính của người sở hữu mã.
import { z } from 'zod';
import { asUser, logCall, DbError } from './db.mjs';
import { GUIDE, TOPICS } from './guide.mjs';
import { uploadResult, fileInsideFolder, driveIdFromUrl, MAX_BYTES } from './drive.mjs';

const taskRef = z.union([z.string().regex(/^(T-)?\d{1,12}$/i), z.number().int().positive()])
  .describe('Mã việc, ví dụ "T-123" hoặc 123');
const toId = (v) => Number(String(v).replace(/^T-/i, ''));

const ok = (data) => ({ content: [{ type: 'text', text: typeof data === 'string' ? data : JSON.stringify(data, null, 2) }] });
const fail = (msg) => ({ isError: true, content: [{ type: 'text', text: msg }] });

const TEXT_MIME = { md: 'text/markdown', txt: 'text/plain', csv: 'text/csv', html: 'text/html', json: 'application/json' };

export function registerTools(server, ident) {
  // Bọc mỗi công cụ: kiểm tra phạm vi mã, ghi nhật ký, đổi lỗi CSDL thành câu dễ hiểu
  const tool = (name, scope, config, handler, logArgs = () => ({})) => {
    server.registerTool(name, config, async (args) => {
      const t0 = Date.now();
      if (!ident.scopes.includes(scope)) {
        await logCall(ident, name, logArgs(args), 'denied', null, 0);
        return fail(`Mã MCP này không có phạm vi "${scope}". Tạo mã mới trên app (Tài khoản → Kết nối AI agent) nếu cần.`);
      }
      try {
        const { result, entity } = await handler(args);
        await logCall(ident, name, logArgs(args), 'ok', entity, Date.now() - t0);
        return ok(result);
      } catch (e) {
        const denied = e instanceof DbError && e.code === '42501';
        await logCall(ident, name, logArgs(args), denied ? 'denied' : (e instanceof DbError ? 'invalid' : 'error'), null, Date.now() - t0);
        if (e instanceof DbError) return fail(e.message);
        console.error(name, e);
        return fail('Lỗi máy chủ, thử lại sau.');
      }
    });
  };
  const call = (sql, params) => asUser(ident, async (c) => (await c.query(sql, params)).rows[0]?.r);

  tool('eos_guide', 'read', {
    title: 'Hướng dẫn Enterprise OS',
    description: `Đọc hướng dẫn cách hệ thống hoạt động. Gọi đầu tiên nếu chưa quen. topic: ${TOPICS.join(', ')}`,
    inputSchema: { topic: z.enum(TOPICS).default(ident.agentId ? 'agent' : 'overview') },
    annotations: { readOnlyHint: true },
  }, async ({ topic }) => ({ result: GUIDE[topic || 'overview'] }));

  if (ident.agentId) { registerAgentTools(server, ident, tool, call); registerGuides(server); return; }

  // ---------- Đọc hiểu hệ thống ----------
  tool('eos_whoami', 'read', {
    title: 'Tôi là ai',
    description: 'Người dùng đang kết nối: tên, công ty, phòng ban, vai trò, trạng thái thư mục Drive, phạm vi của mã.',
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, async () => {
    const me = await call('SELECT agent.mcp_whoami() AS r');
    return { result: { ...me, token_scopes: ident.scopes } };
  });

  tool('eos_my_day', 'read', {
    title: 'Hôm nay của tôi',
    description: 'Tóm tắt hôm nay: việc quá hạn, đến hạn hôm nay, số việc 7 ngày tới, agent đang hỏi tôi, kết quả agent chờ tôi xem, xác nhận agent đang xin, số yêu cầu chờ tôi duyệt.',
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, async () => ({ result: await call('SELECT agent.mcp_my_day() AS r') }));

  tool('eos_approvals_pending', 'read', {
    title: 'Chờ tôi duyệt',
    description: 'Các yêu cầu (việc, đề nghị, đơn từ, văn bản đi, bảng lương) đang chờ người dùng duyệt ở bước hiện tại. Chỉ để xem: duyệt hay trả lại phải làm trên web.',
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, async () => ({ result: await call('SELECT agent.mcp_approvals_pending() AS r') }));

  tool('eos_incoming_list', 'read', {
    title: 'Công văn đến',
    description: 'Công văn đến người dùng được xem. box: mine (tôi đang xử lý), open (chưa xong), overdue (quá hạn), all. Văn bản mật chỉ có số và ngày.',
    inputSchema: { box: z.enum(['mine', 'open', 'overdue', 'all']).default('mine'), limit: z.number().int().min(1).max(100).default(30) },
    annotations: { readOnlyHint: true },
  }, async ({ box, limit }) => ({ result: await call('SELECT agent.mcp_incoming($1,$2) AS r', [box, limit]) }), (a) => ({ box: a.box }));

  tool('eos_my_hr', 'hr_self', {
    title: 'Công, phép, KPI của tôi',
    description: 'Dữ liệu nhân sự của chính người dùng. what: attendance (bảng công tháng), leave (phép năm), kpi (điểm KPI tháng và từng việc). month: YYYY-MM, mặc định tháng này.',
    inputSchema: { what: z.enum(['attendance', 'leave', 'kpi']), month: z.string().regex(/^\d{4}-\d{2}$/).optional() },
    annotations: { readOnlyHint: true },
  }, async ({ what, month }) => ({ result: await call('SELECT agent.mcp_my_hr($1,$2) AS r', [what, month ? `${month}-01` : null]) }),
  (a) => ({ what: a.what, month: a.month }));

  tool('eos_list_tasks', 'read', {
    title: 'Danh sách việc',
    description: 'Liệt kê việc. box: assigned (tôi làm), created (tôi giao), watching (tôi theo dõi), review (kết quả chờ tôi xem), agent_questions (agent đang hỏi tôi). status: open | all | todo | in_progress | blocked | in_review | done.',
    inputSchema: {
      box: z.enum(['assigned', 'created', 'watching', 'review', 'agent_questions']).default('assigned'),
      status: z.enum(['open', 'all', 'todo', 'in_progress', 'blocked', 'in_review', 'done', 'cancelled']).default('open'),
      limit: z.number().int().min(1).max(100).default(30),
    },
    annotations: { readOnlyHint: true },
  }, async ({ box, status, limit }) => ({ result: await call('SELECT agent.mcp_my_tasks($1,$2,$3) AS r', [box, status, limit]) }),
  (a) => ({ box: a.box, status: a.status }));

  tool('eos_get_task', 'read', {
    title: 'Chi tiết việc',
    description: 'Đọc một việc: mô tả, hạn, người phụ trách, việc con, 50 bình luận gần nhất, tệp, link, báo cáo của agent hệ thống.',
    inputSchema: { task: taskRef },
    annotations: { readOnlyHint: true },
  }, async ({ task }) => ({ result: await call('SELECT agent.mcp_task($1) AS r', [toId(task)]), entity: { type: 'task', id: String(toId(task)) } }),
  (a) => ({ task: toId(a.task) }));

  tool('eos_search', 'read', {
    title: 'Tìm việc',
    description: 'Tìm việc theo từ khóa (gõ có dấu hay không dấu đều được), chỉ trong những việc người dùng được xem.',
    inputSchema: { query: z.string().min(2).max(100) },
    annotations: { readOnlyHint: true },
  }, async ({ query }) => ({ result: await call('SELECT agent.mcp_search($1) AS r', [query]) }),
  (a) => ({ query: a.query }));

  tool('eos_list_kbs', 'kb', {
    title: 'Kho dữ liệu được hỏi',
    description: 'Các kho trong Kho dữ liệu chung mà người dùng được hỏi.',
    inputSchema: {},
    annotations: { readOnlyHint: true },
  }, async () => ({ result: await call('SELECT agent.mcp_my_kbs() AS r') }));

  // ---------- Ghi, thay mặt người dùng ----------
  tool('eos_comment', 'write', {
    title: 'Ghi bình luận',
    description: 'Ghi bình luận vào việc. kind = "answer" khi trả lời câu hỏi của agent hệ thống (việc đang Vướng sẽ được làm tiếp).',
    inputSchema: { task: taskRef, body: z.string().min(1).max(8000), kind: z.enum(['note', 'answer']).default('note') },
  }, async ({ task, body, kind }) => {
    const id = await call('SELECT agent.mcp_comment($1,$2,$3) AS r', [toId(task), body, kind]);
    return { result: { comment_id: id }, entity: { type: 'task', id: String(toId(task)) } };
  }, (a) => ({ task: toId(a.task), kind: a.kind, chars: a.body?.length }));

  tool('eos_update_progress', 'write', {
    title: 'Cập nhật tiến độ',
    description: 'Cập nhật % tiến độ việc người dùng được giao (0–99), kèm ghi chú ngắn.',
    inputSchema: { task: taskRef, progress: z.number().int().min(0).max(99), note: z.string().max(1000).optional() },
  }, async ({ task, progress, note }) => ({
    result: await call('SELECT agent.mcp_update_progress($1,$2,$3) AS r', [toId(task), progress, note || null]),
    entity: { type: 'task', id: String(toId(task)) },
  }), (a) => ({ task: toId(a.task), progress: a.progress }));

  tool('eos_save_to_drive', 'drive', {
    title: 'Lưu kết quả vào Drive cá nhân',
    description: `Lưu một tệp kết quả vào thư mục Drive của người dùng (Kết quả/<năm-tháng>/T-<số> - <tên>) và gắn vào việc. content là văn bản (encoding "text") hoặc base64 (encoding "base64", cho docx/xlsx/pdf/ảnh). Tối đa ${MAX_BYTES / 1048576} MB.`,
    inputSchema: {
      task: taskRef,
      filename: z.string().min(1).max(120),
      content: z.string().min(1),
      encoding: z.enum(['text', 'base64']).default('text'),
      mime_type: z.string().max(120).optional(),
    },
  }, async ({ task, filename, content, encoding, mime_type }) => {
    const id = toId(task);
    const bytes = encoding === 'base64' ? Buffer.from(content, 'base64') : Buffer.from(content, 'utf8');
    if (bytes.length > MAX_BYTES) throw new DbError(`Tệp quá ${MAX_BYTES / 1048576} MB`, 'P0001');
    const ext = filename.split('.').pop().toLowerCase();
    const mime = mime_type || TEXT_MIME[ext] || 'application/octet-stream';
    // quyền với việc + thư mục Drive được kiểm trước khi tải lên
    const pre = await asUser(ident, async (c) => {
      await c.query('SELECT agent.mcp_task($1)', [id]);
      return (await c.query('SELECT drive_folder_id, drive_state FROM core.users WHERE id = core.current_user_id()')).rows[0];
    });
    if (!pre?.drive_folder_id || pre.drive_state !== 'ok') {
      throw new DbError('Thư mục Drive của bạn chưa thiết lập xong (trang Tài khoản → Thư mục Drive).', 'P0001');
    }
    const f = await uploadResult({ userFolderId: pre.drive_folder_id, taskId: id, filename, mime, bytes });
    const sha = (await import('node:crypto')).createHash('sha256').update(bytes).digest('hex');
    await call('SELECT agent.mcp_register_file($1,$2,$3,$4,$5,$6,$7,$8) AS r', [id, f.driveId, f.name, f.mime, f.url, f.size, f.folder, sha]);
    return { result: { saved: f.name, folder: f.folder, url: f.url, bytes: f.size }, entity: { type: 'task', id: String(id) } };
  }, (a) => ({ task: toId(a.task), filename: a.filename, encoding: a.encoding, chars: a.content?.length }));

  tool('eos_attach_drive_file', 'drive', {
    title: 'Gắn tệp Drive có sẵn',
    description: 'Gắn một tệp đã nằm trong thư mục Drive của người dùng vào việc (dùng khi agent đã tự tạo tệp bằng Drive của nó). Tệp ngoài thư mục của người dùng bị từ chối.',
    inputSchema: { task: taskRef, url: z.string().url() },
  }, async ({ task, url }) => {
    const id = toId(task);
    const driveId = driveIdFromUrl(url);
    if (!driveId) throw new DbError('Không đọc được mã tệp từ link Drive', 'P0001');
    const pre = await asUser(ident, async (c) => {
      await c.query('SELECT agent.mcp_task($1)', [id]);
      return (await c.query('SELECT drive_folder_id FROM core.users WHERE id = core.current_user_id()')).rows[0];
    });
    if (!pre?.drive_folder_id) throw new DbError('Thư mục Drive của bạn chưa thiết lập', 'P0001');
    let check;
    try { check = await fileInsideFolder(driveId, pre.drive_folder_id); }
    catch (e) { if (e.status === 404) throw new DbError('Agent hệ thống không thấy tệp này. Tệp phải nằm trong thư mục Drive đã chia sẻ của bạn.', 'P0001'); throw e; }
    if (!check.inside) throw new DbError('Tệp không nằm trong thư mục Drive của bạn', '42501');
    const f = check.file;
    await call('SELECT agent.mcp_register_file($1,$2,$3,$4,$5,$6,$7) AS r',
      [id, f.id, f.name, f.mimeType, f.webViewLink || url, Number(f.size || 0), check.folder]);
    return { result: { attached: f.name, folder: check.folder }, entity: { type: 'task', id: String(id) } };
  }, (a) => ({ task: toId(a.task) }));

  tool('eos_submit_result', 'write', {
    title: 'Nộp kết quả',
    description: 'Nộp kết quả việc người dùng được giao. Có quy trình duyệt → Chờ duyệt; không có → Xong (tính KPI). Chỉ gọi khi người dùng đã đồng ý nộp.',
    inputSchema: { task: taskRef, summary: z.string().min(10).max(4000) },
  }, async ({ task, summary }) => ({
    result: await call('SELECT agent.mcp_submit($1,$2) AS r', [toId(task), summary]),
    entity: { type: 'task', id: String(toId(task)) },
  }), (a) => ({ task: toId(a.task), chars: a.summary?.length }));

  registerGuides(server);

  server.registerPrompt('lam_va_nop_viec', {
    title: 'Làm và nộp một việc',
    description: 'Đọc việc, làm, lưu kết quả vào Drive cá nhân, xin đồng ý rồi nộp.',
    argsSchema: { task: z.string().describe('Mã việc, ví dụ T-123') },
  }, ({ task }) => ({
    messages: [{ role: 'user', content: { type: 'text', text:
`Làm việc ${task} trong Enterprise OS cho tôi:
1. eos_get_task ${task}, đọc kỹ mô tả, bình luận và tệp.
2. Nếu thiếu thông tin, hỏi tôi trước.
3. Làm kết quả; kết quả dài thì lưu bằng eos_save_to_drive.
4. Cho tôi xem tóm tắt. Khi tôi đồng ý mới eos_submit_result.` } }],
  }));

  server.registerPrompt('bao_cao_cuoi_ngay', {
    title: 'Báo cáo cuối ngày',
    description: 'Tổng hợp việc đã làm, còn dở, vướng trong ngày từ Enterprise OS.',
    argsSchema: {},
  }, () => ({
    messages: [{ role: 'user', content: { type: 'text', text:
'Gọi eos_my_day và eos_list_tasks (box assigned, status all). Viết báo cáo cuối ngày ngắn: đã xong hôm nay, đang làm (tiến độ), vướng gì, ngày mai làm gì. Hỏi tôi trước khi lưu vào Drive.' } }],
  }));
}

function registerGuides(server) {
  for (const topic of TOPICS) {
    server.registerResource(`guide-${topic}`, `eos://guide/${topic}`,
      { title: `Hướng dẫn: ${topic}`, mimeType: 'text/markdown' },
      async (uri) => ({ contents: [{ uri: uri.href, mimeType: 'text/markdown', text: GUIDE[topic] }] }));
  }

}

// ---------- Worker agent hệ thống: chỉ đọc việc có thẻ đang chạy, và chia việc nếu được phép ----------
function registerAgentTools(server, ident, tool, call) {
  tool('eos_get_task', 'read', {
    title: 'Chi tiết việc (agent)',
    description: 'Đọc việc mà agent đang có thẻ chạy, hoặc việc cha / việc con của nó. Đọc bằng quyền của người phụ trách việc.',
    inputSchema: { task: taskRef },
    annotations: { readOnlyHint: true },
  }, async ({ task }) => ({ result: await call('SELECT agent.mcp_agent_task($1) AS r', [toId(task)]), entity: { type: 'task', id: String(toId(task)) } }),
  (a) => ({ task: toId(a.task) }));

  tool('eos_delegate', 'delegate', {
    title: 'Chia việc con',
    description: 'Chia việc đang làm thành 1–8 việc con cho agent khác. Mỗi phần tử: agent (mã agent), title, description, skill (tùy chọn), after (chỉ số các phần tử phải xong trước). Sau khi chia, kết thúc thẻ hiện tại bằng kanban_complete; khi mọi việc con xong bạn sẽ nhận thẻ tổng hợp.',
    inputSchema: {
      task: taskRef,
      items: z.array(z.object({
        agent: z.string().regex(/^[a-z][a-z-]{1,31}$/),
        title: z.string().min(2).max(300),
        description: z.string().max(8000).optional(),
        skill: z.string().regex(/^[a-z-]{2,32}$/).optional(),
        after: z.array(z.number().int().min(0).max(7)).optional(),
      })).min(1).max(8),
    },
  }, async ({ task, items }) => ({
    result: await call('SELECT agent.delegate($1,$2) AS r', [toId(task), JSON.stringify(items)]),
    entity: { type: 'task', id: String(toId(task)) },
  }), (a) => ({ task: toId(a.task), items: a.items?.length }));
}
