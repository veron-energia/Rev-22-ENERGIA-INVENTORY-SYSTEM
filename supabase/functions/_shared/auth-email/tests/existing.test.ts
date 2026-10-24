// 466 (the Owner, 24 Oct 2026): how the sign-up function reads the database's
// answer about an existing affiliate, and words the refusal the way the page
// does.

import { assertEquals, assertThrows } from 'jsr:@std/assert@1';
import {
  affiliateExistsMessage, EMAIL_HINT_RE, isEmailHint, NO_EXISTING_AFFILIATE, readExistingAffiliate,
} from '../existing.ts';
// The page's own words and hint rule (plain ESM, no SDK).
import {
  EMAIL_HINT_RE as PAGE_HINT_RE, signupExistingMessage,
} from '../../../../../src/lib/auth-email/client.mjs';

Deno.test('466: the database\'s answer is read strictly', () => {
  assertEquals(readExistingAffiliate({ matched: null, login_email: false, email_hint: null, affiliates: 0 }), NO_EXISTING_AFFILIATE);
  assertEquals(readExistingAffiliate({ matched: 'phone', login_email: false, email_hint: 's•••@rev22.com.sg', affiliates: 1 }),
    { matched: 'phone', loginEmail: false, emailHint: 's•••@rev22.com.sg' });
  assertEquals(readExistingAffiliate({ matched: 'phone', login_email: false, email_hint: null, affiliates: 2 }),
    { matched: 'phone', loginEmail: false, emailHint: null });
  assertEquals(readExistingAffiliate({ matched: 'email', login_email: true, email_hint: null, affiliates: 1 }),
    { matched: 'email', loginEmail: true, emailHint: null });
  assertEquals(readExistingAffiliate({ matched: 'email', login_email: false, email_hint: '•••@t466.example.com', affiliates: 1 }),
    { matched: 'email', loginEmail: false, emailHint: '•••@t466.example.com' });
  // A login email match never carries a hint; a phone never counts as the login email.
  assertEquals(readExistingAffiliate({ matched: 'email', login_email: true, email_hint: 'a•••@example.com' }).emailHint, null);
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

Deno.test('466: a hint that is not the mask is dropped, never shown', () => {
  for (const good of ['s•••@rev22.com.sg', '•••@example.com', 'a•••@sub.example.co.uk', '1•••@example.com']) {
    assertEquals(isEmailHint(good), true, good);
  }
  for (const bad of [
    'sam@example.com', 's•••@', '•••', 's••@example.com', 'sa•••@example.com', 's•••@Example.com',
    '<b>•••@example.com', 's•••@example.com <script>', ' s•••@example.com', 's•••@exa mple.com',
    '"•••@example.com', 's•••@-example.com', 'x'.repeat(300), null, 7,
  ]) {
    assertEquals(isEmailHint(bad), false, String(bad));
  }
  assertEquals(readExistingAffiliate({ matched: 'phone', login_email: false, email_hint: 'sam@example.com' }).emailHint, null);
});

Deno.test('466: the server and the page word a refusal the same, with the same hint rule', () => {
  assertEquals(EMAIL_HINT_RE.source, PAGE_HINT_RE.source);
  for (const hint of ['s•••@rev22.com.sg', null]) {
    assertEquals(affiliateExistsMessage('phone', hint), signupExistingMessage('affiliate_phone', hint));
    assertEquals(affiliateExistsMessage('email', hint), signupExistingMessage('affiliate_email', hint));
  }
  assertEquals(affiliateExistsMessage('phone', 's•••@rev22.com.sg'),
    'This phone number already has an Energia affiliate account, which signs in with s•••@rev22.com.sg. Sign in with that email, or reset your password if you have forgotten it.');
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
    { matched: 'phone', loginEmail: false, emailHint: 's•••@example.com' });
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
