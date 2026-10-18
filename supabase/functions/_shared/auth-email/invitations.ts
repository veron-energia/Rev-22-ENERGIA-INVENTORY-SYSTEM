// Inviting an internal user, as a set of decisions with its collaborators
// injected — the same shape as flows.ts, and for the same reason: the cases
// worth testing are the ones that are impractical to stage against a live
// project. A permission refusal, a link that generates but an email that fails,
// a second click arriving while the first is still running.
//
// Two rules this file exists to keep:
//
//   1. The generated action link never leaves the server. It goes into the
//      email and nowhere else — not into the response, not into a log line.
//   2. Authority is never read from the request. Every permission decision is
//      made by a database function running as the CALLER, so the answer comes
//      from the caller's own profile row rather than anything they sent.

import type { AuthEmailConfig } from './config.ts';
import type { GenerateOutcome } from './admin.ts';
import type { DeliveryRequest, DeliveryResult } from './pabbly.ts';
import { isTrustedActionLink } from './redirects.ts';
import { definitelyNotSent } from './pabbly.ts';
import { renderUserInvitation } from './templates.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

export type InviteRole = 'owner' | 'admin' | 'manager' | 'inventory_manager' | 'staff';
export const INVITE_ROLES: InviteRole[] =
  ['owner', 'admin', 'manager', 'inventory_manager', 'staff'];

export interface InviteInput {
  requestId: string;
  email: string;
  fullName: string;
  role: InviteRole;
  workPhone?: string | null;
  personalPhone?: string | null;
  personalEmail?: string | null;
  storeIds?: string[];
}

export interface InvitationDeps {
  /** Runs an RPC as the signed-in administrator, so auth.uid() is them. */
  // deno-lint-ignore no-explicit-any
  callerRpc: (fn: string, args: Record<string, unknown>) => Promise<{ data: any; error: { message: string } | null }>;
  /** Runs an RPC with the service role, for the server-only functions. */
  // deno-lint-ignore no-explicit-any
  adminRpc: (fn: string, args: Record<string, unknown>) => Promise<{ data: any; error: { message: string } | null }>;
  generateInviteLink: (admin: Admin, args: { email: string; redirectTo: string; fullName: string }) => Promise<GenerateOutcome>;
  regenerateSignupLink: (admin: Admin, args: { email: string; redirectTo: string }) => Promise<GenerateOutcome>;
  /**
   * 429: a link for a login that already exists and whose address is
   * confirmed, where an 'invite' link is refused. Only ever asked for a login
   * the database said this invitation may use.
   */
  generateRecoveryLink: (admin: Admin, args: { email: string; redirectTo: string }) => Promise<GenerateOutcome>;
  deliver: (config: AuthEmailConfig, request: DeliveryRequest) => Promise<DeliveryResult>;
  admin: Admin;
}

export type InviteResult =
  | { kind: 'created'; invitationId: string; email: string; delivery: 'accepted_by_provider' | 'failed'; detail?: string }
  | { kind: 'existing_pending'; invitationId: string; message: string }
  | { kind: 'existing_request'; invitationId: string; message: string }
  | { kind: 'email_in_use'; scope: string; message: string }
  | { kind: 'forbidden'; message: string; field?: string }
  | { kind: 'invalid'; field: string; message: string }
  | { kind: 'provisioning_failed'; invitationId?: string; message: string }
  | { kind: 'rate_limited'; message: string; retryAfterSeconds?: number };


/**
 * Did the provider accept the request?
 *
 * 'accepted' is as much as any of this can honestly claim: Pabbly acknowledging
 * a webhook is not an inbox receiving a message, and the wording everywhere
 * downstream says "accepted by provider" rather than "sent" for that reason.
 */
const providerAccepted = (r: DeliveryResult): boolean => r.outcome === 'accepted';

const MAX_LEN = { email: 254, name: 120, phone: 32 };

