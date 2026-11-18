#!/usr/bin/env node
'use strict';
// Operator-only sender. Requires Application Default Credentials with Firebase
// permissions; never include credentials or run this script from the app.
const {parseArgs} = require('node:util');
const {randomUUID} = require('node:crypto');
const {makeMessage, targets} = require('../notification_backend.cjs');

async function main() {
  const {values} = parseArgs({options: {
    uid: {type: 'string'}, title: {type: 'string'}, body: {type: 'string'},
    target: {type: 'string', default: 'home'}, send: {type: 'boolean', default: false},
  }});
  if (!values.uid || values.uid.length > 128 || !values.title || !values.body ||
      !targets.includes(values.target)) throw new Error('Provide --uid, --title, --body and an allowed --target.');
  const {initializeApp} = require('firebase-admin/app');
  const {getFirestore} = require('firebase-admin/firestore');
  const {getMessaging} = require('firebase-admin/messaging');
  initializeApp({projectId: 'jiggo-bee33'});
  const db = getFirestore();
  if ((await db.collection('account_deletions').doc(values.uid).get()).exists) throw new Error('Account unavailable.');
  const devices = await db.collection('users').doc(values.uid).collection('notificationDevices').limit(100).get();
  const recent = devices.docs.filter(doc => doc.data().enabled === true &&
    doc.data().lastSeenMs > Date.now() - 30 * 86400000);
  const id = randomUUID();
  const messages = recent.map(doc => ({doc, payload: makeMessage({
    uid: values.uid, fid: doc.data().fid, id, title: values.title,
    body: values.body, target: values.target, time: Date.now(), revision: doc.data().revision,
  })}));
  console.log(`${messages.length} active device(s). ${values.send ? 'Sending.' : 'Preview only; use --send to deliver.'}`);
  for (const {doc, payload} of messages) {
    if (!values.send) continue;
    if ((await db.collection('account_deletions').doc(values.uid).get()).exists) break;
    const current = await doc.ref.get();
    if (!current.exists || current.data().enabled !== true || current.data().fid !== payload.fid ||
        String(current.data().revision) !== payload.data.revision) continue;
    try { await getMessaging().send(payload); }
    catch (error) {
      if (['messaging/registration-token-not-registered','messaging/invalid-registration-token'].includes(error?.code)) {
        await db.runTransaction(async tx => {
          const latest = await tx.get(doc.ref);
          if (latest.exists && latest.data().fid === payload.fid &&
              String(latest.data().revision) === payload.data.revision) tx.delete(doc.ref);
        });
      }
      // Only a provider error code, never device tokens or credentials.
      console.error('Delivery failed:', String(error?.code || 'unknown').slice(0, 80));
      process.exitCode = 1;
    }
  }
}
main().catch(() => { console.error('Sender failed. Check arguments and server credentials.'); process.exitCode = 1; });
