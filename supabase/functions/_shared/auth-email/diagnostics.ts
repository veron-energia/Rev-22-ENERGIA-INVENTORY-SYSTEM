// Logging and delivery bookkeeping that are safe to leave switched on.
//
// The rule for every log line and every stored row: an identifier, an outcome
// and a duration are fine; an email address, an action link, a token, a password
// or a provider secret is not. Anything that came back from a provider is
// truncated before it is recorded, because provider messages sometimes echo the
// request back.

import type { RpcRunner } from './ratelimit.ts';

export type DeliveryOutcome =
  | 'requested' | 'suppressed' | 'accepted' | 'provider_rejected' | 'timeout' | 'failed';

export const newRequestId = (): string => crypto.randomUUID();

/** Structured, greppable, and deliberately free of anything identifying. */
export function logEvent(event: string, fields: Record<string, string | number | boolean | null>): void {
  const safe: Record<string, unknown> = { event };
  for (const [k, v] of Object.entries(fields)) {
    if (v === null || typeof v === 'number' || typeof v === 'boolean') { safe[k] = v; continue; }
    safe[k] = String(v).replace(/[\r\n]+/g, ' ').slice(0, 200);
  }
  console.log(JSON.stringify(safe));
}

/** Provider text, shortened and stripped of newlines, for troubleshooting only. */
export function safeDetail(value: unknown, max = 300): string {
  if (value === null || value === undefined) return '';
  const text = typeof value === 'string' ? value : (() => {
    try { return JSON.stringify(value); } catch { return String(value); }
  })();
  return text.replace(/[\r\n]+/g, ' ').slice(0, max);
}

/**
 * Record what happened to a send. Best effort on purpose: failing to write a
 * troubleshooting row must never turn a completed request into an error.
 */
export async function recordOutcome(
  admin: RpcRunner<{ error: unknown }>,
  args: {
    requestId: string;
    action: string;
    outcome: DeliveryOutcome;
    recipientHash?: string | null;
    httpStatus?: number | null;
    detail?: string | null;
  },
): Promise<void> {
  try {
    const { error } = await admin.rpc('auth_email_record_outcome', {
      p_request_id: args.requestId,
      p_action: args.action,
      p_outcome: args.outcome,
      p_recipient_hash: args.recipientHash ?? null,
      p_http_status: args.httpStatus ?? null,
      p_detail: args.detail ?? null,
    });
    if (error) logEvent('auth_email.outcome_write_failed', { request_id: args.requestId, action: args.action });
  } catch {
    logEvent('auth_email.outcome_write_failed', { request_id: args.requestId, action: args.action });
  }
}
