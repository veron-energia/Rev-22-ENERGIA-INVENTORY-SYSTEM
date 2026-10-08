// The screens of 398 (and 404's promotion wording), rendered for real against a fake backend.
//
// src/pages/CustomersPage.tsx, src/pages/AffiliatesPage.tsx (with
// ReferralPromotionPanel and DownlineModal) and src/pages/AffiliateNetworkPage.tsx
// are bundled with esbuild and mounted in jsdom. Only the Supabase client, the
// auth context and the QR library are stubbed: the client by a small in-memory
// backend that records every call. Every name, phone and number is invented.
//
// It checks the Owner's rules of 6 Oct 2026 as the screens carry them: the
// Customers page sends Visited and the first visit range to search_customers
// (the list and the export) and shows the first visit; with no visit filter it
// sends the four arguments it always did; the Downline (Tier 1 and Tier 2 with
// joined, visited and first visit) is Owner/Manager only, on the Customers
// page and the Affiliates page; the Affiliates page's Referral promotion tab
// (Owner/Manager) shows friends counted, tier reached, next tier and each
// friend, says "provisional" and offers no reward until the promotion has
// ended; 404 (the Owner, 8 Oct 2026): a friend counts by their first visit,
// whenever referred, and the friends referred in the window who have not
// visited yet are shown, not counted ("Not yet visited"; after the
// promotion, "No visit during the promotion"), from the report's
// not_yet_visited or, before 404, from the friends listed without a visit;
// then a reward is marked with a store and products the store holds,
// sending exactly those to give_referral_campaign_reward; the Owner alone
// undoes one, with a reason, putting stock back or not; the affiliate portal
// shows the affiliate's own count and next tier, and nothing when the
// database does not have it yet. 404's further rules (the Owner, 8 Oct
// 2026): the tab states that past customers are neither counted nor listed
// and that a QR-link form is dated the day it was sent (the friend table's
// "First visit (promotion)"); the portal says how many friends referred
// during the promotion have not visited yet, a count only, hidden at 0,
// without the figure and after the promotion ends.
//
// Run: node --test scripts/referrals/tests/promotion-pages.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://promotion.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
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
      export { default as AffiliatesPage } from './src/pages/AffiliatesPage';
      export { default as CustomersPage } from './src/pages/CustomersPage';
      export { default as AffiliateNetworkPage } from './src/pages/AffiliateNetworkPage';
      export { MemoryRouter } from 'react-router-dom';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      export { React };
      export class ErrorBoundary extends React.Component {
        constructor(p) { super(p); this.state = { error: null }; }
        static getDerivedStateFromError(error) { return { error }; }
        componentDidCatch(error) { globalThis.__renderErrors.push(String(error && error.stack || error)); }
        render() { return this.state.error ? React.createElement('div', { id: 'crashed' }, String(this.state.error.message)) : this.props.children; }
      }`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    // src/lib's own modules (affiliatePortal, used by My Network) import it as './supabase'.
    b.onResolve({ filter: /^\.\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onResolve({ filter: /^qrcode$/ }, () => ({ path: 'qrcode', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^qrcode$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export default { toCanvas: async () => {} };' }));
  } }],
});
const { AffiliatesPage, CustomersPage, AffiliateNetworkPage, MemoryRouter, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const CAMPAIGN = { code: '2026-10', title: 'October referral promotion', reward_reason: 'October referral reward',
  starts_on: '2026-10-01', ends_on: '2026-10-31', tiers: [10, 20, 50, 80], today: '2026-10-06', status: 'provisional' };
const friend = (id, name, counted, visit, referred = '2026-10-03') => ({ customer_id: id, name, phone: '+659139' + id.slice(-4).padStart(4, '0'),
  referred_on: referred, first_visit_on: visit, counted });
function makeFixture() {
  // Fay: Jo Yee was referred in August and first visited in October (404: she counts).
  const fay = { referrer_customer_id: 'c-fay', name: 'Fay Lum', phone: '+6591390050', is_affiliate: true,
    counted: 12, not_yet_visited: 2, referred_in_window: 13, tier_reached: 10, next_tier: 20, to_next: 8, reward: null,
    friends: [friend('f-0001', 'Gia Lo', true, '2026-10-05'), friend('f-0003', 'Jo Yee', true, '2026-10-09', '2026-08-14'),
              friend('f-0002', 'Ian Su', false, null), friend('f-0005', 'Kai Ho', false, null, '2026-10-20')] };
  const gia = { referrer_customer_id: 'c-gia', name: 'Gia Lo', phone: '+6591390051', is_affiliate: false,
    counted: 1, not_yet_visited: 0, referred_in_window: 1, tier_reached: null, next_tier: 10, to_next: 9, reward: null,
    friends: [friend('f-0004', 'Oli Ting', true, '2026-10-12')] };
  const bob = { referrer_customer_id: 'c-bob', name: 'Bob Lim', phone: '+6591390070', is_affiliate: true,
    counted: 21, not_yet_visited: 0, referred_in_window: 21, tier_reached: 20, next_tier: 50, to_next: 29,
    reward: { reward_id: 'rw-1', tier: 20, friends_counted: 21, given_at: '2026-10-31T23:30:00+00:00', given_by_name: 'Owner One',
      store_id: 's-1', store_name: 'Fixture Store', note: null,
      items: [{ product_id: 'p-gift', product_name: 'Gift Set', quantity: 2, use_no: 'SU-2026-9001' }] },
    friends: [] };
  return {
    report: { campaign: { ...CAMPAIGN }, campaigns: [{ code: '2026-10', title: CAMPAIGN.title, starts_on: '2026-10-01', ends_on: '2026-10-31' }],
              referrers: [bob, fay, gia] },
    directory: [{ customer_id: 'c-fay', name: 'Fay Lum', status: 'active', manually_suspended: false, referral_code: 'T398FAY',
      portal_account: 'claimed', direct_referrals: 14, tier2: 1, lifetime: 0, unpaid: 0, blocked: 0, last_commission: null }],
    downline: { customer_id: 'c-fay', name: 'Fay Lum',
      tier1: [{ customer_id: 'f-0001', name: 'Gia Lo', phone: '+6591390051', joined_on: '2026-10-03', joined_from_created: false, visited: true, first_visit_on: '2026-10-05' },
              { customer_id: 'f-0009', name: 'Cal Ee', phone: '+6591390042', joined_on: '2026-08-04', joined_from_created: true, visited: false, first_visit_on: null }],
      tier2: [{ customer_id: 'f-0004', name: 'Oli Ting', phone: '+6591390059', parent_id: 'f-0001', parent_name: 'Gia Lo',
                joined_on: '2026-10-11', joined_from_created: false, visited: true, first_visit_on: '2026-10-12' }] },
    customers: [
      { id: 'c-fay', full_name: 'Fay Lum', first_name: 'Fay', last_name: 'Lum', phone: '+6591390050', email: null, notes: null, is_active: true,
        created_at: '2026-09-01T00:00:00Z', referred_by: null, is_referrer: true, source_label: null, first_visit_on: '2026-09-02', total_count: 2 },
      { id: 'c-cal', full_name: 'Cal Ee', first_name: 'Cal', last_name: 'Ee', phone: '+6591390042', email: null, notes: null, is_active: true,
        created_at: '2026-08-04T00:00:00Z', referred_by: 'c-fay', is_referrer: true, source_label: null, first_visit_on: null, total_count: 2 },
    ],
    stores: [{ id: 's-1', name: 'Fixture Store', deleted_at: null, is_active: true }, { id: 's-2', name: 'Fixture Store B', deleted_at: null, is_active: true }],
    products: [{ id: 'p-gift', name: 'Gift Set', sku: 'T-GIFT', deleted_at: null }, { id: 'p-bottle', name: 'Water Bottle', sku: 'T-BOT', deleted_at: null },
               { id: 'p-none', name: 'Out Of Stock Thing', sku: 'T-NONE', deleted_at: null }],
    store_inventory: [{ id: 'si-1', store_id: 's-1', product_id: 'p-gift', current_qty: 5 }, { id: 'si-2', store_id: 's-1', product_id: 'p-bottle', current_qty: 1 },
                      { id: 'si-3', store_id: 's-1', product_id: 'p-none', current_qty: 0 }],
    progress: { campaign: { code: '2026-10', title: CAMPAIGN.title, starts_on: '2026-10-01', ends_on: '2026-10-31', tiers: [10, 20, 50, 80], status: 'provisional' },
                counted: 3, not_yet_visited: 2, referred_in_window: 4, tier_reached: null, next_tier: 10, to_next: 7, reward_tier: null, reward_given_at: null },
  };
}

function createBackend(fx) {
  const b = { calls: [], handlers: {}, failures: new Map(), fx };
  const rpcs = {
    affiliate_admin_directory: () => fx.directory,
    affiliate_staff_directory: () => ({ total: 1, rows: [{ customer_id: 'c-fay', full_name: 'Fay Lum', referral_code: 'T398FAY', status: 'active', link_usable: true }] }),
    affiliate_pending_claims: () => [],
    affiliate_rejected_claims: () => [],
    referral_campaign_report: () => fx.report,
    give_referral_campaign_reward: a => ({ success: true, reward_id: 'rw-2', tier: 10, store_name: 'Fixture Store',
      items: a.p_items.map((i, k) => ({ ...i, use_no: `SU-2026-910${k}` })) }),
    void_referral_campaign_reward: () => ({ success: true }),
    customer_downline_visits: () => fx.downline,
    search_customers: () => fx.customers,
    active_customer_source_options: () => [],
    customer_profile_stats: () => ({ purchases: 0, total_spend: 0, referred_count: 1, referrer_name: null }),
    customer_purchase_timeline: () => [],
    affiliate_portal_network: () => ({ tier1: [], tier2: [] }),
    affiliate_portal_campaign_progress: () => fx.progress,
  };
  const tables = { stores: fx.stores, products: fx.products, store_inventory: fx.store_inventory, customer_phone_history: [], customers: fx.customers };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], single: false, from: null, to: null }); }
    select() { return this; }
    eq(c, v) { this.filters.push(r => r[c] === v); return this; }
    is(c, v) { this.filters.push(r => (r[c] ?? null) === v); return this; }
    gt(c, v) { this.filters.push(r => Number(r[c]) > v); return this; }
    in(c, vs) { this.filters.push(r => vs.includes(r[c])); return this; }
    or() { return this; }
    ilike() { return this; }
    order() { return this; }
    limit() { return this; }
    range(a, z) { this.from = a; this.to = z; return this; }
    maybeSingle() { this.single = true; return this; }
    single() { this.single = true; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args, filters: this.filters.length });
      await Promise.resolve();
      if (b.failures.has(this.name)) {
        const f = b.failures.get(this.name);
        return { data: null, error: typeof f === 'string' ? { message: f } : f };
      }
      if (this.kind === 'rpc') {
        const fn = b.handlers[this.name] ?? rpcs[this.name];
        if (!fn) return { data: null, error: { message: `unknown rpc ${this.name}` } };
        return { data: structuredClone(fn(this.args)), error: null };
      }
      let rows = (tables[this.name] ?? []).filter(r => this.filters.every(f => f(r)));
      if (this.from != null) rows = rows.slice(this.from, this.to + 1);
      return { data: structuredClone(this.single ? rows[0] ?? null : rows), error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

// ── driving the pages ──────────────────────────────────────────────────────
const USERS = {
  owner: { id: 'u-own', full_name: 'Owner One', role: 'owner', is_active: true },
  manager: { id: 'u-mgr', full_name: 'Manager One', role: 'manager', is_active: true },
  staff: { id: 'u-staff', full_name: 'Staff One', role: 'staff', is_active: true },
};
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(Page, role, setup) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(makeFixture());
  globalThis.__backend = backend; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: USERS[role], signOut: async () => {} };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null,
    React.createElement(MemoryRouter, null, React.createElement(Page)))));
  await tick();
  await act(async () => { await new Promise(r => setTimeout(r, 320)); });
  await tick();
}
const text = () => document.body.textContent;
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const buttons = (scope = document) => [...scope.querySelectorAll('button')];
const button = (label, scope = document) => buttons(scope).find(b => b.textContent.trim() === label);
async function setValue(el, value) {
  assert.ok(el, 'the field exists');
  const proto = el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype
    : el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
  });
  await tick(4);
}
const modal = () => [...document.querySelectorAll('.modal')].pop();
const row = name => [...document.querySelectorAll('tr')].find(tr => tr.querySelector('strong')?.textContent === name);
const callsOf = name => backend.calls.filter(c => c.name === name);
const absent = (el, msg) => assert.ok(el == null, msg);
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── the Customers page ─────────────────────────────────────────────────────
test('the Customers page lists the first visit and, with no visit filter, calls search_customers as it always did', async () => {
  await mount(CustomersPage, 'manager');
  assert.deepEqual(globalThis.__renderErrors, []);
  const first = callsOf('search_customers')[0];
  assert.deepEqual(Object.keys(first.args).sort(), ['p_limit', 'p_offset', 'p_query', 'p_source']);
  assert.ok([...document.querySelectorAll('th')].some(th => th.textContent === 'First visit'));
  assert.ok(row('Fay Lum').textContent.includes('02/09/2026'), 'the first visit, as a Singapore date');
  assert.ok(row('Cal Ee').textContent.includes('—'), 'no visit');
});

test('Visited and the first-visit range reach search_customers; Not visited drops the dates', async () => {
  await mount(CustomersPage, 'manager');
  const sel = document.querySelector('select[aria-label="Visited"]');
  await setValue(sel, 'visited');
  await setValue(document.querySelector('input[aria-label="First visit from"]'), '2026-10-01');
  await setValue(document.querySelector('input[aria-label="First visit to"]'), '2026-10-31');
  const last = callsOf('search_customers').pop();
  assert.equal(last.args.p_visited, 'visited');
  assert.equal(last.args.p_visit_from, '2026-10-01');
  assert.equal(last.args.p_visit_to, '2026-10-31');
  assert.equal(last.args.p_offset, 0);
  await setValue(sel, 'not_visited');
  const nv = callsOf('search_customers').pop();
  assert.equal(nv.args.p_visited, 'not_visited');
  assert.ok(!('p_visit_from' in nv.args) && !('p_visit_to' in nv.args), 'Not visited has no first visit to filter on');
  assert.ok(document.querySelector('input[aria-label="First visit from"]').disabled);
  await click(button('Clear visit filters'));
  assert.deepEqual(Object.keys(callsOf('search_customers').pop().args).sort(), ['p_limit', 'p_offset', 'p_query', 'p_source']);
});

test('the Customers page\'s Downline is Owner/Manager: Tier 1 and Tier 2 with joined, visited and first visit', async () => {
  await mount(CustomersPage, 'manager');
  await click(document.querySelector('button[aria-label="Downline of Fay Lum"]'));
  assert.deepEqual(callsOf('customer_downline_visits').map(c => c.args), [{ p_customer_id: 'c-fay' }]);
  const m = modal();
  assert.ok(m.textContent.includes('Downline — Fay Lum'));
  assert.ok(m.textContent.includes('Tier 1 — referred by Fay Lum (2, 1 visited)'), m.textContent.slice(0, 400));
  assert.ok(m.textContent.includes('Tier 2 — referred by their Tier 1 (1, 1 visited)'));
  const cal = [...m.querySelectorAll('tr')].find(tr => tr.textContent.includes('Cal Ee'));
  assert.ok(cal.textContent.includes('04/08/2026') && cal.textContent.includes('(created)') && cal.textContent.includes('No'), cal.textContent);
  const oli = [...m.querySelectorAll('tr')].find(tr => tr.textContent.includes('Oli Ting'));
  assert.ok(oli.textContent.includes('Gia Lo') && oli.textContent.includes('Yes') && oli.textContent.includes('12/10/2026'));

  await mount(CustomersPage, 'staff');
  absent(document.querySelector('button[aria-label^="Downline of"]'), 'staff get no Downline');
});

// ── the Affiliates page ────────────────────────────────────────────────────
test('the Referral promotion tab: counts, tiers, friends, and provisional until the promotion ends', async () => {
  await mount(AffiliatesPage, 'manager');
  assert.equal(callsOf('referral_campaign_report').length, 0, 'not read until the tab is opened');
  await click(buttons().find(b => b.textContent.trim() === 'Referral promotion'));
  assert.deepEqual(globalThis.__renderErrors, []);
  assert.deepEqual(callsOf('referral_campaign_report').map(c => c.args), [{ p_campaign: null }]);
  assert.ok(document.querySelector('[data-status="provisional"]'), 'says provisional');
  assert.ok(text().includes('Provisional: the promotion runs 1 Oct – 31 Oct 2026'));
  // 404: the rule is the first visit, whenever the friend was referred.
  assert.ok(text().includes('A Tier 1 friend counts when their first visit to the centre is in the promotion, whenever they were referred'), 'the rule');
  assert.ok(!text().includes('first visited the centre in the same window'), 'not the 398 rule');
  // 404 (the Owner's further rules): past customers, and a form dated the day it was sent.
  assert.ok(text().includes('A past customer (a paid or part-paid invoice dated before the promotion started) is neither counted nor listed'), 'past customers');
  assert.ok(text().includes("counts on the day the form was sent, not the date written on it, so a friend's first visit here can differ from the Customers page"), 'the day sent');
  const fay = row('Fay Lum');
  assert.ok(fay.textContent.includes('12') && fay.textContent.includes('20 (8 more)'), fay.textContent);
  assert.ok(fay.textContent.includes('2 friends referred in the window have not visited yet'), fay.textContent);
  assert.ok(!/\b13 (friends )?referred/.test(fay.textContent), 'referred_in_window is not shown');
  // Gia counts only a friend who has visited: no "0 referred in the window" line under her name.
  assert.ok(!row('Gia Lo').textContent.includes('referred in the window'), row('Gia Lo').textContent);
  const mark = button('Mark reward given', fay);
  assert.ok(mark && mark.disabled, 'no reward before the promotion ends');
  assert.ok(row('Bob Lim').textContent.includes('Given · tier 20') && row('Bob Lim').textContent.includes('SU-2026-9001'));
  // Given at 07:30 on 1 Nov in Singapore (23:30 on 31 Oct in UTC): shown as the Singapore day.
  assert.ok(row('Bob Lim').textContent.includes('01/11/2026') && !row('Bob Lim').textContent.includes('31/10/2026'), row('Bob Lim').textContent);
  absent(button('Undo', row('Bob Lim')), 'a Manager cannot undo');
  // The drill-down: a friend referred in August counts (her referral date shown); two not yet visited.
  await click(fay.querySelector('button[aria-label="Friends of Fay Lum"]'));
  assert.ok([...document.querySelectorAll('th')].some(th => th.textContent === 'First visit (promotion)'), 'the promotion\'s first visit');
  const jo = [...document.querySelectorAll('tr')].find(tr => tr.firstElementChild?.textContent === 'Jo Yee');
  assert.ok(jo && jo.textContent.includes('14/08/2026') && jo.textContent.includes('09/10/2026') && jo.textContent.includes('Yes'), jo?.textContent);
  const waiting = [...document.querySelectorAll('tr')].filter(tr => tr.lastElementChild?.textContent === 'Not yet visited');
  assert.deepEqual(waiting.map(tr => tr.firstElementChild.textContent), ['Ian Su', 'Kai Ho']);
  assert.ok(waiting.every(tr => tr.textContent.includes('Not yet')), 'no first visit');
  assert.ok(!text().includes('Visit outside the window') && !text().includes('No visit yet'));
  // A referrer below the first tier has nothing to mark.
  absent(button('Mark reward given', row('Gia Lo')), 'nothing to give below the first tier');
});

test('after the promotion ends, the friends who did not visit say so', async () => {
  await mount(AffiliatesPage, 'manager', b => { b.fx.report.campaign.status = 'final'; });
  await click(buttons().find(b => b.textContent.trim() === 'Referral promotion'));
  assert.ok(row('Fay Lum').textContent.includes('2 friends referred in the window did not visit during it or since'), row('Fay Lum').textContent);
  await click(row('Fay Lum').querySelector('button[aria-label="Friends of Fay Lum"]'));
  const none = [...document.querySelectorAll('tr')].filter(tr => tr.lastElementChild?.textContent === 'No visit during the promotion');
  assert.deepEqual(none.map(tr => tr.firstElementChild.textContent), ['Ian Su', 'Kai Ho']);
  assert.ok(!text().includes('Not yet visited'));
});

test('against a database before 404 the page counts the friends without a visit itself', async () => {
  await mount(AffiliatesPage, 'manager', b => {
    for (const r of b.fx.report.referrers) delete r.not_yet_visited;
    // 398 also listed a friend referred in the window whose first visit fell outside it.
    b.fx.report.referrers[1].friends.push(friend('f-0006', 'Lim Bo', false, '2026-09-20', '2026-10-04'));
  });
  await click(buttons().find(b => b.textContent.trim() === 'Referral promotion'));
  assert.deepEqual(globalThis.__renderErrors, []);
  assert.ok(row('Fay Lum').textContent.includes('2 friends referred in the window have not visited yet'), row('Fay Lum').textContent);
  assert.ok(!row('Gia Lo').textContent.includes('referred in the window'), row('Gia Lo').textContent);
  await click(row('Fay Lum').querySelector('button[aria-label="Friends of Fay Lum"]'));
  assert.ok(text().includes('Visit outside the window'));
});

test('with nobody listed, the report says so', async () => {
  await mount(AffiliatesPage, 'manager', b => { b.fx.report.referrers = []; });
  await click(buttons().find(b => b.textContent.trim() === 'Referral promotion'));
  assert.ok(text().includes('No friend counts in this promotion yet, and no friend referred during it is waiting for a first visit'));
});

test('with "Only referrers with a friend counted" hiding everyone, the table does not say nobody is waiting', async () => {
  // Only Ned is listed: two friends referred in October, neither visited yet.
  await mount(AffiliatesPage, 'manager', b => {
    b.fx.report.referrers = [{ referrer_customer_id: 'c-ned', name: 'Ned Bo', phone: '+6591390058', is_affiliate: false,
      counted: 0, not_yet_visited: 2, referred_in_window: 2, tier_reached: null, next_tier: 10, to_next: 10, reward: null,
      friends: [friend('f-0007', 'Max Ow', false, null), friend('f-0008', 'Lou Ang', false, null)] }];
  });
  await click(buttons().find(b => b.textContent.trim() === 'Referral promotion'));
  assert.ok(row('Ned Bo').textContent.includes('2 friends referred in the window have not visited yet'), row('Ned Bo').textContent);
  const filter = [...document.querySelectorAll('label')].find(l => l.textContent.includes('Only referrers with a friend counted'))?.querySelector('input');
  await click(filter);
  assert.ok(filter.checked, 'the filter is ticked');
  absent(row('Ned Bo'), 'Ned is hidden by the filter');
  assert.ok(text().includes('No referrer has a friend counted in this promotion yet.'), text());
  assert.ok(!text().includes('no friend referred during it is waiting for a first visit'), 'not the untrue line');
  await click(filter);
  assert.ok(row('Ned Bo'), 'unticked, Ned is back');
});

test('after the promotion ends, a reward is marked with a store and products it holds, exactly as chosen', async () => {
  await mount(AffiliatesPage, 'manager', b => { b.fx.report.campaign.status = 'final'; });
  await click(buttons().find(b => b.textContent.trim() === 'Referral promotion'));
  assert.ok(document.querySelector('[data-status="final"]'));
  await click(button('Mark reward given', row('Fay Lum')));
  const m = modal();
  assert.ok(m.textContent.includes('reached tier 10') && m.textContent.includes('October referral reward — Fay Lum'), m.textContent.slice(0, 500));
  await setValue(m.querySelector('select'), 's-1');
  // The picker offers what the store holds, with the stock.
  const pick = buttons(m).find(x => x.textContent.includes('Search a product this store holds'));
  await click(pick);
  const opts = [...m.querySelectorAll('div')].filter(d => d.children.length === 2 && d.firstElementChild.children.length === 0
    && /· \d+ in stock$/.test(d.lastElementChild?.textContent ?? ''));
  assert.deepEqual(opts.map(o => o.firstElementChild.textContent), ['Gift Set', 'Water Bottle'], 'only products in stock at the store');
  await click(opts[0]);
  await setValue(m.querySelector('input[aria-label="Quantity"]'), '6');
  await click(button('Record reward and take stock out', m));
  assert.ok(modal().textContent.includes('Only 5 of "Gift Set" in stock at this store.'));
  assert.equal(callsOf('give_referral_campaign_reward').length, 0, 'nothing sent beyond the stock');
  await setValue(m.querySelector('input[aria-label="Quantity"]'), '2');
  await setValue([...m.querySelectorAll('input')].find(i => i.placeholder?.startsWith('Optional')), 'At the counter');
  await click(button('Record reward and take stock out', m));
  assert.deepEqual(callsOf('give_referral_campaign_reward').map(c => c.args), [{
    p_campaign: '2026-10', p_referrer_customer_id: 'c-fay', p_store_id: 's-1',
    p_items: [{ product_id: 'p-gift', quantity: 2 }], p_note: 'At the counter' }]);
  assert.ok(text().includes('Reward recorded for Fay Lum (tier 10). Taken out of Fixture Store\'s stock: SU-2026-9100.'));
  assert.equal(callsOf('referral_campaign_report').length, 2, 'the report is read again');
});

test('the Owner alone undoes a reward, with a reason, putting the stock back or not', async () => {
  await mount(AffiliatesPage, 'owner', b => { b.fx.report.campaign.status = 'final'; });
  await click(buttons().find(b => b.textContent.trim() === 'Referral promotion'));
  await click(button('Undo', row('Bob Lim')));
  const m = modal();
  assert.ok(m.textContent.includes('2 × Gift Set back into Fixture Store'));
  assert.ok(button('Undo reward', m).disabled, 'a reason is required');
  await setValue(m.querySelector('textarea'), 'Wrong products');
  const tickBox = m.querySelector('input[type="checkbox"]');
  await click(tickBox);
  await click(button('Undo reward', m));
  assert.deepEqual(callsOf('void_referral_campaign_reward').map(c => c.args),
    [{ p_reward_id: 'rw-1', p_reason: 'Wrong products', p_return_stock: false }]);
});

test('the Affiliates page\'s Downline is on each affiliate for an Owner or Manager; staff see neither it nor the promotion', async () => {
  await mount(AffiliatesPage, 'manager');
  await click(document.querySelector('button[aria-label="Downline of Fay Lum"]'));
  assert.deepEqual(callsOf('customer_downline_visits').map(c => c.args), [{ p_customer_id: 'c-fay' }]);
  assert.ok(modal().textContent.includes('Tier 1 — referred by Fay Lum'));
  await mount(AffiliatesPage, 'staff');
  absent(buttons().find(b => b.textContent.trim() === 'Referral promotion'), 'no promotion tab for staff');
  absent(document.querySelector('button[aria-label^="Downline of"]'), 'no Downline for staff');
  assert.equal(callsOf('referral_campaign_report').length + callsOf('customer_downline_visits').length, 0);
});

// ── the affiliate portal ───────────────────────────────────────────────────
test('the portal shows the affiliate\'s own count and next tier, and nothing when the database does not have it yet', async () => {
  await mount(AffiliateNetworkPage, 'staff');
  assert.deepEqual(globalThis.__renderErrors, []);
  const card = document.querySelector('[data-promotion="2026-10"]');
  assert.ok(card, 'the progress card');
  assert.ok(card.textContent.includes('3 friends counted — 7 more to reach 10.'), card.textContent);
  assert.ok(card.textContent.includes('1 Oct – 31 Oct 2026 · so far'));
  // 404: the rule is the first visit, whenever the affiliate referred them; past customers never; no names.
  assert.ok(card.textContent.includes('A friend counts when their first visit to the centre is during the promotion, whenever you referred them, as long as you referred them by its last day. Friends who were already paying customers before it started do not count. Rewards are given after it ends'), card.textContent);
  // 404: how many friends referred during the promotion have not visited yet, a count only.
  const waiting = card.querySelector('[data-not-yet-visited]');
  assert.ok(waiting, 'the not-yet-visited line');
  assert.equal(waiting.textContent, "2 friends you referred during the promotion haven't visited yet.");
  assert.deepEqual(callsOf('affiliate_portal_campaign_progress').map(c => c.args), [undefined], 'it sends no id: the database knows who is asking');
  await mount(AffiliateNetworkPage, 'staff', b => b.failures.set('affiliate_portal_campaign_progress',
    { code: 'PGRST202', message: 'Could not find the function public.affiliate_portal_campaign_progress' }));
  absent(document.querySelector('[data-promotion]'), 'no card');
  assert.ok(!text().includes('Could not find'), 'and no error');
});

test('404: the portal\'s not-yet-visited line: singular, hidden at 0, absent without the figure', async () => {
  await mount(AffiliateNetworkPage, 'staff', b => { b.fx.progress.not_yet_visited = 1; });
  let card = document.querySelector('[data-promotion="2026-10"]');
  assert.equal(card.querySelector('[data-not-yet-visited]')?.textContent, "1 friend you referred during the promotion hasn't visited yet.");
  await mount(AffiliateNetworkPage, 'staff', b => { b.fx.progress.not_yet_visited = 0; });
  card = document.querySelector('[data-promotion="2026-10"]');
  absent(card.querySelector('[data-not-yet-visited]'), 'hidden at 0');
  assert.ok(!card.textContent.includes('visited yet'), card.textContent);
  // A database before 404 sends no figure.
  await mount(AffiliateNetworkPage, 'staff', b => { delete b.fx.progress.not_yet_visited; });
  assert.deepEqual(globalThis.__renderErrors, []);
  card = document.querySelector('[data-promotion="2026-10"]');
  assert.ok(card && card.textContent.includes('3 friends counted'), 'the card still shows');
  absent(card.querySelector('[data-not-yet-visited]'), 'no line without the figure');
});

test('after the promotion, the portal gives the reward\'s day in Singapore', async () => {
  await mount(AffiliateNetworkPage, 'staff', b => {
    Object.assign(b.fx.progress, { counted: 12, tier_reached: 10, next_tier: 20, to_next: 8, reward_tier: 10,
                                   reward_given_at: '2026-10-31T23:30:00+00:00' });
    b.fx.progress.campaign.status = 'final';
  });
  const card = document.querySelector('[data-promotion="2026-10"]');
  assert.ok(card && card.textContent.includes('Your tier 10 reward was given on 01/11/2026.'), card?.textContent);
  // 404: after the end the not-yet-visited line is not shown (the fixture still sends 2).
  absent(card.querySelector('[data-not-yet-visited]'), 'no not-yet-visited line after the promotion');
  assert.ok(!card.textContent.includes("haven't visited yet"), card.textContent);
});
