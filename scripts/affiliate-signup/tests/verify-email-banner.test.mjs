// The warning at the top of the affiliate portal while the email is not
// verified (3 Nov 2026), rendered for real against a fake backend: the real
// AuthProvider, the real portal guard and the real portal pages under a
// router.
//
//   W1  An affiliate whose email is not verified: the Dashboard opens with the
//       warning above its title, naming the login's address. Send
//       verification email asks auth-resend-verification for that address,
//       once however often it is tapped while sending, and says the link is
//       on its way. The warning stays until the email is verified.
//   W2  The same warning above the other portal pages; none on the Account
//       page, which has its own Verify your email (one Send button there).
//   W3  No warning for a verified email, before 437 is on the server, or
//       when the status cannot be read.
//   W4  A send that fails says why, and the warning stays with its button.
//   W5  Verified meanwhile in another tab: Send says so where the warning
//       was. Coming back to the tab reads the status again (not while the
//       tab is hidden), and the warning goes.
//   W6  Not verified, the next page opens with the warning straight away;
//       verified through the emailed link, the Account page reads it and the
//       next page opens without the warning, both before that page's own
//       read is back.
//
// Every name and email is invented (@example.com).
// Run: node --test scripts/affiliate-signup/tests/verify-email-banner.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { setupDom, bundle, fakeSupabase, driver, tokenWith, REPO } from '../../ui/page-harness.mjs';

const dom = setupDom('https://energia.invalid/affiliate/dashboard');
const mod = await bundle(`
  import React from 'react';
  export { default as AffiliateDashboardPage } from './src/pages/AffiliateDashboardPage';
  export { default as AffiliateNetworkPage } from './src/pages/AffiliateNetworkPage';
  export { default as AffiliateEarningsPage } from './src/pages/AffiliateEarningsPage';
  export { default as AffiliatePayoutsPage } from './src/pages/AffiliatePayoutsPage';
  export { default as AffiliateAccountPage } from './src/pages/AffiliateAccountPage';
  export { default as AffiliateVerifyPage } from './src/pages/AffiliateVerifyPage';
  export { AffiliateProtected } from './src/components/RouteGuards';
  export { AuthProvider } from './src/context/AuthContext';
  export { MemoryRouter, Routes, Route, useLocation, useNavigate } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };`);
const { React, act, AuthProvider, AffiliateProtected, MemoryRouter, Routes, Route, useLocation, useNavigate } = mod;
const d = driver(mod, dom);
const h = React.createElement;
after(async () => { await d.unmount(); dom.window.close(); });

const PORTAL_PAGES = [
  ['/affiliate/dashboard', 'AffiliateDashboardPage'],
  ['/affiliate/network', 'AffiliateNetworkPage'],
  ['/affiliate/earnings', 'AffiliateEarningsPage'],
  ['/affiliate/payouts', 'AffiliatePayoutsPage'],
  ['/affiliate/account', 'AffiliateAccountPage'],
];

/** The portal's routes, with the place shown and a way to move inside the app. */
let go = null;
function app(start) {
  const Where = () => { go = useNavigate(); return h('output', { 'data-where': useLocation().pathname }); };
  return h(MemoryRouter, { initialEntries: [start] },
    h(AuthProvider, null,
      h(Where),
      h(Routes, null,
        h(Route, { path: '/affiliate/login', element: h('p', null, 'LOGIN PAGE') }),
        h(Route, { path: '/affiliate/verify', element: h(mod.AffiliateVerifyPage) }),
        ...PORTAL_PAGES.map(([path, page]) => h(Route, { key: path, path, element: h(AffiliateProtected, null, h(mod[page])) })))));
}
const where = () => document.querySelector('[data-where]')?.getAttribute('data-where');
const goTo = async path => { await act(async () => { go(path); }); await d.tick(); };
const warning = () => document.querySelector('[data-banner="verify-email"]');
// Booleans, not elements: a failing check on an element prints the whole page.
const noBanner = () => document.querySelector('[data-banner]') === null;
const above = (a, b) => !!(a.compareDocumentPosition(b) & dom.window.Node.DOCUMENT_POSITION_FOLLOWING);

