// The affiliate portal, the referral link page and the promotion report after
// the audit's section 6 (B11, 425), rendered for real against a fake backend.
//
//   AFFILIATES-7   Each portal page whose figures fail to load says so with
//                  Try again, never "Loading…" for ever, and Try again loads
//                  them. /r/:code says "We could not check this link" when the
//                  check fails, with Try again; "This link is not valid" only
//                  when the server answers so.
//   AFFILIATES-12  A friend who shares a customer's phone waits for a check:
//                  the promotion report says so beside the friend and under
//                  the referrer.
//   454            My Referral QR shows the free therapy link (/r/<code>) and,
//                  for each seminar website taking registrations, the short
//                  seminar link (<site>/<code>) with Copy Link like it, one
//                  card per address; none while the affiliate is suspended or
//                  when there is none.
//
// The pages are bundled with esbuild and mounted in jsdom; only the Supabase
// client, the auth context and the QR library are stubbed. Every name and
// phone below is invented (ACMA fictional numbers).
//
// Run: node --test scripts/referrals/tests/portal-and-signup-425.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import { friendStatus } from '../../../src/lib/referral/campaign.mjs';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://portal.invalid/', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver',
  'sessionStorage', 'localStorage', 'location', 'history']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
dom.window.confirm = () => true;
dom.window.matchMedia = dom.window.matchMedia ?? (() => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {} }));
globalThis.matchMedia = dom.window.matchMedia;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.MessageChannel = class {
  constructor() {
    const port = () => ({ onmessage: null, close() {} });
    this.port1 = port(); this.port2 = port();
    this.port1.postMessage = data => setImmediate(() => this.port2.onmessage?.({ data }));
    this.port2.postMessage = data => setImmediate(() => this.port1.onmessage?.({ data }));
  }
};
const consoleError = console.error;
console.error = (...a) => { if (!String(a[0]).includes('not wrapped in act')) consoleError(...a); };

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { default as AffiliateDashboardPage } from './src/pages/AffiliateDashboardPage';
      export { default as AffiliateEarningsPage } from './src/pages/AffiliateEarningsPage';
      export { default as AffiliatePayoutsPage } from './src/pages/AffiliatePayoutsPage';
      export { default as AffiliateNetworkPage } from './src/pages/AffiliateNetworkPage';
      export { default as AffiliateReferralPage } from './src/pages/AffiliateReferralPage';
      export { default as AffiliateAccountPage } from './src/pages/AffiliateAccountPage';
      export { default as ReferralSignupPage } from './src/pages/ReferralSignupPage';
      export { default as ReferralPromotionPanel } from './src/components/referrals/ReferralPromotionPanel';
      export { MemoryRouter, Routes, Route } from 'react-router-dom';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      export { React };`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /^\.\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onResolve({ filter: /^qrcode$/ }, () => ({ path: 'qrcode', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: `export const supabase = {
        rpc: (...a) => globalThis.__backend.rpc(...a),
        from: (...a) => globalThis.__backend.from(...a),
        auth: { getSession: async () => ({ data: { session: null } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }), signOut: async () => ({}) },
        functions: { invoke: async () => ({ data: null, error: null }) } };` }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^qrcode$/, namespace: 'stub' }, () => ({ loader: 'js', contents: 'export default { toCanvas: async () => {}, toDataURL: async () => "" };' }));
  } }],
});
const M = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { MemoryRouter, Routes, Route, createRoot, act, React } = M;

const PORTAL = {
  affiliate_portal_dashboard: { network: { tier1: 1, tier2: 0, total: 1 }, earnings: { lifetime: 12, unpaid: 12, deduction: 0, paid: 0, settled: 0, reversed: 0, blocked: 0 }, by_tier: { tier1: 12, tier2: 0 }, recent: [] },
  affiliate_portal_earnings: { summary: { lifetime: 12, unpaid: 12, deduction: 0, paid: 0, settled: 0, reversed: 0, blocked: 0 }, by_tier: { tier1: 12, tier2: 0 }, by_month: [], by_purchase: [] },
  affiliate_portal_payouts: [],
  affiliate_portal_network: { tier1: [], tier2: [] },
  affiliate_portal_referral_info: { referral_code: 'T425RIA', accepting: true, direct_referrals: 1,
    seminar_links: [{ event_name: 'Test Health Seminar', first_day: '2026-11-23', last_day: '2026-11-24', url: 'https://seminar.example.com/T425RIA' }] },
  affiliate_portal_me: { name: 'Ria Test', email: 'ria@example.com', status: 'active', referral_code: 'T425RIA', joined_at: '2026-08-01' },
  affiliate_portal_campaign_progress: { campaign: null },
  public_affiliate_referral_info: { valid: true, accepting: true, affiliate_name: 'Ria Test' },
};
function createBackend() {
  const b = { calls: [], failures: new Map(), answers: { ...PORTAL } };
  b.rpc = async (name, args) => {
    b.calls.push({ name, args });
    await Promise.resolve();
    if (b.failures.has(name)) { const f = b.failures.get(name); b.failures.delete(name); return { data: null, error: { message: f } }; }
    return { data: structuredClone(b.answers[name] ?? null), error: null };
  };
  b.from = () => { const q = { select: () => q, eq: () => q, order: () => q, limit: () => q, in: () => q, is: () => q,
    maybeSingle: async () => ({ data: null, error: null }), single: async () => ({ data: null, error: null }),
    then: (res) => Promise.resolve({ data: [], error: null }).then(res) }; return q; };
  return b;
}

let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(element, path = '/', setup) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend();
  globalThis.__backend = backend;
  globalThis.__auth = { profile: null, user: { id: 'u-aff', email: 'ria@example.com' }, signOut: async () => {}, affiliate: { customer_id: 'c-ria' } };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(MemoryRouter, { initialEntries: [path] }, element)));
  await tick();
}
const text = () => document.body.textContent;
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const button = label => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === label);
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

const PAGES = [
  ['AffiliateDashboardPage', 'affiliate_portal_dashboard', 'Tier Breakdown'],
  ['AffiliateEarningsPage', 'affiliate_portal_earnings', 'By Month'],
  ['AffiliatePayoutsPage', 'affiliate_portal_payouts', 'No payouts yet'],
  ['AffiliateNetworkPage', 'affiliate_portal_network', 'Tier 1 — Direct Referrals'],
  ['AffiliateReferralPage', 'affiliate_portal_referral_info', 'Direct referrals so far'],
  ['AffiliateAccountPage', 'affiliate_portal_me', 'Referral Code'],
];
for (const [page, fn, loadedText] of PAGES) {
  test(`AFFILIATES-7: ${page} says when it cannot load, and Try again loads it`, async () => {
    await mount(React.createElement(M[page]), '/affiliate', b => b.failures.set(fn, 'Failed to fetch'));
    const box = document.querySelector('[data-portal-error]');
    assert.ok(box && box.textContent.includes('This page could not be loaded: Failed to fetch'), page);
    assert.ok(!text().includes('Loading…'), 'not Loading… beside the error');
    await click(button('Try again'));
    assert.ok(document.querySelector('[data-portal-error]') == null, 'the error goes');
    assert.ok(text().includes(loadedText), `${page} shows its figures`);
    assert.equal(backend.calls.filter(c => c.name === fn).length, 2, 'read twice: the failure and the retry');
  });
}

const signup = () => React.createElement(Routes, null, React.createElement(Route, { path: '/r/:referralCode', element: React.createElement(M.ReferralSignupPage) }));

test('AFFILIATES-7: /r/:code that cannot be checked says so, not "not valid", and Try again checks it again', async () => {
  await mount(signup(), '/r/T425RIA', b => b.failures.set('public_affiliate_referral_info', 'Failed to fetch'));
  assert.ok(text().includes('We could not check this link'));
  assert.ok(!text().includes('This link is not valid'));
  await click(button('Try again'));
  assert.ok(!text().includes('We could not check this link'));
  assert.ok(text().includes('Claim My FREE Energia Giveaway Bundle'), 'the form shows once the link checks out');
});

test('AFFILIATES-7: "This link is not valid" only when the server answers so', async () => {
  await mount(signup(), '/r/NOPE', b => { b.answers.public_affiliate_referral_info = { valid: false }; });
  assert.ok(text().includes('This link is not valid'));
  assert.ok(!text().includes('We could not check this link'));
});

test('AFFILIATES-12: a friend who shares a customer\'s phone waits for a check in the promotion report', async () => {
  const report = {
    campaign: { code: 'T425', title: 'T425 promotion', reward_reason: 'T425', starts_on: '2026-10-01', ends_on: '2026-10-31', tiers: [1, 3], today: '2026-10-18', status: 'provisional' },
    campaigns: [{ code: 'T425', title: 'T425 promotion', starts_on: '2026-10-01', ends_on: '2026-10-31' }],
    referrers: [{ referrer_customer_id: 'c-ria', name: 'Ria Test', phone: '+61491570006', is_affiliate: true, counted: 1, not_yet_visited: 0,
      referred_in_window: 2, waiting_check: 1, tier_reached: 1, next_tier: 3, to_next: 2, reward: null,
      friends: [
        { customer_id: 'f-nia', name: 'Nia Test', phone: '+61491570737', referred_on: '2026-10-05', first_visit_on: '2026-10-06', counted: true, needs_check: false },
        { customer_id: 'f-mae', name: 'Mae Test', phone: '+61491570157', referred_on: '2026-10-07', first_visit_on: '2026-10-08', counted: false, needs_check: true },
      ] }],
  };
  await mount(React.createElement(M.ReferralPromotionPanel, { isOwner: true }), '/', b => {
    b.answers.referral_campaign_report = report; b.answers.referral_reward_products = []; b.answers.stores_for_rewards = [];
  });
  const waiting = document.querySelector('[data-waiting-check]');
  assert.ok(waiting && waiting.textContent.includes('1 friend waits for a check (shares a phone)'), text());
  const expand = [...document.querySelectorAll('tr')].find(tr => tr.textContent.includes('Ria Test')).querySelector('button');
  await click(expand);
  const mae = [...document.querySelectorAll('tr')].find(tr => tr.textContent.includes('Mae Test'));
  assert.ok(mae && mae.textContent.includes('Waiting for a check (shares a phone)'));
  assert.equal(friendStatus({ counted: false, first_visit_on: '2026-10-08', needs_check: true }, 'final'), 'Waiting for a check (shares a phone)');
  assert.equal(friendStatus({ counted: true, first_visit_on: '2026-10-08', needs_check: false }, 'final'), 'Yes');
});

// 454: the seminar link beside the free therapy link.
const cards = () => [...document.querySelectorAll('.portal-qr-card')].map(c => ({
  title: c.querySelector('h3')?.textContent, url: c.querySelector('.portal-break')?.textContent, card: c }));

test('454: My Referral QR shows the free therapy link and the seminar link, and Copy Link copies the seminar one', async () => {
  const copied = [];
  Object.defineProperty(navigator, 'clipboard', { value: { writeText: async t => { copied.push(t); } }, configurable: true });
  await mount(React.createElement(M.AffiliateReferralPage), '/affiliate/referral');
  const [therapy, seminar, ...rest] = cards();
  assert.equal(rest.length, 0, 'two cards');
  assert.equal(therapy.title, 'Your free therapy link');
  assert.ok(therapy.url.endsWith('/r/T425RIA'), therapy.url);
  assert.equal(seminar.title, 'Your link for Test Health Seminar');
  assert.equal(seminar.url, 'https://seminar.example.com/T425RIA');
  assert.ok(seminar.card.textContent.includes('Existing Energia customers keep their own referrer'));
  await click([...seminar.card.querySelectorAll('button')].find(b => b.textContent.includes('Copy Link')));
  assert.deepEqual(copied, ['https://seminar.example.com/T425RIA']);
  delete navigator.clipboard;
});

test('454: one card per seminar link (one per address), none when there is none (or from a server before 454), none while suspended', async () => {
  const two = [{ event_name: 'Test Seminar A', url: 'https://a.example.com/T425RIA' }, { event_name: 'Test Seminar B', url: 'https://b.example.com/T425RIA' }];
  await mount(React.createElement(M.AffiliateReferralPage), '/affiliate/referral', b => { b.answers.affiliate_portal_referral_info = { ...PORTAL.affiliate_portal_referral_info, seminar_links: two }; });
  assert.deepEqual(cards().map(c => c.url).slice(1), two.map(l => l.url));
  // One site serves one event: the same address twice is one card, under the first name given.
  const same = [two[0], { event_name: 'Test Seminar C', url: two[0].url }];
  await mount(React.createElement(M.AffiliateReferralPage), '/affiliate/referral', b => { b.answers.affiliate_portal_referral_info = { ...PORTAL.affiliate_portal_referral_info, seminar_links: same }; });
  assert.deepEqual(cards().map(c => c.title).slice(1), ['Your link for Test Seminar A']);
  for (const seminar_links of [[], undefined]) {
    await mount(React.createElement(M.AffiliateReferralPage), '/affiliate/referral', b => { b.answers.affiliate_portal_referral_info = { ...PORTAL.affiliate_portal_referral_info, seminar_links }; });
    assert.deepEqual(cards().map(c => c.title), ['Your free therapy link'], JSON.stringify(seminar_links));
  }
  await mount(React.createElement(M.AffiliateReferralPage), '/affiliate/referral', b => { b.answers.affiliate_portal_referral_info = { ...PORTAL.affiliate_portal_referral_info, accepting: false }; });
  assert.equal(cards().length, 0, 'no link while suspended');
  assert.ok(text().includes('Your affiliate account is currently suspended'));
});

test('27 Nov 2026: somebody already registered gets "Book your first-time appointment" under the affiliate link, and nothing about a booking', async () => {
  await mount(signup(), '/r/T425RIA', b => {
    b.answers.affiliate_referral_signup_with_notice = { ok: true, outcome: 'already_registered',
      message: 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.' };
  });
  const type = async (el, value) => {
    assert.ok(el, 'the field exists');
    const set = Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value').set;
    await act(async () => { set.call(el, value); el.dispatchEvent(new dom.window.Event('input', { bubbles: true })); });
  };
  await type(document.getElementById('rl-top-first'), 'Nia');
  await type(document.getElementById('rl-top-last'), 'Test');
  await type(document.getElementById('rl-top-email'), 'nia@example.invalid');
  await type(document.querySelector('.rl-form-card input[type="tel"]'), '+61491570737');
  await click(button('YES! I WANT THIS FREE BUNDLE'));
  assert.ok(text().includes('You are already registered'), text());
  assert.equal(backend.calls.filter(c => c.name === 'affiliate_referral_signup_with_notice').length, 1, 'registered once');

  const done = document.querySelector('.rl-done');
  const join = [...done.querySelectorAll('a')].find(a => a.textContent.includes('Want to become an affiliate instead?'));
  const book = done.querySelector('a[data-action="book-first-visit"]');
  assert.ok(join && book, 'both links are there');
  assert.ok(join.compareDocumentPosition(book) & dom.window.Node.DOCUMENT_POSITION_FOLLOWING, 'the booking button comes after the affiliate link');
  assert.equal(book.textContent.trim(), 'Book your first-time appointment');
  const url = new URL(book.getAttribute('href'));
  assert.equal(url.origin + url.pathname, 'https://cal.com/energia/free', 'the free first-visit booking page');
  assert.equal(url.searchParams.get('name'), 'Nia Test');
  assert.equal(url.searchParams.get('email'), 'nia@example.invalid');
  assert.equal(url.searchParams.get('WhatsApp-Number'), '+61491570737');
  assert.equal(url.searchParams.get('smsReminderNumber'), '+61491570737');
  assert.equal(url.searchParams.get('affiliate'), null, 'no referrer label: the answer does not say whose customer they are');
  assert.ok(done.textContent.includes('Already booked? The confirmation cal.com sent you has your date and time'), 'booked people are pointed to their own confirmation');
  assert.ok(!/\b(19|20)\d\d-\d\d-\d\d\b|cal\.com\/(reschedule|booking)\//.test(done.innerHTML), 'no booking date or change link on this public page');
});

// 549 (the user, 27 Nov 2026): somebody already on file with an upcoming booking.
const KNOWN = { ok: true, outcome: 'already_registered',
  message: 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.' };
const BOOKED = { state: 'booked', start_at: '2026-12-07T02:00:00Z', uid: 't549Nia_1' };
async function registerKnown(lookup, { email = '' } = {}) {
  await mount(signup(), '/r/T425RIA', b => {
    b.answers.affiliate_referral_signup_with_notice = KNOWN;
    const rpc = b.rpc;
    b.rpc = async (name, args) => {
      if (name !== 'referral_booking_lookup') return rpc(name, args);
      b.calls.push({ name, args });
      await Promise.resolve();
      return lookup(args);
    };
  });
  const type = async (el, value) => {
    assert.ok(el, 'the field exists');
    const set = Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value').set;
    await act(async () => { set.call(el, value); el.dispatchEvent(new dom.window.Event('input', { bubbles: true })); });
  };
  await type(document.getElementById('rl-top-first'), 'Nia');
  await type(document.getElementById('rl-top-last'), 'Test');
  if (email) await type(document.getElementById('rl-top-email'), email);
  await type(document.querySelector('.rl-form-card input[type="tel"]'), '+61491570737');
  await click(button('YES! I WANT THIS FREE BUNDLE'));
  assert.ok(text().includes('You are already registered'), text());
  return { type, lookups: () => backend.calls.filter(c => c.name === 'referral_booking_lookup') };
}
const bookButton = () => document.querySelector('a[data-action="book-first-visit"]');

test('549: phone and email match an upcoming booking: its Singapore time, Change time and Cancel, and no Book button', async () => {
  const { lookups } = await registerKnown(() => ({ data: BOOKED, error: null }), { email: 'nia@example.invalid' });
  assert.deepEqual(lookups().map(c => c.args), [{ p_code: 'T425RIA', p_phone: '+61491570737', p_email: 'nia@example.invalid' }]);
  const box = document.querySelector('[data-booking="booked"]');
  assert.ok(box, 'the booking is shown');
  assert.ok(box.textContent.includes('Your appointment'));
  assert.ok(box.textContent.includes('Mon 7 Dec 2026, 10:00 am'), box.textContent);
  assert.equal(box.querySelector('a[data-action="change-time"]').getAttribute('href'), 'https://app.cal.com/reschedule/t549Nia_1');
  assert.equal(box.querySelector('a[data-action="change-time"]').textContent.trim(), 'Change time');
  assert.equal(box.querySelector('a[data-action="cancel-booking"]').getAttribute('href'), 'https://app.cal.com/booking/t549Nia_1?cancel=true');
  assert.equal(bookButton(), null, 'no Book button for somebody booked');
  assert.ok(text().includes('Want to become an affiliate instead?'));
});

test('549: an upcoming booking but no email typed: asked for the email, nothing about the booking, then shown', async () => {
  const { type, lookups } = await registerKnown(args => ({
    data: args.p_email === 'nia@example.invalid' ? BOOKED : { state: 'needs_email' }, error: null }));
  assert.equal(lookups()[0].args.p_email, null, 'no email typed: none sent');
  const ask = document.querySelector('[data-booking="needs-email"]');
  assert.ok(ask && ask.textContent.includes('You already have an appointment booked.'), text());
  assert.ok(!/Dec 2026|cal\.com\/(reschedule|booking)\//.test(document.body.innerHTML), 'no time and no change link before the email matches');
  assert.equal(bookButton(), null, 'no Book button: they have a booking');
  assert.equal(ask.querySelector('.rl-error'), null, 'no error before they try');

  await type(document.getElementById('rl-booking-email'), 'someone@example.invalid');
  await click(button('Show my appointment'));
  assert.ok(text().includes('That email does not match the booking.'), text());
  assert.equal(document.querySelector('[data-booking="booked"]'), null);

  await type(document.getElementById('rl-booking-email'), ' nia@example.invalid ');
  await click(button('Show my appointment'));
  assert.ok(document.querySelector('[data-booking="booked"]'), 'shown once the email matches');
  assert.ok(text().includes('Mon 7 Dec 2026, 10:00 am'));
  assert.deepEqual(lookups().map(c => c.args.p_email), [null, 'someone@example.invalid', 'nia@example.invalid']);
  assert.equal(backend.calls.filter(c => c.name === 'affiliate_referral_signup_with_notice').length, 1, 'looking again never registers again');
});

test('549: a typed email that does not match is said at once; too many tries is said in the box', async () => {
  let n = 0;
  await registerKnown(() => ({ data: n++ === 0 ? { state: 'needs_email' } : { state: 'try_later' }, error: null }), { email: 'other@example.invalid' });
  const ask = document.querySelector('[data-booking="needs-email"]');
  assert.ok(ask.textContent.includes('The email you typed does not match the booking.'), ask.textContent);
  assert.equal(document.getElementById('rl-booking-email').value, 'other@example.invalid');
  await click(button('Show my appointment'));
  assert.ok(text().includes('Too many tries. Please try again in an hour'), text());
  assert.equal(bookButton(), null);
});

test('549: a booking filled from Google Calendar (no cal.com uid): its time, and "contact Energia" instead of links', async () => {
  await registerKnown(() => ({ data: { state: 'booked', start_at: '2026-12-07T02:00:00Z', uid: null }, error: null }), { email: 'nia@example.invalid' });
  const box = document.querySelector('[data-booking="booked"]');
  assert.ok(box.textContent.includes('Mon 7 Dec 2026, 10:00 am'));
  assert.equal(box.querySelector('a'), null, 'no change or cancel link');
  assert.ok(box.textContent.includes('To change it, please contact Energia.'));
});

test('549: no upcoming booking, a database without 549, or a limit: the Book button as before', async () => {
  for (const answer of [
    { data: { state: 'none' }, error: null },
    { data: null, error: { code: 'PGRST202', message: 'Could not find the function public.referral_booking_lookup' } },
    { data: { state: 'try_later' }, error: null },
    { data: { state: 'something new' }, error: null },
  ]) {
    await registerKnown(() => answer);
    assert.ok(bookButton(), JSON.stringify(answer));
    assert.ok(text().includes('Already booked? The confirmation cal.com sent you'));
    assert.equal(document.querySelector('[data-booking]'), null);
  }
});