/** Field checks the interface also makes, repeated here because the interface is not a boundary. */
export function validateInvite(input: Partial<InviteInput>): { ok: true; value: InviteInput } | { ok: false; field: string; message: string } {
  const requestId = String(input.requestId ?? '').trim();
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(requestId)) {
    return { ok: false, field: 'request_id', message: 'A valid request identifier is required.' };
  }
  const fullName = String(input.fullName ?? '').trim();
  if (!fullName) return { ok: false, field: 'full_name', message: 'Enter the person’s full name.' };
  if (fullName.length > MAX_LEN.name) return { ok: false, field: 'full_name', message: 'That name is too long.' };

  const email = String(input.email ?? '').trim().toLowerCase();
  if (email.length > MAX_LEN.email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return { ok: false, field: 'email', message: 'Enter a valid login email address.' };
  }
  const role = String(input.role ?? '') as InviteRole;
  if (!INVITE_ROLES.includes(role)) {
    return { ok: false, field: 'role', message: 'Choose a role.' };
  }

  const trimOrNull = (v: unknown) => {
    const s = String(v ?? '').trim();
    return s ? s.slice(0, MAX_LEN.phone) : null;
  };
  const personalEmail = String(input.personalEmail ?? '').trim().toLowerCase() || null;
  if (personalEmail && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(personalEmail)) {
    return { ok: false, field: 'personal_email', message: 'Enter a valid personal email address, or leave it blank.' };
  }

  const storeIds = Array.isArray(input.storeIds) ? input.storeIds : [];
  if (storeIds.length > 50) return { ok: false, field: 'store_ids', message: 'Too many stores selected.' };
  for (const id of storeIds) {
    if (typeof id !== 'string' || !/^[0-9a-f-]{36}$/i.test(id)) {
      return { ok: false, field: 'store_ids', message: 'A selected store was not recognised.' };
    }
  }

  return {
    ok: true,
    value: {
      requestId, email, fullName, role,
      workPhone: trimOrNull(input.workPhone),
      personalPhone: trimOrNull(input.personalPhone),
      personalEmail,
      storeIds,
    },
  };
}

/** Send one invitation email for a link we have just generated and trust. */
async function sendInvitation(
  deps: InvitationDeps,
  config: AuthEmailConfig,
  args: { requestId: string; link: string; email: string; fullName: string; invitedBy?: string },
): Promise<DeliveryResult> {
  const email = renderUserInvitation(args.fullName, args.link, args.invitedBy);
  return await deps.deliver(config, {
    requestId: args.requestId,
    actionType: 'user_invitation',
    to: args.email,
    subject: email.subject,
    html: email.html,
    text: email.text,
    recipientRole: 'staff',
  });
}

/**
 * 429: an address whose login is someone else's (a confirmed login with no
 * invitation or staff profile behind it). Supabase Auth refuses an 'invite'
 * link for it, and it is not ours to reuse. The invitation was already saved
 * by invite_user_begin, so say so rather than "nothing was changed". A
 * removed member of staff's login is reused (the Owner, 10 Oct 2026), so it
 * does not end here.
 */
const LOGIN_NOT_REUSABLE =
  'That address already has a login that cannot be invited, so no email was sent. '
  + 'The invitation is saved: cancel it on Users & Roles.';

const DELIVERY_DETAIL = (delivery: DeliveryResult, accepted: boolean) =>
  accepted ? undefined
    : definitelyNotSent(delivery.outcome)
      ? 'The email was not sent. Use Resend to try again.'
      : 'It is not certain whether the email went out. Check before resending.';

async function recordFailure(deps: InvitationDeps, invitationId: string, detail: string, isResend: boolean) {
  await deps.adminRpc('invite_user_record_delivery', {
    p_invitation_id: invitationId, p_status: 'failed', p_detail: detail, p_is_resend: isResend,
  });
}

/**
 * 429: the login this invitation may use already, if any (asked of the
 * database with the service role): the login tied to it, a cancelled
 * invitee's, a removed member of staff's, or one an unfinished invitation
 * made. Null when there is none; an answer that is not a login id counts as
 * none.
 */
async function reusableLogin(deps: InvitationDeps, invitationId: string):
  Promise<{ ok: true; loginId: string | null } | { ok: false }> {
  const res = await deps.adminRpc('invite_user_reusable_login', { p_invitation_id: invitationId });
  if (res.error) return { ok: false };
  return { ok: true, loginId: typeof res.data === 'string' && res.data ? res.data : null };
}

