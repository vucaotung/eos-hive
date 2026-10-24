// Máy chủ MCP của Enterprise OS — https://work.enterpriseos.bond/mcp
// Streamable HTTP, không giữ phiên. Xác thực: Authorization: Bearer eos_<48 hex> (mã cá nhân tạo trên app).
import express from 'express';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { verifyToken } from './db.mjs';
import { registerTools } from './tools.mjs';

const PORT = Number(process.env.PORT || 8790);
const RATE = Number(process.env.MCP_RATE_PER_MIN || 120);
const hits = new Map();   // tokenId → [mốc thời gian]
const MINUTE = 60_000;

// Bộ đếm xác thực THẤT BẠI theo IP (IP thật do Caddy chuyển qua X-Forwarded-For, app.set('trust proxy', 'loopback')). Chỉ đếm lần sai; lần đúng không xóa bộ đếm.
// Vượt ngưỡng thì trả 429 TRƯỚC khi truy vấn CSDL (kể cả mã đúng) cho đến khi các lần sai cũ trượt khỏi cửa sổ. Hệ quả cần biết: nhiều máy dùng chung một IP (NAT) chung một hạn mức.
// Giữ trong bộ nhớ của tiến trình (khởi động lại thì xóa); ngưỡng chỉnh bằng MCP_AUTHFAIL_MAX / MCP_AUTHFAIL_WINDOW_MS.
export function makeAuthGuard({ max = 20, windowMs = 5 * MINUTE, maxKeys = 50_000 } = {}) {
  const fails = new Map();   // ip → [mốc thời gian của các lần sai]
  const live = (k, now) => { const a = (fails.get(k) || []).filter((t) => now - t < windowMs); if (a.length) fails.set(k, a); else fails.delete(k); return a; };
  return {
    blocked: (k) => live(k, Date.now()).length >= max,
    fail: (k) => {
      const now = Date.now(), a = live(k, now);
      if (a.length < max) a.push(now);   // bị chặn rồi thì không kéo dài cửa sổ
      fails.set(k, a);
      if (fails.size > maxKeys) fails.delete(fails.keys().next().value);   // chặn phình bộ nhớ khi bị quét từ nhiều IP
    },
    prune: () => { const now = Date.now(); for (const k of [...fails.keys()]) live(k, now); },
    size: () => fails.size,
  };
}

function rateLimited(tokenId) {
  const now = Date.now();
  const arr = (hits.get(tokenId) || []).filter((t) => now - t < 60_000);
  arr.push(now);
  hits.set(tokenId, arr);
  return arr.length > RATE;
}

export function buildApp(opts = {}) {
  const guard = makeAuthGuard({ max: Number(opts.authFailMax ?? process.env.MCP_AUTHFAIL_MAX ?? 20), windowMs: Number(opts.authFailWindowMs ?? process.env.MCP_AUTHFAIL_WINDOW_MS ?? 5 * MINUTE) });
  // dọn bộ đếm cũ (cả bộ đếm theo mã): không để các bảng trong bộ nhớ lớn dần
  const sweep = setInterval(() => { guard.prune(); const now = Date.now(); for (const [k, arr] of hits) { const a = arr.filter((t) => now - t < MINUTE); if (a.length) hits.set(k, a); else hits.delete(k); } }, MINUTE);
  sweep.unref();
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 'loopback');   // Caddy ở phía trước
  app.use(express.json({ limit: '15mb' }));   // base64 của tệp 10 MB

  app.get('/healthz', (_req, res) => res.json({ ok: true }));

  const deny = (res, status, message, headers = {}) => res.status(status)
    .set({ 'WWW-Authenticate': 'Bearer realm="enterprise-os"', ...headers })
    .json({ jsonrpc: '2.0', error: { code: -32001, message }, id: null });

  app.post('/mcp', async (req, res) => {
    const raw = (req.get('authorization') || '').replace(/^Bearer\s+/i, '').trim();
    const ip = req.ip || 'unknown';
    if (guard.blocked(ip)) return deny(res, 429, 'Sai mã quá nhiều lần, thử lại sau ít phút', { 'Retry-After': '300' });
    let ident;
    try { ident = await verifyToken(raw, req.ip); } catch (e) { console.error('verify', e); return deny(res, 503, 'Máy chủ tạm lỗi'); }
    if (!ident) { guard.fail(ip); return deny(res, 401, 'Mã MCP sai, hết hạn hoặc đã thu hồi'); }
    if (rateLimited(ident.tokenId)) return deny(res, 429, 'Gọi quá nhanh, chờ một phút');

    const server = new McpServer(
      { name: 'enterprise-os', version: '0.1.0' },
      { instructions: 'Enterprise OS: hệ thống công việc, công văn, nhân sự của công ty. Gọi eos_guide trước nếu chưa quen. Bạn hành động thay mặt người dùng, trong quyền của họ.' },
    );
    registerTools(server, ident);
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined, enableJsonResponse: true });
    res.on('close', () => { transport.close(); server.close(); });
    try {
      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
    } catch (e) {
      console.error('mcp', e);
      if (!res.headersSent) res.status(500).json({ jsonrpc: '2.0', error: { code: -32603, message: 'Lỗi máy chủ' }, id: null });
    }
  });

  const notAllowed = (_req, res) => res.status(405).set('Allow', 'POST').json({ jsonrpc: '2.0', error: { code: -32000, message: 'Chỉ nhận POST' }, id: null });
  app.get('/mcp', notAllowed);
  app.delete('/mcp', notAllowed);
  return app;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  for (const k of ['DATABASE_URL']) if (!process.env[k]) { console.error(`Thiếu ${k}`); process.exit(1); }
  buildApp().listen(PORT, '127.0.0.1', () => console.log(`eos-mcp lắng nghe 127.0.0.1:${PORT}`));
}
