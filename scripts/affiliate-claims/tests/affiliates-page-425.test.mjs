// The Affiliates page after the audit's section 6 (B11, 425), rendered for
// real against a fake backend.
//
//   AFFILIATES-7   An Owner or Manager whose claim lists fail to load is told
//                  so, rather than seeing no claims.
//   AFFILIATES-8   Suspend asks for its reason in a window, refuses a blank
//                  one and sends the reason typed (no "Suspended" stand-in).
//                  Correct Referrer shows who refers the affiliate now and
//                  since when; removing them needs a tick; Save stays off
//                  while nothing changes.
//   AFFILIATES-10  Staff's directory: one request after the typing stops,
//                  none per key; a new search starts at page 1; Next asks for
//                  the next page once.
//   AFFILIATES-12  "Check these sign-ups" (Q19 = A): the sign-ups that share
//                  a customer's phone, with who had it; Different person and
//                  Same person need a note and send the answer; an answer
//                  someone else gave first is said in the window. Before 425
//                  is on the server there is no list and no error.
//
// src/pages/AffiliatesPage.tsx is bundled with esbuild and mounted in jsdom;
// only the Supabase client, the auth context and the QR library are stubbed.
// Every name, phone and email below is invented (ACMA fictional numbers).
//
// Run: node --test scripts/affiliate-claims/tests/affiliates-page-425.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://affiliates.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
let prompted = 0;
dom.window.confirm = () => true;
dom.window.prompt = () => { prompted++; return 'from a prompt'; };
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
    b.onResolve({ filter: /^qrcode$/ }, () => ({ path: 'qrcode', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^qrcode$/, namespace: 'stub' }, () => ({ loader: 'js', contents: 'export default { toCanvas: async () => {} };' }));
  } }],
});
const { AffiliatesPage, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const MISSING = { code: 'PGRST202', message: 'Could not find the function public.referral_signup_checks_pending without parameters in the schema cache' };
function makeFixture() {
  return {
    customers: [
      { id: 'c-ria', full_name: 'Ria Test', phone: '+61491570006', referred_by: 'c-ken', referred_at: '2026-08-14T02:00:00Z', created_at: '2026-08-01T02:00:00Z', deleted_at: null },
      { id: 'c-ken', full_name: 'Ken Test', phone: '+61491570156', referred_by: null, referred_at: null, created_at: '2026-07-01T02:00:00Z', deleted_at: null },
    ],
    directory: [
      { customer_id: 'c-ria', name: 'Ria Test', status: 'active', manually_suspended: false, referral_code: 'T425RIA',
        portal_account: 'claimed', direct_referrals: 1, tier2: 0, lifetime: 10, unpaid: 10, blocked: 0, last_commission: null },
      { customer_id: 'c-ken', name: 'Ken Test', status: 'active', manually_suspended: false, referral_code: 'T425KEN',
        portal_account: 'not_claimed', direct_referrals: 1, tier2: 0, lifetime: 0, unpaid: 0, blocked: 0, last_commission: null },
    ],
    checks: [
      { check_id: 'chk-mae', customer_id: 'c-mae', customer_name: 'Mae Test', phone: '+61491570157', customer_deleted: false,
        referrer_customer_id: 'c-ria', referrer_name: 'Ria Test', referral_code: 'T425RIA', signed_up_at: '2026-10-15T03:00:00Z',
        shares_with: [{ customer_id: 'c-ann', name: 'Ann Test', deleted: false, paid_invoices: 2 }] },
    ],
  };
}
function createBackend(fx) {
  const b = { calls: [], handlers: {}, failures: new Map(), fx };
  const rpcs = {
    affiliate_admin_directory: () => fx.directory,
    affiliate_staff_directory: a => ({ total: 120, rows: [{ customer_id: 'c-ria', full_name: 'Ria Test', referral_code: 'T425RIA', status: 'active', link_usable: true }], limit: a.p_limit, offset: a.p_offset }),
    affiliate_pending_claims: () => [],
    affiliate_rejected_claims: () => [],
    referral_signup_checks_pending: () => fx.checks,
    decide_referral_signup_check: () => ({ ok: true }),
    suspend_affiliate: () => null,
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], single: false }); }
    select() { return this; }
    eq(c, v) { this.filters.push(r => r[c] === v); return this; }
    is() { return this; } in() { return this; } or() { return this; } order() { return this; } limit() { return this; }
    maybeSingle() { this.single = true; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args });
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
      const rows = (this.name === 'customers' ? fx.customers : []).filter(r => this.filters.every(f => f(r)));
      return { data: structuredClone(this.single ? rows[0] ?? null : rows), error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

const USERS = {
  owner: { id: 'u-own', full_name: 'Owner One', role: 'owner', is_active: true },
  manager: { id: 'u-mgr', full_name: 'Manager One', role: 'manager', is_active: true },
  staff: { id: 'u-staff', full_name: 'Staff One', role: 'staff', is_active: true },
};
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
const wait = async ms => { await act(async () => { await new Promise(r => setTimeout(r, ms)); }); await tick(); };
async function mount(role, setup) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(makeFixture());
  globalThis.__backend = backend;
  globalThis.__auth = { profile: USERS[role] };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(AffiliatesPage)));
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
  const proto = el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
  });
  await tick(2);
}
async function tickBox(el, on) {
  assert.ok(el, 'the tick box exists');
  if (el.checked !== on) await click(el);
}
const modal = () => document.querySelector('.modal');
const callsOf = name => backend.calls.filter(c => c.name === name);
const absent = (el, msg) => assert.ok(el == null, msg);
const row = name => [...document.querySelectorAll('tr')].find(tr => tr.textContent.includes(name) && tr.querySelector('button[title="Correct referrer"]'));
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

