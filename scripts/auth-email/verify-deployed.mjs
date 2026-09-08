// Post-deploy checks against the live endpoints.
//
//   node scripts/auth-email/verify-deployed.mjs --url https://<ref>.supabase.co --anon-key sb_publishable_...
//
// Safe by default: every probe here is either malformed (so it is rejected
// before anything happens) or aimed at an address with no account (so the server
// deliberately sends nothing). No account is created and no email is sent.
//
// Add --send-test-email to send ONE real verification email to the authorized
// test recipient. That one does create an account, so use a fresh address you
// are willing to keep.

import assert from 'node:assert/strict';

const args = process.argv.slice(2);
const flag = (name, fallback = null) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};

const BASE = (flag('--url') ?? '').replace(/\/+$/, '');
const ANON = flag('--anon-key');
const SEND_TEST = args.includes('--send-test-email');
const AUTHORIZED_RECIPIENT = 'shinthantstanley@gmail.com';

if (!BASE || !ANON) {
  console.error('Usage: node scripts/auth-email/verify-deployed.mjs --url https://<ref>.supabase.co --anon-key <publishable key> [--send-test-email]');
  process.exit(2);
}

let failures = 0;
const check = (label, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}: ${label}${detail ? ` — ${detail}` : ''}`);
  if (!ok) failures += 1;
};

const call = async (fn, { method = 'POST', body, contentType = 'application/json', origin } = {}) => {
  const headers = { apikey: ANON, Authorization: `Bearer ${ANON}` };
  if (contentType) headers['Content-Type'] = contentType;
  if (origin) headers.Origin = origin;
  const response = await fetch(`${BASE}/functions/v1/${fn}`, {
    method, headers,
    body: body === undefined ? undefined : (typeof body === 'string' ? body : JSON.stringify(body)),
  });
  const text = await response.text();
  let json = {};
  try { json = JSON.parse(text); } catch { /* keep the raw text */ }
  return { status: response.status, json, text, headers: response.headers };
};

// A different unknown address per run, so repeated runs do not exhaust a bucket.
const unknown = () => `no-such-account-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@example.invalid`;

console.log(`Checking ${BASE}/functions/v1/…\n`);

// --- the functions are reachable and configured -----------------------------
{
  const r = await call('auth-request-recovery', { body: { email: unknown(), flow: 'staff' } });
  if (r.status === 404) {
    check('auth-request-recovery is deployed', false, 'got 404 — deploy the functions first');
    process.exit(1);
  }
  if (r.status === 503 && r.json.error === 'not_configured') {
    check('secrets are set', false, `missing: ${(r.json.missing ?? []).join(', ')}`);
    process.exit(1);
  }
  if (r.status === 401) {
    check('gateway JWT verification is off for public endpoints', false,
      'got 401 — redeploy the three public functions with --no-verify-jwt');
    process.exit(1);
  }
  check('recovery for an unknown address answers 200 and sends nothing',
    r.status === 200 && r.json.ok === true, `status=${r.status}`);
  check('and its body gives no hint that the account is missing',
    !/not found|no account|unknown|does not exist/i.test(r.text), r.text.slice(0, 120));
}

// --- the request envelope ---------------------------------------------------
for (const fn of ['auth-signup-request', 'auth-resend-verification', 'auth-request-recovery']) {
  const get = await call(fn, { method: 'GET', body: undefined });
  check(`${fn}: GET is refused`, get.status === 405, `status=${get.status}`);

  const wrongType = await call(fn, { body: 'email=x', contentType: 'text/plain' });
  check(`${fn}: non-JSON is refused`, wrongType.status === 415, `status=${wrongType.status}`);

  const junk = await call(fn, { body: 'not json' });
  check(`${fn}: malformed JSON is refused`, junk.status === 400, `status=${junk.status}`);

  const huge = await call(fn, { body: { email: 'a'.repeat(20000) } });
  check(`${fn}: an oversized body is refused`, huge.status === 413 || huge.status === 400, `status=${huge.status}`);
}

// --- nothing may be smuggled in ---------------------------------------------
{
  const r = await call('auth-signup-request', {
    body: {
      first_name: 'Probe', last_name: 'Probe', phone: '+6591234567',
      email: unknown(), password: 'a-probe-password-value', terms_accepted: true,
      // None of these may be honoured — the request should be refused outright.
      to: 'victim@example.invalid', subject: 'Injected', html: '<p>injected</p>',
      redirect_to: 'https://evil.example', role: 'service_role', from_email: 'spoof@rev22.com.sg',
    },
  });
  check('a request carrying extra fields is refused, not partly honoured',
    r.status === 400 && r.json.error === 'invalid_request', `status=${r.status}`);
}
{
  const r = await call('auth-request-recovery', { body: { email: unknown(), flow: 'https://evil.example' } });
  check('an arbitrary flow value is refused', r.status === 400, `status=${r.status}`);
}
{
  const r = await call('auth-change-password', { body: { password: 'a-probe-password-value' } });
  check('password change without a user session is refused',
    r.status === 401, `status=${r.status}`);
}

// --- nothing sensitive comes back -------------------------------------------
{
  const r = await call('auth-request-recovery', { body: { email: unknown(), flow: 'affiliate' } });
  const leaked = ['/auth/v1/verify', 'action_link', 'hashed_token', 'delivery_secret', 'connect.pabbly.com', 'service_role']
    .filter(needle => r.text.includes(needle));
  check('no response carries a link, a token or a secret', leaked.length === 0, leaked.join(', '));
  check('responses are not cached', r.headers.get('cache-control') === 'no-store');
}

// --- rate limiting is live --------------------------------------------------
{
  const email = unknown();
  const results = [];
  for (let i = 0; i < 7; i++) {
    results.push(await call('auth-request-recovery', { body: { email, flow: 'staff' } }));
  }
  const limited = results.find(r => r.status === 429);
  check('the per-email recovery limit engages (5 per hour)', Boolean(limited),
    `statuses: ${results.map(r => r.status).join(',')}`);
  if (limited) {
    check('the 429 carries Retry-After and friendly wording',
      Boolean(limited.headers.get('retry-after')) && /try again/i.test(limited.json.message ?? ''),
      limited.json.message);
    check('and it does not say which bucket ran out',
      !/email|address|account/i.test(limited.json.message ?? ''), limited.json.message);
  }
}

// --- the one authorized real send -------------------------------------------
if (SEND_TEST) {
  console.log(`\nSending ONE real verification email to ${AUTHORIZED_RECIPIENT}…`);
  const r = await call('auth-signup-request', {
    body: {
      first_name: 'Shin Thant', last_name: 'Stanley', phone: '+6591234567',
      email: AUTHORIZED_RECIPIENT, password: `Energia-test-${Date.now()}`, terms_accepted: true,
    },
  });
  check('the signup request was accepted', r.status === 200 && r.json.ok === true, `status=${r.status}`);
  check('and delivery was not refused outright', r.json.status !== 'not_sent',
    r.json.status === 'not_sent' ? 'Pabbly rejected it — check the workflow filter and the Gmail step' : `status=${r.json.status}`);
  console.log(`\n  request_id: ${r.json.request_id}`);
  console.log('  Now check, by hand:');
  console.log('    1. the email arrived;');
  console.log('    2. Show original → From is "Rev 22 Global Energia <info@rev22.com.sg>",');
  console.log('       NOT the personal Gmail address;');
  console.log('    3. Reply-To is info@rev22.com.sg;');
  console.log('    4. the link works, and still works in a different browser.');
  console.log('\n  A 200 here means Pabbly accepted the request. It is not proof an email arrived.');
} else {
  console.log('\n(no email was sent — add --send-test-email for the one authorized live send)');
}

console.log(failures === 0 ? '\nAll deployed checks passed.' : `\n${failures} check(s) failed.`);
process.exit(failures === 0 ? 0 : 1);
