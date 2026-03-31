const CACHE_NAME = 'moodly-v10';
const ASSETS = [
  './app.html',
  './manifest.json'
];

// Install — cache core assets
self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(ASSETS))
      .then(() => self.skipWaiting())
  );
});

// Activate — clean old caches
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

// Fetch — network first, fallback to cache
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET' || e.request.url.startsWith('chrome-extension')) return;

  e.respondWith(
    fetch(e.request)
      .then(res => {
        if (res.ok && e.request.url.startsWith(self.location.origin)) {
          const clone = res.clone();
          caches.open(CACHE_NAME).then(cache => cache.put(e.request, clone));
        }
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});

// Push notification handler
self.addEventListener('push', e => {
  const data = e.data ? e.data.json() : {};
  const title = data.title || 'Moodly';
  const options = {
    body: data.body || 'Dags att checka in! Hur var dagen?',
    icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text y=".9em" font-size="90">🧒</text></svg>',
    badge: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text y=".9em" font-size="90">🧒</text></svg>',
    tag: 'moodly-reminder',
    renotify: true,
    data: { url: './app.html' }
  };
  e.waitUntil(self.registration.showNotification(title, options));
});

// Notification click — open app
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL('./app.html', self.location.origin).href;
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(clients => {
        const existing = clients.find(c => new URL(c.url).pathname.endsWith('app.html'));
        if (existing) return existing.focus();
        return self.clients.openWindow(url);
      })
  );
});

// Message handler
self.addEventListener('message', e => {
  if (e.data?.type === 'SCHEDULE_REMINDER') {
    const hour = e.data.hour || 17;
    const minute = e.data.minute || 0;
    scheduleCheck(hour, minute);
  }
  if (e.data?.type === 'PARENT_SUMMARY') {
    parentSummary = { body: e.data.body, hour: e.data.hour || 18, minute: e.data.minute || 0 };
    scheduleParentSummary();
  }
});

let parentSummary = null;
let parentSummaryInterval = null;
function scheduleParentSummary() {
  if (parentSummaryInterval) clearInterval(parentSummaryInterval);
  if (!parentSummary) return;
  parentSummaryInterval = setInterval(async () => {
    const now = new Date();
    if (now.getHours() === parentSummary.hour && now.getMinutes() >= parentSummary.minute && now.getMinutes() < parentSummary.minute + 15) {
      const clients = await self.clients.matchAll({ type: 'window' });
      if (clients.length === 0) {
        self.registration.showNotification('Moodly — Dagens sammanfattning', {
          body: parentSummary.body,
          icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text y=".9em" font-size="90">📊</text></svg>',
          tag: 'moodly-parent-summary',
          renotify: true,
          data: { url: './app.html' }
        });
        parentSummary = null; // Only show once per day
      }
    }
  }, 15 * 60 * 1000);
}

let reminderInterval = null;
function scheduleCheck(hour, minute) {
  if (reminderInterval) clearInterval(reminderInterval);
  reminderInterval = setInterval(async () => {
    const now = new Date();
    if (now.getHours() === hour && now.getMinutes() >= minute && now.getMinutes() < minute + 15) {
      const clients = await self.clients.matchAll({ type: 'window' });
      if (clients.length === 0) {
        self.registration.showNotification('Moodly', {
          body: 'Dags att checka in! Hur var dagen? 📊',
          tag: 'moodly-daily',
          renotify: false,
          data: { url: './app.html' }
        });
      }
    }
  }, 15 * 60 * 1000);
}
