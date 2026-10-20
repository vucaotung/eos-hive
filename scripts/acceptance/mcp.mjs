#!/usr/bin/env node
// Client MCP tối giản cho bộ nghiệm thu: node mcp.mjs <công cụ> '<json đối số>'   (mã trong EOS_ACCEPT_TOKEN, không in)
// Thoát 0 nếu công cụ chạy được, 3 nếu công cụ trả lỗi, 4 nếu kết nối/mã bị từ chối. `--list` in số công cụ.
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const sdk = (f) => pathToFileURL(path.join(root, 'mcp/node_modules/@modelcontextprotocol/sdk/dist/esm/client', f)).href;
const { Client } = await import(sdk('index.js'));
const { StreamableHTTPClientTransport } = await import(sdk('streamableHttp.js'));
const url = process.env.EOS_MCP_URL || 'https://work.enterpriseos.bond/mcp';
const token = process.env.EOS_ACCEPT_TOKEN;
if (!token) { console.error('thiếu EOS_ACCEPT_TOKEN'); process.exit(2); }
const mask = (s) => String(s).replace(/eos_[0-9a-f]{20,}/g, '(mã ẩn)');
const c = new Client({ name: 'acceptance', version: '1' });
try {
  await c.connect(new StreamableHTTPClientTransport(new URL(url), { requestInit: { headers: { Authorization: `Bearer ${token}` } } }));
} catch (e) { console.error('KẾT NỐI:', mask(e.message).slice(0, 200)); process.exit(4); }
const [tool, raw] = process.argv.slice(2);
try {
  if (tool === '--list') { console.log((await c.listTools()).tools.length); }
  else {
    const r = await c.callTool({ name: tool, arguments: raw ? JSON.parse(raw) : {} });
    console.log(mask((r.content || []).map((x) => x.text || '').join('\n')));
    if (r.isError) process.exitCode = 3;
  }
} catch (e) { console.log(mask(e.message).slice(0, 300)); process.exitCode = 3; }
await c.close();
