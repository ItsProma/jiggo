'use strict';
const {randomUUID} = require('node:crypto');

const targets = Object.freeze(['home', 'scan', 'create', 'library', 'profile']);
const labels = {
  en: {home: 'Home', scan: 'Scan', create: 'Document Maker', library: 'Library', profile: 'Profile'},
  bn: {home: 'হোম', scan: 'স্ক্যান', create: 'ডকুমেন্ট তৈরি', library: 'লাইব্রেরি', profile: 'প্রোফাইল'},
};

function createNotificationBackend({db, messaging, HttpsError, serverTimestamp,
  now = Date.now, newId = randomUUID}) {
  const fail = (code, message) => { throw new HttpsError(code, message); };
  function requestData(request, fields) {
    if (!request.auth?.uid) fail('unauthenticated', 'Please sign in first.');
    if (!request.app) fail('unauthenticated', 'App verification is required.');
    const data = request.data;
    if (!data || typeof data !== 'object' || Array.isArray(data) ||
        data.expectedUid !== request.auth.uid ||
        Object.keys(data).some(key => !['expectedUid', 'installationId', ...fields].includes(key)) ||
        typeof data.installationId !== 'string' ||
        !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(data.installationId)) {
      fail('invalid-argument', 'Provide a valid device and account.');
    }
    return {uid: request.auth.uid, data};
  }
  const deviceRef = (uid, id) => db.collection('users').doc(uid).collection('notificationDevices').doc(id);
  async function active(transaction, uid) {
    const deleted = await transaction.get(db.collection('account_deletions').doc(uid));
    if (deleted.exists) fail('failed-precondition', 'This account is unavailable.');
  }
  function counter(data, field) {
    const value = data?.[field] ?? 0;
    if (!Number.isSafeInteger(value) || value < 0) fail('internal', 'Invalid notification usage.');
    return value;
  }
  function reserve(data, kind, maximum, cooldown) {
    const time = now();
    const day = new Date(time).toISOString().slice(0, 10);
    const count = data?.day === day ? counter(data, kind) : 0;
    const last = data?.[`${kind}At`] ?? 0;
    if (!Number.isSafeInteger(last) || last < 0) fail('internal', 'Invalid notification usage.');
    if (count >= maximum || (last > 0 && time - last < cooldown)) {
      fail('resource-exhausted', 'Please wait before another notification request.');
    }
    return {day, [kind]: count + 1, [`${kind}At`]: time, updatedAt: serverTimestamp()};
  }

  async function register(request) {
    const {uid, data} = requestData(request, ['fid', 'language', 'platform', 'revision']);
    if (typeof data.fid !== 'string' || data.fid.length < 16 || data.fid.length > 128 ||
        /[^\x21-\x7e]/.test(data.fid) || !['en', 'bn'].includes(data.language) ||
        !['web', 'android'].includes(data.platform) || !Number.isSafeInteger(data.revision) || data.revision < 1) fail('invalid-argument', 'Invalid notification registration.');
    await db.runTransaction(async tx => {
      await active(tx, uid);
      const rate = db.collection('users').doc(uid).collection('notificationLimits').doc('register');
      const usage = await tx.get(rate);
      const prior = await tx.get(deviceRef(uid, data.installationId));
      if (prior.exists && ((prior.data().revision ?? 0) > data.revision ||
          ((prior.data().revision ?? 0) === data.revision && prior.data().enabled === false))) {
        fail('failed-precondition', 'This device registration was revoked.');
      }
      // A refresh with identical values is idempotent and does not consume quota.
      const same = prior.exists && prior.data().fid === data.fid &&
        prior.data().language === data.language && prior.data().platform === data.platform;
      if (!same) tx.set(rate, reserve(usage.data(), 'registrations', 60, 1000));
      tx.set(deviceRef(uid, data.installationId), {fid: data.fid,
        language: data.language, platform: data.platform, enabled: true, revision: data.revision,
        lastSeenMs: now(), updatedAt: serverTimestamp()});
    });
    return {ok: true};
  }

  async function unregister(request) {
    const {uid, data} = requestData(request, ['revision']);
    if (!Number.isSafeInteger(data.revision) || data.revision < 1) fail('invalid-argument', 'Invalid device revision.');
    await db.runTransaction(async tx => {
      const deleted = await tx.get(db.collection('account_deletions').doc(uid));
      const ref = deviceRef(uid, data.installationId);
      const prior = await tx.get(ref);
      if (deleted.exists) { if (prior.exists) tx.delete(ref); return; }
      if (prior.exists && (prior.data().revision ?? 0) > data.revision) return;
      // Keep a small revocation fence without the FID. An older in-flight
      // registration must not turn notifications back on after opt-out.
      tx.set(ref, {enabled: false, revision: data.revision, updatedAt: serverTimestamp()});
    });
    return {ok: true};
  }

  async function sendTest(request) {
    const {uid, data} = requestData(request, ['target']);
    if (!targets.includes(data.target)) fail('invalid-argument', 'Invalid notification target.');
    const device = await db.runTransaction(async tx => {
      await active(tx, uid);
      const device = await tx.get(deviceRef(uid, data.installationId));
      const rate = db.collection('users').doc(uid).collection('notificationLimits').doc('test');
      const usage = await tx.get(rate);
      if (!device.exists || device.data().enabled !== true) fail('failed-precondition', 'Enable this device first.');
      tx.set(rate, reserve(usage.data(), 'tests', 5, 30000));
      return device.data();
    });
    const language = device.language === 'bn' ? 'bn' : 'en';
    const title = language === 'bn' ? 'Jiggo পরীক্ষামূলক নোটিফিকেশন' : 'Jiggo test notification';
    const body = language === 'bn' ? `এটি একটি পরীক্ষা। ${labels.bn[data.target]} খুলতে চাপো।`
      : `This is a test. Tap to open ${labels.en[data.target]}.`;
    const payload = makeMessage({uid, fid: device.fid,
      id: newId(), title, body, target: data.target, time: now(), revision: device.revision});
    // The payload is fixed and can only target the caller's registered device.
    // No client-provided fid, recipient UID, text or external URL is accepted.
    try {
      const deleted = await db.collection('account_deletions').doc(uid).get();
      const currentDevice = await deviceRef(uid, data.installationId).get();
      if (deleted.exists || !currentDevice.exists || currentDevice.data().enabled !== true ||
          currentDevice.data().revision !== device.revision || currentDevice.data().fid !== device.fid) {
        fail('failed-precondition', 'This account or device is unavailable.');
      }
      await messaging.send(payload);
    } catch (error) {
      if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(error?.code)) {
        // Do not delete a newer fid that refreshed while this send was in flight.
        await db.runTransaction(async tx => {
          const current = await tx.get(deviceRef(uid, data.installationId));
          if (current.exists && current.data().fid === device.fid && current.data().revision === device.revision) {
            tx.delete(current.ref || deviceRef(uid, data.installationId));
          }
        });
      }
      if (error instanceof HttpsError) throw error;
      fail('unavailable', 'The notification could not be delivered. Please reconnect the device.');
    }
    return {ok: true};
  }
  return {register, unregister, sendTest};
}

