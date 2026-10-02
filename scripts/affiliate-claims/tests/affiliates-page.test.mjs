// The Affiliates page's account claims and Unlink login, rendered for real
// against a fake backend (378).
//
// The actual src/pages/AffiliatesPage.tsx is bundled with esbuild and mounted
// in jsdom. Only the Supabase client, the auth context and the QR library are
// stubbed: the client by a small in-memory backend that records every call.
// Every name, phone and email below is invented.
//
// It checks what the owner asked for on 2 Oct 2026: staff see the Pending and
// Rejected Account Claims with Resolve, Reject and Delete, and keep the
// read-only directory; the Resolve window shows the phone entered beside the
// chosen customer's phone; staff are told, and cannot save, when they differ;
// an Owner or Manager can still link such a customer; a refusal that applies
// to everyone (a deleted customer) also disables Save; only an Owner finds
// "Unlink login", on a customer with a linked login, and it asks for a reason
// before sending; Admin and Inventory Manager see the directory alone.
// And the owner's final answers: a login an Owner unlinked is flagged
// "Previously unlinked" in the list and the Resolve window, and staff cannot
// link it back; the Unlink window says so and gives Supabase Auth's last
// sign-in; staff Delete only rejections a staff member made; staff claims load
// on their own (not per keystroke) with their own error; before 378 is applied
// an Owner or Manager sees no new error and saves as before. And: a claim
// whose likely customer had a login unlinked by an Owner is flagged "Login
// unlinked before" in the list and the Resolve window, staff cannot link any
// login to that customer, and the Unlink window says so; before 378 is
// applied, staff see the page as it was (no claim sections, no red banner).
// And 379 (the owner, 2 Oct 2026: "Yes, make Reject protect the customer
// too"): a claim whose likely customer an Owner or Manager rejected a claim for
// is flagged "Claim rejected before" in the list and the Resolve window, and
// staff cannot link any login to them; the Reject window tells an Owner or
// Manager that rejecting protects the likely customer (named), and staff that
// their rejection does not; the Rejected list says a rejection by an Owner or
// Manager keeps protecting after it is deleted; before 379 is applied the
// Reject window promises nothing. And after the review of 379: the Rejected
// list shows who rejected each claim, says which likely customers are
// protected, tells everyone a staff rejection does not protect its likely
// customer, and lets an Owner or Manager confirm such a rejection ("Protect
// <name>", with a reason) so that it does; none of that, nor the list's
// sentence about protection, shows before 379 is applied.
//
// Run: node --test scripts/affiliate-claims/tests/affiliates-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ── the page, bundled ──────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://affiliates.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
dom.window.confirm = () => true;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
// Bundled as ESM, React's act() queues each task on a new MessageChannel and
// never closes it; Node's ports then keep the runner alive after the last test.
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
const { AffiliatesPage, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const STAFF_RULE = 'Only an Owner or Manager can link this claim to a customer whose phone differs from the one entered.';
const DELETED = 'This customer record has been deleted. Link the claim to the customer record that is in use.';
const UNLINKED = 'An Owner unlinked this login from this customer. Only an Owner or Manager can link it again.';
const OWN = 'You cannot resolve your own claim. Ask an Owner or Manager.';
const CUST_UNLINKED = 'An Owner unlinked a login from this customer before. Only an Owner or Manager can link a login to them.';
const DELETE_RULE = 'Only an Owner or Manager can remove a rejection they made.';
const CUST_REJECTED = 'An Owner or Manager rejected a claim for this customer. Only an Owner or Manager can link a login to them.';
const MISSING = { code: 'PGRST202', message: 'Could not find the function public.affiliate_claim_link_check(p_claim_id, p_customer_id) in the schema cache' };
function makeFixture() {
  const customers = [
    { id: 'c-ana', full_name: 'Ana Test', phone: '+65 8378 0101', email: null, notes: null, deleted_at: null },
    { id: 'c-ola', full_name: 'Ola Test', phone: '+6583780102', email: null, notes: null, deleted_at: null },
    { id: 'c-gone', full_name: 'Gus Test', phone: '+6583780104', email: null, notes: null, deleted_at: '2026-09-01T00:00:00Z' },
    { id: 'c-ivy', full_name: 'Ivy Test', phone: '+6583780109', email: null, notes: null, deleted_at: null },
    { id: 'c-wyn', full_name: 'Wyn Test', phone: '+6583780111', email: null, notes: null, deleted_at: null },
    { id: 'c-rhea', full_name: 'Rhea Test', phone: '+6583780113', email: null, notes: null, deleted_at: null },
    { id: 'c-tia', full_name: 'Tia Test', phone: '+6583780115', email: null, notes: null, deleted_at: null },
  ];
  // Customers an Owner unlinked a login from (Ivy's was this very login).
  const unlinkedCustomers = ['c-ivy', 'c-wyn'];
  // 379: customers an Owner or Manager rejected a claim for.
  const rejectedCustomers = ['c-rhea'];
  const claim = (id, email, phone, name, cand) => ({
    claim_id: id, verified_email: email, entered_phone: phone, entered_name: name,
    candidate_customer_id: cand, candidate_name: customers.find(c => c.id === cand)?.full_name ?? null,
    created_at: '2026-09-28T02:00:00Z',
  });
  const pending = [
    claim('cl-ana', 'ana.login@tests.invalid', '+6583780101', 'Ana Test', 'c-ana'),
    claim('cl-ola', 'ola.login@tests.invalid', '+6583780112', 'Ola Test', 'c-ola'),
    claim('cl-gus', 'gus.login@tests.invalid', '+6583780104', 'Gus Test', 'c-gone'),
    // An Owner unlinked this login from Ivy Test before.
    { ...claim('cl-ivy', 'ivy.login@tests.invalid', '+6583780109', 'Ivy Test', 'c-ivy'),
      previously_unlinked: true, unlinked_customer_ids: ['c-ivy'], suggested_customer_unlinked: true },
    // A new login whose likely customer had another login unlinked by an Owner.
    { ...claim('cl-wyn', 'wyn.login@tests.invalid', '+6583780111', 'Wyn Test', 'c-wyn'), suggested_customer_unlinked: true },
    // 379: a new login whose likely customer an Owner or Manager rejected a
    // claim for; and a claim that suggests no one.
    { ...claim('cl-rhea', 'rhea.login@tests.invalid', '+6583780113', 'Rhea Test', 'c-rhea'), suggested_customer_rejected: true },
    claim('cl-nob', 'nob.login@tests.invalid', '+6583780114', 'Nob Test', null),
  ].map(c => ({ suggested_customer_rejected: false, ...c }));   // 379 says it for every pending row
  const rejected = [
    // Rejected by an Owner (or Manager): staff cannot delete it.
    { ...claim('cl-rea', 'rea.login@tests.invalid', '+6583780108', 'Rea Test', null),
      rejected_at: '2026-09-29T02:00:00Z', rejection_reason: 'Could not reach the person', rejected_by_staff: false },
    // Rejected by a member of staff: staff may.
    { ...claim('cl-sue', 'sue.login@tests.invalid', '+6583780110', 'Sue Test', null),
      rejected_at: '2026-09-29T03:00:00Z', rejection_reason: 'Wrong number', rejected_by_staff: true },
    // 379: a staff member's rejection of a claim suggesting Tia, who is not
    // protected; an Owner's rejection of one suggesting Rhea (protected); and
    // a staff member's rejection of another claim suggesting Rhea.
    { ...claim('cl-tia', 'tia.login@tests.invalid', '+6583780115', 'Tia Test', 'c-tia'),
      rejected_at: '2026-09-30T03:00:00Z', rejection_reason: 'Could not reach her', rejected_by_staff: true },
    { ...claim('cl-rho', 'rho.login@tests.invalid', '+6583780113', 'Rhea Test', 'c-rhea'),
      rejected_at: '2026-09-30T04:00:00Z', rejection_reason: 'Impostor\nConfirmed by an Owner: she has no account', rejected_by_staff: false },
    { ...claim('cl-ria', 'ria.login@tests.invalid', '+6583780113', 'Ria Test', 'c-rhea'),
      rejected_at: '2026-09-30T05:00:00Z', rejection_reason: 'Not her', rejected_by_staff: true },
    // An Owner's or Manager's rejection that, with no audit row behind it,
    // protects no one (Ola is not protected): neither "by staff" nor Protect.
    { ...claim('cl-ivo', 'ivo.login@tests.invalid', '+6583780102', 'Ola Test', 'c-ola'),
      rejected_at: '2026-09-30T06:00:00Z', rejection_reason: 'Not her', rejected_by_staff: false },
  ].map(c => ({ suggested_customer_rejected: rejectedCustomers.includes(c.candidate_customer_id), ...c }));   // 379 says it for every rejected row
  const directory = [
    { customer_id: 'c-ana', name: 'Ana Test', status: 'active', manually_suspended: false, referral_code: 'ENTEST01',
      portal_account: 'claimed', direct_referrals: 2, tier2: 1, lifetime: '12.50', unpaid: 10, blocked: 0, last_commission: '2026-09-20T00:00:00Z' },
    { customer_id: 'c-bo', name: 'Bo Test', status: 'active', manually_suspended: false, referral_code: 'ENTEST02',
      portal_account: 'not_claimed', direct_referrals: 0, tier2: 0, lifetime: 0, unpaid: 0, blocked: 0, last_commission: null },
  ];
  const staffDirectory = { total: 2, rows: [
    { customer_id: 'c-ana', full_name: 'Ana Test', referral_code: 'ENTEST01', status: 'active', link_usable: true },
    { customer_id: 'c-bo', full_name: 'Bo Test', referral_code: 'ENTEST02', status: 'active', link_usable: true },
  ] };
  return { customers, unlinkedCustomers, rejectedCustomers, pending, rejected, directory, staffDirectory };
}

// ── fake backend ───────────────────────────────────────────────────────────
// affiliate_claim_link_check answers as 378 does: the same normalised phone
// (here: the digits), a deleted customer refused for everyone (and hidden from
// staff), and for staff only a login an Owner unlinked from that customer, any
// login an Owner unlinked from that customer, a customer an Owner or Manager
// rejected a claim for (379), and the phone rule.
const digits = p => (p ?? '').replace(/\D/g, '').replace(/^(?!65)(\d{8})$/, '65$1');
function createBackend(fx, role) {
  const b = { calls: [], handlers: {}, failures: new Map(), fx };
  const anyCustomer = role === 'owner' || role === 'manager';
  const rpcs = {
    affiliate_admin_directory: () => fx.directory,
    affiliate_staff_directory: () => fx.staffDirectory,
    affiliate_pending_claims: () => fx.pending,
    affiliate_rejected_claims: () => fx.rejected,
    affiliate_claim_link_check: a => {
      const cl = fx.pending.find(c => c.claim_id === a.p_claim_id);
      const c = fx.customers.find(x => x.id === a.p_customer_id);
      const match = !!digits(cl.entered_phone) && digits(cl.entered_phone) === digits(c.phone);
      const unlinked = (cl.unlinked_customer_ids ?? []).includes(c.id);
      const custUnlinked = fx.unlinkedCustomers.includes(c.id);
      const custRejected = fx.rejectedCustomers.includes(c.id);
      const hide = !anyCustomer && !!c.deleted_at;
      return { claim_id: cl.claim_id, entered_phone: cl.entered_phone, customer_id: c.id,
        customer_name: hide ? null : c.full_name, customer_phone: hide ? null : c.phone,
        phones_match: match, customer_deleted: !!c.deleted_at, customer_has_login: false,
        login_is_staff: false, previously_unlinked: unlinked, unlinked_at: unlinked ? '2026-09-30T05:00:00Z' : null,
        customer_previously_unlinked: custUnlinked, customer_unlinked_at: custUnlinked ? '2026-09-30T05:00:00Z' : null,
        customer_previously_rejected: custRejected, customer_rejected_at: custRejected ? '2026-10-01T05:00:00Z' : null,
        phone_changed_since_claim: false, customers_sharing_phone: 1, suggested_customer: cl.candidate_customer_id === c.id,
        own_claim: false, any_customer: anyCustomer,
        problem: c.deleted_at ? DELETED : anyCustomer ? null : unlinked ? UNLINKED : custUnlinked ? CUST_UNLINKED
          : custRejected ? CUST_REJECTED : !match ? STAFF_RULE : null };
    },
    resolve_affiliate_account_claim: a => ({ ok: true, customer_id: a.p_customer_id }),
    reject_affiliate_account_claim: () => ({ ok: true }),
    delete_affiliate_account_claim: () => ({ ok: true }),
    // last_sign_in_at is Supabase Auth's; the stale last_login_at (the day it
    // was linked) is what 378 used to send, and must not be what is shown.
    affiliate_portal_login: () => ({ linked: true, login_email: 'ana.login@tests.invalid', status: 'claimed',
      linked_at: '2026-09-28T03:00:00Z', last_sign_in_at: '2026-10-01T03:00:00Z', last_login_at: '2026-09-28T03:00:00Z',
      claims: [{ claim_id: 'cl-old', entered_name: 'Ana Test', entered_phone: '+6583780101', resolved_at: '2026-09-28T03:00:00Z',
        resolution_note: 'Phoned the number on file', resolved_by_name: 'Staff One' }] }),
    unlink_affiliate_account: a => ({ ok: true, customer_id: a.p_customer_id, login_email: 'ana.login@tests.invalid' }),
  };
  const tables = { customers: fx.customers };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], single: false }); }
    select() { return this; }
    eq(c, v) { this.filters.push(r => r[c] === v); return this; }
    is(c, v) { this.filters.push(r => (r[c] ?? null) === v); return this; }
    in(c, vs) { this.filters.push(r => vs.includes(r[c])); return this; }
    or() { return this; }
    order() { return this; }
    limit() { return this; }
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
      const rows = (tables[this.name] ?? []).filter(r => this.filters.every(f => f(r)));
      return { data: structuredClone(this.single ? rows[0] ?? null : rows), error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

// ── driving the page ───────────────────────────────────────────────────────
const USERS = {
  owner: { id: 'u-own', full_name: 'Owner One', role: 'owner', is_active: true },
  manager: { id: 'u-mgr', full_name: 'Manager One', role: 'manager', is_active: true },
  staff: { id: 'u-staff', full_name: 'Staff One', role: 'staff', is_active: true },
  admin: { id: 'u-adm', full_name: 'Admin One', role: 'admin', is_active: true },
  inventory_manager: { id: 'u-inv', full_name: 'Stock Keeper', role: 'inventory_manager', is_active: true },
};
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(role, setup) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(makeFixture(), role);
  globalThis.__backend = backend; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: USERS[role] };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(AffiliatesPage))));
  await tick();
  // The staff directory search is debounced by 300 ms.
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
  const proto = el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
  });
  await tick(2);
}
const modal = () => document.querySelector('.modal');
const claimRow = email => [...document.querySelectorAll('tr')].find(tr => tr.textContent.includes(email));
// That an element is not there. (A jsdom element inside a failed assertion is
// serialised whole by the test reporter, which then runs out of memory instead
// of reporting the failure; so only its presence is compared.)
const absent = (el, msg) => assert.ok(el == null, msg);
const callsOf = name => backend.calls.filter(c => c.name === name);
const phones = () => ({
  entered: modal().querySelector('[data-phone="entered"]')?.textContent,
  customer: modal().querySelector('[data-phone="customer"]')?.textContent,
});
async function openResolve(email) { await click(button('Resolve', claimRow(email))); }
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── tests ──────────────────────────────────────────────────────────────────
test('staff see Pending and Rejected Account Claims with Resolve, Reject and Delete, and keep the read-only directory', async () => {
  await mount('staff');
  assert.deepEqual(globalThis.__renderErrors, []);
  assert.ok(text().includes('Pending Account Claims (7)'), text());
  assert.ok(text().includes('Rejected Account Claims (6)'));
  const row = claimRow('ana.login@tests.invalid');
  assert.ok(button('Resolve', row) && button('Reject', row), 'Resolve and Reject on a pending claim');
  assert.ok(row.querySelector('button[title="Delete request"]'), 'Delete on a pending claim');
  assert.ok(button('Delete', claimRow('sue.login@tests.invalid')), 'Delete on a rejected claim');
  assert.equal(callsOf('affiliate_pending_claims').length >= 1 && callsOf('affiliate_rejected_claims').length >= 1, true);
  assert.equal(callsOf('affiliate_admin_directory').length, 0, 'the Owner/Manager directory is not read');
  assert.ok(callsOf('affiliate_staff_directory').length >= 1, 'the staff directory is');
  assert.ok(!text().includes('Lifetime') && !text().includes('Unpaid'), 'no money columns');
  assert.ok(!button('Unlink login'), 'no Unlink');
  assert.ok(!document.querySelector('button[title="Correct referrer"]') && !button('Suspend'), 'no referrer correction or suspension');
});

