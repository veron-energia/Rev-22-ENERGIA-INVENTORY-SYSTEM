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
 * The 503 for a function whose secrets are not all set. The names of the missing
 * secrets go to the log only (security audit of 17 Nov 2026, L10): a caller gets
 * a fixed sentence and the request id, never which secret is absent. The reply
 * still carries real CORS headers from the server-side allowlist, so the browser
 * lets the page read the 503 and show the sentence.
 */
export const NOT_CONFIGURED_MESSAGE = 'This service is not available just now. Please try again later.';

export function notConfigured(requestId: string, origin: string | null, allowed: string[]): Response {
  return json(
    { error: 'not_configured', message: NOT_CONFIGURED_MESSAGE, request_id: requestId },
    503, origin, allowed,
  );
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
 * The key a request is counted under for the per-connection limit (security
 * audit of 17 Nov 2026, M6).
 *
 * Only `cf-connecting-ip` is read. Cloudflare sets it, and production logs show
 * it equal to `x-real-ip` on every call; `x-forwarded-for` is a header a caller
 * can write, so it is not read anywhere.
 *
 *   * IPv4: the address, octets written as plain numbers (192.000.002.004 is 192.0.2.4).
 *   * IPv4-mapped IPv6 (::ffff:a.b.c.d): the IPv4.
 *   * IPv6: its /64, written the same way whatever the spelling, so every
 *     address in one /64 (one household or one hosting plan) is one connection.
 *   * Missing or not an address: the literal 'unknown', one shared bucket. That
 *     fails closed: it never means "no limit".
 */
export const UNKNOWN_CLIENT = 'unknown';

export function clientKey(req: Request): string {
  const raw = req.headers.get('cf-connecting-ip');
  if (!raw) return UNKNOWN_CLIENT;
  const bare = raw.trim().replace(/^\[/, '').replace(/\]$/, '').split('%')[0];
  if (bare.includes(':')) {
    const groups = parseIpv6(bare);
    if (!groups) return UNKNOWN_CLIENT;
    const mapped = groups.slice(0, 5).every(g => g === 0) && groups[5] === 0xffff;
    if (mapped) return `${groups[6] >> 8}.${groups[6] & 255}.${groups[7] >> 8}.${groups[7] & 255}`;
    return `${groups.slice(0, 4).map(g => g.toString(16)).join(':')}::/64`;
  }
  // The octets are numbers, so 192.000.002.004 and 192.0.2.4 are one connection.
  return isIpv4(bare) ? bare.split('.').map(Number).join('.') : UNKNOWN_CLIENT;
}

function isIpv4(value: string): boolean {
  return /^(\d{1,3}\.){3}\d{1,3}$/.test(value) && value.split('.').every(o => Number(o) <= 255);
}

/** The eight 16-bit groups of an IPv6 address, or null when it is not one. */
function parseIpv6(value: string): number[] | null {
  let text = value;
  // An embedded IPv4 tail (::ffff:192.0.2.1) is two groups.
  const tail = text.match(/:(\d{1,3}(?:\.\d{1,3}){3})$/);
  if (tail) {
    if (!isIpv4(tail[1])) return null;
    const o = tail[1].split('.').map(Number);
    text = text.slice(0, text.length - tail[1].length) + ((o[0] << 8) | o[1]).toString(16) + ':' + ((o[2] << 8) | o[3]).toString(16);
  }
  if (!/^[0-9a-f:]+$/i.test(text) || text.includes(':::')) return null;
  const halves = text.split('::');
  if (halves.length > 2) return null;
  const read = (part: string): number[] | null => {
    if (part === '') return [];
    const out: number[] = [];
    for (const g of part.split(':')) {
      if (!/^[0-9a-f]{1,4}$/i.test(g)) return null;
      out.push(parseInt(g, 16));
    }
    return out;
  };
  const head = read(halves[0]);
  const rest = halves.length === 2 ? read(halves[1]) : [];
  if (!head || !rest) return null;
  if (halves.length === 1) return head.length === 8 ? head : null;
  const missing = 8 - head.length - rest.length;
  if (missing < 1) return null;
  return [...head, ...new Array<number>(missing).fill(0), ...rest];
}
