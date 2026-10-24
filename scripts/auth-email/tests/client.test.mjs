// How the browser reads the Edge Functions' answers.
//
// Node test runner, same shape as scripts/customer-phones/tests and
// scripts/survey/tests. Run with: npm run test:auth-email

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  AUTH_EMAIL_COPY, interpretAuthEmailResponse, interpretPasswordChange,
  isEmailHint, readSignupRefusal, signupExistingMessage, signupRefusalState,
} from '../../../src/lib/auth-email/client.mjs';

test('a submitted request is a success with nothing to report', () => {
  const result = interpretAuthEmailResponse(200, { ok: true, status: 'submitted', request_id: 'abc' });
  assert.equal(result.ok, true);
  assert.equal(result.kind, 'submitted');
  assert.equal(result.message, null);
  assert.equal(result.requestId, 'abc');
});

test('"not_sent" is a success that still needs saying out loud', () => {
  // The account exists and the request was accepted; only delivery refused it.
  // The page must offer a retry rather than promise an email that is not coming.
  const result = interpretAuthEmailResponse(200, { ok: true, status: 'not_sent', request_id: 'abc' });
  assert.equal(result.ok, true);
  assert.equal(result.kind, 'not_sent');
  assert.equal(result.message, AUTH_EMAIL_COPY.notSent);
});

test('a rate limit keeps the server\'s wording and its delay', () => {
  const result = interpretAuthEmailResponse(429, {
    error: 'rate_limited', message: 'Too many attempts just now. Please try again in about 7 minutes.', retry_after_seconds: 420,
  });
  assert.equal(result.ok, false);
  assert.equal(result.kind, 'rate_limited');
  assert.equal(result.retryAfterSeconds, 420);
  assert.match(result.message, /7 minutes/);
});

test('field errors survive the trip and one is chosen to show', () => {
  const result = interpretAuthEmailResponse(400, {
    error: 'invalid_request', fields: { phone: 'Enter a valid international phone number.' },
  });
  assert.equal(result.kind, 'invalid');
  assert.equal(result.fields.phone, 'Enter a valid international phone number.');
  assert.match(result.message, /valid international phone/);
});

test('a rejected password shows Supabase\'s reason to the account holder', () => {
  const result = interpretAuthEmailResponse(400, {
    error: 'password_rejected', message: 'New password should be different from the old password.',
  });
  assert.equal(result.kind, 'invalid');
  assert.match(result.message, /different from the old password/);
});

test('an expired session says so instead of looking like a server fault', () => {
  assert.equal(interpretAuthEmailResponse(401, { error: 'unauthorized' }).kind, 'unauthorized');
  assert.equal(interpretAuthEmailResponse(403, {}).kind, 'unauthorized');
});

test('a missing-configuration reply names the secrets, and only their names', () => {
  const result = interpretAuthEmailResponse(503, {
    error: 'not_configured', missing: ['PABBLY_AUTH_EMAIL_SHARED_SECRET'],
  });
  assert.equal(result.kind, 'unavailable');
  assert.match(result.message, /PABBLY_AUTH_EMAIL_SHARED_SECRET/);
});

test('status 0 means the request never landed', () => {
  // functions.invoke reports a network failure with no Response to read.
  const result = interpretAuthEmailResponse(0, {});
  assert.equal(result.kind, 'network');
  assert.equal(result.message, AUTH_EMAIL_COPY.network);
});

test('an unreadable body still yields something safe to display', () => {
  for (const body of [null, undefined, 'a string', 42, []]) {
    const result = interpretAuthEmailResponse(500, body);
    assert.equal(result.ok, false);
    assert.equal(typeof result.message, 'string');
    assert.ok(result.message.length > 0);
  }
});

test('the generic copy never distinguishes accounts that exist from ones that do not', () => {
  for (const copy of [AUTH_EMAIL_COPY.recoverySubmitted, AUTH_EMAIL_COPY.resendSubmitted]) {
    assert.match(copy, /\bIf\b/i, `should be conditional: ${copy}`);
    assert.doesNotMatch(copy, /not found|no account|does not exist|already (registered|verified)/i, copy);
  }
  assert.match(AUTH_EMAIL_COPY.recoverySubmitted, /If an account exists for this email/);
});

