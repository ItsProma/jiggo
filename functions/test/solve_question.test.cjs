// Offline contract/workflow tests. No API credentials, deployments or AI costs.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 1]);
const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const webp = Buffer.from('RIFF0000WEBP');

function fixture({ aiError = false, text = '## Steps\nSolution\nFINAL_ANSWER: 4', historyFailures = 0, usageMetadata, advanceMs = 61000, beforeResponse, eligibility = true } = {}) {
  const records = new Map();
  let fakeNow = Date.parse(new Date().toISOString().slice(0, 10) + 'T12:00:00Z');
  class ClockDate extends Date {
    constructor(...args) { super(...(args.length ? args : [fakeNow])); }
    static now() { return fakeNow; }
  }
  const calls = [];
  let nextId = 0;
  let remainingFailures = historyFailures;
  let historyAttempts = 0;
  const ref = (key) => ({
    key,
    collection: (name) => ({ doc: (id) => ref(`${key}/${name}/${id}`) }),
  });
  const db = {
    collection: (name) => ({ doc: (id) => ref(`${name}/${id}`) }),
    // This fake models atomic commits/rollback, not emulator concurrency.
    async runTransaction(callback) {
      const writes = [];
      const result = await callback({
        get: async (r) => {
          const baseline = eligibility && /users\/[^/]+\/settings\/aiEligibility$/.test(r.key)
            ? { ageBand: '18-plus', privacyAccepted: true, guardianPermission: false, version: 1 } : undefined;
          const value = records.has(r.key) ? records.get(r.key) : baseline;
          return { exists: value !== undefined, data: () => value };
        },
        set: (r, data, options) => writes.push({ r, data, merge: options?.merge }),
        update: (r, data) => {
          if (!records.has(r.key)) throw new Error('Missing document');
          writes.push({ r, data, merge: true });
        },
      });
      if (writes.some(({ r }) => r.key.includes('/scanHistory/'))) {
        historyAttempts++;
        if (remainingFailures-- > 0) throw new Error('Firestore temporarily unavailable');
      }
      for (const { r, data, merge } of writes) {
        records.set(r.key, merge ? { ...records.get(r.key), ...data } : data);
      }
      return result;
    },
  };
  class HttpsError extends Error {
    constructor(code, message, details) { super(message); this.code = code; this.details = details; }
  }
  class SafeLunaClient {
    constructor() {
      this.generate = async (input) => {
        calls.push(input);
        fakeNow += advanceMs;
        if (beforeResponse) await beforeResponse();
        if (aiError) throw aiError === true ? new Error('Provider unavailable') : aiError;
        return { text, usageMetadata };
      };
    }
  }
  const mocks = {
    'firebase-functions/v2/https': { onCall: (options, handler) => Object.assign(request => { if (request.auth && !Object.hasOwn(request.auth, 'token')) request = {...request, auth: {...request.auth, token: {firebase: {sign_in_provider: 'google.com'}}}}; return handler(request); }, {options}), HttpsError },
    'node:crypto': { randomUUID: () => `request-${++nextId}` },
    'firebase-functions/params': { defineSecret: (name) => ({ name, value: () => 'offline-test-secret' }) },
    './luna_ai.cjs': { SafeLunaClient },
    'firebase-admin/app': { initializeApp() {} },
    'firebase-admin/firestore': { getFirestore: () => db, FieldValue: { serverTimestamp: () => 'SERVER_TIMESTAMP' } },
  };
  const context = {
    exports: {}, Buffer, Date: ClockDate, console: { log() {}, error() {} },
    require(name) { assert.ok(Object.hasOwn(mocks, name), `Unexpected dependency: ${name}`); return mocks[name]; },
  };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8'), context);
  return {
    ...context.exports, records, calls, context,
    historyAttempts: () => historyAttempts,
    now: () => fakeNow,
    advanceTime: (ms) => { fakeNow += ms; },
    request: (data = {}, uid = 'student-1') => ({
      auth: uid ? { uid } : null,
      data: { imageBase64: jpeg.toString('base64'), mimeType: 'image/jpeg', language: 'bn', ...data },
    }),
  };
}

function usage(f) { return [...f.records.entries()].find(([key]) => /^ai_usage\/[^/]+$/.test(key))?.[1]; }
function history(f) { return [...f.records.entries()].filter(([key]) => key.includes('/scanHistory/')); }

test('Bangla solve saves answer and completes usage atomically', async () => {
  const f = fixture();
  const response = await f.solveQuestion(f.request());
  assert.equal(response.historySaved, true);
  assert.equal(response.remainingToday, 9);
  assert.equal(history(f).length, 1);
  assert.equal(history(f)[0][0], `users/student-1/scanHistory/${response.scanId}`);
  assert.equal(history(f)[0][1].answer, response.answer);
  assert.equal(history(f)[0][1].language, 'Bangla');
  assert.equal(usage(f).count, 1);
  assert.match(f.calls[0].instructions, /step by step in Bangla/);
});

test('English explanation is sent to Luna and stored as English', async () => {
  const f = fixture();
  const result = await f.solveQuestion(f.request({ language: 'en' }));
  assert.equal(result.language, 'English');
  assert.match(f.calls[0].instructions, /step by step in English/);
});