/**
 * Tie a login to the invitation and give it the invitation's pending
 * profile (invite_user_provisioned). Anything but "provisioned" sends no
 * email: a cancel during set-up (413), a login that is already someone's
 * (429), an invitation no longer pending.
 */
async function provision(
  deps: InvitationDeps, invitationId: string, loginId: string, isResend: boolean,
): Promise<{ ok: true } | { ok: false; result: InviteResult }> {
  const provisioned = await deps.adminRpc('invite_user_provisioned', {
    p_invitation_id: invitationId,
    p_auth_user_id: loginId,
  });
  if (provisioned.error) {
    await recordFailure(deps, invitationId, 'profile setup failed', isResend);
    return {
      ok: false,
      result: {
        kind: 'provisioning_failed', invitationId,
        message: 'The account was created but its profile could not be set up. '
               + 'The invitation is saved and no access has been granted — use Resend to try again.',
      },
    };
  }
  const outcome = provisioned.data?.outcome;
  if (outcome === 'provisioned') return { ok: true };
  if (outcome === 'login_in_use') {
    await recordFailure(deps, invitationId, 'the login belongs to someone else', isResend);
    return { ok: false, result: { kind: 'provisioning_failed', invitationId, message: LOGIN_NOT_REUSABLE } };
  }
  // 413: an invitation cancelled while its login was being made answers
  // 'cancelled', not an error. The database has tied that login to the
  // cancelled invitation and closed it (412 blocks it), so nothing is sent.
  return {
    ok: false,
    result: {
      kind: 'provisioning_failed', invitationId,
      message: outcome === 'cancelled'
        ? 'The invitation was cancelled while it was being set up. No email was sent.'
        : 'This invitation is no longer pending. No email was sent.',
    },
  };
}

/**
 * The link for the email. 'invite' makes the login when there is none, and
 * makes a new link for a login whose address is not confirmed yet. For a
 * login this invitation may use whose address is confirmed (its first link
 * was opened, perhaps by an email scanner) Supabase refuses 'invite', so a
 * recovery link signs that same login in to choose a password (429).
 */
async function invitationLink(
  deps: InvitationDeps,
  args: { email: string; fullName: string; redirectTo: string; knownLogin: boolean },
): Promise<GenerateOutcome> {
  const generated = await deps.generateInviteLink(deps.admin, {
    email: args.email, redirectTo: args.redirectTo, fullName: args.fullName,
  });
  if (generated.status === 'already_confirmed' && args.knownLogin) {
    return await deps.generateRecoveryLink(deps.admin, { email: args.email, redirectTo: args.redirectTo });
  }
  return generated;
}

