// Database-backed rate limiting.
//
// The counters live in Postgres (migration 200) rather than in the function,
// because Edge Functions are many short-lived isolates: anything counted in
// memory resets constantly and never sees its siblings' traffic.
//
// Two properties matter here and both are the database's doing:
//   * Reservation is atomic. `auth_email_reserve()` takes one advisory lock
//     around check-then-insert, so concurrent requests cannot all squeeze past
//     the same last slot.
//   * Reservation happens before a link is generated and before Pabbly is
//     contacted, and is never refunded. A failed send, an unknown address and an
//     already-verified account all cost a slot, which is what stops a caller
//     retrying without limit.
//
// Keys are HMACs. The database stores no address and no IP in the clear.

export type LimitedAction = 'signup' | 'resend' | 'recovery';

/**
 * Just enough of a Supabase client to call an RPC. `PromiseLike` rather than
 * `Promise` because the real builder is thenable but not a Promise, and this
 * keeps the module free of the SDK so it can be tested without a network.
 */
export interface RpcRunner<R> {
  rpc: (fn: string, args: Record<string, unknown>) => PromiseLike<R>;
}

export interface Reservation {
  allowed: boolean;
  retryAfterSeconds: number;
  scope?: string;
}

let hmacKey: CryptoKey | null = null;
let hmacKeySource = '';

async function keyFor(secret: string): Promise<CryptoKey> {
  if (hmacKey && hmacKeySource === secret) return hmacKey;
  hmacKey = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
  hmacKeySource = secret;
  return hmacKey;
}

/** Keyed hash of a normalized email or a trusted IP. Not reversible without the secret. */
export async function hashKey(value: string, secret: string, label: string): Promise<string> {
  const key = await keyFor(secret);
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${label}:${value}`));
  return [...new Uint8Array(signature)].map(b => b.toString(16).padStart(2, '0')).join('');
}

export class RateLimiterUnavailableError extends Error {
  constructor(cause: string) {
    super(`Rate limiter unavailable: ${cause}`);
    this.name = 'RateLimiterUnavailableError';
  }
}

/**
 * Claim one attempt. Throws `RateLimiterUnavailableError` if the limiter cannot
 * answer — callers must fail closed on that, never wave the request through.
 */
export async function reserve(
  admin: RpcRunner<{ data: unknown; error: { message?: string } | null }>,
  action: LimitedAction,
  emailHash: string,
  ipHash: string | null,
): Promise<Reservation> {
  const { data, error } = await admin.rpc('auth_email_reserve', {
    p_action: action,
    p_email_hash: emailHash,
    p_ip_hash: ipHash,
  });
  if (error) throw new RateLimiterUnavailableError(error.message ?? 'rpc error');
  if (!data || typeof data !== 'object') throw new RateLimiterUnavailableError('unexpected response');

  const row = data as { allowed?: unknown; retry_after_seconds?: unknown; scope?: unknown };
  if (typeof row.allowed !== 'boolean') throw new RateLimiterUnavailableError('unexpected response');

  return {
    allowed: row.allowed,
    retryAfterSeconds: Number(row.retry_after_seconds ?? 0) || 0,
    scope: typeof row.scope === 'string' ? row.scope : undefined,
  };
}

/** Wording for a 429. Friendly, and it never says which bucket ran out. */
export function rateLimitMessage(retryAfterSeconds: number): string {
  const minutes = Math.ceil(Math.max(retryAfterSeconds, 1) / 60);
  if (minutes <= 1) return 'Too many attempts just now. Please wait a minute and try again.';
  if (minutes < 60) return `Too many attempts just now. Please try again in about ${minutes} minutes.`;
  const hours = Math.ceil(minutes / 60);
  return `Too many attempts just now. Please try again in about ${hours === 1 ? 'an hour' : `${hours} hours`}.`;
}
