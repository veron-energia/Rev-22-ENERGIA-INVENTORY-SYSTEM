// End to end through the handler with the database faked: status codes are the
// website's retry signal, so each one is pinned down here.

import { assert, assertEquals, assertFalse, assertThrows } from 'jsr:@std/assert@1';
import { handleOrder, MAX_BODY_BYTES, type RpcClient } from './handler.ts';
import { loadOrderConfig, MissingConfigError, type OrderConfig } from './config.ts';
import { signBody } from './signature.ts';
import { doorOrder, namesOrder, OFF_ID, paidOrder, SECRET, SESSION_ID } from './fixtures.ts';

const NOW_MS = 1_790_000_000_000;
const NOW_S = NOW_MS / 1000;
const URL = 'https://project.functions.supabase.co/web-ticket-order';

const config: OrderConfig = {
  supabaseUrl: 'https://project.supabase.co',
  serviceRoleKey: 'service-role-key',
  signingSecret: SECRET,
};

type RpcReply = { data: unknown; error: { message?: string; code?: string } | null };

function fakeClient(answer: (fn: string) => RpcReply | Promise<RpcReply> = () => ({
  data: { status: 'invoiced', invoice_no: 'INV-0000001', review_reason: null },
  error: null,
})) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client: RpcClient = {
    rpc(fn, args) {
      calls.push({ fn, args });
      return Promise.resolve(answer(fn));
    },
  };
  return { calls, client };
}

const run = (req: Request, client: RpcClient = fakeClient().client, load: () => OrderConfig = () => config) =>
  handleOrder(req, { loadConfig: load, makeClient: () => client, now: () => NOW_MS });

async function signed(
  body: unknown,
  opts: { timestamp?: number; secret?: string; headers?: Record<string, string>; method?: string } = {},
): Promise<Request> {
  const raw = typeof body === 'string' || body instanceof Uint8Array ? body as string | Uint8Array<ArrayBuffer> : JSON.stringify(body);
  const timestamp = opts.timestamp ?? NOW_S;
  return new Request(URL, {
    method: opts.method ?? 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-energia-timestamp': String(timestamp),
      'x-energia-signature': await signBody(opts.secret ?? SECRET, timestamp, raw),
      ...(opts.headers ?? {}),
    },
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

Deno.test('a paid order goes to web_order_paid and the answer comes back', async () => {
  const { calls, client } = fakeClient();
  const response = await run(await signed({ type: 'paid', order: paidOrder() }), client);

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { ok: true, status: 'invoiced', invoice_no: 'INV-0000001', review_reason: null });
  assertEquals(calls, [{ fn: 'web_order_paid', args: { p_order: paidOrder() } }]);
  assertEquals(response.headers.get('Cache-Control'), 'no-store');
});

Deno.test('a names order goes to web_order_names', async () => {
  const { calls, client } = fakeClient(() => ({
    data: { status: 'needs_review', invoice_no: null, review_reason: 'phone_matches_2_customers' },
    error: null,
  }));
  const response = await run(await signed({ type: 'names', order: namesOrder() }), client);

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { ok: true, status: 'needs_review', invoice_no: null, review_reason: 'phone_matches_2_customers' });
  assertEquals(calls, [{ fn: 'web_order_names', args: { p_order: namesOrder() } }]);
});

Deno.test('what reaches the database is the whitelisted, trimmed order', async () => {
  const { calls, client } = fakeClient();
  const order = { ...paidOrder(), buyer: { name: ' Guest One ', email: '', phone: '+65 9123 0001' } };
  await run(await signed({ type: 'paid', order }), client);
  assertEquals((calls[0].args.p_order as { buyer: unknown }).buyer, { name: 'Guest One', email: null, phone: '+65 9123 0001' });
});

Deno.test('every signature failure is one 401 and never reaches the database', async () => {
  const body = { type: 'paid', order: paidOrder() };
  const raw = JSON.stringify(body);
  const good = await signed(body);
  const requests = [
    await signed(body, { secret: 'another-secret' }),
    await signed(body, { timestamp: NOW_S - 301 }),
    await signed(body, { timestamp: NOW_S + 61 }),
    await signed(body, { headers: { 'x-energia-signature': 'v1=abc' } }),
    await signed(body, { headers: { 'x-energia-timestamp': 'soon' } }),
    new Request(URL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: raw }),
    // A valid signature moved onto a different body.
    new Request(URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-energia-timestamp': good.headers.get('x-energia-timestamp')!,
        'x-energia-signature': good.headers.get('x-energia-signature')!,
      },
      body: raw.replace('"quantity":2', '"quantity":9'),
    }),
  ];
  for (const [i, req] of requests.entries()) {
    const { calls, client } = fakeClient();
    const response = await run(req, client);
    assertEquals(response.status, 401, `request ${i}`);
    assertEquals(await response.json(), { ok: false, error: 'bad_signature' });
    assertEquals(calls.length, 0);
  }
});

