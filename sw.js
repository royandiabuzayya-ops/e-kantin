// Service Worker untuk E-Kantin Cerdas.
// Strategi: NETWORK-FIRST untuk file aplikasi sendiri (app shell) - selalu
// coba ambil versi terbaru dulu saat online, baru fallback ke cache kalau
// offline. Ini penting karena aplikasi masih aktif dikembangkan/diperbarui;
// strategi cache-first (versi lama) membuat HP bisa "terjebak" memakai versi
// lama selamanya walau file terbaru sudah di-upload ke hosting.
//
// CACHE_NAME dinaikkan setiap ada perubahan berarti pada file ini supaya
// versi cache lama otomatis dibersihkan (lihat 'activate' di bawah).
const CACHE_NAME = 'ekantin-cache-v2';
const APP_SHELL = [
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  // Hanya tangani request GET dari origin yang sama (app shell).
  // Request ke CDN (Tailwind/Fonts) atau ke Google Apps Script (sync)
  // dibiarkan lewat jaringan seperti biasa (tidak disentuh Service Worker ini).
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    fetch(event.request, { cache: 'no-store' })
      .then((response) => {
        // Berhasil dari jaringan (online): simpan salinan terbaru ke cache
        // untuk cadangan offline nanti, lalu kembalikan versi terbaru ini.
        const clone = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        return response;
      })
      .catch(() => {
        // Gagal (offline/tidak ada koneksi): baru pakai salinan cache lama
        // sebagai fallback, supaya aplikasi tetap bisa dibuka offline.
        return caches.match(event.request);
      })
  );
});
