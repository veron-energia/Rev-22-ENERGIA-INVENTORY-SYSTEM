// Changing a password as the user, and the notification that follows it.

import { assert, assertEquals, assertFalse, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  ACCEPT_NEEDS_LINK_MESSAGE, bearerToken, cameFromEmailLink, changeOwnPassword, checkCurrentPassword,
  currentPasswordRequiredMessage, EMAIL_LINK_METHODS, EMAIL_LINK_WINDOW_SECONDS, INVITATION_LINK_EXPIRED_MESSAGE,
  invitationLinkState, mayAcceptInvitation, readOwnAccount, tokenClaims,
} from '../password.ts';
import { validateOwnPasswordChange } from '../validate.ts';
import { SUPABASE_URL } from './support.ts';

const withAuth = (value: string) => new Request('https://x', { headers: { Authorization: value } });
const JWT = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1c2VyIn0.signature';

Deno.test('a user access token is recognised; a publishable key is not', () => {
  assertEquals(bearerToken(withAuth(`Bearer ${JWT}`)), JWT);
  assertEquals(bearerToken(withAuth(`bearer ${JWT}`)), JWT);
  // supabase-js sends the publishable key when there is no session. Treating it
  // as a user token would let an anonymous caller reach the change path.
  assertEquals(bearerToken(withAuth('Bearer sb_publishable_abc123')), null);
  assertEquals(bearerToken(withAuth('Bearer not-a-jwt')), null);
  assertEquals(bearerToken(withAuth('')), null);
  assertEquals(bearerToken(new Request('https://x')), null);
});

Deno.test('the change is made as the user, against the ordinary Auth endpoint', async () => {
  const seen: { url: string; init: RequestInit }[] = [];
  const fake: typeof fetch = (url, init) => {
    seen.push({ url: String(url), init: init as RequestInit });
    return Promise.resolve(new Response(JSON.stringify({
      id: 'user-uuid', email: 'ada@example.com', updated_at: '2026-09-08T04:05:06Z',
      user_metadata: { first_name: 'Ada', last_name: 'Lovelace' },
    }), { status: 200, headers: { 'Content-Type': 'application/json' } }));
  };

  const result = await changeOwnPassword({
    supabaseUrl: SUPABASE_URL, apiKey: 'sb_publishable_test', accessToken: JWT, password: 'a-new-password',
  }, fake);

  assertEquals(result.status, 'ok');
  if (result.status === 'ok') {
    // The recipient comes from the account Supabase just updated, never from a body.
    assertEquals(result.email, 'ada@example.com');
    assertEquals(result.displayName, 'Ada Lovelace');
  }

  assertEquals(seen.length, 1);
  assertEquals(seen[0].url, `${SUPABASE_URL}/auth/v1/user`);
  assertEquals(seen[0].init.method, 'PUT', 'the user-scoped endpoint, not the admin one');
  assertFalse(seen[0].url.includes('/admin/'), 'an admin password write would bypass Supabase\'s own rules');
  const headers = seen[0].init.headers as Record<string, string>;
  assertEquals(headers.Authorization, `Bearer ${JWT}`, 'acting as the caller, with their own session');
  assertEquals(JSON.parse(String(seen[0].init.body)), { password: 'a-new-password' });
});

Deno.test('an expired or missing session is unauthorized, not a password failure', async () => {
  for (const status of [401, 403]) {
    const fake: typeof fetch = () => Promise.resolve(new Response('{"msg":"invalid claim"}', { status }));
    const result = await changeOwnPassword({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT, password: 'x'.repeat(12) }, fake);
    assertEquals(result.status, 'unauthorized');
  }
});

Deno.test("Supabase's own refusal wording reaches the account holder", async () => {
  const fake: typeof fetch = () => Promise.resolve(new Response(
    '{"msg":"New password should be different from the old password."}',
    { status: 422, headers: { 'Content-Type': 'application/json' } },
  ));
  const result = await changeOwnPassword({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT, password: 'x'.repeat(12) }, fake);
  assertEquals(result.status, 'rejected');
  if (result.status === 'rejected') assertStringIncludes(result.message, 'different from the old password');
});

Deno.test('an unreachable Auth service is an error, not a silent success', async () => {
  const fake: typeof fetch = () => Promise.reject(new TypeError('network down'));
  const result = await changeOwnPassword({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT, password: 'x'.repeat(12) }, fake);
  assertEquals(result.status, 'error');
});

