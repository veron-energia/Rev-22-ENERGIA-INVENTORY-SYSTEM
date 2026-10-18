import { useCallback, useEffect, useRef, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from './supabase';

/**
 * Who may set a new password on the reset pages (ADMIN-AUTH-9).
 *
 * On a shared shop device anyone could open /reset-password and set a new
 * password for whoever was signed in, without knowing the old one and without
 * being told whose account it was. Now the form asks for nothing more only
 * when the session came from an email link a few minutes ago (a password
 * reset, a magic link, an invitation). Any other session sees "Change the
 * password for <email>", must give the current password, and can sign out.
 *
 * The server (auth-change-password) applies the same rule, so this page only
 * chooses which form to show; it decides nothing. When the server asks for the
 * current password after all (the link is older than the window), the page
 * asks for it and offers a new link for someone who has forgotten it.
 *
 * The rule is in auth-change-password only, not in Supabase Auth. Someone at a
 * signed-in device who uses the browser's developer tools can still set a
 * password through Supabase Auth directly from a session opened by an email
 * link (USER_INVITATIONS.md, "What the 30-minute rule does not stop").
 */

/** The sign-in methods (the token's "amr") that come from an email link. */
export const EMAIL_LINK_METHODS: readonly string[] = ['recovery', 'otp', 'magiclink', 'invite'];
/**
 * How long after opening such a link the password may be set without the
 * current one: 30 minutes (the Owner, 10 Oct 2026). The server's window is the
 * same (auth-change-password).
 */
export const EMAIL_LINK_WINDOW_SECONDS = 30 * 60;
/**
 * How far ahead of this device's clock a link's time may be. A device clock
 * that is a few minutes slow made a fresh link look like one from the future.
 * The server uses its own clock; this only chooses which form to show.
 */
export const CLOCK_SKEW_SECONDS = 10 * 60;

/** When this session's token says it signed in from an email link (none: an empty list). */
function emailLinkTimes(accessToken: string | null | undefined): number[] {
  const part = (accessToken ?? '').split('.')[1];
  if (!part) return [];
  let claims: { amr?: unknown } | null = null;
  try {
    const base64 = part.replace(/-/g, '+').replace(/_/g, '/');
    const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
    claims = JSON.parse(decodeURIComponent(Array.from(atob(padded), c => `%${c.charCodeAt(0).toString(16).padStart(2, '0')}`).join('')));
  } catch {
    return [];
  }
  const amr = claims?.amr;
  if (!Array.isArray(amr)) return [];
  return amr.flatMap((entry) => {
    if (!entry || typeof entry !== 'object') return [];
    const { method, timestamp } = entry as { method?: unknown; timestamp?: unknown };
    return typeof method === 'string' && EMAIL_LINK_METHODS.includes(method) && typeof timestamp === 'number'
      ? [timestamp] : [];
  });
}

/** Did this session come from an email link in the last few minutes? Read from its token. */
export function cameFromEmailLink(accessToken: string | null | undefined, nowSeconds: number = Date.now() / 1000): boolean {
  return emailLinkTimes(accessToken).some(t =>
    t >= nowSeconds - EMAIL_LINK_WINDOW_SECONDS && t <= nowSeconds + CLOCK_SKEW_SECONDS);
}

/**
 * Did this session sign in from an email link at all, at any time? Read from
 * its token, without the device clock (a wrong clock must not hide the form).
 * The invitation page uses this to choose between asking the server and the
 * "You are signed in as" warning. The server (auth-accept-invitation) refuses
 * any other session, and, by its own clock, a link opened more than 30
 * minutes ago (the Owner, 18 Oct 2026).
 */
export function signedInFromEmailLink(accessToken: string | null | undefined): boolean {
  return emailLinkTimes(accessToken).length > 0;
}

/** Does this address's #fragment carry a session from an email link? */
export function emailLinkInAddress(hash: string): boolean {
  return /(^|[#&])type=(recovery|invite|magiclink)(&|$)/.test(hash);
}

/**
 * Was the app opened from an email link? Read once, as the app starts
 * (App.tsx imports this file for that). Supabase reads the link from the
 * address, then clears it, and tells only the listeners already there
 * (PASSWORD_RECOVERY). A reset page loads later, so it can miss both, and a
 * wrong device clock can make the token's time look too old. The server
 * still decides; this only chooses which form to show.
 */
export const openedFromEmailLink: boolean = (() => {
  try {
    return typeof window !== 'undefined' && emailLinkInAddress(window.location.hash ?? '');
  } catch {
    return false;
  }
})();

export type ResetMode = 'checking' | 'no_session' | 'from_link' | 'signed_in';

/**
 * The state of a reset page: still checking, no session (the link expired),
 * a session from the email link, or another signed-in session.
 */
export function useResetSession(): { mode: ResetMode; email: string; needCurrentPassword: () => void } {
  const [mode, setMode] = useState<ResetMode>('checking');
  const [email, setEmail] = useState('');
  const serverWantsCurrent = useRef(false);

  // The client parses the link on load; wait for the session before deciding the
  // link is stale, or a good link looks broken on a slow connection.
  useEffect(() => {
    let cancelled = false;
    const decide = (session: Session | null, event?: string) => {
      if (cancelled) return;
      if (!session) { setMode('no_session'); setEmail(''); return; }
      setEmail(session.user?.email ?? '');
      if (serverWantsCurrent.current) { setMode('signed_in'); return; }
      // From the link: Supabase said so, or the token's link time is recent,
      // or the app was opened from a link and this session signed in from one
      // (the device clock may be wrong). A typed #type=recovery alone is not
      // enough: the session must have come from an email link too.
      const fromLink = event === 'PASSWORD_RECOVERY' || cameFromEmailLink(session.access_token)
        || (openedFromEmailLink && emailLinkTimes(session.access_token).length > 0);
      setMode(m => (fromLink || m === 'from_link' ? 'from_link' : 'signed_in'));
    };
    supabase.auth.getSession().then(({ data }) => decide(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => decide(session, event));
    return () => { cancelled = true; sub.subscription.unsubscribe(); };
  }, []);

  // The server asked for the current password after all (the link is older
  // than the window): show that form.
  const needCurrentPassword = useCallback(() => { serverWantsCurrent.current = true; setMode('signed_in'); }, []);
  return { mode, email, needCurrentPassword };
}
