// The key and the timestamp (436).
//
// A website key is evk_live_… or evk_test_… and 43 base64url characters (32
// random bytes made by the database). The database keeps only its SHA-256, so
// the key is hashed here and looked up by the hash: a plain SHA-256 is safe for
// a 256-bit random secret (nothing to guess), and no slow hash is needed.

import { KEY_RE, MAX_AGE_SECONDS, MAX_FUTURE_SECONDS } from './contract.ts';

/** True when the header has the shape of a key; says nothing of whether it is one. */
export const keyShaped = (value: string | null): value is string => typeof value === 'string' && KEY_RE.test(value);

/** Lower-case hex SHA-256 of the key, as event_web_keys.key_hash holds it. */
export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Why the timestamp header is refused, or null when it is fresh: unix seconds,
 * at most MAX_AGE_SECONDS old and MAX_FUTURE_SECONDS ahead (a captured request
 * cannot be sent again later).
 */
export function timestampProblem(value: string | null, nowSeconds: number): 'missing' | 'malformed' | 'stale' | 'future' | null {
  if (value === null || value === '') return 'missing';
  if (!/^\d{1,12}$/.test(value)) return 'malformed';
  const t = Number(value);
  if (t < nowSeconds - MAX_AGE_SECONDS) return 'stale';
  if (t > nowSeconds + MAX_FUTURE_SECONDS) return 'future';
  return null;
}
