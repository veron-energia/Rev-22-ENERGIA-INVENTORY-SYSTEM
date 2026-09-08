// Server-side configuration for Auth email delivery.
//
// Every value here is a Supabase Function secret. None of them may ever appear
// in an HTTP response, a log line, or the frontend bundle — there is no VITE_
// equivalent of any of these and there must never be one.
//
// Set them with:
//   supabase secrets set --env-file supabase/functions/.env.auth-email
// (see PABBLY_GENERATELINK_AUTH_SETUP.md for the full list and the order).

export interface AuthEmailConfig {
  supabaseUrl: string;
  serviceRoleKey: string;
  /** Publishable/anon key — used as the `apikey` when acting *as the user*. */
  publicApiKey: string;
  publicAppUrl: string;
  callbackBaseUrls: string[];
  allowedOrigins: string[];
  pabblyWebhookUrl: string;
  pabblySharedSecret: string;
  fromAddress: string;
  fromName: string;
  replyTo: string;
  hashSecret: string;
  /**
   * Which entry of the forwarded-for header the platform itself wrote.
   * 1 = the last entry (the value appended by the closest trusted proxy), which
   * is the only one a caller cannot forge. Raise it only after confirming the
   * real hop count from a live request — see the docs.
   */
  trustedProxyHops: number;
  pabblyTimeoutMs: number;
}

class MissingConfigError extends Error {
  constructor(public readonly names: string[]) {
    super(`Missing configuration: ${names.join(', ')}`);
    this.name = 'MissingConfigError';
  }
}

const env = (name: string): string => Deno.env.get(name)?.trim() ?? '';

/** First non-empty value among `names`. Lets one project use either key name. */
const firstOf = (...names: string[]): string => {
  for (const n of names) { const v = env(n); if (v) return v; }
  return '';
};

const list = (raw: string): string[] =>
  raw.split(',').map(s => s.trim().replace(/\/+$/, '')).filter(Boolean);

/**
 * The CORS allowlist, computed without validating anything else.
 *
 * This exists so a misconfigured function can still answer readably. If the
 * allowlist were only available after a successful `loadConfig()`, then a
 * missing secret would produce a 503 with no `Access-Control-Allow-Origin`, the
 * browser would refuse to show it to the page, and a plain configuration
 * mistake would surface as an opaque CORS failure — sending whoever is
 * debugging it off to look at entirely the wrong thing.
 */
export function loadAllowedOrigins(): string[] {
  const app = env('PUBLIC_APP_URL').replace(/\/+$/, '');
  return [...new Set([...(app ? [app] : []), ...list(env('AUTH_EMAIL_TEST_ORIGINS'))])];
}

let cached: AuthEmailConfig | null = null;

export function loadConfig(): AuthEmailConfig {
  if (cached) return cached;

  const supabaseUrl = env('SUPABASE_URL');
  // Projects created before the new API keys inject SUPABASE_SERVICE_ROLE_KEY;
  // newer ones inject SUPABASE_SECRET_KEY. Either is the service role.
  const serviceRoleKey = firstOf('SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_SECRET_KEY');
  const publicApiKey = firstOf('SUPABASE_ANON_KEY', 'SUPABASE_PUBLISHABLE_KEY');
  const publicAppUrl = env('PUBLIC_APP_URL').replace(/\/+$/, '');
  const pabblyWebhookUrl = env('PABBLY_AUTH_EMAIL_WEBHOOK_URL');
  const pabblySharedSecret = env('PABBLY_AUTH_EMAIL_SHARED_SECRET');
  const fromAddress = env('AUTH_EMAIL_FROM_ADDRESS');
  const fromName = env('AUTH_EMAIL_FROM_NAME');
  const replyTo = env('AUTH_EMAIL_REPLY_TO') || fromAddress;
  const hashSecret = env('AUTH_EMAIL_RATE_LIMIT_HASH_SECRET');

  const missing: string[] = [];
  if (!supabaseUrl) missing.push('SUPABASE_URL');
  if (!serviceRoleKey) missing.push('SUPABASE_SERVICE_ROLE_KEY');
  if (!publicApiKey) missing.push('SUPABASE_ANON_KEY');
  if (!publicAppUrl) missing.push('PUBLIC_APP_URL');
  if (!pabblyWebhookUrl) missing.push('PABBLY_AUTH_EMAIL_WEBHOOK_URL');
  if (!pabblySharedSecret) missing.push('PABBLY_AUTH_EMAIL_SHARED_SECRET');
  if (!fromAddress) missing.push('AUTH_EMAIL_FROM_ADDRESS');
  if (!fromName) missing.push('AUTH_EMAIL_FROM_NAME');
  if (!hashSecret) missing.push('AUTH_EMAIL_RATE_LIMIT_HASH_SECRET');
  if (missing.length) throw new MissingConfigError(missing);

  // The production app is always allowed. Test origins are added explicitly and
  // server-side; the browser never gets to nominate one.
  const callbackBaseUrls = [publicAppUrl, ...list(env('AUTH_EMAIL_TEST_CALLBACK_URLS'))];
  const allowedOrigins = [publicAppUrl, ...list(env('AUTH_EMAIL_TEST_ORIGINS'))];

  cached = {
    supabaseUrl: supabaseUrl.replace(/\/+$/, ''),
    serviceRoleKey,
    publicApiKey,
    publicAppUrl,
    callbackBaseUrls: [...new Set(callbackBaseUrls)],
    allowedOrigins: [...new Set(allowedOrigins)],
    pabblyWebhookUrl,
    pabblySharedSecret,
    fromAddress,
    fromName,
    replyTo,
    hashSecret,
    trustedProxyHops: Math.max(1, Number(env('AUTH_EMAIL_TRUSTED_PROXY_HOPS') || '1') || 1),
    pabblyTimeoutMs: Math.max(1000, Number(env('AUTH_EMAIL_PABBLY_TIMEOUT_MS') || '10000') || 10000),
  };
  return cached;
}

/** Test seam: forget the memoised config. */
export function resetConfigCache(): void { cached = null; }

export { MissingConfigError };
