// Request signing between the Alaric website and this function.
//
//   x-energia-timestamp: <unix seconds>
//   x-energia-signature: v1=<hex HMAC-SHA256(secret, "<timestamp>.<raw body>")>
//
// The HMAC covers the exact bytes that arrived, so the body is verified before
// it is parsed and nothing unauthenticated is ever read as JSON. The timestamp
// is inside the HMAC, which is what makes the freshness window mean anything.
//
// A replay inside the window is not a problem worth more machinery: both RPCs
// are keyed on the Stripe session id, so the same order twice is one order.

export const MAX_AGE_SECONDS = 300;
export const MAX_FUTURE_SECONDS = 60;

const TIMESTAMP_RE = /^\d{1,12}$/;
const SIGNATURE_RE = /^v1=([0-9a-fA-F]{64})$/;

/** Why a request was refused. Logged, never returned: every refusal is one 401. */
export type SignatureProblem = 'missing' | 'malformed' | 'mismatch' | 'stale' | 'future';

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

function toBytes(body: Uint8Array | string): Uint8Array {
  return typeof body === 'string' ? new TextEncoder().encode(body) : body;
}

async function mac(secret: string, timestamp: string, body: Uint8Array): Promise<Uint8Array> {
  const prefix = new TextEncoder().encode(`${timestamp}.`);
  const message = new Uint8Array(prefix.byteLength + body.byteLength);
  message.set(prefix, 0);
  message.set(body, prefix.byteLength);
  return new Uint8Array(await crypto.subtle.sign('HMAC', await keyFor(secret), message));
}

const toHex = (bytes: Uint8Array): string =>
  [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');

function fromHex(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

/**
 * Compare two byte strings in time that depends only on their length.
 *
 * Both sides are always 32 bytes here (the header pattern fixes the length), so
 * the early return on a length difference gives nothing away.
 */
export function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) return false;
  let diff = 0;
  for (let i = 0; i < a.byteLength; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/** The `x-energia-signature` value for a body. What the website sends; the tests sign with it too. */
export async function signBody(secret: string, timestamp: string | number, body: Uint8Array | string): Promise<string> {
  return `v1=${toHex(await mac(secret, String(timestamp), toBytes(body)))}`;
}

/**
 * Check the two headers against the raw body. Returns null when the request is
 * authentic and fresh, otherwise the reason it is not.
 *
 * The signature is checked before the clock, so a "stale" or "future" in the
 * logs always means a genuine request with a skewed clock or a long delay, and
 * never a wrong secret.
 */
export async function verifySignature(args: {
  secret: string;
  timestamp: string | null;
  signature: string | null;
  body: Uint8Array;
  nowSeconds: number;
}): Promise<SignatureProblem | null> {
  const timestamp = args.timestamp?.trim() ?? '';
  const signature = args.signature?.trim() ?? '';
  if (!timestamp || !signature) return 'missing';

  const match = SIGNATURE_RE.exec(signature);
  if (!TIMESTAMP_RE.test(timestamp) || !match) return 'malformed';

  const expected = await mac(args.secret, timestamp, args.body);
  if (!timingSafeEqual(expected, fromHex(match[1]))) return 'mismatch';

  const age = args.nowSeconds - Number(timestamp);
  if (age > MAX_AGE_SECONDS) return 'stale';
  if (-age > MAX_FUTURE_SECONDS) return 'future';
  return null;
}
