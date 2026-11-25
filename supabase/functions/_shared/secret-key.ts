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
// error or written to a log by this file. The only thing it logs is ONE fixed
// line per instance (cold start), naming the source in use: 'named' or 'legacy'.

export const EDGE_SECRET_KEY_NAME = 'edge_functions';
export const SECRET_KEY_PREFIX = 'sb_secret_';
/** Characters required after the prefix; anything shorter is unusable. */
export const MIN_KEY_SUFFIX_LENGTH = 20;

const env = (name: string): string => Deno.env.get(name)?.trim() ?? '';

/** The named key from SUPABASE_SECRET_KEYS, or '' when it is not usable. */
function namedKey(): string {
  const raw = env('SUPABASE_SECRET_KEYS');
  if (!raw) return '';
  try {
    const parsed: unknown = JSON.parse(raw);
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) return '';
    const value = (parsed as Record<string, unknown>)[EDGE_SECRET_KEY_NAME];
    if (typeof value !== 'string') return '';
    const key = value.trim();
    return key.startsWith(SECRET_KEY_PREFIX) && key.length - SECRET_KEY_PREFIX.length >= MIN_KEY_SUFFIX_LENGTH ? key : '';
  } catch {
    return '';
  }
}

let announced = false;

/** Test seam: forget that the source line was logged. */
export function resetServiceKeyAnnouncement(): void { announced = false; }

/** The service key: the named one if usable, else SUPABASE_SERVICE_ROLE_KEY, else SUPABASE_SECRET_KEY. '' if none. */
export function loadServiceKey(): string {
  const named = namedKey();
  const key = named || env('SUPABASE_SERVICE_ROLE_KEY') || env('SUPABASE_SECRET_KEY');
  if (key && !announced) {
    announced = true;
    console.log(`service key source: ${named ? 'named' : 'legacy'}`);
  }
  return key;
}
