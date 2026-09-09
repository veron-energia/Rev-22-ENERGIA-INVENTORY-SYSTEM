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

/**
 * Create a confirmation link for a brand-new signup.
 *
 * This is the only call in the system that creates an account, and the metadata
 * it writes is built entirely on the server. Nothing a browser sends becomes a
 * role: the affiliate identity is created later by
 * `complete_affiliate_onboarding()`, which reads the verified session and its
 * own RPC arguments and ignores user metadata completely.
 */
export async function generateSignupLink(
  admin: SupabaseClient,
  args: { email: string; password: string; redirectTo: string; metadata: Record<string, unknown> },
): Promise<GenerateOutcome> {
  return await runGenerate(admin, {
    type: 'signup',
    email: args.email,
    password: args.password,
    options: { redirectTo: args.redirectTo, data: args.metadata },
  });
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
