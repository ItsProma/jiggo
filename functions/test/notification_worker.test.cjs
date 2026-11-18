'use strict';
// Browser worker logic tests with mocked browser APIs. These are not a live
// Chrome/OS notification delivery test and never register or send with Firebase.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');

function worker() {
  const handlers = {};
  const stored = new Map();
  const visible = [];
  const opened = [];
  const messages = [];
  let windows = [{url: 'https://jiggo.example/', postMessage: m => messages.push(m), focus: async () => {}}];
  const db = {close() {}, createObjectStore() {}, transaction() {
    let pending = 0;
    const operation = fn => {
      pending++;
      const req = {};
      setImmediate(() => { req.result = fn(); req.onsuccess?.(); pending--; if (!pending) tx.oncomplete?.(); });
      return req;
    };
    const tx = {objectStore: () => ({
      put(value, key) { return operation(() => { stored.set(key, value); return key; }); },
      get(key) { return operation(() => stored.get(key)); },
    })}; return tx;
  }};
  const self = {location: {href: 'https://jiggo.example/firebase-messaging-sw.js'},
    registration: {
      async getNotifications() { return [...visible]; },
      async showNotification(title, options) {
        const notice = {title, ...options, close() { const i = visible.indexOf(this); if (i >= 0) visible.splice(i,1); }};
        visible.push(notice);
      },
    },
    clients: {claim: async () => {}, matchAll: async () => windows, openWindow: async url => opened.push(url)},
    skipWaiting() {}, addEventListener: (type, fn) => { handlers[type] = fn; },
  };
  const context = {self, URL, Date, Set, Number,
    importScripts() { throw new Error('Offline test'); },
    indexedDB: {open() { const req = {}; setImmediate(() => { req.result = db; req.onsuccess(); }); return req; }},
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../web/firebase-messaging-sw.js'),'utf8'), context);
  async function event(type, data) {
    let work;
    let response;
    handlers[type]({...data, waitUntil: promise => { work = promise; },
      stopImmediatePropagation() {}, ports: [{postMessage: value => { response = value; }}]});
    await work;
    return response;
  }
  const account = (ownerUid, enabled, revision) => event('message', {data: {type: 'jiggo-account',ownerUid,enabled,revision}});
  const show = notice => event('message', {data: {type:'jiggo-local-test',notice}});
  const notice = changes => ({v:'1',id:'n1',ownerUid:'user-1',title:'Jiggo',body:'Test',target:'library',revision:'1',sentAt:String(Date.now()),...changes});
  return {visible, opened, messages, account, show, notice,
    click: n => event('notificationclick', {notification:n}), windows: list => { windows = list; }};
}
test('Worker displays only a consented current-account, current-revision notice', async () => {
  const w = worker(); await w.account('user-1',true,1);
  await w.show(w.notice()); assert.equal(w.visible.length,1);
  await w.show(w.notice({id:'other',ownerUid:'other'}));
  await w.show(w.notice({id:'stale',revision:'0'}));
  assert.equal(w.visible.length,1);
});
test('Opt-out closes existing notices and blocks delayed delivery', async () => {
  const w = worker(); await w.account('user-1',true,1); await w.show(w.notice());
  await w.account('user-1',false,2); await w.show(w.notice());
  assert.equal(w.visible.length,0);
});
test('Worker forwards an allowed click to the live app window', async () => {
  const w = worker(); await w.account('user-1',true,1); await w.show(w.notice());
  await w.click(w.visible[0]);
  assert.equal(w.messages[0].type,'jiggo-notification-open');
  assert.equal(w.messages[0].notice.target,'library');
  assert.equal(w.opened.length,0);
});
test('Worker does not route into a privacy page and uses a safe cold-launch fragment', async () => {
  const w = worker(); await w.account('user-1',true,1); await w.show(w.notice());
  w.windows([{url:'https://jiggo.example/privacy.html',postMessage:()=>{throw new Error('Wrong window');}}]);
  await w.click(w.visible[0]);
  assert.ok(w.opened[0].startsWith('https://jiggo.example/#jiggo-notice='));
  assert.equal(JSON.parse(decodeURIComponent(w.opened[0].split('#jiggo-notice=')[1])).target,'library');
});
test('Signed-out state blocks old notification clicks', async () => {
  const w = worker(); await w.account('user-1',true,1); await w.show(w.notice());
  const old = w.visible[0]; await w.account('',false,2); await w.click(old);
  assert.equal(w.messages.length,0); assert.equal(w.opened.length,0);
});
test('A late command from an older tab cannot undo opt-out or an account change', async () => {
  const w = worker(); await w.account('user-1',true,1);
  await w.account('user-1',false,2);
  await w.account('user-1',true,1);
  await w.show(w.notice());
  assert.equal(w.visible.length,0);
  await w.account('user-2',true,3);
  await w.account('user-1',true,2);
  await w.show(w.notice({id:'late-user',revision:'2'}));
  assert.equal(w.visible.length,0);
  await w.show(w.notice({id:'current-user',ownerUid:'user-2',revision:'3'}));
  assert.equal(w.visible.length,1);
});
test('Worker rejects unsafe destinations and malformed protocol data', async () => {
  const w = worker(); await w.account('user-1',true,1);
  for (const changed of [{target:'https://evil.example/'},{title:'x'.repeat(121)},
    {revision:'-1'},{sentAt:'0'},{ownerUid:''}]) {
    const response = await w.show(w.notice(changed)); assert.equal(response.ok,false);
  }
  assert.equal(w.visible.length,0);
});
test('Launch bridge consumes only app-owned notification fragments before Flutter starts', () => {
  const notice = {v:'1',target:'library',ownerUid:'u'};
  const updates = [];
  let bound;
  const window = {isSecureContext:true, addEventListener(){}};
  const context = {window, document: {baseURI:'https://jiggo.example/'}, URL,
    location: {hash:'#jiggo-notice='+encodeURIComponent(JSON.stringify(notice)),pathname:'/',search:''},
    history: {replaceState: (...args)=>updates.push(args)},
    navigator: {serviceWorker: {addEventListener(){}}}, Notification: {permission:'granted'},
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../web/notification_bridge.js'),'utf8'),context);
  window.jiggoNotifications.bind(value=>{bound=JSON.parse(value);});
  assert.equal(bound.target,'library'); assert.equal(updates[0][2],'/');
});
