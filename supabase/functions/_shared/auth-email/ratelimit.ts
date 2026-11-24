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
  /** Which bucket refused: 'send', 'send_staff' or 'email_day' (a take); the action name for a reserve. */
  action?: string;
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

export type TakeBucket = 'signup' | 'send';

/** Who a take is for: the login's own address hash, and the recipient login's user id. */
export interface TakeWho {
  emailHash?: string;
  userId?: string;
  /** A send to an address the caller typed (a new email proving itself): that address, hashed. Left out for a send to the login's own address. */
  recipientHash?: string;
  /** Recovery: the typed (normalised) address. The database finds the login by it and picks the pool; 'no_login' when there is none. */
  lookupEmail?: string;
}

/**
 * Take one slot of an overall ceiling (security audit of 17 Nov 2026, M6): 30
 * new logins an hour in all ('signup'), or 60 verify and reset emails sent a
 * day ('send'). The numbers are the database's. Unlike `reserve`, this is asked
 * only at the last step before the thing it limits (the login is made, the
 * email is handed over), so a try that stops earlier uses no slot. Throws
 * `RateLimiterUnavailableError` when the database cannot answer: fail closed.
 */
export async function take(
  admin: RpcRunner<{ data: unknown; error: { message?: string } | null }>,
  bucket: TakeBucket,
  who: TakeWho = {},
): Promise<Reservation> {
  // `emailHash` (a login's own address, hashed) also counts the slot against
  // that login's cap of sends a day. `userId` (the RECIPIENT login's auth user
  // id) lets the database choose the pool: staff logins draw on their own 20 a
  // day, everyone else on the 60. The pool is never chosen from anything a
  // caller sends (a recovery request's 'flow' is never passed). Left out, only
  // the overall ceiling of the bucket counts.
  const args: Record<string, unknown> = { p_bucket: bucket };
  if (who.emailHash) args.p_email_hash = who.emailHash;
  if (who.userId) args.p_user_id = who.userId;
  if (who.recipientHash) args.p_recipient_hash = who.recipientHash;
  // An address to look up is passed even when blank: the database answers
  // 'no_login' for it, instead of this becoming a plain take on the 60.
  if (who.lookupEmail !== undefined) args.p_lookup_email = who.lookupEmail;
  const { data, error } = await admin.rpc('auth_email_take', args);
  if (error) throw new RateLimiterUnavailableError(error.message ?? 'rpc error');
  if (!data || typeof data !== 'object') throw new RateLimiterUnavailableError('unexpected response');
  const row = data as { allowed?: unknown; retry_after_seconds?: unknown; scope?: unknown; action?: unknown };
  if (typeof row.allowed !== 'boolean') throw new RateLimiterUnavailableError('unexpected response');
  return {
    allowed: row.allowed,
    retryAfterSeconds: Number(row.retry_after_seconds ?? 0) || 0,
    scope: typeof row.scope === 'string' ? row.scope : undefined,
    action: typeof row.action === 'string' ? row.action : undefined,
  };
}

/**
 * The day's email budget for the endpoints that send straight from their own
 * index.ts (affiliate-details, auth-change-password): 'ok' when a slot was
 * taken, 'full' when the budget is spent, 'unavailable' when the limiter could
 * not answer. Never throws.
 */
export async function takeSendSlot(
  admin: RpcRunner<{ data: unknown; error: { message?: string } | null }>,
  who: TakeWho = {},
): Promise<{ result: 'ok' | 'full' | 'unavailable'; retryAfterSeconds: number; action?: string }> {
  try {
    const taken = await take(admin, 'send', who);
    return { result: taken.allowed ? 'ok' : 'full', retryAfterSeconds: taken.retryAfterSeconds, action: taken.action };
  } catch {
    return { result: 'unavailable', retryAfterSeconds: 0 };
  }
}

/** Wording for a 429. Friendly, and it never says which bucket ran out. */
export function rateLimitMessage(retryAfterSeconds: number): string {
  const minutes = Math.ceil(Math.max(retryAfterSeconds, 1) / 60);
  if (minutes <= 1) return 'Too many attempts just now. Please wait a minute and try again.';
  if (minutes < 60) return `Too many attempts just now. Please try again in about ${minutes} minutes.`;
  const hours = Math.ceil(minutes / 60);
  return `Too many attempts just now. Please try again in about ${hours === 1 ? 'an hour' : `${hours} hours`}.`;
}
