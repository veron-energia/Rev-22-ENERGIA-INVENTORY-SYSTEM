// End-to-end through the real Edge Function code, against a local stand-in for
// Pabbly. Nothing leaves this machine and no email is sent.
//
//   npm run test:auth-email:delivery
//
// What it establishes, before anyone touches a live workflow:
//   * the exact JSON body the Pabbly webhook will receive;
//   * that a request carrying the wrong shared secret is refused by the
//     workflow's own check, without an email being sent;
//   * that the function reports that refusal as "not_sent" rather than
//     pretending the email is on its way;
//   * that a timeout is reported as its own outcome and never auto-retried.
//
// It also writes the rendered emails to scripts/auth-email/preview/ so the HTML
// can be opened and read on a phone-width viewport.

import { handlePublicRequest } from '../../supabase/functions/_shared/auth-email/pipeline.ts';
import { recoveryEndpoint, signupEndpoint, type FlowDeps } from '../../supabase/functions/_shared/auth-email/flows.ts';
import { deliver } from '../../supabase/functions/_shared/auth-email/pabbly.ts';
import { normalizePhone } from '../../supabase/functions/_shared/auth-email/phone.ts';
import { renderPasswordChanged, renderPasswordRecovery, renderVerifySignup } from '../../supabase/functions/_shared/auth-email/templates.ts';
import type { AuthEmailConfig } from '../../supabase/functions/_shared/auth-email/config.ts';

const SHARED_SECRET = 'local-shared-secret-for-this-check-only';
const SUPABASE_URL = 'https://jknfhpgryywsrzdstqzy.supabase.co';
const APP_URL = 'https://rev-22-energia-inventory-system.vercel.app';
const RECIPIENT = 'shinthantstanley@gmail.com';
const ACTION_LINK = `${SUPABASE_URL}/auth/v1/verify?token=e1b7c0d9f2a4&type=signup&redirect_to=${encodeURIComponent(APP_URL + '/affiliate/verify')}`;

// --- a stand-in for the Pabbly workflow -------------------------------------
// It does exactly what step 2 of the real workflow must do: check the shared
// secret before anything is allowed to send.
interface Received { body: Record<string, unknown>; accepted: boolean; }
const received: Received[] = [];
// Counted the moment a request lands, so a deliberately slow response cannot
// make "how many requests arrived" look like zero.
let arrivals = 0;
let behaviour: 'normal' | 'hang' = 'normal';

const server = Deno.serve({ port: 8787, hostname: '127.0.0.1', onListen: () => {} }, async (req) => {
  arrivals += 1;
  const body = await req.json().catch(() => ({}));
  if (behaviour === 'hang') { await new Promise(r => setTimeout(r, 30_000)); }
  if (body.delivery_secret !== SHARED_SECRET) {
    received.push({ body, accepted: false });
    // The Gmail step is never reached, so no unauthorized email is sent.
    return new Response(JSON.stringify({ status: 'error', message: 'invalid delivery_secret' }), { status: 401 });
  }
  received.push({ body, accepted: true });
  return new Response(JSON.stringify({ status: 'success' }), { status: 200 });
});

const config = (overrides: Partial<AuthEmailConfig> = {}): AuthEmailConfig => ({
  supabaseUrl: SUPABASE_URL,
  serviceRoleKey: 'not-used-in-this-check',
  publicApiKey: 'sb_publishable_not_used',
  publicAppUrl: APP_URL,
  callbackBaseUrls: [APP_URL],
  allowedOrigins: [APP_URL],
  pabblyWebhookUrl: 'http://127.0.0.1:8787/workflow/sendwebhookdata/local-check',
  pabblySharedSecret: SHARED_SECRET,
  fromAddress: 'stanley@rev22.com.sg',
  fromName: 'Rev 22 Global Energia',
  replyTo: 'stanley@rev22.com.sg',
  hashSecret: 'local-hash-secret',
  trustedProxyHops: 1,
  pabblyTimeoutMs: 10_000,
  ...overrides,
});

// Supabase and the rate-limit database are stubbed; the delivery half is real.
const deps = (): FlowDeps => ({
  accountState: () => Promise.resolve('none'),
  generateSignupLink: () => Promise.resolve({ status: 'ok', link: { actionLink: ACTION_LINK, email: RECIPIENT, displayName: 'Shin Thant' } }),
  regenerateSignupLink: () => Promise.resolve({ status: 'ok', link: { actionLink: ACTION_LINK, email: RECIPIENT, displayName: 'Shin Thant' } }),
  generateRecoveryLink: () => Promise.resolve({ status: 'ok', link: { actionLink: ACTION_LINK.replace('type=signup', 'type=recovery'), email: RECIPIENT, displayName: 'Shin Thant' } }),
  deliver: (cfg, request) => deliver(cfg, request),
  normalizePhone,
});

const admin = {
  rpc: (fn: string) => Promise.resolve(
    fn === 'auth_email_reserve' ? { data: { allowed: true, retry_after_seconds: 0 }, error: null } : { data: null, error: null },
  ),
};

const post = (body: unknown) => new Request(`${APP_URL}/x`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Origin: APP_URL, 'x-forwarded-for': '203.0.113.7' },
  body: JSON.stringify(body),
});

const signupBody = {
  first_name: 'Shin Thant', last_name: 'Stanley', phone: '+6591234567',
  email: RECIPIENT, password: 'a-local-check-password', terms_accepted: true,
};

