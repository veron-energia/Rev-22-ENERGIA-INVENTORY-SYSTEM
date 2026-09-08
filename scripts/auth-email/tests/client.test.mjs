// How the browser reads the Edge Functions' answers.
//
// Node test runner, same shape as scripts/customer-phones/tests and
// scripts/survey/tests. Run with: npm run test:auth-email

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  AUTH_EMAIL_COPY, interpretAuthEmailResponse, interpretPasswordChange,
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
