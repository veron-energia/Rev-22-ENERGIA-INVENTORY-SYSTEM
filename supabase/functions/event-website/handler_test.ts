// End to end through the handler with the database faked (436): the status
// codes are the website's retry signal (contract ERRORS), so each is pinned.

import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { handleRequest, type RpcClient } from './handler.ts';
import { loadEventWebsiteConfig, MissingConfigError, type EventWebsiteConfig } from './config.ts';
import { sha256Hex } from './keys.ts';
import { ERRORS, MAX_BODY_BYTES } from './contract.ts';
import { EVENT, LIVE_KEY, messages, REQUEST_ID, TOKEN_1, TOKEN_2 } from './fixtures.ts';

const NOW_MS = 1_790_000_000_000;
const NOW_S = NOW_MS / 1000;
const URL = 'https://project.supabase.co/functions/v1/event-website';
const config: EventWebsiteConfig = { supabaseUrl: 'https://project.supabase.co', serviceRoleKey: 'service-role-key' };

type RpcReply = { data: unknown; error: { message?: string; code?: string } | null };

function fakeClient(answer: (args: Record<string, unknown>) => RpcReply | Promise<RpcReply> = () => ({
  data: { ok: true, test: false, status: 'ok' }, error: null,
})) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client: RpcClient = {
    rpc(fn, args) {
      calls.push({ fn, args });
      return Promise.resolve(answer(args));
    },
  };
  return { calls, client };
}

const run = (req: Request, client: RpcClient = fakeClient().client, load: () => EventWebsiteConfig = () => config) =>
  handleRequest(req, { loadConfig: load, makeClient: () => client, now: () => NOW_MS });

function request(body: unknown, opts: { key?: string | null; timestamp?: string | null; requestId?: string | null;
  headers?: Record<string, string>; method?: string } = {}): Request {
  const headers: Record<string, string> = { 'Content-Type': 'application/json', ...(opts.headers ?? {}) };
  const key = opts.key === undefined ? LIVE_KEY : opts.key;
  if (key !== null) headers['x-energia-key'] = key;
  const ts = opts.timestamp === undefined ? String(NOW_S) : opts.timestamp;
  if (ts !== null) headers['x-energia-timestamp'] = ts;
  const rid = opts.requestId === undefined ? REQUEST_ID : opts.requestId;
  if (rid !== null) headers['x-energia-request-id'] = rid;
  return new Request(URL, {
    method: opts.method ?? 'POST',
    headers,
    body: opts.method === 'GET' ? undefined : (typeof body === 'string' ? body : JSON.stringify(body)),
  });
}

async function logsOf(fn: () => Promise<unknown>): Promise<string> {
  const lines: string[] = [];
  const original = console.log;
  console.log = (...args: unknown[]) => { lines.push(args.map(String).join(' ')); };
  try { await fn(); } finally { console.log = original; }
  return lines.join('\n');
}

Deno.test("a message goes to event_web_call with the key's hash, the request id, the type and the rebuilt body", async () => {
  const { calls, client } = fakeClient(() => ({ data: { ok: true, test: false, status: 'registered', people: [] }, error: null }));
  const m = messages();
  const response = await run(request(m.register), client);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { ok: true, test: false, status: 'registered', people: [] });
  assertEquals(calls, [{ fn: 'event_web_call', args: {
    p_key_hash: await sha256Hex(LIVE_KEY), p_request_id: REQUEST_ID, p_type: 'register', p_body: m.register } }]);
  assertEquals(response.headers.get('Cache-Control'), 'no-store');
});

Deno.test('a read needs no request id and sends none', async () => {
  const { calls, client } = fakeClient();
  const response = await run(request(messages().event_info, { requestId: null }), client);
  assertEquals(response.status, 200);
  assertEquals(calls[0].args.p_request_id, null);
  const again = fakeClient();
  await run(request(messages().sync), again.client);
  assertEquals(again.calls[0].args.p_request_id, null);
});

