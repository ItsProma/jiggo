'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createNotificationBackend, makeMessage} = require('../notification_backend.cjs');

const installationId = '11111111-1111-4111-8111-111111111111';
const fid = 'cExampleInstallation12';
class HttpsError extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
function fixture() {
  const records = new Map();
  const sends = [];
  let time = Date.parse('2026-11-15T12:00:00Z');
  let failure;
  let beforeSend;
  const ref = key => ({key, collection: name => ({doc: id => ref(`${key}/${name}/${id}`)}),
    get: async () => snapshot(ref(key)), delete: async () => records.delete(key)});
  const snapshot = ref => ({exists: records.has(ref.key), data: () => records.get(ref.key), ref});
  let tail = Promise.resolve();
  const db = {collection: name => ({doc: id => ref(`${name}/${id}`)}),
    runTransaction(callback) {
      const run = tail.then(async () => {
        const writes = [];
        const result = await callback({get: async ref => snapshot(ref),
          set: (ref, value) => writes.push(() => records.set(ref.key, value)),
          delete: ref => writes.push(() => records.delete(ref.key))});
        for (const write of writes) write();
        return result;
      });
      tail = run.catch(() => {});
      return run;
    },
  };
  const service = createNotificationBackend({db, HttpsError,
    messaging: {async send(message) { sends.push(message); if (beforeSend) beforeSend(); if (failure) throw failure; }},
    serverTimestamp: () => 'SERVER_TIMESTAMP', now: () => time, newId: () => 'notice-1'});
  const request = data => ({auth: {uid: 'user-1'}, app: {appId: 'verified'},
    data: {expectedUid: 'user-1', installationId, ...data}});
  const registration = data => request({fid, language: 'bn', platform: 'android', revision: 1, ...data});
  return {service, records, sends, request, registration,
    advance: ms => { time += ms; }, failSend: error => { failure = error; },
    beforeSend: callback => { beforeSend = callback; },
    device: `users/user-1/notificationDevices/${installationId}`};
}