test('a password change is reported separately from its notification', () => {
  const sent = interpretPasswordChange(200, { ok: true, password_changed: true, notified: true, request_id: 'r1' });
  assert.equal(sent.ok, true);
  assert.equal(sent.kind, 'changed');
  assert.equal(sent.notified, true);

  // The notification failing must not read as the password change failing.
  const unsent = interpretPasswordChange(200, { ok: true, password_changed: true, notified: false });
  assert.equal(unsent.ok, true, 'the password did change');
  assert.equal(unsent.kind, 'changed');
  assert.equal(unsent.notified, false);
  assert.equal(unsent.message, null, 'nothing alarming to show the user');
});

test('a failed password change is not reported as changed', () => {
  const result = interpretPasswordChange(401, { error: 'unauthorized' });
  assert.equal(result.ok, false);
  assert.equal(result.kind, 'unauthorized');
  assert.equal(result.notified, false);
});

// 437 (the Owner, 20 Oct 2026): sign-up goes straight in, and says when an
// address already has a login.
test('437: a sign-up that made the login reads as "created", for the page to sign in', () => {
  const result = interpretAuthEmailResponse(200, { ok: true, status: 'created', request_id: 'abc' });
  assert.equal(result.ok, true);
  assert.equal(result.kind, 'created');
  assert.equal(result.message, null);
});

test('437: an address that already has a login reads as "email_in_use", with Sign in and Reset password', () => {
  const result = interpretAuthEmailResponse(409, { error: 'email_in_use', message: 'This email already has an Energia login. Sign in, or reset your password if you have forgotten it.' });
  assert.equal(result.ok, false);
  assert.equal(result.kind, 'email_in_use');
  assert.match(result.message, /sign in/i);
  assert.match(result.message, /reset your password/i);
  assert.equal(interpretAuthEmailResponse(409, { error: 'email_in_use' }).message, AUTH_EMAIL_COPY.signupEmailInUse);
});

test('437: an old server\'s "submitted" is still a plain success', () => {
  assert.equal(interpretAuthEmailResponse(200, { ok: true, status: 'submitted' }).kind, 'submitted');
});

// 466 (the Owner, 24 Oct 2026): an existing affiliate's email or phone is sent
// to Sign in, worded from fixed codes.
test('466: affiliate_exists reads as its own kind, worded here, with the hint only when it is the mask', () => {
  const phone = interpretAuthEmailResponse(409, { error: 'affiliate_exists', matched: 'phone', email_hint: 's•••@rev22.com.sg',
    message: 'anything the server says', request_id: 'r1' });
  assert.equal(phone.ok, false);
  assert.equal(phone.kind, 'affiliate_exists');
  assert.equal(phone.matched, 'phone');
  assert.equal(phone.emailHint, 's•••@rev22.com.sg');
  assert.equal(phone.requestId, 'r1');
  assert.equal(phone.message, 'This phone number already has an Energia affiliate account, which signs in with s•••@rev22.com.sg. Sign in with that email, or reset your password if you have forgotten it.');
  const email = interpretAuthEmailResponse(409, { error: 'affiliate_exists', matched: 'email' });
  assert.equal(email.kind, 'affiliate_exists');
  assert.equal(email.matched, 'email');
  assert.equal(email.emailHint, null);
  assert.equal(email.message, 'This email is already on an Energia affiliate account. Sign in with the email you used for it, or reset your password if you have forgotten it.');
  const bad = interpretAuthEmailResponse(409, { error: 'affiliate_exists', matched: 'phone', email_hint: 'sam@example.com' });
  assert.equal(bad.emailHint, null, 'a whole address is not a hint');
  assert.doesNotMatch(bad.message, /sam@example\.com/);
  // A match it does not know is not this kind (the page then shows the error on the form).
  assert.notEqual(interpretAuthEmailResponse(409, { error: 'affiliate_exists', matched: 'name' }).kind, 'affiliate_exists');
  // email_in_use keeps its words, and says what matched.
  const inUse = interpretAuthEmailResponse(409, { error: 'email_in_use', matched: 'email', message: AUTH_EMAIL_COPY.signupEmailInUse });
  assert.equal(inUse.kind, 'email_in_use');
  assert.equal(inUse.matched, 'email');
  assert.equal(inUse.message, AUTH_EMAIL_COPY.signupEmailInUse);
});

