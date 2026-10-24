// POST /functions/v1/auth-signup-request
//
// Affiliate signup. Since 437 (the Owner's decisions of 20 Oct 2026) it makes
// the Supabase Auth login already confirmed, through the admin API, and sends
// no email: the page signs in with the password typed and goes straight to the
// affiliate dashboard. The email is verified later, from the Account page
// (auth-resend-verification sends that email through Pabbly). Supabase keeps
// owning the user and the password hash; "Confirm email" stays on.
//
// Deploy without gateway JWT verification — nobody signing up has a session yet:
//   supabase functions deploy auth-signup-request --no-verify-jwt
// What protects it instead lives in _shared/auth-email: a narrow request
// envelope, a strict field whitelist, and atomic database-backed rate limiting.
//
// Body: { first_name, last_name, phone, email, password, terms_accepted }.
// Any other field is a rejected request, not an ignored one.
//
// Answers: 200 { ok: true, status: 'created' } when the login was made; 409
// { error: 'email_in_use' } when the address already has a login (the Owner
// accepted that this shows an address is registered; decision 4), with nothing
// about that login changed; 400 for a refused field; 429 when rate limited.
// Since 466 (the Owner, 24 Oct 2026), asked before any login is made: 409
// { error: 'email_in_use', matched: 'email' } for an affiliate's own login
// email too, and 409 { error: 'affiliate_exists', matched: 'email' | 'phone',
// email_hint? } for another email or the phone of an existing affiliate (her
// sign-up's or her record's; the hint is her login email masked, when she is
// the only one). The page sends the person to Sign in; nothing is made. A
// customer of her own on an affiliate's phone (no login) who types her
// record's name signs up as before. Needs migration 466
// (affiliate_signup_existing) first: without it every sign-up answers 503.

import { handlePublicRequest } from '../_shared/auth-email/pipeline.ts';
import { signupEndpoint } from '../_shared/auth-email/flows.ts';
import { liveDeps } from '../_shared/auth-email/liveDeps.ts';

Deno.serve((req) => handlePublicRequest(req, signupEndpoint(liveDeps)));
