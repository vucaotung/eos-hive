// Service worker Dẹo Việc: lưu vỏ app để mở nhanh và mở được khi mất mạng.
// Dữ liệu /api luôn đi mạng (không cache), để không bao giờ hiện số liệu cũ như số mới.
const V = "deo-viec-v2";
const SHELL = ["/", "/index.html", "/app.css", "/app.js", "/register-sw.js", "/manifest.webmanifest", "/icon-192.png", "/icon-512.png", "/apple-touch-icon.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(V).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.pathname.startsWith("/api/")) return;
  if (u.origin === location.origin) {
    // vỏ app: mạng trước, rơi về cache khi offline
    e.respondWith(fetch(e.request).then(r => { const c = r.clone(); caches.open(V).then(x => x.put(e.request, c)); return r; })
      .catch(() => caches.match(e.request).then(r => r || caches.match("/index.html"))));
  } else if (u.hostname.endsWith("gstatic.com") || u.hostname.endsWith("googleapis.com")) {
    e.respondWith(caches.match(e.request).then(r => r || fetch(e.request).then(res => { const c = res.clone(); caches.open(V).then(x => x.put(e.request, c)); return res; })));
  }
});