Deno.test('an unsigned body is never parsed', async () => {
  // Not JSON and not signed: the answer is the signature, not the syntax.
  const response = await run(await signed('{not json', { secret: 'another-secret' }));
  assertEquals(response.status, 401);
});

Deno.test('a signed body is then held to the whitelist', async () => {
  const { calls, client } = fakeClient();
  const extra = await run(await signed({ type: 'paid', order: { ...paidOrder(), discount: 100 } }), client);
  assertEquals(extra.status, 400);
  assertEquals(await extra.json(), { ok: false, error: 'invalid_request', field: 'order.discount' });

  const broken = await run(await signed('{"type":"paid",'), client);
  assertEquals(broken.status, 400);
  assertEquals((await broken.json()).error, 'invalid_json');

  const notUtf8 = await run(await signed(new Uint8Array([0x7b, 0xff, 0x7d])), client);
  assertEquals(notUtf8.status, 400);
  assertEquals(calls.length, 0);
});

Deno.test('the envelope: POST, JSON, at most 16 KB', async () => {
  const body = { type: 'paid', order: paidOrder() };
  assertEquals((await run(new Request(URL, { method: 'GET' }))).status, 405);
  assertEquals((await run(await signed(body, { headers: { 'Content-Type': 'text/plain' } }))).status, 415);

  const big = JSON.stringify({ ...body, pad: 'x'.repeat(MAX_BODY_BYTES) });
  assertEquals((await run(await signed(big))).status, 413);
  // Content-Length can lie; the read itself is capped.
  const stream = new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode(big)); c.close(); } });
  const lying = new Request(URL, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: stream });
  assertEquals((await run(lying)).status, 413);
});

Deno.test('database and network failures ask for a retry', async () => {
  const failures: Array<(fn: string) => RpcReply | Promise<RpcReply>> = [
    () => ({ data: null, error: { message: 'canceling statement due to statement timeout', code: '57014' } }),
    () => ({ data: null, error: { message: 'TypeError: fetch failed', code: '' } }),
    () => Promise.reject(new Error('connection reset')),
    () => ({ data: { status: 'maybe' }, error: null }),
    () => ({ data: null, error: null }),
    // Only web_order_names answers not_found; from web_order_paid it is unexpected.
    () => ({ data: { status: 'not_found', invoice_no: null, review_reason: null }, error: null }),
  ];
  for (const [i, answer] of failures.entries()) {
    const response = await run(await signed({ type: 'paid', order: paidOrder() }), fakeClient(answer).client);
    assertEquals(response.status, 503, `failure ${i}`);
    assertEquals(await response.json(), { ok: false, error: 'retry' });
  }
});

Deno.test('text the database cannot store is refused before the database, not retried', async () => {
  for (const escape of ['\\u0000', '\\ud800', '\\udc00']) {
    const { calls, client } = fakeClient();
    // As it arrives: a JSON escape, plain ASCII, so valid UTF-8 and correctly signed.
    const raw = JSON.stringify({ type: 'paid', order: paidOrder() }).replace('"name":"Guest One"', `"name":"Guest${escape}One"`);
    assert(raw.includes(escape));
    let response: Response | undefined;
    const logs = await logsOf(async () => {
      response = await run(await signed(raw), client);
    });

    assertEquals(response!.status, 400, escape);
    assertEquals(await response!.json(), { ok: false, error: 'invalid_request', field: 'order.buyer.name' });
    assertEquals(calls.length, 0);
    assertFalse(logs.includes('Guest'), `log mentions the name (${escape})`);
  }
});

