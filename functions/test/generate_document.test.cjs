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
      if (writes.some(({ r }) => r.key.includes('/documents/'))) {
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
    'firebase-functions/v2/https': { onCall: (options, handler) => Object.assign(handler, { options }), HttpsError },
    'node:crypto': { randomUUID: () => `request-${++nextId}` },
    'firebase-functions/params': { defineSecret: (name) => ({ name, value: () => 'offline-test-secret' }) },
    './luna_ai.cjs': { SafeLunaClient },
    './handwriting_backend.cjs': require('../handwriting_backend.cjs'),
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


function documentUsage(f) {
  return [...f.records.entries()].find(([key]) => /^document_usage\/[^/]+$/.test(key))?.[1];
}
function documents(f) {
  return [...f.records.entries()].filter(([key]) => key.includes('/documents/'));
}
function request(uid = 'student-1', data = {}) {
  return { auth: uid ? { uid } : null, data: {
    title: 'Leave Application', instructions: 'Request two days of leave for family reasons.',
    documentType: 'Leave Application', language: 'Bangla', ...data,
  } };
}

test('Generated document is saved under authenticated owner and its ID is returned', async () => {
  const f = fixture({ text: '## Application\nDear Sir,\nPlease grant leave.' });
  const response = await f.generateDocument(request());
  assert.equal(response.savedToLibrary, true);
  assert.equal(response.remainingToday, 9);
  assert.equal(documents(f).length, 1);
  assert.equal(documents(f)[0][0], `users/student-1/documents/${response.documentId}`);
  assert.equal(documents(f)[0][1].content, response.document);
  assert.equal(documentUsage(f).count, 1);
});

test('Rejects unauthenticated requests before usage or Luna calls', async () => {
  const f = fixture();
  await assert.rejects(f.generateDocument(request(null)), { code: 'unauthenticated' });
  assert.equal(f.calls.length, 0);
  assert.equal(f.records.size, 0);
});

for (const [name, data] of [
  ['short title', { title: 'ab' }], ['long title', { title: 'a'.repeat(151) }],
  ['short instructions', { instructions: 'tiny' }],
  ['long instructions', { instructions: 'a'.repeat(2001) }],
  ['empty type', { documentType: ' ' }],
  ['unsupported language', { language: 'bn' }],
  ['non-string title', { title: 123 }],
]) test(`Rejects ${name} before spending quota`, async () => {
  const f = fixture();
  await assert.rejects(f.generateDocument(request('student-1', data)), { code: 'invalid-argument' });
  assert.equal(f.calls.length, 0);
  assert.equal(f.records.size, 0);
});

for (const [type, expected] of [
  ['CV / Resume', 'employment'], ['Job Application', 'role'],
  ['Leave Application', 'requested dates'], ['Formal Letter', 'salutation'],
  ['Invoice', 'taxes'], ['Assignment', 'citations'],
  ['Custom AI Document', 'purpose'],
]) test(`${type} has relevant generation guidance`, async () => {
  const f = fixture();
  await f.generateDocument(request('student-1', { documentType: type, language: 'English' }));
  assert.match(f.calls[0].instructions, new RegExp(expected));
  const fields = JSON.parse(f.calls[0].inputText);
  assert.equal(fields.language, 'English');
  assert.equal(fields.documentType, type);
});

test('Trims input while preserving user-selected language and custom types', async () => {
  const f = fixture();
  const response = await f.generateDocument(request('student-1', {
    title: '  My Letter  ', documentType: '  Custom Report  ', language: 'English',
  }));
  assert.equal(response.title, 'My Letter');
  assert.equal(response.documentType, 'Custom Report');
  assert.equal(documents(f)[0][1].language, 'English');
});

test('Daily document limit and scan limit stay independent', async () => {
  const f = fixture();
  for (let i = 0; i < 10; i++) await f.generateDocument(request());
  await assert.rejects(f.generateDocument(request()), { code: 'resource-exhausted' });
  const scan = await f.solveQuestion(f.request());
  assert.equal(scan.remainingToday, 9);
});

test('Document quota is isolated per authenticated account', async () => {
  const f = fixture();
  for (let i = 0; i < 10; i++) await f.generateDocument(request());
  const response = await f.generateDocument(request('student-2'));
  assert.equal(response.remainingToday, 9);
  assert.ok(documents(f).some(([key]) => key.startsWith('users/student-2/')));
});

for (const [label, options] of [['provider error', { aiError: true }], ['empty response', { text: '  ' }]]) {
  test(`${label} refunds document usage without saving a blank document`, async () => {
    const f = fixture(options);
    await assert.rejects(f.generateDocument(request()), { code: 'internal' });
    assert.equal(documentUsage(f).count, 0);
    assert.equal(documents(f).length, 0);
    assert.equal([...f.records.entries()].find(([key]) => key.startsWith('document_usage/') && key.includes('/requests/'))[1].status, 'refunded');
  });
}

test('Temporary save error retries one document ID without calling Luna again', async () => {
  const f = fixture({ historyFailures: 1 });
  const result = await f.generateDocument(request());
  assert.equal(result.savedToLibrary, true);
  assert.equal(f.historyAttempts(), 2);
  assert.equal(documents(f).length, 1);
  assert.equal(f.calls.length, 1);
});

test('Persistent save error preserves usable content and explicitly reports unsaved status', async () => {
  const f = fixture({ historyFailures: 3 });
  const result = await f.generateDocument(request());
  assert.equal(result.savedToLibrary, false);
  assert.equal(result.documentId, null);
  assert.ok(result.document);
  assert.equal(documents(f).length, 0);
  assert.equal(documentUsage(f).count, 1);
});

test('Malformed usage counter is rejected without an AI call', async () => {
  const f = fixture();
  const date = new Date().toISOString().slice(0, 10);
  f.records.set(`document_usage/student-1_${date}`, { count: '2' });
  await assert.rejects(f.generateDocument(request()), { code: 'internal' });
  assert.equal(f.calls.length, 0);
});

test('Generated document remains protected by App Check and server-only secrets', () => {
  const f = fixture();
  assert.equal(f.generateDocument.options.enforceAppCheck, true);
  assert.equal(f.generateDocument.options.secrets.length, 1);
  assert.equal(f.generateDocument.options.region, 'europe-west1');
});


const handwritingRequest = (data = {}, uid = 'student-1') => ({auth: uid ? {uid} : null,
  data: {expectedUid: uid, imageBase64: jpeg.toString('base64'), mimeType:'image/jpeg',language:'auto',...data}});
const transcription = text => JSON.stringify({readable:true,text});
test('Handwriting transcribes original text into one editable Library note without saving photos',async()=>{
  const text='  বাংলা নোট\nEnglish note [unclear]';
  const f=fixture({text:transcription(text)});
  const result=await f.recognizeHandwriting(handwritingRequest());
  assert.equal(result.text,text);
  assert.equal(result.savedToLibrary,true);
  assert.equal(result.remainingToday,9);
  const notes=documents(f);
  assert.equal(notes.length,1);
  assert.equal(notes[0][1].documentType,'Handwriting Recognition');
  assert.equal(notes[0][1].content,text);
  assert.equal(JSON.stringify([...f.records.values()]).includes(jpeg.toString('base64')),false);
  assert.equal(f.calls.length,1);
  assert.equal(f.recognizeHandwriting.options.enforceAppCheck,true);
  assert.equal(f.recognizeHandwriting.options.secrets[0].name,'OPENAI_API_KEY');
});
test('Handwriting rejects unauthenticated, forged, oversized and unsupported requests before AI',async()=>{
  const f=fixture();
  await assert.rejects(f.recognizeHandwriting(handwritingRequest({},null)),{code:'unauthenticated'});
  for(const extra of [{expectedUid:'another'},{language:'xx'},{system:'override'},{mimeType:'image/png'},
    {imageBase64:'@not-base64'},{imageBase64:'A'.repeat(3*1024*1024)}]) {
    await assert.rejects(f.recognizeHandwriting(handwritingRequest(extra)),{code:'invalid-argument'});
  }
  assert.equal(f.calls.length,0);
  assert.equal(f.records.size,0);
});
test('Unreadable and malformed handwriting responses refund scan quota but retain usage attempts',async()=>{
  for(const text of [JSON.stringify({readable:false,text:''}),'not json',JSON.stringify({readable:true,text:'ok',extra:'bad'}),transcription('x'.repeat(20001))]) {
    const f=fixture({text,usageMetadata:{totalTokenCount:10}});
    await assert.rejects(f.recognizeHandwriting(handwritingRequest()));
    const usage=[...f.records.entries()].find(([k])=>/^ai_usage\/[^/]+$/.test(k))[1];
    assert.equal(usage.count,0);
    assert.equal(documents(f).length,0);
    assert.equal([...f.records.entries()].find(([k])=>k.startsWith('ai_attempts/'))[1].count,1);
  }
});
test('Handwriting and Scan & Solve share the same daily reservation',async()=>{
  const f=fixture({text:transcription('A handwritten line')});
  await f.solveQuestion(f.request());
  const result=await f.recognizeHandwriting(handwritingRequest());
  assert.equal(result.remainingToday,8);
  assert.equal(f.calls.length,2);
});
test('Handwriting cannot bypass age eligibility, deletion fences or the global kill switch',async()=>{
  for(const mode of ['age','deleted','paused']) {
    const f=fixture({eligibility:mode!=='age',text:transcription('Notes')});
    if(mode==='deleted')f.records.set('account_deletions/student-1',{status:'deleting'});
    if(mode==='paused')f.records.set('ai_config/control',{enabled:false});
    await assert.rejects(f.recognizeHandwriting(handwritingRequest()));
    assert.equal(f.calls.length,0);
    assert.equal(documents(f).length,0);
  }
});
test('Handwriting save retries never repeat AI generation and failed history is explicit',async()=>{
  const f=fixture({text:transcription('Notes'),historyFailures:2});
  assert.equal((await f.recognizeHandwriting(handwritingRequest())).savedToLibrary,true);
  assert.equal(f.calls.length,1);
  const g=fixture({text:transcription('Notes'),historyFailures:3});
  const result=await g.recognizeHandwriting(handwritingRequest());
  assert.equal(result.savedToLibrary,false);
  assert.equal(result.documentId,null);
  assert.equal(result.text,'Notes');
  assert.equal(g.calls.length,1);
});
test('Deleting an account during handwriting recognition prevents new Library content',async()=>{
  let f;
  f=fixture({text:transcription('Notes'),beforeResponse:()=>f.records.set('account_deletions/student-1',{status:'deleting'})});
  await assert.rejects(f.recognizeHandwriting(handwritingRequest()),{code:'failed-precondition'});
  assert.equal(documents(f).length,0);
});
