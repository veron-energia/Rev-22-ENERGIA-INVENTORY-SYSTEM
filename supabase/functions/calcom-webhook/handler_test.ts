// End to end through the handler with the database faked (480): every status
// code cal.com can get, and that no log line carries anything from the body.

import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { handleWebhook, MAX_BODY_BYTES, readResult, type RpcClient } from './handler.ts';
import { loadWebhookConfig, MissingConfigError, type WebhookConfig } from './config.ts';
import { signBody } from './signature.ts';
import { createdBody, createdEvent, pingBody, SECRET, UID } from './fixtures.ts';

const URL = 'https://project.functions.supabase.co/calcom-webhook';
const config: WebhookConfig = { supabaseUrl: 'https://project.supabase.co', serviceRoleKey: 'service-role-key', webhookSecret: SECRET };

type RpcReply = { data: unknown; error: { message?: string; code?: string } | null };

function fakeClient(answer: () => RpcReply | Promise<RpcReply> = () => ({ data: { result: 'created' }, error: null })) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client: RpcClient = {
    rpc(fn, args) {
      calls.push({ fn, args });
      return Promise.resolve(answer());
    },
  };
  return { calls, client };
}

const run = (req: Request, client: RpcClient = fakeClient().client, load: () => WebhookConfig = () => config) =>
  handleWebhook(req, { loadConfig: load, makeClient: () => client, now: () => 1_790_000_000_000 });

async function signed(body: unknown, opts: { secret?: string; headers?: Record<string, string>; method?: string } = {}): Promise<Request> {
  const raw = typeof body === 'string' || body instanceof Uint8Array ? body as string | Uint8Array<ArrayBuffer> : JSON.stringify(body);
  return new Request(URL, {
    method: opts.method ?? 'POST',
    headers: { 'Content-Type': 'application/json', 'x-cal-signature-256': await signBody(opts.secret ?? SECRET, raw), ...(opts.headers ?? {}) },
    body: raw,
  });
}

/** Everything the handler logged while `fn` ran. */
async function logsOf(fn: () => Promise<unknown>): Promise<string> {
  const lines: string[] = [];
  const original = console.log;
  console.log = (...args: unknown[]) => { lines.push(args.map(String).join(' ')); };
  try { await fn(); } finally { console.log = original; }
  return lines.join('\n');
}

const PERSONAL = ['Fixture Person', 'fixture.person', 'example.invalid', '9001', '9002', '9003', 'fixture answer', UID];

Deno.test('a booking goes to calcom_booking_ingest with only the kept fields, and its result comes back', async () => {
  const { calls, client } = fakeClient();
  let response: Response | undefined;
  const logs = await logsOf(async () => { response = await run(await signed(createdBody()), client); });
  assertEquals(response!.status, 200);
  assertEquals(await response!.json(), { ok: true, result: 'created' });
  assertEquals(response!.headers.get('Cache-Control'), 'no-store');
  assertEquals(calls, [{ fn: 'calcom_booking_ingest', args: { p_event: createdEvent() } }]);
  assert(logs.includes('"event":"calcom_webhook.done"') && logs.includes('"trigger":"BOOKING_CREATED"') && logs.includes('"result":"created"'));
  for (const p of PERSONAL) assertFalse(logs.includes(p), `log mentions ${p}`);
});

Deno.test('every result the database gives is passed back as 200', async () => {
  for (const result of ['created', 'updated', 'unchanged', 'stale', 'ignored']) {
    const response = await run(await signed(createdBody()), fakeClient(() => ({ data: { result, previous: 'updated' }, error: null })).client);
    assertEquals([response.status, await response.json()], [200, { ok: true, result }], result);
  }
});

Deno.test('PING is answered without the database; other triggers are ignored without it', async () => {
  const { calls, client } = fakeClient();
  const ping = await run(await signed(pingBody()), client);
  assertEquals([ping.status, await ping.json()], [200, { ok: true, result: 'pong' }]);
  for (const t of ['BOOKING_REJECTED', 'BOOKING_REQUESTED', 'MEETING_ENDED', 'BOOKING_PAYMENT_INITIATED']) {
    const r = await run(await signed({ ...createdBody(), triggerEvent: t }), client);
    assertEquals([r.status, await r.json()], [200, { ok: true, result: 'ignored' }], t);
  }
  assertEquals(calls.length, 0);
});

