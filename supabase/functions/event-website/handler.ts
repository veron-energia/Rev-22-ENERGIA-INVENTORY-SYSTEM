// One message from an event's website in, one database call out (436).
//
// Order of checks: configuration, the request envelope (POST, JSON, at most
// MAX_BODY_BYTES read with a hard ceiling), the key's shape, the timestamp, the
// request id's shape, UTF-8 JSON, the contract's whitelist, a request id for a
// write, and only then one RPC: event_web_call(key hash, request id, type,
// body). The database decides everything else (the key, the event, replays,
// the rate, the business rules) and its answer is passed back.
//
// Status codes are the website's retry signal (contract ERRORS): 503 means try
// again (a passing fault: a database error other than class 22, the network);
// 429 means try again after Retry-After (the key's sign-up budget is used up;
// HitPay's notices have their own); any other 4xx is final for that request. A database error of SQLSTATE class 22
// (data exception) is 400 invalid_request, field body: the same message would
// be refused on every retry.
//
// Logs: the type, the event code, the request id, the business id, the outcome
// and how long it took. Never a name, phone, email, upgrade token, key or body.
//
// Kept free of the Supabase SDK so the tests run offline; index.ts supplies the
// real client.

import { logEvent } from '../_shared/auth-email/diagnostics.ts';
import { MissingConfigError, type EventWebsiteConfig } from './config.ts';
import {
  ERRORS, HEADER_KEY, HEADER_REQUEST_ID, HEADER_TIMESTAMP, MAX_BODY_BYTES, REQUEST_ID_RE, isWriteType, type ErrorCode,
} from './contract.ts';
import { keyShaped, sha256Hex, timestampProblem } from './keys.ts';
import { aboutOf, validateRequest } from './validate.ts';

export { MAX_BODY_BYTES };

/** Just enough of a Supabase client to call an RPC. */
export interface RpcClient {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<{
    data: unknown;
    error: { message?: string; code?: string } | null;
  }>;
}

export interface EventWebsiteDeps {
  loadConfig: () => EventWebsiteConfig;
  makeClient: (config: EventWebsiteConfig) => RpcClient;
  /** Milliseconds since the epoch. A seam for the freshness window. */
  now?: () => number;
}

function reply(body: Record<string, unknown>, status: number, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...extra },
  });
}

function fail(error: ErrorCode, extra: { field?: string; retry_after_seconds?: number } = {}): Response {
  const headers: Record<string, string> = {};
  if (error === 'method_not_allowed') headers.Allow = 'POST';
  if (extra.retry_after_seconds) headers['Retry-After'] = String(extra.retry_after_seconds);
  return reply({ ok: false, error, ...extra }, ERRORS[error].http, headers);
}

const safeCode = (code: unknown): string => (typeof code === 'string' && /^[A-Za-z0-9_]{1,16}$/.test(code) ? code : 'unknown');
/** SQLSTATE class 22, data exception: a value the database will never accept. */
const isDataException = (code: string): boolean => /^22[0-9A-Z]{3}$/.test(code);
const isObject = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === 'object' && !Array.isArray(v);

export async function handleRequest(req: Request, deps: EventWebsiteDeps): Promise<Response> {
  const now = deps.now ?? Date.now;
  const started = now();

  let config: EventWebsiteConfig;
  try {
    config = deps.loadConfig();
  } catch (error) {
    if (error instanceof MissingConfigError) {
      logEvent('event_website.config_missing', { names: error.names.join(' ') });
      return fail('not_configured');
    }
    throw error;
  }

  if (req.method !== 'POST') return fail('method_not_allowed');
  const contentType = req.headers.get('content-type') ?? '';
  if (!contentType.toLowerCase().split(';')[0].trim().endsWith('application/json')) return fail('unsupported_media_type');
  if (Number(req.headers.get('content-length') ?? '0') > MAX_BODY_BYTES) return fail('payload_too_large');
  const raw = await readCapped(req, MAX_BODY_BYTES);
  if (raw === null) return fail('payload_too_large');

  const key = req.headers.get(HEADER_KEY);
  if (!keyShaped(key)) {
    logEvent('event_website.bad_key', { reason: key ? 'malformed' : 'missing' });
    return fail('bad_key');
  }
  const stale = timestampProblem(req.headers.get(HEADER_TIMESTAMP), Math.floor(started / 1000));
  if (stale) {
    logEvent('event_website.bad_timestamp', { reason: stale });
    return fail('bad_timestamp');
  }
  const requestId = req.headers.get(HEADER_REQUEST_ID);
  if (requestId !== null && !REQUEST_ID_RE.test(requestId)) {
    return fail('invalid_request', { field: HEADER_REQUEST_ID });
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(raw));
  } catch {
    return fail('invalid_json');
  }
  const checked = validateRequest(parsed);
  if (!checked.ok) {
    // The field's path, never its value.
    logEvent('event_website.invalid_request', { field: checked.field });
    return fail('invalid_request', { field: checked.field });
  }
  const request = checked.value;
  const type = request.type;
  const write = isWriteType(type);
  if (write && requestId === null) return fail('invalid_request', { field: HEADER_REQUEST_ID });
  const about = { type, event: request.event, request_id: write ? requestId : null, ...aboutOf(request) };

  let data: unknown;
  try {
    const admin = deps.makeClient(config);
    const answer = await admin.rpc('event_web_call', {
      p_key_hash: await sha256Hex(key),
      p_request_id: write ? requestId : null,
      p_type: type,
      p_body: request,
    });
    if (answer.error) {
      // The code only. A Postgres message can quote the row it refused.
      const code = safeCode(answer.error.code);
      if (isDataException(code)) {
        logEvent('event_website.invalid_request', { ...about, field: 'body', code, ms: now() - started });
        return fail('invalid_request', { field: 'body' });
      }
      logEvent('event_website.retry', { ...about, code, ms: now() - started });
      return fail('retry');
    }
    data = answer.data;
  } catch {
    logEvent('event_website.retry', { ...about, code: 'network', ms: now() - started });
    return fail('retry');
  }

  if (!isObject(data) || typeof data.ok !== 'boolean') {
    logEvent('event_website.retry', { ...about, code: 'unexpected_result', ms: now() - started });
    return fail('retry');
  }
  if (data.ok === false) {
    const code = typeof data.error === 'string' && data.error in ERRORS ? data.error as ErrorCode : null;
    if (!code) {
      logEvent('event_website.retry', { ...about, code: 'unexpected_result', ms: now() - started });
      return fail('retry');
    }
    logEvent('event_website.refused', { ...about, error: code, field: typeof data.field === 'string' ? data.field : null, ms: now() - started });
    return fail(code, {
      ...(typeof data.field === 'string' ? { field: data.field } : {}),
      ...(typeof data.retry_after_seconds === 'number' ? { retry_after_seconds: data.retry_after_seconds } : {}),
    });
  }
  logEvent('event_website.done', { ...about, status: typeof data.status === 'string' ? data.status : null, ms: now() - started });
  return reply(data, 200);
}

// Content-Length can lie or be absent (chunked). Read with a hard ceiling.
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
  let offset = 0;
  for (const c of chunks) { merged.set(c, offset); offset += c.byteLength; }
  return merged;
}