test('the Resolve window shows the two phones side by side, and staff link the customer whose phone matches', async () => {
  await mount('staff');
  await openResolve('ana.login@tests.invalid');
  assert.deepEqual(callsOf('affiliate_claim_link_check').map(c => c.args), [{ p_claim_id: 'cl-ana', p_customer_id: 'c-ana' }],
    'the likely customer is checked as soon as the window opens');
  const p = phones();
  assert.ok(p.entered.includes('Phone entered at sign-up') && p.entered.includes('+6583780101'), p.entered);
  assert.ok(p.customer.includes("Customer's phone") && p.customer.includes('+65 8378 0101'), p.customer);
  assert.ok(modal().textContent.includes('The phones match.'));
  assert.ok(!modal().textContent.includes(STAFF_RULE));
  await setValue(modal().querySelector('textarea'), 'Phoned the number on file');
  const save = button('Link Account');
  assert.equal(save.disabled, false, 'Save is enabled');
  await click(save);
  assert.deepEqual(callsOf('resolve_affiliate_account_claim').map(c => c.args),
    [{ p_claim_id: 'cl-ana', p_customer_id: 'c-ana', p_note: 'Phoned the number on file' }]);
  absent(modal(), 'the window closes');
  assert.ok(text().includes('Account claim resolved.'));
});