test('466: the hint has one shape: at most one character, •••, @, a lower-case domain', () => {
  for (const good of ['s•••@rev22.com.sg', '•••@example.com', 'a•••@sub.example.co.uk']) assert.equal(isEmailHint(good), true, good);
  for (const bad of ['sam@example.com', 'sa•••@example.com', 's•••@Example.com', '<b>•••@example.com', 's•••@example.com x', '', null, undefined, 5]) {
    assert.equal(isEmailHint(bad), false, String(bad));
  }
});

test('466: the Join page hands the Sign in page codes, a mask-shaped hint, and the email only for email_in_use', () => {
  assert.deepEqual(signupRefusalState({ kind: 'email_in_use' }, ' ada@example.com '),
    { signupRefused: { reason: 'email_in_use', emailHint: null, email: 'ada@example.com' } });
  assert.deepEqual(signupRefusalState({ kind: 'affiliate_exists', matched: 'phone', emailHint: 's•••@example.com' }, 'new@example.com'),
    { signupRefused: { reason: 'affiliate_phone', emailHint: 's•••@example.com', email: '' } });
  assert.deepEqual(signupRefusalState({ kind: 'affiliate_exists', matched: 'email', emailHint: 'not a hint' }, 'new@example.com'),
    { signupRefused: { reason: 'affiliate_email', emailHint: null, email: '' } });
  for (const kind of ['created', 'submitted', 'not_sent', 'rate_limited', 'invalid', 'unavailable', 'network', 'unknown']) {
    assert.equal(signupRefusalState({ kind }, 'ada@example.com'), null, kind);
  }
});

test('466: the Sign in page reads only that shape, and words it itself', () => {
  assert.deepEqual(readSignupRefusal({ signupRefused: { reason: 'affiliate_phone', emailHint: 's•••@example.com', email: 'x@example.com' } }), {
    reason: 'affiliate_phone', emailHint: 's•••@example.com', email: '',
    message: signupExistingMessage('affiliate_phone', 's•••@example.com'),
  });
  assert.deepEqual(readSignupRefusal({ signupRefused: { reason: 'email_in_use', emailHint: 's•••@example.com', email: 'ada@example.com' } }), {
    reason: 'email_in_use', emailHint: null, email: 'ada@example.com', message: AUTH_EMAIL_COPY.signupEmailInUse,
  });
  for (const state of [null, undefined, 'x', {}, { signupRefused: null }, { signupRefused: { reason: 'free text' } },
    { signupRefused: { reason: ['affiliate_phone'] } }]) {
    assert.equal(readSignupRefusal(state), null, JSON.stringify(state));
  }
  assert.equal(readSignupRefusal({ signupRefused: { reason: 'affiliate_email', emailHint: '<i>x</i>' } }).emailHint, null);
  assert.equal(readSignupRefusal({ signupRefused: { reason: 'email_in_use', email: `${'x'.repeat(300)}@example.com` } }).email, '');
});

test('466: the words name both ways in, and only the hint says anything of the account', () => {
  for (const reason of ['affiliate_email', 'affiliate_phone']) {
    for (const hint of ['s•••@example.com', null]) {
      const c = signupExistingMessage(reason, hint);
      assert.match(c, /sign in/i);
      assert.match(c, /reset your password/);
      assert.equal(c.includes('@'), hint !== null);
    }
  }
  assert.equal(signupExistingMessage('affiliate_phone', 'sam@example.com'), signupExistingMessage('affiliate_phone', null));
});
