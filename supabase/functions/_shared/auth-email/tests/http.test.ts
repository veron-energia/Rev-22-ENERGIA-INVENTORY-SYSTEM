// The request envelope, CORS, and where the client IP is allowed to come from.

import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { corsHeaders, guardRequest, json, notConfigured, NOT_CONFIGURED_MESSAGE, clientKey, MAX_BODY_BYTES } from '../http.ts';
import { APP_URL } from './support.ts';

const allowed = [APP_URL];
const req = (init: RequestInit & { url?: string } = {}) =>
  new Request(init.url ?? 'https://project.functions.supabase.co/auth-signup-request', init);

Deno.test('only listed origins are echoed back', () => {
  assertEquals(corsHeaders(APP_URL, allowed)['Access-Control-Allow-Origin'], APP_URL);
  assertEquals(corsHeaders(`${APP_URL}/`, allowed)['Access-Control-Allow-Origin'], APP_URL);
  // Absent header rather than a wildcard: an unlisted origin gets no permission.
  assertEquals(corsHeaders('https://evil.example', allowed)['Access-Control-Allow-Origin'], undefined);
  assertEquals(corsHeaders(null, allowed)['Access-Control-Allow-Origin'], undefined);
  assertEquals(corsHeaders(APP_URL, allowed).Vary, 'Origin');
});

Deno.test('preflight is answered without touching anything else', async () => {
  const guard = await guardRequest(req({ method: 'OPTIONS', headers: { Origin: APP_URL } }), allowed);
  assertFalse(guard.ok);
  if (!guard.ok) assertEquals(guard.response.status, 204);
});

Deno.test('anything but POST is refused', async () => {
  for (const method of ['GET', 'PUT', 'DELETE', 'PATCH', 'HEAD']) {
    const guard = await guardRequest(req({ method }), allowed);
    assertFalse(guard.ok);
    if (!guard.ok) assertEquals(guard.response.status, 405, method);
  }
});

Deno.test('only JSON is accepted', async () => {
  for (const type of ['text/plain', 'application/x-www-form-urlencoded', 'multipart/form-data', '']) {
    const guard = await guardRequest(req({ method: 'POST', headers: { 'Content-Type': type }, body: '{}' }), allowed);
    assertFalse(guard.ok);
    if (!guard.ok) assertEquals(guard.response.status, 415, type);
  }
});

Deno.test('an oversized body is refused even when Content-Length lies', async () => {
  const big = JSON.stringify({ email: 'a'.repeat(MAX_BODY_BYTES + 1000) });

  const declared = await guardRequest(req({
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': String(MAX_BODY_BYTES + 1000) },
    body: big,
  }), allowed);
  assertFalse(declared.ok);
  if (!declared.ok) assertEquals(declared.response.status, 413);

  // Streamed with no Content-Length at all: the read still stops at the ceiling.
  const stream = new ReadableStream({
    start(controller) { controller.enqueue(new TextEncoder().encode(big)); controller.close(); },
  });
  const streamed = await guardRequest(new Request('https://project.functions.supabase.co/x', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: stream,
    // @ts-ignore duplex is required for a streaming body
    duplex: 'half',
  }), allowed);
  assertFalse(streamed.ok);
  if (!streamed.ok) assertEquals(streamed.response.status, 413);
});

Deno.test('only a JSON object is a body', async () => {
  for (const body of ['not json', '[1,2,3]', 'null', '"a string"', '42']) {
    const guard = await guardRequest(req({ method: 'POST', headers: { 'Content-Type': 'application/json' }, body }), allowed);
    assertFalse(guard.ok);
    if (!guard.ok) assertEquals(guard.response.status, 400, body);
  }
});

Deno.test('a well-formed request parses', async () => {
  const guard = await guardRequest(req({
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8', Origin: APP_URL },
    body: JSON.stringify({ email: 'a@b.co' }),
  }), allowed);
  assert(guard.ok);
  if (guard.ok) {
    assertEquals(guard.body, { email: 'a@b.co' });
    assertEquals(guard.origin, APP_URL);
  }
});