test('staff are told, and cannot save, when the phones differ', async () => {
  await mount('staff');
  await openResolve('ola.login@tests.invalid');
  const p = phones();
  assert.ok(p.entered.includes('+6583780112') && p.customer.includes('+6583780102'), `${p.entered} | ${p.customer}`);
  const alert = [...modal().querySelectorAll('[role="alert"]')].map(a => a.textContent);
  assert.deepEqual(alert, [STAFF_RULE], 'the owner\'s sentence, once');
  await setValue(modal().querySelector('textarea'), 'Looks like them');
  const save = button('Link Account');
  assert.equal(save.disabled, true, 'Save is disabled');
  await click(save);
  assert.equal(callsOf('resolve_affiliate_account_claim').length, 0, 'nothing is sent');
});

test('an Owner or Manager may still link a customer whose phone differs', async () => {
  for (const role of ['manager', 'owner']) {
    await mount(role);
    await openResolve('ola.login@tests.invalid');
    assert.ok(modal().textContent.includes('The phones differ.'), `${role}: the difference is shown`);
    assert.ok(!modal().textContent.includes(STAFF_RULE), `${role}: no staff refusal`);
    await setValue(modal().querySelector('textarea'), 'Verified in person; changed number');
    assert.equal(button('Link Account').disabled, false, `${role}: Save is enabled`);
    await click(button('Link Account'));
    assert.deepEqual(callsOf('resolve_affiliate_account_claim').map(c => c.args),
      [{ p_claim_id: 'cl-ola', p_customer_id: 'c-ola', p_note: 'Verified in person; changed number' }], role);
  }
});

