// The contract is copied verbatim (436): here, into the Event page
// (src/components/events/eventWebsiteContract.ts, shown on the Website tab)
// and into the website (src/lib/event-api-contract.ts). Each copy's md5 is the
// one recorded in contract.md5, so a drift is a failing test.

import { assertEquals } from 'jsr:@std/assert@1';
import { crypto as stdCrypto } from 'jsr:@std/crypto@1';
import {
  callEventApi, CONTRACT_VERSION, ERRORS, EventApiError, isWriteType, READ_TYPES, SUGGESTED_TALK_TITLES, withEventApiRetries, WRITE_TYPES,
} from './contract.ts';

const here = new URL('.', import.meta.url);
const md5 = async (bytes: Uint8Array<ArrayBuffer>) => Array.from(new Uint8Array(await stdCrypto.subtle.digest('MD5', bytes)), (b) => b.toString(16).padStart(2, '0')).join('');

Deno.test("the edge function's contract.ts and the Event page's copy are the recorded version", async () => {
  const recorded = (await Deno.readTextFile(new URL('contract.md5', here))).trim();
  assertEquals(await md5(await Deno.readFile(new URL('contract.ts', here))), recorded);
  assertEquals(await md5(await Deno.readFile(new URL('../../../src/components/events/eventWebsiteContract.ts', here))), recorded);
});

Deno.test("the contract's message lists and errors hang together", () => {
  assertEquals(CONTRACT_VERSION, 1);
  assertEquals([...WRITE_TYPES, ...READ_TYPES].length, 10);
  for (const t of WRITE_TYPES) assertEquals(isWriteType(t), true);
  for (const t of READ_TYPES) assertEquals(isWriteType(t), false);
  // A passing fault (503) is tried again at once; too many requests (429) after its retry_after_seconds.
  for (const [code, e] of Object.entries(ERRORS)) assertEquals(e.retry, e.http === 503 || e.http === 429, code);
});

Deno.test('the reference client: a 429 is retryable after its wait, and is not retried at once', async () => {
  const realFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = (() => {
    calls++;
    return Promise.resolve(new Response(JSON.stringify({ ok: false, error: 'too_many_requests', retry_after_seconds: 42 }),
      { status: 429, headers: { 'Content-Type': 'application/json', 'Retry-After': '42' } }));
  }) as typeof fetch;
  try {
    const config = { url: 'https://example.invalid/functions/v1/event-website', key: 'evk_test_' + 'a'.repeat(43), event: 'HT-TEST' };
    const failed = await withEventApiRetries(() => callEventApi(config, 'event_info', {}), [500, 1500]).catch((e) => e);
    assertEquals(failed instanceof EventApiError, true);
    assertEquals([failed.code, failed.httpStatus, failed.retryable, failed.retryAfterSeconds], ['too_many_requests', 429, true, 42]);
    assertEquals(calls, 1);
  } finally {
    globalThis.fetch = realFetch;
  }
});

Deno.test('the suggested talk titles are the ones in 436 (event_web_talk_titles)', async () => {
  const sql = await Deno.readTextFile(new URL('../../436_event_website_registrations_and_vip.sql', import.meta.url));
  const fn = sql.slice(sql.indexOf('FUNCTION public.event_web_talk_titles('));
  const list = fn.slice(fn.indexOf('array['), fn.indexOf(']::text[]'));
  const titles = [...list.matchAll(/'((?:[^']|'')*)'/g)].map((m) => m[1].replaceAll("''", "'"));
  assertEquals(titles, [...SUGGESTED_TALK_TITLES]);
});
