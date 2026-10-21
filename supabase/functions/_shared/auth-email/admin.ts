// The service-role Supabase client, and the two Auth calls that need it.
//
// Isolated in one file so that every other module in here stays free of the
// Supabase SDK and can be unit-tested without a network. The service-role key
// only ever exists inside this process.

import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.108.2';
import type { AuthEmailConfig } from './config.ts';

export function adminClient(config: AuthEmailConfig): SupabaseClient {
  return createClient(config.supabaseUrl, config.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });
}

export type AccountState = 'none' | 'unconfirmed' | 'confirmed';

/**
 * Whether an address has no account, an unconfirmed one, or a verified one.
 *
 * Answered by a service-role-only database function so the endpoints can act on
 * the difference while their HTTP responses stay identical in all three cases.
 */
export async function accountState(admin: SupabaseClient, email: string): Promise<AccountState> {
  const { data, error } = await admin.rpc('auth_email_user_state', { p_email: email });
  if (error) throw new Error(`account state lookup failed: ${error.message}`);
  if (data === 'none' || data === 'unconfirmed' || data === 'confirmed') return data;
  throw new Error('account state lookup returned an unexpected value');
}

export interface GeneratedLink {
  actionLink: string;
  email: string;
  displayName: string;
  /**
   * The Auth account this link belongs to.
   *
   * Optional because only the invitation path needs it — a recovery link is
   * acted on by the recipient's own session, so nothing has to look the account
   * up. The invitation path checks for it explicitly rather than assuming.
   */
  userId?: string | null;
}

export type GenerateOutcome =
  | { status: 'ok'; link: GeneratedLink }
  | { status: 'already_confirmed' }
  | { status: 'no_such_user' }
  | { status: 'error'; message: string };

export type CreateOutcome =
  | { status: 'created'; userId: string }
  /** The address already has a login (any login: affiliate, staff, or an unfinished sign-up). */
  | { status: 'exists' }
  /** Supabase Auth refused a value (its own password policy, say); the message is its own. */
  | { status: 'refused'; field: 'password' | 'email'; message: string }
  | { status: 'error'; message: string };

/**
 * Create an affiliate sign-up's login, already confirmed (437).
 *
 * The Owner decided on 20 Oct 2026 that Create Account takes the person
 * straight to the affiliate dashboard, with no waiting for an email, while
 * Supabase Auth's "Confirm email" stays on. So the server makes the login
 * confirmed itself, through the admin API, and the browser then signs in
 * with the password the person typed. The email is verified later, from the
 * affiliate Account page; until then the app's own record says it is not
 * (affiliate_accounts.email_verified_at, set by confirm_affiliate_email()).
 *
 * `app_metadata.affiliate_email_unverified` marks a login whose email was
 * never proven. Only the service role can write app_metadata, and
 * complete_affiliate_onboarding() reads it: a login without it was confirmed
 * by Supabase's own email link (every login before 437) and counts as
 * verified.
 *
 * This is the only call in the system that creates an affiliate login, and
 * the metadata it writes is built entirely on the server. Nothing a browser
 * sends becomes a role: the affiliate identity comes from
 * complete_affiliate_onboarding(), which reads the session and its own
 * arguments, and these details only when it is given none.
 */
export async function createConfirmedSignup(
  admin: SupabaseClient,
  args: { email: string; password: string; metadata: Record<string, unknown> },
): Promise<CreateOutcome> {
  const { data, error } = await admin.auth.admin.createUser({
    email: args.email,
    password: args.password,
    email_confirm: true,
    user_metadata: args.metadata,
    app_metadata: { affiliate_email_unverified: true },
  });
  if (error) {
    const code = (error as { code?: string }).code ?? '';
    const message = error.message ?? '';
    if (code === 'email_exists' || code === 'user_already_exists'
      || /already been registered|already registered|already exists/i.test(message)) {
      return { status: 'exists' };
    }
    if (code === 'weak_password') return { status: 'refused', field: 'password', message };
    if (code === 'email_address_invalid') return { status: 'refused', field: 'email', message: 'Enter a valid email address.' };
    return { status: 'error', message };
  }
  const userId = data?.user?.id;
  if (!userId) return { status: 'error', message: 'no user returned' };
  return { status: 'created', userId };
}

