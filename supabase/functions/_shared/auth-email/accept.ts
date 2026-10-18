// Accepting an invitation: the decisions behind auth-accept-invitation, with
// what they call passed in, so they can be tested without a Supabase project.
//
// The order is the whole security argument:
//
//   1. Only a session opened from an emailed link may go on (429). A
//      password sign-in is refused before anything is read or set.
//   2. The login must have a pending invitation: open, not cancelled, not
//      used. Its address must match, and its profile must be the pending one
//      the invitation made. Anything else stops here, before any password is
//      set (429). If this cannot be checked, nothing is set either.
//      Before 429 a login with no invitation went on to step 4. Any session
//      from an emailed link then set a new password without the current one,
//      however old the link: all staff, and any affiliate who used a reset
//      link. That got round the 30-minute rule in auth-change-password.
//   3. The link must have been opened in the last 30 minutes (the Owner,
//      18 Oct 2026: "30 minutes, like reset links"). It is the window of
//      auth-change-password, from the same code (invitationLinkState in
//      password.ts). A link opened longer ago is told "This invitation link
//      has expired. Ask for a new invitation." and an Owner or Manager
//      presses Resend on Users & Roles, which sends a new link. This comes
//      after step 2, so a login with no pending invitation, or a cancelled,
//      used, expired, wrong-address or unfinished one, is still told that
//      first (the order of 10 Oct). Before this an invitation link worked at
//      any age.
//   4. Supabase changes the password, with the invitee's own token. If that
//      fails, nothing else happens.
//   5. Only once Supabase has confirmed it does the database switch the
//      profile on (invite_user_accept), with the role and stores an
//      administrator chose, never anything this request carried. The
//      database checks the invitation again, under a lock.
//
// The page asks first with { check: true }. That runs steps 1 to 3 only and
// sets nothing, so the page shows the password form only to someone with a
// pending invitation and a link opened in the last 30 minutes.

import {
  ACCEPT_NEEDS_LINK_MESSAGE, INVITATION_LINK_EXPIRED_MESSAGE, invitationLinkState, type OwnAccount, type PasswordChange,
} from './password.ts';
import { validatePasswordChange } from './validate.ts';

/** An invitation made for a login: its status and the address it was sent to. */
export interface InvitationRow { status: string; email: string }

/** The profile of a login: its invitation state, and whether it was removed. */
export interface ProfileState { invitationStatus: string | null; deleted: boolean }

export interface AcceptDeps {
  /** Who the caller's own token belongs to (Supabase Auth, nothing changed). */
  readAccount: () => Promise<OwnAccount>;
  /** The invitations made for this login, newest first. */
  invitationsFor: (userId: string) => Promise<InvitationRow[]>;
  /** The login's profile, or null when it has none (an affiliate, say). */
  profileOf: (userId: string) => Promise<ProfileState | null>;
  /** Supabase sets the password, with the caller's own token. */
  changePassword: (password: string) => Promise<PasswordChange>;
  /** invite_user_accept, as the service role. */
  acceptInDatabase: (userId: string, email: string) =>
    Promise<{ data: unknown; error: { message: string } | null }>;
  /** The "password changed" email. A failure here undoes nothing. */
  notifyPasswordChanged: (change: Extract<PasswordChange, { status: 'ok' }>) => Promise<void>;
  log: (event: string, fields: Record<string, string>) => void;
}

export interface AcceptAnswer { status: number; body: Record<string, unknown> }

/** What a request with no session is told. */
export const LINK_NO_LONGER_VALID = 'This invitation link is no longer valid. Ask for a new invitation.';
const LINK_EXPIRED = 'This invitation link has expired or has already been used. Ask for a new invitation.';
const CANNOT_CHECK = 'We could not check your invitation just now. Please try again shortly.';
/**
 * What a login with no invitation is told: invite_user_accept's words. The
 * page adds where to go (sign in, or reset the password).
 */
export const NOT_INVITED_MESSAGE = 'There is no invitation for this account.';
/**
 * The `reason` for a pending invitation whose link was opened more than 30
 * minutes ago (step 3). Not invite_user_accept's "expired", which is an
 * invitation the database closed.
 */
export const LINK_EXPIRED_REASON = 'link_expired';

