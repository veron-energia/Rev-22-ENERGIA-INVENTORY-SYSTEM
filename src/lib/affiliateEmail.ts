// 437 (the Owner, 20 Oct 2026): an affiliate verifies their email later,
// from the Account page. Its email holds a sign-in link to /affiliate/verify;
// a session opened from it marks the email verified there.

/** The sign-in methods (the token's "amr") that come from an emailed link. */
const EMAIL_LINK_METHODS = ['magiclink', 'otp', 'recovery', 'invite', 'email/signup'];
/** The server's window: a link opened in the last 30 minutes (429's). */
const EMAIL_LINK_WINDOW_SECONDS = 30 * 60;
/**
 * How far this device's clock may be off. A device clock a few minutes slow
 * made a fresh link look like one from the future (resetSession.ts has the
 * same allowance). The server checks again with its own clock.
 */
const CLOCK_SKEW_SECONDS = 10 * 60;

/**
 * Was this session opened from an emailed link in the last 30 minutes (the
 * access token's amr, read without checking its signature), allowing for a
 * device clock that is a few minutes off? The database's
 * confirm_affiliate_email() checks the same thing again on the real token,
 * with its own clock; this only saves the call on an ordinary password
 * sign-in.
 */
export function sessionFromEmailLink(accessToken: string | null | undefined, nowSeconds = Date.now() / 1000): boolean {
  const part = accessToken?.split('.')[1];
  if (!part) return false;
  try {
    const base64 = part.replace(/-/g, '+').replace(/_/g, '/');
    const claims = JSON.parse(atob(base64 + '='.repeat((4 - (base64.length % 4)) % 4)));
    const amr: unknown[] = Array.isArray(claims?.amr) ? claims.amr : [];
    return amr.some((entry) => {
      if (!entry || typeof entry !== 'object') return false;
      const { method, timestamp } = entry as { method?: unknown; timestamp?: unknown };
      return typeof method === 'string' && EMAIL_LINK_METHODS.includes(method)
        && typeof timestamp === 'number'
        && timestamp >= nowSeconds - EMAIL_LINK_WINDOW_SECONDS - CLOCK_SKEW_SECONDS
        && timestamp <= nowSeconds + CLOCK_SKEW_SECONDS;
    });
  } catch {
    return false;
  }
}

/** An emailed link Supabase refused (expired, or already used). */
export interface EmailLinkError { code: string; description: string; path: string }

/** What an address says about a refused link: `error_code` (or `error`) and `error_description`. */
export function emailLinkErrorIn(hash: string, search: string, path: string): EmailLinkError | null {
  for (const raw of [hash, search]) {
    const params = new URLSearchParams((raw ?? '').replace(/^[#?]/, ''));
    const code = params.get('error_code') || params.get('error');
    if (code) return { code, description: params.get('error_description') ?? '', path };
  }
  return null;
}

// Read once, as the app starts (App.tsx imports this file for that), before
// the page that needs it has loaded or the address has changed. Supabase
// keeps an existing session when a link fails, so without this the page
// could not tell a refused link from an ordinary visit.
let atLoad: EmailLinkError | null = (() => {
  try {
    return typeof window === 'undefined' ? null
      : emailLinkErrorIn(window.location.hash ?? '', window.location.search ?? '', window.location.pathname ?? '');
  } catch {
    return null;
  }
})();

/**
 * The refused link the app was opened with, when it was opened at a path
 * starting with `pathPrefix`; given once (a later visit is an ordinary one).
 */
export function takeEmailLinkError(pathPrefix: string): EmailLinkError | null {
  const e = atLoad;
  if (!e || !e.path.startsWith(pathPrefix)) return null;
  atLoad = null;
  return e;
}
