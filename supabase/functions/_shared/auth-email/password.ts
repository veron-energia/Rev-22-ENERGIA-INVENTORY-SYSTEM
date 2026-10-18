// Changing a password as the signed-in user, not as an administrator.
//
// The notification email is only trustworthy if the change is something this
// server watched happen. So the server performs the change itself, through the
// ordinary user-scoped Auth endpoint with the caller's own access token — the
// same request the browser would have made. Everything Supabase enforces still
// applies: the session must be valid, a recovery session works exactly as a
// recovery session should, the project password policy holds, and any
// reauthentication requirement stands.
//
// What is deliberately not used here is the admin user-update API. That would
// let this endpoint set anyone's password on the strength of a request body,
// which is a far larger thing to expose than a notification email is worth.
//
// The new password passes through this function to Supabase and is never
// logged, never stored, and never included in the notification.

export type PasswordChange =
  | { status: 'ok'; userId: string; email: string; displayName: string; changedAt: string }
  | { status: 'unauthorized' }
  | { status: 'rejected'; message: string }
  | { status: 'error'; message: string };

// `currentPassword`, when given, goes to Supabase as current_password. With
// the Auth setting "Require current password when updating" on, Supabase
// refuses a password session's change without it, so the 429 path that asks
// for the current password keeps working when that setting is turned on.
export async function changeOwnPassword(
  args: { supabaseUrl: string; apiKey: string; accessToken: string; password: string; currentPassword?: string | null },
  fetchImpl: typeof fetch = fetch,
): Promise<PasswordChange> {
  const body: { password: string; current_password?: string } = { password: args.password };
  if (args.currentPassword) body.current_password = args.currentPassword;
  let response: Response;
  try {
    response = await fetchImpl(`${args.supabaseUrl}/auth/v1/user`, {
      method: 'PUT',
      headers: {
        apikey: args.apiKey,
        Authorization: `Bearer ${args.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
  } catch (error) {
    return { status: 'error', message: `auth request failed: ${String(error)}` };
  }

  const answer = await response.json().catch(() => ({}));

  if (response.status === 401 || response.status === 403) return { status: 'unauthorized' };
  if (!response.ok) {
    // Supabase's own wording, passed through. The caller is the account holder,
    // so "New password should be different from the old password" or a policy
    // failure is exactly what they need to read.
    const message = typeof answer?.msg === 'string' ? answer.msg
      : typeof answer?.message === 'string' ? answer.message
        : typeof answer?.error_description === 'string' ? answer.error_description
          : 'Could not update the password.';
    return { status: 'rejected', message };
  }

  const id = typeof answer?.id === 'string' ? answer.id : '';
  const email = typeof answer?.email === 'string' ? answer.email : '';
  if (!id || !email) return { status: 'error', message: 'password updated but the account could not be read back' };

  const meta = (answer?.user_metadata ?? {}) as Record<string, unknown>;
  const displayName = [meta.first_name, meta.last_name]
    .filter(v => typeof v === 'string' && v.trim())
    .join(' ')
    .trim();

  return {
    status: 'ok',
    userId: id,
    email,
    displayName,
    changedAt: typeof answer?.updated_at === 'string' ? answer.updated_at : new Date().toISOString(),
  };
}

/**
 * Who the caller's own token belongs to, read from the ordinary user-scoped
 * Auth endpoint (nothing is changed). Used to look an invitation up before a
 * password is set from its link.
 */
export type OwnAccount =
  | { status: 'ok'; userId: string; email: string }
  | { status: 'unauthorized' }
  | { status: 'error'; message: string };

export async function readOwnAccount(
  args: { supabaseUrl: string; apiKey: string; accessToken: string },
  fetchImpl: typeof fetch = fetch,
): Promise<OwnAccount> {
  let response: Response;
  try {
    response = await fetchImpl(`${args.supabaseUrl}/auth/v1/user`, {
      method: 'GET',
      headers: { apikey: args.apiKey, Authorization: `Bearer ${args.accessToken}` },
    });
  } catch (error) {
    return { status: 'error', message: `auth request failed: ${String(error)}` };
  }
  if (response.status === 401 || response.status === 403) return { status: 'unauthorized' };
  const body = await response.json().catch(() => ({}));
  if (!response.ok) return { status: 'error', message: `auth answered ${response.status}` };
  const id = typeof body?.id === 'string' ? body.id : '';
  const email = typeof body?.email === 'string' ? body.email : '';
  if (!id) return { status: 'error', message: 'the account could not be read' };
  return { status: 'ok', userId: id, email };
}

// ── 429 (ADMIN-AUTH-9): who may change a password without the current one ──
//
// A session is not proof that the person at the screen owns it: on a shared
// shop device anyone could open the reset page and set a new password for
// whoever was signed in. So the change needs one of two things:
//   * a session that came from an email link a few minutes ago (a password
//     reset, a magic link, an invitation): the person has the mailbox; or
//   * the current password, which Supabase Auth checks.
// This rule is in auth-change-password. auth-accept-invitation uses the same
// 30-minute window for invitation links (invitationLinkState, 18 Oct 2026),
// with no current-password route. Neither is in Supabase Auth. Someone at a
// signed-in device who uses the browser's developer tools can still set a
// password through Supabase Auth directly from a session opened by an email
// link. See USER_INVITATIONS.md, "What the 30-minute rule does not stop".

/** The sign-in methods (the token's "amr") that come from an email link. */
export const EMAIL_LINK_METHODS: readonly string[] = ['recovery', 'otp', 'magiclink', 'invite'];
/**
 * How long after opening such a link the password may be set without the
 * current one: 30 minutes (the Owner, 10 Oct 2026). After that the current
 * password is needed, and the pages offer a new link.
 */
export const EMAIL_LINK_WINDOW_SECONDS = 30 * 60;

/**
 * The claims of a token, read without checking its signature. That is safe
 * for this one decision because the change itself is made with the same
 * token, which Supabase Auth does check: a forged token gets no further.
 */
export function tokenClaims(token: string): Record<string, unknown> | null {
  const part = token.split('.')[1];
  if (!part) return null;
  try {
    const base64 = part.replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
    const bytes = Uint8Array.from(atob(padded), c => c.charCodeAt(0));
    const claims = JSON.parse(new TextDecoder().decode(bytes));
    return claims && typeof claims === 'object' && !Array.isArray(claims) ? claims : null;
  } catch {
    return null;
  }
}

/** Did this session come from an email link in the last few minutes? */
export function cameFromEmailLink(token: string, nowSeconds = Date.now() / 1000,
                                  windowSeconds = EMAIL_LINK_WINDOW_SECONDS): boolean {
  const amr = tokenClaims(token)?.amr;
  if (!Array.isArray(amr)) return false;
  return amr.some((entry) => {
    if (!entry || typeof entry !== 'object') return false;
    const { method, timestamp } = entry as { method?: unknown; timestamp?: unknown };
    return typeof method === 'string' && EMAIL_LINK_METHODS.includes(method)
      && typeof timestamp === 'number'
      && timestamp >= nowSeconds - windowSeconds && timestamp <= nowSeconds + 60;
  });
}

/**
 * Where a session stands for accepting an invitation (auth-accept-invitation):
 *
 *   'open'           it was opened from an emailed link (the invitation, or
 *                    the recovery link a confirmed login gets) in the last
 *                    30 minutes: the password may be set;
 *   'expired'        it was opened from such a link, longer ago: the person
 *                    asks for a new invitation, and an Owner or Manager
 *                    presses Resend on Users & Roles;
 *   'not_from_link'  any other session, such as a password sign-in.
 *
 * The window is auth-change-password's, through the same cameFromEmailLink
 * and EMAIL_LINK_WINDOW_SECONDS: 30 minutes, like reset links (the Owner,
 * 18 Oct 2026). Before that an invitation link worked at any age.
 *
 * A password sign-in may not accept. A member of staff who was removed and
 * is invited again still has their old password, and the block on their
 * login is lifted when the invitation is set up (429), so that password alone
 * must not switch them back on without the email. A new invitee has no
 * password, so their session always comes from the link.
 */
export type InvitationLinkState = 'open' | 'expired' | 'not_from_link';

export function invitationLinkState(token: string, nowSeconds = Date.now() / 1000): InvitationLinkState {
  if (cameFromEmailLink(token, nowSeconds)) return 'open';
  return cameFromEmailLink(token, nowSeconds, Number.POSITIVE_INFINITY) ? 'expired' : 'not_from_link';
}

/**
 * May this session accept an invitation now? Only one opened from an emailed
 * link in the last 30 minutes (invitationLinkState is 'open').
 */
export function mayAcceptInvitation(token: string, nowSeconds = Date.now() / 1000): boolean {
  return invitationLinkState(token, nowSeconds) === 'open';
}

/** What auth-accept-invitation answers a session that did not come from the link. */
export const ACCEPT_NEEDS_LINK_MESSAGE = 'Open the invitation link from your email to finish setting up.';

/**
 * What auth-accept-invitation answers a link opened more than 30 minutes ago,
 * once the login is known to have a pending invitation (the Owner's words,
 * 18 Oct 2026).
 */
export const INVITATION_LINK_EXPIRED_MESSAGE = 'This invitation link has expired. Ask for a new invitation.';

/**
 * Why the current password is asked for. A session that did come from an
 * email link, only longer ago than the window, is told so and pointed at a
 * new link: someone who opened a reset link and came back later has usually
 * forgotten the current password (the reset pages offer "Request a new link"
 * beside the field). Any other session is simply asked for it.
 */
export function currentPasswordRequiredMessage(token: string, nowSeconds = Date.now() / 1000): string {
  return cameFromEmailLink(token, nowSeconds, Number.POSITIVE_INFINITY)
    ? `The email link you signed in with was opened more than ${EMAIL_LINK_WINDOW_SECONDS / 60} minutes ago. `
      + 'Enter your current password, or request a new link.'
    : 'Enter your current password to change it.';
}

export type CurrentPasswordCheck =
  | { status: 'ok' }
  | { status: 'wrong' }
  | { status: 'rate_limited' }
  | { status: 'error'; message: string };

/**
 * Is this the account's current password? Asked of Supabase Auth with an
 * ordinary password sign-in, the way the sign-in page asks it. The session
 * that sign-in opens is closed again at once. Neither password is logged.
 */
export async function checkCurrentPassword(
  args: { supabaseUrl: string; apiKey: string; email: string; password: string },
  fetchImpl: typeof fetch = fetch,
): Promise<CurrentPasswordCheck> {
  let response: Response;
  try {
    response = await fetchImpl(`${args.supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: args.apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: args.email, password: args.password }),
    });
  } catch (error) {
    return { status: 'error', message: `auth request failed: ${String(error)}` };
  }
  const body = await response.json().catch(() => ({}));
  if (response.status === 429) return { status: 'rate_limited' };
  if (response.status === 400 || response.status === 401 || response.status === 403) return { status: 'wrong' };
  if (!response.ok) return { status: 'error', message: `auth answered ${response.status}` };

  const accessToken = typeof body?.access_token === 'string' ? body.access_token : '';
  if (accessToken) {
    await fetchImpl(`${args.supabaseUrl}/auth/v1/logout?scope=local`, {
      method: 'POST',
      headers: { apikey: args.apiKey, Authorization: `Bearer ${accessToken}` },
    }).then((r) => r.body?.cancel()).catch(() => undefined);
  }
  return { status: 'ok' };
}

/** The bearer token, or null. Never logged. */
export function bearerToken(req: Request): string | null {
  const header = req.headers.get('authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  const token = match?.[1]?.trim() ?? '';
  // The anon/publishable key is what supabase-js sends when there is no session;
  // it is not a user token and must not be treated as one.
  if (!token || !token.includes('.') || token.startsWith('sb_')) return null;
  return token;
}
