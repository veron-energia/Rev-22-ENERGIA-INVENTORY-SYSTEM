// Security audit of 17 Nov 2026, finding M6 (the user's decisions of 20 Nov 2026):
// the per-connection limit follows the /64, the overall ceilings refuse with the
// same 429, and each send takes a slot of the day's budget.
//
// The fake database below keeps the bucket counts in memory and refuses where
// the real one does: 10 sign-ups an hour per connection, 30 new logins an hour
// in all, 60 emails a day. The numbers themselves are the database's (531).
// Every address is made up.

import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { handlePublicRequest } from '../pipeline.ts';
import { recoveryEndpoint, signupEndpoint } from '../flows.ts';
import { take, takeSendSlot } from '../ratelimit.ts';
import {
  LOGIN_ID, allowAll, fakeAdmin, flowDeps, okLink, postRequest, recordingDeliver, testConfig, validSignupBody,
} from './support.ts';

// deno-lint-ignore no-explicit-any
const run = (req: Request, endpoint: any, admin: any, config = testConfig()) =>
  handlePublicRequest(req, endpoint, { loadConfig: () => config, makeAdmin: () => admin });

/** A database that counts: per-connection sign-ups, the overall ceilings. */
function countingAdmin(limits: { perIp?: number; signupAll?: number; sendAll?: number } = {}) {
  const perIp = new Map<string, number>();
  const used = { signup: 0, send: 0 };
  const admin = fakeAdmin({
    ...allowAll,
    auth_email_reserve: (args) => {
      if (args.p_action !== 'signup') return { allowed: true, retry_after_seconds: 0 };
      const key = String(args.p_ip_hash);
      const n = (perIp.get(key) ?? 0) + 1;
      if (n > (limits.perIp ?? 10)) return { allowed: false, retry_after_seconds: 1800, scope: 'ip' };
      perIp.set(key, n);
      return { allowed: true, retry_after_seconds: 0 };
    },
    auth_email_take: (args) => {
      const bucket = args.p_bucket as 'signup' | 'send';
      const cap = bucket === 'signup' ? (limits.signupAll ?? 30) : (limits.sendAll ?? 60);
      if (used[bucket] >= cap) return { allowed: false, retry_after_seconds: 3000, scope: 'all', action: bucket };
      used[bucket] += 1;
      return { allowed: true, retry_after_seconds: 0 };
    },
  });
  return { admin, used, perIp };
}

const signupFrom = (ip: string, n: number) =>
  postRequest({ ...validSignupBody, email: `person${n}@example.invalid` }, { headers: { 'cf-connecting-ip': ip } });

