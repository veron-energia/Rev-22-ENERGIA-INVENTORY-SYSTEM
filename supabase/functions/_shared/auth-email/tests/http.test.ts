// The request envelope, CORS, and where the client IP is allowed to come from.

import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { corsHeaders, guardRequest, json, trustedClientIp, MAX_BODY_BYTES } from '../http.ts';
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

Deno.test('the client IP is read only from the entry our own proxy wrote', () => {
  // A caller putting a fake address in front cannot displace the real one.
  assertEquals(trustedClientIp(new Request('https://x', { headers: { 'x-forwarded-for': '9.9.9.9, 203.0.113.7' } }), 1), '203.0.113.7');
  assertEquals(trustedClientIp(new Request('https://x', { headers: { 'x-forwarded-for': '203.0.113.7' } }), 1), '203.0.113.7');
  assertEquals(trustedClientIp(new Request('https://x', { headers: { 'x-forwarded-for': 'a, b, 203.0.113.7, 10.0.0.1' } }), 2), '203.0.113.7');
  assertEquals(trustedClientIp(new Request('https://x', { headers: { 'x-forwarded-for': '2001:db8::1' } }), 1), '2001:db8::1');
});

Deno.test('an unusable forwarded-for yields no IP, never a fabricated one', () => {
  // null means "email limits only" to the caller; it must never mean "unlimited".
  assertEquals(trustedClientIp(new Request('https://x'), 1), null);
  assertEquals(trustedClientIp(new Request('https://x', { headers: { 'x-forwarded-for': '' } }), 1), null);
  assertEquals(trustedClientIp(new Request('https://x', { headers: { 'x-forwarded-for': 'not-an-ip' } }), 1), null);
  assertEquals(trustedClientIp(new Request('https://x', { headers: { 'x-forwarded-for': '999.1.1.1' } }), 1), null);
  assertEquals(trustedClientIp(new Request('https://x', { headers: { 'x-forwarded-for': '203.0.113.7' } }), 3), null);
  // Headers we have not verified as platform-written are not consulted at all.
  assertEquals(trustedClientIp(new Request('https://x', { headers: { 'x-real-ip': '203.0.113.7', 'true-client-ip': '203.0.113.7' } }), 1), null);
});
