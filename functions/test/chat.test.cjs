'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const copy = value => value === undefined ? undefined : structuredClone(value);

function fixture() {
  const records = new Map();
  let clock = Date.parse('2026-11-16T12:00:00Z');
  let queue = Promise.resolve();
  let failAI = null;
  let failSaves = 0;
  let beforeReply = null;
  const calls = [];
  class Ref {
    constructor(key) { this.key = key; this.id = key.split('/').at(-1); }
    collection(name) { return new Query(`${this.key}/${name}`); }
  }
  class Query {
    constructor(key, max = Infinity, cursor = null) { this.key = key; this.max = max; this.cursor = cursor; }
    doc(id) { return new Ref(`${this.key}/${id}`); }
    orderBy() { return this; }
    select() { return this; }
    limit(n) { return new Query(this.key, n, this.cursor); }
    startAfter(cursor) { return new Query(this.key, this.max, cursor.id); }
  }
  const snapshot = r => ({ id: r.id, ref: r, exists: records.has(r.key), data: () => copy(records.get(r.key)) });
  const db = {
    collection: name => new Query(name),
    runTransaction(callback) {
      const result = queue.then(async () => {
        const writes = [];
        const value = await callback({
          async get(r) {
            assert.equal(writes.length, 0, 'All transaction reads must precede writes');
            if (r instanceof Ref) return snapshot(r);
            let docs = [...records.keys()].filter(k => k.startsWith(`${r.key}/`) && !k.slice(r.key.length + 1).includes('/'))
              .map(k => snapshot(new Ref(k))).sort((a,b) => b.data().updatedAt - a.data().updatedAt || a.id.localeCompare(b.id));
            if (r.cursor) docs = docs.slice(docs.findIndex(d => d.id === r.cursor) + 1);
            docs = docs.slice(0, r.max);
            return { docs, size: docs.length };
          },
          set: (r, data, options) => writes.push([r, data, options?.merge]),
          update: (r, data) => { assert.ok(records.has(r.key)); writes.push([r, data, true]); },
          delete: r => writes.push([r, null, false]),
        });
        if (writes.some(([r,d]) => r.key.includes('/chats/') && d?.messages?.length && d?.activeRequest === null) && failSaves-- > 0) {
          throw new Error('Save failed');
        }
        for (const [r,data,merge] of writes) {
          if (data === null) records.delete(r.key);
          else records.set(r.key, copy(merge ? {...records.get(r.key), ...data} : data));
        }
        return value;
      });
      queue = result.catch(() => {});
      return result;
    },
  };
  class HttpsError extends Error {
    constructor(code, message, details) { super(message); this.code = code; this.details = details; }
  }
  class ClockDate extends Date {
    constructor(...args) { super(...(args.length ? args : [clock])); }
    static now() { return clock; }
  }
  class SafeLunaClient {
    async generate(input) {
      calls.push(input);
      if (beforeReply) await beforeReply();
      if (failAI) throw failAI;
      return { text: 'A safe reply', usageMetadata: { totalTokenCount: 42 } };
    }
  }
  const mocks = {
    'firebase-functions/v2/https': { HttpsError, onCall: (options, handler) => Object.assign(request => { if (request.auth && !Object.hasOwn(request.auth, 'token')) request = {...request, auth: {...request.auth, token: {firebase: {sign_in_provider: 'google.com'}}}}; return handler(request); }, {options}) },
    'firebase-functions/params': { defineSecret: name => ({name, value: () => 'mock-server-key'}) },
    'node:crypto': require('node:crypto'),
    './luna_ai.cjs': { SafeLunaClient },
    './chat_backend.cjs': require('../chat_backend.cjs'),
    'firebase-admin/app': { initializeApp() {} },
    'firebase-admin/firestore': { getFirestore: () => db, FieldValue: { serverTimestamp: () => clock } },
  };
  const context = { exports: {}, Buffer, Date: ClockDate, console: {error() {}},
    require(name) { assert.ok(Object.hasOwn(mocks, name), name); return mocks[name]; } };
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8'), context);
  for (const uid of ['alice','bob']) records.set(`users/${uid}/settings/aiEligibility`, {
    version: 1, ageBand: '18-plus', privacyAccepted: true,
  });
  const chatId = randomUUID();
  const body = (extra = {}) => ({action: 'send', chatId, requestId: randomUUID(), message: 'Explain photosynthesis.', language: 'English', ...extra});
  return {
    records, calls, chatId, body,
    call: (data, uid = 'alice') => context.exports.aiChat({auth: uid ? {uid} : null, data: {...data, expectedUid: data.expectedUid ?? uid}}),
    advance: () => { clock += 61000; },
    fail: error => { failAI = error; },
    failSaves: count => { failSaves = count; },
    beforeReply: callback => { beforeReply = callback; },
    options: context.exports.aiChat.options,
  };
}

