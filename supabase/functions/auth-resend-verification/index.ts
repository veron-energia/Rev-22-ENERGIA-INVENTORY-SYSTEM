// POST /functions/v1/auth-resend-verification
//
// RETIRED (security audit of 17 Nov 2026, M6; the user, 20 Nov 2026). It sends
// nothing, makes nothing and counts nothing: after the request checks it
// answers the same 200 as before and makes no database call. Kept deployed so
// a page from before M6 gets its usual answer. The verification code comes
// from the signed-in Account page (affiliate-details, 'verify_email_send').
//
//   supabase functions deploy auth-resend-verification --no-verify-jwt
//
// Body: { email }, and nothing else (it is checked, then ignored).

import { handleRetiredResend } from '../_shared/auth-email/pipeline.ts';

Deno.serve((req) => handleRetiredResend(req));