test('AFFILIATES-7: an Owner or Manager is told when the claim lists cannot be loaded', async () => {
  await mount('manager', b => b.failures.set('affiliate_pending_claims', 'connection reset'));
  const card = document.querySelector('[data-error="claims"]');
  assert.ok(card && card.textContent.includes('connection reset'), 'the claims error card');
});

test('AFFILIATES-8: Suspend asks for a reason in a window, refuses a blank one and sends the reason typed', async () => {
  await mount('owner');
  await click(button('Suspend', row('Ria Test')));
  assert.equal(prompted, 0, 'no browser prompt');
  assert.ok(modal() && modal().textContent.includes('Suspend Ria Test?'));
  await click(button('Suspend', modal()));
  assert.ok(modal().textContent.includes('This field is required.'));
  assert.equal(callsOf('suspend_affiliate').length, 0, 'nothing sent for a blank reason');
  await setValue(modal().querySelector('textarea'), '  Shared a fake link  ');
  await click(button('Suspend', modal()));
  assert.deepEqual(callsOf('suspend_affiliate').map(c => c.args), [{ p_customer_id: 'c-ria', p_reason: 'Shared a fake link' }]);
  absent(modal(), 'the window closes once saved');
  assert.ok(text().includes('Ria Test is suspended.'));
});

test('AFFILIATES-8: a refused suspension stays in its window with the server\'s words', async () => {
  await mount('owner', b => b.failures.set('suspend_affiliate', 'Affiliate not found'));
  await click(button('Suspend', row('Ken Test')));
  await setValue(modal().querySelector('textarea'), 'Asked to stop');
  await click(button('Suspend', modal()));
  assert.ok(modal() && modal().textContent.includes('Affiliate not found'));
});

test('AFFILIATES-8: Correct Referrer shows the current referrer, and removing them needs a tick', async () => {
  await mount('owner');
  await click(row('Ria Test').querySelector('button[title="Correct referrer"]'));
  const current = modal().querySelector('[data-current-referrer]');
  assert.ok(current.textContent.includes('Current referrer: Ken Test, since 14/08/2026'), current.textContent);
  const save = () => button('Remove Referrer', modal()) ?? button('Save Correction', modal());
  assert.equal(save().textContent.trim(), 'Remove Referrer', 'a blank new referrer removes the current one');
  assert.equal(save().disabled, true, 'no reason, no tick: Save is off');
  await setValue(modal().querySelectorAll('textarea')[0], 'Wrong link was used');
  assert.equal(save().disabled, true, 'the tick is still needed');
  const box = modal().querySelector('[data-remove-referrer] input');
  assert.ok(modal().querySelector('[data-remove-referrer]').textContent.includes('Remove Ken Test as the referrer.'));
  await tickBox(box, true);
  assert.equal(save().disabled, false);
  await click(save());
  assert.deepEqual(callsOf('reassign_customer_referrer').map(c => c.args),
    [{ p_customer_id: 'c-ria', p_new_referrer_id: null, p_reason: 'Wrong link was used' }]);
});

