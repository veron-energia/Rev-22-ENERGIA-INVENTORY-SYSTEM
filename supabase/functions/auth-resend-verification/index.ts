// POST /functions/v1/auth-resend-verification
//
// A fresh verification link for somebody who signed up but never verified — the
// email went missing, the link expired, or the account was created while
// delivery was down.
//
//   supabase functions deploy auth-resend-verification --no-verify-jwt
//
// Body: { email }. Nothing else, and deliberately so: no password, no name, no
// metadata. This endpoint can only mint a new link for an account that already
// exists and is not yet verified. It cannot create an account, cannot change a
// password, and cannot alter an account's stored details.
//
// A verified account gets nothing, however many times the form is submitted.

import { handlePublicRequest } from '../_shared/auth-email/pipeline.ts';
import { resendEndpoint } from '../_shared/auth-email/flows.ts';
import { liveDeps } from '../_shared/auth-email/liveDeps.ts';

Deno.serve((req) => handlePublicRequest(req, resendEndpoint(liveDeps)));