Deno.test('a good, a bad and a missing signature', async () => {
  const body = createdBody();
  const raw = JSON.stringify(body);
  const good = await signed(body);
  const requests = [
    await signed(body, { secret: 'another-secret' }),
    await signed(body, { headers: { 'x-cal-signature-256': 'no-secret-provided' } }),
    await signed(body, { headers: { 'x-cal-signature-256': '' } }),
    new Request(URL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: raw }),
    // A valid signature moved onto a different body.
    new Request(URL, { method: 'POST', headers: { 'x-cal-signature-256': good.headers.get('x-cal-signature-256')! },
                       body: raw.replace('2026-10-31T06:00:00Z', '2026-11-30T06:00:00Z') }),
  ];
  for (const [i, req] of requests.entries()) {
    const { calls, client } = fakeClient();
    const response = await run(req, client);
    assertEquals(response.status, 401, `request ${i}`);
    assertEquals(await response.json(), { ok: false, error: 'bad_signature' });
    assertEquals(calls.length, 0);
  }
  // The header name in any case, and no Content-Type needed.
  const { calls, client } = fakeClient();
  const plain = new Request(URL, { method: 'POST', headers: { 'X-Cal-Signature-256': await signBody(SECRET, raw) }, body: raw });
  assertEquals((await run(plain, client)).status, 200);
  assertEquals(calls.length, 1);
});

Deno.test('an unsigned body is never parsed', async () => {
  const response = await run(await signed('{not json', { secret: 'another-secret' }));
  assertEquals(response.status, 401);
});

Deno.test('not configured: 503 until the secret (or the platform\'s keys) is set, whatever is sent', async () => {
  const missing = () => { throw new MissingConfigError(['CALCOM_WEBHOOK_SECRET']); };
  const { calls, client } = fakeClient();
  let response: Response | undefined;
  const logs = await logsOf(async () => { response = await run(await signed(createdBody()), client, missing); });
  assertEquals([response!.status, await response!.json()], [503, { ok: false, error: 'not_configured' }]);
  assertEquals((await run(new Request(URL, { method: 'GET' }), client, missing)).status, 503);
  assertEquals(calls.length, 0);
  assert(logs.includes('CALCOM_WEBHOOK_SECRET'));
  assertFalse(logs.includes(SECRET));
});

Deno.test('the config reads its three values and names what is missing, never a value', () => {
  const saved = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEY', 'CALCOM_WEBHOOK_SECRET'].map(k => [k, Deno.env.get(k)] as const);
  try {
    for (const [k] of saved) Deno.env.delete(k);
    Deno.env.set('SUPABASE_URL', 'https://project.supabase.co/');
    Deno.env.set('SUPABASE_SECRET_KEY', 'made-up-service-key');
    try { loadWebhookConfig(); throw new Error('no error'); } catch (e) {
      assert(e instanceof MissingConfigError);
      assertEquals(e.names, ['CALCOM_WEBHOOK_SECRET']);
      assertFalse(String(e.message).includes('made-up-service-key'));
    }
    Deno.env.set('CALCOM_WEBHOOK_SECRET', '  made-up-webhook-secret  ');
    assertEquals(loadWebhookConfig(), { supabaseUrl: 'https://project.supabase.co', serviceRoleKey: 'made-up-service-key', webhookSecret: 'made-up-webhook-secret' });
  } finally {
    for (const [k, v] of saved) { if (v === undefined) Deno.env.delete(k); else Deno.env.set(k, v); }
  }
});

Deno.test('POST only', async () => {
  for (const method of ['GET', 'PUT', 'DELETE', 'PATCH']) {
    const response = await run(new Request(URL, { method, body: method === 'GET' ? undefined : '{}' }));
    assertEquals(response.status, 405, method);
    assertEquals(response.headers.get('Allow'), 'POST');
  }
});

Deno.test('oversize: refused by Content-Length and while reading', async () => {
  const big = JSON.stringify({ ...createdBody(), pad: 'x'.repeat(MAX_BODY_BYTES) });
  const { calls, client } = fakeClient();
  assertEquals((await run(await signed(big), client)).status, 413);
  const stream = new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode(big)); c.close(); } });
  assertEquals((await run(new Request(URL, { method: 'POST', body: stream }), client)).status, 413);
  assertEquals(calls.length, 0);
});

