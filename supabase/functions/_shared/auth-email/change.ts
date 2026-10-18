// Changing your own password: the decisions behind auth-change-password, with
// what they call passed in, so they can be tested without a Supabase project.
//
// The order:
//
//   1. No session, or a body that is not a password change: refused.
//   2. A session opened from an email link in the last 30 minutes (a reset
//      link, a sign-in link, an invitation) may go on without the current
//      password (the Owner, 10 Oct 2026). Any other session must give the
//      current password. Supabase Auth checks it, with an ordinary sign-in,
//      before anything is changed. A link opened longer ago is told so.
//   3. Supabase changes the password with the caller's own token. The current
//      password, when given, goes with it (current_password).
//   4. Only once Supabase has confirmed it is the "password changed" email
//      sent. A failed email undoes nothing.
//
// What this does not stop: the 30-minute rule lives here only, not in
// Supabase Auth. Someone at a signed-in device who uses the browser's
// developer tools can still set a password through Supabase Auth directly
// from a session opened by an email link. Turning on Supabase's "Require
// current password when updating" closes that for password sign-ins only.

import {
  cameFromEmailLink, currentPasswordRequiredMessage,
  type CurrentPasswordCheck, type OwnAccount, type PasswordChange,
} from './password.ts';
import { validateOwnPasswordChange } from './validate.ts';
import { safeDetail } from './diagnostics.ts';

export interface ChangeDeps {
  /** Who the caller's own token belongs to (Supabase Auth, nothing changed). */
  readAccount: () => Promise<OwnAccount>;
  /** Is this the account's current password? (Supabase Auth, a sign-in.) */
  checkCurrentPassword: (email: string, password: string) => Promise<CurrentPasswordCheck>;
  /** Supabase sets the password, with the caller's own token. */
  changePassword: (password: string, currentPassword: string | null) => Promise<PasswordChange>;
  /** The "password changed" email. Answers whether Pabbly took it. */
  notify: (change: Extract<PasswordChange, { status: 'ok' }>) => Promise<boolean>;
  log: (event: string, fields: Record<string, string>) => void;
}

export interface ChangeAnswer { status: number; body: Record<string, unknown> }

const SIGN_IN_AGAIN = 'Please sign in again and retry.';
const SESSION_EXPIRED = 'Your session has expired. Please use the link again or sign in.';
const UNAVAILABLE = 'We could not update your password just now. Please try again shortly.';

const answer = (status: number, body: Record<string, unknown>): ChangeAnswer => ({ status, body });
const unavailable = () => answer(503, { error: 'temporarily_unavailable', message: UNAVAILABLE });

/**
 * One request to auth-change-password, after the envelope was checked.
 * `token` is the caller's own access token (null when there is none);
 * `body` is the parsed JSON body.
 */
export async function changeOwnPasswordRequest(
  token: string | null, body: Record<string, unknown>, deps: ChangeDeps, nowSeconds = Date.now() / 1000,
): Promise<ChangeAnswer> {
  // Step 1.
  if (!token) return answer(401, { error: 'unauthorized', message: SIGN_IN_AGAIN });
  const parsed = validateOwnPasswordChange(body);
  if (!parsed.ok) {
    return answer(400, { error: 'invalid_request', fields: { [parsed.errors[0].field]: parsed.errors[0].message } });
  }
  const current = parsed.value.currentPassword;

  // Step 2. Not straight from an email link, so the current password is needed.
  if (!cameFromEmailLink(token, nowSeconds)) {
    if (!current) {
      return answer(400, { error: 'current_password_required', message: currentPasswordRequiredMessage(token, nowSeconds) });
    }
    let account: OwnAccount;
    try {
      account = await deps.readAccount();
    } catch {
      return unavailable();
    }
    if (account.status === 'unauthorized') return answer(401, { error: 'unauthorized', message: SESSION_EXPIRED });
    if (account.status !== 'ok' || !account.email) return unavailable();

    let check: CurrentPasswordCheck;
    try {
      check = await deps.checkCurrentPassword(account.email, current);
    } catch (error) {
      check = { status: 'error', message: String(error) };
    }
    if (check.status === 'wrong') {
      deps.log('auth_email.password_change_refused', { reason: 'current_password_wrong' });
      return answer(400, { error: 'current_password_wrong', message: 'That is not your current password.' });
    }
    if (check.status === 'rate_limited') {
      return answer(429, { error: 'rate_limited', message: 'Too many attempts. Please wait a few minutes and try again.' });
    }
    if (check.status !== 'ok') {
      deps.log('auth_email.password_change_error', { detail: safeDetail(check.message) });
      return unavailable();
    }
  }

  // Step 3.
  let change: PasswordChange;
  try {
    change = await deps.changePassword(parsed.value.password, current);
  } catch (error) {
    change = { status: 'error', message: String(error) };
  }
  if (change.status === 'unauthorized') return answer(401, { error: 'unauthorized', message: SESSION_EXPIRED });
  if (change.status === 'rejected') return answer(400, { error: 'password_rejected', message: change.message });
  if (change.status === 'error') {
    deps.log('auth_email.password_change_error', { detail: safeDetail(change.message) });
    return unavailable();
  }

  // Step 4. The password is changed. Whatever happens to the email from here,
  // the answer to "did my password change?" is yes, and the answer says so.
  // `notified` means Pabbly took the request, not that the email arrived.
  let notified = false;
  try {
    notified = await deps.notify(change);
  } catch {
    notified = false;
  }
  return answer(200, { ok: true, password_changed: true, notified });
}
