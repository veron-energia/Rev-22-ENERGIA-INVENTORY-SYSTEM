// The Commissions page after the audit's section 6 (B11), rendered for real
// against a fake backend.
//
//   AFFILIATES-M2  No built-in rates: Rates stays off until the saved rates
//                  have loaded; a load error says so, with Retry, and turns
//                  Rates off again. Boxes hold text: a blank box is refused,
//                  0 shows as "0". Save is off while nothing changed, and asks
//                  to confirm old → new. The window opens on the rates saved
//                  now, and a save first checks they did not change.
//   AFFILIATES-6   The tab row and the buttons wrap; the first tab is
//                  "Balances".
//   AFFILIATES-7   A failed referrer list says so, with Retry, not "No
//                  referrers yet". A failed referrer says so, with Retry. A
//                  late answer for a referrer no longer open is dropped.
//   AFFILIATES-13  The downline is Tier 1 and Tier 2 only, said so.
//
// src/pages/CommissionsPage.tsx is bundled with esbuild and mounted in jsdom;
// only the Supabase client, the auth context and xlsx are stubbed. Every name
// and phone below is invented (ACMA fictional numbers).
//
// Run: node --test scripts/commissions/tests/commissions-page-425.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://commissions.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver', 'sessionStorage']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
dom.window.confirm = () => true;
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
      export { default as CommissionsPage } from './src/pages/CommissionsPage';
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
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onResolve({ filter: /^xlsx$/ }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.from(...a), rpc: (...a) => globalThis.__backend.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const utils = { json_to_sheet: () => ({}), book_new: () => ({}), book_append_sheet: () => {} }; export const writeFile = () => {};' }));
  } }],
});
const { CommissionsPage, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const SETTINGS = { commission_tier1_own_rate: 15, commission_tier1_third_rate: 4.5, commission_tier2_own_rate: 35, commission_tier2_third_rate: 0 };
const REFERRERS = [
  { customer_id: 'r-amy', full_name: 'Amy Test', phone: '+61491570006', direct_referrals: 1, total_downline: 2, lifetime_earned: 20, unpaid_earned: 20 },
  { customer_id: 'r-bob', full_name: 'Bob Test', phone: '+61491570156', direct_referrals: 1, total_downline: 1, lifetime_earned: 10, unpaid_earned: 10 },
];
const earnings = name => ({ lifetime: { tier1_earned: name === 'r-amy' ? 20 : 10, tier2_earned: 0, total_paid: 0, total_earned: name === 'r-amy' ? 20 : 10 }, monthly: [], by_buyer: [], lines: [] });
// An older server (before 425) still sends Tier 3.
const DOWNLINE = [
  { customer_id: 'd1', full_name: 'Cara Test', phone: '+61491570157', depth: 1, paid_purchases: 1, total_spend: 100 },
  { customer_id: 'd2', full_name: 'Dino Test', phone: '+61491570737', depth: 2, paid_purchases: 0, total_spend: 0 },
  { customer_id: 'd3', full_name: 'Eve Test', phone: '+61491571266', depth: 3, paid_purchases: 0, total_spend: 0 },
];

function createBackend() {
  const b = { calls: [], failures: new Map(), hold: new Map(), settings: { ...SETTINGS } };
  const answer = async (name, args, fn) => {
    b.calls.push({ name, args });
    await Promise.resolve();
    if (b.hold.has(name)) await b.hold.get(name)(args);
    if (b.failures.has(name)) { const f = b.failures.get(name); b.failures.delete(name); return { data: null, error: { message: f } }; }
    return { data: structuredClone(fn(args)), error: null };
  };
  const rpcs = {
    referrer_list: () => REFERRERS,
    referrer_earnings: a => earnings(a.p_customer_id),
    referrer_downline: () => DOWNLINE,
    set_commission_rates: () => null,
    affiliate_payout_overview: () => ({ groups: [], payouts: [], methods: [], balances: [], settlements: [] }),
    commission_referrer_names: () => [],
  };
  b.rpc = (name, args) => answer(name, args, a => (rpcs[name] ?? (() => null))(a));
  b.from = table => {
    const q = { select: () => q, eq: () => q,
      single: () => answer(`${table}.single`, null, () => b.settings),
      maybeSingle: () => answer(`${table}.maybe`, null, () => ({ instalment_commission_from: null })) };
    return q;
  };
  return b;
}

let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(role = 'owner', setup) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend();
  globalThis.__backend = backend;
  globalThis.__auth = { profile: { id: 'u-' + role, full_name: role, role, is_active: true } };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(CommissionsPage)));
  await tick();
}
const text = () => document.body.textContent;
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const button = (label, scope = document) => [...scope.querySelectorAll('button')].find(b => b.textContent.trim() === label);
async function setValue(el, value) {
  assert.ok(el, 'the field exists');
  await act(async () => {
    Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
  });
  await tick(2);
}
const modal = () => document.querySelector('.modal');
const callsOf = name => backend.calls.filter(c => c.name === name);
const absent = (el, msg) => assert.ok(el == null, msg);
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

