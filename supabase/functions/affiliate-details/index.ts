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
// them to Supabase and Pabbly. Every email takes one slot of the day's budget
// of 60 verify and reset emails (M6) first; see takeSend.
//
// Body: { action: 'start', changes: { first_name?, last_name?, phone?, email? } }
//       { action: 'verify', request_id, code }
//       { action: 'resend' | 'cancel', request_id }
//       { action: 'decide', request_id, approve, note }   (an Owner or Manager)
//       { action: 'verify_email_send' }   (M6: emails the 6-digit code that verifies the login's own email)

import { loadAllowedOrigins, loadConfig, MissingConfigError } from '../_shared/auth-email/config.ts';
import { adminClient } from '../_shared/auth-email/admin.ts';
import { clientKey, guardRequest, json, notConfigured } from '../_shared/auth-email/http.ts';
import { bearerToken } from '../_shared/auth-email/password.ts';
import { handleDetailsRequest } from '../_shared/auth-email/details.ts';
import { renderDetailsChanged, renderDetailsCode, renderVerifyCode } from '../_shared/auth-email/templates.ts';
import { deliver } from '../_shared/auth-email/pabbly.ts';
import { hashKey, reserve, takeSendSlot } from '../_shared/auth-email/ratelimit.ts';
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
      return notConfigured(requestId, origin, loadAllowedOrigins());
    }
    throw error;
  }
  const allowed = config.allowedOrigins;

  const guard = await guardRequest(req, allowed);
  if (!guard.ok) return guard.response;

  const admin = adminClient(config);

  // One send through Pabbly, with its outcome row (the address only hashed).
  const send = async (actionType: 'details_code' | 'details_changed' | 'verify_signup', to: string, message: { subject: string; html: string; text: string }) => {
    const recipientHash = await hashKey(to.toLowerCase(), config.hashSecret, 'email');
    // The verification code is logged under the 'resend' label the delivery table already knows.
    const label = actionType === 'verify_signup' ? 'resend' : actionType;
    try {
      const result = await deliver(config, {
        requestId, actionType, to, subject: message.subject, html: message.html, text: message.text, recipientRole: 'affiliate',
      });
      await recordOutcome(admin, { requestId, action: label, outcome: result.outcome, recipientHash, httpStatus: result.httpStatus, detail: result.detail });
      logEvent('auth_email.delivery', { action: label, request_id: requestId, outcome: result.outcome, http_status: result.httpStatus });
      return result.outcome === 'accepted';
    } catch (error) {
      await recordOutcome(admin, { requestId, action: label, outcome: 'failed', recipientHash, detail: safeDetail(String(error)) });
      logEvent('auth_email.delivery_failed', { action: label, request_id: requestId, detail: safeDetail(String(error)) });
      return false;
    }
  };

  const answer = await handleDetailsRequest(bearerToken(req), guard.body as Record<string, unknown>, {
    readUser: async (token) => {
      const { data, error } = await admin.auth.getUser(token);
      return error || !data?.user ? null : { id: data.user.id, email: data.user.email ?? null };
    },
    rpc: async (fn, args) => {
      const { data, error } = await admin.rpc(fn, args);
      return { data, error: error ? { message: error.message } : null };
    },
    setLoginEmail: async (userId, email) => {
      const { error } = await admin.auth.admin.updateUserById(userId, { email, email_confirm: true });
      return error ? { ok: false, error: safeDetail(error.message) } : { ok: true };
    },
    takeSend: async ({ loginEmail, userId, recipientEmail }) => {
      const slot = await takeSendSlot(admin, {
        emailHash: loginEmail ? await hashKey(loginEmail.toLowerCase(), config.hashSecret, 'email') : undefined,
        userId,
        recipientHash: recipientEmail ? await hashKey(recipientEmail.toLowerCase(), config.hashSecret, 'email') : undefined,
      });
      if (slot.result === 'unavailable') logEvent('auth_email.limiter_unavailable', { action: 'affiliate_details', request_id: requestId });
      return slot.result;
    },
    reserveResend: async (loginEmail) => {
      try {
        const ipHash = await hashKey(clientKey(req), config.hashSecret, 'ip');
        const emailHash = await hashKey(loginEmail.toLowerCase(), config.hashSecret, 'email');
        const r = await reserve(admin, 'resend', emailHash, ipHash);
        return { allowed: r.allowed, retryAfterSeconds: r.retryAfterSeconds };
      } catch {
        logEvent('auth_email.limiter_unavailable', { action: 'affiliate_details', request_id: requestId });
        return null;
      }
    },
    sendVerifyCode: (to, code) => send('verify_signup', to, renderVerifyCode(code)),
    sendCode: (to, code, purpose) => send('details_code', to, renderDetailsCode(code, purpose)),
    sendChanged: (to, changes) => send('details_changed', to, renderDetailsChanged(changes, new Date().toISOString(), config.replyTo)),
    log: (event, fields) => logEvent(event, { request_id: requestId, ...fields }),
  });

  const wait = answer.status === 429 ? Number(answer.body.retry_after_seconds) : 0;
  return json({ ...answer.body, ...(answer.status === 200 ? { server_request_id: requestId } : {}) }, answer.status, origin, allowed,
    wait > 0 ? { 'Retry-After': String(Math.ceil(wait)) } : {});
});