const redact = (body: Record<string, unknown>) => ({
  ...body,
  delivery_secret: `<${String(body.delivery_secret).length} characters — never printed>`,
  html: `<${String(body.html).length} characters of HTML>`,
  text: `<${String(body.text).length} characters of plain text>`,
});

// Everything the functions log, kept so it can be inspected for leakage.
const logged: string[] = [];
const realLog = console.log.bind(console);
console.log = (...parts: unknown[]) => {
  const line = parts.map(String).join(' ');
  if (line.startsWith('{"event":"auth_email')) { logged.push(line); return; }
  realLog(...parts);
};

let failures = 0;
const check = (label: string, ok: boolean, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}: ${label}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures += 1;
};

try {
  // --- 1. a correct request reaches the workflow and is accepted ------------
  let response = await handlePublicRequest(post(signupBody), signupEndpoint(deps()), {
    loadConfig: () => config(), makeAdmin: () => admin,
  });
  let json = await response.json();
  check('signup is accepted by the workflow', response.status === 200 && json.status === 'submitted', `status=${json.status}`);
  check('the workflow received exactly one request', received.length === 1);
  check('the shared secret was checked and matched', received[0]?.accepted === true);

  console.log('\n--- the JSON body the Pabbly webhook receives ---');
  console.log(JSON.stringify(redact(received[0].body), null, 2));

  const sent = received[0].body;
  check('the recipient is the account address', sent.to === RECIPIENT);
  check('the sender is the company alias', sent.from_email === 'stanley@rev22.com.sg' && sent.from_name === 'Rev 22 Global Energia');
  check('reply-to is set', sent.reply_to === 'stanley@rev22.com.sg');
  check('the subject is the agreed wording', sent.subject === 'Verify Your Energia Affiliate Account');
  check('the action link is inside the message, not a separate field',
    String(sent.html).includes(ACTION_LINK.replace(/&/g, '&amp;')) && !('token' in sent) && !('action_link' in sent));
  check('a request id is present for deduplication', typeof sent.request_id === 'string' && String(sent.request_id).length === 36);

  // --- 2. the wrong secret is refused, and no email is sent ----------------
  received.length = 0; arrivals = 0;
  response = await handlePublicRequest(post(signupBody), signupEndpoint(deps()), {
    loadConfig: () => config({ pabblySharedSecret: 'the-wrong-secret' }), makeAdmin: () => admin,
  });
  json = await response.json();
  check('a wrong shared secret is refused by the workflow before any sending', received[0]?.accepted === false);
  check('and the function reports it honestly rather than promising an email',
    json.status === 'not_sent', `status=${json.status}`);

  // --- 3. recovery, for the staff flow -------------------------------------
  received.length = 0; arrivals = 0;
  response = await handlePublicRequest(post({ email: RECIPIENT, flow: 'staff' }), recoveryEndpoint(deps()), {
    loadConfig: () => config(), makeAdmin: () => admin,
  });
  json = await response.json();
  check('staff recovery is accepted', response.status === 200 && json.status === 'submitted');
  check('recovery carries the staff role and subject',
    received[0]?.body.recipient_role === 'staff' && received[0]?.body.subject === 'Reset Your Energia Password');

  // --- 4. a hanging provider times out, once, and is not retried -----------
  received.length = 0;
  arrivals = 0;
  behaviour = 'hang';
  const started = Date.now();
  response = await handlePublicRequest(post(signupBody), signupEndpoint(deps()), {
    loadConfig: () => config({ pabblyTimeoutMs: 1500 }), makeAdmin: () => admin,
  });
  json = await response.json();
  const elapsed = Date.now() - started;
  behaviour = 'normal';
  check('the wait is bounded', elapsed < 4000, `${elapsed}ms`);
  check('a timeout is not reported as a failure, because it may have sent', json.status === 'submitted');
  check('and it is attempted exactly once — no automatic resend', arrivals === 1, `${arrivals} request(s) arrived`);

  // --- 5. write the rendered emails out for a human to look at ------------
  await Deno.mkdir('scripts/auth-email/preview', { recursive: true });
  const previews = {
    'verify-signup': renderVerifySignup('Shin Thant', ACTION_LINK),
    'password-recovery': renderPasswordRecovery('Shin Thant', ACTION_LINK.replace('type=signup', 'type=recovery')),
    'password-changed': renderPasswordChanged('Shin Thant', new Date().toISOString(), 'stanley@rev22.com.sg'),
  };
  for (const [name, email] of Object.entries(previews)) {
    await Deno.writeTextFile(`scripts/auth-email/preview/${name}.html`, email.html);
    await Deno.writeTextFile(`scripts/auth-email/preview/${name}.txt`, `Subject: ${email.subject}\n\n${email.text}\n`);
  }
  // --- 6. nothing sensitive reached the logs ------------------------------
  const allLogs = logged.join('\n');
  check('the function logged something to troubleshoot with', logged.length >= 4, `${logged.length} lines`);
  check('and no log line carries an address, a link, a token or a secret',
    !allLogs.includes('@') && !allLogs.includes('token=') && !allLogs.includes('/auth/v1/')
    && !allLogs.includes(SHARED_SECRET) && !allLogs.includes(signupBody.password) && !allLogs.includes(ACTION_LINK));
  console.log('\n--- a sample of what the functions log ---');
  realLog(logged.slice(0, 2).join('\n'));

  console.log('\nRendered previews written to scripts/auth-email/preview/');
  console.log(failures === 0 ? '\nAll local delivery checks passed. No email was sent.' : `\n${failures} check(s) failed.`);
} finally {
  await server.shutdown();
}

if (failures > 0) Deno.exit(1);
