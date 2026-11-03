// POST /functions/v1/affiliate-details
//
// 491 (3 Nov 2026): an affiliate changes their own name, phone or email from
// the portal's Account page, and an Owner or Manager decides the changes that
// wait for staff (the Affiliates page).
//
//   supabase functions deploy affiliate-details
//
// The JWT is required (no --no-verify-jwt): every action is for the signed-in
// caller, read from their token here; the body never names whose details
// change. The rules are the database's (491); the steps are in
// ../_shared/auth-email/details.ts, with their tests. This file only connects
// them to Supabase and Pabbly.
//
// Body: { action: 'start', changes: { first_name?, last_name?, phone?, email? } }
//       { action: 'verify', request_id, code }
//       { action: 'resend' | 'cancel', request_id }
//       { action: 'decide', request_id, approve, note }   (an Owner or Manager)

import { loadAllowedOrigins, loadConfig, MissingConfigError } from '../_shared/auth-email/config.ts';
import { adminClient } from '../_shared/auth-email/admin.ts';
import { guardRequest, json } from '../_shared/auth-email/http.ts';
import { bearerToken } from '../_shared/auth-email/password.ts';
import { handleDetailsRequest } from '../_shared/auth-email/details.ts';
import { renderDetailsChanged, renderDetailsCode } from '../_shared/auth-email/templates.ts';
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
      logEvent('auth_email.config_missing', { action: 'affiliate_details', request_id: requestId, names: error.names.join(' ') });
      return json({ error: 'not_configured', missing: error.names }, 503, origin, loadAllowedOrigins());
    }
    throw error;
  }
  const allowed = config.allowedOrigins;

  const guard = await guardRequest(req, allowed);
  if (!guard.ok) return guard.response;

  const admin = adminClient(config);

  // One send through Pabbly, with its outcome row (the address only hashed).
  const send = async (actionType: 'details_code' | 'details_changed', to: string, message: { subject: string; html: string; text: string }) => {
    const recipientHash = await hashKey(to.toLowerCase(), config.hashSecret, 'email');
    try {
      const result = await deliver(config, {
        requestId, actionType, to, subject: message.subject, html: message.html, text: message.text, recipientRole: 'affiliate',
      });
      await recordOutcome(admin, { requestId, action: actionType, outcome: result.outcome, recipientHash, httpStatus: result.httpStatus, detail: result.detail });
      logEvent('auth_email.delivery', { action: actionType, request_id: requestId, outcome: result.outcome, http_status: result.httpStatus });
      return result.outcome === 'accepted';
    } catch (error) {
      await recordOutcome(admin, { requestId, action: actionType, outcome: 'failed', recipientHash, detail: safeDetail(String(error)) });
      logEvent('auth_email.delivery_failed', { action: actionType, request_id: requestId, detail: safeDetail(String(error)) });
      return false;
    }
  };

  const answer = await handleDetailsRequest(bearerToken(req), guard.body as Record<string, unknown>, {
    readUser: async (token) => {
      const { data, error } = await admin.auth.getUser(token);
      return error || !data?.user ? null : { id: data.user.id };
    },
    rpc: async (fn, args) => {
      const { data, error } = await admin.rpc(fn, args);
      return { data, error: error ? { message: error.message } : null };
    },
    setLoginEmail: async (userId, email) => {
      const { error } = await admin.auth.admin.updateUserById(userId, { email, email_confirm: true });
      return error ? { ok: false, error: safeDetail(error.message) } : { ok: true };
    },
    sendCode: (to, code, purpose) => send('details_code', to, renderDetailsCode(code, purpose)),
    sendChanged: (to, changes) => send('details_changed', to, renderDetailsChanged(changes, new Date().toISOString(), config.replyTo)),
    log: (event, fields) => logEvent(event, { request_id: requestId, ...fields }),
  });

  return json({ ...answer.body, ...(answer.status === 200 ? { server_request_id: requestId } : {}) }, answer.status, origin, allowed);
});
