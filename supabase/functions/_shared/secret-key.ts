// The service key the Edge Functions use.
//
// Supabase injects every secret key into a function's environment as
// SUPABASE_SECRET_KEYS, a JSON object keyed by the key's NAME, for example
//   {"default":"sb_secret_...","edge_functions":"sb_secret_..."}
// The Edge Functions use the key named 'edge_functions', so that key can be
// created, rotated or deleted without touching anyone else's (Pabbly has its
// own). When that entry is absent or unusable, the legacy single-key variables
// are read exactly as before, so nothing changes until the named key exists.
//
// No key, or any part of one (nor its length or a hash), is ever returned in an
// error or written to a log by this file. The only thing it logs is ONE line per
// instance (cold start), naming the source in use: 'named', or 'legacy' with the
// reason the named key was not used (26 Nov 2026: a fixed phrase, plus at most the
// NAMES of the secret keys, which are labels chosen in the dashboard, never values).

export const EDGE_SECRET_KEY_NAME = 'edge_functions';
export const SECRET_KEY_PREFIX = 'sb_secret_';
/** Characters required after the prefix; anything shorter is unusable. */
export const MIN_KEY_SUFFIX_LENGTH = 20;

const env = (name: string): string => Deno.env.get(name)?.trim() ?? '';

/** A key NAME as it may appear in the log: a short plain label, else '?'. */
function shownName(n: string): string {
  return /^[A-Za-z0-9_-]{1,40}$/.test(n) && !n.toLowerCase().includes('sb_') ? n : '?';
}

/** The named key from SUPABASE_SECRET_KEYS, or '' with the reason it is not usable. */
function namedKey(): { key: string; reason: string } {
  const raw = env('SUPABASE_SECRET_KEYS');
  if (!raw) return { key: '', reason: 'no SUPABASE_SECRET_KEYS' };
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return { key: '', reason: 'SUPABASE_SECRET_KEYS is not JSON' };
  }
  if (Array.isArray(parsed)) return { key: '', reason: `SUPABASE_SECRET_KEYS is a list of ${parsed.length}` };
  if (parsed === null || typeof parsed !== 'object') return { key: '', reason: 'SUPABASE_SECRET_KEYS is not an object' };
  const record = parsed as Record<string, unknown>;
  const value = record[EDGE_SECRET_KEY_NAME];
  if (value === undefined) {
    const names = Object.keys(record).slice(0, 10).map(shownName).sort().join(', ');
    return { key: '', reason: `no ${EDGE_SECRET_KEY_NAME} entry; names: ${names || 'none'}` };
  }
  if (typeof value !== 'string') {
    return { key: '', reason: `${EDGE_SECRET_KEY_NAME} entry is ${value === null ? 'null' : Array.isArray(value) ? 'a list' : typeof value}` };
  }
  const key = value.trim();
  if (!key.startsWith(SECRET_KEY_PREFIX)) return { key: '', reason: `${EDGE_SECRET_KEY_NAME} entry is not a secret key` };
  if (key.length - SECRET_KEY_PREFIX.length < MIN_KEY_SUFFIX_LENGTH) return { key: '', reason: `${EDGE_SECRET_KEY_NAME} entry is too short` };
  return { key, reason: '' };
}

let announced = false;

/** Test seam: forget that the source line was logged. */
export function resetServiceKeyAnnouncement(): void { announced = false; }

/** The service key: the named one if usable, else SUPABASE_SERVICE_ROLE_KEY, else SUPABASE_SECRET_KEY. '' if none. */
export function loadServiceKey(): string {
  const named = namedKey();
  const key = named.key || env('SUPABASE_SERVICE_ROLE_KEY') || env('SUPABASE_SECRET_KEY');
  if (key && !announced) {
    announced = true;
    console.log(named.key ? 'service key source: named' : `service key source: legacy (${named.reason})`);
  }
  return key;
}