Deno.test('a write without a request id, or with a malformed one, is refused before the database', async () => {
  for (const [rid, body] of [[null, messages().vip_paid], ['not-a-uuid', messages().event_info],
    ['0B9A2F0E-3C4D-4E5F-8A6B-7C8D9E0F1A2B', messages().register]] as [string | null, unknown][]) {
    const { calls, client } = fakeClient();
    const response = await run(request(body, { requestId: rid }), client);
    assertEquals(response.status, 400);
    assertEquals(await response.json(), { ok: false, error: 'invalid_request', field: 'x-energia-request-id' });
    assertEquals(calls.length, 0);
  }
});

Deno.test('the envelope: POST, JSON, at most 16 KiB (even when Content-Length lies), UTF-8', async () => {
  assertEquals((await run(request(messages().event_info, { method: 'GET' }))).status, 405);
  assertEquals((await run(request(messages().event_info, { headers: { 'Content-Type': 'text/plain' } }))).status, 415);
  const big = JSON.stringify({ ...messages().event_info, pad: 'x'.repeat(MAX_BODY_BYTES) });
  assertEquals((await run(request(big))).status, 413);
  assertEquals((await run(request(big, { headers: { 'Content-Length': '10' } }))).status, 413);
  const bad = await run(request('{"type": "event_info"'));
  assertEquals([bad.status, (await bad.json()).error], [400, 'invalid_json']);
  const latin = await run(new Request(URL, { method: 'POST', body: new Uint8Array([0x7b, 0xff, 0x7d]),
    headers: { 'Content-Type': 'application/json', 'x-energia-key': LIVE_KEY, 'x-energia-timestamp': String(NOW_S) } }));
  assertEquals([latin.status, (await latin.json()).error], [400, 'invalid_json']);
});

Deno.test('the key: missing or malformed is bad_key (401) before anything is read from the database', async () => {
  for (const key of [null, 'evk_live_short', 'Bearer ' + LIVE_KEY]) {
    const { calls, client } = fakeClient();
    const response = await run(request(messages().event_info, { key }), client);
    assertEquals([response.status, await response.json()], [401, { ok: false, error: 'bad_key' }]);
    assertEquals(calls.length, 0);
  }
});

Deno.test('the timestamp: missing, malformed, more than 300 s old or 60 s ahead is bad_timestamp (401)', async () => {
  for (const ts of [null, 'yesterday', String(NOW_S - 301), String(NOW_S + 61)]) {
    const { calls, client } = fakeClient();
    const response = await run(request(messages().event_info, { timestamp: ts }), client);
    assertEquals([response.status, await response.json()], [401, { ok: false, error: 'bad_timestamp' }]);
    assertEquals(calls.length, 0);
  }
  assertEquals((await run(request(messages().event_info, { timestamp: String(NOW_S - 300) }))).status, 200);
});

Deno.test("a body outside the contract is invalid_request with the field's path", async () => {
  const { calls, client } = fakeClient();
  const response = await run(request({ ...messages().person, upgrade_token: 'nope' }), client);
  assertEquals([response.status, await response.json()], [400, { ok: false, error: 'invalid_request', field: 'upgrade_token' }]);
  assertEquals(calls.length, 0);
});

Deno.test("the database's refusals map to the contract's status codes", async () => {
  for (const [error, extra] of [['bad_key', {}], ['wrong_event', {}], ['request_conflict', {}],
    ['too_many_requests', { retry_after_seconds: 42 }], ['invalid_request', { field: 'type' }]] as [string, Record<string, unknown>][]) {
    const { client } = fakeClient(() => ({ data: { ok: false, error, ...extra }, error: null }));
    const response = await run(request(messages().vip_checkout), client);
    assertEquals(response.status, ERRORS[error as keyof typeof ERRORS].http, error);
    assertEquals(await response.json(), { ok: false, error, ...extra });
    if (error === 'too_many_requests') assertEquals(response.headers.get('Retry-After'), '42');
  }
});

