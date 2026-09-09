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

  const generated = await deps.generateInviteLink(deps.admin, {
    email: input.email, redirectTo, fullName: input.fullName,
  });
  if (generated.status !== 'ok') {
    // The invitation row survives on purpose. A retry resends it rather than
    // creating a second person, and nothing is deleted to tidy up.
    await deps.adminRpc('invite_user_record_delivery', {
      p_invitation_id: invitationId, p_status: 'failed',
      p_detail: `link generation returned ${generated.status}`, p_is_resend: false,
    });
    return {
      kind: 'provisioning_failed', invitationId,
      message: generated.status === 'already_confirmed'
        ? 'That address already has a confirmed account. Nothing was changed.'
        : 'The account could not be created. The invitation is saved — use Resend to try again.',
    };
  }

  if (!isTrustedActionLink(generated.link.actionLink, config)) {
    await deps.adminRpc('invite_user_record_delivery', {
      p_invitation_id: invitationId, p_status: 'failed',
      p_detail: 'generated link failed origin validation', p_is_resend: false,
    });
    return { kind: 'provisioning_failed', invitationId, message: 'The invitation link could not be verified.' };
  }

  // The account exists; attach it and write the inaccessible profile. If this
  // fails the account is left with no profile at all, which grants nothing.
  if (!generated.link.userId) {
    await deps.adminRpc('invite_user_record_delivery', {
      p_invitation_id: invitationId, p_status: 'failed',
      p_detail: 'no auth user id returned', p_is_resend: false,
    });
    return {
      kind: 'provisioning_failed', invitationId,
      message: 'The account was created but could not be identified. The invitation is saved — use Resend.',
    };
  }

  const provisioned = await deps.adminRpc('invite_user_provisioned', {
    p_invitation_id: invitationId,
    p_auth_user_id: generated.link.userId,
  });
  if (provisioned.error) {
    await deps.adminRpc('invite_user_record_delivery', {
      p_invitation_id: invitationId, p_status: 'failed',
      p_detail: 'profile setup failed', p_is_resend: false,
    });
    return {
      kind: 'provisioning_failed', invitationId,
      message: 'The account was created but its profile could not be set up. '
             + 'The invitation is saved and no access has been granted — use Resend to try again.',
    };
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
    detail: accepted ? undefined
          : definitelyNotSent(delivery.outcome)
            ? 'The email was not sent. Use Resend to try again.'
            : 'It is not certain whether the email went out. Check before resending.',
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

  // The account already exists, so a fresh 'invite' is refused. Regenerating a
  // signup link is the path this codebase already uses for an unconfirmed
  // account: it leaves the password untouched, because there is none.
  let generated = await deps.generateInviteLink(deps.admin, {
    email: row.email, redirectTo, fullName: row.full_name,
  });
  if (generated.status === 'already_confirmed' || generated.status === 'error') {
    generated = await deps.regenerateSignupLink(deps.admin, { email: row.email, redirectTo });
  }

  if (generated.status !== 'ok' || !isTrustedActionLink(generated.link.actionLink, config)) {
    await deps.adminRpc('invite_user_record_delivery', {
      p_invitation_id: invitationId, p_status: 'failed',
      p_detail: 'link generation failed', p_is_resend: true,
    });
    return { kind: 'provisioning_failed', invitationId, message: 'A new invitation link could not be created.' };
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
    detail: accepted ? undefined
          : definitelyNotSent(delivery.outcome)
            ? 'The email was not sent. Use Resend to try again.'
            : 'It is not certain whether the email went out. Check before resending.',
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