Deno.test('M6: 31 sign-ups from 31 IPv6 addresses in ONE /64 are refused after 10', async () => {
  const { admin } = countingAdmin();
  let created = 0;
  const endpoint = signupEndpoint(flowDeps({ createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u' }); } }));
  const statuses: number[] = [];
  for (let n = 0; n < 31; n++) {
    const ip = `2001:db8:aaaa:bbbb:${(n + 1).toString(16)}::${(n + 7).toString(16)}`;
    statuses.push((await run(signupFrom(ip, n), endpoint, admin)).status);
  }
  assertEquals(statuses.filter(s => s === 200).length, 10);
  assertEquals(statuses.filter(s => s === 429).length, 21);
  assertEquals(statuses.slice(0, 10).every(s => s === 200), true);
  assertEquals(created, 10);
});

Deno.test('M6: 11 different /64s are not limited per connection', async () => {
  const { admin } = countingAdmin();
  const endpoint = signupEndpoint(flowDeps());
  for (let n = 0; n < 11; n++) {
    const response = await run(signupFrom(`2001:db8:${(n + 1).toString(16)}::1`, n), endpoint, admin);
    assertEquals(response.status, 200, `sign-up ${n}`);
  }
});

Deno.test('M6: a forged x-forwarded-for does not earn a fresh connection', async () => {
  const { admin } = countingAdmin();
  const endpoint = signupEndpoint(flowDeps());
  const statuses: number[] = [];
  for (let n = 0; n < 12; n++) {
    const req = postRequest({ ...validSignupBody, email: `forged${n}@example.invalid` },
      { headers: { 'cf-connecting-ip': '203.0.113.50', 'x-forwarded-for': `198.51.100.${n}` } });
    statuses.push((await run(req, endpoint, admin)).status);
  }
  assertEquals(statuses.filter(s => s === 429).length, 2);
});

Deno.test('M6: no cf-connecting-ip shares one bucket ("unknown") and is limited, not free', async () => {
  const { admin } = countingAdmin();
  const endpoint = signupEndpoint(flowDeps());
  const statuses: number[] = [];
  for (let n = 0; n < 12; n++) {
    statuses.push((await run(postRequest({ ...validSignupBody, email: `anon${n}@example.invalid` }), endpoint, admin)).status);
  }
  assertEquals(statuses.filter(s => s === 429).length, 2);
});

Deno.test('M6: 31 sign-ups from 31 connections: the 31st is refused by the overall ceiling, and makes no login', async () => {
  const { admin, used } = countingAdmin();
  let created = 0;
  const endpoint = signupEndpoint(flowDeps({ createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u' }); } }));
  let last: Response | null = null;
  for (let n = 0; n < 31; n++) last = await run(signupFrom(`203.0.113.${n + 1}`, n), endpoint, admin);
  assertEquals(created, 30);
  assertEquals(used.signup, 30);
  assertEquals(last!.status, 429);
  assertEquals(last!.headers.get('Retry-After'), '3000');
  const body = await last!.json();
  assertEquals(body.error, 'rate_limited');
  assertFalse(JSON.stringify(body).includes('all'), 'which bucket ran out stays server-side');
  const outcomes = admin.calls.filter(c => c.fn === 'auth_email_record_outcome').map(c => c.args.p_detail);
  assert(outcomes.includes('rate_limited:signup'), 'recorded as suppressed with the bucket named');
});

Deno.test('M6: the overall slot is taken after the duplicate checks, so a duplicate try uses none', async () => {
  const { admin, used } = countingAdmin();
  const endpoint = signupEndpoint(flowDeps({ accountState: () => Promise.resolve('confirmed') }));
  const response = await run(signupFrom('203.0.113.9', 1), endpoint, admin);
  assertEquals(response.status, 409);
  assertEquals(used.signup, 0);
});

Deno.test('M6: a refused reserve with scope "all" is answered like any other refusal (sign-up)', async () => {
  const admin = fakeAdmin({
    auth_email_reserve: () => ({ allowed: false, retry_after_seconds: 600, scope: 'all', action: 'signup' }),
    auth_email_record_outcome: () => null,
  });
  const response = await run(signupFrom('203.0.113.77', 1), signupEndpoint(flowDeps()), admin);
  assertEquals(response.status, 429);
  assertEquals(response.headers.get('Retry-After'), '600');
  assertEquals((await response.json()).error, 'rate_limited');
});

const refusingTake = () => fakeAdmin({
  ...allowAll,
  auth_email_take: () => ({ allowed: false, retry_after_seconds: 1200, scope: 'all', action: 'send' }),
});

Deno.test('M6: a refused take on recovery is answered silently, exactly like an unknown address', async () => {
  for (const action of ['send', 'send_staff', 'email_day']) {
    const { sent, deliver } = recordingDeliver();
    const admin = fakeAdmin({ ...allowAll, auth_email_take: () => ({ allowed: false, retry_after_seconds: 1200, scope: 'all', action }) });
    const response = await run(postRequest({ email: 'a@example.invalid', flow: 'affiliate' }),
      recoveryEndpoint(flowDeps({ deliver, generateRecoveryLink: () => Promise.resolve(okLink('a@example.invalid')) })), admin);
    const unknown = await run(postRequest({ email: 'b@example.invalid', flow: 'affiliate' }),
      recoveryEndpoint(flowDeps({ deliver, generateRecoveryLink: () => Promise.resolve({ status: 'no_such_user' }) })), fakeAdmin(allowAll));
    assertEquals(response.status, unknown.status);
    assertEquals(response.status, 200);
    assertEquals(response.headers.get('Retry-After'), null);
    const a = await response.json(); const b = await unknown.json();
    delete a.request_id; delete b.request_id;
    assertEquals(a, b, 'an address with a login and one without answer alike');
    assertEquals(sent.length, 0);
    assertEquals(admin.calls.filter(c => c.fn === 'auth_email_record_outcome').at(-1)?.args.p_detail, `${action}_full`);
  }
});

Deno.test('M6: recovery takes its slot by the typed address BEFORE any link is made; a forged flow never picks the pool', async () => {
  for (const flow of ['staff', 'affiliate'] as const) {
    const order: string[] = [];
    const { sent, deliver } = recordingDeliver();
    const admin = fakeAdmin({ ...allowAll, auth_email_take: () => { order.push('take'); return { allowed: true, retry_after_seconds: 0 }; } });
    const response = await run(postRequest({ email: 'A@Example.invalid', flow }),
      recoveryEndpoint(flowDeps({ deliver, generateRecoveryLink: () => { order.push('link'); return Promise.resolve(okLink('a@example.invalid')); } })), admin);
    assertEquals(response.status, 200);
    assertEquals(sent.length, 1);
    assertEquals(order, ['take', 'link'], 'the slot first, then the link');
    assertEquals(admin.calls.filter(c => c.fn === 'auth_email_take').map(c => c.args),
      [{ p_bucket: 'send', p_lookup_email: 'a@example.invalid' }], `flow=${flow}: only the normalised address, no flow, no hash, no id`);
  }
});

Deno.test('M6: a full budget on recovery never makes a link', async () => {
  for (const action of ['send', 'send_staff', 'email_day']) {
    let links = 0;
    const { sent, deliver } = recordingDeliver();
    const admin = fakeAdmin({ ...allowAll, auth_email_take: () => ({ allowed: false, retry_after_seconds: 900, scope: 'all', action }) });
    const response = await run(postRequest({ email: 'a@example.invalid', flow: 'affiliate' }),
      recoveryEndpoint(flowDeps({ deliver, generateRecoveryLink: () => { links += 1; return Promise.resolve(okLink('a@example.invalid')); } })), admin);
    assertEquals(response.status, 200);
    assertEquals(links, 0, `${action}: no new link that nobody receives`);
    assertEquals(sent.length, 0);
  }
});

Deno.test('M6: an unknown address on recovery: no link, no slot, the same answer as a full budget', async () => {
  let links = 0;
  const { sent, deliver } = recordingDeliver();
  const unknownAdmin = fakeAdmin({ ...allowAll, auth_email_take: () => ({ allowed: false, retry_after_seconds: 0, action: 'no_login' }) });
  const full = fakeAdmin({ ...allowAll, auth_email_take: () => ({ allowed: false, retry_after_seconds: 900, scope: 'all', action: 'send' }) });
  const endpoint = recoveryEndpoint(flowDeps({ deliver, generateRecoveryLink: () => { links += 1; return Promise.resolve(okLink()); } }));
  const a = await run(postRequest({ email: 'nobody@example.invalid', flow: 'affiliate' }), endpoint, unknownAdmin);
  const b = await run(postRequest({ email: 'a@example.invalid', flow: 'affiliate' }), endpoint, full);
  assertEquals(a.status, 200); assertEquals(b.status, 200);
  assertEquals(a.headers.get('Retry-After'), null); assertEquals(b.headers.get('Retry-After'), null);
  const ba = await a.json(); const bb = await b.json();
  delete ba.request_id; delete bb.request_id;
  assertEquals(ba, bb, 'identical bodies');
  assertEquals(links, 0);
  assertEquals(sent.length, 0);
  assertEquals(unknownAdmin.calls.filter(c => c.fn === 'auth_email_record_outcome').at(-1)?.args.p_detail, 'no_account');
  assertEquals(full.calls.filter(c => c.fn === 'auth_email_record_outcome').at(-1)?.args.p_detail, 'send_full');
});

Deno.test('M6: after an allowed take, a link that finds no login (a race) is suppressed as no_account', async () => {
  const { sent, deliver } = recordingDeliver();
  const response = await run(postRequest({ email: 'a@example.invalid', flow: 'affiliate' }),
    recoveryEndpoint(flowDeps({ deliver, generateRecoveryLink: () => Promise.resolve({ status: 'no_such_user' }) })), fakeAdmin(allowAll));
  assertEquals(response.status, 200);
  assertEquals(sent.length, 0);
});

Deno.test('M6: a take the database cannot answer fails closed with the 503 wording, nothing sent or made', async () => {
  const { sent, deliver } = recordingDeliver();
  let created = 0;
  const admin = fakeAdmin({ ...allowAll, auth_email_take: () => new Error('connection refused') });
  for (const [endpoint, body] of [
    [signupEndpoint(flowDeps({ createConfirmedSignup: () => { created += 1; return Promise.resolve({ status: 'created', userId: 'u' }); } })), validSignupBody],
    [recoveryEndpoint(flowDeps({ deliver })), { email: 'a@example.invalid', flow: 'staff' }],
  ] as const) {
    const response = await run(postRequest(body), endpoint, admin);
    assertEquals(response.status, 503);
    const text = await response.text();
    assertEquals(JSON.parse(text).error, 'temporarily_unavailable');
    assertFalse(text.includes('connection refused'));
  }
  assertEquals(created, 0);
  assertEquals(sent.length, 0);
});

Deno.test('M6: take() and takeSendSlot() read the database answer, and fail closed on a bad one', async () => {
  const ok = fakeAdmin({ auth_email_take: () => ({ allowed: true, retry_after_seconds: 0 }) });
  assertEquals((await take(ok, 'send')).allowed, true);
  assertEquals(ok.calls[0], { fn: 'auth_email_take', args: { p_bucket: 'send' } });
  assertEquals((await takeSendSlot(ok)).result, 'ok');
  const looked = fakeAdmin({ auth_email_take: () => ({ allowed: true, retry_after_seconds: 0 }) });
  await take(looked, 'send', { lookupEmail: 'a@example.invalid' });
  assertEquals(looked.calls[0].args, { p_bucket: 'send', p_lookup_email: 'a@example.invalid' });
  const keyed = fakeAdmin({ auth_email_take: () => ({ allowed: true, retry_after_seconds: 0 }) });
  await take(keyed, 'send', { emailHash: 'abc123', userId: LOGIN_ID });
  assertEquals(keyed.calls[0].args, { p_bucket: 'send', p_email_hash: 'abc123', p_user_id: LOGIN_ID });
  const login = fakeAdmin({ auth_email_take: () => ({ allowed: false, retry_after_seconds: 10, scope: 'email', action: 'email_day' }) });
  const refusedByLogin = await takeSendSlot(login, { emailHash: 'abc123' });
  assertEquals(refusedByLogin.result, 'full');
  assertEquals(refusedByLogin.action, 'email_day');

  const full = fakeAdmin({ auth_email_take: () => ({ allowed: false, retry_after_seconds: 90, scope: 'all', action: 'send' }) });
  assertEquals(await take(full, 'signup'), { allowed: false, retryAfterSeconds: 90, scope: 'all', action: 'send' });
  assertEquals(await takeSendSlot(full), { result: 'full', retryAfterSeconds: 90, action: 'send' });

  for (const bad of [new Error('down'), null, { nope: 1 }]) {
    const broken = fakeAdmin({ auth_email_take: () => bad });
    assertEquals((await takeSendSlot(broken)).result, 'unavailable');
  }
});

Deno.test('M6: the two senders outside the pipeline take a slot before they deliver', async () => {
  for (const path of ['../../../affiliate-details/index.ts', '../../../auth-change-password/index.ts']) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    const slot = source.indexOf('takeSendSlot(admin');
    assert(slot > 0, `${path} asks for a slot`);
    // affiliate-details orders its slot in details.ts (tested there); change-password inline.
    if (path.includes('change-password')) assert(source.indexOf('await deliver(config') > slot, `${path}: slot before deliver`);
  }
  // Staff invitations do not draw on the budget.
  for (const path of ['../../../admin-invite-user/index.ts', '../../../auth-accept-invitation/index.ts', '../invitations.ts']) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertFalse(source.includes('takeSend') || source.includes('auth_email_take') || /\btake\(/.test(source), `${path} must not take from the budget`);
  }
});

Deno.test('M6: no public endpoint issues a code or makes a link that verifies', async () => {
  for (const path of ['../flows.ts', '../admin.ts']) {
    const source = await Deno.readTextFile(new URL(path, import.meta.url));
    assertFalse(/magiclink|generateMagicLink|affiliateEmailNeedsVerification|affiliate_email_code_issue/.test(source), path);
  }
});
