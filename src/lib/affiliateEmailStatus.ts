import { supabase } from './supabase';
import { AUTH_EMAIL_COPY } from './authEmail';
import { detailsStep } from './affiliateDetails';
import { verifyCodeMessage } from './auth-email/client.mjs';

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
 * Send the verification email (M6, the user, 20 Nov 2026): a 6-digit code to
 * the login's own address, asked for with her own session (affiliate-details,
 * 'verify_email_send'; the address is the token's, never typed). She types the
 * code on the Account page (confirmEmailCode). No emailed link verifies.
 * `where` says where the code is typed: 'here' (the Account page) or 'account'
 * (the warning on another page points her there).
 */
export async function sendVerificationEmail(uid: string | null, _email: string, where: 'here' | 'account' = 'here'): Promise<VerificationSent> {
  const step = await detailsStep({ action: 'verify_email_send' });
  if (!step.ok) {
    if (step.error === 'too_many_requests') return { ok: false, text: AUTH_EMAIL_COPY.verifyEmailLimit, verified: false };
    if (step.error === 'not_sent') return { ok: false, text: AUTH_EMAIL_COPY.notSent, verified: false };
    return { ok: false, text: step.message ?? AUTH_EMAIL_COPY.unavailable, verified: false };
  }
  // 'not_needed': verified meanwhile (another tab), or nothing to verify.
  if (step.status === ('not_needed' as string)) {
    let nowVerified: boolean | null = null;
    try { nowVerified = uid ? await readEmailVerified(uid) : null; } catch { /* say nothing more than we know */ }
    if (nowVerified) return { ok: true, text: 'Your email is already verified.', verified: true };
    return { ok: false, text: AUTH_EMAIL_COPY.unavailable, verified: false };
  }
  return { ok: true, text: where === 'here' ? AUTH_EMAIL_COPY.verifyEmailSent : AUTH_EMAIL_COPY.verifyEmailSentElsewhere, verified: false };
}

/** What typing the code came to, in words for the person. */
export interface CodeChecked { ok: boolean; text: string; verified: boolean }

/** Check the 6-digit code typed on the Account page (confirm_affiliate_email_code, with her own session). */
export async function confirmEmailCode(code: string): Promise<CodeChecked> {
  const clean = code.replace(/\s+/g, '');
  if (!/^[0-9]{6}$/.test(clean)) return { ok: false, text: verifyCodeMessage('invalid'), verified: false };
  const { data, error } = await supabase.rpc('confirm_affiliate_email_code', { p_code: clean });
  if (error) return { ok: false, text: verifyCodeMessage(undefined), verified: false };
  const a = (data ?? {}) as { verified?: boolean; already?: boolean; reason?: string; tries_left?: number };
  if (a.verified === true) {
    return { ok: true, text: a.already ? 'Your email is already verified.' : 'Thank you. Your email is verified.', verified: true };
  }
  return { ok: false, text: verifyCodeMessage(a.reason, a.tries_left), verified: false };
}