test('Authentication is required before Luna or Firestore', async () => {
  const f = fixture();
  await assert.rejects(f.solveQuestion(f.request({}, null)), { code: 'unauthenticated' });
  assert.equal(f.calls.length, 0);
  assert.equal(f.records.size, 0);
});

for (const [name, data] of [
  ['empty image', { imageBase64: '' }],
  ['invalid base64', { imageBase64: '$$$' }],
  ['unsupported MIME', { mimeType: 'image/gif' }],
  ['false MIME', { mimeType: 'image/png' }],
  ['non-image bytes', { imageBase64: Buffer.from('hello').toString('base64') }],
  ['unsupported language', { language: 'xx' }],
  ['oversized image', { imageBase64: Buffer.alloc(2 * 1024 * 1024 + 1).toString('base64') }],
]) test(`Rejects ${name} without AI cost or quota charge`, async () => {
  const f = fixture();
  await assert.rejects(f.solveQuestion(f.request(data)), { code: 'invalid-argument' });
  assert.equal(f.calls.length, 0);
  assert.equal(f.records.size, 0);
});

for (const [mimeType, bytes] of [['image/png', png], ['image/webp', webp]]) {
  test(`Accepts ${mimeType} signature`, async () => {
    const f = fixture();
    await f.solveQuestion(f.request({ mimeType, imageBase64: bytes.toString('base64') }));
    assert.equal(f.calls[0].mimeType, mimeType);
  });
}

test('11th daily scan is rejected before calling Luna', async () => {
  const f = fixture();
  for (let i = 0; i < 10; i++) await f.solveQuestion(f.request());
  await assert.rejects(f.solveQuestion(f.request()), { code: 'resource-exhausted' });
  assert.equal(f.calls.length, 10);
  assert.equal(usage(f).count, 10);
});

test('Quota belongs to the authenticated user', async () => {
  const f = fixture();
  for (let i = 0; i < 10; i++) await f.solveQuestion(f.request());
  const response = await f.solveQuestion(f.request({}, 'student-2'));
  assert.equal(response.remainingToday, 9);
  assert.ok(history(f).some(([key]) => key.startsWith('users/student-2/')));
});

for (const [name, options] of [['provider error', { aiError: true }], ['empty response', { text: '  ' }]]) {
  test(`${name} refunds quota and creates no history`, async () => {
    const f = fixture(options);
    await assert.rejects(f.solveQuestion(f.request()), { code: 'internal' });
    assert.equal(usage(f).count, 0);
    assert.equal(history(f).length, 0);
    const requestRecord = [...f.records.entries()].find(([key]) => key.startsWith('ai_usage/') && key.includes('/requests/'))[1];
    assert.equal(requestRecord.status, 'refunded');
  });
}

test('Transient history failure retries without extra Luna calls or duplicate history', async () => {
  const f = fixture({ historyFailures: 1 });
  const result = await f.solveQuestion(f.request());
  assert.equal(result.historySaved, true);
  assert.equal(f.historyAttempts(), 2);
  assert.equal(f.calls.length, 1);
  assert.equal(history(f).length, 1);
  assert.equal(usage(f).count, 1);
});

test('Persistent history failure returns answer and explicit unsaved status, retaining quota', async () => {
  const f = fixture({ historyFailures: 3 });
  const result = await f.solveQuestion(f.request());
  assert.ok(result.answer);
  assert.equal(result.historySaved, false);
  assert.equal(f.historyAttempts(), 3);
  assert.equal(history(f).length, 0);
  assert.equal(usage(f).count, 1);
  assert.equal([...f.records.entries()].find(([key]) => key.startsWith('ai_usage/') && key.includes('/requests/'))[1].status, 'reserved');
});

test('Completion retry is idempotent and preserves the original history timestamp', async () => {
  const f = fixture();
  const result = await f.solveQuestion(f.request());
  const date = usage(f).date;
  await f.context.completeDailyScan('student-1', date, result.scanId, 'replacement', 'English');
  assert.equal(history(f).length, 1);
  assert.equal(history(f)[0][1].answer, result.answer);
});

test('App Check, secret binding and existing scan resource caps remain configured', () => {
  const f = fixture();
  assert.equal(f.solveQuestion.options.enforceAppCheck, true);
  assert.equal(f.solveQuestion.options.maxInstances, 2);
  assert.equal(f.solveQuestion.options.timeoutSeconds, 60);
  assert.equal(f.solveQuestion.options.secrets.length, 1);
});

