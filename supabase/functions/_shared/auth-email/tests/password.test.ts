// Changing a password as the user, and the notification that follows it.

import { assert, assertEquals, assertFalse, assertStringIncludes } from 'jsr:@std/assert@1';
import { bearerToken, changeOwnPassword } from '../password.ts';
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

Deno.test('the request body never carries anything but the password', async () => {
  const seen: string[] = [];
  const fake: typeof fetch = (_url, init) => {
    seen.push(String((init as RequestInit).body));
    return Promise.resolve(new Response(JSON.stringify({ id: 'u', email: 'a@b.co' }), { status: 200 }));
  };
  await changeOwnPassword({ supabaseUrl: SUPABASE_URL, apiKey: 'k', accessToken: JWT, password: 'hunter22hunter' }, fake);
  const body = JSON.parse(seen[0]);
  assertEquals(Object.keys(body), ['password']);
  assert(!('email' in body) && !('role' in body) && !('data' in body));
});
