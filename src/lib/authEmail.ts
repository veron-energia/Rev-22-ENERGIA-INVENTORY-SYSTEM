import { supabase } from './supabase';
import {
  interpretAuthEmailResponse,
  interpretPasswordChange,
  AUTH_EMAIL_COPY,
} from './auth-email/client.mjs';
import type { AuthEmailResult, PasswordChangeResult } from './auth-email/client.d.mts';

export { AUTH_EMAIL_COPY };
export type { AuthEmailResult, PasswordChangeResult };

// The Auth-email Edge Functions. Naming matches the function directories under
// supabase/functions.
export type AuthEmailFunction =
  | 'auth-signup-request'
  | 'auth-resend-verification'
  | 'auth-request-recovery'
  | 'auth-change-password';

/**
 * Call one of the Auth-email functions and read its response properly.
 *
 * `functions.invoke` reports any non-2xx as a `FunctionsHttpError` whose
 * `context` is the raw `Response`, so the structured body — field errors, the
 * rate-limit wording, the retry delay — is only there if you go and read it.
 * Treating that error as a bare failure would throw away everything the server
 * took the trouble to say.
 */
async function callFunction(name: AuthEmailFunction, body: Record<string, unknown>): Promise<{ status: number; payload: unknown }> {
  const { data, error } = await supabase.functions.invoke(name, { body });

  if (!error) return { status: 200, payload: data };

  const response = (error as { context?: unknown }).context;
  if (response instanceof Response) {
    const payload = await response.json().catch(() => ({}));
    return { status: response.status, payload };
  }
  // No response at all. The browser deliberately hides the difference between a
  // dead network, a CORS refusal and a 404 on the preflight, so this is as much
  // as the page can honestly know.
  return { status: 0, payload: {} };
}

/**
 * A "could not reach the server" result is accurate but unhelpful to whoever is
 * building this, because the three causes look identical from JavaScript. In a
 * dev build, say what they actually are; production keeps the plain wording.
 */
function withDevHint<T extends { kind: string; message: string | null }>(result: T, name: AuthEmailFunction): T {
  if (!import.meta.env.DEV || result.kind !== 'network') return result;
  return {
    ...result,
    message:
      `${result.message} (dev: the browser could not reach "${name}". Check the ` +
      `Network tab — a 404 on the preflight means the function is not deployed; ` +
      `a blocked preflight usually means this origin is not in AUTH_EMAIL_TEST_ORIGINS.)`,
  };
}

export async function requestAffiliateSignup(input: {
  firstName: string; lastName: string; phone: string; email: string; password: string; termsAccepted: boolean;
}): Promise<AuthEmailResult> {
  const { status, payload } = await callFunction('auth-signup-request', {
    first_name: input.firstName,
    last_name: input.lastName,
    phone: input.phone,
    email: input.email,
    password: input.password,
    terms_accepted: input.termsAccepted,
  });
  return withDevHint(interpretAuthEmailResponse(status, payload), 'auth-signup-request');
}

export async function resendVerification(email: string): Promise<AuthEmailResult> {
  const { status, payload } = await callFunction('auth-resend-verification', { email });
  return withDevHint(interpretAuthEmailResponse(status, payload), 'auth-resend-verification');
}

/**
 * The browser names the flow — "affiliate" or "staff" — and the server maps it
 * to an allowlisted callback. There is deliberately no way to pass a URL.
 */
export async function requestPasswordRecovery(email: string, flow: 'affiliate' | 'staff'): Promise<AuthEmailResult> {
  const { status, payload } = await callFunction('auth-request-recovery', { email, flow });
  return withDevHint(interpretAuthEmailResponse(status, payload), 'auth-request-recovery');
}

/**
 * Change the signed-in user's password.
 *
 * Goes through the Edge Function rather than `supabase.auth.updateUser` so the
 * security notification is sent by a server that watched Supabase confirm the
 * change, instead of on the browser's word that one happened. Supabase still
 * applies every rule it would have applied — the function makes the same
 * user-scoped call with this session's own token.
 */
export async function changePassword(password: string): Promise<PasswordChangeResult> {
  const { status, payload } = await callFunction('auth-change-password', { password });
  const result = withDevHint(interpretPasswordChange(status, payload), 'auth-change-password');
  // The session's tokens are reissued by the password change; refresh the local
  // copy so the rest of the app keeps working without a re-login.
  if (result.ok) await supabase.auth.refreshSession().catch(() => undefined);
  return result;
}