// Account-deletion mocks model scoped recursive deletes and atomic transactions.
// They do not exercise live IAM, App Check or Firestore concurrency.
function accountFixture({ guest = false, failDeleteKey = null, failAuthDelete = false } = {}) {
  const records = new Map();
  const users = new Map([['owner', { uid: 'owner', providerData: guest ? [] : [{ providerId: 'google.com' }] }]]);
  const deleted = [];
  let failKey = failDeleteKey;
  let authFails = failAuthDelete;
  let nextId = 0;
  const ref = (key) => ({
    key, id: key.split('/').at(-1),
    collection: (name) => query(`${key}/${name}`),
    set: async (data) => records.set(key, data),
  });
  function query(name, options = {}) {
    return {
      doc: (id) => ref(`${name}/${id}`),
      where: (_, op, value) => query(name, { ...options, [op]: value }),
      orderBy: () => query(name, options),
      limit: (limit) => query(name, { ...options, limit }),
      startAfter: (snapshot) => query(name, { ...options, cursor: snapshot.id }),
      get: async () => {
        const docs = [...records.keys()]
          .filter((key) => key.startsWith(`${name}/`) && !key.slice(name.length + 1).includes('/'))
          .map((key) => ({ id: key.slice(name.length + 1), ref: ref(key) }))
          .filter((doc) => (!options['>='] || doc.id >= options['>=']) &&
            (!options['<='] || doc.id <= options['<=']) && (!options.cursor || doc.id > options.cursor))
          .sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0)
          .slice(0, options.limit ?? Infinity);
        return { docs, size: docs.length, empty: docs.length === 0 };
      },
    };
  }
  const db = {
    collection: (name) => query(name),
    async runTransaction(callback) {
      const writes = [];
      const value = await callback({
        get: async (r) => ({ exists: records.has(r.key), data: () => records.get(r.key) }),
        set: (r, data) => writes.push([r.key, data]),
        update: (r, data) => {
          assert.ok(records.has(r.key));
          writes.push([r.key, { ...records.get(r.key), ...data }]);
        },
      });
      for (const [key, data] of writes) records.set(key, data);
      return value;
    },
    async recursiveDelete(r) {
      if (r.key === failKey) { failKey = null; throw new Error('Offline deletion test'); }
      deleted.push(r.key);
      for (const key of [...records.keys()]) {
        if (key === r.key || key.startsWith(`${r.key}/`)) records.delete(key);
      }
    },
  };
  class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
  const mocks = {
    'firebase-functions/v2/https': { onCall: (options, handler) => Object.assign(request => { if (request.auth && !Object.hasOwn(request.auth, 'token')) request = {...request, auth: {...request.auth, token: {firebase: {sign_in_provider: 'google.com'}}}}; return handler(request); }, {options}), HttpsError },
    'node:crypto': { randomUUID: () => `job-${++nextId}` },
    'firebase-functions/params': { defineSecret: (name) => ({ name, value: () => 'offline-test-secret' }) },
    './luna_ai.cjs': { SafeLunaClient: class {} },
    'firebase-admin/app': { initializeApp() {} },
    'firebase-admin/firestore': {
      getFirestore: () => db,
      FieldValue: { serverTimestamp: () => 'SERVER_TIMESTAMP' },
      FieldPath: { documentId: () => '__name__' },
    },
    'firebase-admin/auth': { getAuth: () => ({
      getUser: async (uid) => {
        if (!users.has(uid)) { const e = new Error('Missing user'); e.code = 'auth/user-not-found'; throw e; }
        return users.get(uid);
      },
      deleteUser: async (uid) => {
        if (authFails) { authFails = false; throw new Error('Auth temporarily unavailable'); }
        users.delete(uid);
      },
    }) },
  };
  const context = { exports: {}, Buffer, console: { log() {}, error() {} }, require: (name) => {
    assert.ok(Object.hasOwn(mocks, name), name); return mocks[name];
  } };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8'), context);
  const request = () => ({
    auth: { uid: 'owner', token: {
      auth_time: Math.floor(Date.now() / 1000),
      firebase: { sign_in_provider: guest ? 'anonymous' : 'google.com' },
    } },
    data: { confirm: true, expectedUid: 'owner' },
  });
  return { ...context.exports, records, users, deleted, request };
}

test('Account deletion requires authentication', async () => {
  const f = accountFixture();
  await assert.rejects(f.deleteMyAccount({ data: { confirm: true } }), { code: 'unauthenticated' });
  assert.equal(f.records.size, 0);
});

test('Deletion requires explicit confirmation and matching expected account', async () => {
  const f = accountFixture();
  for (const data of [{}, { confirm: true, expectedUid: 'other' }, { confirm: true, expectedUid: 'owner', uid: 'other' }]) {
    await assert.rejects(f.deleteMyAccount({ ...f.request(), data }), { code: 'invalid-argument' });
  }
  assert.equal(f.records.size, 0);
});

test('Google deletion rejects a stale authentication time', async () => {
  const f = accountFixture(); const r = f.request(); r.auth.token.auth_time -= 301;
  await assert.rejects(f.deleteMyAccount(r), { code: 'failed-precondition' });
  assert.ok(f.users.has('owner'));
});

test('Old anonymous token cannot bypass recent login after Google linking', async () => {
  const f = accountFixture(); const r = f.request();
  r.auth.token.firebase.sign_in_provider = 'anonymous'; r.auth.token.auth_time -= 301;
  await assert.rejects(f.deleteMyAccount(r), { code: 'failed-precondition' });
});

test('Guest can delete its account without Google credentials', async () => {
  const f = accountFixture({ guest: true }); const r = f.request(); r.auth.token.auth_time -= 86400;
  const result = await f.deleteMyAccount(r);
  assert.equal(result.deleted, true);
  assert.equal(f.users.has('owner'), false);
});

