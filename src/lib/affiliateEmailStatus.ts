import { supabase } from './supabase';
import { resendVerification, AUTH_EMAIL_COPY } from './authEmail';

// 437 (the Owner, 20 Oct 2026): an affiliate verifies their email later. The
// app's own "email verified" (affiliate_accounts.email_verified_at) and the
// verification email, for the Account page and for the warning at the top of
// the other portal pages (3 Nov 2026).

// The last answer read for each login in this tab. Each portal page draws the
// portal shell again, so the warning shows straight away on the next page
// rather than a moment after it, and stays away once the Account page has
// read the email as verified.
const lastRead = new Map<string, boolean>();

/**
 * Is this login's email verified? null: unknown (no 437 on the server, or no
 * account); throws when the read itself failed.
 */
export async function readEmailVerified(uid: string): Promise<boolean | null> {
  const { data, error } = await supabase.from('affiliate_accounts').select('email_verified_at').eq('auth_user_id', uid).maybeSingle();
  if (error) {
    // Before 437 the column is not there: say nothing rather than "not verified".
    if ((error as { code?: string }).code === '42703' || /does not exist/i.test(error.message ?? '')) { lastRead.delete(uid); return null; }
    throw new Error(error.message);
  }
  if (!data) { lastRead.delete(uid); return null; }
  const verified = !!(data as { email_verified_at: string | null }).email_verified_at;
  lastRead.set(uid, verified);
  return verified;
}

/** What readEmailVerified last found for this login in this tab (null: not read yet, or unknown). */
export function lastEmailVerified(uid: string | null | undefined): boolean | null {
  return uid ? lastRead.get(uid) ?? null : null;
}

/** What Send verification email came to, in words for the person. */
export interface VerificationSent { ok: boolean; text: string; verified: boolean }

/**
 * Send the verification email. It goes through auth-resend-verification, as
 * the other Auth emails do (Pabbly). Its link signs the affiliate in at
 * /affiliate/verify, which marks the email verified and lands on the Account
 * page.
 */
export async function sendVerificationEmail(uid: string | null, email: string): Promise<VerificationSent> {
  const result = await resendVerification(email);
  if (!result.ok) return { ok: false, text: result.message ?? AUTH_EMAIL_COPY.unavailable, verified: false };
  if (result.kind === 'not_sent') return { ok: false, text: result.message ?? AUTH_EMAIL_COPY.notSent, verified: false };
  // The server answers "submitted" whether or not it sent anything (it
  // tells no one which addresses need it). Verified meanwhile, in another
  // tab, nothing was sent: read it again and say so.
  let nowVerified: boolean | null = null;
  try { nowVerified = uid ? await readEmailVerified(uid) : null; } catch { /* keep the answer the server gave */ }
  if (nowVerified) return { ok: true, text: 'Your email is already verified.', verified: true };
  return { ok: true, text: AUTH_EMAIL_COPY.verifyEmailSent, verified: false };
}
