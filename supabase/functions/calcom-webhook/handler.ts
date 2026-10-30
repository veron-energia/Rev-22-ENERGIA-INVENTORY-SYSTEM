// One cal.com webhook in, at most one database call out (480).
//
// Order of checks: configuration, the request envelope (POST, size), cal.com's
// signature over the raw bytes, and only then JSON and the trigger. PING is
// answered without the database; a trigger other than a booking created,
// rescheduled or cancelled is answered and ignored. A booking goes to the
// service-role-only calcom_booking_ingest with the fields payload.ts keeps.
//
// Status codes: 200 for everything handled (stored, already stored, older than
// what is stored, ignored, PING); 400 for a body that will never be accepted
// (not JSON, no trigger, no booking uid, no readable createdAt, or a database
// data exception, SQLSTATE class 22, which the same body would hit again); 401
// for a signature that is not cal.com's; 405 not POST; 413 too large; 503 for
// anything that may work later (not configured yet, the database unreachable
// or refusing for another reason). Nothing from the body is ever logged or
// returned: only the trigger,
// the outcome, a SQLSTATE and how long it took. Not even the booking's uid:
// cal.com's booking page opens with it.
//
// Kept free of the Supabase SDK so the tests run offline; index.ts supplies the
// real client.

import { logEvent } from '../_shared/auth-email/diagnostics.ts';
import { MissingConfigError, type WebhookConfig } from './config.ts';
import { classify } from './payload.ts';
import { verifySignature } from './signature.ts';

export const MAX_BODY_BYTES = 64 * 1024;
export const INGEST_RESULTS = ['created', 'updated', 'unchanged', 'stale', 'ignored'] as const;
export type IngestResult = (typeof INGEST_RESULTS)[number];

/** Just enough of a Supabase client to call an RPC. */
export interface RpcClient {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{
    data: unknown;
    error: { message?: string; code?: string } | null;
  }>;
}

export interface WebhookDeps {
  loadConfig: () => WebhookConfig;
  makeClient: (config: WebhookConfig) => RpcClient;
  /** Milliseconds since the epoch, for the durations logged. */
  now?: () => number;
}

function reply(body: Record<string, unknown>, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra },
  });
}

const retry = () => reply({ ok: false, error: 'retry' }, 503);

export async function handleWebhook(req: Request, deps: WebhookDeps): Promise<Response> {
  const now = deps.now ?? Date.now;
  const started = now();

  let config: WebhookConfig;
  try {
    config = deps.loadConfig();
  } catch (error) {
    if (error instanceof MissingConfigError) {
      logEvent('calcom_webhook.config_missing', { names: error.names.join(' ') });
      return reply({ ok: false, error: 'not_configured' }, 503);
    }
    throw error;
  }

  if (req.method !== 'POST') return reply({ ok: false, error: 'method_not_allowed' }, 405, { Allow: 'POST' });
  if (Number(req.headers.get('content-length') ?? '0') > MAX_BODY_BYTES) {
    return reply({ ok: false, error: 'payload_too_large' }, 413);
  }
  const raw = await readCapped(req, MAX_BODY_BYTES);
  if (raw === null) return reply({ ok: false, error: 'payload_too_large' }, 413);

  const problem = await verifySignature({
    secret: config.webhookSecret,
    signature: req.headers.get('x-cal-signature-256'),
    body: raw,
  });
  if (problem) {
    logEvent('calcom_webhook.bad_signature', { reason: problem });
    return reply({ ok: false, error: 'bad_signature' }, 401);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(raw));
  } catch {
    logEvent('calcom_webhook.invalid_request', { field: 'body' });
    return reply({ ok: false, error: 'invalid_json' }, 400);
  }

  const c = classify(parsed);
  if (c.kind === 'invalid') {
    // The field's path, never its value.
    logEvent('calcom_webhook.invalid_request', { field: c.field });
    return reply({ ok: false, error: 'invalid_request', field: c.field }, 400);
  }
  if (c.kind === 'ping') {
    logEvent('calcom_webhook.done', { trigger: 'PING', result: 'pong', ms: now() - started });
    return reply({ ok: true, result: 'pong' }, 200);
  }
  if (c.kind === 'ignored') {
    logEvent('calcom_webhook.done', { trigger: c.trigger, result: 'ignored', ms: now() - started });
    return reply({ ok: true, result: 'ignored' }, 200);
  }

  const trigger = c.trigger;
  let data: unknown;
  try {
    const admin = deps.makeClient(config);
    const answer = await admin.rpc('calcom_booking_ingest', { p_event: c.event });
    if (answer.error) {
      // The code only. A Postgres message can quote what it refused.
      const code = safeCode(answer.error.code);
      if (isDataException(code)) {
        logEvent('calcom_webhook.invalid_request', { trigger, field: 'payload', code, ms: now() - started });
        return reply({ ok: false, error: 'invalid_request', field: 'payload' }, 400);
      }
      logEvent('calcom_webhook.retry', { trigger, code, ms: now() - started });
      return retry();
    }
    data = answer.data;
  } catch {
    logEvent('calcom_webhook.retry', { trigger, code: 'network', ms: now() - started });
    return retry();
  }

  const result = readResult(data);
  if (!result) {
    logEvent('calcom_webhook.retry', { trigger, code: 'unexpected_result', ms: now() - started });
    return retry();
  }
  logEvent('calcom_webhook.done', { trigger, result, ms: now() - started });
  return reply({ ok: true, result }, 200);
}

/** calcom_booking_ingest's {result, previous?}: the result, or null when it is anything else. */
export function readResult(data: unknown): IngestResult | null {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) return null;
  const r = (data as Record<string, unknown>).result;
  return typeof r === 'string' && (INGEST_RESULTS as readonly string[]).includes(r) ? r as IngestResult : null;
}

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
