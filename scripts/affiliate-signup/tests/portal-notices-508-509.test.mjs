// The portal's two notices (the Owner, 17 Nov 2026), rendered for real against
// a fake backend: the real AuthProvider, the real portal guard and the real
// portal pages under a router.
//
//   N1  An affiliate whose link to the record is not confirmed yet (508,
//       affiliate_portal_me link_proven false): Dashboard, My Network,
//       Earnings and Payouts show "We are checking your account" instead of
//       their sections (the page still makes its one read, which the server
//       answers empty). The Account page shows the notice above the login's
//       own details.
//   N2  A suspended affiliate (509, portal_closed): every portal page shows
//       "Your affiliate account is suspended" and nothing else; the menu has
//       only Rules and Sign Out; no warning about the email.
//   N3  Before 509 is on the server, "me" says status "suspended" and still
//       answers: the pages hide it all the same.
//   N4  An affiliate whose link is proven, or a server before 508 (no
//       link_proven): the pages as before, no notice.
//   N5  When "me" cannot be read, the pages show what they read, as before.
//
// Every name and email is invented (@example.com).
// Run: node --test scripts/affiliate-signup/tests/portal-notices-508-509.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, fakeSupabase, driver, tokenWith } from '../../ui/page-harness.mjs';

const dom = setupDom('https://energia.invalid/affiliate/dashboard');
const mod = await bundle(`
  import React from 'react';
  export { default as AffiliateDashboardPage } from './src/pages/AffiliateDashboardPage';
  export { default as AffiliateNetworkPage } from './src/pages/AffiliateNetworkPage';
  export { default as AffiliateEarningsPage } from './src/pages/AffiliateEarningsPage';
  export { default as AffiliatePayoutsPage } from './src/pages/AffiliatePayoutsPage';
  export { default as AffiliateAccountPage } from './src/pages/AffiliateAccountPage';
  export { AffiliateProtected } from './src/components/RouteGuards';
  export { AuthProvider } from './src/context/AuthContext';
  export { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };`);
const { React, AuthProvider, AffiliateProtected, MemoryRouter, Routes, Route, useLocation } = mod;
const d = driver(mod, dom);
const h = React.createElement;
after(async () => { await d.unmount(); dom.window.close(); });

const RECORD_PAGES = [
  ['/affiliate/dashboard', 'AffiliateDashboardPage', 'affiliate_portal_dashboard'],
  ['/affiliate/network', 'AffiliateNetworkPage', 'affiliate_portal_network'],
  ['/affiliate/earnings', 'AffiliateEarningsPage', 'affiliate_portal_earnings'],
  ['/affiliate/payouts', 'AffiliatePayoutsPage', 'affiliate_portal_payouts'],
];
const ALL_PAGES = [...RECORD_PAGES.map(([p, c]) => [p, c]), ['/affiliate/account', 'AffiliateAccountPage']];

function app(start) {
  const Where = () => h('output', { 'data-where': useLocation().pathname });
  return h(MemoryRouter, { initialEntries: [start] },
    h(AuthProvider, null,
      h(Where),
      h(Routes, null,
        h(Route, { path: '/affiliate/login', element: h('p', null, 'LOGIN PAGE') }),
        ...ALL_PAGES.map(([path, page]) => h(Route, { key: path, path, element: h(AffiliateProtected, null, h(mod[page])) })))));
}
const notice = kind => document.querySelector(`[data-notice="portal-${kind}"]`);
const navLabels = () => [...document.querySelectorAll('.portal-sidebar .portal-navlink')].map(a => a.textContent.trim());

const PORTAL = {
  affiliate_portal_dashboard: { network: { tier1: 1, tier2: 0, total: 1 }, earnings: { lifetime: 12, unpaid: 12, deduction: 0, paid: 0, settled: 0, reversed: 0, blocked: 0 }, by_tier: { tier1: 12, tier2: 0 }, recent: [] },
  affiliate_portal_earnings: { summary: { lifetime: 12, unpaid: 12, deduction: 0, paid: 0, settled: 0, reversed: 0, blocked: 0 }, by_tier: { tier1: 12, tier2: 0 }, by_month: [], by_purchase: [] },
  affiliate_portal_payouts: [],
  affiliate_portal_network: { tier1: [], tier2: [] },
  affiliate_portal_campaign_progress: { campaign: null },
  affiliate_portal_details: { route: 'code', verified: true, first_name: 'Nell', last_name: 'Notice', phone: '+61491570101', email: 'nell@example.com', login_email: 'nell@example.com', request: null },
};

