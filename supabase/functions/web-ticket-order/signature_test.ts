// Request signing: what counts as the website, and for how long.

import { assert, assertEquals, assertFalse, assertMatch } from 'jsr:@std/assert@1';
import { MAX_AGE_SECONDS, MAX_FUTURE_SECONDS, signBody, timingSafeEqual, verifySignature } from './signature.ts';

const SECRET = 'test-signing-secret';
const NOW = 1_790_000_000;
const BODY = '{"type":"paid","order":{"channel":"alaric-birthday-2026"}}';
const bytes = (s: string) => new TextEncoder().encode(s);

const check = async (overrides: Partial<Parameters<typeof verifySignature>[0]> = {}) =>
  await verifySignature({
    secret: SECRET,
    timestamp: String(NOW),
    signature: await signBody(SECRET, NOW, BODY),
    body: bytes(BODY),
    nowSeconds: NOW,
    ...overrides,
  });

Deno.test('the signature is v1= and 64 lowercase hex characters', async () => {
  assertMatch(await signBody(SECRET, NOW, BODY), /^v1=[0-9a-f]{64}$/);
});

Deno.test('it matches an HMAC-SHA256 of "<timestamp>.<body>" computed independently', async () => {
  const key = await crypto.subtle.importKey('raw', bytes(SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, bytes(`${NOW}.${BODY}`)));
  const hex = [...mac].map(b => b.toString(16).padStart(2, '0')).join('');
  assertEquals(await signBody(SECRET, NOW, BODY), `v1=${hex}`);
  // A string and its UTF-8 bytes sign the same, including non-ASCII names.
  const accented = '{"name":"Guest Oné"}';
  assertEquals(await signBody(SECRET, NOW, accented), await signBody(SECRET, NOW, bytes(accented)));
});

Deno.test('a genuine, fresh request passes', async () => {
  assertEquals(await check(), null);
  // Upper-case hex is the same signature.
  const upper = (await signBody(SECRET, NOW, BODY)).replace(/[a-f]/g, c => c.toUpperCase());
  assertEquals(await check({ signature: upper }), null);
});

Deno.test('missing headers are refused', async () => {
  assertEquals(await check({ timestamp: null }), 'missing');
  assertEquals(await check({ signature: null }), 'missing');
  assertEquals(await check({ timestamp: '', signature: '' }), 'missing');
});

Deno.test('malformed headers are refused before any HMAC is compared', async () => {
  const good = await signBody(SECRET, NOW, BODY);
  for (const signature of [
    good.slice(3),                 // no scheme
    good.replace('v1=', 'v0='),    // unknown scheme
    good.slice(0, -2),             // too short
    `${good}00`,                   // too long
    `${good.slice(0, -1)}g`,       // not hex
    `${good},${good}`,             // lists are not supported
  ]) assertEquals(await check({ signature }), 'malformed', signature);

  for (const timestamp of ['abc', '-5', '1.5', `${NOW}ms`, '1'.repeat(13)]) {
    assertEquals(await check({ timestamp }), 'malformed', timestamp);
  }
});

Deno.test('a changed body, timestamp or secret does not verify', async () => {
  assertEquals(await check({ body: bytes(BODY.replace('paid', 'names')) }), 'mismatch');
  assertEquals(await check({ body: bytes(`${BODY} `) }), 'mismatch', 'even trailing whitespace');
  assertEquals(await check({ timestamp: String(NOW + 1) }), 'mismatch', 'the timestamp is signed');
  assertEquals(await check({ secret: 'another-secret' }), 'mismatch');
});

Deno.test('the window is 300 s into the past and 60 s into the future', async () => {
  const at = async (sent: number) =>
    await check({ timestamp: String(sent), signature: await signBody(SECRET, sent, BODY) });

  assertEquals(await at(NOW - MAX_AGE_SECONDS), null);
  assertEquals(await at(NOW - MAX_AGE_SECONDS - 1), 'stale');
  assertEquals(await at(NOW + MAX_FUTURE_SECONDS), null);
  assertEquals(await at(NOW + MAX_FUTURE_SECONDS + 1), 'future');
});

Deno.test('a stale request with a wrong signature reports the signature, not the clock', async () => {
  assertEquals(await check({ timestamp: String(NOW - 3600) }), 'mismatch');
});

Deno.test('timingSafeEqual compares every byte', () => {
  assert(timingSafeEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 3])));
  assertFalse(timingSafeEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 4])));
  assertFalse(timingSafeEqual(new Uint8Array([0, 2, 3]), new Uint8Array([1, 2, 3])));
  assertFalse(timingSafeEqual(new Uint8Array([1, 2]), new Uint8Array([1, 2, 3])));
  assert(timingSafeEqual(new Uint8Array(0), new Uint8Array(0)));
});
