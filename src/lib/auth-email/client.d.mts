export interface AuthEmailResult {
  ok: boolean;
  kind: 'submitted' | 'not_sent' | 'created' | 'email_in_use' | 'affiliate_exists' | 'rate_limited' | 'invalid' | 'unauthorized' | 'unavailable' | 'network' | 'unknown';
  message: string | null;
  fields: Record<string, string>;
  requestId: string | null;
  retryAfterSeconds: number;
  /** 466: what an existing account has of a sign-up ('email_in_use' and 'affiliate_exists' only). */
  matched?: 'email' | 'phone';
}
export type SignupRefusalReason = 'email_in_use' | 'affiliate_email' | 'affiliate_phone';
export interface SignupRefusalState {
  signupRefused: { reason: SignupRefusalReason; email: string };
}
export interface SignupRefusal {
  reason: SignupRefusalReason;
  email: string;
  message: string;
}
export const SIGNUP_REFUSAL_REASONS: SignupRefusalReason[];
export function signupExistingMessage(reason: SignupRefusalReason): string;
export function signupRefusalState(result: AuthEmailResult, typedEmail: string): SignupRefusalState | null;
export function readSignupRefusal(state: unknown): SignupRefusal | null;
export interface PasswordChangeResult extends AuthEmailResult {
  kind: AuthEmailResult['kind'] | 'changed';
  notified: boolean;
}
export const AUTH_EMAIL_COPY: {
  signupSubmitted: string;
  signupExistingHint: string;
  signupEmailInUse: string;
  verifyEmailSent: string;
  resendSubmitted: string;
  recoverySubmitted: string;
  notSent: string;
  unavailable: string;
  network: string;
  unauthorized: string;
};
export function interpretAuthEmailResponse(httpStatus: number, body: unknown): AuthEmailResult;
export function interpretPasswordChange(httpStatus: number, body: unknown): PasswordChangeResult;