test('AFFILIATES-8: with no referrer now, a blank new referrer changes nothing and cannot be saved', async () => {
  await mount('owner');
  await click(row('Ken Test').querySelector('button[title="Correct referrer"]'));
  assert.ok(modal().querySelector('[data-current-referrer]').textContent.includes('Current referrer: None'));
  await setValue(modal().querySelectorAll('textarea')[0], 'Checking');
  absent(modal().querySelector('[data-remove-referrer]'), 'nothing to remove');
  assert.equal(button('Save Correction', modal()).disabled, true);
});

test('AFFILIATES-10: staff search sends one request after the typing stops; a new search starts at page 1; Next asks once', async () => {
  await mount('staff');
  assert.deepEqual(callsOf('affiliate_staff_directory').map(c => c.args.p_offset), [0], 'one load on opening');
  const box = document.querySelector('input[aria-label="Search affiliates"]');
  await setValue(box, 'R'); await setValue(box, 'Ri'); await setValue(box, 'Ria');
  assert.equal(callsOf('affiliate_staff_directory').length, 1, 'nothing per key');
  await wait(320);
  assert.deepEqual(callsOf('affiliate_staff_directory').map(c => [c.args.p_search, c.args.p_offset]), [[null, 0], ['Ria', 0]]);
  await click(button('Next'));
  assert.deepEqual(callsOf('affiliate_staff_directory').slice(2).map(c => [c.args.p_search, c.args.p_offset]), [['Ria', 50]], 'Next: one request for page 2');
  await setValue(box, 'Ken');
  await wait(320);
  assert.deepEqual(callsOf('affiliate_staff_directory').slice(3).map(c => [c.args.p_search, c.args.p_offset]), [['Ken', 0]], 'a new search starts at page 1');
  await click(button('Refresh'));
  assert.deepEqual(callsOf('affiliate_staff_directory').slice(4).map(c => [c.args.p_search, c.args.p_offset]), [['Ken', 0]], 'Refresh reloads what is on screen');
});

test('AFFILIATES-12: an Owner sees the sign-ups to check, with who had the phone', async () => {
  await mount('owner');
  const card = document.querySelector('[data-section="signup-checks"]');
  assert.ok(card, 'the Check these sign-ups card');
  assert.ok(card.textContent.includes('Check these sign-ups (1)'));
  const r = card.querySelector('[data-check="chk-mae"]');
  for (const s of ['Mae Test', '+61491570157', 'Ria Test', 'Ann Test', '2 paid invoices', '15/10/2026']) assert.ok(r.textContent.includes(s), s);
});

test('AFFILIATES-12: Different person needs a note, then sends the answer and reloads', async () => {
  await mount('owner');
  await click(button('Different person', document.querySelector('[data-check="chk-mae"]')));
  assert.ok(modal().textContent.includes('Mae Test shares a phone with Ann Test but is someone else.'));
  assert.equal(button('Count them', modal()).disabled, true, 'no note, no save');
  await setValue(modal().querySelector('textarea'), 'Called Ann: Mae is her daughter');
  await click(button('Count them', modal()));
  assert.deepEqual(callsOf('decide_referral_signup_check').map(c => c.args),
    [{ p_check_id: 'chk-mae', p_decision: 'different_person', p_note: 'Called Ann: Mae is her daughter' }]);
  absent(modal(), 'closed once saved');
  assert.ok(text().includes('Mae Test is checked as a different person and now counts for referral promotions.'));
  assert.ok(callsOf('referral_signup_checks_pending').length >= 2, 'the list is read again');
});

test('AFFILIATES-12: an answer someone else gave first is said in the window', async () => {
  await mount('manager', b => { b.handlers.decide_referral_signup_check = () => ({ ok: false, already: true, message: 'This sign-up was already checked. Refresh the page.' }); });
  await click(button('Same person', document.querySelector('[data-check="chk-mae"]')));
  assert.ok(modal().textContent.includes('They never count for a referral promotion.'));
  await setValue(modal().querySelector('textarea'), 'Same lady, new spelling');
  await click(button('Do not count them', modal()));
  assert.ok(modal() && modal().textContent.includes('This sign-up was already checked.'));
});

test('AFFILIATES-12: before 425 there is no list and no error; staff never see the list', async () => {
  await mount('owner', b => b.failures.set('referral_signup_checks_pending', MISSING));
  absent(document.querySelector('[data-section="signup-checks"]'), 'no list');
  absent(document.querySelector('[data-error="signup-checks"]'), 'no error');
  await mount('staff');
  absent(document.querySelector('[data-section="signup-checks"]'), 'staff: no list');
  assert.equal(callsOf('referral_signup_checks_pending').length, 0, 'staff: not read');
});