Deno.test('a 200 that does not name the account is not treated as a change', async () => {
  const fake: typeof fetch = () => Promise.resolve(new Response('{}', { status: 200 }));
  const result = await changeOwnPassword({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT, password: 'x'.repeat(12) }, fake);
  // Without an address there is nobody to notify, so this must not read as success.
  assertEquals(result.status, 'error');
});

Deno.test('the request body carries the password, the current password when given, and nothing else', async () => {
  const seen: string[] = [];
  const fake: typeof fetch = (_url, init) => {
    seen.push(String((init as RequestInit).body));
    return Promise.resolve(new Response(JSON.stringify({ id: 'u', email: 'a@example.com' }), { status: 200 }));
  };
  await changeOwnPassword({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT, password: 'hunter22hunter' }, fake);
  await changeOwnPassword({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT, password: 'hunter22hunter', currentPassword: null }, fake);
  await changeOwnPassword({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT, password: 'hunter22hunter', currentPassword: '' }, fake);
  for (const sent of seen) assertEquals(Object.keys(JSON.parse(sent)), ['password']);
  // 429: with Supabase's "Require current password when updating" on, a
  // password session's change needs current_password, so it goes along.
  await changeOwnPassword({
    supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT, password: 'hunter22hunter', currentPassword: 'the-old-one',
  }, fake);
  const body = JSON.parse(seen[3]);
  assertEquals(body, { password: 'hunter22hunter', current_password: 'the-old-one' });
  for (const sent of seen.map(x => JSON.parse(x))) {
    assert(Object.keys(sent).every(k => k === 'password' || k === 'current_password'));
    assert(!('email' in sent) && !('role' in sent) && !('data' in sent));
  }
});

Deno.test('reading the caller\'s own account is a GET as the caller, and changes nothing', async () => {
  const seen: { url: string; init: RequestInit }[] = [];
  const fake: typeof fetch = (url, init) => {
    seen.push({ url: String(url), init: init as RequestInit });
    return Promise.resolve(new Response(JSON.stringify({ id: 'user-uuid', email: 'ada@example.com' }), { status: 200 }));
  };
  const result = await readOwnAccount({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT }, fake);
  assertEquals(result, { status: 'ok', userId: 'user-uuid', email: 'ada@example.com' });
  assertEquals(seen.length, 1);
  assertEquals(seen[0].url, `${SUPABASE_URL}/auth/v1/user`);
  assertEquals(seen[0].init.method, 'GET');
  assertEquals(seen[0].init.body, undefined, 'nothing is sent');
  assertEquals((seen[0].init.headers as Record<string, string>).Authorization, `Bearer ${JWT}`);
});

Deno.test('reading the account: an expired link is unauthorized; a failure is an error, never an account', async () => {
  for (const status of [401, 403]) {
    const fake: typeof fetch = () => Promise.resolve(new Response('{}', { status }));
    assertEquals((await readOwnAccount({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT }, fake)).status, 'unauthorized');
  }
  const down: typeof fetch = () => Promise.reject(new TypeError('network down'));
  assertEquals((await readOwnAccount({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT }, down)).status, 'error');
  const blank: typeof fetch = () => Promise.resolve(new Response('{}', { status: 200 }));
  assertEquals((await readOwnAccount({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT }, blank)).status, 'error');
});

// ── 429 (ADMIN-AUTH-9): a session alone does not change a password ──────────