Deno.test('bad JSON, not UTF-8 and a body that is not a booking are 400, naming no value', async () => {
  const { calls, client } = fakeClient();
  const broken = await run(await signed('{"triggerEvent":"BOOKING_CREATED",'), client);
  assertEquals([broken.status, await broken.json()], [400, { ok: false, error: 'invalid_json' }]);
  const notUtf8 = await run(await signed(new Uint8Array([0x7b, 0xff, 0x7d])), client);
  assertEquals(notUtf8.status, 400);
  const noTrigger = await run(await signed({ payload: createdBody().payload }), client);
  assertEquals([noTrigger.status, await noTrigger.json()], [400, { ok: false, error: 'invalid_request', field: 'triggerEvent' }]);
  const noUid = await run(await signed(createdBody({ uid: null })), client);
  assertEquals([noUid.status, await noUid.json()], [400, { ok: false, error: 'invalid_request', field: 'payload.uid' }]);
  assertEquals(calls.length, 0);
});

Deno.test('a booking without a readable createdAt is a 400 naming the field, and never reaches the database', async () => {
  const { calls, client } = fakeClient();
  const { createdAt: _dropped, ...noTime } = createdBody();
  for (const body of [noTime, { ...createdBody(), createdAt: null }, { ...createdBody(), createdAt: 1793000000000 }, { ...createdBody(), createdAt: ' ' }]) {
    let response: Response | undefined;
    const logs = await logsOf(async () => { response = await run(await signed(body), client); });
    assertEquals([response!.status, await response!.json()], [400, { ok: false, error: 'invalid_request', field: 'createdAt' }]);
    assert(logs.includes('"field":"createdAt"'));
    for (const p of PERSONAL) assertFalse(logs.includes(p), `log mentions ${p}`);
  }
  assertEquals(calls.length, 0);
});

Deno.test('a data exception from the database is a 400, logged by its code only', async () => {
  for (const code of ['22023', '22P02', '22007']) {
    const { calls, client } = fakeClient(() => ({ data: null,
      error: { message: 'calcom_booking_ingest: payload.startTime is not a moment near Fixture Person +61255509001 fixture.person@example.invalid', code } }));
    let response: Response | undefined;
    const logs = await logsOf(async () => { response = await run(await signed(createdBody()), client); });
    assertEquals([response!.status, await response!.json()], [400, { ok: false, error: 'invalid_request', field: 'payload' }], code);
    assertEquals(calls.length, 1);
    assert(logs.includes(`"code":"${code}"`));
    for (const p of [...PERSONAL, 'startTime is not']) assertFalse(logs.includes(p), `log mentions ${p} (${code})`);
  }
});

Deno.test('any other database or network failure is a safe 503 without personal data', async () => {
  const failures: Array<() => RpcReply | Promise<RpcReply>> = [
    () => ({ data: null, error: { message: 'permission denied for function calcom_booking_ingest', code: '42501' } }),
    () => ({ data: null, error: { message: 'canceling statement due to statement timeout (Fixture Person, +61255509001)', code: '57014' } }),
    () => ({ data: null, error: { message: 'TypeError: fetch failed', code: '' } }),
    () => ({ data: null, error: { message: 'odd', code: 'not a code; drop table' } }),
    () => Promise.reject(new Error('connection reset near fixture.person@example.invalid')),
    () => ({ data: { result: 'maybe' }, error: null }),
    () => ({ data: null, error: null }),
    () => ({ data: ['created'], error: null }),
  ];
  for (const [i, answer] of failures.entries()) {
    let response: Response | undefined;
    const logs = await logsOf(async () => { response = await run(await signed(createdBody()), fakeClient(answer).client); });
    assertEquals(response!.status, 503, `failure ${i}`);
    const body = await response!.text();
    assertEquals(JSON.parse(body), { ok: false, error: 'retry' });
    for (const p of [...PERSONAL, 'drop table', 'permission denied', 'statement timeout']) {
      assertFalse(logs.includes(p), `log ${i} mentions ${p}`);
      assertFalse(body.includes(p), `answer ${i} mentions ${p}`);
    }
  }
});

Deno.test('readResult accepts the five results only', () => {
  assertEquals(readResult({ result: 'stale', previous: 'created' }), 'stale');
  assertEquals(readResult({ result: 'pong' }), null);
  assertEquals(readResult('created'), null);
  assertEquals(readResult(null), null);
});