Deno.test('a database error of class 22 is final (400, field body); any other, or none, is 503 retry', async () => {
  const data22 = fakeClient(() => ({ data: null, error: { code: '22P02', message: 'invalid input syntax for type uuid: "+61491570737"' } }));
  const r22 = await run(request(messages().vip_paid), data22.client);
  assertEquals([r22.status, await r22.json()], [400, { ok: false, error: 'invalid_request', field: 'body' }]);
  for (const reply of [{ data: null, error: { code: '40001' } }, { data: null, error: { code: '23505' } },
    { data: 'nonsense', error: null }, { data: { ok: false, error: 'something_new' }, error: null }]) {
    const { client } = fakeClient(() => reply as RpcReply);
    const response = await run(request(messages().vip_paid), client);
    assertEquals([response.status, await response.json()], [503, { ok: false, error: 'retry' }]);
  }
  const thrown: RpcClient = { rpc() { return Promise.reject(new Error('network down')); } };
  const response = await run(request(messages().vip_paid), thrown);
  assertEquals([response.status, await response.json()], [503, { ok: false, error: 'retry' }]);
});

Deno.test('without its database settings the function answers 503 not_configured', async () => {
  const response = await run(request(messages().event_info), fakeClient().client, () => { throw new MissingConfigError(['SUPABASE_URL']); });
  assertEquals([response.status, await response.json()], [503, { ok: false, error: 'not_configured' }]);
  assertEquals(ERRORS.not_configured.retry, true);
});

