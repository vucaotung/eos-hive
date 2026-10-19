# Bên trong container web: phục vụ app tĩnh, chuyển /api → PostgREST, /auth → dịch vụ đăng nhập.
{
	admin off
	auto_https off
}
:8080 {
	encode zstd gzip
	handle_path /api/* {
		reverse_proxy api:3000
	}
	handle /auth/* {
		reverse_proxy auth:8090
	}
	handle {
		root * /srv
		header {
			X-Content-Type-Options nosniff
			Referrer-Policy strict-origin-when-cross-origin
			X-Frame-Options DENY
			Permissions-Policy "camera=(), microphone=(), geolocation=()"
			# Nút đăng nhập Google cần accounts.google.com
			Content-Security-Policy "default-src 'self'; script-src 'self' https://accounts.google.com/gsi/client; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com https://accounts.google.com/gsi/style; font-src https://fonts.gstatic.com; img-src 'self' data: https://*.googleusercontent.com; connect-src 'self' https://accounts.google.com/gsi/; frame-src https://accounts.google.com/gsi/; manifest-src 'self'; base-uri 'self'; form-action 'self'"
		}
		@shell path / /index.html /sw.js /manifest.webmanifest
		header @shell Cache-Control "no-cache"
		@assets path /assets/*
		header @assets Cache-Control "public, max-age=31536000, immutable"
		try_files {path} /index.html
		file_server
	}
}
