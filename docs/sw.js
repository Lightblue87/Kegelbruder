// Kegel Brüder PWA — offline cache. Bump CACHE_NAME on any deploy that
// changes a cached file so clients pick up the new version.
const CACHE_NAME = "kegelbrueder-v3";

const PRECACHE_URLS = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./css/style.css",
  "./vendor/sql-js/sql-wasm.js",
  "./vendor/sql-js/sql-wasm.wasm",
  "./js/main.js",
  "./js/format.js",
  "./js/db.js",
  "./js/state.js",
  "./js/numpad.js",
  "./js/components.js",
  "./js/views/sidebar.js",
  "./js/views/gameSession.js",
  "./js/views/attendance.js",
  "./js/views/playerSort.js",
  "./js/views/billing.js",
  "./js/views/tiebreak.js",
  "./js/views/tiebreakShared.js",
  "./js/views/pumpenTiebreak.js",
  "./js/views/cashManagement.js",
  "./js/views/playerManagement.js",
  "./js/views/archive.js",
  "./js/views/settings.js",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-192.png",
  "./icons/icon-maskable-512.png",
  "./icons/apple-touch-icon.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  event.respondWith(
    caches.match(event.request).then((cached) => {
      const networkFetch = fetch(event.request)
        .then((response) => {
          if (response && response.status === 200) {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return response;
        })
        .catch(() => cached || caches.match("./index.html"));
      return cached || networkFetch;
    })
  );
});