function makeMessage({uid, fid, id, title, body, target, time, revision}) {
  if (!targets.includes(target) || typeof title !== 'string' || !title || title.length > 120 ||
      typeof body !== 'string' || body.length > 500 || !uid || !fid || !id || !Number.isSafeInteger(revision) || revision < 1) {
    throw new TypeError('Invalid notification message');
  }
  return {
    fid,
    // Data-only: background handlers check consent and current ownership before
    // display. Do not add a notification block, which bypasses those checks.
    data: {v: '1', id, ownerUid: uid, title, body, target, sentAt: String(time), revision: String(revision)},
    android: {priority: 'high', ttl: 300000},
    webpush: {headers: {TTL: '300', Urgency: 'high'}},
  };
}

let backend;
function production() {
  if (!backend) {
    const {getFirestore, FieldValue} = require('firebase-admin/firestore');
    backend = createNotificationBackend({db: getFirestore(),
      messaging: require('firebase-admin/messaging').getMessaging(),
      HttpsError: require('firebase-functions/v2/https').HttpsError,
      serverTimestamp: () => FieldValue.serverTimestamp()});
  }
  return backend;
}
module.exports = {createNotificationBackend, makeMessage, targets,
  register: request => production().register(request),
  unregister: request => production().unregister(request),
  sendTest: request => production().sendTest(request)};