test('Deletion removes owner content and nested usage without touching another UID', async () => {
  const f = accountFixture();
  for (const key of [
    'users/owner/documents/a', 'users/owner/scanHistory/b',
    'ai_usage/owner_2026-11-13', 'ai_usage/owner_2026-11-13/requests/r',
    'document_usage/owner_2026-11-13', 'document_usage/owner_2026-11-13/requests/r',
    'users/other/documents/c', 'ai_usage/owner_extra_2026-11-13',
    'document_usage/owner_extra_2026-11-13',
  ]) f.records.set(key, {});
  const result = await f.deleteMyAccount(f.request());
  assert.equal(result.deleted, true);
  assert.equal(f.records.has('users/owner/documents/a'), false);
  assert.equal(f.records.has('ai_usage/owner_2026-11-13/requests/r'), false);
  assert.equal(f.records.has('document_usage/owner_2026-11-13'), false);
  assert.ok(f.records.has('users/other/documents/c'));
  assert.ok(f.records.has('ai_usage/owner_extra_2026-11-13'));
  assert.ok(f.records.has('document_usage/owner_extra_2026-11-13'));
  assert.equal(f.records.get('account_deletions/owner').status, 'completed');
});

test('Usage cleanup paginates beyond 100 records', async () => {
  const f = accountFixture();
  for (let i = 0; i < 130; i++) {
    const date = new Date(Date.UTC(2025, 0, i + 1)).toISOString().slice(0, 10);
    f.records.set(`document_usage/owner_${date}`, {});
  }
  await f.deleteMyAccount(f.request());
  assert.equal([...f.records.keys()].some((key) => key.startsWith('document_usage/owner_')), false);
});

test('Cleanup failure keeps Auth and a failed marker so retry can finish', async () => {
  const f = accountFixture({ failDeleteKey: 'users/owner' });
  f.records.set('users/owner/documents/a', {});
  await assert.rejects(f.deleteMyAccount(f.request()), { code: 'internal' });
  assert.ok(f.users.has('owner'));
  assert.equal(f.records.get('account_deletions/owner').status, 'failed');
  assert.equal((await f.deleteMyAccount(f.request())).deleted, true);
});

test('Auth deletion failure can be retried after data cleanup', async () => {
  const f = accountFixture({ failAuthDelete: true });
  f.records.set('users/owner/documents/a', {});
  await assert.rejects(f.deleteMyAccount(f.request()), { code: 'internal' });
  assert.equal(f.records.has('users/owner/documents/a'), false);
  assert.ok(f.users.has('owner'));
  assert.equal((await f.deleteMyAccount(f.request())).deleted, true);
});

test('Repeated deletion of a completed account is idempotent', async () => {
  const f = accountFixture(); const r = f.request();
  await f.deleteMyAccount(r);
  const count = f.deleted.length;
  assert.equal((await f.deleteMyAccount(r)).deleted, true);
  assert.equal(f.deleted.length, count);
});

test('Concurrent deletion is rejected while a lease is active', async () => {
  const f = accountFixture();
  f.records.set('account_deletions/owner', { status: 'deleting', leaseUntil: Date.now() + 60000 });
  await assert.rejects(f.deleteMyAccount(f.request()), { code: 'already-exists' });
  assert.equal(f.deleted.length, 0);
});

test('Deletion callable enforces App Check and does not bind a Luna secret', () => {
  const f = accountFixture();
  assert.equal(f.deleteMyAccount.options.enforceAppCheck, true);
  assert.equal(f.deleteMyAccount.options.secrets, undefined);
});

test('Deletion marker blocks scan reservation before Luna cost', async () => {
  const f = fixture(); f.records.set('account_deletions/student-1', { status: 'failed' });
  await assert.rejects(f.solveQuestion(f.request()), { code: 'failed-precondition' });
  assert.equal(f.calls.length, 0);
});

test('Deletion marker blocks document reservation before Luna cost', async () => {
  const f = fixture(); f.records.set('account_deletions/student-1', { status: 'deleting' });
  await assert.rejects(f.generateDocument({ auth: { uid: 'student-1' }, data: {
    title: 'My Letter', instructions: 'Write a short letter please.', documentType: 'Formal Letter', language: 'English',
  } }), { code: 'failed-precondition' });
  assert.equal(f.calls.length, 0);
});

test('In-flight scan cannot save history after deletion begins', async () => {
  const f = fixture();
  f.records.set('account_deletions/student-1', { status: 'deleting' });
  await assert.rejects(
    f.context.completeDailyScan('student-1', '2026-11-13', 'late-scan', 'Answer', 'English'),
    { code: 'failed-precondition' },
  );
  assert.equal([...f.records.keys()].some((key) => key.includes('/scanHistory/')), false);
});

test('In-flight document cannot recreate content after deletion begins', async () => {
  const f = fixture();
  const db = f.context.require('firebase-admin/firestore').getFirestore();
  f.records.set('account_deletions/student-1', { status: 'completed' });
  const usageRef = db.collection('document_usage').doc('student-1_2026-11-13');
  await assert.rejects(f.context.saveGeneratedDocument({
    uid: 'student-1', usageRef, requestRef: usageRef.collection('requests').doc('late-doc'),
  }, db.collection('users').doc('student-1').collection('documents').doc('late-doc'), {
    title: 'Late document', content: 'Content',
  }), { code: 'failed-precondition' });
  assert.equal([...f.records.keys()].some((key) => key.includes('/documents/')), false);
});

