// The Rules and regulations page (490; the user, 3 Nov 2026), rendered for
// real against a fake backend: the real AuthProvider and the real page under
// a router.
//
//   P1 Signed out: the plain page with Sign in and Join, the live rates in the
//      table (Tier 2 as a share of Tier 1 and of the sale), the product lists
//      by type, the machines, 489's start day, and every worked example
//      worked out from the live rates.
//   P2 Other rates: the table and every example follow them.
//   P3 A signed-in affiliate sees it inside the portal, with Rules in the menu.
//   P4 A read that fails says so, with Try again; no settings row says so.
//   P5 Without 489's cut-off the page states no start day.
//   P6 The sign-up page's "Energia Affiliate terms" opens this page in a new tab.
//   P7 The sums: rounding half away from zero to the cent, Tier 2 from the
//      rounded Tier 1, formatting.
//   492 (the user, 3 Nov 2026: "more professional"; Energia's name, never
//   "we", "our" or "us"; Tier 1 phone numbers for every direct referral):
//   P8 Laid out as terms: the summary's four rates as large figures (Tier 2
//      as a share of the sale, with its share of Tier 1), the effective date,
//      the contents, clauses 1 to 13 in order, each point numbered n.1, n.2,
//      ..., the examples as Appendix A, and the footer.
//   P9 Print: the button prints; on paper every product list is open, and
//      afterwards the lists are as they were.
//   P10 Energia's voice: no "we", "our", "ours" or "us" anywhere on the page,
//      signed out or signed in; the phone clause says what My Network shows.
//
// Every name and email is invented (@example.com).
// Run: node --test scripts/affiliate-signup/tests/rules-page-490.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, fakeSupabase, driver, tokenWith } from '../../ui/page-harness.mjs';

const dom = setupDom('https://energia.invalid/affiliate/rules');
const mod = await bundle(`
  import React from 'react';
  export { default as AffiliateRulesPage } from './src/pages/AffiliateRulesPage';
  export { default as AffiliateJoinPage } from './src/pages/AffiliateJoinPage';
  export { AuthProvider } from './src/context/AuthContext';
  export * as rules from './src/lib/affiliateRules';
  export { MemoryRouter, Routes, Route } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };`);
const { React, AuthProvider, MemoryRouter, Routes, Route, rules } = mod;
const d = driver(mod, dom);
const h = React.createElement;
after(async () => { await d.unmount(); dom.window.close(); });

const UID = '00000000-0000-4000-8000-000000000490';
const EMAIL = 'rae-490@example.com';
const INFO = {
  rates: { tier1_own: 15, tier1_third: 4.5, tier2_own: 35, tier2_third: 35 },
  machines_from: '2026-11-03',
  products: { own: ['Test Corset', 'Test Pillow'], third_party: ['Test Water System'], no_commission: ['Test Delivery Fee'] },
  machines: [{ name: 'Test Machine Rental', earns: 'third_party' }, { name: 'Test Own Machine', earns: 'own' }],
};

function app(start) {
  return h(MemoryRouter, { initialEntries: [start] },
    h(AuthProvider, null,
      h(Routes, null,
        h(Route, { path: '/affiliate/rules', element: h(mod.AffiliateRulesPage) }),
        h(Route, { path: '/affiliate/join', element: h(mod.AffiliateJoinPage) }))));
}