test('a refusal that applies to everyone (a deleted customer) is shown and disables Save, for an Owner too', async () => {
  await mount('owner');
  await openResolve('gus.login@tests.invalid');
  assert.ok(modal().textContent.includes(DELETED), modal().textContent);
  await setValue(modal().querySelector('textarea'), 'x');
  assert.equal(button('Link Account').disabled, true);
});

test('only an Owner finds Unlink login, on a customer with a linked login, and it needs a reason', async () => {
  await mount('owner');
  const unlinks = buttons().filter(b => b.textContent.trim() === 'Unlink login');
  assert.equal(unlinks.length, 1, 'one linked customer, one Unlink');
  assert.equal(unlinks[0].getAttribute('aria-label'), 'Unlink login of Ana Test');
  await click(unlinks[0]);
  assert.deepEqual(callsOf('affiliate_portal_login').map(c => c.args), [{ p_customer_id: 'c-ana' }]);
  const m = modal();
  assert.ok(m.textContent.includes('ana.login@tests.invalid'), 'the login is named');
  assert.ok(m.textContent.includes('account claim resolved by Staff One'), 'and how it was linked');
  assert.ok(m.textContent.includes('Phoned the number on file'));
  assert.ok(m.textContent.includes('referral code and link, referred customers, commissions and payouts stay as they are'));
  assert.ok(m.textContent.includes('last signed in 01/10/2026'), 'the last sign-in is Supabase Auth\'s, not the day it was linked');
  assert.ok(m.textContent.includes('which usually parks a new account claim and never links them back to Ana Test by itself, even if their email, phone and name all match this customer\'s record.'),
    'sign-up no longer links the login straight back');
  assert.ok(!m.textContent.includes('links them straight back'), 'the old promise is gone');
  const note = m.querySelector('[data-note="after-unlink"]')?.textContent ?? '';
  assert.ok(note.includes('Afterwards staff cannot link any login to Ana Test, this one or a new one, and sign-up no longer links one to them automatically; only an Owner or Manager can link a login to them.'), note);
  const others = m.querySelector('[data-note="other-customers"]')?.textContent ?? '';
  assert.ok(others.includes('This covers Ana Test only.')
    && others.includes('For other customers, staff who change a customer\'s email, name or phone can still change which customer a sign-up is linked to automatically, as before.'), others);
  assert.ok(note.includes('a claim that suggests Ana Test shows “Login unlinked before”'), note);
  assert.ok(note.includes('If the person must not get back in, Reject that claim.'), note);
  const go = buttons(m).find(b => b.textContent.trim() === 'Unlink login');
  assert.equal(go.disabled, true, 'no reason, no unlink');
  await setValue(m.querySelector('#unlink-reason'), '  Linked to the wrong Ana ');
  assert.equal(go.disabled, false);
  await click(go);
  assert.deepEqual(callsOf('unlink_affiliate_account').map(c => c.args), [{ p_customer_id: 'c-ana', p_reason: 'Linked to the wrong Ana' }]);
  absent(modal(), 'the window closes');
  assert.ok(text().includes('Login unlinked. ana.login@tests.invalid no longer opens Ana Test\'s affiliate portal'), text());
  assert.ok(callsOf('affiliate_admin_directory').length >= 2, 'the directory is reloaded');
});

test('a refused unlink is shown in its window, which stays open', async () => {
  await mount('owner', b => b.failures.set('unlink_affiliate_account', 'Only an Owner can unlink an affiliate login'));
  await click(buttons().find(b => b.textContent.trim() === 'Unlink login'));
  await setValue(modal().querySelector('#unlink-reason'), 'Linked to the wrong Ana');
  await click(buttons(modal()).find(b => b.textContent.trim() === 'Unlink login'));
  assert.ok(modal(), 'the window stays open');
  assert.equal(modal().querySelector('[role="alert"]')?.textContent, 'Only an Owner can unlink an affiliate login');
  assert.ok(!text().includes('Login unlinked.'));
});

test('a Manager handles claims as before but has no Unlink', async () => {
  await mount('manager');
  assert.ok(text().includes('Pending Account Claims (7)'));
  assert.ok(text().includes('Lifetime'), 'the money columns stay');
  assert.ok(!buttons().some(b => b.textContent.trim() === 'Unlink login'));
});

test('Admin and Inventory Manager see the directory alone, as before', async () => {
  for (const role of ['admin', 'inventory_manager']) {
    await mount(role);
    assert.ok(!text().includes('Pending Account Claims'), role);
    assert.ok(!text().includes('Rejected Account Claims'), role);
    assert.equal(callsOf('affiliate_pending_claims').length + callsOf('affiliate_rejected_claims').length, 0, `${role}: claims are not read`);
    assert.ok(text().includes('Ana Test'), `${role}: the directory is there`);
  }
});

test('a login an Owner unlinked is flagged in the list and the Resolve window, and staff cannot link it back', async () => {
  await mount('staff');
  const flagged = [...document.querySelectorAll('tr')].filter(tr => tr.querySelector('[data-flag="previously-unlinked"]'));
  assert.deepEqual(flagged.map(tr => tr.textContent.includes('ivy.login@tests.invalid')), [true], 'only the unlinked login is flagged');
  assert.ok(flagged[0].textContent.includes('Previously unlinked'));
  await openResolve('ivy.login@tests.invalid');
  const flag = modal().querySelector('[data-flag="previously-unlinked"]')?.textContent ?? '';
  assert.ok(flag.includes('Previously unlinked.') && flag.includes('An Owner unlinked this login from this customer on 30/09/2026.'), flag);
  assert.ok(modal().textContent.includes('The phones match.'), 'though the phones match');
  assert.deepEqual([...modal().querySelectorAll('[role="alert"]')].map(a => a.textContent), [UNLINKED]);
  await setValue(modal().querySelector('textarea'), 'Phoned the number on file');
  assert.equal(button('Link Account').disabled, true, 'Save is disabled');
  await click(button('Link Account'));
  assert.equal(callsOf('resolve_affiliate_account_claim').length, 0, 'nothing is sent');
});

