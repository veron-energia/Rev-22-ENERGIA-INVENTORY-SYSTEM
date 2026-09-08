// What each public endpoint actually does, with its collaborators injected.
//
// The `index.ts` files are wiring and nothing else; the decisions live here so
// they can be exercised without a Supabase project, a network or a real webhook.
// The interesting cases — an already-verified account, an address with no
// account, a signup whose email fails to send — are exactly the ones that are
// impractical to reproduce against a live project, so being able to test them
// offline is the difference between checking them and hoping.

import type { AuthEmailConfig } from './config.ts';
import type { AccountState, GenerateOutcome } from './admin.ts';
import type { DeliveryRequest, DeliveryResult } from './pabbly.ts';
import type { EndpointResult, PublicEndpoint, PublicContext } from './pipeline.ts';
import { validateEmailOnly, validateRecovery, validateSignup, type RecoveryFlow, type SignupInput } from './validate.ts';
import { callbackUrl, isTrustedActionLink } from './redirects.ts';
import { renderPasswordRecovery, renderVerifySignup } from './templates.ts';

// deno-lint-ignore no-explicit-any
type Admin = any;

export interface FlowDeps {
  accountState: (admin: Admin, email: string) => Promise<AccountState>;
  generateSignupLink: (admin: Admin, args: { email: string; password: string; redirectTo: string; metadata: Record<string, unknown> }) => Promise<GenerateOutcome>;
  regenerateSignupLink: (admin: Admin, args: { email: string; redirectTo: string }) => Promise<GenerateOutcome>;
  generateRecoveryLink: (admin: Admin, args: { email: string; redirectTo: string }) => Promise<GenerateOutcome>;
  deliver: (config: AuthEmailConfig, request: DeliveryRequest) => Promise<DeliveryResult>;
  normalizePhone: (raw: string) => string | null;
  now?: () => Date;
}

/** Send the verification email for a link we have just generated and trust. */
async function sendVerification(
  ctx: PublicContext<unknown>,
  deps: FlowDeps,
  outcome: GenerateOutcome,
  name: string,
): Promise<EndpointResult> {
  if (outcome.status === 'already_confirmed') return { kind: 'suppressed', reason: 'already_verified' };
  if (outcome.status === 'no_such_user') return { kind: 'suppressed', reason: 'no_account' };
  if (outcome.status === 'error') return { kind: 'internal_error', detail: outcome.message };

  if (!isTrustedActionLink(outcome.link.actionLink, ctx.config)) {
    return { kind: 'internal_error', detail: 'generated link failed origin validation' };
  }

  const email = renderVerifySignup(name || outcome.link.displayName, outcome.link.actionLink);
  return {
    kind: 'delivered',
    result: await deps.deliver(ctx.config, {
      requestId: ctx.requestId,
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

export function signupEndpoint(deps: FlowDeps): PublicEndpoint<SignupInput> {
  const now = deps.now ?? (() => new Date());
  return {
    action: 'signup',
    parse: (body) => validateSignup(body, deps.normalizePhone),
    emailOf: (value) => value.email,
    run: async (ctx) => {
      const redirectTo = callbackUrl(ctx.config, 'affiliate_signup', ctx.origin);
      const state = await deps.accountState(ctx.admin, ctx.value.email);

      // Already verified: send nothing. Submitting this form is not authority to
      // re-mail a live account, and the response is unchanged either way.
      if (state === 'confirmed') return { kind: 'suppressed', reason: 'already_verified' };

      const outcome = state === 'unconfirmed'
        // Signed up before but never verified. Treat it as a resend: a fresh
        // link, the password untouched, and no metadata written — otherwise
        // anyone could rewrite a pending account's details from this form.
        ? await deps.regenerateSignupLink(ctx.admin, { email: ctx.value.email, redirectTo })
        : await deps.generateSignupLink(ctx.admin, {
          email: ctx.value.email,
          password: ctx.value.password,
          redirectTo,
          // Built here, never taken from the request. Descriptive only: the
          // affiliate identity comes from complete_affiliate_onboarding(),
          // which reads the verified session and its own arguments and ignores
          // user metadata entirely, so nothing here can grant a role.
          metadata: {
            first_name: ctx.value.firstName,
            last_name: ctx.value.lastName,
            phone: ctx.value.phone,
            role_hint: 'affiliate',
            signup_source: 'affiliate_join',
            terms_accepted_at: now().toISOString(),
          },
        });

      // From here the account exists. A delivery failure must leave it alone: no
      // deletion, no second creation, no password rewrite. The person retries
      // through auth-resend-verification.
      return await sendVerification(ctx, deps, outcome, ctx.value.firstName);
    },
  };
}

export function resendEndpoint(deps: FlowDeps): PublicEndpoint<{ email: string }> {
  return {
    action: 'resend',
    parse: (body) => validateEmailOnly(body),
    emailOf: (value) => value.email,
    run: async (ctx) => {
      const state = await deps.accountState(ctx.admin, ctx.value.email);
      if (state === 'none') return { kind: 'suppressed', reason: 'no_account' };
      if (state === 'confirmed') return { kind: 'suppressed', reason: 'already_verified' };

      const redirectTo = callbackUrl(ctx.config, 'affiliate_signup', ctx.origin);
      const outcome = await deps.regenerateSignupLink(ctx.admin, { email: ctx.value.email, redirectTo });
      return await sendVerification(ctx, deps, outcome, '');
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
