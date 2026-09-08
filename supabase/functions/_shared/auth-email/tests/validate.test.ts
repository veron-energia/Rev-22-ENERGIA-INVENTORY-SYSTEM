// Input validation: what the endpoints accept, and — more importantly — what
// they refuse.

import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import {
  isEmailShaped, normalizeEmail, passwordProblem, cleanName,
  validateSignup, validateEmailOnly, validateRecovery, validatePasswordChange,
} from '../validate.ts';

const phone = (raw: string) => (/^\+65[3689]\d{7}$/.test(raw) ? raw : null);
const base = {
  first_name: 'Ada', last_name: 'Lovelace', phone: '+6591234567',
  email: 'Ada@Example.com', password: 'correct-horse-battery', terms_accepted: true,
};

Deno.test('email is normalized the way Supabase compares addresses', () => {
  assertEquals(normalizeEmail('  Ada@Example.COM '), 'ada@example.com');
  // Dots and plus tags are NOT stripped: Supabase treats them as distinct
  // addresses, and quietly merging them here would rate-limit the wrong account.
  assertEquals(normalizeEmail('a.b+tag@example.com'), 'a.b+tag@example.com');
});

Deno.test('addresses that could carry a header break are rejected', () => {
  assert(isEmailShaped('ada@example.com'));
  for (const bad of [
    'ada@example.com\nBcc: victim@example.com',
    'ada@example.com\r\nSubject: spam',
    'ada@example.com, victim@example.com',
    '"ada"@example.com',
    'ada<@example.com',
    'no-at-sign',
    '',
  ]) assertFalse(isEmailShaped(bad), `should reject: ${JSON.stringify(bad)}`);
});

Deno.test('password policy matches the affiliate form and bcrypt', () => {
  assertEquals(passwordProblem('12345678'), null);
  assert(passwordProblem('short12')?.includes('at least 8'));
  assert(passwordProblem(undefined)?.includes('required'));
  // 72 bytes is bcrypt's ceiling underneath Supabase; refuse rather than truncate.
  assertEquals(passwordProblem('a'.repeat(72)), null);
  assert(passwordProblem('a'.repeat(73))?.includes('72'));
  assert(passwordProblem('é'.repeat(40))?.includes('72'), 'byte length, not character length');
});

Deno.test('signup accepts a well-formed submission', () => {
  const result = validateSignup({ ...base }, phone);
  assert(result.ok);
  assertEquals(result.value.email, 'ada@example.com');
  assertEquals(result.value.phone, '+6591234567');
  assertEquals(result.value.firstName, 'Ada');
});

Deno.test('signup refuses smuggled fields rather than ignoring them', () => {
  for (const extra of [
    { role: 'owner' }, { subject: 'Anything' }, { html: '<b>hi</b>' },
    { redirect_to: 'https://evil.example' }, { to: 'victim@example.com' },
    { from_email: 'spoof@example.com' }, { app_metadata: { role: 'service_role' } },
  ]) {
    const result = validateSignup({ ...base, ...extra }, phone);
    assertFalse(result.ok, `should refuse ${Object.keys(extra)[0]}`);
    if (!result.ok) assertEquals(result.errors[0].field, Object.keys(extra)[0]);
  }
});

Deno.test('signup requires terms acceptance, and only a real true', () => {
  for (const value of [false, 'true', 1, undefined, null]) {
    const result = validateSignup({ ...base, terms_accepted: value }, phone);
    assertFalse(result.ok, `should refuse terms_accepted=${JSON.stringify(value)}`);
  }
});

Deno.test('signup requires a phone the shared rules accept', () => {
  const result = validateSignup({ ...base, phone: '12345' }, phone);
  assertFalse(result.ok);
  if (!result.ok) assertEquals(result.errors[0].field, 'phone');
});

Deno.test('names are collapsed and capped, never trusted as markup', () => {
  assertEquals(cleanName('  Ada   Byron  '), 'Ada Byron');
  assertEquals(cleanName('x'.repeat(200)).length, 80);
  assertEquals(cleanName(42), '');
});

Deno.test('resend takes an email and nothing else', () => {
  assert(validateEmailOnly({ email: 'a@b.co' }).ok);
  assertFalse(validateEmailOnly({ email: 'a@b.co', password: 'hunter22' }).ok);
  assertFalse(validateEmailOnly({}).ok);
});

Deno.test('recovery accepts only the two known flows and never a URL', () => {
  assert(validateRecovery({ email: 'a@b.co', flow: 'staff' }).ok);
  assert(validateRecovery({ email: 'a@b.co', flow: 'affiliate' }).ok);
  assertFalse(validateRecovery({ email: 'a@b.co', flow: 'admin' }).ok);
  assertFalse(validateRecovery({ email: 'a@b.co', flow: 'https://evil.example' }).ok);
  assertFalse(validateRecovery({ email: 'a@b.co', flow: 'staff', redirect_to: 'https://evil.example' }).ok);
  assertFalse(validateRecovery({ email: 'a@b.co' }).ok);
});

Deno.test('password change takes a password and nothing else', () => {
  assert(validatePasswordChange({ password: 'longenough1' }).ok);
  assertFalse(validatePasswordChange({ password: 'longenough1', email: 'victim@example.com' }).ok);
  assertFalse(validatePasswordChange({ password: 'short' }).ok);
});
