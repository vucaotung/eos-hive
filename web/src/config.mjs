// Cấu hình từ biến môi trường (đọc lúc khởi động, không có bí mật nào trong mã).
export function loadConfig(env = process.env) {
  const c = {
    port: Number(env.PORT || 8791),
    host: env.HOST || '127.0.0.1',                                   // chỉ nghe localhost; Caddy chuyển tiếp /app vào đây
    publicUrl: (env.PUBLIC_URL || 'https://work.enterpriseos.bond').replace(/\/+$/, ''),
    databaseUrl: env.DATABASE_URL,
    sessionSecret: env.SESSION_SECRET,
    sessionTtlSec: Math.round(Number(env.SESSION_TTL_HOURS || 8) * 3600),
    trustProxy: env.TRUST_PROXY === '1',
    loginRatePerMin: Number(env.LOGIN_RATE_PER_MIN || 30),                 // số lượt bắt đầu/hoàn tất đăng nhập mỗi phút mỗi IP
    writeRatePerMin: Number(env.WRITE_RATE_PER_MIN || 120),                // số thao tác ghi mỗi phút mỗi người
    google: {
      clientId: env.GOOGLE_LOGIN_CLIENT_ID || '',
      clientSecret: env.GOOGLE_LOGIN_CLIENT_SECRET || '',
      authUrl: env.GOOGLE_AUTH_URL || 'https://accounts.google.com/o/oauth2/v2/auth',
      tokenUrl: env.GOOGLE_TOKEN_URL || 'https://oauth2.googleapis.com/token',
    },
  };
  if (!c.databaseUrl) throw new Error('Thiếu DATABASE_URL');
  if (!c.sessionSecret || c.sessionSecret.length < 32) throw new Error('SESSION_SECRET phải có ít nhất 32 ký tự');
  c.secureCookies = c.publicUrl.startsWith('https://');
  c.host_header = new URL(c.publicUrl).host;
  c.googleEnabled = Boolean(c.google.clientId && c.google.clientSecret);
  return c;
}
