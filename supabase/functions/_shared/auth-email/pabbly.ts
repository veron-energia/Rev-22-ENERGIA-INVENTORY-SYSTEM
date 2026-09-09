// Handing a finished email to Pabbly Connect.
//
// Pabbly is a delivery step and nothing more. It never decides the recipient,
// the subject, the sender or the content — all of those are built here and sent
// as a complete message. The shared secret travels in the payload so the
// workflow can refuse anything that did not come from this function; it is not
// what protects the public endpoints, which is the rate limiter's job.
//
// Three outcomes are kept distinct on purpose, because conflating them is how
// people end up believing an email arrived when it did not:
//
//   accepted           Pabbly returned 2xx. It has the request. That is all this
//                      proves — not that Gmail ran, not that anything arrived.
//   provider_rejected  Pabbly answered with a non-2xx. Nothing was sent.
//   timeout            No answer inside the bounded wait. Pabbly may already
//                      have accepted and sent it. Never retried automatically.

import type { AuthEmailConfig } from './config.ts';
import { safeDetail, type DeliveryOutcome } from './diagnostics.ts';

export interface DeliveryRequest {
  requestId: string;
  actionType: 'verify_signup' | 'password_recovery' | 'password_changed' | 'user_invitation';
  to: string;
  subject: string;
  html: string;
  text: string;
  recipientRole: 'affiliate' | 'staff';
}

export interface DeliveryResult {
  outcome: DeliveryOutcome;
  httpStatus: number | null;
  detail: string;
}

/**
 * POST the message to the Pabbly webhook.
 *
 * Resolves for every outcome, including failure: the caller decides what a
 * failed send means for the request, and for signup it must not mean the new
 * account is thrown away.
 */
export async function deliver(
  config: AuthEmailConfig,
  request: DeliveryRequest,
  fetchImpl: typeof fetch = fetch,
): Promise<DeliveryResult> {
  const payload = {
    delivery_secret: config.pabblySharedSecret,
    request_id: request.requestId,
    action_type: request.actionType,
    to: request.to,
    from_name: config.fromName,
    from_email: config.fromAddress,
    reply_to: config.replyTo,
    subject: request.subject,
    html: request.html,
    text: request.text,
    recipient_role: request.recipientRole,
  };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), config.pabblyTimeoutMs);

  try {
    const response = await fetchImpl(config.pabblyWebhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // Lets the workflow deduplicate a replay without claiming exactly-once.
        'Idempotency-Key': request.requestId,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    const body = await response.text().catch(() => '');
    if (!response.ok) {
      return { outcome: 'provider_rejected', httpStatus: response.status, detail: safeDetail(body) };
    }
    return { outcome: 'accepted', httpStatus: response.status, detail: safeDetail(body, 120) };
  } catch (error) {
    const aborted = error instanceof DOMException
      ? error.name === 'AbortError'
      : (error as { name?: string })?.name === 'AbortError';
    if (aborted) {
      return {
        outcome: 'timeout',
        httpStatus: null,
        detail: `No response within ${config.pabblyTimeoutMs}ms; delivery state unknown.`,
      };
    }
    return { outcome: 'failed', httpStatus: null, detail: safeDetail(String(error)) };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Did the request definitely not go anywhere?
 *
 * `timeout` answers false: the message may well have been sent, so the caller
 * must not retry it and must not tell the user it definitely failed.
 */
export function definitelyNotSent(outcome: DeliveryOutcome): boolean {
  return outcome === 'provider_rejected' || outcome === 'failed';
}
