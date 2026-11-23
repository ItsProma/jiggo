// Emulator only. Refuse to run against any remote/production Firestore host.
const { test, before, beforeEach, after } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createRequire } = require('node:module');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');
const { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, deleteField, Timestamp, setLogLevel } = require('firebase/firestore');
setLogLevel('silent');
const endpoint = process.env.FIRESTORE_EMULATOR_HOST;
assert.ok(endpoint && /^(127\.0\.0\.1|localhost):\d+$/.test(endpoint),
  'Start the Firestore emulator first. Remote/production hosts are never allowed.');
const [host, port] = endpoint.split(':');
let env;
let adminDb;
const documentPath = 'users/alice/documents/doc-1';
const scanPath = 'users/alice/scanHistory/scan-1';
const userDb = (uid = 'alice') => env.authenticatedContext(uid, {firebase: {sign_in_provider: 'google.com'}}).firestore();
const seed = (key, data) => env.withSecurityRulesDisabled(async (context) => {
  await setDoc(doc(context.firestore(), key), data);
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'jiggo-bee33',
    firestore: { host, port: Number(port), rules: fs.readFileSync(path.join(__dirname, '../firestore.rules'), 'utf8') },
  });
});
beforeEach(async () => {
  await env.clearFirestore();
  await seed(documentPath, { title: 'My document', content: 'Original content',
    language: 'English', documentType: 'Formal Letter', createdAt: Timestamp.fromMillis(1000) });
  await seed(scanPath, { answer: 'Original answer', language: 'Bangla', createdAt: Timestamp.fromMillis(1000) });
});
after(async () => {
  if (env) await env.cleanup();
  if (adminDb) await adminDb.terminate();
});

test('Messaging IDs and notification quotas are server-only even for their owner', async () => {
  const paths = ['users/alice/notificationDevices/device-1', 'users/alice/notificationLimits/test'];
  for (const key of paths) {
    await seed(key, {fid: 'private-installation-id', enabled: true, revision: 1});
    for (const uid of ['alice', 'bob']) {
      const ref = doc(userDb(uid), key);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref, {enabled: true}));
      await assertFails(updateDoc(ref, {revision: 99}));
      await assertFails(deleteDoc(ref));
    }
  }
});

function realNotificationBackend() {
  serverContext();
  const load = createRequire(path.join(__dirname, '../functions/package.json'));
  class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
  return require('../functions/notification_backend.cjs').createNotificationBackend({
    db: adminDb, HttpsError, serverTimestamp: () => load('firebase-admin/firestore').FieldValue.serverTimestamp(),
    messaging: {send() { throw new Error('Live delivery is never allowed in emulator tests'); }},
  });
}

test('Real notification transactions cannot replay registration after concurrent opt-out', async () => {
  const service = realNotificationBackend();
  const id = '11111111-1111-4111-8111-111111111111';
  const request = extra => ({auth: {uid:'notification-user'}, app: {appId:'verified-test'},
    data: {expectedUid:'notification-user', installationId:id, ...extra}});
  await Promise.allSettled([
    service.register(request({fid:'cExampleInstallation12', language:'bn', platform:'android', revision:1})),
    service.unregister(request({revision:2})),
  ]);
  const final = (await adminDb.doc(`users/notification-user/notificationDevices/${id}`).get()).data();
  assert.equal(final.enabled, false);
  assert.equal(final.revision, 2);
  assert.equal(final.fid, undefined);
});

test('Real notification registration cannot recreate data after account deletion', async () => {
  const service = realNotificationBackend();
  await adminDb.doc('account_deletions/notification-user').set({status:'completed'});
  await assert.rejects(service.register({auth:{uid:'notification-user'}, app:{appId:'verified-test'},
    data: {expectedUid:'notification-user', installationId:'11111111-1111-4111-8111-111111111111',
      fid:'cExampleInstallation12', language:'bn', platform:'android', revision:1}}), {code:'failed-precondition'});
  assert.equal((await adminDb.collection('users/notification-user/notificationDevices').get()).size,0);
});

