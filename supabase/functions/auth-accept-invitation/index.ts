// POST /functions/v1/auth-accept-invitation
//
// The invited user's side: set a password, and only then gain access.
//
//   supabase functions deploy auth-accept-invitation
//
// Body: { password }. The account is read from the caller's own session, never
// from the body, so this cannot be pointed at somebody else's invitation.
//
// The order matters and is the whole security argument:
//
//   1. Supabase changes the password, using the invited user's own token. If
//      that fails, nothing else happens.
//   2. Only once Supabase has confirmed it does the database activate the
//      profile — and it activates the role and stores an ADMINISTRATOR chose,
//      never anything this request carried.
//
// A browser saying "the password was set" is not accepted as evidence, because
// it is not evidence. Neither is a valid session on its own: a link issued
// before an invitation was cancelled still produces one, and invite_user_accept
// refuses it.

import { loadAllowedOrigins, loadConfig, MissingConfigError } from '../_shared/auth-email/config.ts';
import { adminClient } from '../_shared/auth-email/admin.ts';
import { guardRequest, json } from '../_shared/auth-email/http.ts';
import { validatePasswordChange } from '../_shared/auth-email/validate.ts';
import { bearerToken, changeOwnPassword } from '../_shared/auth-email/password.ts';
import { renderPasswordChanged } from '../_shared/auth-email/templates.ts';
import { deliver } from '../_shared/auth-email/pabbly.ts';
import { logEvent, newRequestId } from '../_shared/auth-email/diagnostics.ts';

Deno.serve(async (req) => {
  const requestId = newRequestId();
  const origin = req.headers.get('origin');

  let config;
  try {
    config = loadConfig();
  } catch (error) {
    if (error instanceof MissingConfigError) {
      return json({ error: 'not_configured', missing: error.names }, 503, origin, loadAllowedOrigins());
    }
    throw error;
  }
  const allowed = config.allowedOrigins;

  const guard = await guardRequest(req, allowed);
  if (!guard.ok) return guard.response;

  const token = bearerToken(req);
  if (!token) {
    return json({
      error: 'unauthorized',
      message: 'This invitation link is no longer valid. Ask for a new invitation.',
    }, 401, origin, allowed);
  }

  const parsed = validatePasswordChange(guard.body);
  if (!parsed.ok) {
    return json({ error: 'invalid_request', fields: { [parsed.errors[0].field]: parsed.errors[0].message } },
                400, origin, allowed);
  }

  // Step 1: Supabase sets the password with the invited user's own token.
  const change = await changeOwnPassword({
    supabaseUrl: config.supabaseUrl,
    apiKey: config.publicApiKey,
    accessToken: token,
    password: (guard.body as { password: string }).password,
  });

  if (change.status === 'unauthorized') {
    logEvent('user_invitation.accept_password_failed', { request_id: requestId, kind: 'unauthorized' });
    return json({
      error: 'unauthorized',
      message: 'This invitation link has expired or has already been used. Ask for a new invitation.',
    }, 401, origin, allowed);
  }
  if (change.status === 'rejected') {
    // The invitation stays pending. Nothing has been activated, and they can
    // try a different password on the same link.
    logEvent('user_invitation.accept_password_failed', { request_id: requestId, kind: 'rejected' });
    return json({ error: 'password_rejected', message: change.message }, 400, origin, allowed);
  }
  if (change.status === 'error') {
    logEvent('user_invitation.accept_password_failed', { request_id: requestId, kind: 'error' });
    return json({
      error: 'temporarily_unavailable',
      message: 'We could not set your password just now. Please try again shortly.',
    }, 503, origin, allowed);
  }

  // Step 2: activation, on the strength of a confirmed password change.
  const admin = adminClient(config);
  const { data, error } = await admin.rpc('invite_user_accept', {
    p_auth_user_id: change.userId,
    p_email: change.email,
  });

  if (error) {
    logEvent('user_invitation.accept_failed', { request_id: requestId });
    console.error('invite_user_accept failed', { request_id: requestId, error: error.message });
    return json({
      error: 'activation_failed',
      // The password IS set at this point, so say so rather than implying the
      // whole thing failed and inviting them to try a used link again.
      message: 'Your password was set, but your access could not be switched on. '
             + 'Ask whoever invited you to check your account.',
    }, 502, origin, allowed);
  }

  const result = (data ?? {}) as { activated?: boolean; reason?: string; message?: string; role?: string };
  if (!result.activated) {
    logEvent('user_invitation.accept_refused', { request_id: requestId, reason: result.reason ?? 'unknown' });
    return json({
      error: 'not_activated', reason: result.reason,
      message: result.message ?? 'This invitation can no longer be used.',
    }, 403, origin, allowed);
  }

  // The same notification every other password change sends. Failure here does
  // not undo the activation — the account is legitimately set up either way.
  const notice = renderPasswordChanged(change.displayName || change.email, change.changedAt, config.replyTo);
  await deliver(config, {
    requestId, actionType: 'password_changed', to: change.email,
    subject: notice.subject, html: notice.html, text: notice.text,
    recipientRole: 'staff',
  }).catch(() => undefined);

  logEvent('user_invitation.accepted', { request_id: requestId, role: result.role ?? '' });
  return json({ ok: true, role: result.role }, 200, origin, allowed);
});