Deno.test('a data exception from the database is a 400 invalid_request, not a retry', async () => {
  // 22P05 untranslatable_character, 22P02 invalid_text_representation,
  // 22001 string_data_right_truncation, 22003 numeric_value_out_of_range, 22007 invalid_datetime_format.
  for (const code of ['22P05', '22P02', '22001', '22003', '22007']) {
    const { calls, client } = fakeClient(() => ({
      data: null,
      error: { message: 'unsupported Unicode escape sequence near Guest One, +65 9123 0001, guest.one@tests.invalid', code },
    }));
    let response: Response | undefined;
    const logs = await logsOf(async () => {
      response = await run(await signed({ type: 'names', order: namesOrder() }), client);
    });

    assertEquals(response!.status, 400, code);
    assertEquals(await response!.json(), { ok: false, error: 'invalid_request', field: 'order' });
    assertEquals(calls.length, 1);
    // The code, never the message: it can quote the value it refused.
    assert(logs.includes('"event":"web_order.invalid_request"'), code);
    assert(logs.includes(`"code":"${code}"`), code);
    assert(logs.includes('"field":"order"'), code);
    assert(logs.includes(SESSION_ID), code);
    assertFalse(logs.includes('web_order.retry'), code);
    for (const personal of ['Unicode', 'Guest', 'guest.one', 'tests.invalid', '9123']) {
      assertFalse(logs.includes(personal), `log mentions ${personal} (${code})`);
    }
  }

  // Only class 22, as a whole SQLSTATE: every other database error is still a retry.
  for (const code of ['23505', '40001', '57014', 'P0001', '42883', '2200', '220001', 'PGRST116', '']) {
    const client = fakeClient(() => ({ data: null, error: { message: 'refused', code } })).client;
    const response = await run(await signed({ type: 'paid', order: paidOrder() }), client);
    assertEquals(response.status, 503, code);
    assertEquals(await response.json(), { ok: false, error: 'retry' });
  }
});

Deno.test('names that arrive before their paid order are a 409 not_found, not a retry', async () => {
  const { calls, client } = fakeClient(() => ({ data: { status: 'not_found', invoice_no: null, review_reason: null }, error: null }));
  let response: Response | undefined;
  const logs = await logsOf(async () => {
    response = await run(await signed({ type: 'names', order: namesOrder() }), client);
  });

  assertEquals(response!.status, 409);
  assertEquals(await response!.json(), { ok: false, error: 'not_found' });
  assertEquals(calls, [{ fn: 'web_order_names', args: { p_order: namesOrder() } }]);
  // Logged as the ordering race it is, not as a database fault.
  assert(logs.includes('"event":"web_order.names_before_paid"'));
  assert(logs.includes(SESSION_ID));
  assertFalse(logs.includes('web_order.retry'));
  for (const personal of ['Guest', 'tests.invalid', '9123']) assertFalse(logs.includes(personal), `log mentions ${personal}`);
});

Deno.test('logs carry the type, session, status and timing, and nothing about the people', async () => {
  const leaky = fakeClient(() => ({
    data: null,
    error: { message: 'duplicate key: Key (phone)=(+65 9123 0001) guest.one@tests.invalid', code: '23505' },
  }));
  const logs = await logsOf(async () => {
    await run(await signed({ type: 'paid', order: paidOrder() }));
    await run(await signed({ type: 'names', order: namesOrder() }));
    await run(await signed({ type: 'paid', order: paidOrder() }), leaky.client);
    await run(await signed({ type: 'names', order: { ...namesOrder(), extra: 'Guest Two' } }));
    await run(await signed({ type: 'paid', order: paidOrder() }, { secret: 'another-secret' }));
  });

  assert(logs.includes(SESSION_ID));
  assert(logs.includes('"status":"invoiced"'));
  assert(logs.includes('"code":"23505"'));
  assert(logs.includes('"reason":"mismatch"'));
  for (const personal of ['Guest', 'guest.one', 'tests.invalid', '9123', SECRET]) {
    assertFalse(logs.includes(personal), `log mentions ${personal}`);
  }
});

// ---------------------------------------------------------------------------
// 380: staff-link registrations, the sync and the staff list
// ---------------------------------------------------------------------------

Deno.test('a staff-link registration goes to web_order_door, and dismissed is an answer it may give', async () => {
  for (const status of ['recorded', 'needs_review', 'invoiced', 'dismissed', 'refused']) {
    const { calls, client } = fakeClient(() => ({ data: { status, invoice_no: null, review_reason: null }, error: null }));
    const response = await run(await signed({ type: 'door', order: doorOrder() }), client);
    assertEquals(response.status, 200, status);
    assertEquals(await response.json(), { ok: true, status, invoice_no: null, review_reason: null });
    assertEquals(calls, [{ fn: 'web_order_door', args: { p_order: doorOrder() } }]);
  }
  // Only a staff-link registration can be dismissed: from web_order_paid it is unexpected.
  const odd = fakeClient(() => ({ data: { status: 'dismissed', invoice_no: null, review_reason: null }, error: null }));
  assertEquals((await run(await signed({ type: 'paid', order: paidOrder() }), odd.client)).status, 503);
});

