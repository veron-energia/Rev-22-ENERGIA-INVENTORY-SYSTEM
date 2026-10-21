// Pure interpretation of what the Auth-email Edge Functions send back.
//
// Kept free of React and of the Supabase client so it can be unit-tested with
// the Node test runner, following the same `.mjs` + `.d.mts` shape as
// `lib/customer-phones/normalize.mjs` and `lib/survey/form.mjs`.
//
// One rule shapes all of this: the server answers resend and recovery
// identically whether or not an account exists, so the wording here must be
// generic too. A screen that said "no account found" would undo the server's
// care on the client side. Sign-up is the exception since 437 (the Owner, 20
// Oct 2026): it says when an address already has a login.

export const AUTH_EMAIL_COPY = {
  // Two branches, both stated, neither confirmed. The server deliberately
  // suppresses the email when the address is already verified, so a screen that
  // promised one would leave exactly those people waiting for something that is
  // never coming. Saying both without saying which applies keeps the server's
  // enumeration resistance and still gives everyone a next step.
  signupSubmitted:
    'If this address is new to Energia, a verification link is on its way — open it to carry on. '
    + 'If you already have an affiliate login with this address, no new email is sent: sign in below, '
    + 'or reset your password if you have forgotten it.',
  signupExistingHint:
    'Already signed up before? No email will arrive. Use Sign in or Reset password.',
  // 437 (the Owner, 20 Oct 2026, decision 4): sign-up says when an address
  // already has a login, and offers Sign in and Reset password. The Owner
  // accepted that this shows the address is registered.
  signupEmailInUse:
    'This email already has an Energia login. Sign in, or reset your password if you have forgotten it.',
  // 437 (decision 2): the Account page's "Send verification email".
  verifyEmailSent:
    'A verification link is on its way to your email. Open it on this phone or computer to finish. '
    + 'Check your spam folder if it does not arrive in a few minutes.',
  resendSubmitted:
    'If that address still needs verifying, a new link is on its way. Please check your inbox and spam folder.',
  recoverySubmitted:
    'If an account exists for this email, password reset instructions will be sent.',
  notSent:
    'We could not hand your email to our delivery service just now. Please wait a moment and try again.',
  unavailable:
    'We could not process that request just now. Please try again shortly.',
  network:
    'We could not reach the server. Check your connection and try again.',
  unauthorized:
    'Your session has expired. Please use the link again, or sign in and retry.',
};

/**
 * Turn an HTTP status plus a parsed JSON body into something a page can render.
 *
 * `kind` is what the caller should branch on; `message` is always safe to show.
 * A 200 with `status: "not_sent"` is a real case and not an error: the request
 * was accepted and the account is intact, but the delivery step refused it, so
 * the page should offer a retry rather than claim the email is on its way.
 */
export function interpretAuthEmailResponse(httpStatus, body) {
  const data = body && typeof body === 'object' ? body : {};
  const requestId = typeof data.request_id === 'string' ? data.request_id : null;

  if (httpStatus === 0) {
    return { ok: false, kind: 'network', message: AUTH_EMAIL_COPY.network, fields: {}, requestId, retryAfterSeconds: 0 };
  }

  if (httpStatus >= 200 && httpStatus < 300 && data.ok === true && data.status === 'created') {
    // 437: sign-up made the login, already confirmed; the page signs in next.
    return { ok: true, kind: 'created', message: null, fields: {}, requestId, retryAfterSeconds: 0 };
  }

  if (httpStatus >= 200 && httpStatus < 300 && data.ok === true) {
    const notSent = data.status === 'not_sent';
    return {
      ok: true,
      kind: notSent ? 'not_sent' : 'submitted',
      message: notSent ? AUTH_EMAIL_COPY.notSent : null,
      fields: {},
      requestId,
      retryAfterSeconds: 0,
    };
  }

  if (httpStatus === 409 && data.error === 'email_in_use') {
    return {
      ok: false, kind: 'email_in_use',
      message: typeof data.message === 'string' ? data.message : AUTH_EMAIL_COPY.signupEmailInUse,
      fields: {}, requestId, retryAfterSeconds: 0,
    };
  }

  if (httpStatus === 429) {
    return {
      ok: false,
      kind: 'rate_limited',
      message: typeof data.message === 'string' ? data.message : 'Too many attempts just now. Please try again later.',
      fields: {},
      requestId,
      retryAfterSeconds: Number(data.retry_after_seconds ?? 0) || 0,
    };
  }

  if (httpStatus === 400 && data.error === 'invalid_request') {
    const fields = data.fields && typeof data.fields === 'object' ? data.fields : {};
    const first = Object.values(fields).find(v => typeof v === 'string');
    return { ok: false, kind: 'invalid', message: first ?? 'Please check the details you entered.', fields, requestId, retryAfterSeconds: 0 };
  }

  // The account holder's own password was refused (too short, unchanged, policy).
  if (httpStatus === 400 && data.error === 'password_rejected') {
    return {
      ok: false, kind: 'invalid',
      message: typeof data.message === 'string' ? data.message : 'Could not update the password.',
      fields: {}, requestId, retryAfterSeconds: 0,
    };
  }

  if (httpStatus === 401 || httpStatus === 403) {
    return { ok: false, kind: 'unauthorized', message: AUTH_EMAIL_COPY.unauthorized, fields: {}, requestId, retryAfterSeconds: 0 };
  }

  if (httpStatus === 503 && data.error === 'not_configured') {
    // Names of missing secrets, never values. Useful during rollout, harmless after.
    const names = Array.isArray(data.missing) ? data.missing.join(', ') : '';
    return {
      ok: false, kind: 'unavailable',
      message: names ? `Email delivery is not configured yet (${names}).` : AUTH_EMAIL_COPY.unavailable,
      fields: {}, requestId, retryAfterSeconds: 0,
    };
  }

  return {
    ok: false,
    kind: httpStatus >= 500 ? 'unavailable' : 'unknown',
    message: typeof data.message === 'string' ? data.message : AUTH_EMAIL_COPY.unavailable,
    fields: {},
    requestId,
    retryAfterSeconds: 0,
  };
}

/**
 * The password-change endpoint answers with a different question in mind: did
 * the password change? A failure to send the notification must never read as a
 * failed password change, so the two are reported separately.
 */
export function interpretPasswordChange(httpStatus, body) {
  const data = body && typeof body === 'object' ? body : {};
  if (httpStatus >= 200 && httpStatus < 300 && data.password_changed === true) {
    return { ok: true, kind: 'changed', message: null, notified: data.notified === true, fields: {}, requestId: typeof data.request_id === 'string' ? data.request_id : null, retryAfterSeconds: 0 };
  }
  return { ...interpretAuthEmailResponse(httpStatus, data), notified: false };
}