test('Owner reads its document and scan', async () => {
  await assertSucceeds(getDoc(doc(userDb(), documentPath)));
  await assertSucceeds(getDoc(doc(userDb(), scanPath)));
});
test('Owner lists its documents and scans', async () => {
  await assertSucceeds(getDocs(collection(userDb(), 'users/alice/documents')));
  await assertSucceeds(getDocs(collection(userDb(), 'users/alice/scanHistory')));
});
test('Guest cannot access even an old anonymous-owned document', async () => {
  const guest = env.authenticatedContext('alice', { firebase: { sign_in_provider: 'anonymous' } }).firestore();
  await assertFails(getDoc(doc(guest, documentPath)));
  await assertFails(deleteDoc(doc(guest, scanPath)));
});
test('Another account cannot read or list owner data', async () => {
  for (const target of [documentPath, scanPath]) await assertFails(getDoc(doc(userDb('bob'), target)));
  for (const target of ['users/alice/documents', 'users/alice/scanHistory']) {
    await assertFails(getDocs(collection(userDb('bob'), target)));
  }
});
test('Unauthenticated access is denied', async () => {
  const db = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, documentPath)));
  await assertFails(updateDoc(doc(db, documentPath), { title: 'New title' }));
  await assertFails(deleteDoc(doc(db, scanPath)));
});
test('Direct document create remains blocked', async () => {
  await assertFails(setDoc(doc(userDb(), 'users/alice/documents/new'), { title: 'New', content: 'Text' }));
});
test('Direct scan create remains blocked', async () => {
  await assertFails(setDoc(doc(userDb(), 'users/alice/scanHistory/new'), { answer: 'Answer' }));
});
test('Document title and content edits remain authorized', async () => {
  await assertSucceeds(updateDoc(doc(userDb(), documentPath), { title: 'আমার ডকুমেন্ট', content: '**Saved text**' }));
});
test('Empty document content remains editable and saveable', async () => {
  await assertSucceeds(updateDoc(doc(userDb(), documentPath), { content: '' }));
});
test('Owner can add a title to a legacy scan without modifying its answer', async () => {
  await assertSucceeds(updateDoc(doc(userDb(), scanPath), { title: 'আমার গণিত' }));
  assert.equal((await getDoc(doc(userDb(), scanPath))).data().answer, 'Original answer');
});
test('Blank, whitespace, oversized and non-string titles are denied', async () => {
  for (const title of ['', '   ', 'x'.repeat(151), 123, null]) {
    await assertFails(updateDoc(doc(userDb(), documentPath), { title }));
    await assertFails(updateDoc(doc(userDb(), scanPath), { title }));
  }
});
test('Non-string and oversized content is denied', async () => {
  for (const content of [null, 123, 'x'.repeat(200001)]) {
    await assertFails(updateDoc(doc(userDb(), documentPath), { content }));
  }
});
test('Required editable fields cannot be removed', async () => {
  await assertFails(updateDoc(doc(userDb(), documentPath), { title: deleteField() }));
  await assertFails(updateDoc(doc(userDb(), documentPath), { content: deleteField() }));
});
test('Document metadata and arbitrary extra fields remain immutable', async () => {
  for (const data of [{ language: 'Bangla' }, { documentType: 'Invoice' },
    { createdAt: Timestamp.fromMillis(2000) }, { ownerId: 'bob' }]) {
    await assertFails(updateDoc(doc(userDb(), documentPath), data));
  }
});
test('Scan answer and metadata cannot be edited directly', async () => {
  for (const data of [{ answer: 'Forged answer' }, { language: 'English' },
    { createdAt: Timestamp.fromMillis(2000) }, { extra: true }]) {
    await assertFails(updateDoc(doc(userDb(), scanPath), data));
  }
});
test('Another account cannot rename or delete owner records', async () => {
  await assertFails(updateDoc(doc(userDb('bob'), documentPath), { title: 'Stolen' }));
  await assertFails(deleteDoc(doc(userDb('bob'), documentPath)));
  await assertFails(updateDoc(doc(userDb('bob'), scanPath), { title: 'Stolen' }));
  await assertFails(deleteDoc(doc(userDb('bob'), scanPath)));
});
test('Owner can delete documents and scans', async () => {
  await assertSucceeds(deleteDoc(doc(userDb(), documentPath)));
  await assertSucceeds(deleteDoc(doc(userDb(), scanPath)));
});
test('Private usage, limits, config and deletion records reject all client access', async () => {
  for (const key of ['ai_usage/alice_2026-11-13', 'document_usage/alice_2026-11-13',
    'ai_attempts/alice_2026-11-13', 'ai_request_limits/alice', 'ai_budget/2026-11-13',
    'ai_budget/2026-11-13/calls/request-1', 'ai_config/control', 'account_deletions/alice']) {
    await seed(key, { count: 1 });
    await assertFails(getDoc(doc(userDb(), key)));
    await assertFails(setDoc(doc(userDb(), key), { count: 0 }));
    await assertFails(deleteDoc(doc(userDb(), key)));
  }
});
test('Deletion marker blocks owner reads and writes without blocking another owner', async () => {
  await seed('account_deletions/alice', { status: 'deleting' });
  await assertFails(getDoc(doc(userDb(), documentPath)));
  await assertFails(updateDoc(doc(userDb(), documentPath), { title: 'Late edit' }));
  await assertFails(deleteDoc(doc(userDb(), scanPath)));
  await seed('users/bob/documents/b', { title: 'Bob', content: 'Text' });
  await assertSucceeds(getDoc(doc(userDb('bob'), 'users/bob/documents/b')));
});
test('Server test seeding can still create records for later owner reads', async () => {
  await seed('users/alice/documents/server-created', { title: 'Generated', content: 'Text' });
  await assertSucceeds(getDoc(doc(userDb(), 'users/alice/documents/server-created')));
});