test('for another customer the window still flags the login, and an Owner or Manager may link it back', async () => {
  // The server says this customer is not the one it was unlinked from.
  await mount('staff', b => { b.handlers.affiliate_claim_link_check = a => ({ claim_id: a.p_claim_id, entered_phone: '+6583780109',
    customer_id: a.p_customer_id, customer_name: 'Ivy Test', customer_phone: '+6583780109', phones_match: true,
    customer_deleted: false, customer_has_login: false, login_is_staff: false, previously_unlinked: false,
    any_customer: false, problem: null }); });
  await openResolve('ivy.login@tests.invalid');
  const other = modal().querySelector('[data-flag="previously-unlinked"]')?.textContent ?? '';
  assert.ok(other.includes('An Owner unlinked this login from a customer before.'), other);
  assert.equal(modal().querySelectorAll('[role="alert"]').length, 0);
  for (const role of ['owner', 'manager']) {
    await mount(role);
    assert.ok(claimRow('ivy.login@tests.invalid').querySelector('[data-flag="previously-unlinked"]'), `${role}: flagged in the list`);
    await openResolve('ivy.login@tests.invalid');
    const flag = modal().querySelector('[data-flag="previously-unlinked"]')?.textContent ?? '';
    assert.ok(flag.includes('from this customer') && flag.includes('Staff cannot link it back to that customer'), `${role}: ${flag}`);
    assert.equal(modal().querySelectorAll('[role="alert"]').length, 0, `${role}: no refusal`);
    await setValue(modal().querySelector('textarea'), 'Owner checked in person');
    assert.equal(button('Link Account').disabled, false, `${role}: Save is enabled`);
    await click(button('Link Account'));
    assert.deepEqual(callsOf('resolve_affiliate_account_claim').map(c => c.args),
      [{ p_claim_id: 'cl-ivy', p_customer_id: 'c-ivy', p_note: 'Owner checked in person' }], role);
  }
});

test('any other refusal the server gives staff (their own claim) is shown and disables Save', async () => {
  await mount('staff', b => { b.handlers.affiliate_claim_link_check = a => ({ claim_id: a.p_claim_id, entered_phone: '+6583780101',
    customer_id: a.p_customer_id, customer_name: 'Ana Test', customer_phone: '+65 8378 0101', phones_match: true,
    customer_deleted: false, customer_has_login: false, login_is_staff: false, own_claim: true, any_customer: false, problem: OWN }); });
  await openResolve('ana.login@tests.invalid');
  assert.deepEqual([...modal().querySelectorAll('[role="alert"]')].map(a => a.textContent), [OWN]);
  await setValue(modal().querySelector('textarea'), 'x');
  assert.equal(button('Link Account').disabled, true);
});

test('staff delete only a rejection a staff member made; an Owner deletes any', async () => {
  await mount('staff');
  const theirs = button('Delete', claimRow('rea.login@tests.invalid'));
  assert.equal(theirs.disabled, true, 'an Owner\'s or Manager\'s rejection: no Delete');
  assert.equal(theirs.getAttribute('title'), DELETE_RULE, 'and it says why');
  const staffs = button('Delete', claimRow('sue.login@tests.invalid'));
  assert.equal(staffs.disabled, false, 'a staff rejection: Delete');
  await click(staffs);
  await click(button('Delete Request'));
  assert.deepEqual(callsOf('delete_affiliate_account_claim').map(c => c.args), [{ p_claim_id: 'cl-sue' }]);
  for (const role of ['owner', 'manager']) {
    await mount(role);
    assert.equal(button('Delete', claimRow('rea.login@tests.invalid')).disabled, false, `${role}: Delete as before`);
    assert.equal(button('Delete', claimRow('sue.login@tests.invalid')).disabled, false, `${role}: Delete as before`);
  }
});

test('staff claims load on their own: not on every search keystroke, and their error is not cleared by the directory', async () => {
  await mount('staff');
  const claimCalls = () => callsOf('affiliate_pending_claims').length + callsOf('affiliate_rejected_claims').length;
  assert.equal(claimCalls(), 2, 'pending and rejected, once each');
  const dirBefore = callsOf('affiliate_staff_directory').length;
  const search = document.querySelector('input[aria-label="Search affiliates"]');
  for (const v of ['A', 'An', 'Ana', 'Ana ', 'Ana T']) await setValue(search, v);
  await act(async () => { await new Promise(r => setTimeout(r, 320)); });
  await tick();
  assert.ok(callsOf('affiliate_staff_directory').length > dirBefore, 'the directory is searched');
  assert.equal(claimCalls(), 2, 'the claims are not read again');
  // A change reads them again.
  await click(button('Reject', claimRow('ana.login@tests.invalid')));
  await setValue(modal().querySelector('textarea'), 'Not them');
  await click(button('Reject Claim'));
  assert.equal(claimCalls(), 4, 'after a reject, once more');

  await mount('staff', b => b.failures.set('affiliate_pending_claims', 'permission denied for the claims'));
  const banner = () => document.querySelector('[data-error="claims"]')?.textContent ?? '';
  assert.ok(banner().includes('permission denied for the claims'), 'the claims error is shown after the directory loaded');
  await setValue(document.querySelector('input[aria-label="Search affiliates"]'), 'Bo');
  await act(async () => { await new Promise(r => setTimeout(r, 320)); });
  await tick();
  assert.ok(banner().includes('permission denied for the claims'), 'and stays after another directory search');
});

test('staff see a "safe no-op" answer from the server after the reload', async () => {
  await mount('staff', b => { b.handlers.resolve_affiliate_account_claim = () =>
    ({ ok: false, already: true, message: 'This login is already linked to an affiliate account.' }); });
  await openResolve('ana.login@tests.invalid');
  await setValue(modal().querySelector('textarea'), 'Phoned the number on file');
  await click(button('Link Account'));
  assert.ok(text().includes('This login is already linked to an affiliate account.'), text());
});

test('before 378 is applied, an Owner or Manager sees the Resolve window as before; staff are told', async () => {
  for (const role of ['owner', 'manager']) {
    await mount(role, b => b.failures.set('affiliate_claim_link_check', MISSING));
    await openResolve('ola.login@tests.invalid');
    assert.equal(modal().querySelectorAll('[role="alert"]').length, 0, `${role}: no red alert`);
    assert.ok(!modal().textContent.includes('Could not find the function'), role);
    await setValue(modal().querySelector('textarea'), 'Verified in person');
    assert.equal(button('Link Account').disabled, false, `${role}: Save works`);
    await click(button('Link Account'));
    assert.equal(callsOf('resolve_affiliate_account_claim').length, 1, `${role}: and is sent`);
  }
  await mount('staff', b => b.failures.set('affiliate_claim_link_check', MISSING));
  await openResolve('ana.login@tests.invalid');
  assert.ok(modal().querySelector('[role="alert"]')?.textContent.includes('Could not find the function'), 'staff are told');
  await setValue(modal().querySelector('textarea'), 'x');
  assert.equal(button('Link Account').disabled, true, 'and cannot save');
});