export async function createInvitation(
  deps: InvitationDeps,
  config: AuthEmailConfig,
  input: InviteInput,
  redirectTo: string,
  invitedByName?: string,
): Promise<InviteResult> {
  // Permissions and conflicts first, before an account exists anywhere. A
  // refusal here has cost nothing and left nothing behind.
  const begun = await deps.callerRpc('invite_user_begin', {
    p_request_id: input.requestId,
    p_email: input.email,
    p_full_name: input.fullName,
    p_role: input.role,
    p_work_phone: input.workPhone,
    p_personal_phone: input.personalPhone,
    p_personal_email: input.personalEmail,
    p_store_ids: input.storeIds ?? [],
  });
  if (begun.error) return { kind: 'provisioning_failed', message: begun.error.message };

  const row = begun.data ?? {};
  switch (row.outcome) {
    case 'forbidden': return { kind: 'forbidden', message: row.message, field: row.field };
    case 'invalid': return { kind: 'invalid', field: row.field, message: row.message };
    case 'email_in_use': return { kind: 'email_in_use', scope: row.scope, message: row.message };
    case 'existing_pending': return { kind: 'existing_pending', invitationId: row.invitation_id, message: row.message };
    case 'existing_request': return { kind: 'existing_request', invitationId: row.invitation_id, message: row.message };
    case 'created': break;
    default: return { kind: 'provisioning_failed', message: 'The invitation could not be recorded.' };
  }

  const invitationId: string = row.invitation_id;

  // 429: a login this address already has that the invitation may use (a
  // cancelled invitee's or a removed member of staff's, invited again). It is
  // set up first: its profile is put back as pending and the block placed
  // when it was cancelled or removed is lifted, or the new link would be
  // refused. A removed member of staff's address is confirmed, so their link
  // is a recovery link (invitationLink).
  const reusable = await reusableLogin(deps, invitationId);
  if (!reusable.ok) {
    await recordFailure(deps, invitationId, 'the login check failed', false);
    return {
      kind: 'provisioning_failed', invitationId,
      message: 'The invitation is saved, but it could not be set up. No access has been granted — use Resend to try again.',
    };
  }
  const knownLogin = reusable.loginId;
  if (knownLogin) {
    const ready = await provision(deps, invitationId, knownLogin, false);
    if (!ready.ok) return ready.result;
  }

  const generated = await invitationLink(deps, {
    email: input.email, fullName: input.fullName, redirectTo, knownLogin: !!knownLogin,
  });
  if (generated.status !== 'ok') {
    // The invitation row survives on purpose. A retry resends it rather than
    // creating a second person, and nothing is deleted to tidy up.
    await recordFailure(deps, invitationId, `link generation returned ${generated.status}`, false);
    return {
      kind: 'provisioning_failed', invitationId,
      message: generated.status === 'already_confirmed' && !knownLogin
        ? LOGIN_NOT_REUSABLE
        : 'The account could not be created. The invitation is saved — use Resend to try again.',
    };
  }

  if (!isTrustedActionLink(generated.link.actionLink, config)) {
    await recordFailure(deps, invitationId, 'generated link failed origin validation', false);
    return { kind: 'provisioning_failed', invitationId, message: 'The invitation link could not be verified.' };
  }

  // The account exists; attach it and write the inaccessible profile. If this
  // fails the account is left with no profile at all, which grants nothing.
  if (!generated.link.userId) {
    await recordFailure(deps, invitationId, 'no auth user id returned', false);
    return {
      kind: 'provisioning_failed', invitationId,
      message: 'The account was created but could not be identified. The invitation is saved — use Resend.',
    };
  }
  if (knownLogin) {
    if (generated.link.userId !== knownLogin) {
      await recordFailure(deps, invitationId, 'the link was made for another login', false);
      return { kind: 'provisioning_failed', invitationId, message: 'The invitation link could not be verified.' };
    }
  } else {
    const ready = await provision(deps, invitationId, generated.link.userId, false);
    if (!ready.ok) return ready.result;
  }

  const delivery = await sendInvitation(deps, config, {
    requestId: input.requestId, link: generated.link.actionLink,
    email: generated.link.email, fullName: input.fullName, invitedBy: invitedByName,
  });
  const accepted = providerAccepted(delivery);

  await deps.adminRpc('invite_user_record_delivery', {
    p_invitation_id: invitationId,
    p_status: accepted ? 'accepted_by_provider' : 'failed',
    p_detail: accepted ? 'provider accepted the request' : delivery.detail,
    p_is_resend: false,
  });

  return {
    kind: 'created', invitationId, email: input.email,
    delivery: accepted ? 'accepted_by_provider' : 'failed',
    // definitelyNotSent distinguishes "the provider said no" from "we never
    // found out", which is the difference between resend and wait.
    detail: DELIVERY_DETAIL(delivery, accepted),
  };
}