Deno.test('a staff-link registration is signed and whitelisted like an order', async () => {
  const { calls, client } = fakeClient();
  assertEquals((await run(await signed({ type: 'door', order: doorOrder() }, { secret: 'another-secret' }), client)).status, 401);
  const extra = await run(await signed({ type: 'door', order: { ...doorOrder(), discount: 100 } }), client);
  assertEquals(extra.status, 400);
  assertEquals(await extra.json(), { ok: false, error: 'invalid_request', field: 'order.discount' });
  assertEquals(calls.length, 0);
});

const SYNC_OK = {
  status: 'ok',
  event: { name: 'Test Event', days: ['2026-10-19', '2026-10-20'] },
  orders: [{ order_id: OFF_ID, provider: 'door', status: 'invoiced', invoice_no: 'INV-2026-0001', buyer_name: 'Guest One',
             buyer_phone: '+65 9123 0001', people: [{ position: 1, name: 'Guest One', phone: '+65 9123 0001' }] }],
  counter: [{ invoice_no: 'INV-2026-0002', customer_name: 'Guest Two', phone: '+65 9123 0002', people: [] }],
  // 382: the event's free guests.
  free: [{ order_id: 'FREE-1A2B3C4D', name: 'Guest Three', phone: '+65 9123 0003', email: 'guest.three@tests.invalid',
           days: ['2026-10-19'], status: 'registered', registered_by: 'Staff A', notes: 'VEG', date: '2026-10-02' }],
};

Deno.test('a sync goes to web_order_sync with the channel, and its answer comes back', async () => {
  const { calls, client } = fakeClient(() => ({ data: { ...SYNC_OK, extra: 'dropped' }, error: null }));
  let response: Response | undefined;
  const logs = await logsOf(async () => {
    response = await run(await signed({ type: 'sync', channel: 'alaric-birthday-2026' }), client);
  });
  assertEquals(response!.status, 200);
  assertEquals(await response!.json(), { ok: true, ...SYNC_OK });
  assertEquals(calls, [{ fn: 'web_order_sync', args: { p_channel: 'alaric-birthday-2026' } }]);
  // Counts, never the people.
  assert(logs.includes('"type":"sync"') && logs.includes('"channel":"alaric-birthday-2026"'));
  assert(logs.includes('"orders":1') && logs.includes('"counter":1') && logs.includes('"free":1') && logs.includes('"status":"ok"'));
  for (const personal of ['Guest', '9123', 'INV-2026', 'FREE-', 'guest.three', 'Staff A', 'VEG']) {
    assertFalse(logs.includes(personal), `log mentions ${personal}`);
  }
});

Deno.test('382: a database without the free guests sends none, and the website gets an empty list', async () => {
  const { free: _free, ...before382 } = SYNC_OK;
  const { client } = fakeClient(() => ({ data: before382, error: null }));
  let response: Response | undefined;
  const logs = await logsOf(async () => {
    response = await run(await signed({ type: 'sync', channel: 'alaric-birthday-2026' }), client);
  });
  assertEquals(response!.status, 200);
  assertEquals(await response!.json(), { ok: true, ...before382, free: [] });
  assert(logs.includes('"free":0'));
});

Deno.test('382: free guests that are not a list are a retry', async () => {
  for (const free of [null, {}, 'FREE-1A2B3C4D', 1, true]) {
    const { client } = fakeClient(() => ({ data: { ...SYNC_OK, free }, error: null }));
    const response = await run(await signed({ type: 'sync', channel: 'alaric-birthday-2026' }), client);
    assertEquals(response.status, 503, JSON.stringify(free));
  }
});

Deno.test('too soon and refused syncs carry nothing else; anything malformed is a retry', async () => {
  for (const status of ['too_soon', 'refused']) {
    const { client } = fakeClient(() => ({ data: { status, orders: [], free: SYNC_OK.free }, error: null }));
    const response = await run(await signed({ type: 'sync', channel: 'alaric-birthday-2026' }), client);
    assertEquals(response.status, 200);
    assertEquals(await response.json(), { ok: true, status });
  }
  for (const data of [{ status: 'ok', event: SYNC_OK.event, orders: [] }, { status: 'ok', event: [], orders: [], counter: [] },
                      { status: 'later' }, null, []]) {
    const { client } = fakeClient(() => ({ data, error: null }));
    const response = await run(await signed({ type: 'sync', channel: 'alaric-birthday-2026' }), client);
    assertEquals(response.status, 503, JSON.stringify(data));
  }
});