test('before 378 is applied, the Unlink window shows no red alert', async () => {
  await mount('owner', b => b.failures.set('affiliate_portal_login',
    { code: 'PGRST202', message: 'Could not find the function public.affiliate_portal_login(p_customer_id) in the schema cache' }));
  await click(buttons().find(b => b.textContent.trim() === 'Unlink login'));
  const m = modal();
  assert.equal(m.querySelectorAll('[role="alert"]').length, 0, 'no red alert');
  assert.ok(m.textContent.includes('Unlinking a login is not available yet.'), m.textContent);
  assert.ok(!m.textContent.includes('Loading…'));
  assert.equal(buttons(m).find(b => b.textContent.trim() === 'Unlink login').disabled, true);
  // Any other failure is still shown.
  await mount('owner', b => b.failures.set('affiliate_portal_login', 'Only an Owner can see or unlink an affiliate login'));
  await click(buttons().find(b => b.textContent.trim() === 'Unlink login'));
  assert.equal(modal().querySelector('[role="alert"]')?.textContent, 'Only an Owner can see or unlink an affiliate login');
});

test('a claim suggesting a customer an Owner unlinked a login from is flagged; staff cannot link any login to them', async () => {
  await mount('staff');
  const flagged = () => [...document.querySelectorAll('tr')].filter(tr => tr.querySelector('[data-flag="customer-previously-unlinked"]'))
    .map(tr => tr.querySelector('td').textContent.split('.invalid')[0] + '.invalid');
  assert.deepEqual(flagged(), ['ivy.login@tests.invalid', 'wyn.login@tests.invalid'], 'the claims whose likely customer had a login unlinked');
  const badge = claimRow('wyn.login@tests.invalid').querySelector('[data-flag="customer-previously-unlinked"]');
  assert.equal(badge.textContent, 'Login unlinked before');
  assert.equal(badge.getAttribute('title'), CUST_UNLINKED);
  absent(claimRow('wyn.login@tests.invalid').querySelector('[data-flag="previously-unlinked"]'), 'not this login');
  await openResolve('wyn.login@tests.invalid');
  const flag = modal().querySelector('[data-flag="customer-previously-unlinked"]')?.textContent ?? '';
  assert.ok(flag.includes('Login unlinked before.') && flag.includes('An Owner unlinked a login from this customer on 30/09/2026.'), flag);
  assert.ok(!flag.includes('Staff cannot link'), 'staff are told by the refusal itself');
  absent(modal().querySelector('[data-flag="previously-unlinked"]'), 'the window does not flag this login');
  assert.ok(modal().textContent.includes('The phones match.'), 'though the phones match');
  assert.deepEqual([...modal().querySelectorAll('[role="alert"]')].map(a => a.textContent), [CUST_UNLINKED]);
  await setValue(modal().querySelector('textarea'), 'Phoned the number on file');
  assert.equal(button('Link Account').disabled, true, 'Save is disabled');
  await click(button('Link Account'));
  assert.equal(callsOf('resolve_affiliate_account_claim').length, 0, 'nothing is sent');
  // The same login's own unlink keeps its own flag and sentence, not this one.
  await click(button('Cancel', modal()));
  await openResolve('ivy.login@tests.invalid');
  absent(modal().querySelector('[data-flag="customer-previously-unlinked"]'), 'its own unlink is flagged as such, not as another login\'s');
  assert.deepEqual([...modal().querySelectorAll('[role="alert"]')].map(a => a.textContent), [UNLINKED]);
  for (const role of ['owner', 'manager']) {
    await mount(role);
    assert.ok(claimRow('wyn.login@tests.invalid').querySelector('[data-flag="customer-previously-unlinked"]'), `${role}: flagged in the list`);
    await openResolve('wyn.login@tests.invalid');
    const f = modal().querySelector('[data-flag="customer-previously-unlinked"]')?.textContent ?? '';
    assert.ok(f.includes('Staff cannot link any login to them'), `${role}: ${f}`);
    assert.equal(modal().querySelectorAll('[role="alert"]').length, 0, `${role}: no refusal`);
    await setValue(modal().querySelector('textarea'), 'Owner checked in person');
    assert.equal(button('Link Account').disabled, false, `${role}: Save is enabled`);
    await click(button('Link Account'));
    assert.deepEqual(callsOf('resolve_affiliate_account_claim').map(c => c.args),
      [{ p_claim_id: 'cl-wyn', p_customer_id: 'c-wyn', p_note: 'Owner checked in person' }], role);
  }
});

test('before 378 is applied, staff see the page as it was: no claim sections and no red banner', async () => {
  const OLD = { code: 'P0001', message: 'Owner or Manager only' };
  const GONE = { code: 'PGRST202', message: 'Could not find the function public.affiliate_pending_claims without parameters in the schema cache' };
  for (const [label, pending, rejectedErr] of [['the old refusal', OLD, OLD], ['no such function', GONE, GONE], ['the old refusal on one list', OLD, null]]) {
    await mount('staff', b => { b.failures.set('affiliate_pending_claims', pending); if (rejectedErr) b.failures.set('affiliate_rejected_claims', rejectedErr); });
    assert.deepEqual(globalThis.__renderErrors, [], label);
    absent(document.querySelector('[data-error="claims"]'), `${label}: no claims banner`);
    assert.ok(!text().includes('Owner or Manager only') && !text().includes('Could not find the function'), `${label}: no error at all`);
    assert.ok(!text().includes('Pending Account Claims') && !text().includes('Rejected Account Claims'), `${label}: no claim sections`);
    assert.ok(!text().includes('settle account claims'), `${label}: the intro does not offer claims`);
    assert.ok(text().includes('Changes to affiliate accounts are made by an Owner or Manager.'), `${label}: the intro staff had before`);
    assert.ok(text().includes('Ana Test') && button('QR & link'), `${label}: the directory is there`);
    await click(button('Refresh'));
    absent(document.querySelector('[data-error="claims"]'), `${label}: still no banner after Refresh`);
    assert.ok(!text().includes('Pending Account Claims'), `${label}: still no claims after Refresh`);
  }
  // Once the server offers them (378 applied), they show on the next load.
  await mount('staff', b => b.failures.set('affiliate_pending_claims', OLD));
  backend.failures.delete('affiliate_pending_claims');
  await click(button('Refresh'));
  assert.ok(text().includes('Pending Account Claims (7)') && text().includes('settle account claims'), 'shown once 378 is there');
});

// ── 379: an Owner's or Manager's Reject protects the likely customer ────────
const PROTECTS = name => `Rejecting also protects ${name}: afterwards staff cannot link any login to them, and sign-up no longer links one to them automatically; only an Owner or Manager can. This stays even if the rejected request is deleted later.`;
const NO_CUSTOMER = 'No likely customer is suggested, so rejecting this claim does not protect any customer.';
const STAFF_NOTE = name => `Your rejection does not protect ${name}: staff can still link another login to them, and sign-up can still link one automatically. If they need protecting, ask an Owner or Manager to reject this claim instead, or to protect them from Rejected Account Claims once you have rejected it.`;
const note = which => modal().querySelector(`[data-note="${which}"]`)?.textContent ?? null;
async function openReject(email) { await click(button('Reject', claimRow(email))); }