const PORTAL = {
  affiliate_portal_dashboard: { network: { tier1: 1, tier2: 0, total: 1 }, earnings: { lifetime: 12, unpaid: 12, deduction: 0, paid: 0, settled: 0, reversed: 0, blocked: 0 }, by_tier: { tier1: 12, tier2: 0 }, recent: [] },
  affiliate_portal_earnings: { summary: { lifetime: 12, unpaid: 12, deduction: 0, paid: 0, settled: 0, reversed: 0, blocked: 0 }, by_tier: { tier1: 12, tier2: 0 }, by_month: [], by_purchase: [] },
  affiliate_portal_payouts: [],
  affiliate_portal_network: { tier1: [], tier2: [] },
  affiliate_portal_campaign_progress: { campaign: null },
};

/**
 * A signed-in affiliate and the backend behind the portal. Each test has its
 * own login, since the app keeps each login's last answer for the tab.
 * statusReads counts the reads of the email status.
 */
let logins = 0;
function backend({ verifiedAt = null, amr = 'password', resend } = {}) {
  logins += 1;
  const uid = `00000000-0000-4000-8000-${String(logins).padStart(12, '0')}`;
  const email = `wen-${logins}@example.com`;
  const auth = {
    session: {
      access_token: tokenWith({ sub: uid, role: 'authenticated', amr: [{ method: amr, timestamp: Math.floor(Date.now() / 1000) - 60 }] }),
      user: { id: uid, email, user_metadata: {} },
    },
    getSession: async () => ({ data: { session: auth.session } }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
    signOut: async () => ({}),
    refreshSession: async () => ({ data: {} }),
  };
  const row = { id: 'acct-1', auth_user_id: uid, customer_id: 'cust-1', affiliate_id: 'aff-1', status: 'claimed', email_verified_at: verifiedAt };
  const client = fakeSupabase({
    auth,
    tables: { profiles: [], affiliate_accounts: [row] },
    rpc: {
      ...Object.fromEntries(Object.entries(PORTAL).map(([name, answer]) => [name, () => answer])),
      affiliate_portal_me: () => ({ customer_id: 'cust-1', name: 'Wen Testbanner', email, referral_code: 'TWEN486', status: 'active',
        joined_at: '2026-11-01T02:00:00Z', account_status: 'claimed', direct_referrals: 0 }),
      complete_affiliate_onboarding: () => ({ status: 'active', customer_id: 'cust-1', referral_code: 'TWEN486', already: true, new_customer: false, email_verified: false }),
      confirm_affiliate_email: () => {
        const already = !!row.email_verified_at;
        row.email_verified_at ??= '2026-11-03T02:00:00Z';
        return { verified: true, already };
      },
    },
    invoke: { 'auth-resend-verification': resend ?? (() => ({ data: { ok: true, status: 'submitted', request_id: 'r1' }, error: null })) },
  });
  client.statusReads = 0;
  const realFrom = client.from;
  client.from = table => {
    const q = realFrom(table);
    const realSelect = q.select.bind(q);
    q.select = cols => { if (String(cols).includes('email_verified_at')) client.statusReads += 1; return realSelect(cols); };
    return q;
  };
  globalThis.__supabase = client;
  return { client, row, email };
}

/** Reads of the email status answer this error instead (the AuthProvider's own read is left alone). */
function failStatusReads(client, error) {
  const realFrom = client.from;
  client.from = table => {
    const q = realFrom(table);
    const realSelect = q.select.bind(q);
    q.select = cols => {
      if (String(cols).includes('email_verified_at')) q.exec = async () => ({ data: null, error });
      return realSelect(cols);
    };
    return q;
  };
}

test('W1: an unverified email: the Dashboard opens with the warning, and Send asks for the login\'s own address once', async () => {
  let release = null;
  const { client, email } = backend({ resend: () => new Promise(r => {
    release = () => r({ data: { ok: true, status: 'submitted', request_id: 'r1' }, error: null });
  }) });
  await d.mount(app('/affiliate/dashboard'));
  await d.tick(10);
  assert.equal(where(), '/affiliate/dashboard');
  const banner = warning();
  assert.ok(banner, 'the warning shows');
  assert.match(banner.textContent, /^Please verify your email/);
  assert.match(banner.textContent, new RegExp(`We will send a link to ${email.replace('.', '\\.')}\\. Open it to confirm the address is yours\\.`));
  const title = document.querySelector('h1');
  assert.equal(title?.textContent, 'Dashboard');
  assert.ok(above(banner, title), 'above the page title');
  assert.match(d.text(), /Tier Breakdown/, 'the page itself loads as before');

  const send = d.button('Send verification email', banner);
  await d.click(send);
  assert.equal(send.textContent, 'Sending…');
  assert.equal(send.disabled, true);
  await d.click(send);
  release();
  await d.tick(5);
  assert.deepEqual(client.calls.filter(c => c.fn === 'auth-resend-verification').map(c => c.body), [{ email }], 'once, for the login\'s address');
  assert.match(banner.querySelector('[role="status"]')?.textContent ?? '', /A verification link is on its way to your email\./);
  assert.ok(warning(), 'the warning stays until the email is verified');
  assert.equal(d.button('Send verification email', warning())?.disabled, false);
});

test('W2: the warning is above every portal page but Account, which keeps its own Verify your email with one Send button', async () => {
  backend();
  for (const [path] of PORTAL_PAGES.filter(([path]) => path !== '/affiliate/account')) {
    await d.mount(app(path));
    await d.tick(10);
    assert.equal(where(), path);
    assert.ok(warning(), path);
    assert.ok(above(warning(), document.querySelector('h1')), `${path}: above the page title`);
  }
  await d.mount(app('/affiliate/account'));
  await d.tick(10);
  assert.ok(noBanner(), 'no warning on the Account page');
  assert.equal(document.querySelector('[data-email-verified]')?.textContent, 'Not verified');
  assert.ok(document.querySelector('[data-section="verify-email"]'));
  assert.equal([...document.querySelectorAll('button')].filter(b => b.textContent.trim() === 'Send verification email').length, 1);
  // My Referral QR draws the same shell (its QR library is not loaded here):
  // every portal page leaves the warning on but the Account page.
  for (const page of ['Dashboard', 'Network', 'Earnings', 'Payouts', 'Referral']) {
    const src = readFileSync(`${REPO}src/pages/Affiliate${page}Page.tsx`, 'utf8');
    assert.match(src, /<AffiliateLayout>/, page);
    assert.doesNotMatch(src, /verifyEmailBanner/, page);
  }
  assert.match(readFileSync(`${REPO}src/pages/AffiliateAccountPage.tsx`, 'utf8'), /<AffiliateLayout verifyEmailBanner=\{false\}>/);
});

test('W3: no warning for a verified email, before 437 is on the server, or when the status cannot be read', async () => {
  backend({ verifiedAt: '2026-11-01T02:00:00Z' });
  await d.mount(app('/affiliate/dashboard'));
  await d.tick(10);
  assert.match(d.text(), /Tier Breakdown/);
  assert.ok(noBanner(), 'verified');

  for (const [why, message] of [['before 437', 'column affiliate_accounts.email_verified_at does not exist'], ['the read failed', 'Failed to fetch']]) {
    const { client } = backend();
    failStatusReads(client, { message });
    await d.mount(app('/affiliate/dashboard'));
    await d.tick(10);
    assert.match(d.text(), /Tier Breakdown/, why);
    assert.ok(noBanner(), why);
  }
});

test('W4: a send that fails says why, and the warning stays with its button', async () => {
  const { client } = backend({ resend: () => ({ data: { ok: true, status: 'not_sent', request_id: 'r4' }, error: null }) });
  await d.mount(app('/affiliate/dashboard'));
  await d.tick(10);
  const banner = warning();
  await d.click(d.button('Send verification email', banner));
  assert.match(banner.querySelector('[role="alert"]')?.textContent ?? '', /We could not hand your email to our delivery service just now/);
  assert.equal(d.button('Send verification email', banner)?.disabled, false);
  // No answer at all (a dead network).
  client.invokeHandlers['auth-resend-verification'] = () => ({ data: null, error: { message: 'Failed to send a request to the Edge Function' } });
  await d.click(d.button('Send verification email', banner));
  assert.match(banner.querySelector('[role="alert"]')?.textContent ?? '', /We could not reach the server/);
  assert.equal(client.calls.filter(c => c.fn === 'auth-resend-verification').length, 2);
  assert.ok(warning());
});

test('W5: verified meanwhile in another tab: Send says so, and coming back to the tab reads again (not while it is hidden)', async () => {
  const first = backend({ resend: () => {
    first.row.email_verified_at = '2026-11-03T04:00:00Z';
    return { data: { ok: true, status: 'submitted', request_id: 'r5' }, error: null };
  } });
  await d.mount(app('/affiliate/dashboard'));
  await d.tick(10);
  await d.click(d.button('Send verification email', warning()));
  await d.tick(5);
  assert.ok(!warning(), 'the warning goes');
  assert.equal(document.querySelector('[data-banner="email-verified"]')?.textContent, 'Your email is already verified.');
  assert.doesNotMatch(d.text(), /on its way/);

  const second = backend();
  await d.mount(app('/affiliate/earnings'));
  await d.tick(10);
  assert.ok(warning());
  second.row.email_verified_at = '2026-11-03T05:00:00Z';
  const reads = second.client.statusReads;
  Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true });
  await act(async () => { document.dispatchEvent(new dom.window.Event('visibilitychange')); });
  await d.tick(5);
  assert.equal(second.client.statusReads, reads, 'not read while the tab is hidden');
  assert.ok(warning());
  delete document.visibilityState;
  assert.equal(document.visibilityState, 'visible');
  await act(async () => { document.dispatchEvent(new dom.window.Event('visibilitychange')); });
  await d.tick(5);
  assert.equal(second.client.statusReads, reads + 1, 'read again on coming back');
  assert.ok(noBanner(), 'the warning goes, with nothing to say');
});

test('W6: the next page opens with the warning straight away, and without it once the emailed link has verified the email', async () => {
  const { client } = backend({ amr: 'magiclink' });
  await d.mount(app('/affiliate/dashboard'));
  await d.tick(10);
  assert.ok(warning(), 'not verified yet');
  let open = null;
  client.gate.affiliate_accounts = new Promise(r => { open = r; });
  await goTo('/affiliate/earnings');
  assert.equal(where(), '/affiliate/earnings');
  assert.ok(warning(), 'straight away, before the read is back');
  open(); await d.tick(5);
  delete client.gate.affiliate_accounts;

  // The emailed link: /affiliate/verify marks the email verified and lands on the Account page.
  await goTo('/affiliate/verify');
  await d.tick(20);
  assert.equal(where(), '/affiliate/account');
  assert.equal(document.querySelector('[data-email-verified]')?.textContent, 'Verified');
  client.gate.affiliate_accounts = new Promise(r => { open = r; });
  await goTo('/affiliate/dashboard');
  assert.equal(where(), '/affiliate/dashboard');
  assert.ok(noBanner(), 'no warning, before the read is back');
  open(); await d.tick(5);
  delete client.gate.affiliate_accounts;
  assert.ok(noBanner(), 'nor after it');
});