// ── The two reads, as auth-accept-invitation makes them (service role) ─────

type Rows = PromiseLike<{ data: unknown; error: { message: string } | null }>;
/** The part of a Supabase query these reads use. */
export interface RowQuery {
  eq(column: string, value: string): RowQuery;
  order(column: string, options: { ascending: boolean }): RowQuery;
  limit(count: number): Rows;
  maybeSingle(): Rows;
}
/** The part of a Supabase client these reads use. */
export interface TableReader { from(table: string): { select(columns: string): RowQuery } }

/** A login's invitations, newest first (the last 50). A failed read throws. */
export async function invitationsOfLogin(db: TableReader, userId: string): Promise<InvitationRow[]> {
  const { data, error } = await db.from('user_invitations').select('status, email_normalized')
    .eq('auth_user_id', userId).order('invited_at', { ascending: false }).limit(50);
  if (error) throw new Error(error.message);
  return ((Array.isArray(data) ? data : []) as { status?: unknown; email_normalized?: unknown }[]).map(r => ({
    status: typeof r.status === 'string' ? r.status : '',
    email: typeof r.email_normalized === 'string' ? r.email_normalized : '',
  }));
}

/** A login's profile state, or null when it has none. A failed read throws. */
export async function profileStateOf(db: TableReader, userId: string): Promise<ProfileState | null> {
  const { data, error } = await db.from('profiles').select('invitation_status, deleted_at')
    .eq('id', userId).maybeSingle();
  if (error) throw new Error(error.message);
  if (!data) return null;
  const row = data as { invitation_status?: unknown; deleted_at?: unknown };
  return {
    invitationStatus: typeof row.invitation_status === 'string' ? row.invitation_status : null,
    deleted: row.deleted_at != null,
  };
}

/** Is this body the page's question "is there a pending invitation?" and nothing else? */
export function isInvitationCheck(body: Record<string, unknown>): boolean {
  const keys = Object.keys(body);
  return keys.length === 1 && keys[0] === 'check' && body.check === true;
}

type Precheck =
  | { ok: true; userId: string; email: string }
  | { ok: false; answer: AcceptAnswer; reason: string };

const refuse = (status: number, reason: string, body: Record<string, unknown>): Precheck =>
  ({ ok: false, reason, answer: { status, body } });

const notActivated = (reason: string, message: string): Precheck =>
  refuse(403, reason, { error: 'not_activated', reason, message });

const normal = (email: string) => email.trim().toLowerCase();

/**
 * Step 2: does this login have a pending invitation? Refuses unless it does.
 * The same words and the same choice as invite_user_accept: a pending
 * invitation of the login is the one accepted, else its newest one says why
 * not. A failed read refuses too: nothing is set that was not checked.
 */
export async function pendingInvitation(deps: Pick<AcceptDeps, 'readAccount' | 'invitationsFor' | 'profileOf'>):
  Promise<Precheck> {
  const unavailable = refuse(503, 'unavailable', { error: 'temporarily_unavailable', message: CANNOT_CHECK });
  let account: OwnAccount;
  try {
    account = await deps.readAccount();
  } catch {
    return unavailable;
  }
  if (account.status === 'unauthorized') {
    return refuse(401, 'unauthorized', { error: 'unauthorized', message: LINK_EXPIRED });
  }
  if (account.status !== 'ok') return unavailable;

  let rows: InvitationRow[];
  try {
    rows = await deps.invitationsFor(account.userId);
  } catch {
    return unavailable;
  }
  const invitation = rows.find(r => r.status === 'pending') ?? rows[0];
  if (!invitation) return notActivated('not_invited', NOT_INVITED_MESSAGE);
  if (invitation.status === 'cancelled') {
    return notActivated('cancelled', 'This invitation was cancelled and can no longer be used.');
  }
  if (invitation.status === 'accepted') {
    return notActivated('already_accepted', 'This invitation has already been used. Sign in with your password.');
  }
  if (invitation.status !== 'pending') return notActivated(invitation.status, 'This invitation is no longer valid.');
  if (normal(invitation.email) !== normal(account.email)) {
    return notActivated('wrong_account', 'This invitation was sent to a different address.');
  }

  let profile: ProfileState | null;
  try {
    profile = await deps.profileOf(account.userId);
  } catch {
    return unavailable;
  }
  if (!profile || profile.deleted || profile.invitationStatus !== 'pending') {
    return notActivated('not_set_up', 'This invitation was not finished. Ask whoever invited you to send it again.');
  }
  return { ok: true, userId: account.userId, email: account.email };
}