test('a claim suggesting a customer an Owner or Manager rejected a claim for is flagged; staff cannot link any login to them', async () => {
  await mount('staff');
  const flagged = [...document.querySelectorAll('tr')].filter(tr => tr.querySelector('[data-flag="customer-previously-rejected"]'));
  assert.deepEqual(flagged.map(tr => tr.textContent.includes('rhea.login@tests.invalid')), [true], 'only the claim whose likely customer is protected');
  const badge = flagged[0].querySelector('[data-flag="customer-previously-rejected"]');
  assert.equal(badge.textContent, 'Claim rejected before');
  assert.equal(badge.getAttribute('title'), CUST_REJECTED);
  absent(flagged[0].querySelector('[data-flag="customer-previously-unlinked"]'), 'not flagged as unlinked');
  await openResolve('rhea.login@tests.invalid');
  const flag = modal().querySelector('[data-flag="customer-previously-rejected"]')?.textContent ?? '';
  assert.equal(flag, 'Claim rejected before. An Owner or Manager rejected a claim for this customer on 01/10/2026.', 'staff are told by the refusal itself');
  absent(modal().querySelector('[data-flag="customer-previously-unlinked"]'), 'no unlink flag');
  assert.ok(modal().textContent.includes('The phones match.'), 'though the phones match');
  assert.deepEqual([...modal().querySelectorAll('[role="alert"]')].map(a => a.textContent), [CUST_REJECTED]);
  await setValue(modal().querySelector('textarea'), 'Phoned the number on file');
  assert.equal(button('Link Account').disabled, true, 'Save is disabled');
  await click(button('Link Account'));
  assert.equal(callsOf('resolve_affiliate_account_claim').length, 0, 'nothing is sent');
  // Another customer in the same window carries no such flag.
  await click(button('Cancel', modal()));
  await openResolve('ana.login@tests.invalid');
  absent(modal().querySelector('[data-flag="customer-previously-rejected"]'), 'a customer no one rejected a claim for is not flagged');
  for (const role of ['owner', 'manager']) {
    await mount(role);
    assert.ok(claimRow('rhea.login@tests.invalid').querySelector('[data-flag="customer-previously-rejected"]'), `${role}: flagged in the list`);
    await openResolve('rhea.login@tests.invalid');
    const f = modal().querySelector('[data-flag="customer-previously-rejected"]')?.textContent ?? '';
    assert.equal(f, 'Claim rejected before. An Owner or Manager rejected a claim for this customer on 01/10/2026. Staff cannot link any login to them; link this one only once you are sure who the person is.', `${role}: ${f}`);
    assert.equal(modal().querySelectorAll('[role="alert"]').length, 0, `${role}: no refusal`);
    await setValue(modal().querySelector('textarea'), 'Owner checked in person');
    assert.equal(button('Link Account').disabled, false, `${role}: Save is enabled`);
    await click(button('Link Account'));
    assert.deepEqual(callsOf('resolve_affiliate_account_claim').map(c => c.args),
      [{ p_claim_id: 'cl-rhea', p_customer_id: 'c-rhea', p_note: 'Owner checked in person' }], role);
  }
});

test('the Reject window tells an Owner or Manager that rejecting protects the likely customer, by name', async () => {
  for (const role of ['owner', 'manager']) {
    await mount(role);
    await openReject('ana.login@tests.invalid');
    assert.equal(note('reject-protects'), PROTECTS('Ana Test'), role);
    assert.equal(note('reject-staff'), null, `${role}: not the staff sentence`);
    await setValue(modal().querySelector('textarea'), 'Not Ana');
    await click(button('Reject Claim'));
    assert.deepEqual(callsOf('reject_affiliate_account_claim').map(c => c.args), [{ p_claim_id: 'cl-ana', p_reason: 'Not Ana' }], role);
    absent(modal(), `${role}: the window closes`);
    // Already protected, the window still says what this rejection does.
    await openReject('rhea.login@tests.invalid');
    assert.equal(note('reject-protects'), PROTECTS('Rhea Test'), `${role}: Rhea`);
    await click(button('Cancel', modal()));
    // A claim that suggests no one protects no one.
    await openReject('nob.login@tests.invalid');
    assert.equal(note('reject-protects'), NO_CUSTOMER, `${role}: no likely customer`);
  }
});

test('the Reject window tells staff their rejection does not protect the likely customer', async () => {
  await mount('staff');
  await openReject('ana.login@tests.invalid');
  assert.equal(note('reject-staff'), STAFF_NOTE('Ana Test'));
  assert.equal(note('reject-protects'), null, 'no promise of protection');
  await setValue(modal().querySelector('textarea'), 'Could not reach them');
  await click(button('Reject Claim'));
  assert.deepEqual(callsOf('reject_affiliate_account_claim').map(c => c.args), [{ p_claim_id: 'cl-ana', p_reason: 'Could not reach them' }]);
  // Nothing to say where the customer is protected already, or there is none.
  for (const email of ['rhea.login@tests.invalid', 'wyn.login@tests.invalid', 'nob.login@tests.invalid']) {
    await openReject(email);
    assert.equal(note('reject-staff'), null, email);
    assert.equal(note('reject-protects'), null, email);
    await click(button('Cancel', modal()));
  }
});

const rejectedIntro = () => [...document.querySelectorAll('p')].find(p => p.textContent.includes('A rejected request blocks'))?.textContent ?? '';
test('the Rejected list says a rejection by an Owner or Manager keeps protecting the likely customer after it is deleted', async () => {
  for (const role of ['staff', 'owner']) {
    await mount(role);
    assert.ok(rejectedIntro().includes('Delete it if you want them to be able to try again. A rejection by an Owner or Manager also protects the likely customer, even after it is deleted: only an Owner or Manager can then link a login to them. A rejection by staff does not.'), `${role}: ${rejectedIntro()}`);
  }
});

const PROTECT_EXPLAINS = name => `A member of staff rejected this claim, and a rejection by staff does not protect ${name}. Confirming it as an Owner or Manager does: afterwards staff cannot link any login to ${name}, and sign-up no longer links one to them automatically; only an Owner or Manager can. This stays even if the request is deleted later.`;
const rejectedBy = email => claimRow(email).querySelector('[data-rejected-by]')?.textContent.trim() ?? null;
const protectButtons = () => [...document.querySelectorAll('[data-action="protect"]')];

