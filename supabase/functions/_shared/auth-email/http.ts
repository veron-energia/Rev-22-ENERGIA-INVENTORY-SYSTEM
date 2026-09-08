// Request-shape guards, CORS and response helpers shared by every Auth-email
// endpoint.
//
// These endpoints are reachable without a logged-in user, so the gateway is not
// the thing keeping them safe. CORS is not either — it is a browser courtesy, not
// an access control. What actually protects them is the combination in here plus
// the database-backed rate limiting: a narrow method/content-type/size envelope,
// a strict field whitelist, and server-controlled recipients and redirects.

export const MAX_BODY_BYTES = 8 * 1024;

export interface Guarded<T> {
  ok: true;
  body: T;
  origin: string | null;
}
export interface GuardFailure {
  ok: false;
  response: Response;
}

/** Echo the caller's origin only when it is on the server-side allowlist. */
export function corsHeaders(origin: string | null, allowed: string[]): Record<string, string> {
  const clean = origin?.replace(/\/+$/, '') ?? null;
  const permitted = clean !== null && allowed.includes(clean);
  return {
    ...(permitted ? { 'Access-Control-Allow-Origin': clean } : {}),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

export function json(
  body: unknown,
  status: number,
  origin: string | null,
  allowed: string[],
  extra: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(origin, allowed),
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      ...extra,
    },
  });
}

/**
 * Enforce the request envelope and return the parsed JSON body.
 *
 * Rejects anything that is not a POST of a modest JSON object: wrong method,
 * wrong content type, missing or oversized body, non-object JSON. Nothing here
 * reveals whether an account exists — these are shape failures only.
 */
export async function guardRequest<T = Record<string, unknown>>(
  req: Request,
  allowedOrigins: string[],
): Promise<Guarded<T> | GuardFailure> {
  const origin = req.headers.get('origin');

  if (req.method === 'OPTIONS') {
    return { ok: false, response: new Response(null, { status: 204, headers: corsHeaders(origin, allowedOrigins) }) };
  }
  if (req.method !== 'POST') {
    return { ok: false, response: json({ error: 'method_not_allowed' }, 405, origin, allowedOrigins, { Allow: 'POST, OPTIONS' }) };
  }

  const contentType = req.headers.get('content-type') ?? '';
  if (!contentType.toLowerCase().split(';')[0].trim().endsWith('application/json')) {
    return { ok: false, response: json({ error: 'unsupported_media_type' }, 415, origin, allowedOrigins) };
  }

  const declared = Number(req.headers.get('content-length') ?? '0');
  if (declared > MAX_BODY_BYTES) {
    return { ok: false, response: json({ error: 'payload_too_large' }, 413, origin, allowedOrigins) };
  }

  // Content-Length can lie or be absent (chunked). Read with a hard ceiling.
  const raw = await readCapped(req, MAX_BODY_BYTES);
  if (raw === null) {
    return { ok: false, response: json({ error: 'payload_too_large' }, 413, origin, allowedOrigins) };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { ok: false, response: json({ error: 'invalid_json' }, 400, origin, allowedOrigins) };
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return { ok: false, response: json({ error: 'invalid_json' }, 400, origin, allowedOrigins) };
  }

  return { ok: true, body: parsed as T, origin };
}

async function readCapped(req: Request, limit: number): Promise<string | null> {
  if (!req.body) return '';
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
  return new TextDecoder().decode(merged);
}

/**
 * The client IP, taken only from the entry the platform's own proxy wrote.
 *
 * A caller can put anything in `x-forwarded-for`; the platform appends the real
 * peer address after whatever arrived, so counting from the right is the only
 * reading a caller cannot forge. `hops` says how many proxies of our own sit in
 * front of the function — 1 by default.
 *
 * Returns null when nothing trustworthy is available. Callers must treat that as
 * "no IP limiting", never as "unlimited": the per-email limits stay mandatory.
 */
export function trustedClientIp(req: Request, hops: number): string | null {
  const header = req.headers.get('x-forwarded-for');
  if (!header) return null;
  const parts = header.split(',').map(s => s.trim()).filter(Boolean);
  if (parts.length === 0) return null;
  const index = parts.length - Math.max(1, hops);
  if (index < 0) return null;
  const candidate = parts[index];
  return looksLikeIp(candidate) ? candidate : null;
}

function looksLikeIp(value: string): boolean {
  const bare = value.replace(/^\[|\]$/g, '').split('%')[0];
  if (/^(\d{1,3}\.){3}\d{1,3}$/.test(bare)) {
    return bare.split('.').every(o => Number(o) <= 255);
  }
  return /^[0-9a-f:]+$/i.test(bare) && bare.includes(':');
}