export async function resendInvitation(
  deps: InvitationDeps,
  config: AuthEmailConfig,
  invitationId: string,
  redirectTo: string,
  requestId: string,
  invitedByName?: string,
): Promise<InviteResult> {
  const prepared = await deps.callerRpc('invite_user_prepare_resend', { p_invitation_id: invitationId });
  if (prepared.error) return { kind: 'provisioning_failed', message: prepared.error.message };

  const row = prepared.data ?? {};
  if (row.outcome === 'forbidden') return { kind: 'forbidden', message: row.message };
  if (row.outcome === 'rate_limited') {
    return { kind: 'rate_limited', message: row.message, retryAfterSeconds: row.retry_after_seconds };
  }
  if (row.outcome !== 'ok') return { kind: 'provisioning_failed', invitationId, message: row.message };

  // 429: an invitation whose set-up never finished has no login tied to it.
  // Its login (made by the earlier attempt, or a cancelled invitee's) is set
  // up first; with none, the 'invite' link below makes one, which is then
  // set up before anything is sent. Before 429 a resend sent the link without
  // a profile behind it.
  let knownLogin: string | null = typeof row.auth_user_id === 'string' && row.auth_user_id ? row.auth_user_id : null;
  if (!knownLogin) {
    const reusable = await reusableLogin(deps, invitationId);
    if (!reusable.ok) {
      await recordFailure(deps, invitationId, 'the login check failed', true);
      return { kind: 'provisioning_failed', invitationId, message: 'A new invitation link could not be created.' };
    }
    knownLogin = reusable.loginId;
    if (knownLogin) {
      const ready = await provision(deps, invitationId, knownLogin, true);
      if (!ready.ok) return ready.result;
    }
  }

  // The login usually exists already, so 'invite' makes a new link for it
  // while its address is unconfirmed, and a recovery link once it is
  // confirmed (429: before, a signup link was tried there, which Supabase
  // refuses for a confirmed address). Regenerating a signup link stays the
  // fallback when 'invite' fails outright.
  let generated = await invitationLink(deps, {
    email: row.email, fullName: row.full_name, redirectTo, knownLogin: !!knownLogin,
  });
  if (generated.status === 'error') {
    generated = await deps.regenerateSignupLink(deps.admin, { email: row.email, redirectTo });
  }

  if (generated.status !== 'ok' || !isTrustedActionLink(generated.link.actionLink, config)) {
    await recordFailure(deps, invitationId, 'link generation failed', true);
    return {
      kind: 'provisioning_failed', invitationId,
      message: generated.status === 'already_confirmed' && !knownLogin
        ? LOGIN_NOT_REUSABLE
        : 'A new invitation link could not be created.',
    };
  }
  if (knownLogin) {
    if (generated.link.userId && generated.link.userId !== knownLogin) {
      await recordFailure(deps, invitationId, 'the link was made for another login', true);
      return { kind: 'provisioning_failed', invitationId, message: 'A new invitation link could not be created.' };
    }
  } else {
    if (!generated.link.userId) {
      await recordFailure(deps, invitationId, 'no auth user id returned', true);
      return { kind: 'provisioning_failed', invitationId, message: 'A new invitation link could not be created.' };
    }
    const ready = await provision(deps, invitationId, generated.link.userId, true);
    if (!ready.ok) return ready.result;
  }

  // 413: cancelled while the new link was being made? Ask again, as the
  // caller, just before sending. It changes nothing (the counters move when
  // the delivery is recorded), and a cancelled invitation's email never goes.
  const still = await deps.callerRpc('invite_user_prepare_resend', { p_invitation_id: invitationId });
  if (still.error || still.data?.outcome !== 'ok') {
    return {
      kind: 'provisioning_failed', invitationId,
      message: `${still.data?.message ?? still.error?.message ?? 'This invitation can no longer be resent.'} No email was sent.`,
    };
  }

  const delivery = await sendInvitation(deps, config, {
    requestId, link: generated.link.actionLink,
    email: generated.link.email, fullName: row.full_name, invitedBy: invitedByName,
  });
  const accepted = providerAccepted(delivery);

  await deps.adminRpc('invite_user_record_delivery', {
    p_invitation_id: invitationId,
    p_status: accepted ? 'accepted_by_provider' : 'failed',
    p_detail: accepted ? 'provider accepted the request' : delivery.detail,
    p_is_resend: true,
  });

  return {
    kind: 'created', invitationId, email: row.email,
    delivery: accepted ? 'accepted_by_provider' : 'failed',
    detail: DELIVERY_DETAIL(delivery, accepted),
  };
}

export async function cancelInvitation(
  deps: InvitationDeps, invitationId: string, reason: string,
): Promise<{ kind: 'cancelled' | 'forbidden' | 'error'; message?: string }> {
  const res = await deps.callerRpc('invite_user_cancel', {
    p_invitation_id: invitationId, p_reason: reason,
  });
  if (res.error) return { kind: 'error', message: res.error.message };
  const row = res.data ?? {};
  if (row.outcome === 'cancelled') return { kind: 'cancelled' };
  if (row.outcome === 'forbidden') return { kind: 'forbidden', message: row.message };
  return { kind: 'error', message: row.message ?? 'The invitation could not be cancelled.' };
}

// Accepting an invitation lives in accept.ts (429).