/**
 * A sign-in link for a confirmed login, sent as the Account page's
 * verification email (437). Opening it signs the person in at
 * /affiliate/verify, and a session opened from an emailed link is what
 * confirm_affiliate_email() accepts as proof of the mailbox. Only asked for an
 * address that already has a confirmed affiliate login
 * (affiliateEmailNeedsVerification), so it never brings an account into being.
 */
export async function generateMagicLink(
  admin: SupabaseClient,
  args: { email: string; redirectTo: string },
): Promise<GenerateOutcome> {
  return await runGenerate(admin, {
    type: 'magiclink',
    email: args.email,
    options: { redirectTo: args.redirectTo },
  });
}

/**
 * Whether an address belongs to a confirmed affiliate login whose email the
 * app has not verified yet (437). Answered by a service-role-only database
 * function; the answer never reaches the browser.
 */
export async function affiliateEmailNeedsVerification(admin: SupabaseClient, email: string): Promise<boolean> {
  const { data, error } = await admin.rpc('affiliate_email_verification_needed', { p_email: email });
  if (error) throw new Error(`verification lookup failed: ${error.message}`);
  return data === true;
}

/**
 * Create a fresh confirmation link for an account that already exists and has
 * not been verified yet.
 *
 * Two deliberate omissions make this safe to expose to an unauthenticated
 * caller. No `data`, so an existing account's metadata is never rewritten by
 * whoever submitted the form. And an empty password, which the Auth service
 * ignores for an existing user — it only reads the password on the branch that
 * creates one, where an empty value is refused outright. So this call can mint a
 * new link for an unverified account, and it cannot change that account's
 * password and cannot bring a new account into existence.
 */
export async function regenerateSignupLink(
  admin: SupabaseClient,
  args: { email: string; redirectTo: string },
): Promise<GenerateOutcome> {
  return await runGenerate(admin, {
    type: 'signup',
    email: args.email,
    password: '',
    options: { redirectTo: args.redirectTo },
  });
}

/** Recovery link. Reports `no_such_user` rather than inventing an account. */
/**
 * Create the Auth account for an invited internal user and return its link.
 *
 * `generateLink({ type: 'invite' })` creates the account and hands the link
 * back. It is deliberately not `inviteUserByEmail`, which would send the email
 * through Supabase's own sender and bypass the Pabbly pipeline, the branded
 * template and the configured From address entirely.
 *
 * No password is set here. The invited user has none until they choose one, so
 * there is nothing for an administrator to see, send on, or accidentally log.
 *
 * The metadata is a display convenience only. Authority lives in the profiles
 * row that invite_user_provisioned() writes; nothing reads a role from here.
 */
export async function generateInviteLink(
  admin: SupabaseClient,
  args: { email: string; redirectTo: string; fullName: string },
): Promise<GenerateOutcome> {
  return await runGenerate(admin, {
    type: 'invite',
    email: args.email,
    options: {
      redirectTo: args.redirectTo,
      data: { full_name: args.fullName, invited_to: 'energia_internal' },
    },
  });
}

export async function generateRecoveryLink(
  admin: SupabaseClient,
  args: { email: string; redirectTo: string },
): Promise<GenerateOutcome> {
  return await runGenerate(admin, {
    type: 'recovery',
    email: args.email,
    options: { redirectTo: args.redirectTo },
  });
}

// deno-lint-ignore no-explicit-any
async function runGenerate(admin: SupabaseClient, params: any): Promise<GenerateOutcome> {
  const { data, error } = await admin.auth.admin.generateLink(params);

  if (error) {
    const code = (error as { code?: string }).code ?? '';
    const status = (error as { status?: number }).status ?? 0;
    const message = error.message ?? '';
    if (code === 'email_exists' || /already been registered|already registered/i.test(message)) {
      return { status: 'already_confirmed' };
    }
    if (code === 'user_not_found' || status === 404 || /user with this email not found/i.test(message)) {
      return { status: 'no_such_user' };
    }
    return { status: 'error', message };
  }

  const actionLink = data?.properties?.action_link;
  if (!actionLink) return { status: 'error', message: 'no action link returned' };

  const meta = (data?.user?.user_metadata ?? {}) as Record<string, unknown>;
  const displayName = [meta.first_name, meta.last_name]
    .filter(v => typeof v === 'string' && v.trim())
    .join(' ')
    .trim();

  return {
    status: 'ok',
    link: {
      actionLink,
      email: data.user?.email ?? params.email,
      displayName,
      userId: data.user?.id ?? null,
    },
  };
}
