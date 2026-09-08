// POST /functions/v1/auth-change-password
//
// Sets a new password for the signed-in caller and, only once Supabase has
// confirmed the change, sends the "your password was changed" notification.
//
//   supabase functions deploy auth-change-password
//
// Note the missing --no-verify-jwt: this endpoint requires a session, so the
// gateway should check the JWT too. The function does not rely on that — it uses
// the caller's token to make the change, so an unauthenticated request cannot do
// anything regardless of how the gateway is configured.
//
// Body: { password }. The recipient is never in the body: it is read back from
// the account Supabase just updated. There is no way to ask this endpoint to
// email somebody else, and no way to make it send by merely claiming a password
// change happened — a claim is not accepted, only a completed change is.
//
// Serves both the recovery-link reset page and the in-portal password change,
// because a recovery session is an ordinary session as far as this is concerned.

import { loadAllowedOrigins, loadConfig, MissingConfigError } from '../_shared/auth-email/config.ts';
import { adminClient } from '../_shared/auth-email/admin.ts';
import { guardRequest, json } from '../_shared/auth-email/http.ts';
import { validatePasswordChange } from '../_shared/auth-email/validate.ts';
import { bearerToken, changeOwnPassword } from '../_shared/auth-email/password.ts';
import { renderPasswordChanged } from '../_shared/auth-email/templates.ts';
import { deliver } from '../_shared/auth-email/pabbly.ts';
import { hashKey } from '../_shared/auth-email/ratelimit.ts';
import { logEvent, newRequestId, recordOutcome, safeDetail } from '../_shared/auth-email/diagnostics.ts';

Deno.serve(async (req) => {
  const requestId = newRequestId();
  const origin = req.headers.get('origin');

  let config;
  try {
    config = loadConfig();
  } catch (error) {
    if (error instanceof MissingConfigError) {
      logEvent('auth_email.config_missing', { action: 'password_change', request_id: requestId, names: error.names.join(' ') });
      return json({ error: 'not_configured', missing: error.names }, 503, origin, loadAllowedOrigins());
    }
    throw error;
  }
  const allowed = config.allowedOrigins;

  const guard = await guardRequest(req, allowed);
  if (!guard.ok) return guard.response;

  const token = bearerToken(req);
  if (!token) return json({ error: 'unauthorized', message: 'Please sign in again and retry.' }, 401, origin, allowed);

  const parsed = validatePasswordChange(guard.body);
  if (!parsed.ok) {
    return json({ error: 'invalid_request', fields: { [parsed.errors[0].field]: parsed.errors[0].message } }, 400, origin, allowed);
  }

  const change = await changeOwnPassword({
    supabaseUrl: config.supabaseUrl,
    apiKey: config.publicApiKey,
    accessToken: token,
    password: parsed.value.password,
  });

  if (change.status === 'unauthorized') {
    return json({ error: 'unauthorized', message: 'Your session has expired. Please use the link again or sign in.' }, 401, origin, allowed);
  }
  if (change.status === 'rejected') {
    return json({ error: 'password_rejected', message: change.message }, 400, origin, allowed);
  }
  if (change.status === 'error') {
    logEvent('auth_email.password_change_error', { request_id: requestId, detail: safeDetail(change.message) });
    return json({ error: 'temporarily_unavailable', message: 'We could not update your password just now. Please try again shortly.' }, 503, origin, allowed);
  }

  // The password is changed. Whatever happens to the notification from here, the
  // answer to "did my password change?" is yes, and the response must say so.
  const admin = adminClient(config);
  const recipientHash = await hashKey(change.email.toLowerCase(), config.hashSecret, 'email');

  let notified = false;
  try {
    const message = renderPasswordChanged(change.displayName, change.changedAt, config.replyTo);
    const result = await deliver(config, {
      requestId,
      actionType: 'password_changed',
      to: change.email,
      subject: message.subject,
      html: message.html,
      text: message.text,
      recipientRole: 'affiliate',
    });
    notified = result.outcome === 'accepted';
    await recordOutcome(admin, {
      requestId, action: 'password_change', outcome: result.outcome,
      recipientHash, httpStatus: result.httpStatus, detail: result.detail,
    });
    logEvent('auth_email.delivery', { action: 'password_change', request_id: requestId, outcome: result.outcome, http_status: result.httpStatus });
  } catch (error) {
    await recordOutcome(admin, { requestId, action: 'password_change', outcome: 'failed', recipientHash, detail: safeDetail(String(error)) });
    logEvent('auth_email.notification_failed', { request_id: requestId, detail: safeDetail(String(error)) });
  }

  // `notified` reports that Pabbly accepted the request — not that the email
  // arrived. The frontend treats it as a footnote, never as the outcome.
  return json({ ok: true, password_changed: true, notified, request_id: requestId }, 200, origin, allowed);
});