test('Registration stores only the verified caller device and locale', async () => {
  const f = fixture(); await f.service.register(f.registration());
  assert.equal(f.records.get(f.device).fid, fid);
  assert.equal(f.records.get(f.device).language, 'bn');
  assert.equal(f.records.get(f.device).revision, 1);
  assert.equal(f.sends.length, 0);
  assert.ok([...f.records.keys()].every(key => key.startsWith('users/user-1/')));
});
for (const which of ['auth', 'app']) test(`Registration requires ${which}`, async () => {
  const f = fixture(); const req = f.registration(); delete req[which];
  await assert.rejects(f.service.register(req), {code: 'unauthenticated'});
  assert.equal(f.records.size, 0);
});
for (const data of [
  {expectedUid: 'other-user'}, {installationId: '../other'}, {fid: 'bad'},
  {language: 'xx'}, {platform: 'ios'}, {revision: -1}, {revision: 1.5}, {recipient: 'other'},
]) test(`Rejects malformed registration ${JSON.stringify(data)}`, async () => {
  const f = fixture(); await assert.rejects(f.service.register(f.registration(data)), {code: 'invalid-argument'});
  assert.equal(f.records.size, 0);
});
test('Deletion marker blocks registration without recreating account data', async () => {
  const f = fixture(); f.records.set('account_deletions/user-1', {status: 'deleting'});
  await assert.rejects(f.service.register(f.registration()), {code: 'failed-precondition'});
  assert.equal(f.records.size, 1);
});
test('Identical registration is idempotent and does not consume another quota slot', async () => {
  const f = fixture(); await f.service.register(f.registration());
  await f.service.register(f.registration());
  assert.equal(f.records.get('users/user-1/notificationLimits/register').registrations, 1);
});
test('Opt-out removes the FID and rejects an older in-flight registration', async () => {
  const f = fixture(); await f.service.register(f.registration());
  await f.service.unregister(f.request({revision: 2}));
  assert.equal(f.records.get(f.device).fid, undefined);
  assert.equal(f.records.get(f.device).enabled, false);
  await assert.rejects(f.service.register(f.registration()), {code: 'failed-precondition'});
  await assert.rejects(f.service.register(f.registration({revision: 2})), {code: 'failed-precondition'});
  f.advance(2000);
  await f.service.register(f.registration({revision: 3}));
  assert.equal(f.records.get(f.device).enabled, true);
});
test('An older sign-out cleanup cannot remove a newer registration', async () => {
  const f = fixture(); await f.service.register(f.registration({revision: 3}));
  await f.service.unregister(f.request({revision: 2}));
  assert.equal(f.records.get(f.device).enabled, true);
  assert.equal(f.records.get(f.device).revision, 3);
});
test('Cleanup during account deletion does not leave a new revocation record', async () => {
  const f = fixture(); f.records.set('account_deletions/user-1', {status: 'deleting'});
  await f.service.unregister(f.request({revision: 2}));
  assert.equal(f.records.size, 1);
});
test('Push test only sends fixed text to the caller registration, with no auto-display payload', async () => {
  const f = fixture(); await f.service.register(f.registration());
  await f.service.sendTest(f.request({target: 'library'}));
  const message = f.sends[0];
  assert.equal(message.fid, fid);
  assert.equal(message.token, undefined);
  assert.equal(message.notification, undefined);
  assert.equal(message.data.ownerUid, 'user-1');
  assert.equal(message.data.target, 'library');
  assert.equal(message.data.revision, '1');
  assert.match(message.data.body, /লাইব্রেরি/);
  assert.ok(Object.values(message.data).every(value => typeof value === 'string'));
});
for (const data of [{target: 'https://example.org'}, {target: 'library', fid: 'another'},
  {target: 'library', title: 'client text'}, {target: 'library', expectedUid: 'other'}]) {
  test(`Push test rejects arbitrary targets or client content ${JSON.stringify(data)}`, async () => {
    const f = fixture(); await f.service.register(f.registration());
    await assert.rejects(f.service.sendTest(f.request(data)), {code: 'invalid-argument'});
    assert.equal(f.sends.length, 0);
  });
}
test('Unregistered and deleting accounts cannot send', async () => {
  const f = fixture();
  await assert.rejects(f.service.sendTest(f.request({target: 'home'})), {code: 'failed-precondition'});
  await f.service.register(f.registration());
  f.records.set('account_deletions/user-1', {status: 'completed'});
  await assert.rejects(f.service.sendTest(f.request({target: 'home'})), {code: 'failed-precondition'});
  assert.equal(f.sends.length, 0);
});
test('Five tests per day and thirty-second cooldown are separate from AI quotas', async () => {
  const f = fixture(); await f.service.register(f.registration());
  await f.service.sendTest(f.request({target: 'home'}));
  await assert.rejects(f.service.sendTest(f.request({target: 'home'})), {code: 'resource-exhausted'});
  for (let i = 0; i < 4; i++) { f.advance(30001); await f.service.sendTest(f.request({target: 'home'})); }
  f.advance(30001);
  await assert.rejects(f.service.sendTest(f.request({target: 'home'})), {code: 'resource-exhausted'});
  assert.equal(f.sends.length, 5);
  assert.ok([...f.records.keys()].every(key => key.startsWith('users/user-1/notification')));
});
test('Provider failure is generic and does not refund the attempt counter', async () => {
  const f = fixture(); await f.service.register(f.registration());
  f.failSend(new Error('private provider detail'));
  await assert.rejects(f.service.sendTest(f.request({target: 'scan'})), error =>
    error.code === 'unavailable' && !error.message.includes('private provider detail'));
  assert.equal(f.records.get('users/user-1/notificationLimits/test').tests, 1);
});
test('An invalid old FID response does not remove a concurrently refreshed registration', async () => {
  const f = fixture(); await f.service.register(f.registration());
  f.beforeSend(() => f.records.set(f.device, {...f.records.get(f.device), fid: 'newerRegistrationFID123'}));
  f.failSend({code: 'messaging/registration-token-not-registered'});
  await assert.rejects(f.service.sendTest(f.request({target: 'home'})), {code: 'unavailable'});
  assert.equal(f.records.get(f.device).fid, 'newerRegistrationFID123');
});
test('Operator payload builder rejects unsafe target and oversized text', () => {
  const base = {uid: 'u', fid, id: 'n', title: 'Jiggo', body: 'Test', target: 'home', time: Date.now(), revision: 1};
  assert.throws(() => makeMessage({...base, target: 'javascript:alert(1)'}));
  assert.throws(() => makeMessage({...base, body: 'x'.repeat(501)}));
});

test('An invalid old send cannot delete a newer consent revision using the same FID', async () => {
  const f = fixture(); await f.service.register(f.registration());
  f.beforeSend(() => f.records.set(f.device, {...f.records.get(f.device), revision: 3}));
  f.failSend({code: 'messaging/registration-token-not-registered'});
  await assert.rejects(f.service.sendTest(f.request({target: 'home'})), {code: 'unavailable'});
  assert.equal(f.records.get(f.device).revision, 3);
});