function globalBudget(f) {
  return [...f.records.entries()].find(([key]) => /^ai_budget\/[^/]+$/.test(key))?.[1];
}
function attemptUsage(f) {
  return [...f.records.entries()].find(([key]) => /^ai_attempts\/[^/]+$/.test(key))?.[1];
}
function documentRequest(uid = 'student-1') {
  return { auth: { uid }, data: { title: 'My Letter', instructions: 'Write a short letter please.',
    documentType: 'Formal Letter', language: 'English' } };
}

test('Fourth request inside a 60-second window is rejected without another Luna call', async () => {
  const f = fixture({ advanceMs: 0 });
  for (let i = 0; i < 3; i++) await f.solveQuestion(f.request());
  await assert.rejects(f.solveQuestion(f.request()), (error) => {
    assert.equal(error.code, 'resource-exhausted');
    assert.equal(error.details.reason, 'rate-limit');
    return true;
  });
  assert.equal(f.calls.length, 3);
  f.advanceTime(60001);
  await f.solveQuestion(f.request());
  assert.equal(f.calls.length, 4);
});

test('Scan and document calls share one burst window', async () => {
  const f = fixture({ advanceMs: 0 });
  await f.solveQuestion(f.request());
  await f.generateDocument(documentRequest());
  await f.solveQuestion(f.request());
  await assert.rejects(f.generateDocument(documentRequest()), (error) => error.details.reason === 'rate-limit');
  assert.equal(f.calls.length, 3);
});

test('Third overlapping AI call is rejected and finishing calls release their slots', async () => {
  const release = [];
  const f = fixture({ advanceMs: 0, beforeResponse: () => new Promise((resolve) => release.push(resolve)) });
  const first = f.solveQuestion(f.request());
  while (f.calls.length < 1) await new Promise(setImmediate);
  const second = f.generateDocument(documentRequest());
  while (f.calls.length < 2) await new Promise(setImmediate);
  await assert.rejects(f.solveQuestion(f.request()), (error) => error.details.reason === 'concurrency-limit');
  release[0](); await first;
  release[1](); await second;
  assert.equal(Object.keys(f.records.get('ai_request_limits/student-1').active).length, 0);
});

test('Expired request leases do not permanently block a user', async () => {
  const f = fixture({ advanceMs: 0 });
  f.records.set('ai_request_limits/student-1', { active: { abandoned: f.now() - 1 } });
  await f.solveQuestion(f.request());
  assert.equal(Object.keys(f.records.get('ai_request_limits/student-1').active).length, 0);
});

test('Repeated provider failures retain attempt charges while refunding successful-use quota', async () => {
  const f = fixture({ aiError: true });
  for (let i = 0; i < 30; i++) await assert.rejects(f.solveQuestion(f.request()), { code: 'internal' });
  await assert.rejects(f.solveQuestion(f.request()), (error) => error.details.reason === 'daily-attempts');
  assert.equal(f.calls.length, 30);
  assert.equal(usage(f).count, 0);
  assert.equal(attemptUsage(f).count, 30);
  assert.equal(globalBudget(f).attempts, 30);
});

test('App-wide allowance is shared across users and document/scan endpoints', async () => {
  const f = fixture();
  f.records.set('ai_config/control', { globalDailyAttempts: 2 });
  await f.solveQuestion(f.request());
  await f.generateDocument(documentRequest('student-2'));
  await assert.rejects(f.solveQuestion(f.request({}, 'student-3')), (error) => error.details.reason === 'global-budget');
  assert.equal(f.calls.length, 2);
  assert.equal(globalBudget(f).attempts, 2);
});

test('Server-only pause switch blocks requests before user quota or AI cost', async () => {
  const f = fixture(); f.records.set('ai_config/control', { enabled: false });
  await assert.rejects(f.solveQuestion(f.request()), (error) => error.details.reason === 'ai-paused');
  assert.equal(f.calls.length, 0);
  assert.equal(usage(f), undefined);
});

test('Invalid budget configuration fails closed', async () => {
  const f = fixture(); f.records.set('ai_config/control', { globalDailyAttempts: 'unlimited' });
  await assert.rejects(f.solveQuestion(f.request()), { code: 'internal' });
  assert.equal(f.calls.length, 0);
});

test('Reported token metadata is tracked without recording prompts or images', async () => {
  const f = fixture({ usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 40,
    thoughtsTokenCount: 10, totalTokenCount: 150 } });
  const result = await f.solveQuestion(f.request());
  const budget = globalBudget(f);
  assert.equal(budget.reportedInputTokens, 100);
  assert.equal(budget.reportedOutputTokens, 40);
  assert.equal(budget.reportedThinkingTokens, 10);
  assert.equal(budget.reportedTotalTokens, 150);
  assert.equal(budget.unknownUsageRequests, 0);
  const ledger = [...f.records.entries()].find(([key]) => key.endsWith(`/calls/${result.scanId}`))[1];
  assert.equal(ledger.status, 'finalized');
  for (const field of ['uid', 'answer', 'imageBase64', 'instructions', 'title']) {
    assert.equal(Object.hasOwn(ledger, field), false);
  }
});