// Use the project's real Admin Firestore SDK, but stub AI and callable HTTP
// wiring. These checks exercise actual emulator transaction conflict/retry behavior.
function serverContext() {
  const load = createRequire(path.join(__dirname, '../functions/package.json'));
  const adminApp = load('firebase-admin/app');
  const firestore = load('firebase-admin/firestore');
  if (!adminDb) {
    const app = adminApp.initializeApp({ projectId: 'jiggo-bee33' }, 'phase5-emulator-tests');
    adminDb = firestore.getFirestore(app);
  }
  class HttpsError extends Error {
    constructor(code, message, details) { super(message); this.code = code; this.details = details; }
  }
  const mock = {
    'firebase-functions/v2/https': { HttpsError, onCall: (_, handler) => handler },
    'node:crypto': require('node:crypto'),
    'firebase-functions/params': { defineSecret: () => ({ value: () => { throw new Error('AI must never run in these tests'); } }) },
    './luna_ai.cjs': { SafeLunaClient: class { constructor() { throw new Error('No live AI calls allowed'); } } },
    'firebase-admin/app': { initializeApp() {} },
    'firebase-admin/firestore': {
      getFirestore: () => new Proxy(adminDb, {
        get(target, property) {
          // Bridge VM-realm Promises for the SDK's native instanceof check.
          if (property === 'runTransaction') {
            return (callback) => target.runTransaction(async (transaction) => callback(transaction));
          }
          const value = Reflect.get(target, property, target);
          return typeof value === 'function' ? value.bind(target) : value;
        },
      }),
      FieldValue: firestore.FieldValue,
    },
  };
  const context = { exports: {}, Buffer, Date, console, require: (name) => {
    assert.ok(Object.hasOwn(mock, name), `Unexpected production dependency: ${name}`);
    return mock[name];
  } };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../functions/index.js'), 'utf8'), context);
  return context;
}

test('Real Firestore transactions admit at most two overlapping reservations per UID', async () => {
  const server = serverContext();
  const date = '2026-11-13';
  await adminDb.doc('users/guard-user/settings/aiEligibility').set({ version: 1, ageBand: '18-plus', privacyAccepted: true });
  const results = await Promise.allSettled(Array.from({ length: 8 }, (_, i) =>
    server.reserveDailyScan('guard-user', date, `concurrent-${i}`)));
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 2);
  for (const result of results.filter((value) => value.status === 'rejected')) {
    assert.equal(result.reason.code, 'resource-exhausted');
  }
  assert.equal((await adminDb.doc(`ai_usage/guard-user_${date}`).get()).data().count, 2);
  assert.equal((await adminDb.doc(`ai_budget/${date}`).get()).data().attempts, 2);
});

test('Real shared-budget transaction caps parallel requests from distinct UIDs', async () => {
  const server = serverContext();
  const date = '2026-11-13';
  await adminDb.doc('ai_config/control').set({ globalDailyAttempts: 3 });
  await Promise.all(Array.from({ length: 8 }, (_, i) => adminDb.doc(`users/guard-user-${i}/settings/aiEligibility`).set({ version: 1, ageBand: '18-plus', privacyAccepted: true })));
  const results = await Promise.allSettled(Array.from({ length: 8 }, (_, i) =>
    server.reserveDailyScan(`guard-user-${i}`, date, `global-${i}`)));
  assert.equal(results.filter((result) => result.status === 'fulfilled').length, 3);
  assert.equal((await adminDb.doc(`ai_budget/${date}`).get()).data().attempts, 3);
});

