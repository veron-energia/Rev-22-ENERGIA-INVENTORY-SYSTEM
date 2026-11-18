// 466 (the Owner, 24 Oct 2026): an affiliate sign-up with the email or phone
// of an existing affiliate is sent to Sign in, and nothing is made.
//
// The database decides (affiliate_signup_existing, the service role's alone);
// this file only reads its answer, strictly, and words the refusal. Kept free
// of the Supabase SDK so it can be tested offline.

/** What of a sign-up an existing affiliate account already has. */
export interface ExistingAffiliate {
  /** Its email (first), else its phone; null for neither. */
  matched: 'email' | 'phone' | null;
  /** The email typed is that affiliate's own login email (today's email_in_use). */
  loginEmail: boolean;
  // No email hint (security audit of 17 Nov 2026, L9; the user, 18 Nov 2026):
  // the database still returns a masked `email_hint`, but it is ignored here,
  // so no part of anyone's email can reach a response, a log line or a page.
}

export const NO_EXISTING_AFFILIATE: ExistingAffiliate = { matched: null, loginEmail: false };

/**
 * Read the database's answer. A reply that is not the expected shape is an
 * error (the sign-up then answers 503 and makes nothing), never "no match":
 * `matched` must be there ('email', 'phone' or null) and `login_email` must be
 * true or false, whatever was matched.
 */
export function readExistingAffiliate(data: unknown): ExistingAffiliate {
  if (!data || typeof data !== 'object' || Array.isArray(data)) {
    throw new Error('existing affiliate lookup returned an unexpected value');
  }
  const row = data as { matched?: unknown; login_email?: unknown };
  // The key itself must be there (null for no match): {} or { error } is not
  // "no match", and neither is a login_email that is not true or false.
  if (!('matched' in row) || typeof row.login_email !== 'boolean') {
    throw new Error('existing affiliate lookup returned an unexpected value');
  }
  const matched = row.matched;
  if (matched !== null && matched !== 'email' && matched !== 'phone') {
    throw new Error('existing affiliate lookup returned an unexpected match');
  }
  if (matched === null) return NO_EXISTING_AFFILIATE;
  const loginEmail = matched === 'email' && row.login_email;
  return { matched, loginEmail };
}

/**
 * The words of the refusal. The page builds the same words itself, from the
 * same codes (src/lib/auth-email/client.mjs, signupExistingMessage); this one
 * is for a page from before 466, which shows a 409 it does not know with the
 * server's message. A test keeps the two the same.
 */
export function affiliateExistsMessage(matched: 'email' | 'phone'): string {
  const what = matched === 'phone'
    ? 'This phone number already has an Energia affiliate account'
    : 'This email is already on an Energia affiliate account';
  return `${what}. Sign in with the email you used for it, or reset your password if you have forgotten it.`;
}
