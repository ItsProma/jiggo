/* Handle click routing before loading Firebase, as required by the FCM SDK. */
'use strict';
const allowedTargets = new Set(['home', 'scan', 'create', 'library', 'profile']);
const appUrl = new URL('./', self.location.href).href;
const database = () => new Promise((resolve, reject) => {
  const request = indexedDB.open('jiggo-notification-state', 1);
  request.onupgradeneeded = () => request.result.createObjectStore('settings');
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(new Error('Notification settings unavailable'));
});
async function state(write) {
  const db = await database();
  try {
    return await new Promise((resolve, reject) => {
      const tx = db.transaction('settings', write ? 'readwrite' : 'readonly');
      const store = tx.objectStore('settings');
      const request = store.get('account');
      let value;
      request.onsuccess = () => {
        const prior = request.result;
        value = prior;
        if (!write) return;
        // An older tab or in-flight command cannot undo a newer opt-out/account
        // change. Compare and write in the same IndexedDB transaction.
        if (prior && (prior.revision > write.revision ||
            (prior.revision === write.revision &&
              (prior.ownerUid !== write.ownerUid || (!prior.enabled && write.enabled))))) return;
        store.put(write, 'account');
        value = write;
      };
      tx.oncomplete = () => resolve(value);
      tx.onerror = () => reject(new Error('Notification settings unavailable'));
      tx.onabort = tx.onerror;
    });
  } finally { db.close(); }
}
function valid(notice) {
  const time = Number(notice?.sentAt);
  return notice?.v === '1' && typeof notice.id === 'string' && notice.id.length > 0 && notice.id.length <= 120 &&
    typeof notice.ownerUid === 'string' && notice.ownerUid.length > 0 && notice.ownerUid.length <= 128 &&
    typeof notice.title === 'string' && notice.title.length > 0 && notice.title.length <= 120 &&
    Number.isSafeInteger(Number(notice.revision)) && Number(notice.revision) >= 0 && typeof notice.body === 'string' && notice.body.length <= 500 && allowedTargets.has(notice.target) &&
    Number.isSafeInteger(time) && time >= Date.now() - 86400000 && time <= Date.now() + 300000;
}
async function show(notice) {
  if (!valid(notice)) throw new Error('Invalid notification');
  const account = await state();
  if (!account?.enabled || account.ownerUid !== notice.ownerUid || account.revision !== Number(notice.revision)) return false;
  await self.registration.showNotification(notice.title, {
    body: notice.body, tag: notice.id, data: notice,
    icon: new URL('icons/Icon-192.png', appUrl).href,
  });
  return true;
}
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('message', event => {
  const data = event.data;
  if (data?.type !== 'jiggo-account' && data?.type !== 'jiggo-local-test') return;
  event.waitUntil((async () => {
    try {
      if (data.type === 'jiggo-account') {
        if (typeof data.ownerUid !== 'string' || data.ownerUid.length > 128 ||
            typeof data.enabled !== 'boolean' || !Number.isSafeInteger(data.revision) || data.revision < 0) throw new Error('Invalid account');
        await state({ownerUid: data.ownerUid, enabled: data.enabled, revision: data.revision});
        if (!data.enabled || !data.ownerUid) {
          for (const notice of await self.registration.getNotifications()) notice.close();
        }
      } else if (!await show(data.notice)) throw new Error('Notification consent changed');
      event.ports[0]?.postMessage({ok: true});
    } catch (_) { event.ports[0]?.postMessage({ok: false}); }
  })());
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const notice = event.notification.data;
  if (!valid(notice)) return;
  event.stopImmediatePropagation();
  event.waitUntil((async () => {
    const account = await state();
    if (!account?.enabled || account.ownerUid !== notice.ownerUid || account.revision !== Number(notice.revision)) return;
    const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const client of windows) {
      if (new URL(client.url).origin === new URL(appUrl).origin &&
          [new URL(appUrl).pathname, new URL(appUrl).pathname + 'index.html'].includes(new URL(client.url).pathname)) {
        client.postMessage({type: 'jiggo-notification-open', notice});
        await client.focus();
        return;
      }
    }
    await self.clients.openWindow(appUrl + '#jiggo-notice=' + encodeURIComponent(JSON.stringify(notice)));
  })());
});
// Match firebase_core_web's JS SDK. The local test still works offline if these
// scripts cannot load; the app reports remote setup/connection separately.
try {
  importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-app-compat.js');
  importScripts('https://www.gstatic.com/firebasejs/13.1.0/firebase-messaging-compat.js');
  firebase.initializeApp({
    apiKey: 'AIzaSyA1BaUTFz8EjTNExm17ezGsxJYk42e29K0',
    appId: '1:651664929928:web:fa1c6c5511b1e0c6361b3d',
    messagingSenderId: '651664929928', projectId: 'jiggo-bee33',
    authDomain: 'jiggo-bee33.firebaseapp.com',
    storageBucket: 'jiggo-bee33.firebasestorage.app',
  });
  firebase.messaging().onBackgroundMessage(message => show(message.data).catch(() => {}));
} catch (_) { /* Remote setup is retried by the next worker update. */ }
