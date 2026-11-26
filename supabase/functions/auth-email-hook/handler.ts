// The hook's whole behaviour, kept apart from Deno.serve so index_test.ts can call it.
//
// Error shape: Supabase Auth reads a Send Email hook's refusal as
//   { "error": { "http_code": <number>, "message": <string> } }
// sent with a 4xx status; the Auth API call that triggered the hook then fails
// with that message and nothing is sent. Source: Supabase docs, Auth Hooks
// (https://supabase.com/docs/guides/auth/auth-hooks, "Error handling") and
// Send Email Hook (https://supabase.com/docs/guides/auth/auth-hooks/send-email-hook).

import { Webhook } from 'https://esm.sh/standardwebhooks@1.0.0';

export const REFUSAL_MESSAGE =
  'Email from the sign-in service is switched off for this project; the app sends its own emails.';

const KINDS = ['signup', 'recovery', 'invite', 'magiclink', 'email_change', 'reauthentication'];

// Success answer, quiet kinds only: Send Email Hook docs, "Outputs": "No outputs are
// required. An empty response with a status code of 200 is taken as a successful
// response." (https://supabase.com/docs/guides/auth/auth-hooks/send-email-hook).
// Body used: {} with HTTP 200, as the docs' own example returns.
const QUIET_KINDS = ['recovery', 'magiclink'];

export type HookDeps = {
  /** SEND_EMAIL_HOOK_SECRET, or '' when it is not set. */
  hookSecret: string;
  log?: (line: string) => void;
};

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

export async function handleHook(req: Request, deps: HookDeps): Promise<Response> {
  const log = deps.log ?? ((line: string) => console.log(line));
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  if (!deps.hookSecret) {
    // Names only, never values.
    log(JSON.stringify({ evt: 'auth_email_misconfigured', missing: ['SEND_EMAIL_HOOK_SECRET'] }));
    return json({ error: 'not_configured' }, 500);
  }

  // Signature first, on the raw body, before anything is parsed.
  const raw = await req.text();
  const headers = Object.fromEntries(req.headers);
  let payload: unknown;
  try {
    payload = new Webhook(deps.hookSecret.replace('v1,whsec_', '')).verify(raw, headers);
  } catch (_e) {
    log(JSON.stringify({ evt: 'auth_email_bad_signature' }));
    return json({ error: 'invalid_signature' }, 401);
  }

  // Only a fixed word from the list is logged, never the raw value.
  const rawKind = (payload as { email_data?: { email_action_type?: unknown } } | null)?.email_data?.email_action_type;
  const kind = typeof rawKind === 'string' && KINDS.includes(rawKind) ? rawKind : 'other';
  const requestId = (headers['webhook-id'] ?? '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 64) || 'none';
  if (QUIET_KINDS.includes(kind)) {
    // Nothing is sent, and the answer is the same success a real send would give.
    log(JSON.stringify({ evt: 'auth_email_dropped', kind, request_id: requestId }));
    return json({}, 200);
  }
  log(JSON.stringify({ evt: 'auth_email_refused', kind, request_id: requestId }));

  return json({ error: { http_code: 403, message: REFUSAL_MESSAGE } }, 403);
}