test('Real completion fence blocks post-deletion content and preserves anonymous usage accounting', async () => {
  const server = serverContext();
  const date = '2026-11-13';
  const uid = 'guard-user';
  await adminDb.doc('users/guard-user/settings/aiEligibility').set({ version: 1, ageBand: '18-plus', privacyAccepted: true });
  await server.reserveDailyScan(uid, date, 'late-request');
  await adminDb.doc(`account_deletions/${uid}`).set({ status: 'completed' });
  await adminDb.recursiveDelete(adminDb.doc(`users/${uid}`));
  await adminDb.recursiveDelete(adminDb.doc(`ai_attempts/${uid}_${date}`));
  await adminDb.recursiveDelete(adminDb.doc(`ai_request_limits/${uid}`));
  await assert.rejects(server.completeDailyScan(uid, date, 'late-request', 'Answer', 'English'),
    { code: 'failed-precondition' });
  await server.finishAiGuard(uid, date, 'late-request', { totalTokenCount: 50 }, 'answer');
  assert.equal((await adminDb.doc(`users/${uid}/scanHistory/late-request`).get()).exists, false);
  assert.equal((await adminDb.doc(`ai_attempts/${uid}_${date}`).get()).exists, false);
  assert.equal((await adminDb.doc(`ai_request_limits/${uid}`).get()).exists, false);
  assert.equal((await adminDb.doc(`ai_budget/${date}`).get()).data().reportedTotalTokens, 50);
});

test('AI reports and report quotas cannot be read or modified directly by any client', async () => {
  const targets = ['users/alice/aiReports/report-1', 'ai_report_usage/alice_2026-11-13'];
  for (const target of targets) {
    await seed(target, { content: 'Private report', count: 1 });
    for (const db of [userDb(), userDb('bob'), env.unauthenticatedContext().firestore()]) {
      await assertFails(getDoc(doc(db, target)));
      await assertFails(setDoc(doc(db, target), { count: 0 }));
      await assertFails(deleteDoc(doc(db, target)));
    }
  }
});

test('Age declarations are private and clients cannot bypass eligibility with direct writes', async () => {
  const key = 'users/alice/settings/aiEligibility';
  await seed(key, { ageBand: 'under-13', privacyAccepted: true, version: 1 });
  for (const db of [userDb(), userDb('bob')]) {
    await assertFails(getDoc(doc(db, key)));
    await assertFails(setDoc(doc(db, key), { ageBand: '18-plus', privacyAccepted: true, version: 1 }));
    await assertFails(deleteDoc(doc(db, key)));
  }
});

test('Real reservation transaction rejects unconfirmed and under-13 accounts without usage writes', async () => {
  const server = serverContext();
  const date = '2026-11-14';
  for (const profile of [null, { version: 1, ageBand: 'under-13', privacyAccepted: true }]) {
    if (profile) await adminDb.doc('users/age-test/settings/aiEligibility').set(profile);
    await assert.rejects(server.reserveDailyScan('age-test', date, 'blocked'), { code: 'failed-precondition' });
    assert.equal((await adminDb.doc(`ai_usage/age-test_${date}`).get()).exists, false);
  }
});

test('Concurrent age declarations cannot overwrite a committed age band', async () => {
  const server = serverContext();
  const makeRequest = (ageBand) => ({ auth: { uid: 'age-race', token: {firebase: {sign_in_provider: 'google.com'}} }, data: {
    expectedUid: 'age-race', ageBand, guardianPermission: false, privacyAccepted: true, version: 1 } });
  const results = await Promise.allSettled(['under-13', '18-plus'].map((band) => server.exports.setAiEligibility(makeRequest(band))));
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  assert.equal(results.filter((r) => r.status === 'rejected').length, 1);
});

test('Email accounts require verification and cannot read another owner', async () => {
  const unverified = env.authenticatedContext('alice', {firebase: {sign_in_provider: 'password'}, email_verified: false}).firestore();
  const verified = env.authenticatedContext('alice', {firebase: {sign_in_provider: 'password'}, email_verified: true}).firestore();
  await assertFails(getDoc(doc(unverified, documentPath)));
  await assertSucceeds(getDoc(doc(verified, documentPath)));
  await assertFails(getDoc(doc(verified, 'users/bob/documents/other')));
});