test('AFFILIATES-M2: Rates stays off until the saved rates load; a load error says so and Retry loads them', async () => {
  let release;
  await mount('owner', b => { b.failures.set('app_settings.single', 'connection reset'); });
  assert.equal(button('Rates').disabled, true, 'no rates, no window');
  const banner = document.querySelector('[data-error="rates"]');
  assert.ok(banner && banner.textContent.includes('connection reset'));
  await click(button('Retry', banner));
  assert.equal(button('Rates').disabled, false);
  absent(document.querySelector('[data-error="rates"]'), 'the banner goes');
  // While the first load is still on its way, Rates is off too.
  await mount('owner', b => { b.hold.set('app_settings.single', () => new Promise(r => { release = r; })); });
  assert.equal(button('Rates').disabled, true);
  await act(async () => release()); await tick();
  assert.equal(button('Rates').disabled, false);
});

test('AFFILIATES-M2: 0 shows as "0", a blank box is refused, nothing changed means no Save', async () => {
  await mount('owner');
  await click(button('Rates'));
  const box = k => modal().querySelector(`input[name="${k}"]`);
  assert.deepEqual(['t1_own', 't1_third', 't2_own', 't2_third'].map(k => box(k).value), ['15', '4.5', '35', '0']);
  assert.equal(button('Save', modal()).disabled, true, 'nothing changed');
  assert.ok(modal().querySelector('[data-note="no-change"]'));
  await setValue(box('t2_own'), '');
  assert.ok(modal().querySelector('[data-rate-error="t2_own"]').textContent.includes('Enter a rate.'));
  assert.equal(button('Save', modal()).disabled, true, 'a blank box is not saved as 0');
  await setValue(box('t2_own'), '120');
  assert.ok(modal().querySelector('[data-rate-error="t2_own"]').textContent.includes('from 0 to 100'));
  assert.equal(callsOf('set_commission_rates').length, 0);
});

test('AFFILIATES-M2: Save shows old → new and saves only on Confirm', async () => {
  await mount('manager');
  await click(button('Rates'));
  await setValue(modal().querySelector('input[name="t1_own"]'), '12.5');
  await click(button('Save', modal()));
  const confirm = modal().querySelector('[data-confirm="rates"]');
  assert.ok(confirm && confirm.textContent.includes('Tier 1 — Own: 15% → 12.5%'), 'the change is listed');
  assert.ok(!confirm.textContent.includes('Tier 2'), 'only what changed');
  assert.equal(callsOf('set_commission_rates').length, 0, 'not saved yet');
  await click(button('Confirm and save', modal()));
  assert.deepEqual(callsOf('set_commission_rates').map(c => c.args),
    [{ p_tier1_own: 12.5, p_tier1_third: 4.5, p_tier2_own: 35, p_tier2_third: 0 }]);
  absent(modal(), 'closed once saved');
});

test('AFFILIATES-M2: a failed reload after a save turns Rates off; the next save keeps the rate saved before', async () => {
  await mount('owner', b => {
    // The server saves the rates, then the page's reload fails.
    b.hold.set('set_commission_rates', async a => {
      b.settings = { commission_tier1_own_rate: a.p_tier1_own, commission_tier1_third_rate: a.p_tier1_third,
        commission_tier2_own_rate: a.p_tier2_own, commission_tier2_third_rate: a.p_tier2_third };
      b.failures.set('app_settings.single', 'connection reset');
    });
  });
  await click(button('Rates'));
  await setValue(modal().querySelector('input[name="t2_own"]'), '30');
  await click(button('Save', modal()));
  await click(button('Confirm and save', modal()));
  absent(modal(), 'closed once saved');
  assert.ok(document.querySelector('[data-error="rates"]').textContent.includes('connection reset'));
  assert.equal(button('Rates').disabled, true, 'no window on rates that may be out of date');
  backend.hold.clear();
  await click(button('Retry', document.querySelector('[data-error="rates"]')));
  await click(button('Rates'));
  assert.equal(modal().querySelector('input[name="t2_own"]').value, '30', 'the window shows the rate saved');
  await setValue(modal().querySelector('input[name="t1_own"]'), '16');
  await click(button('Save', modal()));
  const confirm = modal().querySelector('[data-confirm="rates"]');
  assert.ok(confirm.textContent.includes('Tier 1 — Own: 15% → 16%') && !confirm.textContent.includes('Tier 2'));
  await click(button('Confirm and save', modal()));
  assert.deepEqual(callsOf('set_commission_rates').map(c => c.args).at(-1),
    { p_tier1_own: 16, p_tier1_third: 4.5, p_tier2_own: 30, p_tier2_third: 0 }, 'Tier 2 Own stays 30');
});