/**
 * One request to auth-accept-invitation, after the envelope was checked.
 * `token` is the caller's own access token; `body` is the parsed JSON body.
 */
export async function acceptInvitationRequest(
  token: string, body: Record<string, unknown>, deps: AcceptDeps, nowSeconds = Date.now() / 1000,
): Promise<AcceptAnswer> {
  // Step 1. Nothing is read or set before this. How long ago the link was
  // opened is read here, once, and used at step 3.
  const link = invitationLinkState(token, nowSeconds);
  if (link === 'not_from_link') {
    deps.log('user_invitation.accept_refused', { reason: 'not_from_link' });
    return { status: 401, body: { error: 'unauthorized', reason: 'not_from_link', message: ACCEPT_NEEDS_LINK_MESSAGE } };
  }

  const check = isInvitationCheck(body);
  if (!check) {
    const parsed = validatePasswordChange(body);
    if (!parsed.ok) {
      return { status: 400, body: { error: 'invalid_request', fields: { [parsed.errors[0].field]: parsed.errors[0].message } } };
    }
  }

  // Step 2.
  const pending = await pendingInvitation(deps);
  if (!pending.ok) {
    deps.log('user_invitation.accept_refused', { reason: pending.reason });
    return pending.answer;
  }

  // Step 3. A pending invitation, but a link opened more than 30 minutes ago.
  // Answered as the step 2 refusals are (403 not_activated with a reason), so
  // the page shows the words with "Go to sign in" and no password form.
  if (link === 'expired') {
    deps.log('user_invitation.accept_refused', { reason: LINK_EXPIRED_REASON });
    return { status: 403, body: {
      error: 'not_activated', reason: LINK_EXPIRED_REASON, message: INVITATION_LINK_EXPIRED_MESSAGE,
    } };
  }
  if (check) return { status: 200, body: { ok: true, pending: true } };

  // Step 4.
  const change = await deps.changePassword(body.password as string);
  if (change.status === 'unauthorized') {
    deps.log('user_invitation.accept_password_failed', { kind: 'unauthorized' });
    return { status: 401, body: { error: 'unauthorized', message: LINK_EXPIRED } };
  }
  if (change.status === 'rejected') {
    // The invitation stays pending. Nothing has been switched on, and they can
    // try a different password on the same link.
    deps.log('user_invitation.accept_password_failed', { kind: 'rejected' });
    return { status: 400, body: { error: 'password_rejected', message: change.message } };
  }
  if (change.status === 'error') {
    deps.log('user_invitation.accept_password_failed', { kind: 'error' });
    return { status: 503, body: {
      error: 'temporarily_unavailable',
      message: 'We could not set your password just now. Please try again shortly.',
    } };
  }

  // Step 5, on the strength of a confirmed password change.
  const { data, error } = await deps.acceptInDatabase(change.userId, change.email);
  if (error) {
    deps.log('user_invitation.accept_failed', {});
    return { status: 502, body: {
      error: 'activation_failed',
      // The password IS set now, so say so, rather than implying it all failed
      // and inviting them to try a used link again.
      message: 'Your password was set, but your access could not be switched on. '
             + 'Ask whoever invited you to check your account.',
    } };
  }
  const result = (data ?? {}) as { activated?: boolean; reason?: string; message?: string; role?: string };
  if (!result.activated) {
    deps.log('user_invitation.accept_refused', { reason: result.reason ?? 'unknown' });
    return { status: 403, body: {
      error: 'not_activated', reason: result.reason,
      message: result.message ?? 'This invitation can no longer be used.',
    } };
  }

  // The same notice every other password change sends.
  await deps.notifyPasswordChanged(change).catch(() => undefined);
  deps.log('user_invitation.accepted', { role: result.role ?? '' });
  return { status: 200, body: { ok: true, role: result.role } };
}

