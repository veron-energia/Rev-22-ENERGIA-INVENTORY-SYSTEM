export interface AuthEmailResult {
  ok: boolean;
  kind: 'submitted' | 'not_sent' | 'rate_limited' | 'invalid' | 'unauthorized' | 'unavailable' | 'network' | 'unknown';
  message: string | null;
  fields: Record<string, string>;
  requestId: string | null;
  retryAfterSeconds: number;
}
export interface PasswordChangeResult extends AuthEmailResult {
  kind: AuthEmailResult['kind'] | 'changed';
  notified: boolean;
}
export const AUTH_EMAIL_COPY: {
  signupSubmitted: string;
  resendSubmitted: string;
  recoverySubmitted: string;
  notSent: string;
  unavailable: string;
  network: string;
  unauthorized: string;
};
export function interpretAuthEmailResponse(httpStatus: number, body: unknown): AuthEmailResult;
export function interpretPasswordChange(httpStatus: number, body: unknown): PasswordChangeResult;