Deno.test('config: the service role from either variable; nothing else is needed', () => {
  const saved = { url: Deno.env.get('SUPABASE_URL'), key: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'), secret: Deno.env.get('SUPABASE_SECRET_KEY') };
  try {
    Deno.env.set('SUPABASE_URL', 'https://project.supabase.co/');
    Deno.env.delete('SUPABASE_SERVICE_ROLE_KEY');
    Deno.env.set('SUPABASE_SECRET_KEY', 'sb_secret_test');
    assertEquals(loadEventWebsiteConfig(), { supabaseUrl: 'https://project.supabase.co', serviceRoleKey: 'sb_secret_test' });
    Deno.env.delete('SUPABASE_SECRET_KEY');
    let missing: string[] = [];
    try { loadEventWebsiteConfig(); } catch (e) { if (e instanceof MissingConfigError) missing = e.names; }
    assertEquals(missing, ['SUPABASE_SERVICE_ROLE_KEY']);
  } finally {
    for (const [k, v] of [['SUPABASE_URL', saved.url], ['SUPABASE_SERVICE_ROLE_KEY', saved.key], ['SUPABASE_SECRET_KEY', saved.secret]] as [string, string | undefined][]) {
      if (v === undefined) Deno.env.delete(k); else Deno.env.set(k, v);
    }
  }
});

Deno.test('no value is ever logged: not the key, a name, phone, email, token or reference', async () => {
  const m = messages();
  const log = await logsOf(async () => {
    const { client } = fakeClient(() => ({ data: { ok: true, test: false, status: 'registered', people: [] }, error: null }));
    await run(request(m.register), client);
    await run(request(m.vip_transfer), client);
    await run(request({ ...m.register, registration: { ...m.register.registration, people: [{ ...m.register.registration.people[0], email: 'bad' }] } }), client);
    const e22 = fakeClient(() => ({ data: null, error: { code: '22P02', message: 'Ada Example +61491570737' } }));
    await run(request(m.vip_paid), e22.client);
  });
  for (const secret of [LIVE_KEY, 'Ada', 'Example', '+61491570737', 'ada@example.com', 'payer.one@example.com', TOKEN_1, 'PN 778899']) {
    assertFalse(log.includes(secret), `logged ${secret}`);
  }
  assert(log.includes('"event":"' + EVENT + '"'));
  assert(log.includes('REG-20261101-1A2B3C4D'));
  assert(log.includes('"field":"registration.people.0.email"'));
});

// Planning answers (round 7, 21 Oct 2026): a write like any other; the database answers per person.
Deno.test('planning_answers is a write: without a request id it is refused before the database; with one it reaches event_web_call as type planning_answers with the rebuilt body', async () => {
  const m = messages();
  const none = fakeClient();
  const refused = await run(request(m.planning_answers, { requestId: null }), none.client);
  assertEquals([refused.status, await refused.json()], [400, { ok: false, error: 'invalid_request', field: 'x-energia-request-id' }]);
  assertEquals(none.calls.length, 0);
  const { calls, client } = fakeClient(() => ({ data: { ok: true, test: false, status: 'ok', people: [] }, error: null }));
  const response = await run(request(m.planning_answers), client);
  assertEquals(response.status, 200);
  assertEquals(calls, [{ fn: 'event_web_call', args: {
    p_key_hash: await sha256Hex(LIVE_KEY), p_request_id: REQUEST_ID, p_type: 'planning_answers', p_body: m.planning_answers } }]);
});

Deno.test('no planning answer is ever logged: not the tokens, an allergy, the question, a talk title or another answer', async () => {
  const m = messages();
  const answer = { ok: true, test: false, status: 'ok', people: [
    { person_id: '6f1e2d3c-4b5a-4968-8776-655443322110', status: 'saved', reason: null,
      planning: { version: 1, answers: m.planning_answers.planning.people[0].answers, updated_at: '2026-11-01T02:01:05Z', updated_by: 'guest' } },
    { person_id: null, status: 'refused', reason: 'person_not_found', planning: null }] };
  const log = await logsOf(async () => {
    const { client } = fakeClient(() => ({ data: answer, error: null }));
    await run(request(m.planning_answers), client);
    const people = m.planning_answers.planning.people;
    await run(request({ ...m.planning_answers, planning: { ...m.planning_answers.planning,
      people: [{ ...people[1], answers: { ...people[1].answers, allergy_details: 'Peanuts'.repeat(20) } }] } }), client);
    const e22 = fakeClient(() => ({ data: null, error: { code: '22023', message: 'Peanuts: answers outside the contract' } }));
    await run(request(m.planning_answers), e22.client);
  });
  for (const secret of [TOKEN_1, TOKEN_2, 'Peanuts', 'Is it good to walk every day?', 'How long for?', 'Sleep better, stress less',
    'Caring for your eyes', 'Community centre notice', 'vegetarian', 'wheelchair', '6f1e2d3c']) {
    assertFalse(log.includes(secret), `logged ${secret}`);
  }
  assert(log.includes('"type":"planning_answers"'));
  assert(log.includes('"field":"planning.people.0.answers.allergy_details"'));
});

Deno.test("the database's per-person answer passes through as 200; closed too", async () => {
  const m = messages();
  const perPerson = { ok: true, test: false, status: 'ok', people: [
    { person_id: '6f1e2d3c-4b5a-4968-8776-655443322110', status: 'refused', reason: 'changed_meanwhile',
      planning: { version: 4, answers: m.planning_answers.planning.people[1].answers, updated_at: '2026-11-01T01:00:00Z', updated_by: 'staff' } },
    { person_id: '7a6b5c4d-3e2f-4a1b-8c9d-0e1f2a3b4c5d', status: 'test', reason: null,
      planning: { version: 1, answers: m.planning_answers.planning.people[0].answers, updated_at: '2026-11-01T02:01:05Z', updated_by: 'guest' } }] };
  for (const data of [perPerson, { ok: true, test: false, status: 'closed', reason: 'ended' },
    { ok: true, test: true, status: 'closed', reason: 'event_deleted' }]) {
    const { client } = fakeClient(() => ({ data, error: null }));
    const response = await run(request(m.planning_answers), client);
    assertEquals([response.status, await response.json()], [200, data]);
  }
});