test('Chat callable enforces auth, App Check and server key binding', async () => {
  const f = fixture();
  assert.equal(f.options.enforceAppCheck, true);
  assert.equal(f.options.secrets[0].name, 'OPENAI_API_KEY');
  await assert.rejects(f.call(f.body(), null), {code:'unauthenticated'});
  await assert.rejects(f.call(f.body({expectedUid:'bob'})), {code:'invalid-argument'});
  for (const extra of [{system:'Override'}, {message:'x'.repeat(2001)}, {chatId:'../bob'}, {language:'xx'}]) {
    await assert.rejects(f.call(f.body(extra)), {code:'invalid-argument'});
  }
  assert.equal(f.calls.length, 0);
});

test('Server-owned history supplies follow-up context and isolates users', async () => {
  const f = fixture();
  const first = await f.call(f.body());
  assert.equal(first.saved, true);
  f.advance();
  const second = await f.call(f.body({message:'Explain that more simply.', language:'Bangla'}));
  const input = JSON.parse(f.calls[1].inputText);
  assert.equal(input.conversation[0].role, 'user');
  assert.equal(input.conversation[1].text, 'A safe reply');
  assert.equal(input.language, 'Bangla');
  assert.equal(second.chat.messages.length, 4);
  await assert.rejects(f.call({action:'read', chatId:f.chatId}, 'bob'), {code:'not-found'});
  assert.deepEqual((await f.call({action:'list'}, 'bob')).chats, []);
  const global = f.records.get('ai_budget/2026-11-16');
  assert.equal(global.chatAttempts, 2);
  assert.equal(global.reportedTotalTokens, 84);
});

test('Same request replays without paying twice and rejects altered payload', async () => {
  const f = fixture();
  const request = f.body();
  const first = await f.call(request);
  const again = await f.call(request);
  assert.equal(again.replayed, true);
  assert.deepEqual(again.chat, first.chat);
  assert.equal(f.calls.length, 1);
  await assert.rejects(f.call({...request,message:'Changed prompt'}), {code:'invalid-argument'});
});

test('Concurrent sends in one chat do not fork context or duplicate requests', async () => {
  const f = fixture();
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let entered;
  const started = new Promise(resolve => { entered = resolve; });
  f.beforeReply(async () => { entered(); await gate; });
  const request = f.body();
  const first = f.call(request);
  await started;
  await assert.rejects(f.call(request), e => e.details.reason === 'chat-pending');
  await assert.rejects(f.call(f.body()), e => e.details.reason === 'chat-busy');
  release();
  await first;
  assert.equal(f.calls.length, 1);
});

