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

function rateLimited(tokenId) {
  const now = Date.now();
  const arr = (hits.get(tokenId) || []).filter((t) => now - t < 60_000);
  arr.push(now);
  hits.set(tokenId, arr);
  return arr.length > RATE;
}

export function buildApp() {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 'loopback');   // Caddy ở phía trước
  app.use(express.json({ limit: '15mb' }));   // base64 của tệp 10 MB

  app.get('/healthz', (_req, res) => res.json({ ok: true }));

  const deny = (res, status, message) => res.status(status)
    .set('WWW-Authenticate', 'Bearer realm="enterprise-os"')
    .json({ jsonrpc: '2.0', error: { code: -32001, message }, id: null });

  app.post('/mcp', async (req, res) => {
    const raw = (req.get('authorization') || '').replace(/^Bearer\s+/i, '').trim();
    let ident;
    try { ident = await verifyToken(raw, req.ip); } catch (e) { console.error('verify', e); return deny(res, 503, 'Máy chủ tạm lỗi'); }
    if (!ident) return deny(res, 401, 'Mã MCP sai, hết hạn hoặc đã thu hồi');
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
