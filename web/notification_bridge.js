/* Browser-only notification operations. No tokens or user content are logged. */
(() => {
  'use strict';
  let callback;
  const pending = [];
  const base = new URL('./', document.baseURI);
  const scope = new URL('firebase-cloud-messaging-push-scope', base).href;
  let workerPromise;
  const supported = () => window.isSecureContext && 'Notification' in window &&
    'serviceWorker' in navigator;
  const worker = () => {
    if (!supported()) return Promise.reject(new Error('Notifications unavailable'));
    workerPromise ??= navigator.serviceWorker.register(
      new URL('firebase-messaging-sw.js', base).href, {scope})
      .catch(error => { workerPromise = undefined; throw error; });
    return workerPromise;
  };
  const activeWorker = async () => {
    const registration = await worker();
    const active = registration.active || registration.waiting || registration.installing;
    if (!active) throw new Error('Notification worker unavailable');
    if (active.state !== 'activated') await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Notification worker timeout')), 10000);
      active.addEventListener('statechange', () => {
        if (active.state === 'activated') { clearTimeout(timer); resolve(); }
        if (active.state === 'redundant') { clearTimeout(timer); reject(new Error('Notification worker stopped')); }
      });
    });
    return registration;
  };
  const command = async data => {
    const registration = await activeWorker();
    await new Promise((resolve, reject) => {
      const channel = new MessageChannel();
      const timer = setTimeout(() => reject(new Error('Notification settings timeout')), 3000);
      channel.port1.onmessage = event => {
        clearTimeout(timer); channel.port1.close();
        event.data?.ok ? resolve() : reject(new Error('Notification settings not saved'));
      };
      registration.active.postMessage(data, [channel.port2]);
    });
  };
  const opened = data => {
    const raw = JSON.stringify(data);
    if (raw.length > 6000) return;
    if (callback) callback(raw); else pending.push(raw);
  };
  // Consume the app-owned launch fragment before Flutter reads the initial route.
  if (location.hash.startsWith('#jiggo-notice=')) {
    try { opened(JSON.parse(decodeURIComponent(location.hash.slice(14)))); } catch (_) { /* Invalid launch data. */ }
    history.replaceState(null, '', location.pathname + location.search);
  }
  if ('serviceWorker' in navigator) navigator.serviceWorker.addEventListener('message', event => {
    if (event.data?.type === 'jiggo-notification-open') opened(event.data.notice);
  });
  window.jiggoNotifications = {
    supported,
    permission: () => supported() ? Notification.permission : 'unsupported',
    request: () => supported() ? Notification.requestPermission() : Promise.resolve('unsupported'),
    bind: handler => { callback = handler; while (pending.length) callback(pending.shift()); },
    unbind: () => { callback = undefined; },
    account: async (ownerUid, enabled, revision) => {
      // Opting out on a fresh installation must not register a push worker.
      if (!enabled && !await navigator.serviceWorker.getRegistration(scope)) return;
      await command({type: 'jiggo-account', ownerUid, enabled, revision});
    },
    show: async raw => {
      if (Notification.permission !== 'granted') throw new Error('Notification permission needed');
      const notice = JSON.parse(raw);
      await command({type: 'jiggo-local-test', notice});
    },
    cancelAll: async () => {
      const registration = await navigator.serviceWorker.getRegistration(scope);
      if (registration) for (const notice of await registration.getNotifications()) notice.close();
    },
  };
})();
