// The hook refuses every email after a valid signature, and sends nothing.

import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { Webhook } from 'https://esm.sh/standardwebhooks@1.0.0';
import { handleHook, REFUSAL_MESSAGE } from './handler.ts';

const SECRET_B64 = btoa('test-hook-secret-0123456789abcdef');
const HOOK_SECRET = `v1,whsec_${SECRET_B64}`;
const URL = 'https://project.functions.supabase.co/auth-email-hook';
const ADDRESS = 'someone@example.test';
const LINK = 'https://project.supabase.co/auth/v1/verify?token=abc123&type=recovery';
const KINDS = ['signup', 'recovery', 'invite', 'magiclink', 'email_change', 'reauthentication'];

function signedRequest(kind: string, opts: { secret?: string; method?: string; id?: string } = {}): Request {
  const body = JSON.stringify({
    user: { email: ADDRESS },
    email_data: { token: '123456', token_hash: 'hash-abc', redirect_to: LINK, email_action_type: kind, site_url: LINK },
  });
  const id = opts.id ?? 'msg_test_1';
  const date = new Date();
  const sig = new Webhook(opts.secret ?? SECRET_B64).sign(id, date, body);
  return new Request(URL, {
    method: opts.method ?? 'POST',
    headers: {
      'Content-Type': 'application/json',
      'webhook-id': id,
      'webhook-timestamp': String(Math.floor(date.getTime() / 1000)),
      'webhook-signature': sig,
    },
    body: opts.method === 'GET' ? undefined : body,
  });
}

function run(req: Request, hookSecret = HOOK_SECRET) {
  const lines: string[] = [];
  const realFetch = globalThis.fetch;
  let fetchCalls = 0;
  globalThis.fetch = (() => {
    fetchCalls++;
    return Promise.reject(new Error('no network call allowed'));
  }) as typeof fetch;
  return handleHook(req, { hookSecret, log: (l) => lines.push(l) })
    .then(async (res) => ({ res, text: await res.text(), lines, fetchCalls }))
    .finally(() => {
      globalThis.fetch = realFetch;
    });
}

Deno.test('a bad signature is refused', async () => {
  const wrong = await run(signedRequest('recovery', { secret: btoa('some-other-secret-key-0123456789') }));
  assertEquals(wrong.res.status, 401);
  assertEquals(JSON.parse(wrong.text), { error: 'invalid_signature' });
  assertEquals(wrong.fetchCalls, 0);

  const missing = await run(new Request(URL, { method: 'POST', body: '{"email_data":{"email_action_type":"signup"}}' }));
  assertEquals(missing.res.status, 401);
  assertEquals(missing.fetchCalls, 0);
});

for (const kind of ['recovery', 'magiclink']) {
  Deno.test(`a valid signature with "${kind}" gets the documented success and nothing is sent`, async () => {
    const r = await run(signedRequest(kind));
    assertEquals(r.res.status, 200);
    assertEquals(r.res.headers.get('Content-Type'), 'application/json');
    assertEquals(JSON.parse(r.text), {});
    assertEquals(r.fetchCalls, 0);
    assertEquals(r.lines.length, 1);
    assertEquals(JSON.parse(r.lines[0]), { evt: 'auth_email_dropped', kind, request_id: 'msg_test_1' });
    assertFalse(r.lines[0].includes(ADDRESS));
  });
}

for (const kind of ['signup', 'invite', 'email_change', 'reauthentication']) {
  Deno.test(`a valid signature with "${kind}" is refused in the documented shape, with no network call`, async () => {
    const r = await run(signedRequest(kind));
    assertEquals(r.res.status, 403);
    assertEquals(r.res.headers.get('Content-Type'), 'application/json');
    assertEquals(JSON.parse(r.text), { error: { http_code: 403, message: REFUSAL_MESSAGE } });
    assertEquals(r.fetchCalls, 0);
    assertEquals(r.lines.length, 1);
    const line = JSON.parse(r.lines[0]);
    assertEquals(line, { evt: 'auth_email_refused', kind, request_id: 'msg_test_1' });
  });
}

Deno.test('an unknown kind is refused too and logged as "other"', async () => {
  const r = await run(signedRequest('something-new'));
  assertEquals(r.res.status, 403);
  assertEquals(JSON.parse(r.lines[0]).kind, 'other');
  assertEquals(r.fetchCalls, 0);
});

Deno.test('anything but POST is refused', async () => {
  for (const method of ['GET', 'PUT', 'DELETE']) {
    const r = await run(signedRequest('signup', { method }));
    assertEquals(r.res.status, 405);
    assertEquals(r.fetchCalls, 0);
  }
});

Deno.test('without SEND_EMAIL_HOOK_SECRET nothing is accepted', async () => {
  const r = await run(signedRequest('signup'), '');
  assertEquals(r.res.status, 500);
  assertEquals(r.fetchCalls, 0);
});

Deno.test('no log line carries an address, domain, link, token or code', async () => {
  const all: string[] = [];
  for (const kind of KINDS) all.push(...(await run(signedRequest(kind))).lines);
  all.push(...(await run(signedRequest('recovery', { secret: btoa('some-other-secret-key-0123456789') }))).lines);
  assert(all.length > 0);
  for (const line of all) {
    for (const bad of [ADDRESS, 'example.test', '@', 'http', 'supabase.co', 'abc123', '123456', 'hash-abc']) {
      assertFalse(line.includes(bad), `log line contains ${bad}`);
    }
  }
});

Deno.test('the file reads only SEND_EMAIL_HOOK_SECRET', async () => {
  const src = await Deno.readTextFile(new globalThis.URL('./index.ts', import.meta.url)) +
    await Deno.readTextFile(new globalThis.URL('./handler.ts', import.meta.url));
  const code = src.split('\n').filter((l) => !l.trimStart().startsWith('//')).join('\n');
  const names = [...code.matchAll(/Deno\.env\.get\('([A-Z_]+)'\)/g)].map((m) => m[1]);
  assertEquals(names, ['SEND_EMAIL_HOOK_SECRET']);
  assertFalse(code.includes('PABBLY'));
  assertFalse(code.includes('AUTH_EMAIL_TEST_RECIPIENT'));
  assertFalse(code.includes('fetch('));
});