/** A signed-in affiliate whose "me" answers `me` (or fails when `me` is an Error). Each test has its own login. */
let logins = 0;
function backend(me) {
  logins += 1;
  const uid = `00000000-0000-4000-8509-${String(logins).padStart(12, '0')}`;
  const email = `nell-${logins}@example.com`;
  const auth = {
    session: {
      access_token: tokenWith({ sub: uid, role: 'authenticated', amr: [{ method: 'password', timestamp: Math.floor(Date.now() / 1000) - 60 }] }),
      user: { id: uid, email, user_metadata: {} },
    },
    getSession: async () => ({ data: { session: auth.session } }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
    signOut: async () => ({}),
    refreshSession: async () => ({ data: {} }),
  };
  const row = { id: 'acct-1', auth_user_id: uid, customer_id: 'cust-1', affiliate_id: 'aff-1', status: 'claimed', email_verified_at: null };
  const client = fakeSupabase({
    auth,
    tables: { profiles: [], affiliate_accounts: [row] },
    rpc: {
      ...Object.fromEntries(Object.entries(PORTAL).map(([name, answer]) => [name, () => answer])),
      affiliate_portal_me: () => { if (me instanceof Error) throw me; return typeof me === 'function' ? me(email) : me; },
    },
    fail: me instanceof Error ? { affiliate_portal_me: me.message } : {},
  });
  globalThis.__supabase = client;
  return { client, email };
}

const openMe = email => ({ customer_id: 'cust-1', name: 'Nell Notice', email, referral_code: 'TNEL509', status: 'active',
  joined_at: '2026-11-01T02:00:00Z', account_status: 'claimed', direct_referrals: 1, link_proven: true });

test('N1: a link not confirmed yet: the record pages show "We are checking your account" instead of their sections', async () => {
  backend(email => ({ ...openMe(email), name: 'Nell Typed', joined_at: null, direct_referrals: 0, link_proven: false }));
  for (const [path, , rpc] of RECORD_PAGES) {
    await d.mount(app(path));
    await d.tick(10);
    const n = notice('checking');
    assert.ok(n, `${path}: the notice shows`);
    assert.match(n.textContent, /^We are checking your account/);
    assert.match(n.textContent, /Energia is confirming that this customer record is yours\. Your referrals, earnings and payouts will show here once that is done\./);
    assert.equal(document.querySelector('h1'), null, `${path}: not the page's sections`);
    assert.ok(!/Tier Breakdown|Direct Referrals|By Month|Payout History/.test(d.text()), `${path}: none of ${rpc}'s sections`);
    assert.equal(notice('suspended'), null);
  }
  await d.mount(app('/affiliate/account'));
  await d.tick(10);
  assert.ok(notice('checking'), 'Account: the notice shows');
  assert.equal(document.querySelector('h1')?.textContent, 'Account', 'Account: the page shows below it');
  assert.match(d.text(), /Nell Typed/, 'the name the login typed');
  assert.ok(!!(notice('checking').compareDocumentPosition(document.querySelector('h1')) & dom.window.Node.DOCUMENT_POSITION_FOLLOWING), 'above the page');
  assert.ok(navLabels().includes('Dashboard'), 'the menu is as before');
});

test('N2: a suspended affiliate: every page shows "Your affiliate account is suspended" and nothing else', async () => {
  backend({ status: 'suspended', portal_closed: true });
  for (const [path] of ALL_PAGES) {
    await d.mount(app(path));
    await d.tick(10);
    const n = notice('suspended');
    assert.ok(n, `${path}: the notice shows`);
    assert.match(n.textContent, /^Your affiliate account is suspended/);
    assert.match(n.textContent, /Your affiliate portal is closed for now\. Please contact Energia if you have any questions\./);
    assert.equal(document.querySelector('h1'), null, `${path}: nothing of the page`);
    assert.equal(document.querySelector('[data-banner]'), null, `${path}: no email warning`);
    assert.deepEqual(navLabels(), ['Rules', 'Sign Out'], `${path}: only Rules and Sign Out`);
  }
  // The server refuses them all (509); a refusal is not shown either.
  assert.ok(!/Not an affiliate account|Tier Breakdown|Change Password/.test(d.text()));
});

test('N3: before 509, "me" says suspended and still answers: the pages hide it all the same', async () => {
  backend(email => ({ ...openMe(email), status: 'suspended' }));
  await d.mount(app('/affiliate/network'));
  await d.tick(10);
  assert.ok(notice('suspended'));
  assert.equal(document.querySelector('h1'), null);
});

test('N4: a proven link, or a server before 508: the pages as before, with no notice', async () => {
  for (const me of [openMe, email => { const m = openMe(email); delete m.link_proven; return m; }]) {
    backend(me);
    for (const [path] of ALL_PAGES) {
      await d.mount(app(path));
      await d.tick(10);
      assert.equal(notice('checking'), null, path);
      assert.equal(notice('suspended'), null, path);
      assert.ok(document.querySelector('h1'), `${path}: the page shows`);
    }
  }
});

test('N5: "me" cannot be read: the pages show what they read, as before', async () => {
  backend(new Error('network down'));
  await d.mount(app('/affiliate/dashboard'));
  await d.tick(10);
  assert.equal(notice('checking'), null);
  assert.equal(notice('suspended'), null);
  assert.equal(document.querySelector('h1')?.textContent, 'Dashboard');
  assert.match(d.text(), /Tier Breakdown/);
});
