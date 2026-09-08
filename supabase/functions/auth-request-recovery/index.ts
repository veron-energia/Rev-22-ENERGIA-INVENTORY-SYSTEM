// POST /functions/v1/auth-request-recovery
//
// Password recovery, for both affiliates and staff.
//
//   supabase functions deploy auth-request-recovery --no-verify-jwt
//
// Body: { email, flow } where flow is exactly "affiliate" or "staff". The
// browser names a flow; the server maps it to an allowlisted callback. There is
// no code path that turns caller-supplied text into a redirect.
//
// An address with no account produces the same response as one with an account.

import { handlePublicRequest } from '../_shared/auth-email/pipeline.ts';
import { recoveryEndpoint } from '../_shared/auth-email/flows.ts';
import { liveDeps } from '../_shared/auth-email/liveDeps.ts';

Deno.serve((req) => handlePublicRequest(req, recoveryEndpoint(liveDeps)));
