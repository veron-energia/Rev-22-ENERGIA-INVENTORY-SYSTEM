// POST /functions/v1/auth-signup-request
//
// Affiliate signup. Creates the Supabase Auth user, has Supabase mint the
// verification link, and hands the finished email to Pabbly. Supabase keeps
// owning the user, the password hash and the token; only delivery moved.
//
// Deploy without gateway JWT verification — nobody signing up has a session yet:
//   supabase functions deploy auth-signup-request --no-verify-jwt
// What protects it instead lives in _shared/auth-email: a narrow request
// envelope, a strict field whitelist, and atomic database-backed rate limiting.
//
// Body: { first_name, last_name, phone, email, password, terms_accepted }.
// Any other field is a rejected request, not an ignored one.
//
// The generated link is never returned to the browser and never logged, and the
// response is identical for a new, an unverified and an already-verified address.

import { handlePublicRequest } from '../_shared/auth-email/pipeline.ts';
import { signupEndpoint } from '../_shared/auth-email/flows.ts';
import { liveDeps } from '../_shared/auth-email/liveDeps.ts';

Deno.serve((req) => handlePublicRequest(req, signupEndpoint(liveDeps)));
