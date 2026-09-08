// Two tests against the LIVE "Energia — Supabase Auth Emails" workflow.
//
//   deno run --allow-env --allow-read --allow-net scripts/auth-email/live-pabbly-test.ts --confirm
//
//   1. Wrong shared secret  → the workflow's filter must stop it. No email.
//   2. Correct shared secret → one real verification email, rendered by the same
//      template the Edge Function uses, to an authorized test recipient only.
//
// Recipients come from a fixed allowlist below. --to may pick one of them; there
// is no way to send anywhere else. Add an address here only when the account
// holder has authorized it in so many words.
//
//   --to <address>   default: the first entry
//   --first, --last  the name shown in the email
//
// Note on the link: this script cannot mint a real Supabase token (that needs the
// service-role key, which lives only in the deployed function), so test 2 carries
// a clearly-marked non-working link. It proves delivery, sender and rendering —
// not token validity. Real link testing happens after the functions are deployed.

import { renderVerifySignup } from '../../supabase/functions/_shared/auth-email/templates.ts';

const AUTHORIZED_RECIPIENTS = [
  'shinthantstanley@gmail.com',
  'tiktokautomationtryout@gmail.com',
];

const arg = (name: string, fallback: string) => {
  const i = Deno.args.indexOf(name);
  return i >= 0 && Deno.args[i + 1] ? Deno.args[i + 1] : fallback;
};

const RECIPIENT = arg('--to', AUTHORIZED_RECIPIENTS[0]);
const FIRST_NAME = arg('--first', 'Shin Thant');
const LAST_NAME = arg('--last', '');

if (!AUTHORIZED_RECIPIENTS.includes(RECIPIENT)) {
  console.error(`Refusing: ${RECIPIENT} is not an authorized test recipient.`);
  console.error(`Allowed: ${AUTHORIZED_RECIPIENTS.join(', ')}`);
  Deno.exit(2);
}

if (!Deno.args.includes('--confirm')) {
  console.error('Refusing to send without --confirm.');
  Deno.exit(2);
}

const env = new Map(
  (await Deno.readTextFile('.env'))
    .split('\n')
    .filter(l => /^[A-Z]/.test(l))
    .map(l => {
      const i = l.indexOf('=');
      return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^"|"$/g, '')] as [string, string];
    }),
);

const WEBHOOK = env.get('PABBLY_AUTH_EMAIL_WEBHOOK_URL')!;
const SECRET = env.get('PABBLY_AUTH_EMAIL_SHARED_SECRET')!;
const FROM_NAME = env.get('AUTH_EMAIL_FROM_NAME')!;
const FROM_ADDRESS = env.get('AUTH_EMAIL_FROM_ADDRESS')!;
const REPLY_TO = env.get('AUTH_EMAIL_REPLY_TO')!;

if (!WEBHOOK?.startsWith('https://connect.pabbly.com/')) {
  console.error('PABBLY_AUTH_EMAIL_WEBHOOK_URL is missing or not a Pabbly webhook.');
  Deno.exit(2);
}

const post = async (label: string, secret: string, subjectSuffix: string) => {
  const link = `${env.get('VITE_SUPABASE_URL')}/auth/v1/verify?token=NOT-A-REAL-TOKEN-delivery-test&type=signup&redirect_to=${encodeURIComponent(env.get('PUBLIC_APP_URL') + '/affiliate/verify')}`;
  const email = renderVerifySignup(`${FIRST_NAME} ${LAST_NAME}`.trim(), link);
  const requestId = crypto.randomUUID();

  const started = Date.now();
  const response = await fetch(WEBHOOK, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Idempotency-Key': requestId },
    body: JSON.stringify({
      delivery_secret: secret,
      request_id: requestId,
      action_type: 'verify_signup',
      to: RECIPIENT,
      from_name: FROM_NAME,
      from_email: FROM_ADDRESS,
      reply_to: REPLY_TO,
      subject: `${email.subject}${subjectSuffix}`,
      html: email.html,
      text: email.text,
      recipient_role: 'affiliate',
    }),
    signal: AbortSignal.timeout(10_000),
  });
  const body = await response.text().catch(() => '');
  console.log(`\n[${label}]`);
  console.log(`  request_id : ${requestId}`);
  console.log(`  http       : ${response.status} in ${Date.now() - started}ms`);
  console.log(`  body       : ${body.slice(0, 160)}`);
  return requestId;
};

console.log('Live test against the Energia — Supabase Auth Emails workflow.');
console.log(`Recipient: ${RECIPIENT}  (allowlisted)`);
console.log(`Name in email: ${`${FIRST_NAME} ${LAST_NAME}`.trim()}`);

const rejected = await post('1. WRONG secret — the filter must stop this', 'this-is-not-the-shared-secret', ' [SHOULD NOT ARRIVE]');
await new Promise(r => setTimeout(r, 3000));
const accepted = await post('2. CORRECT secret — one real email', SECRET, ' [delivery test]');

console.log(`
Both requests were accepted by the webhook listener — that is Pabbly taking the
request, not Gmail sending anything. The difference must show up downstream:

  In Pabbly → History, filtered to this workflow:
    ${rejected}   should stop at the Filter step (condition false)
    ${accepted}   should run through to the Gmail step

  In the inbox of ${RECIPIENT}:
    exactly ONE new message, the one marked [delivery test].
    If the [SHOULD NOT ARRIVE] one is there, the filter is not protecting the
    workflow and must be fixed before anything is deployed.

  On the message that did arrive, use "Show original" and check:
    From:     ${FROM_NAME} <${FROM_ADDRESS}>
    Reply-To: ${REPLY_TO}

  The link inside is deliberately not a working token.
`);
