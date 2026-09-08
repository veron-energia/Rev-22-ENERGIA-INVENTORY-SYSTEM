// The limiter's client side: keyed hashing, the shape of a reservation, and
// what happens when the database cannot answer.

import { assert, assertEquals, assertFalse, assertNotEquals, assertRejects, assertStringIncludes } from 'jsr:@std/assert@1';
import { hashKey, rateLimitMessage, reserve, RateLimiterUnavailableError } from '../ratelimit.ts';
import { fakeAdmin } from './support.ts';

Deno.test('keys are keyed hashes, not the values themselves', async () => {
  const secret = 'hash-secret-value';
  const hash = await hashKey('ada@example.com', secret, 'email');

  assertEquals(hash.length, 64);
  assert(/^[0-9a-f]+$/.test(hash));
  assertFalse(hash.includes('ada'), 'the address must not be recoverable by eye');
  assertEquals(await hashKey('ada@example.com', secret, 'email'), hash, 'stable within a secret');
  assertNotEquals(await hashKey('ada@example.com', 'a-different-secret', 'email'), hash);
  // Separate label spaces, so an address and an IP can never collide.
  assertNotEquals(await hashKey('ada@example.com', secret, 'ip'), hash);
});

Deno.test('a reservation is passed to the database, not decided locally', async () => {
  const admin = fakeAdmin({ auth_email_reserve: () => ({ allowed: true, retry_after_seconds: 0 }) });
  const result = await reserve(admin, 'signup', 'email-hash', 'ip-hash');

  assertEquals(result.allowed, true);
  assertEquals(admin.calls[0].fn, 'auth_email_reserve');
  assertEquals(admin.calls[0].args, { p_action: 'signup', p_email_hash: 'email-hash', p_ip_hash: 'ip-hash' });
});

Deno.test('a missing IP is passed through as null, keeping the email limits', async () => {
  const admin = fakeAdmin({ auth_email_reserve: () => ({ allowed: true, retry_after_seconds: 0 }) });
  await reserve(admin, 'recovery', 'email-hash', null);
  assertEquals(admin.calls[0].args.p_ip_hash, null);
});

Deno.test('a refusal carries the delay but the caller learns nothing else', async () => {
  const admin = fakeAdmin({ auth_email_reserve: () => ({ allowed: false, retry_after_seconds: 840, scope: 'email' }) });
  const result = await reserve(admin, 'resend', 'email-hash', 'ip-hash');
  assertEquals(result.allowed, false);
  assertEquals(result.retryAfterSeconds, 840);
});

Deno.test('a limiter that errors or answers nonsense throws rather than allowing', async () => {
  await assertRejects(
    () => reserve(fakeAdmin({ auth_email_reserve: () => new Error('connection refused') }), 'signup', 'e', null),
    RateLimiterUnavailableError,
  );
  await assertRejects(
    () => reserve(fakeAdmin({ auth_email_reserve: () => 'not an object' }), 'signup', 'e', null),
    RateLimiterUnavailableError,
  );
  await assertRejects(
    () => reserve(fakeAdmin({ auth_email_reserve: () => ({ retry_after_seconds: 5 }) }), 'signup', 'e', null),
    RateLimiterUnavailableError,
  );
});

Deno.test('the 429 wording is friendly and names no bucket', () => {
  assertStringIncludes(rateLimitMessage(30), 'wait a minute');
  assertStringIncludes(rateLimitMessage(420), '7 minutes');
  assertStringIncludes(rateLimitMessage(3600), 'an hour');
  assertStringIncludes(rateLimitMessage(7200), '2 hours');
  for (const seconds of [1, 60, 900, 3600]) {
    const message = rateLimitMessage(seconds);
    assertFalse(/email|address|account|IP/i.test(message), message);
  }
});
