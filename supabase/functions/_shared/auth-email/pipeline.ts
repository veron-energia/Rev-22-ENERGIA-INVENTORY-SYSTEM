// The shape every public Auth-email endpoint shares.
//
// Signup, resend and recovery differ only in what they validate and what they
// generate. The envelope around that — configuration, request guards, keyed
// hashing, atomic reservation, outcome recording, and a response that gives away
// nothing about the account — is identical, so it lives here once.
//
// The response is the part worth reading twice. Whatever happened inside, a
// caller sees the same body for a brand-new account, an unverified one, a
// verified one and an address with no account at all. Account status is never
// distinguishable from the outside: not in the body, not in the status code, and
// not in how long the request took to fail.

import { loadAllowedOrigins, loadConfig, MissingConfigError, type AuthEmailConfig } from './config.ts';
import { adminClient } from './admin.ts';
import { guardRequest, json, trustedClientIp } from './http.ts';
import { hashKey, rateLimitMessage, reserve, RateLimiterUnavailableError, type LimitedAction } from './ratelimit.ts';
import { logEvent, newRequestId, recordOutcome, safeDetail } from './diagnostics.ts';
import { definitelyNotSent } from './pabbly.ts';
import type { DeliveryResult } from './pabbly.ts';
import type { FieldError, Validated } from './validate.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

export interface PublicContext<T> {
  config: AuthEmailConfig;
  admin: Admin;
  value: T;
  requestId: string;
  origin: string | null;
  emailHash: string;
}

export type EndpointResult =
  /** Deliberately sent nothing — no account, or already verified. */
  | { kind: 'suppressed'; reason: string }
  /** Handed to Pabbly; the result says what Pabbly did with it. */
  | { kind: 'delivered'; result: DeliveryResult }
  /** Something on our side went wrong before a send was attempted. */
  | { kind: 'internal_error'; detail: string };

/**
 * Test seam. Production passes nothing and gets the real configuration loader
 * and the real service-role client; a test supplies both and never touches a
 * network or a Supabase project.
 */
export interface PipelineDeps {
  loadConfig?: () => AuthEmailConfig;
  makeAdmin?: (config: AuthEmailConfig) => Admin;
}

export interface PublicEndpoint<T> {
  action: LimitedAction;
  /** Machine label for logs and the delivery table. */
  parse: (body: Record<string, unknown>, config: AuthEmailConfig) => Validated<T>;
  emailOf: (value: T) => string;
  run: (ctx: PublicContext<T>) => Promise<EndpointResult>;
}

export async function handlePublicRequest<T>(
  req: Request,
  endpoint: PublicEndpoint<T>,
  deps: PipelineDeps = {},
): Promise<Response> {
  const requestId = newRequestId();
  const origin = req.headers.get('origin');

  // Configuration first: without it there is no allowlist to answer from.
  let config: AuthEmailConfig;
  try {
    config = (deps.loadConfig ?? loadConfig)();
  } catch (error) {
    if (error instanceof MissingConfigError) {
      logEvent('auth_email.config_missing', { action: endpoint.action, request_id: requestId, names: error.names.join(' ') });
      // Names only — a missing-secret error must never quote a value — but with
      // real CORS headers, so the browser lets the page read which names.
      return json({ error: 'not_configured', missing: error.names }, 503, origin, loadAllowedOrigins());
    }
    throw error;
  }
  const allowed = config.allowedOrigins;

  const guard = await guardRequest(req, allowed);
  if (!guard.ok) return guard.response;

  const parsed = endpoint.parse(guard.body, config);
  if (!parsed.ok) {
    return json({ error: 'invalid_request', fields: shapeErrors(parsed.errors) }, 400, origin, allowed);
  }

  const email = endpoint.emailOf(parsed.value);
  const ip = trustedClientIp(req, config.trustedProxyHops);

  const emailHash = await hashKey(email, config.hashSecret, 'email');
  const ipHash = ip ? await hashKey(ip, config.hashSecret, 'ip') : null;

  const admin = (deps.makeAdmin ?? adminClient)(config);

  // Reserve before anything is generated or sent, and never give the slot back.
  let reservation;
  try {
    reservation = await reserve(admin, endpoint.action, emailHash, ipHash);
  } catch (error) {
    // Fail closed. A limiter that cannot answer is not permission to proceed.
    logEvent('auth_email.limiter_unavailable', {
      action: endpoint.action, request_id: requestId,
      cause: error instanceof RateLimiterUnavailableError ? safeDetail(error.message, 120) : 'unknown',
    });
    return json({ error: 'temporarily_unavailable', message: 'We could not process that request just now. Please try again shortly.' },
      503, origin, allowed);
  }

  if (!reservation.allowed) {
    logEvent('auth_email.rate_limited', {
      action: endpoint.action, request_id: requestId,
      retry_after: reservation.retryAfterSeconds, ip_seen: ip !== null,
    });
    return json(
      { error: 'rate_limited', message: rateLimitMessage(reservation.retryAfterSeconds), retry_after_seconds: reservation.retryAfterSeconds },
      429, origin, allowed,
      { 'Retry-After': String(Math.max(1, reservation.retryAfterSeconds)) },
    );
  }

  await recordOutcome(admin, { requestId, action: endpoint.action, outcome: 'requested', recipientHash: emailHash });

  let result: EndpointResult;
  try {
    result = await endpoint.run({ config, admin, value: parsed.value, requestId, origin, emailHash });
  } catch (error) {
    result = { kind: 'internal_error', detail: safeDetail(String(error)) };
  }

  return await finish(admin, { requestId, action: endpoint.action, emailHash, origin, allowed, ipSeen: ip !== null }, result);
}

async function finish(
  admin: Admin,
  meta: { requestId: string; action: string; emailHash: string; origin: string | null; allowed: string[]; ipSeen: boolean },
  result: EndpointResult,
): Promise<Response> {
  const { requestId, action, emailHash, origin, allowed } = meta;

  if (result.kind === 'internal_error') {
    await recordOutcome(admin, { requestId, action, outcome: 'failed', recipientHash: emailHash, detail: result.detail });
    logEvent('auth_email.internal_error', { action, request_id: requestId, detail: result.detail });
    return json({ error: 'temporarily_unavailable', message: 'We could not process that request just now. Please try again shortly.' },
      503, origin, allowed);
  }

  if (result.kind === 'suppressed') {
    await recordOutcome(admin, { requestId, action, outcome: 'suppressed', recipientHash: emailHash, detail: result.reason });
    logEvent('auth_email.suppressed', { action, request_id: requestId, reason: result.reason, ip_seen: meta.ipSeen });
    // Identical to the success body below — that is the point.
    return json({ ok: true, status: 'submitted', request_id: requestId }, 200, origin, allowed);
  }

  const { outcome, httpStatus, detail } = result.result;
  await recordOutcome(admin, { requestId, action, outcome, recipientHash: emailHash, httpStatus, detail });
  logEvent('auth_email.delivery', { action, request_id: requestId, outcome, http_status: httpStatus, ip_seen: meta.ipSeen });

  // "accepted" means Pabbly took the request, not that an email arrived, so the
  // status stays "submitted" rather than anything that sounds like confirmation.
  const status = definitelyNotSent(outcome) ? 'not_sent' : 'submitted';
  return json({ ok: true, status, request_id: requestId }, 200, origin, allowed);
}

function shapeErrors(errors: FieldError[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const e of errors) if (!(e.field in out)) out[e.field] = e.message;
  return out;
}