test('the Rejected list shows who rejected each claim', async () => {
  for (const role of ['staff', 'owner', 'manager']) {
    await mount(role);
    assert.deepEqual(['rea', 'sue', 'tia', 'rho', 'ria', 'ivo'].map(n => rejectedBy(`${n}.login@tests.invalid`)),
      ['by an Owner or Manager', 'by staff', 'by staff', 'by an Owner or Manager', 'by staff', 'by an Owner or Manager'], role);
  }
});

test('the Rejected list says which likely customers are protected, and that a staff rejection does not protect its likely customer', async () => {
  for (const role of ['staff', 'owner', 'manager']) {
    await mount(role);
    const notes = [...document.querySelectorAll('[data-note="staff-rejection"]')].map(n => n.textContent);
    assert.deepEqual(notes, ['Rejected by staff — does not protect Tia Test'], `${role}: only the staff rejection whose likely customer is not protected`);
    assert.ok(claimRow('tia.login@tests.invalid').querySelector('[data-note="staff-rejection"]'), `${role}: on Tia's row`);
    for (const email of ['rho.login@tests.invalid', 'ria.login@tests.invalid']) {
      const badge = claimRow(email).querySelector('[data-flag="customer-protected"]');
      assert.ok(badge, `${role}: ${email} shows Rhea protected`);
      assert.equal(badge.textContent, 'Protected');
      assert.equal(badge.getAttribute('title'), CUST_REJECTED);
    }
    for (const email of ['tia.login@tests.invalid', 'rea.login@tests.invalid', 'sue.login@tests.invalid', 'ivo.login@tests.invalid']) {
      absent(claimRow(email).querySelector('[data-flag="customer-protected"]'), `${role}: ${email} is not shown protected`);
    }
    // An Owner's or Manager's rejection is not called a staff one.
    absent(claimRow('ivo.login@tests.invalid').querySelector('[data-note="staff-rejection"]'), `${role}: not a staff rejection`);
    // A rejection that suggested no one says nothing about protection.
    absent(claimRow('sue.login@tests.invalid').querySelector('[data-note="staff-rejection"]'), `${role}: no likely customer, nothing to say`);
  }
});

test('staff have no Protect button', async () => {
  await mount('staff');
  assert.equal(protectButtons().length, 0);
  assert.ok(!text().includes('Protect Tia Test'));
});

test('an Owner or Manager can protect the likely customer of a staff rejection, with a reason', async () => {
  for (const role of ['owner', 'manager']) {
    await mount(role, b => { b.handlers.reject_affiliate_account_claim = () => ({ ok: true, taken_over: true }); });
    assert.deepEqual(protectButtons().map(b => b.textContent.trim()), ['Protect Tia Test'], `${role}: one Protect, on Tia's row`);
    assert.ok(claimRow('tia.login@tests.invalid').contains(protectButtons()[0]), role);
    const rejectedReads = callsOf('affiliate_rejected_claims').length;
    await click(protectButtons()[0]);
    const m = modal();
    assert.equal(m.querySelector('[data-note="protect-explains"]')?.textContent, PROTECT_EXPLAINS('Tia Test'), role);
    assert.ok(m.querySelector('[data-note="protect-yours"]')?.textContent.includes('The rejection becomes yours, so staff can no longer delete it. The staff member\'s reason stays, and yours is added below it unless it says the same.'), role);
    assert.ok(m.textContent.includes('by staff — “Could not reach her”'), `${role}: the staff rejection is shown`);
    const go = buttons(m).find(b => b.textContent.trim() === 'Protect Tia Test');
    assert.equal(go.disabled, true, `${role}: no reason, no protection`);
    await click(go);
    assert.equal(callsOf('reject_affiliate_account_claim').length, 0, `${role}: nothing sent without a reason`);
    await setValue(m.querySelector('#protect-reason'), '  Impostor: Tia made no account ');
    assert.equal(go.disabled, false, role);
    await click(go);
    assert.deepEqual(callsOf('reject_affiliate_account_claim').map(c => c.args),
      [{ p_claim_id: 'cl-tia', p_reason: 'Impostor: Tia made no account' }], role);
    absent(modal(), `${role}: the window closes`);
    assert.ok(text().includes('Tia Test is now protected: only an Owner or Manager can link a login to them.'), `${role}: ${text().slice(0, 400)}`);
    assert.ok(callsOf('affiliate_rejected_claims').length > rejectedReads, `${role}: the lists are read again`);
  }
});

test('a Protect the server answers "already rejected" stays in its window, with the server\'s words', async () => {
  await mount('owner', b => { b.handlers.reject_affiliate_account_claim = () =>
    ({ ok: false, already: true, message: 'This claim has already been rejected.' }); });
  await click(protectButtons()[0]);
  await setValue(modal().querySelector('#protect-reason'), 'Impostor');
  await click(buttons(modal()).find(b => b.textContent.trim() === 'Protect Tia Test'));
  assert.ok(modal(), 'the window stays open');
  assert.equal(modal().querySelector('[role="alert"]')?.textContent, 'This claim has already been rejected.');
  assert.ok(!text().includes('is now protected'));
});

test('before 379 is applied, the Rejected list says nothing about protection and offers no Protect', async () => {
  for (const role of ['owner', 'staff']) {
    await mount(role, b => b.fx.rejected.forEach(c => { delete c.suggested_customer_rejected; }));
    assert.ok(rejectedIntro().includes('Delete it if you want them to be able to try again.'), role);
    assert.ok(!rejectedIntro().includes('protects'), `${role}: no promise of protection: ${rejectedIntro()}`);
    absent(document.querySelector('[data-note="rejected-protects"]'), role);
    absent(document.querySelector('[data-note="staff-rejection"]'), `${role}: no "does not protect"`);
    absent(document.querySelector('[data-flag="customer-protected"]'), `${role}: no Protected badge`);
    assert.equal(protectButtons().length, 0, `${role}: no Protect`);
    // Who rejected each one is 378's, and still shown.
    assert.equal(rejectedBy('tia.login@tests.invalid'), 'by staff', role);
    assert.equal(rejectedBy('rho.login@tests.invalid'), 'by an Owner or Manager', role);
  }
});

test('before 379 is applied, the Reject window promises nothing about the customer', async () => {
  for (const role of ['owner', 'staff']) {
    await mount(role, b => b.fx.pending.forEach(c => { delete c.suggested_customer_rejected; }));
    absent(document.querySelector('[data-flag="customer-previously-rejected"]'), `${role}: no flag`);
    for (const email of ['ana.login@tests.invalid', 'nob.login@tests.invalid']) {
      await openReject(email);
      assert.equal(note('reject-protects'), null, `${role} ${email}`);
      assert.equal(note('reject-staff'), null, `${role} ${email}`);
      await click(button('Cancel', modal()));
    }
  }
});
