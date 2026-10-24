// What each public endpoint actually does, with its collaborators injected.
//
// The `index.ts` files are wiring and nothing else; the decisions live here so
// they can be exercised without a Supabase project, a network or a real webhook.
// The interesting cases — an address that already has a login, an address with
// no account, an email that fails to send — are exactly the ones that are
// impractical to reproduce against a live project, so being able to test them
// offline is the difference between checking them and hoping.

import type { AuthEmailConfig } from './config.ts';
import type { AccountState, CreateOutcome, GenerateOutcome } from './admin.ts';
import type { DeliveryRequest, DeliveryResult } from './pabbly.ts';
import type { ExistingAffiliate } from './existing.ts';
import type { EndpointResult, PublicEndpoint, PublicContext } from './pipeline.ts';
import { validateEmailOnly, validateRecovery, validateSignup, type RecoveryFlow, type SignupInput } from './validate.ts';
import { callbackUrl, isTrustedActionLink } from './redirects.ts';
import { renderPasswordRecovery, renderVerifyEmail, renderVerifySignup } from './templates.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

export interface FlowDeps {
  accountState: (admin: Admin, email: string) => Promise<AccountState>;
  /** 466: whether the sign-up's email or phone is an existing affiliate's (and the Audit Log row). */
  affiliateSignupExisting: (admin: Admin, args: { email: string; phone: string; name: string; requestId: string }) => Promise<ExistingAffiliate>;
  /** 437: the affiliate sign-up's login, made already confirmed. */
  createConfirmedSignup: (admin: Admin, args: { email: string; password: string; metadata: Record<string, unknown> }) => Promise<CreateOutcome>;
  regenerateSignupLink: (admin: Admin, args: { email: string; redirectTo: string }) => Promise<GenerateOutcome>;
  /** 437: the Account page's verification email holds a sign-in link. */
  generateMagicLink: (admin: Admin, args: { email: string; redirectTo: string }) => Promise<GenerateOutcome>;
  /** 437: a confirmed affiliate login whose email the app has not verified yet. */
  affiliateEmailNeedsVerification: (admin: Admin, email: string) => Promise<boolean>;
  generateRecoveryLink: (admin: Admin, args: { email: string; redirectTo: string }) => Promise<GenerateOutcome>;
  deliver: (config: AuthEmailConfig, request: DeliveryRequest) => Promise<DeliveryResult>;
  normalizePhone: (raw: string) => string | null;
  now?: () => Date;
}

/**
 * Send an email for a link we have just generated and trust: the old sign-up
 * verification (a login made before 437 and never confirmed), or the Account
 * page's verification email (437).
 */
async function sendVerification(
  ctx: PublicContext<unknown>,
  deps: FlowDeps,
  outcome: GenerateOutcome,
  name: string,
  kind: 'signup' | 'email' = 'signup',
): Promise<EndpointResult> {
  if (outcome.status === 'already_confirmed') return { kind: 'suppressed', reason: 'already_verified' };
  if (outcome.status === 'no_such_user') return { kind: 'suppressed', reason: 'no_account' };
  if (outcome.status === 'error') return { kind: 'internal_error', detail: outcome.message };

  if (!isTrustedActionLink(outcome.link.actionLink, ctx.config)) {
    return { kind: 'internal_error', detail: 'generated link failed origin validation' };
  }

  const email = kind === 'email'
    ? renderVerifyEmail(name || outcome.link.displayName, outcome.link.actionLink)
    : renderVerifySignup(name || outcome.link.displayName, outcome.link.actionLink);
  return {
    kind: 'delivered',
    result: await deps.deliver(ctx.config, {
      requestId: ctx.requestId,
      // Both go through the workflow's affiliate verification route; the
      // subject and the content are built here.
      actionType: 'verify_signup',
      // The recipient is the address Supabase holds for the account, never a
      // value from the request body.
      to: outcome.link.email,
      subject: email.subject,
      html: email.html,
      text: email.text,
      recipientRole: 'affiliate',
    }),
  };
}

/**
 * Affiliate sign-up (437, the Owner's decisions of 20 Oct 2026).
 *
 * 1. Create Account takes the person straight in: the login is made already
 *    confirmed, and the page signs in with the password typed. No email is
 *    sent; the email is verified later, from the Account page.
 * 4. An address that already has a login is told so ("email_in_use"), and
 *    the page offers Sign in and Reset password. The Owner accepted that this
 *    shows an address is registered; the rate limit (per address and per
 *    network) is what keeps anyone from testing addresses in bulk. Nothing
 *    about an existing login is changed: no password, no details, no email.
 *
 * 466 (the Owner, 24 Oct 2026): the email or phone of an EXISTING AFFILIATE
 * (her login email, the email or phone she signed up with, or her record's)
 * is sent to Sign in, and nothing is made. Asked first, before any login:
 *   * her login email: "email_in_use", as above (the page fills it in);
 *   * another email of hers (her record's, her sign-up's):
 *     "affiliate_exists", matched 'email';
 *   * then any login's email (staff, a sign-up never finished):
 *     "email_in_use", as above;
 *   * then her phone (the email typed is no login's): "affiliate_exists",
 *     matched 'phone' (not for a customer of her own on that phone, with no
 *     login, who types her record's name: she signs up as before).
 * A Gmail address spelt another way than a login's (dots, a +tag) is a new
 * email, whoever's login it is, so the answer never tells an affiliate's
 * login from staff's. With "affiliate_exists", the masked login email when
 * exactly one affiliate matched. The database writes the Audit Log row on her
 * record, with this request's id (auth_email_deliveries.request_id). Both
 * lookups (the affiliate one and the login one) are asked every time, at
 * once, so an affiliate's login email and staff's take the same work to
 * answer. Each try costs a rate-limit slot like any other (reserved before
 * this runs). A customer who is not an affiliate signs up as before.
 */
