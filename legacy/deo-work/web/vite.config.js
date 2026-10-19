import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// Khi phát triển: /api → PostgREST, /auth → dịch vụ đăng nhập
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    proxy: {
      "/api": { target: process.env.API_TARGET || "http://localhost:3300", rewrite: (p) => p.replace(/^\/api/, "") },
      "/auth": { target: process.env.AUTH_TARGET || "http://localhost:8090" },
    },
  },
  build: { target: "es2022", sourcemap: false, chunkSizeWarningLimit: 900 },
});
