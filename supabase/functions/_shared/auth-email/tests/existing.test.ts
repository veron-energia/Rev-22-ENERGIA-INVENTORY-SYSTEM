// 466 (the Owner, 24 Oct 2026): how the sign-up function reads the database's
// answer about an existing affiliate, and words the refusal the way the page
// does.

import { assertEquals, assertThrows } from 'jsr:@std/assert@1';
import { affiliateExistsMessage, NO_EXISTING_AFFILIATE, readExistingAffiliate } from '../existing.ts';
// The page's own words (plain ESM, no SDK).
import { signupExistingMessage } from '../../../../../src/lib/auth-email/client.mjs';

Deno.test('466: the database\'s answer is read strictly, and its email_hint is ignored (security audit of 17 Nov 2026, L9)', () => {
  assertEquals(readExistingAffiliate({ matched: null, login_email: false, email_hint: null, affiliates: 0 }), NO_EXISTING_AFFILIATE);
  // The database still sends a masked hint; the server drops it.
  assertEquals(readExistingAffiliate({ matched: 'phone', login_email: false, email_hint: 's•••@example.com', affiliates: 1 }),
    { matched: 'phone', loginEmail: false });
  assertEquals(readExistingAffiliate({ matched: 'phone', login_email: false, email_hint: null, affiliates: 2 }),
    { matched: 'phone', loginEmail: false });
  assertEquals(readExistingAffiliate({ matched: 'email', login_email: true, email_hint: null, affiliates: 1 }),
    { matched: 'email', loginEmail: true });
  assertEquals(readExistingAffiliate({ matched: 'email', login_email: false, email_hint: '•••@t466.example.com', affiliates: 1 }),
    { matched: 'email', loginEmail: false });
  assertEquals(readExistingAffiliate({ matched: 'phone', login_email: false, email_hint: 'sam@example.com' }),
    { matched: 'phone', loginEmail: false }, 'not even a whole address is carried');
  // A phone never counts as the login email.
  assertEquals(readExistingAffiliate({ matched: 'phone', login_email: true, email_hint: null }).loginEmail, false);
});

Deno.test('466: an answer of the wrong shape is an error (the sign-up then makes nothing), never "no match"', () => {
  for (const bad of [null, undefined, 'phone', 42, [], { matched: 'name' }, { matched: true }, { matched: 'PHONE' },
    // a reply without the keys, or with login_email not true or false, is not "no match"
    {}, { error: 'x' }, { matched: undefined, login_email: false }, { login_email: false }, { matched: null },
    { matched: 'email' }, { matched: 'email', login_email: 'true' }, { matched: 'phone', login_email: null },
    { matched: 'name', login_email: false }]) {
    assertThrows(() => readExistingAffiliate(bad), Error, undefined, JSON.stringify(bad));
  }
});

Deno.test('466: the server and the page word a refusal the same, with no email in it (security audit of 17 Nov 2026, L9)', () => {
  assertEquals(affiliateExistsMessage('phone'), signupExistingMessage('affiliate_phone'));
  assertEquals(affiliateExistsMessage('email'), signupExistingMessage('affiliate_email'));
  assertEquals(affiliateExistsMessage('phone'),
    'This phone number already has an Energia affiliate account. Sign in with the email you used for it, or reset your password if you have forgotten it.');
  for (const m of [affiliateExistsMessage('phone'), affiliateExistsMessage('email')]) {
    assertEquals(/[•@]/.test(m), false, m);
  }
});

Deno.test('466: the live lookup asks affiliate_signup_existing with the phone, email, name and request id, and fails on an error', async () => {
  const { affiliateSignupExisting } = await import('../admin.ts');
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  // deno-lint-ignore no-explicit-any
  const admin = (reply: { data: unknown; error: { message: string } | null }): any => ({
    rpc: (fn: string, args: Record<string, unknown>) => { calls.push({ fn, args }); return Promise.resolve(reply); },
  });
  assertEquals(
    await affiliateSignupExisting(admin({ data: { matched: 'phone', login_email: false, email_hint: 's•••@example.com', affiliates: 1 }, error: null }),
      { email: 'ada@example.com', phone: '+6591234567', name: 'Ada Lovelace', requestId: '00000000-0000-4000-8000-000000000466' }),
    { matched: 'phone', loginEmail: false });
  assertEquals(calls, [{ fn: 'affiliate_signup_existing',
    args: { p_phone: '+6591234567', p_email: 'ada@example.com', p_name: 'Ada Lovelace',
            p_request_id: '00000000-0000-4000-8000-000000000466' } }]);
  let thrown = '';
  try {
    await affiliateSignupExisting(admin({ data: null, error: { message: 'permission denied' } }),
      { email: 'a@example.com', phone: '+6591234567', name: 'Ada Lovelace', requestId: '00000000-0000-4000-8000-000000000466' });
  } catch (error) { thrown = String(error); }
  assertEquals(thrown, 'Error: existing affiliate lookup failed: permission denied');
});