export function signupEndpoint(deps: FlowDeps): PublicEndpoint<SignupInput> {
  const now = deps.now ?? (() => new Date());
  return {
    action: 'signup',
    parse: (body) => validateSignup(body, deps.normalizePhone),
    emailOf: (value) => value.email,
    run: async (ctx) => {
      // 466: an existing affiliate's email or phone, and the login check,
      // asked together on every path: an affiliate's login email is not
      // answered one round trip sooner than staff's. A lookup that fails
      // throws: the sign-up answers 503 and makes nothing. The name is put
      // together as complete_affiliate_onboarding does (first, a space,
      // last), so a family member on an affiliate's phone who types her own
      // record's name signs up as before.
      const [existing, state] = await Promise.all([
        deps.affiliateSignupExisting(ctx.admin, {
          email: ctx.value.email,
          phone: ctx.value.phone,
          name: `${ctx.value.firstName} ${ctx.value.lastName}`.trim(),
          requestId: ctx.requestId,
        }),
        deps.accountState(ctx.admin, ctx.value.email),
      ]);
      if (existing.matched === 'email') {
        return existing.loginEmail
          ? { kind: 'email_in_use' }
          : { kind: 'affiliate_exists', matched: 'email', emailHint: existing.emailHint };
      }

      // Any login with this address (an affiliate, a member of staff, or a
      // sign-up from before 437 that was never confirmed) keeps it.
      if (state !== 'none') return { kind: 'email_in_use' };
      if (existing.matched === 'phone') {
        return { kind: 'affiliate_exists', matched: 'phone', emailHint: existing.emailHint };
      }

      const outcome = await deps.createConfirmedSignup(ctx.admin, {
        email: ctx.value.email,
        password: ctx.value.password,
        // Built here, never taken from the request. Descriptive only:
        // complete_affiliate_onboarding() reads these only when the page
        // gives it no details, and nothing here can grant a role.
        metadata: {
          first_name: ctx.value.firstName,
          last_name: ctx.value.lastName,
          phone: ctx.value.phone,
          role_hint: 'affiliate',
          signup_source: 'affiliate_join',
          terms_accepted_at: now().toISOString(),
        },
      });
      // Two presses at once: the second finds the first's login.
      if (outcome.status === 'exists') return { kind: 'email_in_use' };
      if (outcome.status === 'refused') return { kind: 'refused', field: outcome.field, message: outcome.message };
      if (outcome.status === 'error') return { kind: 'internal_error', detail: outcome.message };
      return { kind: 'created' };
    },
  };
}

/**
 * Resend, and the Account page's "Send verification email" (437).
 *
 *   * A login from before 437 that was never confirmed gets a fresh sign-up
 *     link, as before: the password untouched, no metadata written.
 *   * A confirmed affiliate login whose email the app has not verified gets
 *     the verification email: a sign-in link to /affiliate/verify, which
 *     marks the email verified (confirm_affiliate_email()).
 *   * Anything else gets nothing.
 * The response is the same in every case, so it tells no one whether the
 * address has a login.
 */
export function resendEndpoint(deps: FlowDeps): PublicEndpoint<{ email: string }> {
  return {
    action: 'resend',
    parse: (body) => validateEmailOnly(body),
    emailOf: (value) => value.email,
    run: async (ctx) => {
      const state = await deps.accountState(ctx.admin, ctx.value.email);
      if (state === 'none') return { kind: 'suppressed', reason: 'no_account' };

      const redirectTo = callbackUrl(ctx.config, 'affiliate_signup', ctx.origin);
      if (state === 'unconfirmed') {
        const outcome = await deps.regenerateSignupLink(ctx.admin, { email: ctx.value.email, redirectTo });
        return await sendVerification(ctx, deps, outcome, '');
      }

      if (!(await deps.affiliateEmailNeedsVerification(ctx.admin, ctx.value.email))) {
        return { kind: 'suppressed', reason: 'already_verified' };
      }
      const outcome = await deps.generateMagicLink(ctx.admin, { email: ctx.value.email, redirectTo });
      return await sendVerification(ctx, deps, outcome, '', 'email');
    },
  };
}

export function recoveryEndpoint(deps: FlowDeps): PublicEndpoint<{ email: string; flow: RecoveryFlow }> {
  return {
    action: 'recovery',
    parse: (body) => validateRecovery(body),
    emailOf: (value) => value.email,
    run: async (ctx) => {
      const redirectTo = callbackUrl(
        ctx.config,
        ctx.value.flow === 'staff' ? 'staff_recovery' : 'affiliate_recovery',
        ctx.origin,
      );
      const outcome = await deps.generateRecoveryLink(ctx.admin, { email: ctx.value.email, redirectTo });

      // No account for this address: nothing sent, nothing revealed.
      if (outcome.status === 'no_such_user' || outcome.status === 'already_confirmed') {
        return { kind: 'suppressed', reason: 'no_account' };
      }
      if (outcome.status === 'error') return { kind: 'internal_error', detail: outcome.message };
      if (!isTrustedActionLink(outcome.link.actionLink, ctx.config)) {
        return { kind: 'internal_error', detail: 'generated link failed origin validation' };
      }

      const email = renderPasswordRecovery(outcome.link.displayName, outcome.link.actionLink);
      return {
        kind: 'delivered',
        result: await deps.deliver(ctx.config, {
          requestId: ctx.requestId,
          actionType: 'password_recovery',
          to: outcome.link.email,
          subject: email.subject,
          html: email.html,
          text: email.text,
          recipientRole: ctx.value.flow === 'staff' ? 'staff' : 'affiliate',
        }),
      };
    },
  };
}