test('AFFILIATES-M2: the window opens on the rates saved now, not on what the page read earlier', async () => {
  await mount('manager');
  backend.settings = { ...SETTINGS, commission_tier2_own_rate: 25 };   // another Manager saved meanwhile
  await click(button('Rates'));
  assert.equal(modal().querySelector('input[name="t2_own"]').value, '25');
  await mount('manager');
  backend.failures.set('app_settings.single', 'connection reset');
  await click(button('Rates'));
  absent(modal(), 'a failed read does not open the window');
  assert.ok(document.querySelector('[data-error="rates"]').textContent.includes('connection reset'));
  assert.equal(button('Rates').disabled, true);
});

test('AFFILIATES-M2: rates changed while the window was open are not saved over', async () => {
  await mount('owner');
  await click(button('Rates'));
  await setValue(modal().querySelector('input[name="t1_own"]'), '16');
  backend.settings = { ...SETTINGS, commission_tier2_own_rate: 25 };   // another Owner saved meanwhile
  await click(button('Save', modal()));
  await click(button('Confirm and save', modal()));
  assert.equal(callsOf('set_commission_rates').length, 0, 'nothing saved');
  assert.ok(modal().textContent.includes('The rates changed since you opened this window.'));
  const box = k => modal().querySelector(`input[name="${k}"]`);
  assert.equal(box('t2_own').value, '25', 'a box left alone shows the new rate');
  assert.equal(box('t1_own').value, '16', 'a box changed keeps what was typed');
  await click(button('Save', modal()));
  const confirm = modal().querySelector('[data-confirm="rates"]');
  assert.ok(confirm.textContent.includes('Tier 1 — Own: 15% → 16%') && !confirm.textContent.includes('Tier 2'));
  await click(button('Confirm and save', modal()));
  assert.deepEqual(callsOf('set_commission_rates').map(c => c.args),
    [{ p_tier1_own: 16, p_tier1_third: 4.5, p_tier2_own: 25, p_tier2_third: 0 }]);
});

test('AFFILIATES-M2: Admins see no Rates button', async () => {
  await mount('admin');
  absent(button('Rates'), 'no Rates for an Admin');
});

test('AFFILIATES-6: the tabs and buttons wrap, and the first tab is "Balances"', async () => {
  await mount('owner');
  const tabs = button('Balances').parentElement;
  assert.equal(tabs.style.flexWrap, 'wrap');
  assert.equal(button('Rates').parentElement.style.flexWrap, 'wrap');
  absent(button('Balances (by affiliate / month)'), 'the long label is gone');
});

test('AFFILIATES-7: a failed referrer list says so, and Retry loads it', async () => {
  await mount('owner', b => b.failures.set('referrer_list', 'statement timeout'));
  await click(button('Referrers'));
  const box = document.querySelector('[data-error="referrers"]');
  assert.ok(box && box.textContent.includes('statement timeout'));
  assert.ok(!text().includes('No referrers yet'));
  await click(button('Retry', box));
  assert.ok(text().includes('Amy Test') && text().includes('Bob Test'));
});

test('AFFILIATES-7: a late answer for a referrer no longer open is dropped; a failed one says so with Retry', async () => {
  let releaseAmy;
  await mount('owner', b => {
    b.hold.set('referrer_earnings', a => a.p_customer_id === 'r-amy' ? new Promise(r => { releaseAmy = r; }) : Promise.resolve());
  });
  await click(button('Referrers'));
  const view = name => [...document.querySelectorAll('tr')].find(tr => tr.textContent.includes(name)).querySelector('button');
  await click(view('Amy Test'));
  await click(button('Close', modal().querySelector('.modal-footer') ?? modal()));
  await click(view('Bob Test'));
  assert.ok(modal().textContent.includes('Referrer — Bob Test'));
  await act(async () => releaseAmy()); await tick();
  assert.ok(modal().textContent.includes('Referrer — Bob Test'), 'still Bob');
  assert.ok(modal().textContent.includes('S$10.00') && !modal().textContent.includes('S$20.00'), 'Bob\'s figures, not Amy\'s');
  await click(button('Close', modal().querySelector('.modal-footer') ?? modal()));
  backend.hold.clear();
  backend.failures.set('referrer_downline', 'permission denied');
  await click(view('Amy Test'));
  const err = modal().querySelector('[data-error="referrer-detail"]');
  assert.ok(err && err.textContent.includes('permission denied'));
  assert.ok(!modal().textContent.includes('S$0.00'), 'no zeros in place of an error');
  await click(button('Retry', err));
  assert.ok(modal().textContent.includes('S$20.00'));
});

test('AFFILIATES-13: the downline is Tier 1 and Tier 2, said so', async () => {
  await mount('owner');
  await click(button('Referrers'));
  await click([...document.querySelectorAll('tr')].find(tr => tr.textContent.includes('Amy Test')).querySelector('button'));
  const m = modal().textContent;
  assert.ok(m.includes('Downline (2)'), 'two people listed');
  assert.ok(m.includes('Tier 1 and Tier 2, the levels that earn commission'));
  assert.ok(m.includes('Tier 1 · 1 paid') && m.includes('Tier 2 · 0 paid'));
  assert.ok(!m.includes('Eve Test') && !m.includes('Tier 3'), 'no Tier 3');
});
