// POST /functions/v1/admin-invite-user
//
// Creates, resends and cancels invitations for internal users.
//
//   supabase functions deploy admin-invite-user
//
// Note the missing --no-verify-jwt: this endpoint requires a signed-in
// administrator, so the gateway should check the token too. The function does
// not rely on that — every permission decision is made by a database function
// running as the caller, so an unauthenticated or under-privileged request is
// refused by the database regardless of how the gateway is configured.
//
// Body: { action: 'create' | 'resend' | 'cancel', ... }.
//
// The generated invitation link is never in a response and never in a log line.
// It goes into the email and nowhere else, so an administrator cannot forward
// it, paste it, or accidentally hand somebody else an account.

import { loadAllowedOrigins, loadConfig, MissingConfigError } from '../_shared/auth-email/config.ts';
import { adminClient, generateInviteLink, regenerateSignupLink } from '../_shared/auth-email/admin.ts';
import { guardRequest, json } from '../_shared/auth-email/http.ts';
import { bearerToken } from '../_shared/auth-email/password.ts';
import { callbackUrl } from '../_shared/auth-email/redirects.ts';
import { deliver } from '../_shared/auth-email/pabbly.ts';
import { logEvent, newRequestId } from '../_shared/auth-email/diagnostics.ts';
import {
  cancelInvitation, createInvitation, resendInvitation, validateInvite,
  type InvitationDeps,
} from '../_shared/auth-email/invitations.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.108.2';

Deno.serve(async (req) => {
  const requestId = newRequestId();
  const origin = req.headers.get('origin');

  let config;
  try {
    config = loadConfig();
  } catch (error) {
    if (error instanceof MissingConfigError) {
      logEvent('auth_email.config_missing', { action: 'invite', request_id: requestId, names: error.names.join(' ') });
      return json({ error: 'not_configured', missing: error.names }, 503, origin, loadAllowedOrigins());
    }
    throw error;
  }
  const allowed = config.allowedOrigins;

  const guard = await guardRequest(req, allowed);
  if (!guard.ok) return guard.response;

  const token = bearerToken(req);
  if (!token) {
    return json({ error: 'unauthorized', message: 'Please sign in again and retry.' }, 401, origin, allowed);
  }

  const body = (guard.body ?? {}) as Record<string, unknown>;
  const action = String(body.action ?? '');

  // Two clients, two jobs. The caller client carries the administrator's own
  // token, so auth.uid() inside every permission function is them and a role
  // cannot be claimed. The admin client is used only for creating the Auth
  // account and for the two server-only functions.
  const caller = createClient(config.supabaseUrl, config.publicApiKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = adminClient(config);

  // Who is asking, from the token rather than the body.
  const { data: me, error: meError } = await caller.auth.getUser();
  if (meError || !me?.user) {
    return json({ error: 'unauthorized', message: 'Please sign in again and retry.' }, 401, origin, allowed);
  }
  const { data: myProfile } = await caller
    .from('profiles').select('full_name').eq('id', me.user.id).maybeSingle();
  const invitedByName = (myProfile as { full_name?: string } | null)?.full_name;

  const deps: InvitationDeps = {
    callerRpc: (fn, args) => caller.rpc(fn, args) as never,
    adminRpc: (fn, args) => admin.rpc(fn, args) as never,
    generateInviteLink, regenerateSignupLink, deliver, admin,
  };

  const redirectTo = callbackUrl(config, 'user_invitation', origin);

  try {
    if (action === 'create') {
      const parsed = validateInvite({
        requestId: body.request_id as string,
        email: body.email as string,
        fullName: body.full_name as string,
        role: body.role as never,
        workPhone: body.work_phone as string,
        personalPhone: body.personal_phone as string,
        personalEmail: body.personal_email as string,
        storeIds: body.store_ids as string[],
      });
      if (!parsed.ok) {
        return json({ error: 'invalid_request', field: parsed.field, message: parsed.message }, 400, origin, allowed);
      }

      const result = await createInvitation(deps, config, parsed.value, redirectTo, invitedByName);
      logEvent('user_invitation.create', {
        request_id: requestId, outcome: result.kind,
        // The address is not logged, and neither is the link.
        role: parsed.value.role,
      });

      switch (result.kind) {
        case 'created':
          return json({
            ok: true, invitation_id: result.invitationId, email: result.email,
            delivery: result.delivery, detail: result.detail,
          }, 200, origin, allowed);
        case 'forbidden':
          return json({ error: 'forbidden', message: result.message, field: result.field }, 403, origin, allowed);
        case 'invalid':
          return json({ error: 'invalid_request', field: result.field, message: result.message }, 400, origin, allowed);
        case 'email_in_use':
          return json({ error: 'email_in_use', scope: result.scope, message: result.message }, 409, origin, allowed);
        case 'existing_pending':
        case 'existing_request':
          return json({ error: 'already_invited', invitation_id: result.invitationId, message: result.message }, 409, origin, allowed);
        default:
          return json({ error: 'provisioning_failed', invitation_id: (result as { invitationId?: string }).invitationId,
                        message: result.message }, 502, origin, allowed);
      }
    }

    if (action === 'resend') {
      const invitationId = String(body.invitation_id ?? '');
      if (!/^[0-9a-f-]{36}$/i.test(invitationId)) {
        return json({ error: 'invalid_request', message: 'An invitation is required.' }, 400, origin, allowed);
      }
      const result = await resendInvitation(deps, config, invitationId, redirectTo, requestId, invitedByName);
      logEvent('user_invitation.resend', { request_id: requestId, outcome: result.kind });

      if (result.kind === 'created') {
        return json({ ok: true, invitation_id: result.invitationId, delivery: result.delivery, detail: result.detail }, 200, origin, allowed);
      }
      if (result.kind === 'forbidden') return json({ error: 'forbidden', message: result.message }, 403, origin, allowed);
      if (result.kind === 'rate_limited') {
        return json({ error: 'rate_limited', message: result.message,
                      retry_after_seconds: result.retryAfterSeconds }, 429, origin, allowed);
      }
      return json({ error: 'resend_failed', message: (result as { message: string }).message }, 502, origin, allowed);
    }

    if (action === 'cancel') {
      const invitationId = String(body.invitation_id ?? '');
      if (!/^[0-9a-f-]{36}$/i.test(invitationId)) {
        return json({ error: 'invalid_request', message: 'An invitation is required.' }, 400, origin, allowed);
      }
      const reason = String(body.reason ?? '').slice(0, 300);
      const result = await cancelInvitation(deps, invitationId, reason);
      logEvent('user_invitation.cancel', { request_id: requestId, outcome: result.kind });

      if (result.kind === 'cancelled') return json({ ok: true }, 200, origin, allowed);
      if (result.kind === 'forbidden') return json({ error: 'forbidden', message: result.message }, 403, origin, allowed);
      return json({ error: 'cancel_failed', message: result.message }, 400, origin, allowed);
    }

    return json({ error: 'invalid_request', message: 'Unknown action.' }, 400, origin, allowed);
  } catch (error) {
    // Never echo an internal error to the browser: it is the one place a
    // connection string or a key could leak through this endpoint.
    logEvent('user_invitation.error', { request_id: requestId, action });
    console.error('admin-invite-user failed', { request_id: requestId, action, error: String(error) });
    return json({ error: 'internal_error', message: 'Something went wrong. Please try again.' }, 500, origin, allowed);
  }
});