/** A backend; signedIn: an affiliate's session and account. */
function backend({ info = INFO, signedIn = false, fail } = {}) {
  const session = signedIn ? {
    access_token: tokenWith({ sub: UID, role: 'authenticated', amr: [{ method: 'password', timestamp: Math.floor(Date.now() / 1000) - 60 }] }),
    user: { id: UID, email: EMAIL, user_metadata: {} },
  } : null;
  const client = fakeSupabase({
    auth: {
      session,
      getSession: async () => ({ data: { session } }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
      signOut: async () => ({}), refreshSession: async () => ({ data: {} }),
    },
    tables: { profiles: [], affiliate_accounts: signedIn
      ? [{ id: 'acct-1', auth_user_id: UID, customer_id: 'cust-1', affiliate_id: 'aff-1', status: 'claimed', email_verified_at: '2026-11-01T02:00:00Z' }] : [] },
    rpc: { affiliate_rules_info: () => info },
    fail: fail ? { affiliate_rules_info: fail } : {},
  });
  globalThis.__supabase = client;
  return client;
}
const example = id => document.querySelector(`[data-example="${id}"]`)?.textContent ?? '';
const rateRow = n => [...document.querySelectorAll('[data-table="rates"] tbody tr')][n]?.textContent ?? '';

test('P1: signed out, the plain page with the live rates, lists, machines and worked examples', async () => {
  const client = backend();
  await d.mount(app('/affiliate/rules'));
  await d.tick(10);
  assert.equal(document.querySelector('h1')?.textContent, 'Rules and regulations');
  const links = [...document.querySelectorAll('a')].map(a => [a.textContent, a.getAttribute('href')]);
  assert.ok(links.some(([t, href]) => t === 'Sign in' && href === '/affiliate/login'));
  assert.ok(links.some(([t, href]) => t === 'Join' && href === '/affiliate/join'));
  assert.equal(document.querySelector('.portal-sidebar'), null, 'not the portal shell');
  assert.equal(client.calls.filter(c => c.rpc === 'affiliate_rules_info').length, 1);

  assert.equal(rateRow(0), 'Tier 115% of the amount paid4.5% of the amount paid');
  assert.equal(rateRow(1), 'Tier 235% of the Tier 1 commission (5.25% of the amount paid)35% of the Tier 1 commission (1.575% of the amount paid)');

  const list = k => [...document.querySelectorAll(`[data-list="${k}"] li`)].map(li => li.textContent);
  assert.deepEqual(list('own'), ['Test Corset', 'Test Pillow']);
  assert.deepEqual(list('third_party'), ['Test Water System']);
  assert.deepEqual(list('no_commission'), ['Test Delivery Fee']);
  assert.match(document.querySelector('[data-list="own"] summary').textContent, /Energia's own products \(2\)/);
  assert.deepEqual(list('machines'), ['Test Machine Rental: the third-party rate', 'Test Own Machine: Energia\'s own rate']);
  assert.match(d.text(), /Machines bought or rented earn like the machine itself: a third-party machine earns the third-party rate, and one of Energia's own machines earns Energia's own rate\. This applies to sales from 3 November 2026; earlier sales keep the rate they were made at\./);
  assert.match(d.text(), /Items that earn no commission: Test Delivery Fee\./);

  assert.match(example('tier1'), /You earn Tier 1: 15% of S\$468\.00 = S\$70\.20\..*Tier 2: 35% of S\$70\.20 = S\$24\.57\./);
  assert.match(example('tier2'), /Ann earns Tier 1: S\$70\.20\..*You earn Tier 2: S\$24\.57\./);
  assert.match(example('third'), /4\.5% of S\$2,886\.00 = S\$129\.87\..*35% of S\$129\.87 = S\$45\.45\./);
  assert.match(example('promotion'), /S\$200\.00 of it earns 15%: S\$30\.00\. S\$100\.00 earns 4\.5%: S\$4\.50\..*Tier 1: S\$34\.50\. Tier 2: S\$12\.08\./);
  assert.match(example('bundle'), /4\.5% of S\$15,000\.00 = S\$675\.00, once\. Tier 2: S\$236\.25\./);
  assert.match(example('package'), /Tier 1: S\$45\.00\. Tier 2: S\$15\.75\./);
  assert.match(example('therapy'), /15% of S\$199\.00 = S\$29\.85\. Tier 2: S\$10\.45\./);
  assert.match(example('parts'), /October: S\$60\.00 .*November: S\$90\.00/);
  assert.match(example('refund'), /becomes S\$40\.20 instead of S\$70\.20\..*S\$30\.00 comes off your next commission\./);
  assert.match(example('own-purchase'), /You earn nothing.*Tier 1: S\$15\.00; their referrer earns Tier 2: S\$5\.25\./);
  assert.match(d.text(), /Each month's commission is paid early the following month by PayNow or bank transfer\. There is no minimum\./);
});

test('P2: other rates, and the table and every example follow them', async () => {
  backend({ info: { ...INFO, rates: { tier1_own: 10, tier1_third: 5, tier2_own: 50, tier2_third: 20 } } });
  await d.mount(app('/affiliate/rules'));
  await d.tick(10);
  assert.equal(rateRow(0), 'Tier 110% of the amount paid5% of the amount paid');
  assert.equal(rateRow(1), 'Tier 250% of the Tier 1 commission (5% of the amount paid)20% of the Tier 1 commission (1% of the amount paid)');
  assert.match(example('tier1'), /10% of S\$468\.00 = S\$46\.80\..*50% of S\$46\.80 = S\$23\.40\./);
  assert.match(example('third'), /5% of S\$2,886\.00 = S\$144\.30\..*20% of S\$144\.30 = S\$28\.86\./);
  assert.match(example('bundle'), /= S\$750\.00, once\. Tier 2: S\$150\.00\./);
});

test('P3: a signed-in affiliate sees it inside the portal, with Rules in the menu', async () => {
  backend({ signedIn: true });
  await d.mount(app('/affiliate/rules'));
  await d.tick(10);
  assert.ok(document.querySelector('.portal-sidebar'), 'the portal shell');
  const rulesLinks = [...document.querySelectorAll('.portal-sidebar a')].filter(a => a.textContent.trim() === 'Rules');
  assert.equal(rulesLinks.length, 1);
  assert.equal(rulesLinks[0].getAttribute('href'), '/affiliate/rules');
  assert.match(rulesLinks[0].className, /\bactive\b/);
  assert.ok(![...document.querySelectorAll('a')].some(a => a.textContent === 'Join'), 'no Join for an affiliate');
  assert.match(example('tier1'), /S\$70\.20/);
});

test('P4: a read that fails says so, with Try again; no settings row says so', async () => {
  const client = backend({ fail: 'Failed to fetch' });
  await d.mount(app('/affiliate/rules'));
  await d.tick(10);
  assert.match(document.querySelector('[data-portal-error]')?.textContent ?? '', /This page could not be loaded: Failed to fetch/);
  delete client.fail.affiliate_rules_info;
  await d.click(d.button('Try again'));
  await d.tick(5);
  assert.ok(!document.querySelector('[data-portal-error]'));
  assert.match(example('tier1'), /S\$70\.20/);

  backend({ info: { ...INFO, rates: null } });
  await d.mount(app('/affiliate/rules'));
  await d.tick(10);
  assert.match(d.text(), /The commission rates could not be read\./);
  assert.ok(!document.querySelector('[data-example]'));
});

test('P5: without 489\'s cut-off the page states no start day', async () => {
  backend({ info: { ...INFO, machines_from: null } });
  await d.mount(app('/affiliate/rules'));
  await d.tick(10);
  assert.match(d.text(), /Machines bought or rented earn like the machine itself/);
  assert.doesNotMatch(d.text(), /This applies to sales from/);
});

test('P6: the sign-up page\'s "Energia Affiliate terms" opens this page in a new tab', async () => {
  backend();
  await d.mount(app('/affiliate/join'));
  await d.tick(10);
  const a = document.querySelector('a[data-link="terms"]');
  assert.equal(a?.textContent, 'Energia Affiliate terms');
  assert.equal(a.getAttribute('href'), '/affiliate/rules');
  assert.equal(a.getAttribute('target'), '_blank');
  assert.match(a.getAttribute('rel') ?? '', /noopener/);
});

test('P7: the sums round half away from zero to the cent, with Tier 2 from the rounded Tier 1', () => {
  assert.equal(rules.divRound(1575, 10), 158);
  assert.equal(rules.divRound(-1575, 10), -158);
  assert.equal(rules.divRound(1574, 10), 157);
  assert.equal(rules.percentOf(450, 35), 158, '35% of S$4.50 = S$1.58 (1.575 rounds up)');
  assert.equal(rules.percentOf(46800, 15), 7020);
  assert.equal(rules.percentOf(10000, 4.5), 450);
  assert.equal(rules.percentOf(288600, 4.5), 12987);
  assert.deepEqual(rules.earns(10000, 'third_party', INFO.rates), { tier1: 450, tier2: 158 });
  assert.equal(rules.share(7020, 26800, 46800), 4020);
  assert.equal(rules.sgd(1500000), 'S$15,000.00');
  assert.equal(rules.sgd(5), 'S$0.05');
  assert.equal(rules.sgd(-3000), '−S$30.00');
  assert.equal(rules.pct(1.575), '1.575%');
  assert.equal(rules.pct(15), '15%');
  assert.equal(rules.effectiveTier2(4.5, 35), 1.575);
  assert.equal(rules.longDate('2026-11-03'), '3 November 2026');
  assert.equal(rules.longDate(null), null);
});

test('P8: laid out as terms: the summary\'s figures, the effective date, numbered clauses, the appendix', async () => {
  backend();
  await d.mount(app('/affiliate/rules'));
  await d.tick(10);
  const fig = k => document.querySelector(`[data-glance] [data-rate="${k}"]`)?.textContent;
  assert.deepEqual([fig('tier1_own'), fig('tier1_third'), fig('tier2_own'), fig('tier2_third')], ['15%', '4.5%', '5.25%', '1.575%']);
  const glance = document.querySelector('[data-glance]').textContent;
  assert.match(glance, /Tier 1 · your referrals' purchases/);
  assert.match(glance, /of the amount paid \(35% of the Tier 1 commission\)/);
  assert.match(glance, /Paid monthly.*Earned when paid.*Refunds reduce it.*Two tiers only/);
  assert.match(glance, /This summary is for convenience\. The terms below apply\./);
  assert.equal(document.querySelector('[data-effective]')?.textContent, '3 November 2026');
  assert.match(document.querySelector('.terms-footer')?.textContent ?? '', /Energia Affiliate terms · Effective 3 November 2026/);

  const clauses = [...document.querySelectorAll('[data-clause]')];
  assert.deepEqual(clauses.map(c => c.getAttribute('data-clause')), ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13']);
  assert.deepEqual(clauses.map(c => c.querySelector('h2').textContent), [
    '1. About these terms', '2. Definitions', '3. Referrals', '4. Commission rates', '5. Energia\'s own and third-party products',
    '6. How each kind of purchase earns', '7. What earns no commission', '8. When commission is earned', '9. Refunds and cancellations',
    '10. Your affiliate account', '11. Payouts', '12. Your referrals\' details', '13. Changes to these terms']);
  for (const c of clauses) {
    const n = c.getAttribute('data-clause');
    const nums = [...c.querySelectorAll('.terms-points > li > .terms-num')].map(x => x.textContent);
    assert.ok(nums.length > 0, `clause ${n} has points`);
    assert.deepEqual(nums, nums.map((_, i) => `${n}.${i + 1}`), `clause ${n} numbered`);
  }
  assert.match(document.querySelector('[data-clause="1"]').textContent, /These terms are between you and Energia\..*please ask Energia staff at any Energia outlet\./);
  assert.ok(document.querySelector('[data-clause="4"] [data-table="rates"]'), 'the rates table is in clause 4');
  // The contents link to every clause and the appendix; the old anchors still lead to their parts.
  const hrefs = [...document.querySelectorAll('.terms-contents a')].map(a => a.getAttribute('href'));
  assert.deepEqual(hrefs, ['#about', '#definitions', '#referrals', '#earn', '#products', '#kinds', '#nothing', '#when', '#refunds',
                           '#status', '#payouts', '#details', '#changes', '#examples']);
  for (const h of hrefs) assert.ok(document.getElementById(h.slice(1)), h);
  const appendix = document.getElementById('examples');
  assert.match(appendix.querySelector('h2').textContent, /^Appendix A\. Worked examples$/);
  assert.equal(appendix.querySelectorAll('[data-example]').length, 10);
  assert.match(appendix.textContent, /These examples explain the terms above; where they differ, the terms apply\./);
});

test('P9: Print prints, with every product list open on paper and closed again afterwards', async () => {
  backend();
  await d.mount(app('/affiliate/rules'));
  await d.tick(10);
  let printed = 0;
  const print = window.print;
  window.print = () => { printed += 1; };
  try {
    await d.click(document.querySelector('[data-print]'));
    assert.equal(printed, 1);
  } finally { window.print = print; }
  const lists = [...document.querySelectorAll('.terms-doc details')];
  assert.equal(lists.length, 4);
  assert.ok(lists.every(l => !l.open), 'closed on screen');
  lists[0].open = true;
  window.dispatchEvent(new window.Event('beforeprint'));
  assert.ok(lists.every(l => l.open), 'all open on paper');
  window.dispatchEvent(new window.Event('afterprint'));
  assert.ok(lists[0].open && lists.slice(1).every(l => !l.open), 'as they were');
  assert.match(document.querySelector('[data-print]').className, /\bterms-noprint\b/);
});

test('P10: Energia\'s voice, signed out and signed in; the phone clause says what My Network shows', async () => {
  for (const signedIn of [false, true]) {
    backend({ signedIn });
    await d.mount(app('/affiliate/rules'));
    await d.tick(10);
    const page = document.querySelector('.terms-doc').textContent;
    assert.doesNotMatch(page, /\b(we|our|ours|us)\b/i, signedIn ? 'signed in' : 'signed out');
    assert.match(page, /Energia staff name you as the affiliate on a sale/);
    assert.match(page, /A discount Energia staff give on the whole invoice/);
    assert.match(document.querySelector('[data-clause="12"]').textContent,
      /It shows the phone numbers of your direct referrals \(Tier 1\), unless a referral has asked Energia to hide theirs, and never the phone number of a Tier 2 referral\. No numbers are shown while your affiliate account is suspended, or until Energia has confirmed that your portal login belongs to your customer record\./);
    assert.doesNotMatch(page, /were told, when they signed up/, 'the old phone rule is gone');
  }
});
