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
// Body: { password, current_password? }. The recipient is never in the body:
// it is read back from the account Supabase just updated. There is no way to
// ask this endpoint to email somebody else, and no way to make it send by
// merely claiming a password change happened — a claim is not accepted, only a
// completed change is.
//
// Serves the recovery-link reset pages and the in-portal password change.
// 429 (ADMIN-AUTH-9): a session alone is no longer enough here. The change
// needs a session that came from an email link in the last 30 minutes (a
// reset link, a sign-in link, an invitation), or the current password, which
// Supabase Auth checks. The current password, when given, also goes to
// Supabase with the change.
//
// The decisions, and the order they run in, are in
// ../_shared/auth-email/change.ts, with their tests. This file only connects
// them to Supabase and Pabbly.
//
// The 30-minute rule is in this function only. Someone at a signed-in device
// who uses the browser's developer tools can still set a password through
// Supabase Auth directly from a session opened by an email link. No Supabase
// setting enforces 30 minutes. "Require current password when updating"
// closes the direct route for password sign-ins only.

import { loadAllowedOrigins, loadConfig, MissingConfigError } from '../_shared/auth-email/config.ts';
import { adminClient } from '../_shared/auth-email/admin.ts';
import { guardRequest, json } from '../_shared/auth-email/http.ts';
import { bearerToken, changeOwnPassword, checkCurrentPassword, readOwnAccount } from '../_shared/auth-email/password.ts';
import { changeOwnPasswordRequest } from '../_shared/auth-email/change.ts';
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
  const api = { supabaseUrl: config.supabaseUrl, apiKey: config.publicApiKey };

  const answer = await changeOwnPasswordRequest(token, guard.body as Record<string, unknown>, {
    readAccount: () => readOwnAccount({ ...api, accessToken: token ?? '' }),
    checkCurrentPassword: (email, password) => checkCurrentPassword({ ...api, email, password }),
    changePassword: (password, currentPassword) =>
      changeOwnPassword({ ...api, accessToken: token ?? '', password, currentPassword }),

    // The password is changed by now. The email only follows it.
    notify: async (change) => {
      const admin = adminClient(config);
      const recipientHash = await hashKey(change.email.toLowerCase(), config.hashSecret, 'email');

      // 429 (ADMIN-AUTH-17): staff were labelled "affiliate" too. A login with a
      // staff profile is staff; any other (an affiliate's) stays "affiliate".
      let recipientRole: 'staff' | 'affiliate' = 'affiliate';
      try {
        const { data: staffProfile } = await admin.from('profiles').select('id').eq('id', change.userId).maybeSingle();
        if (staffProfile) recipientRole = 'staff';
      } catch {
        // The label only steers the email's wording; the change is already made.
      }

      try {
        const message = renderPasswordChanged(change.displayName, change.changedAt, config.replyTo);
        const result = await deliver(config, {
          requestId,
          actionType: 'password_changed',
          to: change.email,
          subject: message.subject,
          html: message.html,
          text: message.text,
          recipientRole,
        });
        await recordOutcome(admin, {
          requestId, action: 'password_change', outcome: result.outcome,
          recipientHash, httpStatus: result.httpStatus, detail: result.detail,
        });
        logEvent('auth_email.delivery', { action: 'password_change', request_id: requestId, outcome: result.outcome, http_status: result.httpStatus });
        return result.outcome === 'accepted';
      } catch (error) {
        await recordOutcome(admin, { requestId, action: 'password_change', outcome: 'failed', recipientHash, detail: safeDetail(String(error)) });
        logEvent('auth_email.notification_failed', { request_id: requestId, detail: safeDetail(String(error)) });
        return false;
      }
    },
    log: (event, fields) => logEvent(event, { request_id: requestId, ...fields }),
  });

  // `notified` reports that Pabbly accepted the request — not that the email
  // arrived. The frontend treats it as a footnote, never as the outcome.
  const reply = answer.status === 200 ? { ...answer.body, request_id: requestId } : answer.body;
  return json(reply, answer.status, origin, allowed);
});