const b64url = (v: unknown) => btoa(JSON.stringify(v)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const tokenWith = (claims: Record<string, unknown>) => `${b64url({ alg: 'ES256' })}.${b64url(claims)}.signature`;
const NOW = 1_791_000_000;

Deno.test('a session that came from a reset, magic or invitation link a few minutes ago may set the password', () => {
  for (const method of ['recovery', 'otp', 'magiclink', 'invite']) {
    assert(cameFromEmailLink(tokenWith({ amr: [{ method, timestamp: NOW - 60 }] }), NOW), method);
  }
  // Several entries: one that qualifies is enough.
  assert(cameFromEmailLink(tokenWith({
    amr: [{ method: 'password', timestamp: NOW - 5 }, { method: 'recovery', timestamp: NOW - 120 }],
  }), NOW));
});

Deno.test('a password sign-in, an old link, a signup confirmation or no claims at all need the current password', () => {
  assertFalse(cameFromEmailLink(tokenWith({ amr: [{ method: 'password', timestamp: NOW - 10 }] }), NOW));
  assertFalse(cameFromEmailLink(tokenWith({ amr: [{ method: 'recovery', timestamp: NOW - 31 * 60 }] }), NOW), 'over 30 minutes ago');
  assertFalse(cameFromEmailLink(tokenWith({ amr: [{ method: 'recovery', timestamp: NOW + 3600 }] }), NOW), 'a time ahead');
  assertFalse(cameFromEmailLink(tokenWith({ amr: [{ method: 'email/signup', timestamp: NOW - 10 }] }), NOW));
  assertFalse(cameFromEmailLink(tokenWith({ amr: [{ method: 'recovery', timestamp: String(NOW) }] }), NOW));
  assertFalse(cameFromEmailLink(tokenWith({ sub: 'x' }), NOW));
  assertFalse(cameFromEmailLink('not-a-token', NOW));
  assertFalse(cameFromEmailLink('a.!!!.c', NOW));
  assertEquals(tokenClaims(tokenWith({ sub: 'x', amr: [] })), { sub: 'x', amr: [] });
});

Deno.test('a link opened too long ago is told so and pointed at a new link; any other session is just asked', () => {
  const old = currentPasswordRequiredMessage(tokenWith({ amr: [{ method: 'recovery', timestamp: NOW - 31 * 60 }] }), NOW);
  assertStringIncludes(old, 'opened more than 30 minutes ago');
  assertStringIncludes(old, 'request a new link');
  assertStringIncludes(
    currentPasswordRequiredMessage(tokenWith({ amr: [{ method: 'invite', timestamp: NOW - 3 * 86400 }] }), NOW),
    'request a new link');
  for (const token of [
    tokenWith({ amr: [{ method: 'password', timestamp: NOW - 31 * 60 }] }),
    tokenWith({ amr: [{ method: 'recovery', timestamp: NOW + 3600 }] }),
    tokenWith({ sub: 'x' }),
    'not-a-token',
  ]) {
    assertEquals(currentPasswordRequiredMessage(token, NOW), 'Enter your current password to change it.');
  }
});

// 429: accepting an invitation needs a session opened from the emailed link.
// 18 Oct 2026 (the Owner): "30 minutes, like reset links", the window of
// auth-change-password. A removed member of staff invited again still has
// their old password, and their login's block is lifted when the invitation
// is set up, so a password sign-in may never accept.
Deno.test('an invitation is accepted only from a session opened from an emailed link in the last 30 minutes', () => {
  for (const method of ['recovery', 'otp', 'magiclink', 'invite']) {
    const opened = (ago: number) => tokenWith({ amr: [{ method, timestamp: NOW - ago }] });
    assert(mayAcceptInvitation(opened(0), NOW), `${method}, just now`);
    assert(mayAcceptInvitation(opened(60), NOW), `${method}, a minute ago`);
    assert(mayAcceptInvitation(opened(30 * 60), NOW), `${method}, exactly 30 minutes ago`);
    assertFalse(mayAcceptInvitation(opened(30 * 60 + 1), NOW), `${method}, just over 30 minutes ago`);
    assertFalse(mayAcceptInvitation(opened(5 * 86400), NOW), `${method}, days ago`);
    assertEquals(invitationLinkState(opened(60), NOW), 'open', method);
    assertEquals(invitationLinkState(opened(30 * 60 + 1), NOW), 'expired', method);
    assertEquals(invitationLinkState(opened(5 * 86400), NOW), 'expired', method);
  }
  assert(mayAcceptInvitation(tokenWith({
    amr: [{ method: 'password', timestamp: NOW - 5 }, { method: 'otp', timestamp: NOW - 10 * 60 }],
  }), NOW), 'one recent link entry is enough');
  assertEquals(invitationLinkState(tokenWith({
    amr: [{ method: 'password', timestamp: NOW - 5 }, { method: 'otp', timestamp: NOW - 3 * 3600 }],
  }), NOW), 'expired', 'a fresh password sign-in does not make an old link new');
});

Deno.test("the invitation window is auth-change-password's, from the same code", () => {
  assertEquals(EMAIL_LINK_WINDOW_SECONDS, 30 * 60);
  for (const method of EMAIL_LINK_METHODS) {
    for (const ago of [-3600, -61, -60, 0, 60, 29 * 60, 30 * 60, 30 * 60 + 1, 31 * 60, 3600, 3 * 86400]) {
      const token = tokenWith({ amr: [{ method, timestamp: NOW - ago }] });
      assertEquals(mayAcceptInvitation(token, NOW), cameFromEmailLink(token, NOW), `${method}, ${ago}s ago`);
    }
  }
  assertEquals(INVITATION_LINK_EXPIRED_MESSAGE, 'This invitation link has expired. Ask for a new invitation.');
});

Deno.test('a password sign-in cannot accept an invitation (the old password of someone invited back)', () => {
  for (const token of [
    tokenWith({ amr: [{ method: 'password', timestamp: NOW - 10 }] }),
    tokenWith({ amr: [{ method: 'email/signup', timestamp: NOW - 10 }] }),
    tokenWith({ amr: [{ method: 'otp', timestamp: NOW + 3600 }] }),
    tokenWith({ amr: [{ method: 'otp', timestamp: String(NOW) }] }),
    tokenWith({ sub: 'x' }),
    'not-a-token',
  ]) {
    assertFalse(mayAcceptInvitation(token, NOW));
    assertEquals(invitationLinkState(token, NOW), 'not_from_link');
  }
  assertStringIncludes(ACCEPT_NEEDS_LINK_MESSAGE, 'invitation link from your email');
});

Deno.test('the current password is checked by Supabase Auth with a sign-in, whose session is then closed', async () => {
  const seen: { url: string; init: RequestInit }[] = [];
  const fake: typeof fetch = (url, init) => {
    seen.push({ url: String(url), init: init as RequestInit });
    return Promise.resolve(String(url).includes('grant_type=password')
      ? new Response(JSON.stringify({ access_token: 'new-session-token' }), { status: 200 })
      : new Response(null, { status: 204 }));
  };
  const result = await checkCurrentPassword(
    { supabaseUrl: SUPABASE_URL, apiKey: 'k', email: 'ada@example.com', password: 'old-password' }, fake);
  assertEquals(result.status, 'ok');
  assertEquals(seen[0].url, `${SUPABASE_URL}/auth/v1/token?grant_type=password`);
  assertEquals(JSON.parse(String(seen[0].init.body)), { email: 'ada@example.com', password: 'old-password' });
  assertEquals(seen[1].url, `${SUPABASE_URL}/auth/v1/logout?scope=local`);
  assertEquals((seen[1].init.headers as Record<string, string>).Authorization, 'Bearer new-session-token');
});

Deno.test('a wrong current password, a rate limit and an outage are told apart', async () => {
  const answer = (status: number): typeof fetch =>
    () => Promise.resolve(new Response('{"error_code":"invalid_credentials"}', { status }));
  const args = { supabaseUrl: SUPABASE_URL, apiKey: 'k', email: 'ada@example.com', password: 'guess' };
  assertEquals((await checkCurrentPassword(args, answer(400))).status, 'wrong');
  assertEquals((await checkCurrentPassword(args, answer(429))).status, 'rate_limited');
  assertEquals((await checkCurrentPassword(args, answer(500))).status, 'error');
  assertEquals((await checkCurrentPassword(args, () => Promise.reject(new TypeError('down')))).status, 'error');
});

Deno.test('the body may carry the current password, and nothing else new', () => {
  assertEquals(validateOwnPasswordChange({ password: 'longenough1' }),
    { ok: true, value: { password: 'longenough1', currentPassword: null } });
  assertEquals(validateOwnPasswordChange({ password: 'longenough1', current_password: 'old' }),
    { ok: true, value: { password: 'longenough1', currentPassword: 'old' } });
  assertEquals(validateOwnPasswordChange({ password: 'longenough1', current_password: '' }).ok, true);
  assertFalse(validateOwnPasswordChange({ password: 'longenough1', email: 'victim@example.com' }).ok);
  assertFalse(validateOwnPasswordChange({ password: 'longenough1', current_password: 42 }).ok);
  assertFalse(validateOwnPasswordChange({ password: 'short', current_password: 'old' }).ok);
});
