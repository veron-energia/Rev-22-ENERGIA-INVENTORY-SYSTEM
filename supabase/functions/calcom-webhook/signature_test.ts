// cal.com's signature: what counts as cal.com (480).

import { assertEquals, assertFalse, assert, assertMatch } from 'jsr:@std/assert@1';
import { signBody, timingSafeEqual, verifySignature } from './signature.ts';

const SECRET = 'test-calcom-webhook-secret';
const BODY = '{"triggerEvent":"PING","createdAt":"2026-10-29T03:00:00.000Z","payload":{}}';
const bytes = (s: string) => new TextEncoder().encode(s);

const check = async (overrides: Partial<Parameters<typeof verifySignature>[0]> = {}) =>
  await verifySignature({ secret: SECRET, signature: await signBody(SECRET, BODY), body: bytes(BODY), ...overrides });

Deno.test('the signature is 64 lowercase hex characters, no prefix', async () => {
  assertMatch(await signBody(SECRET, BODY), /^[0-9a-f]{64}$/);
});

Deno.test('it is an HMAC-SHA256 of the raw body alone, computed independently', async () => {
  const key = await crypto.subtle.importKey('raw', bytes(SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, bytes(BODY)));
  assertEquals(await signBody(SECRET, BODY), [...mac].map(b => b.toString(16).padStart(2, '0')).join(''));
  // A string and its UTF-8 bytes sign the same, a non-ASCII name too.
  const accented = '{"name":"Fixture Oné"}';
  assertEquals(await signBody(SECRET, accented), await signBody(SECRET, bytes(accented)));
});

Deno.test('a genuine request passes, in either case of hex and with spaces around it', async () => {
  assertEquals(await check(), null);
  assertEquals(await check({ signature: (await signBody(SECRET, BODY)).toUpperCase() }), null);
  assertEquals(await check({ signature: ` ${await signBody(SECRET, BODY)} ` }), null);
});

Deno.test('a missing signature is refused', async () => {
  assertEquals(await check({ signature: null }), 'missing');
  assertEquals(await check({ signature: '' }), 'missing');
  assertEquals(await check({ signature: '   ' }), 'missing');
});

Deno.test('a malformed signature is refused before any HMAC is compared', async () => {
  const good = await signBody(SECRET, BODY);
  for (const signature of ['no-secret-provided', `sha256=${good}`, good.slice(0, 63), `${good}0`, 'z'.repeat(64)]) {
    assertEquals(await check({ signature }), 'malformed', signature);
  }
});

Deno.test('another secret, another body or one changed byte is a mismatch', async () => {
  assertEquals(await check({ signature: await signBody('another-secret', BODY) }), 'mismatch');
  assertEquals(await check({ body: bytes(BODY.replace('PING', 'BOOKING_CREATED')) }), 'mismatch');
  assertEquals(await check({ body: bytes(BODY + ' ') }), 'mismatch');
});

Deno.test('the comparison is all or nothing', () => {
  const a = new Uint8Array([1, 2, 3]);
  assert(timingSafeEqual(a, new Uint8Array([1, 2, 3])));
  assertFalse(timingSafeEqual(a, new Uint8Array([1, 2, 4])));
  assertFalse(timingSafeEqual(a, new Uint8Array([1, 2])));
});
