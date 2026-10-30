// cal.com's webhook signature (480).
//
//   x-cal-signature-256: <hex HMAC-SHA256(secret, raw body)>
//
// cal.com signs the exact body it sends with the webhook's secret. The HMAC is
// checked over the bytes that arrived, before anything is parsed, so nothing
// unauthenticated is ever read as JSON. cal.com sends no timestamp, so there is
// no freshness window: a replayed delivery is harmless, because the database
// stores each booking by its uid and an event it has already applied (the same
// uid, trigger and createdAt) changes nothing.

/** Why a request was refused. Logged, never returned: every refusal is one 401. */
export type SignatureProblem = 'missing' | 'malformed' | 'mismatch';

const SIGNATURE_RE = /^[0-9a-fA-F]{64}$/;

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

const toBytes = (body: Uint8Array | string): Uint8Array =>
  typeof body === 'string' ? new TextEncoder().encode(body) : body;

async function mac(secret: string, body: Uint8Array): Promise<Uint8Array> {
  // A copy on its own ArrayBuffer, which is what WebCrypto takes.
  return new Uint8Array(await crypto.subtle.sign('HMAC', await keyFor(secret), new Uint8Array(body)));
}

const toHex = (bytes: Uint8Array): string => [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');

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

/** The `x-cal-signature-256` value cal.com sends for a body. The tests sign with it. */
export async function signBody(secret: string, body: Uint8Array | string): Promise<string> {
  return toHex(await mac(secret, toBytes(body)));
}

/** Check the header against the raw body: null when it is cal.com's, otherwise why not. */
export async function verifySignature(args: {
  secret: string;
  signature: string | null;
  body: Uint8Array;
}): Promise<SignatureProblem | null> {
  const signature = args.signature?.trim() ?? '';
  if (!signature) return 'missing';
  if (!SIGNATURE_RE.test(signature)) return 'malformed';
  const expected = await mac(args.secret, args.body);
  return timingSafeEqual(expected, fromHex(signature)) ? null : 'mismatch';
}
