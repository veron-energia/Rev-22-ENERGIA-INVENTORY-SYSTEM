// One website order in, one database call out.
//
// Order of checks: configuration, the request envelope, the signature over the
// raw bytes, and only then JSON and the field whitelist. The database decides
// everything else (channel mode, test orders, customer matching, the invoice)
// and the answer it gives is passed back as it is.
//
// Status codes are the website's retry signal. 503 means "try again": the
// website's webhook answers Stripe with a 500 and Stripe redelivers, which is
// safe because both RPCs are keyed on the session id. Any 4xx means "sending
// this again now will not help", so the website logs it and carries on; that
// includes a database error of SQLSTATE class 22 (data exception), which the
// same order would hit on every retry. The one 4xx that is not final is 409
// not_found: names that arrived before their paid order, which can be sent
// again after `paid` succeeds.
//
// Kept free of the Supabase SDK so the tests run offline; index.ts supplies the
// real client.

import { logEvent } from '../_shared/auth-email/diagnostics.ts';
import { MissingConfigError, type OrderConfig } from './config.ts';
import { verifySignature } from './signature.ts';
import { validateOrderRequest } from './validate.ts';

export const MAX_BODY_BYTES = 16 * 1024;

export const RESULT_STATUSES = ['invoiced', 'recorded', 'needs_review', 'refused'] as const;
export type ResultStatus = (typeof RESULT_STATUSES)[number];

export interface OrderResult {
  status: ResultStatus;
  invoice_no: string | null;
  review_reason: string | null;
}

/** Just enough of a Supabase client to call an RPC. */
export interface RpcClient {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{
    data: unknown;
    error: { message?: string; code?: string } | null;
  }>;
}

export interface OrderDeps {
  loadConfig: () => OrderConfig;
  makeClient: (config: OrderConfig) => RpcClient;
  /** Milliseconds since the epoch. A seam for the freshness window. */
  now?: () => number;
}

function reply(body: Record<string, unknown>, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra },
  });
}

const retry = () => reply({ ok: false, error: 'retry' }, 503);

export async function handleOrder(req: Request, deps: OrderDeps): Promise<Response> {
  const now = deps.now ?? Date.now;
  const started = now();

  let config: OrderConfig;
  try {
    config = deps.loadConfig();
  } catch (error) {
    if (error instanceof MissingConfigError) {
      logEvent('web_order.config_missing', { names: error.names.join(' ') });
      return reply({ ok: false, error: 'not_configured' }, 503);
    }
    throw error;
  }

  if (req.method !== 'POST') return reply({ ok: false, error: 'method_not_allowed' }, 405, { Allow: 'POST' });

  const contentType = req.headers.get('content-type') ?? '';
  if (!contentType.toLowerCase().split(';')[0].trim().endsWith('application/json')) {
    return reply({ ok: false, error: 'unsupported_media_type' }, 415);
  }
  if (Number(req.headers.get('content-length') ?? '0') > MAX_BODY_BYTES) {
    return reply({ ok: false, error: 'payload_too_large' }, 413);
  }
  const raw = await readCapped(req, MAX_BODY_BYTES);
  if (raw === null) return reply({ ok: false, error: 'payload_too_large' }, 413);

  const problem = await verifySignature({
    secret: config.signingSecret,
    timestamp: req.headers.get('x-energia-timestamp'),
    signature: req.headers.get('x-energia-signature'),
    body: raw,
    nowSeconds: Math.floor(started / 1000),
  });
  if (problem) {
    logEvent('web_order.bad_signature', { reason: problem });
    return reply({ ok: false, error: 'bad_signature' }, 401);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(raw));
  } catch {
    return reply({ ok: false, error: 'invalid_json' }, 400);
  }

  const checked = validateOrderRequest(parsed);
  if (!checked.ok) {
    // The field's path, never its value.
    logEvent('web_order.invalid_request', { field: checked.field });
    return reply({ ok: false, error: 'invalid_request', field: checked.field }, 400);
  }

  const { type, order } = checked.value;
  const session = order.stripe_session_id;
  const fn = type === 'paid' ? 'web_order_paid' : 'web_order_names';

  let data: unknown;
  try {
    const answer = await deps.makeClient(config).rpc(fn, { p_order: order });
    if (answer.error) {
      // The code only. A Postgres message can quote the row it refused, and
      // that row may hold a phone number or an email.
      const code = safeCode(answer.error.code);
      if (isDataException(code)) {
        // Class 22: the database refused a value in this order. The same order
        // would be refused again, so a retry would only repeat it for days.
        logEvent('web_order.invalid_request', { type, session_id: session, field: 'order', code, ms: now() - started });
        return reply({ ok: false, error: 'invalid_request', field: 'order' }, 400);
      }
      logEvent('web_order.retry', { type, session_id: session, code, ms: now() - started });
      return retry();
    }
    data = answer.data;
  } catch {
    logEvent('web_order.retry', { type, session_id: session, code: 'network', ms: now() - started });
    return retry();
  }

  // The buyer registered before `paid` landed (Stripe is still retrying the
  // webhook), so web_order_names has no order to name. A 503 would be wrong
  // twice over: /register does not retry, and the log would point at the
  // database. It is its own 4xx, so the website can tell it apart and send the
  // names again once `paid` has been stored.
  if (type === 'names' && isNotFound(data)) {
    logEvent('web_order.names_before_paid', { type, session_id: session, status: 'not_found', ms: now() - started });
    return reply({ ok: false, error: 'not_found' }, 409);
  }

  const result = readResult(data);
  if (!result) {
    logEvent('web_order.retry', { type, session_id: session, code: 'unexpected_result', ms: now() - started });
    return retry();
  }

  logEvent('web_order.done', { type, session_id: session, status: result.status, ms: now() - started });
  return reply({ ok: true, ...result }, 200);
}

/** The RPC's `{status, invoice_no, review_reason}`, or null when it is anything else. */
export function readResult(data: unknown): OrderResult | null {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) return null;
  const d = data as Record<string, unknown>;
  if (typeof d.status !== 'string' || !(RESULT_STATUSES as readonly string[]).includes(d.status)) return null;
  const optional = (v: unknown) => (typeof v === 'string' && v ? v : null);
  return { status: d.status as ResultStatus, invoice_no: optional(d.invoice_no), review_reason: optional(d.review_reason) };
}

/** web_order_names' answer when no paid order has that session id yet. */
const isNotFound = (data: unknown): boolean =>
  data !== null && typeof data === 'object' && (data as Record<string, unknown>).status === 'not_found';

const safeCode = (code: unknown): string =>
  typeof code === 'string' && /^[A-Za-z0-9_]{1,16}$/.test(code) ? code : 'unknown';

/** SQLSTATE class 22, data exception: a value the database will never accept. */
const isDataException = (code: string): boolean => /^22[0-9A-Z]{3}$/.test(code);

// Content-Length can lie or be absent (chunked). Read with a hard ceiling, and
// keep the bytes: the signature is over exactly what arrived.
async function readCapped(req: Request, limit: number): Promise<Uint8Array | null> {
  if (!req.body) return new Uint8Array(0);
  const reader = req.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value) {
        total += value.byteLength;
        if (total > limit) { await reader.cancel().catch(() => {}); return null; }
        chunks.push(value);
      }
    }
  } finally {
    reader.releaseLock?.();
  }
  const merged = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) { merged.set(c, at); at += c.byteLength; }
  return merged;
}
