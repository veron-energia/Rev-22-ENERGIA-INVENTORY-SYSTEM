// POST /functions/v1/auth-accept-invitation
//
// The invited user's side: set a password, and only then gain access.
//
//   supabase functions deploy auth-accept-invitation
//
// Body: { password }, or { check: true } to ask whether this login has a
// pending invitation (nothing is set). The account is read from the caller's
// own session, never from the body, so this cannot be pointed at somebody
// else's invitation.
//
// The decisions, and the order they run in, are in
// ../_shared/auth-email/accept.ts, with their tests:
//
//   1. Only a session opened from the emailed link may go on.
//   2. The login must have a pending invitation (429). A login with none (a
//      member of staff or an affiliate who opened a reset link), or with a
//      cancelled or used one, is refused before any password is set.
//   3. The link must have been opened in the last 30 minutes, like a reset
//      link (the Owner, 18 Oct 2026; the window of auth-change-password).
//      Longer ago: "This invitation link has expired. Ask for a new
//      invitation." An Owner or Manager presses Resend on Users & Roles.
//   4. Supabase changes the password, using the invited user's own token.
//   5. Only once Supabase has confirmed it does the database switch the
//      profile on, with the role and stores an ADMINISTRATOR chose.
//
// A browser saying "the password was set" is not accepted as evidence, because
// it is not evidence. Neither is a valid session on its own.

import { loadAllowedOrigins, loadConfig, MissingConfigError } from '../_shared/auth-email/config.ts';
import { adminClient } from '../_shared/auth-email/admin.ts';
import { guardRequest, json } from '../_shared/auth-email/http.ts';
import { bearerToken, changeOwnPassword, readOwnAccount } from '../_shared/auth-email/password.ts';
import {
  acceptInvitationRequest, invitationsOfLogin, LINK_NO_LONGER_VALID, profileStateOf, type TableReader,
} from '../_shared/auth-email/accept.ts';
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
    return json({ error: 'unauthorized', message: LINK_NO_LONGER_VALID }, 401, origin, allowed);
  }

  const admin = adminClient(config);
  // The two reads take only the part of the client they use. The full
  // client's types are too deep for TypeScript to compare with it.
  const tables = admin as unknown as TableReader;
  const answer = await acceptInvitationRequest(token, guard.body as Record<string, unknown>, {
    readAccount: () => readOwnAccount({ supabaseUrl: config.supabaseUrl, apiKey: config.publicApiKey, accessToken: token }),
    invitationsFor: (userId) => invitationsOfLogin(tables, userId),
    profileOf: (userId) => profileStateOf(tables, userId),
    changePassword: (password) => changeOwnPassword({
      supabaseUrl: config.supabaseUrl, apiKey: config.publicApiKey, accessToken: token, password,
    }),
    acceptInDatabase: async (userId, email) => {
      const { data, error } = await admin.rpc('invite_user_accept', { p_auth_user_id: userId, p_email: email });
      if (error) console.error('invite_user_accept failed', { request_id: requestId, error: error.message });
      return { data, error: error ? { message: error.message } : null };
    },
    notifyPasswordChanged: async (change) => {
      const notice = renderPasswordChanged(change.displayName || change.email, change.changedAt, config.replyTo);
      await deliver(config, {
        requestId, actionType: 'password_changed', to: change.email,
        subject: notice.subject, html: notice.html, text: notice.text,
        recipientRole: 'staff',
      });
    },
    log: (event, fields) => logEvent(event, { request_id: requestId, ...fields }),
  });
  return json(answer.body, answer.status, origin, allowed);
});
