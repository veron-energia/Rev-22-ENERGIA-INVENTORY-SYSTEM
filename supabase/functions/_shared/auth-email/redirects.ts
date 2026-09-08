// Where a verification or recovery link is allowed to land.
//
// The browser names a flow. The server owns the URL. There is no code path that
// turns caller-supplied text into a redirect, which is the whole point: an
// open redirect here would hand an attacker a Supabase-signed action link.

import type { AuthEmailConfig } from './config.ts';

export const CALLBACK_PATHS = {
  affiliate_signup: '/affiliate/verify',
  affiliate_recovery: '/affiliate/reset-password',
  staff_recovery: '/reset-password',
} as const;

export type CallbackFlow = keyof typeof CALLBACK_PATHS;

/**
 * Pick the base URL for a callback.
 *
 * Production (`PUBLIC_APP_URL`) is the default and the first entry. A request
 * whose Origin exactly matches a separately configured test origin gets that
 * one instead — which is how a staging build can be exercised without ever
 * letting an arbitrary origin nominate itself.
 */
export function callbackBaseFor(config: AuthEmailConfig, origin: string | null): string {
  const clean = origin?.replace(/\/+$/, '') ?? null;
  if (clean && config.callbackBaseUrls.includes(clean)) return clean;
  return config.publicAppUrl;
}

export function callbackUrl(config: AuthEmailConfig, flow: CallbackFlow, origin: string | null): string {
  return `${callbackBaseFor(config, origin)}${CALLBACK_PATHS[flow]}`;
}

/**
 * A generated action link is only usable if it points at this project's own
 * Auth endpoint. Checked before the link is put into an email so a surprising
 * value from upstream cannot become a link we send on Energia's behalf.
 */
export function isTrustedActionLink(link: unknown, config: AuthEmailConfig): link is string {
  if (typeof link !== 'string' || link.length === 0 || link.length > 2048) return false;
  if (/[\r\n\t<>"']/.test(link)) return false;
  let parsed: URL;
  try { parsed = new URL(link); } catch { return false; }
  if (parsed.protocol !== 'https:') return false;
  try {
    return parsed.origin === new URL(config.supabaseUrl).origin;
  } catch { return false; }
}
