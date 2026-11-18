const { test } = require('node:test');
const assert = require('node:assert/strict');
const { SafeLunaClient, usageMetadata } = require('../luna_ai.cjs');
function fixture({ inputFlag = false, outputFlag = false, moderationErrorAt = 0, moderationBody,
  status = 'completed', text = 'উত্তর: ৪', responseError = false, refuse = false, withUsage = true } = {}) {
  const calls = []; let moderated = 0;
  const client = new SafeLunaClient({ apiKey: 'offline-key', uid: 'owner-user', fetchImpl: async (url, options) => {
    const body = JSON.parse(options.body); calls.push({ url, body });
    if (url.endsWith('/moderations')) {
      moderated++; if (moderated === moderationErrorAt) throw new Error('private provider data');
      return { ok: true, json: async () => moderationBody ?? { results: [{ flagged: moderated === 1 ? inputFlag : outputFlag }] } };
    }
    if (responseError) return { ok: false, json: async () => ({ secret: 'private provider data' }) };
    return { ok: true, json: async () => ({ status, output: [{ content: [refuse ? { type: 'refusal' } : { type: 'output_text', text }] }],
      ...(withUsage ? { usage: { input_tokens: 1200, output_tokens: 300, total_tokens: 1500, output_tokens_details: { reasoning_tokens: 100 } } } : {}) }) };
  } });
  return { client, calls, input: { instructions: 'Explain in Bangla.', inputText: 'What is 2 + 2?', maxOutputTokens: 2048 } };
}
test('Luna image request is moderated before/after generation, stores no Responses state, and hashes the UID', async () => {
  const f = fixture(); const result = await f.client.generate({ ...f.input, imageBase64: '/9j/', mimeType: 'image/jpeg' });
  assert.equal(result.text, 'উত্তর: ৪'); assert.equal(f.calls.length, 3);
  assert.ok(f.calls[0].url.endsWith('/moderations')); assert.ok(f.calls[1].url.endsWith('/responses'));
  assert.ok(f.calls[2].url.endsWith('/moderations'));
  const b = f.calls[1].body;
  assert.equal(b.model, 'gpt-6-luna'); assert.equal(b.store, false);
  assert.match(b.safety_identifier, /^[a-f0-9]{64}$/); assert.ok(!JSON.stringify(b).includes('owner-user'));
  assert.match(b.instructions, /ages 13-17/); assert.match(b.instructions, /untrusted content/);
  assert.equal(b.input[0].content[1].image_url, 'data:image/jpeg;base64,/9j/');
  assert.equal(b.input[0].content[1].detail, 'high'); assert.equal(b.max_output_tokens, 2048); assert.equal(b.tools, undefined);
  assert.equal(result.usageMetadata.totalTokenCount, 1500);
  assert.equal(result.usageMetadata.candidatesTokenCount, 300); // Reasoning is already included.
  assert.equal(result.usageMetadata.thoughtsTokenCount, 100);
});
test('Flagged input stops before generation cost', async () => {
  const f = fixture({ inputFlag: true }); await assert.rejects(f.client.generate(f.input), { kind: 'safety-blocked' }); assert.equal(f.calls.length, 1);
});
test('Flagged output cannot be returned and billed usage is retained', async () => {
  const f = fixture({ outputFlag: true });
  await assert.rejects(f.client.generate(f.input), (e) => e.kind === 'safety-blocked' && e.usageMetadata.totalTokenCount === 1500 && e.providerResponded);
});
for (const step of [1, 2]) test(`Moderation failure at step ${step} fails closed`, async () => {
  const f = fixture({ moderationErrorAt: step }); await assert.rejects(f.client.generate(f.input), (e) => e.kind === 'safety-unavailable' && !e.message.includes('private'));
  assert.equal(f.calls.length, step === 1 ? 1 : 3);
});
for (const body of [{}, { results: [] }, { results: [{ flagged: 'false' }] }]) test('Malformed moderation cannot authorize generation', async () => {
  const f = fixture({ moderationBody: body }); await assert.rejects(f.client.generate(f.input), { kind: 'safety-unavailable' }); assert.equal(f.calls.length, 1);
});
test('Provider failure has no automatic retry and leaks no error body', async () => {
  const f = fixture({ responseError: true }); await assert.rejects(f.client.generate(f.input), (e) => e.kind === 'provider-unavailable' && !e.message.includes('private')); assert.equal(f.calls.length, 2);
});
for (const status of ['incomplete', 'failed', 'cancelled', 'in_progress']) test(`A ${status} response cannot be presented as a complete document`, async () => {
  const f = fixture({ status }); await assert.rejects(f.client.generate(f.input), { kind: 'provider-incomplete' }); assert.equal(f.calls.length, 2);
});
test('Empty text and a refusal cannot become a saved answer', async () => {
  for (const options of [{ text: ' ' }, { refuse: true }]) {
    const f = fixture(options); await assert.rejects(f.client.generate(f.input));
  }
});
test('Missing usage remains unknown, never fabricated as zero', async () => {
  const f = fixture({ withUsage: false }); assert.equal((await f.client.generate(f.input)).usageMetadata, null); assert.equal(usageMetadata(null), null);
});
test('Invalid output caps and blank input are rejected before any provider call', async () => {
  const f = fixture();
  for (const maxOutputTokens of [undefined, 0, 4000, NaN]) await assert.rejects(f.client.generate({ ...f.input, maxOutputTokens }), { kind: 'invalid-request' });
  await assert.rejects(f.client.generate({ ...f.input, inputText: '  ' }), { kind: 'invalid-request' }); assert.equal(f.calls.length, 0);
});

for (const text of ['![remote image](https://example.org/image.png)', '<img src="https://example.org/image.png">']) {
  test('Generated markup cannot trigger automatic external image loads in Markdown renderers', async () => {
    const f = fixture({ text });
    await assert.rejects(f.client.generate(f.input), { kind: 'safety-blocked' });
    assert.equal(f.calls.length, 2);
  });
}