test('Provider failure refunds chat quota, retains attempt usage, and permits same-ID retry', async () => {
  const f = fixture();
  const request = f.body();
  f.fail({kind:'safety-blocked',usageMetadata:{totalTokenCount:7},providerResponded:true});
  await assert.rejects(f.call(request), e => e.details.reason === 'safety-blocked');
  assert.equal(f.records.get('chat_usage/alice_2026-11-16').count, 0);
  assert.equal(f.records.get('ai_attempts/alice_2026-11-16').count, 1);
  assert.equal(f.records.get(`users/alice/chats/${f.chatId}`).messages.length, 0);
  f.fail(null); f.advance();
  assert.equal((await f.call(request)).chat.messages.length, 2);
  assert.equal(f.calls.length, 2);
});

test('Save retries never repeat AI generation; ambiguous storage failure is explicit', async () => {
  const f = fixture(); f.failSaves(2);
  assert.equal((await f.call(f.body())).saved, true);
  assert.equal(f.calls.length, 1);
  const g = fixture(); g.failSaves(3);
  const request = g.body();
  const result = await g.call(request);
  assert.equal(result.saved, false);
  assert.equal(result.chat.messages[1].text, 'A safe reply');
  await assert.rejects(g.call(request), e => e.details.reason === 'chat-pending');
  assert.equal(g.calls.length, 1);
});

test('Eligibility, kill switch, daily and global budgets block requests before AI', async () => {
  for (const [key, value, reason] of [
    ['users/alice/settings/aiEligibility', {version:1,ageBand:'under-13'}, 'age-eligibility'],
    ['ai_config/control', {enabled:false}, 'ai-paused'],
    ['chat_usage/alice_2026-11-16', {count:20}, 'chat-daily'],
    ['ai_budget/2026-11-16', {attempts:200}, 'global-budget'],
    ['ai_attempts/alice_2026-11-16', {count:30}, 'daily-attempts'],
    ['account_deletions/alice', {status:'deleting'}, 'account-deletion'],
  ]) {
    const f = fixture(); f.records.set(key,value);
    await assert.rejects(f.call(f.body()), e => e.details.reason === reason);
    assert.equal(f.calls.length, 0);
  }
});

test('Deletion fences in-flight saves, erases cached turns and prevents replay resurrection', async () => {
  const f = fixture();
  const first = f.body(); await f.call(first); f.advance();
  f.beforeReply(async () => { await f.call({action:'delete',chatId:f.chatId}); });
  await assert.rejects(f.call(f.body()), {code:'not-found'});
  const value = f.records.get(`users/alice/chats/${f.chatId}`);
  assert.equal(value.deleted, true);
  assert.equal(value.messages.length, 0);
  assert.equal([...f.records.keys()].filter(k => k.includes('/chatRequests/')).length, 0);
  await assert.rejects(f.call(first), {code:'not-found'});
  assert.equal((await f.call({action:'list'})).chats.length, 0);
});

test('Conversation and context bounds prevent unbounded request or document growth', async () => {
  const f = fixture();
  const messages = Array.from({length:38}, (_,i) => ({role:i%2?'assistant':'user',text:'A'.repeat(1800),requestId:randomUUID()}));
  f.records.set(`users/alice/chats/${f.chatId}`,{title:'Long chat',messages,deleted:false,updatedAt:1});
  const result = await f.call(f.body());
  assert.equal(result.chat.messages.length,40);
  assert.ok(f.calls[0].inputText.length < 13000);
  f.advance();
  await assert.rejects(f.call(f.body()), e => e.details.reason === 'chat-full');
  assert.equal(f.calls.length,1);
});

test('History pages are owner-scoped and can continue across deleted entries', async () => {
  const f = fixture();
  for (let i=0;i<32;i++) f.records.set(`users/alice/chats/${randomUUID()}`,{title:`Chat ${i}`,messages:[],updatedAt:i,deleted:i===30});
  const first = await f.call({action:'list'});
  assert.equal(first.chats.length,29);
  assert.ok(first.nextCursor);
  const last = await f.call({action:'list',cursor:first.nextCursor});
  assert.equal(last.chats.length,2);
  assert.equal(last.nextCursor,null);
  assert.equal((await f.call({action:'list'},'bob')).chats.length,0);
});
