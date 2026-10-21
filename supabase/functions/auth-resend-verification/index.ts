// POST /functions/v1/auth-resend-verification
//
// Two emails, both to an address that already has a login:
//   * a fresh sign-up link for somebody who signed up before 437 and never
//     verified (the email went missing, the link expired, or the account was
//     created while delivery was down);
//   * since 437, the affiliate Account page's "Send verification email": a
//     sign-in link for a confirmed affiliate login whose email the app has not
//     verified yet. Opening it at /affiliate/verify marks the email verified.
//
//   supabase functions deploy auth-resend-verification --no-verify-jwt
//
// Body: { email }. Nothing else, and deliberately so: no password, no name, no
// metadata. This endpoint can only mint a link for an account that already
// exists. It cannot create an account, cannot change a password, and cannot
// alter an account's stored details.
//
// A verified account gets nothing, however many times the form is submitted,
// and the answer is the same whatever the address holds.

import { handlePublicRequest } from '../_shared/auth-email/pipeline.ts';
import { resendEndpoint } from '../_shared/auth-email/flows.ts';
import { liveDeps } from '../_shared/auth-email/liveDeps.ts';

Deno.serve((req) => handlePublicRequest(req, resendEndpoint(liveDeps)));
