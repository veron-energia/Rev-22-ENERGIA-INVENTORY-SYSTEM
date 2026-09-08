// Server-side validation. The browser's checks are a convenience; these are the
// ones that count.
//
// Two rules run through everything here:
//   1. Only whitelisted fields are read. An unknown key is a rejected request,
//      not an ignored one — that is what stops a caller smuggling `role`,
//      `subject`, `html`, `redirect_to` or a provider setting into the payload.
//   2. Nothing user-supplied ever reaches a header, a recipient or a link.

export interface FieldError { field: string; message: string; }

export type Validated<T> = { ok: true; value: T } | { ok: false; errors: FieldError[] };

/** Supabase compares addresses case-insensitively after trimming; match that. */
export function normalizeEmail(raw: unknown): string {
  return typeof raw === 'string' ? raw.trim().toLowerCase() : '';
}

// Deliberately conservative, and it rejects the CR/LF and comma that make header
// injection possible in the first place.
const EMAIL_RE = /^[^\s@,;:<>"'\\]+@[^\s@,;:<>"'\\]+\.[^\s@,;:<>"'\\]+$/;

export function isEmailShaped(email: string): boolean {
  return email.length >= 6 && email.length <= 254 && EMAIL_RE.test(email) && !/[\r\n\t]/.test(email);
}

/**
 * The password policy the affiliate signup form has always enforced (>= 8),
 * plus the 72-byte ceiling bcrypt imposes underneath Supabase. Supabase applies
 * its own project policy on top; this never relaxes it, only refuses earlier.
 */
export const PASSWORD_MIN_LENGTH = 8;
export const PASSWORD_MAX_BYTES = 72;

export function passwordProblem(password: unknown): string | null {
  if (typeof password !== 'string') return 'Password is required.';
  if (password.length < PASSWORD_MIN_LENGTH) return `Password must be at least ${PASSWORD_MIN_LENGTH} characters.`;
  if (new TextEncoder().encode(password).length > PASSWORD_MAX_BYTES) {
    return `Password must be at most ${PASSWORD_MAX_BYTES} bytes.`;
  }
  return null;
}

/** Collapse whitespace and cap length. Names are display data, never markup. */
export function cleanName(raw: unknown, max = 80): string {
  return typeof raw === 'string' ? raw.replace(/\s+/g, ' ').trim().slice(0, max) : '';
}

/** Reject any key we did not ask for, rather than quietly dropping it. */
export function unknownFields(body: Record<string, unknown>, allowed: readonly string[]): string[] {
  return Object.keys(body).filter(k => !allowed.includes(k));
}

// ---------------------------------------------------------------------------
// Signup
// ---------------------------------------------------------------------------

export const SIGNUP_FIELDS = [
  'first_name', 'last_name', 'phone', 'email', 'password', 'terms_accepted',
] as const;

export interface SignupInput {
  firstName: string;
  lastName: string;
  phone: string;
  email: string;
  password: string;
  termsAccepted: true;
}

export function validateSignup(
  body: Record<string, unknown>,
  normalizePhone: (raw: string) => string | null,
): Validated<SignupInput> {
  const errors: FieldError[] = [];

  const extra = unknownFields(body, SIGNUP_FIELDS);
  if (extra.length) {
    // Named explicitly: a caller who tried to set `role` or `subject` should be
    // told it was refused, not left believing it was honoured.
    return { ok: false, errors: [{ field: extra[0], message: `Unexpected field: ${extra.slice(0, 5).join(', ')}` }] };
  }

  const firstName = cleanName(body.first_name);
  const lastName = cleanName(body.last_name);
  if (!firstName) errors.push({ field: 'first_name', message: 'Please enter your first name.' });

  const email = normalizeEmail(body.email);
  if (!isEmailShaped(email)) errors.push({ field: 'email', message: 'Enter a valid email address.' });

  const rawPhone = typeof body.phone === 'string' ? body.phone.trim().slice(0, 32) : '';
  const phone = rawPhone ? normalizePhone(rawPhone) : null;
  if (!phone) errors.push({ field: 'phone', message: 'Enter a valid international phone number.' });

  const pw = passwordProblem(body.password);
  if (pw) errors.push({ field: 'password', message: pw });

  if (body.terms_accepted !== true) {
    errors.push({ field: 'terms_accepted', message: 'Please agree to the Affiliate terms to continue.' });
  }

  if (errors.length) return { ok: false, errors };
  return {
    ok: true,
    value: {
      firstName, lastName, phone: phone as string, email,
      password: body.password as string, termsAccepted: true,
    },
  };
}

// ---------------------------------------------------------------------------
// Resend verification
// ---------------------------------------------------------------------------

export const RESEND_FIELDS = ['email'] as const;

export function validateEmailOnly(body: Record<string, unknown>): Validated<{ email: string }> {
  const extra = unknownFields(body, RESEND_FIELDS);
  if (extra.length) return { ok: false, errors: [{ field: extra[0], message: `Unexpected field: ${extra.slice(0, 5).join(', ')}` }] };
  const email = normalizeEmail(body.email);
  if (!isEmailShaped(email)) return { ok: false, errors: [{ field: 'email', message: 'Enter a valid email address.' }] };
  return { ok: true, value: { email } };
}

// ---------------------------------------------------------------------------
// Recovery
// ---------------------------------------------------------------------------

export const RECOVERY_FIELDS = ['email', 'flow'] as const;
export const RECOVERY_FLOWS = ['affiliate', 'staff'] as const;
export type RecoveryFlow = (typeof RECOVERY_FLOWS)[number];

/**
 * The browser names a fixed flow — "affiliate" or "staff" — and nothing else.
 * It never supplies a URL; the server maps the flow to an allowlisted callback.
 */
export function validateRecovery(body: Record<string, unknown>): Validated<{ email: string; flow: RecoveryFlow }> {
  const extra = unknownFields(body, RECOVERY_FIELDS);
  if (extra.length) return { ok: false, errors: [{ field: extra[0], message: `Unexpected field: ${extra.slice(0, 5).join(', ')}` }] };

  const email = normalizeEmail(body.email);
  if (!isEmailShaped(email)) return { ok: false, errors: [{ field: 'email', message: 'Enter a valid email address.' }] };

  const flow = typeof body.flow === 'string' ? body.flow.trim() : '';
  if (!(RECOVERY_FLOWS as readonly string[]).includes(flow)) {
    return { ok: false, errors: [{ field: 'flow', message: 'Unknown flow.' }] };
  }
  return { ok: true, value: { email, flow: flow as RecoveryFlow } };
}

// ---------------------------------------------------------------------------
// Password change
// ---------------------------------------------------------------------------

export const PASSWORD_CHANGE_FIELDS = ['password'] as const;

export function validatePasswordChange(body: Record<string, unknown>): Validated<{ password: string }> {
  const extra = unknownFields(body, PASSWORD_CHANGE_FIELDS);
  if (extra.length) return { ok: false, errors: [{ field: extra[0], message: `Unexpected field: ${extra.slice(0, 5).join(', ')}` }] };
  const problem = passwordProblem(body.password);
  if (problem) return { ok: false, errors: [{ field: 'password', message: problem }] };
  return { ok: true, value: { password: body.password as string } };
}
