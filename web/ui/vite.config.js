import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

// Dựng ra ../public (máy chủ Express phục vụ ở /app). Bản dựng được commit để máy chủ không cần Node dev.
// Khi phát triển: /app/api và /app/auth chuyển sang máy chủ web đang chạy (API_TARGET).
export default defineConfig({
  base: "/app/",
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    proxy: { "/app/api": process.env.API_TARGET || "http://127.0.0.1:8791", "/app/auth": process.env.API_TARGET || "http://127.0.0.1:8791" },
  },
  build: { target: "es2022", sourcemap: false, chunkSizeWarningLimit: 900, outDir: "../public", emptyOutDir: true },
});