test('Missing metadata is marked unknown rather than claimed as zero cost', async () => {
  const f = fixture(); await f.solveQuestion(f.request());
  assert.equal(globalBudget(f).unknownUsageRequests, 1);
});

test('Usage finalization is idempotent', async () => {
  const metadata = { totalTokenCount: 150 };
  const f = fixture({ usageMetadata: metadata });
  const result = await f.solveQuestion(f.request());
  const date = [...f.records.keys()].find((key) => /^ai_budget\/[^/]+$/.test(key)).split('/')[1];
  await f.context.finishAiGuard('student-1', date, result.scanId, metadata, 'answer');
  assert.equal(globalBudget(f).reportedTotalTokens, 150);
  assert.equal(globalBudget(f).finalizedCalls, 1);
});

test('Finishing usage after deletion does not recreate UID-scoped records', async () => {
  const f = fixture();
  const result = await f.solveQuestion(f.request());
  const date = [...f.records.keys()].find((key) => /^ai_budget\/[^/]+$/.test(key)).split('/')[1];
  const callKey = `ai_budget/${date}/calls/${result.scanId}`;
  f.records.get(callKey).status = 'reserved';
  f.records.set('account_deletions/student-1', { status: 'completed' });
  f.records.delete(`ai_attempts/student-1_${date}`);
  f.records.delete('ai_request_limits/student-1');
  await f.context.finishAiGuard('student-1', date, result.scanId, null, 'answer');
  assert.equal(f.records.has(`ai_attempts/student-1_${date}`), false);
  assert.equal(f.records.has('ai_request_limits/student-1'), false);
});

test('Account deletion also removes new UID-scoped attempt and rate records', async () => {
  const f = accountFixture();
  f.records.set('ai_attempts/owner_2026-11-13', { count: 3 });
  f.records.set('ai_request_limits/owner', { active: {} });
  f.records.set('ai_budget/2026-11-13', { attempts: 8 });
  await f.deleteMyAccount(f.request());
  assert.equal(f.records.has('ai_attempts/owner_2026-11-13'), false);
  assert.equal(f.records.has('ai_request_limits/owner'), false);
  assert.equal(f.records.get('ai_budget/2026-11-13').attempts, 8);
});

test('Provider retry and continuation are disabled on both endpoints', async () => {
  const f = fixture(); await f.solveQuestion(f.request()); await f.generateDocument(documentRequest());
  for (const input of f.calls) {
    assert.ok(input.maxOutputTokens <= 3000);
    assert.equal(input.model, undefined); // Client requests cannot select a model.

  }
  assert.equal(f.solveQuestion.options.concurrency, 2);
  assert.equal(f.generateDocument.options.concurrency, 2);
});

test('Unexpected request fields are rejected without an AI call', async () => {
  const f = fixture();
  await assert.rejects(f.solveQuestion(f.request({ uid: 'other-user' })), { code: 'invalid-argument' });
  const r = documentRequest(); r.data.uid = 'other-user';
  await assert.rejects(f.generateDocument(r), { code: 'invalid-argument' });
  assert.equal(f.calls.length, 0);
});

test('Sanitized logging never forwards arbitrary error bodies or code strings', () => {
  const f = fixture();
  assert.equal(f.context.safeErrorCode({ message: 'secret or user content' }), 'unknown-error');
  assert.equal(f.context.safeErrorCode({ code: 'secret or user content' }), 'unknown-error');
  assert.equal(f.context.safeErrorCode({ code: 'permission-denied' }), 'permission-denied');
  assert.equal(f.context.safeErrorCode({ status: 429 }), 429);
});


const reportData = { source: 'scan', content: 'Reported answer', reason: 'incorrect', note: '' };
function reportRequest(data = reportData, uid = 'student-1') {
  return { auth: uid ? { uid } : null, data };
}

test('Chat answers can be reported under the same authenticated report limit', async () => {
  const f = fixture();
  await f.reportAiContent(reportRequest({...reportData,source:'chat'}));
  const report = [...f.records.entries()].find(([key]) => key.includes('/aiReports/'))[1];
  assert.equal(report.source,'chat');
  assert.equal(f.calls.length,0);
});

test('Account deletion removes chat messages, request metadata and exact-owner chat quotas', async () => {
  const f = accountFixture();
  f.records.set('users/owner/chats/chat-1',{messages:['private text']});
  f.records.set('users/owner/chatRequests/req-1',{hash:'private request hash'});
  f.records.set('chat_usage/owner_2026-11-16',{count:5});
  f.records.set('chat_usage/owner_other_2026-11-16',{count:2});
  await f.deleteMyAccount(f.request());
  assert.equal(f.records.has('users/owner/chats/chat-1'),false);
  assert.equal(f.records.has('users/owner/chatRequests/req-1'),false);
  assert.equal(f.records.has('chat_usage/owner_2026-11-16'),false);
  assert.equal(f.records.has('chat_usage/owner_other_2026-11-16'),true);
});

