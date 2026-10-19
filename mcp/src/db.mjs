// Kết nối Postgres cho máy chủ MCP.
// Đăng nhập bằng tài khoản eos_mcp (thành viên của vai trò mcp_svc). Mỗi lần gọi công cụ là một giao dịch:
// SET LOCAL ROLE mcp_svc + request.jwt.claims của đúng người sở hữu mã, nên mọi hàm agent.mcp_* chỉ thấy quyền của người đó.
import pg from 'pg';

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: Number(process.env.PG_POOL_MAX || 10),
  idleTimeoutMillis: 30_000,
  statement_timeout: 10_000,
});

export class DbError extends Error {
  constructor(message, code) { super(message); this.code = code; }
}

// Chạy fn(client) trong giao dịch, mang danh tính người dùng (sub) và kênh (via)
export async function asUser(ident, fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SET LOCAL ROLE mcp_svc');
    await client.query("SELECT set_config('request.jwt.claims', $1, true)",
      [JSON.stringify(ident.agentId
        ? { sub: ident.userId, role: 'agent', agent: ident.agentId, via: `agent:${ident.agentCode}` }
        : { sub: ident.userId, role: 'app_user', via: `mcp:${ident.prefix}` })]);
    const out = await fn(client);
    await client.query('COMMIT');
    return out;
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    // 42501 = không đủ quyền; P0001 = lỗi nghiệp vụ do hàm báo
    if (e.code) throw new DbError(e.message, e.code);
    throw e;
  } finally {
    client.release();
  }
}

// Gọi hàm không cần danh tính người dùng (kiểm tra mã, ghi nhật ký)
export async function asService(sql, params) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SET LOCAL ROLE mcp_svc');
    const r = await client.query(sql, params);
    await client.query('COMMIT');
    return r;
  } catch (e) {
    await client.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    client.release();
  }
}

export async function verifyToken(raw, ip) {
  if (!/^eos_[0-9a-f]{48}$/.test(raw || '')) return null;
  const r = await asService('SELECT * FROM agent.mcp_token_verify($1, $2)', [raw, ip || null]);
  if (!r.rows.length) return null;
  const k = r.rows[0];
  return { tokenId: k.token_id, userId: k.user_id, companyId: k.company_id, scopes: k.scopes, prefix: k.prefix,
           agentId: k.agent_id || null, agentCode: k.agent_code || null };
}

export async function logCall(ident, tool, args, outcome, entity, ms) {
  try {
    await asService('SELECT agent.mcp_log($1,$2,$3,$4,$5,$6,$7)',
      [ident.tokenId, tool, args || {}, outcome, entity?.type || null, entity?.id || null, ms]);
  } catch { /* nhật ký không được làm hỏng lần gọi */ }
}

export async function close() { await pool.end(); }
