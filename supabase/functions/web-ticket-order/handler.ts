// One website order in, one database call out.
//
// Order of checks: configuration, the request envelope, the signature over the
// raw bytes, and only then JSON and the field whitelist. The database decides
// everything else (channel mode, test orders, customer matching, the invoice)
// and the answer it gives is passed back as it is.
//
// Status codes are the website's retry signal. 503 means "try again": the
// website's webhook answers Stripe with a 500 and Stripe redelivers, which is
// safe because every RPC is keyed on the session (or OFF) id, or (380's sync
// and staff) only asks: a sync just notes when it ran. Any 4xx means "sending
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
// 380: a staff-link registration a Manager dismissed says so when it is sent again.
export const DOOR_RESULT_STATUSES = [...RESULT_STATUSES, 'dismissed'] as const;
export type ResultStatus = (typeof DOOR_RESULT_STATUSES)[number];

// 380: the database function behind each message.
const RPC = {
  paid: 'web_order_paid', names: 'web_order_names', door: 'web_order_door', sync: 'web_order_sync', staff: 'web_order_staff',
} as const;
export const SYNC_STATUSES = ['ok', 'too_soon', 'refused'] as const;
export const STAFF_STATUSES = ['ok', 'refused'] as const;

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

  const request = checked.value;
  const type = request.type;
  const fn = RPC[type];
  // What the logs say the request was about: the checkout id, the OFF id, or
  // (sync, staff) the channel. None of them is personal.
  const about: Record<string, string> = request.type === 'sync' || request.type === 'staff'
    ? { channel: request.channel }
    : { session_id: request.type === 'door' ? request.order.order_id : request.order.stripe_session_id };
  const args = request.type === 'sync' || request.type === 'staff' ? { p_channel: request.channel } : { p_order: request.order };

  let data: unknown;
  try {
    const answer = await deps.makeClient(config).rpc(fn, args);
    if (answer.error) {
      // The code only. A Postgres message can quote the row it refused, and
      // that row may hold a phone number or an email.
      const code = safeCode(answer.error.code);
      if (isDataException(code)) {
        // Class 22: the database refused a value in this order. The same order
        // would be refused again, so a retry would only repeat it for days.
        logEvent('web_order.invalid_request', { type, ...about, field: 'order', code, ms: now() - started });
        return reply({ ok: false, error: 'invalid_request', field: 'order' }, 400);
      }
      logEvent('web_order.retry', { type, ...about, code, ms: now() - started });
      return retry();
    }
    data = answer.data;
  } catch {
    logEvent('web_order.retry', { type, ...about, code: 'network', ms: now() - started });
    return retry();
  }

  // 380: the sync and the staff list are passed back as the database built
  // them, keeping only their own fields. They carry names and contacts, so
  // only counts are logged.
  if (type === 'sync' || type === 'staff') {
    const answer = type === 'sync' ? readSync(data) : readStaff(data);
    if (!answer) {
      logEvent('web_order.retry', { type, ...about, code: 'unexpected_result', ms: now() - started });
      return retry();
    }
    const counts: Record<string, number> = 'staff' in answer ? { staff: answer.staff.length }
      : answer.status === 'ok' ? { orders: answer.orders.length, counter: answer.counter.length, free: answer.free.length } : {};
    logEvent('web_order.done', { type, ...about, status: answer.status, ...counts, ms: now() - started });
    return reply({ ok: true, ...answer }, 200);
  }

  // The buyer registered before `paid` landed (Stripe is still retrying the
  // webhook), so web_order_names has no order to name. A 503 would be wrong
  // twice over: /register does not retry, and the log would point at the
  // database. It is its own 4xx, so the website can tell it apart and send the
  // names again once `paid` has been stored.
  if (type === 'names' && isNotFound(data)) {
    logEvent('web_order.names_before_paid', { type, ...about, status: 'not_found', ms: now() - started });
    return reply({ ok: false, error: 'not_found' }, 409);
  }

  const result = readResult(data, type === 'door' ? DOOR_RESULT_STATUSES : RESULT_STATUSES);
  if (!result) {
    logEvent('web_order.retry', { type, ...about, code: 'unexpected_result', ms: now() - started });
    return retry();
  }

  logEvent('web_order.done', { type, ...about, status: result.status, ms: now() - started });
  return reply({ ok: true, ...result }, 200);
}

/** The RPC's `{status, invoice_no, review_reason}`, or null when it is anything else. */
export function readResult(data: unknown, statuses: readonly string[] = RESULT_STATUSES): OrderResult | null {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) return null;
  const d = data as Record<string, unknown>;
  if (typeof d.status !== 'string' || !statuses.includes(d.status)) return null;
  const optional = (v: unknown) => (typeof v === 'string' && v ? v : null);
  return { status: d.status as ResultStatus, invoice_no: optional(d.invoice_no), review_reason: optional(d.review_reason) };
}

const isObject = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === 'object' && !Array.isArray(v);

export type SyncAnswer =
  | { status: 'too_soon' | 'refused' }
  | { status: 'ok'; event: Record<string, unknown>; orders: unknown[]; counter: unknown[]; free: unknown[] };
export interface StaffAnswer { status: (typeof STAFF_STATUSES)[number]; staff: { id: string; name: string }[] }

/**
 * 380: web_order_sync's answer: `{status: 'ok', event, orders, counter, free}`,
 * or just `{status: 'too_soon' | 'refused'}`. Null when it is anything else.
 * 382 added `free` (the event's free guests); a database without 382 sends
 * none, which is passed on as `[]`.
 */
export function readSync(data: unknown): SyncAnswer | null {
  if (!isObject(data) || typeof data.status !== 'string' || !(SYNC_STATUSES as readonly string[]).includes(data.status)) return null;
  if (data.status !== 'ok') return { status: data.status as 'too_soon' | 'refused' };
  if (!isObject(data.event) || !Array.isArray(data.orders) || !Array.isArray(data.counter)) return null;
  const free = data.free === undefined ? [] : data.free;
  if (!Array.isArray(free)) return null;
  return { status: 'ok', event: data.event, orders: data.orders, counter: data.counter, free };
}

/** 380: web_order_staff's answer, each person as id and name only. Null when it is anything else. */
export function readStaff(data: unknown): StaffAnswer | null {
  if (!isObject(data) || typeof data.status !== 'string' || !(STAFF_STATUSES as readonly string[]).includes(data.status)) return null;
  if (!Array.isArray(data.staff)) return null;
  const staff: { id: string; name: string }[] = [];
  for (const s of data.staff) {
    if (!isObject(s) || typeof s.id !== 'string' || typeof s.name !== 'string') return null;
    staff.push({ id: s.id, name: s.name });
  }
  return { status: data.status as StaffAnswer['status'], staff };
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