test('AI report stores only user-submitted text under authenticated UID without Luna', async () => {
  const f = fixture();
  const result = await f.reportAiContent(reportRequest());
  assert.equal(result.received, true);
  const reports = [...f.records.entries()].filter(([key]) => key.includes('/aiReports/'));
  assert.equal(reports.length, 1);
  assert.match(reports[0][0], /^users\/student-1\/aiReports\//);
  assert.equal(reports[0][1].content, reportData.content);
  assert.equal(reports[0][1].status, 'new');
  assert.equal(f.calls.length, 0);
});

test('AI report requires authentication and App Check with no Luna secret binding', async () => {
  const f = fixture();
  await assert.rejects(f.reportAiContent(reportRequest(reportData, null)), { code: 'unauthenticated' });
  assert.equal(f.records.size, 0);
  assert.equal(f.reportAiContent.options.enforceAppCheck, true);
  assert.equal(f.reportAiContent.options.secrets, undefined);
});

for (const [name, change] of [
  ['blank text', { content: '  ' }],
  ['oversized text', { content: 'a'.repeat(20001) }],
  ['oversized note', { note: 'a'.repeat(1001) }],
  ['unknown reason', { reason: 'unknown' }],
  ['unknown source', { source: 'unknown' }],
  ['injected owner', { uid: 'victim' }],
]) test(`AI report rejects ${name} before writes`, async () => {
  const f = fixture();
  await assert.rejects(f.reportAiContent(reportRequest({ ...reportData, ...change })), { code: 'invalid-argument' });
  assert.equal(f.records.size, 0);
  assert.equal(f.calls.length, 0);
});

test('AI reports enforce five daily reports per UID without charging AI quotas', async () => {
  const f = fixture();
  for (let i = 0; i < 5; i++) await f.reportAiContent(reportRequest());
  await assert.rejects(f.reportAiContent(reportRequest()), { code: 'resource-exhausted' });
  assert.equal([...f.records.keys()].filter((key) => key.includes('/aiReports/')).length, 5);
  await f.reportAiContent(reportRequest(reportData, 'student-2'));
  assert.equal(f.calls.length, 0);
  assert.equal(usage(f), undefined);
});

test('Account deletion marker blocks new AI reports without creating usage', async () => {
  const f = fixture();
  f.records.set('account_deletions/student-1', { status: 'deleting' });
  await assert.rejects(f.reportAiContent(reportRequest()), { code: 'failed-precondition' });
  assert.equal(f.records.size, 1);
});

test('Account deletion removes submitted reports and report counters, preserving other users', async () => {
  const f = accountFixture();
  const date = new Date().toISOString().slice(0, 10);
  f.records.set('users/owner/aiReports/report-1', { content: 'Private report' });
  f.records.set(`ai_report_usage/owner_${date}`, { count: 1 });
  f.records.set(`ai_report_usage/another_${date}`, { count: 2 });
  await f.deleteMyAccount(f.request());
  assert.equal(f.records.has('users/owner/aiReports/report-1'), false);
  assert.equal(f.records.has(`ai_report_usage/owner_${date}`), false);
  assert.equal(f.records.has(`ai_report_usage/another_${date}`), true);
});

const eligibilityRequest = (data = {}, uid = 'student-1') => ({ auth: uid ? { uid } : null,
  data: { expectedUid: uid, ageBand: '18-plus', guardianPermission: false, privacyAccepted: true, version: 1, ...data } });
test('AI endpoints require eligibility before quota reservation or provider costs', async () => {
  const f = fixture({ eligibility: false });
  await assert.rejects(f.solveQuestion(f.request()), { code: 'failed-precondition' });
  await assert.rejects(f.generateDocument(documentRequest()), { code: 'failed-precondition' });
  assert.equal(f.records.size, 0); assert.equal(f.calls.length, 0);
});
test('Adult declaration enables AI but cannot be submitted for another account', async () => {
  const f = fixture({ eligibility: false });
  await assert.rejects(f.setAiEligibility(eligibilityRequest({ expectedUid: 'victim' })), { code: 'invalid-argument' });
  assert.equal((await f.setAiEligibility(eligibilityRequest())).eligible, true);
  const p = f.records.get('users/student-1/settings/aiEligibility');
  assert.equal(p.method, 'self-declaration'); assert.equal(p.dateOfBirth, undefined);
  await f.solveQuestion(f.request()); assert.equal(f.calls.length, 1);
});
test('Teen eligibility requires guardian permission and privacy acceptance', async () => {
  const f = fixture({ eligibility: false });
  assert.equal((await f.setAiEligibility(eligibilityRequest({ ageBand: '13-17' }))).eligible, false);
  await assert.rejects(f.solveQuestion(f.request()), { code: 'failed-precondition' });
  assert.equal((await f.setAiEligibility(eligibilityRequest({ ageBand: '13-17', guardianPermission: true }))).eligible, true);
  await f.solveQuestion(f.request()); assert.equal(f.calls.length, 1);
});
test('Under-13 declaration cannot enable AI or be changed to adult to bypass the gate', async () => {
  const f = fixture({ eligibility: false });
  assert.equal((await f.setAiEligibility(eligibilityRequest({ ageBand: 'under-13' }))).eligible, false);
  await assert.rejects(f.setAiEligibility(eligibilityRequest()), { code: 'failed-precondition' });
  await assert.rejects(f.solveQuestion(f.request()), { code: 'failed-precondition' }); assert.equal(f.calls.length, 0);
});
test('Privacy consent must be accepted before AI use', async () => {
  const f = fixture({ eligibility: false });
  assert.equal((await f.setAiEligibility(eligibilityRequest({ privacyAccepted: false }))).eligible, false);
  await assert.rejects(f.generateDocument(documentRequest()), { code: 'failed-precondition' });
});
test('Eligibility requires auth, exact payloads and App Check without an AI secret', async () => {
  const f = fixture({ eligibility: false });
  await assert.rejects(f.setAiEligibility(eligibilityRequest({}, null)), { code: 'unauthenticated' });
  await assert.rejects(f.setAiEligibility(eligibilityRequest({ admin: true })), { code: 'invalid-argument' });
  await assert.rejects(f.setAiEligibility(eligibilityRequest({ version: 2 })), { code: 'invalid-argument' });
  for (const name of ['getAiEligibility', 'setAiEligibility']) {
    assert.equal(f[name].options.enforceAppCheck, true); assert.equal(f[name].options.secrets, undefined);
  }
});
test('Eligibility lookup cannot target another UID', async () => {
  const f = fixture({ eligibility: false });
  assert.equal((await f.getAiEligibility({ auth: { uid: 'student-1' }, data: { expectedUid: 'student-1' } })).eligible, false);
  await assert.rejects(f.getAiEligibility({ auth: { uid: 'student-1' }, data: { expectedUid: 'victim' } }), { code: 'invalid-argument' });
});
test('Deletion marker blocks eligibility recreation', async () => {
  const f = fixture({ eligibility: false }); f.records.set('account_deletions/student-1', { status: 'completed' });
  await assert.rejects(f.setAiEligibility(eligibilityRequest()), { code: 'failed-precondition' }); assert.equal(f.records.size, 1);
});
test('Account deletion removes the nested eligibility declaration', async () => {
  const f = accountFixture(); f.records.set('users/owner/settings/aiEligibility', { ageBand: '13-17' });
  await f.deleteMyAccount(f.request()); assert.equal(f.records.has('users/owner/settings/aiEligibility'), false);
});

test('Updated AI clients bind requests to their original account before costs or writes', async () => {
  const f = fixture();
  await assert.rejects(f.solveQuestion(f.request({ expectedUid: 'old-user' })), { code: 'failed-precondition' });
  const document = documentRequest(); document.data.expectedUid = 'old-user';
  await assert.rejects(f.generateDocument(document), { code: 'failed-precondition' });
  assert.equal(f.calls.length, 0); assert.equal(f.records.size, 0);
  await f.solveQuestion(f.request({ expectedUid: 'student-1' }));
  assert.equal(f.calls.length, 1);
});

test('AI endpoints bind the OpenAI secret only', () => {
  const f = fixture();
  assert.equal(f.solveQuestion.options.secrets[0].name, 'OPENAI_API_KEY');
  assert.equal(f.generateDocument.options.secrets[0].name, 'OPENAI_API_KEY');
});
test('A blocked paid response preserves usage metadata but refunds successful-use quota and saves no history', async () => {
  const error = Object.assign(new Error('Do not expose this body'), { kind: 'safety-blocked', providerResponded: true,
    usageMetadata: { promptTokenCount: 12, candidatesTokenCount: 8, totalTokenCount: 20 } });
  const f = fixture({ aiError: error });
  await assert.rejects(f.solveQuestion(f.request()), { code: 'permission-denied' });
  assert.equal(history(f).length, 0);
  assert.equal(usage(f).count, 0);
  const attempts = [...f.records.entries()].find(([key]) => key.startsWith('ai_attempts/'))[1];
  assert.equal(attempts.count, 1); assert.equal(attempts.reportedTotalTokens, 20);
});

for (const provider of ['anonymous','custom',null]) test(`Member guard rejects ${provider} before eligibility, AI or database access`, async () => {
  const f = fixture();
  const auth = {uid: 'student-1', token: {firebase: {sign_in_provider: provider}}};
  await assert.rejects(f.solveQuestion({...f.request(),auth}), {code:'unauthenticated'});
  await assert.rejects(f.generateDocument({auth,data:{}}), {code:'unauthenticated'});
  await assert.rejects(f.getAiEligibility({auth,data:{expectedUid:auth.uid}}), {code:'unauthenticated'});
  await assert.rejects(f.aiChat({auth,data:{action:'list'}}), {code:'unauthenticated'});
  assert.equal(f.calls.length,0); assert.equal(f.records.size,0);
});
test('Unverified password account is rejected with an actionable reason', async () => {
  const f=fixture(),auth={uid:'student-1',token:{firebase:{sign_in_provider:'password'},email_verified:false}};
  await assert.rejects(f.solveQuestion({...f.request(),auth}), e=>e.code==='permission-denied'&&e.details.reason==='email-verification');
  assert.equal(f.calls.length,0);assert.equal(f.records.size,0);
});