Deno.test('responses are never cached', async () => {
  const response = json({ ok: true }, 200, APP_URL, allowed);
  assertEquals(response.headers.get('Cache-Control'), 'no-store');
  assertEquals(await response.json(), { ok: true });
});

const withCf = (value: string | null, extra: Record<string, string> = {}) =>
  new Request('https://x', { headers: { ...(value === null ? {} : { 'cf-connecting-ip': value }), ...extra } });

Deno.test('M6: the client key of an IPv4 address is the address', () => {
  assertEquals(clientKey(withCf('203.0.113.7')), '203.0.113.7');
  assertEquals(clientKey(withCf(' 198.51.100.20 ')), '198.51.100.20');
});

Deno.test('M6: IPv4 octets are normalised, so a leading zero is not a new connection', () => {
  assertEquals(clientKey(withCf('192.000.002.004')), '192.0.2.4');
  assertEquals(clientKey(withCf('203.000.113.007')), '203.0.113.7');
  assertEquals(clientKey(withCf('256.1.1.1')), 'unknown');
});

Deno.test('M6: an IPv4-mapped IPv6 address is its IPv4, in either spelling', () => {
  assertEquals(clientKey(withCf('::ffff:203.0.113.7')), '203.0.113.7');
  assertEquals(clientKey(withCf('::FFFF:cb00:7107')), '203.0.113.7');
  assertEquals(clientKey(withCf('[::ffff:192.0.2.1]')), '192.0.2.1');
});

Deno.test('M6: an IPv6 address is its /64, however it is spelt', () => {
  const key = '2001:db8:1:2::/64';
  for (const a of [
    '2001:db8:1:2::1', '2001:db8:1:2:ffff:ffff:ffff:ffff', '2001:0db8:0001:0002:0000:0000:0000:0001',
    '2001:DB8:1:2:a:b:c:d', '[2001:db8:1:2::9]', '2001:db8:1:2::1%eth0', '2001:db8:1:2:0:0:0:0',
  ]) assertEquals(clientKey(withCf(a)), key, a);
  assertEquals(clientKey(withCf('2001:db8:1:3::1')), '2001:db8:1:3::/64', 'the next /64 is another connection');
  assertEquals(clientKey(withCf('2001:db8::1')), '2001:db8:0:0::/64', 'a "::" inside the first four groups');
  assertEquals(clientKey(withCf('::1')), '0:0:0:0::/64');
});

Deno.test('M6: a forged x-forwarded-for, x-real-ip or true-client-ip is never read', () => {
  const forged = { 'x-forwarded-for': '198.51.100.9, 203.0.113.7', 'x-real-ip': '203.0.113.8', 'true-client-ip': '203.0.113.9' };
  assertEquals(clientKey(withCf('198.51.100.5', forged)), '198.51.100.5');
  assertEquals(clientKey(withCf(null, forged)), 'unknown', 'with no cf-connecting-ip the forged headers count for nothing');
});

Deno.test('M6: a missing or unusable header is the shared key "unknown", never "no limit"', () => {
  for (const v of [null, '', 'not-an-ip', '999.1.1.1', '1.2.3', '2001:db8::1::2', '2001:db8:1:2:3:4:5:6:7', '12345::1', ':::', '2001:db8:g::1']) {
    assertEquals(clientKey(withCf(v)), 'unknown', String(v));
  }
});

// (security audit of 17 Nov 2026, L10)
Deno.test('the not-configured reply carries a fixed sentence and a request id, and no secret name', async () => {
  const response = notConfigured('req-123', APP_URL, allowed);
  assertEquals(response.status, 503);
  assertEquals(response.headers.get('Access-Control-Allow-Origin'), APP_URL);
  const text = await response.text();
  const body = JSON.parse(text);
  assertEquals(body, { error: 'not_configured', message: NOT_CONFIGURED_MESSAGE, request_id: 'req-123' });
  assertFalse('missing' in body);
});
