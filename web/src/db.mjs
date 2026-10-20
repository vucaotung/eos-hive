// Kết nối Postgres cho web. Đăng nhập bằng eos_web (thành viên web_svc). Mỗi thao tác là một giao dịch:
// SET LOCAL ROLE web_svc + request.jwt.claims của đúng người đăng nhập; web chỉ gọi hàm agent.web_* và vài hàm agent.mcp_* đã cấp quyền.
import pg from 'pg';

export class DbError extends Error {
  constructor(message, code) { super(message); this.code = code; }
  get forbidden() { return this.code === '42501'; }
  get business() { return this.code === 'P0001'; }      // RAISE EXCEPTION do hàm nghiệp vụ: câu tiếng Việt, hiển thị được cho người dùng
}

export function createDb(databaseUrl) {
  const pool = new pg.Pool({ connectionString: databaseUrl, max: 8, idleTimeoutMillis: 30_000, statement_timeout: 10_000 });
  async function run(claims, fn) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('SET LOCAL ROLE web_svc');
      if (claims) await client.query("SELECT set_config('request.jwt.claims', $1, true)", [JSON.stringify(claims)]);
      const out = await fn(client);
      await client.query('COMMIT');
      return out;
    } catch (e) {
      await client.query('ROLLBACK').catch(() => {});
      if (e.code && typeof e.code === 'string' && e.code.length === 5) throw new DbError(e.message, e.code);
      throw e;
    } finally { client.release(); }
  }
  const one = async (client, sql, params) => (await client.query(sql, params)).rows[0]?.r;
  return {
    asUser: (sub, fn) => run({ sub, role: 'app_user', via: 'web' }, fn),
    asAnon: (fn) => run(null, fn),
    one,
    close: () => pool.end(),
  };
}
