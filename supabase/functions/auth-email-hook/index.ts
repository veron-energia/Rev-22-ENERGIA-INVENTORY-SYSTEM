// Supabase Send Email Auth Hook — project-wide Auth email delivery.
//
// Flow:
//   Supabase Auth --(signed Standard Webhook)--> this function
//     -> verify signature (SEND_EMAIL_HOOK_SECRET)
//     -> build branded Energia email(s) + the final Supabase verify URL
//     -> POST sanitized payload(s) to Pabbly (with a shared secret)
//     -> Pabbly Filter checks the secret, then Gmail sends from the company alias
//
// Supabase still owns every security token; Pabbly/Gmail only DELIVER the message.
//
// Deploy (JWT verification is intentionally OFF — the caller is Supabase Auth,
// not a browser; security comes from the signed webhook, not a user JWT):
//   supabase functions deploy auth-email-hook --no-verify-jwt
//
// Required secrets (see PABBLY_AUTH_EMAIL_SETUP.md):
//   SEND_EMAIL_HOOK_SECRET, PABBLY_AUTH_EMAIL_WEBHOOK_URL,
//   PABBLY_AUTH_EMAIL_SHARED_SECRET, AUTH_EMAIL_FROM_ADDRESS,
//   AUTH_EMAIL_FROM_NAME, AUTH_EMAIL_REPLY_TO
//   (SUPABASE_URL is injected by the Edge runtime; AUTH_EMAIL_TEST_RECIPIENT is optional.)

import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { Webhook } from 'https://esm.sh/standardwebhooks@1.0.0';
import { buildDeliveries, type AuthEmailEnv, type HookPayload } from './templates.ts';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

// Domain-only, for safe logging (never log full recipients or tokens).
const domainOf = (email: string) => {
  const at = email.lastIndexOf('@');
  return at >= 0 ? email.slice(at + 1) : 'unknown';
};

function readEnv(): { env: AuthEmailEnv; hookSecret: string; pabblyUrl: string; pabblySecret: string; missing: string[] } {
  const get = (k: string) => Deno.env.get(k) ?? '';
  const hookSecret = get('SEND_EMAIL_HOOK_SECRET');
  const pabblyUrl = get('PABBLY_AUTH_EMAIL_WEBHOOK_URL');
  const pabblySecret = get('PABBLY_AUTH_EMAIL_SHARED_SECRET');
  const supabaseUrl = get('SUPABASE_URL');
  const fromEmail = get('AUTH_EMAIL_FROM_ADDRESS');
  const fromName = get('AUTH_EMAIL_FROM_NAME');
  const replyTo = get('AUTH_EMAIL_REPLY_TO');
  const testRecipient = get('AUTH_EMAIL_TEST_RECIPIENT');

  const missing: string[] = [];
  if (!hookSecret) missing.push('SEND_EMAIL_HOOK_SECRET');
  if (!pabblyUrl) missing.push('PABBLY_AUTH_EMAIL_WEBHOOK_URL');
  if (!pabblySecret) missing.push('PABBLY_AUTH_EMAIL_SHARED_SECRET');
  if (!supabaseUrl) missing.push('SUPABASE_URL');
  if (!fromEmail) missing.push('AUTH_EMAIL_FROM_ADDRESS');
  if (!fromName) missing.push('AUTH_EMAIL_FROM_NAME');

  return {
    env: { supabaseUrl, fromName, fromEmail, replyTo: replyTo || undefined, testRecipient: testRecipient || undefined },
    hookSecret, pabblyUrl, pabblySecret, missing,
  };
}

async function postToPabbly(url: string, secret: string, delivery: Record<string, unknown>): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 9000);
  try {
    return await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ delivery_secret: secret, ...delivery }),
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);

  const { env, hookSecret, pabblyUrl, pabblySecret, missing } = readEnv();
  if (missing.length) {
    // Fail safe — don't forward anything. Log NAMES only, never values.
    console.error(JSON.stringify({ evt: 'auth_email_misconfigured', missing }));
    return json({ error: 'not_configured' }, 500);
  }

  // 1) Read the RAW body and verify the signed webhook BEFORE parsing JSON.
  const raw = await req.text();
  const headers = Object.fromEntries(req.headers);
  let payload: HookPayload;
  try {
    const wh = new Webhook(hookSecret.replace('v1,whsec_', ''));
    payload = wh.verify(raw, headers) as HookPayload;
  } catch (_e) {
    console.warn(JSON.stringify({ evt: 'auth_email_bad_signature' }));
    return json({ error: 'invalid_signature' }, 401);
  }

  // Stable-ish id for tracing + downstream dedupe (never a token).
  const requestId = headers['webhook-id'] || crypto.randomUUID();
  const actionType = String(payload?.email_data?.email_action_type ?? 'unknown');
  const isKnown = ['signup', 'recovery', 'invite', 'magiclink', 'email_change', 'reauthentication'].includes(actionType);
  if (!isKnown) console.warn(JSON.stringify({ evt: 'auth_email_unknown_action', request_id: requestId, action_type: actionType }));

  // 2) Build the branded email(s). Throws if there isn't safe data to act on.
  let deliveries;
  try {
    deliveries = buildDeliveries(payload, env, requestId);
  } catch (e) {
    console.error(JSON.stringify({ evt: 'auth_email_build_failed', request_id: requestId, action_type: actionType, reason: String((e as Error).message) }));
    return json({ error: 'insufficient_email_data' }, 400);
  }

  // 3) Deliver each via Pabbly. For email_change this is two calls; ALL must
  //    succeed (2xx) or we return non-200 so Supabase reports a send failure.
  for (const d of deliveries) {
    let res: Response;
    try {
      res = await postToPabbly(pabblyUrl, pabblySecret, d as unknown as Record<string, unknown>);
    } catch (e) {
      console.error(JSON.stringify({ evt: 'auth_email_delivery_error', request_id: requestId, action_type: actionType, to_domain: domainOf(d.to), reason: (e as Error).name }));
      return json({ error: 'delivery_failed' }, 502);
    }
    if (!res.ok) {
      console.error(JSON.stringify({ evt: 'auth_email_delivery_non_2xx', request_id: requestId, action_type: actionType, to_domain: domainOf(d.to), status: res.status }));
      return json({ error: 'delivery_rejected' }, 502);
    }
    console.log(JSON.stringify({ evt: 'auth_email_delivered', request_id: requestId, action_type: actionType, recipient_role: d.recipient_role, to_domain: domainOf(d.to), status: res.status }));
  }

  // 4) Supabase expects an empty JSON object + 200 on success.
  return json({}, 200);
});
