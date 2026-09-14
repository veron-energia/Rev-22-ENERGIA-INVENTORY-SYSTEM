// The signup confirmation must not promise an email that will not be sent.
//
// The server answers signup identically for a new address and one that is
// already verified, and deliberately sends nothing in the second case. A screen
// that asserted "we've sent you a link" therefore left returning affiliates
// waiting for something that was never coming, with no other way forward.
//
// The wording has to do two things at once: state both possibilities so that
// nobody is stranded, and still never reveal which one applies.
import test from 'node:test';
import assert from 'node:assert/strict';
import { AUTH_EMAIL_COPY } from '../../../src/lib/auth-email/client.mjs';

test('signup copy covers the already-verified case', () => {
  const c = AUTH_EMAIL_COPY.signupSubmitted.toLowerCase();
  assert.match(c, /no new email is sent|already have/,
    'the copy must tell an existing account that no email is coming');
  assert.match(c, /sign in/, 'it must point at sign-in');
  assert.match(c, /reset|password/, 'it must point at password recovery');
});

test('signup copy does not reveal whether the account exists', () => {
  const c = AUTH_EMAIL_COPY.signupSubmitted.toLowerCase();
  // Anything that states the account's existence as fact would undo the
  // server's enumeration resistance.
  for (const leak of [
    'this email is already registered',
    'account already exists',
    'no account found',
    'that address is not registered',
  ]) {
    assert.ok(!c.includes(leak), `copy must not assert "${leak}"`);
  }
  // Both branches are conditional.
  assert.match(c, /\bif\b/, 'both outcomes must be stated conditionally');
});

test('the existing-account hint is short and actionable', () => {
  const h = AUTH_EMAIL_COPY.signupExistingHint;
  assert.ok(h.length > 0 && h.length < 160, 'hint should be a short line');
  assert.match(h.toLowerCase(), /sign in|reset/, 'hint must name a next step');
});

test('recovery copy stays generic', () => {
  assert.match(AUTH_EMAIL_COPY.recoverySubmitted.toLowerCase(), /if an account exists/,
    'recovery must not confirm whether the address is registered');
});