Deno.test('the staff list goes to web_order_staff, and comes back as ids and names only', async () => {
  const { calls, client } = fakeClient(() => ({
    data: { status: 'ok', staff: [{ id: 'a', name: 'Staff A', email: 'staff.a@tests.invalid' }, { id: 'b', name: 'Staff B' }] },
    error: null,
  }));
  let response: Response | undefined;
  const logs = await logsOf(async () => {
    response = await run(await signed({ type: 'staff', channel: 'alaric-birthday-2026' }), client);
  });
  assertEquals(response!.status, 200);
  assertEquals(await response!.json(), { ok: true, status: 'ok', staff: [{ id: 'a', name: 'Staff A' }, { id: 'b', name: 'Staff B' }] });
  assertEquals(calls, [{ fn: 'web_order_staff', args: { p_channel: 'alaric-birthday-2026' } }]);
  assert(logs.includes('"staff":2'));
  assertFalse(logs.includes('Staff A'));
  for (const data of [{ status: 'ok' }, { status: 'ok', staff: [{ id: 'a' }] }, { status: 'maybe', staff: [] }]) {
    const bad = fakeClient(() => ({ data, error: null }));
    assertEquals((await run(await signed({ type: 'staff', channel: 'alaric-birthday-2026' }), bad.client)).status, 503,
      JSON.stringify(data));
  }
});

Deno.test('sync and staff are signed requests too', async () => {
  for (const type of ['sync', 'staff']) {
    const { calls, client } = fakeClient();
    const response = await run(await signed({ type, channel: 'alaric-birthday-2026' }, { secret: 'another-secret' }), client);
    assertEquals(response.status, 401, type);
    assertEquals(calls.length, 0);
  }
});

Deno.test('a staff-link registration\'s logs carry its OFF id and status, nothing about the people', async () => {
  const logs = await logsOf(async () => {
    await run(await signed({ type: 'door', order: doorOrder() }));
    const leaky = fakeClient(() => ({ data: null, error: { message: 'Key (phone)=(+65 9123 0001)', code: '23505' } }));
    await run(await signed({ type: 'door', order: doorOrder() }), leaky.client);
  });
  assert(logs.includes(OFF_ID));
  assert(logs.includes('"type":"door"'));
  for (const personal of ['Guest', 'guest.one', '9123', 'PayNow 0001']) assertFalse(logs.includes(personal), `log mentions ${personal}`);
});

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const NAMES = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEY', 'WEB_ORDER_SIGNING_SECRET'];

async function withEnv<T>(values: Record<string, string>, fn: () => T | Promise<T>): Promise<T> {
  const saved = new Map(NAMES.map(n => [n, Deno.env.get(n)]));
  for (const name of NAMES) Deno.env.delete(name);
  for (const [k, v] of Object.entries(values)) Deno.env.set(k, v);
  try { return await fn(); } finally {
    for (const name of NAMES) Deno.env.delete(name);
    for (const [k, v] of saved) if (v !== undefined) Deno.env.set(k, v);
  }
}

Deno.test('without the signing secret the function answers 503 not_configured', async () => {
  await withEnv({ SUPABASE_URL: config.supabaseUrl, SUPABASE_SERVICE_ROLE_KEY: 'service-role-key' }, async () => {
    const error = assertThrows(() => loadOrderConfig(), MissingConfigError) as MissingConfigError;
    assertEquals(error.names, ['WEB_ORDER_SIGNING_SECRET']);

    const { calls, client } = fakeClient();
    const response = await run(await signed({ type: 'paid', order: paidOrder() }), client, loadOrderConfig);
    assertEquals(response.status, 503);
    assertEquals(await response.json(), { ok: false, error: 'not_configured' });
    assertEquals(calls.length, 0);
  });
});

Deno.test('either service-role key name works, and the secret is read from the environment', async () => {
  await withEnv({
    SUPABASE_URL: 'https://project.supabase.co/',
    SUPABASE_SECRET_KEY: 'sb_secret_test',
    WEB_ORDER_SIGNING_SECRET: SECRET,
  }, async () => {
    assertEquals(loadOrderConfig(), { supabaseUrl: 'https://project.supabase.co', serviceRoleKey: 'sb_secret_test', signingSecret: SECRET });
    const response = await run(await signed({ type: 'paid', order: paidOrder() }), fakeClient().client, loadOrderConfig);
    assertEquals(response.status, 200);
  });
});
