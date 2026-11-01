const CACHE_NAME = 'divido-app-shell-v1';
const SHELL_FILES = [
  'index.html',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
  'version.json',
  'manifest.json',
  'assets/AssetManifest.bin',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/NOTICES',
  'assets/assets/.env',
  'assets/assets/divido_logo.png',
  'assets/assets/divido_logo_only.png',
  'assets/assets/gcash_logo.png',
  'assets/fonts/MaterialIcons-Regular.otf',
  'assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'icons/divido-icon-192.png',
  'icons/divido-icon-512.png',
  'divido_favicon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) =>
        cache.addAll(
          SHELL_FILES.map((path) => new URL(path, self.registration.scope)),
        ),
      )
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) =>
        Promise.all(
          names
            .filter((name) => name.startsWith('divido-app-shell-') && name !== CACHE_NAME)
            .map((name) => caches.delete(name)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const requestUrl = new URL(request.url);
  if (
    request.method !== 'GET' ||
    requestUrl.origin !== self.location.origin ||
    requestUrl.pathname.endsWith('/offline_service_worker.js')
  ) {
    return;
  }

  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE_NAME);
      const cachedResponse = await cache.match(request);

      try {
        const response = await fetch(request);
        if (response.ok) await cache.put(request, response.clone());
        return response;
      } catch (error) {
        if (cachedResponse) return cachedResponse;
        if (request.mode === 'navigate') {
          const cachedIndex = await cache.match(
            new URL('index.html', self.registration.scope),
          );
          if (cachedIndex) return cachedIndex;
        }
        throw error;
      }
    })(),
  );
});
