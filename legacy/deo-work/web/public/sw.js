// Dẹo Work: lưu vỏ app để mở nhanh; /api và /auth luôn đi mạng.
const V = "deo-work-v1";
self.addEventListener("install", (e) => { e.waitUntil(caches.open(V).then((c) => c.addAll(["/", "/index.html", "/manifest.webmanifest", "/icon-192.png"])).then(() => self.skipWaiting())); });
self.addEventListener("activate", (e) => { e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== V).map((k) => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", (e) => {
  const u = new URL(e.request.url);
  if (e.request.method !== "GET" || u.origin !== location.origin || u.pathname.startsWith("/api/") || u.pathname.startsWith("/auth/")) return;
  if (u.pathname.startsWith("/assets/")) {   // tệp có hash: dùng cache trước
    e.respondWith(caches.match(e.request).then((r) => r || fetch(e.request).then((res) => { const c = res.clone(); caches.open(V).then((x) => x.put(e.request, c)); return res; })));
    return;
  }
  e.respondWith(fetch(e.request).then((res) => { const c = res.clone(); caches.open(V).then((x) => x.put(e.request, c)); return res; })
    .catch(() => caches.match(e.request).then((r) => r || caches.match("/index.html"))));
});
