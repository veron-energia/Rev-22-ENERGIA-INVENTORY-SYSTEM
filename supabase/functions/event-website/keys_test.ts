// The key's shape and hash, and the timestamp window (436).

import { assertEquals } from 'jsr:@std/assert@1';
import { keyShaped, sha256Hex, timestampProblem } from './keys.ts';
import { LIVE_KEY, TEST_KEY } from './fixtures.ts';

Deno.test('a key is evk_live_ or evk_test_ and 43 base64url characters', () => {
  assertEquals(keyShaped(LIVE_KEY), true);
  assertEquals(keyShaped(TEST_KEY), true);
  for (const bad of [null, '', 'evk_live_short', LIVE_KEY + 'A', LIVE_KEY.replace('evk_live_', 'evk_prod_'),
    LIVE_KEY.slice(0, -1) + '=', 'Bearer ' + LIVE_KEY]) {
    assertEquals(keyShaped(bad), false, String(bad));
  }
});

Deno.test('the hash is the lower-case hex SHA-256 the database keeps', async () => {
  // sha256("abc"), the FIPS 180-2 test vector.
  assertEquals(await sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  assertEquals((await sha256Hex(LIVE_KEY)).length, 64);
});

Deno.test('the timestamp: unix seconds, at most 300 s old or 60 s ahead', () => {
  const now = 1_790_000_000;
  assertEquals(timestampProblem(String(now), now), null);
  assertEquals(timestampProblem(String(now - 300), now), null);
  assertEquals(timestampProblem(String(now + 60), now), null);
  assertEquals(timestampProblem(String(now - 301), now), 'stale');
  assertEquals(timestampProblem(String(now + 61), now), 'future');
  assertEquals(timestampProblem(null, now), 'missing');
  assertEquals(timestampProblem('', now), 'missing');
  assertEquals(timestampProblem('1.5e9', now), 'malformed');
  // Milliseconds instead of seconds is not a timestamp at all.
  assertEquals(timestampProblem(String(now * 1000), now), 'malformed');
  assertEquals(timestampProblem(String(now * 10), now), 'future');
});
