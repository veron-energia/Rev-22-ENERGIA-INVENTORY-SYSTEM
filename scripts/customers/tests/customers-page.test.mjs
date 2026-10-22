// The Customers page after 418, rendered for real against a fake backend.
//
// src/pages/CustomersPage.tsx is bundled with esbuild and mounted in jsdom.
// Only the Supabase client and the auth context are stubbed: the client by a
// small in-memory backend that records every call, can answer late, and can
// fail a call. Every name, phone and number is invented.
//
// It checks:
//   * CUSTOMERS-9: Add goes through create_customer_quick (one request id per
//     window, the same on a retry) and Edit through update_customer (only the
//     fields changed, with the updated_at read when Edit opened). The page
//     never writes the customers table. The date-of-birth rule (the Owner,
//     9 Oct 2026): staff fill in a missing date; one already filled in is
//     locked for them; an Owner or Manager changing it, or anyone changing
//     the phone, gives a reason. The fields are locked while the latest
//     details load; if they cannot be read, Save stays off until Retry reads
//     them (so the check for an older copy is never skipped). A second Save
//     after a lost answer that finds its own change saved closes the window.
//   * CUSTOMERS-13: opening another customer's View clears the wallet at
//     once, and a late answer for the customer opened before is dropped; an
//     older list answer arriving after a newer one is dropped.
//   * CUSTOMERS-14: a failed search and a failed View say so plainly, with
//     Retry; a database's own words are not shown to staff.
//   * CUSTOMERS-18: Opening balance and Adjust send one request id per
//     window, the same on a second Confirm.
//   * CUSTOMERS-19: phone history is read per customer when the Profile
//     opens, the icon buttons are labelled, dates are Singapore days
//     (dd/mm/yyyy), and Add says who already uses the phone.
//   * CUSTOMERS-11: the referrer picker (CustomerSearchSelect) also matches a
//     phone typed with spaces or +65 on its digits.
//   * Who edits customers (the Owner, 9 Oct 2026): an Inventory Manager sees
//     no Add, Edit, Change phone or Source, but still finds and views
//     customers; the old Admin role adds and edits, and its filled-in date
//     of birth stays locked, as for Staff. The Invoices page's Add a customer
//     (QuickCustomerModal) says the same and sends nothing.
//   * Who sees the full Profile (453, the Owner, 22 Oct 2026): Staff and the
//     old Admin role, as Owners and Managers, get the figures, the phone
//     history, the purchase timeline and the Downline (the Profile's button
//     and the row's); Delete, Deleted Customers and the credit Opening
//     balance and Adjust stay Owner/Manager. An Inventory Manager keeps the
//     Limited view and asks for none of it.
//
// Run: node --test scripts/customers/tests/customers-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://customers.invalid', pretendToBeVisual: true });
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
// The page writes a failed load's details to the console; the fixture's own
// failures say "(fixture)" and are not printed.
console.error = (...a) => { if (!/not wrapped in act|\(fixture\)/.test(String(a[0]))) consoleError(...a); };

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { default as CustomersPage } from './src/pages/CustomersPage';
      export { QuickCustomerModal } from './src/components/customers/QuickCustomerModal';
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
    b.onResolve({ filter: /^\.\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
  } }],
});
const { CustomersPage, QuickCustomerModal, MemoryRouter, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const customer = (id, first, last, phone, extra = {}) => ({
  id, full_name: `${first} ${last}`, first_name: first, last_name: last, phone, email: null, address: null, notes: null,
  is_active: true, created_at: '2026-07-01T00:00:00Z', updated_at: `2026-10-0${id.slice(-1)}T01:02:03.456789+00:00`,
  referred_by: null, is_referrer: false, date_of_birth: null, gender: null, gender_other: null, occupation: null,
  deleted_at: null, source_label: null, first_visit_on: null, total_count: 2, ...extra });
function makeFixture() {
  return {
    customers: [
      customer('c-1', 'Ada', 'Tan', '+6591418501'),
      customer('c-2', 'Ben', 'Lee', '+6591418502', { date_of_birth: '1980-05-06' }),
    ],
    phones: [
      { customer_id: 'c-1', phone: '+6591418599', reason: 'New number', created_at: '2026-10-08T17:30:00+00:00' },
      { customer_id: 'c-2', phone: '+6591418598', reason: 'Other customer', created_at: '2026-09-01T00:00:00+00:00' },
    ],
    stores: [{ id: 's-1', name: 'Fixture Store', deleted_at: null }],
  };
}

function createBackend(fx) {
  // failures: name -> a message, an error object ({ message, code }), or a
  // function of the arguments. gates: name -> a promise the call waits for.
  const b = { calls: [], handlers: {}, failures: new Map(), gates: new Map(), fx };
  const rpcs = {
    search_customers: () => fx.customers,
    active_customer_source_options: () => [],
    customer_overview: a => ({ affiliate_state: { state: 'none' }, refunds: [], purchased_therapy: [], legacy_therapy: [],
                               deleted_invoices: [], _for: a.p_customer_id }),
    customer_credit_balances: a => ({ available_total: a.p_customer_id === 'c-1' ? 111 : 222, categories: {} }),
    customer_credit_statement: () => [],
    customer_profile_stats: () => ({ purchases: 0, total_spend: 0, referred_count: 0, referrer_name: null }),
    customer_purchase_timeline: () => [],
    customer_downline_visits: a => ({ customer_id: a.p_customer_id, name: 'Ada Tan', phone: '+6591418501', tier1: [], tier2: [] }),
    customer_match_candidates: () => ({ candidates: [{ id: 'c-1', full_name: 'Ada Tan', phone_tail: '8501', name_matches: false }],
                                        used: 1, remaining: 2 }),
    create_customer_quick: a => ({ customer_id: 'c-new', full_name: `${a.p_first_name} ${a.p_last_name ?? ''}`.trim(), replayed: false }),
    update_customer: a => ({ customer_id: a.p_customer_id, changed: Object.keys(a.p_changes) }),
    add_legacy_credit: () => 'lot-1',
    adjust_customer_credit: () => 'adj-1',
    customer_stock_loans: () => [],
  };
  const tables = () => ({ stores: fx.stores, customer_phone_history: fx.phones, customers: fx.customers });
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], single: false, ors: [], write: null }); }
    select() { return this; }
    eq(c, v) { this.filters.push([c, v]); return this; }
    is(c, v) { this.filters.push([c, v]); return this; }
    in() { return this; }
    or(f) { this.ors.push(f); return this; }
    order() { return this; }
    limit() { return this; }
    range() { return this; }
    maybeSingle() { this.single = true; return this; }
    single() { this.single = true; return this; }
    insert(v) { this.write = ['insert', v]; return this; }
    update(v) { this.write = ['update', v]; return this; }
    upsert(v) { this.write = ['upsert', v]; return this; }
    delete() { this.write = ['delete']; return this; }
    async exec() {
      const call = { kind: this.kind, name: this.name, args: this.args, filters: this.filters, ors: this.ors, write: this.write };
      b.calls.push(call);
      await Promise.resolve();
      if (b.gates.has(this.name)) await b.gates.get(this.name);
      if (b.failures.has(this.name)) {
        const f = b.failures.get(this.name);
        if (typeof f === 'function' ? f(this.args) : true) {
          return { data: null, error: typeof f === 'object' ? { ...f }
            : { message: typeof f === 'string' ? f : `${this.name} failed (fixture)` } };
        }
      }
      if (this.write) return { data: null, error: { message: 'permission denied for table ' + this.name } };
      if (this.kind === 'rpc') {
        const fn = b.handlers[this.name] ?? rpcs[this.name];
        if (!fn) return { data: null, error: { message: `unknown rpc ${this.name}` } };
        return { data: structuredClone(await fn(this.args)), error: null };
      }
      let rows = (tables()[this.name] ?? []).filter(r => this.filters.every(([c, v]) => (r[c] ?? null) === v));
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
  invman: { id: 'u-inv', full_name: 'Inventory One', role: 'inventory_manager', is_active: true },
  admin: { id: 'u-adm', full_name: 'Admin One', role: 'admin', is_active: true },
};
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
const wait = async ms => { await act(async () => { await new Promise(r => setTimeout(r, ms)); }); await tick(); };
async function mount(role, setup) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(makeFixture());
  globalThis.__backend = backend; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: USERS[role], signOut: async () => {} };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null,
    React.createElement(MemoryRouter, null, React.createElement(CustomersPage)))));
  await tick();
  await wait(320);
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
const writes = () => backend.calls.filter(c => c.write);
const field = (label, scope = modal()) => {
  const group = [...scope.querySelectorAll('.form-group')].find(g => g.querySelector('label')?.textContent.trim().startsWith(label));
  return group?.querySelector('input, select, textarea');
};
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── list ───────────────────────────────────────────────────────────────────
test('the list does not read every phone history, and labels its icon buttons', async () => {
  await mount('manager');
  assert.deepEqual(globalThis.__renderErrors, []);
  assert.equal(callsOf('customer_phone_history').length, 0, 'no phone history on a list load');
  const r = row('Ada Tan');
  assert.ok(r.querySelector('button[aria-label="Edit customer"][title="Edit customer"]'), 'Edit has a label');
  assert.ok(r.querySelector('button[aria-label="Change phone"]'), 'Change phone has a label');
  assert.ok(r.querySelector('button[aria-label="Delete customer"]'), 'Delete has a label');
});

test('an Inventory Manager finds and views customers but is offered no Add, Edit, Change phone or Source', async () => {
  await mount('invman');
  assert.deepEqual(globalThis.__renderErrors, []);
  const r = row('Ada Tan');
  assert.ok(r, 'the list shows');
  assert.ok(button('View', r) && button('Profile', r), 'View and Profile are offered');
  assert.ok(!button('Add Customer'), 'no Add Customer');
  assert.ok(!r.querySelector('button[aria-label="Edit customer"]'), 'no Edit');
  assert.ok(!r.querySelector('button[aria-label="Change phone"]'), 'no Change phone');
  assert.ok(!button('Source', r), 'no Source');
  assert.ok(!r.querySelector('button[aria-label="Delete customer"]'), 'no Delete');
  await click(button('View', r));
  assert.ok(modal().textContent.includes('Ada Tan'), 'View opens');
  assert.equal(writes().length, 0);
  assert.equal(callsOf('update_customer').length + callsOf('create_customer_quick').length + callsOf('change_customer_phone').length, 0);
});

test('the old Admin role adds and edits customers; a filled-in date of birth stays locked for it', async () => {
  await mount('admin');
  const r = row('Ben Lee');
  assert.ok(button('Add Customer') && r.querySelector('button[aria-label="Edit customer"]') && r.querySelector('button[aria-label="Change phone"]'),
            'Add, Edit and Change phone are offered');
  await click(r.querySelector('button[aria-label="Edit customer"]'));
  await tick();
  assert.equal(field('Date of Birth').disabled, true, 'an Admin cannot change a filled-in date of birth');
});

test('the Invoices page\'s Add a customer tells an Inventory Manager to pick one, and sends nothing', async () => {
  for (const [role, mayAdd] of [['invman', false], ['staff', true]]) {
    if (root) await act(async () => root.unmount());
    document.body.innerHTML = '<div id="root"></div>';
    backend = createBackend(makeFixture());
    globalThis.__backend = backend; globalThis.__renderErrors = [];
    globalThis.__auth = { profile: USERS[role], signOut: async () => {} };
    const created = [];
    root = createRoot(document.getElementById('root'));
    await act(async () => root.render(React.createElement(ErrorBoundary, null,
      React.createElement(QuickCustomerModal, { initialName: 'Cara', onCreated: id => created.push(id), onPickedExisting: () => {}, onClose: () => {} }))));
    await tick();
    const dialog = document.querySelector('.quick-customer');
    const add = button('Add customer', dialog);
    assert.equal(dialog.textContent.includes('Only Owners, Managers and Staff can add or change customers'), !mayAdd, role);
    assert.equal(add.disabled, !mayAdd, role + ': Add customer enabled');
    if (mayAdd) {
      await setValue(dialog.querySelector('input:not([type])'), 'Cara');
      const phone = dialog.querySelector('.qc-field input[type="tel"], .qc-field input[inputmode="tel"]') || [...dialog.querySelectorAll('input')][2];
      await setValue(phone, '+6591418561');
      await click(add);
      assert.equal(callsOf('create_customer_quick').length, 1, 'staff add a customer');
    } else {
      await click(add);
      assert.equal(callsOf('create_customer_quick').length, 0, 'an Inventory Manager sends nothing');
    }
  }
});

test('a failed search says so plainly with Retry, not "No customers yet"; Retry loads the list', async () => {
  await mount('staff', b => b.failures.set('search_customers', { message: 'canceling statement due to statement timeout (fixture)', code: '57014' }));
  assert.ok(text().includes('The customer list could not be loaded.') && text().includes('Please try again. If it keeps failing, tell the Owner.'),
            text().slice(0, 300));
  assert.ok(!text().includes('canceling statement'), 'the database\'s own words are not shown to staff');
  assert.ok(!text().includes('No customers yet'));
  backend.failures.delete('search_customers');
  await click(button('Retry'));
  assert.ok(row('Ada Tan'), 'the list after Retry');
});

test('a list refused by the app\'s own check shows its plain message; a table refusal does not', async () => {
  await mount('staff', b => b.failures.set('search_customers', { message: 'Only active Energia staff can do this.', code: '42501' }));
  assert.ok(text().includes('Only active Energia staff can do this.'), text().slice(0, 300));
  await mount('staff', b => b.failures.set('search_customers', { message: 'permission denied for table customers (fixture)', code: '42501' }));
  assert.ok(!text().includes('permission denied') && text().includes('Please try again.'), text().slice(0, 300));
});

test('an older list answer that arrives after a newer one is dropped', async () => {
  await mount('staff');
  // The next search ("Ada") answers late; the one after it ("Ben") at once.
  let release;
  backend.handlers.search_customers = a => (a.p_query === 'Ada'
    ? new Promise(r => { release = () => r([backend.fx.customers[0]]); })
    : a.p_query === 'Ben' ? [backend.fx.customers[1]] : backend.fx.customers);
  const box = document.querySelector('input[placeholder^="Search name"]');
  await setValue(box, 'Ada');
  await wait(320);
  await setValue(box, 'Ben');
  await wait(320);
  assert.ok(row('Ben Lee') && !row('Ada Tan'), 'the newer search shows');
  await act(async () => release());
  await tick();
  assert.ok(row('Ben Lee') && !row('Ada Tan'), 'the late, older answer did not replace it');
});

// ── View ───────────────────────────────────────────────────────────────────
test('View: another customer\'s wallet is cleared at once, and a late answer for them is dropped', async () => {
  await mount('manager');
  let releaseA;
  backend.handlers.customer_credit_balances = a => (a.p_customer_id === 'c-1'
    ? new Promise(r => { releaseA = () => r({ available_total: 111, categories: {} }); })
    : { available_total: 222, categories: {} });
  await click(button('View', row('Ada Tan')));
  assert.ok(releaseA, 'Ada\'s balance is being read');
  await click(button('Close', modal()));
  backend.handlers.customer_credit_balances = a => (a.p_customer_id === 'c-1' ? { available_total: 111, categories: {} }
    : new Promise(() => {}));            // Ben's balance never arrives
  await click(button('View', row('Ben Lee')));
  await act(async () => releaseA());     // Ada's answer arrives now, late
  await tick();
  assert.ok(modal().textContent.includes('Ben Lee'));
  assert.ok(!modal().textContent.includes('111.00'), 'Ada\'s wallet shows under Ben');
});

test('View: a customer opened after another never shows the first one\'s wallet', async () => {
  await mount('manager');
  await click(button('View', row('Ada Tan')));
  assert.ok(modal().textContent.includes('S$111.00'), 'Ada\'s wallet');
  await click(button('Close', modal()));
  // Ben's View arrives; his wallet does not (yet).
  backend.handlers.customer_credit_balances = a => (a.p_customer_id === 'c-2' ? new Promise(() => {}) : { available_total: 111, categories: {} });
  await click(button('View', row('Ben Lee')));
  assert.ok(modal().textContent.includes('Affiliate'), 'Ben\'s View is shown');
  assert.ok(!modal().textContent.includes('111.00'), 'Ada\'s wallet shows under Ben: ' + modal().textContent);
});

test('View (443): the wallet by source, each with its Paid and Bonus, and each package or bundle bought with what is left (used up too; credit moved in says so)', async () => {
  await mount('manager');
  backend.handlers.customer_credit_balances = a => ({
    customer_id: a.p_customer_id, available_total: 1872,
    categories: { paid: 1570, bonus: 170, legacy: 105, promotional: 15, exchange: 12 },
    sources: {
      credit_package: { paid: 1000, bonus: 100, legacy: 0, promotional: 0, exchange: 0, total: 1100 },
      premium_bundle: { paid: 500, bonus: 50, legacy: 45, promotional: 0, exchange: 0, total: 595 },
      other: { paid: 70, bonus: 20, legacy: 60, promotional: 15, exchange: 12, total: 177 },
    },
    purchases: [
      { source: 'credit_package', name: 'Fixture Package', invoice_no: 'INV-2026-0901', bought_on: '2026-10-21', paid: 1000, bonus: 100, legacy: 0, total: 1100 },
      { source: 'credit_package', name: 'Fixture Package', invoice_no: 'INV-2026-0903', bought_on: '2026-10-22', paid: 0, bonus: 0, legacy: 0, total: 0 },
      { source: 'credit_package', name: 'Fixture Package', invoice_no: 'INV-2026-0904', bought_on: '2026-10-23', paid: 40, bonus: 0, legacy: 0, total: 40, received: true },
      { source: 'premium_bundle', name: 'Fixture Bundle', invoice_no: 'INV-2026-0902', bought_on: '2026-10-21', paid: 500, bonus: 50, legacy: 45, total: 595 },
    ],
  });
  await click(button('View', row('Ada Tan')));
  const bySource = modal().querySelector('[data-testid="credit-by-source"]');
  assert.ok(bySource, 'the wallet by source: ' + modal().textContent);
  const t = bySource.textContent;
  assert.ok(t.includes('Credit Package') && t.includes('S$1100.00') && t.includes('Paid S$1000.00 · Bonus S$100.00'), t);
  assert.ok(t.includes('Premium Bundle') && t.includes('S$595.00') && t.includes('Paid S$500.00 · Bonus S$50.00 · Legacy S$45.00'), t);
  assert.ok(t.includes('Other') && t.includes('S$177.00') && t.includes('Paid S$70.00 · Bonus S$20.00 · Legacy S$60.00 · Promotional S$15.00 · Exchange S$12.00'), t);
  const bought = modal().querySelector('[data-testid="credit-purchases"]').textContent;
  assert.ok(bought.includes('Credit Package bought') && bought.includes('Fixture Package · INV-2026-0901 · 21/10/2026')
    && bought.includes('S$1100.00 left'), bought);
  assert.ok(bought.includes('Premium Bundle bought') && bought.includes('Fixture Bundle · INV-2026-0902')
    && bought.includes('(Paid S$500.00 · Bonus S$50.00 · Legacy S$45.00)'), bought);
  // One used up is still listed, at S$0.00; credit moved in from another
  // customer's purchase says so.
  const rows = [...modal().querySelectorAll('[data-testid="credit-purchases"] > div > div')].map(d => d.textContent);
  assert.ok(rows.some(r => r.includes('INV-2026-0903') && r.includes('S$0.00 left') && !r.includes('received')), rows.join(' | '));
  assert.ok(rows.some(r => r.includes('INV-2026-0904 · 23/10/2026 · received from another customer') && r.includes('S$40.00 left')), rows.join(' | '));
  assert.ok(!rows.some(r => r.includes('INV-2026-0901') && r.includes('received')), 'one bought here is not "received"');
  assert.ok(modal().textContent.includes('S$1872.00'), 'the total, as before');
});

test('View (before 443): a balance with no sources shows the categories as before', async () => {
  await mount('manager');
  backend.handlers.customer_credit_balances = () => ({ available_total: 350, categories: { paid: 300, bonus: 50 } });
  await click(button('View', row('Ada Tan')));
  assert.ok(!modal().querySelector('[data-testid="credit-by-source"]') && !modal().querySelector('[data-testid="credit-purchases"]'));
  assert.ok(modal().textContent.includes('S$300.00') && modal().textContent.includes('S$50.00'), modal().textContent);
});

test('View: a failed load says so with Retry instead of "Loading…" for ever', async () => {
  await mount('manager', b => b.failures.set('customer_overview', 'customer_overview failed (fixture)'));
  await click(button('View', row('Ada Tan')));
  assert.ok(modal().textContent.includes('This customer could not be loaded') && !modal().textContent.includes('Loading…'), modal().textContent);
  assert.ok(modal().textContent.includes('Please try again') && !modal().textContent.includes('(fixture)'), 'plain words: ' + modal().textContent);
  backend.failures.delete('customer_overview');
  await click(button('Retry', modal()));
  assert.ok(modal().textContent.includes('Credit wallet'), 'loaded after Retry');
});

// ── credit windows ─────────────────────────────────────────────────────────
test('Opening balance and Adjust send one request id per window, the same on a second Confirm', async () => {
  await mount('manager');
  await click(button('View', row('Ada Tan')));
  await click(button('Opening balance', modal()));
  backend.failures.set('add_legacy_credit', 'the answer was lost (fixture)');
  await click(button('Confirm', modal()));
  backend.failures.delete('add_legacy_credit');
  await click(button('Confirm', modal()));
  const [first, second] = callsOf('add_legacy_credit').map(c => c.args);
  assert.match(first.p_request_id, /^[0-9a-f-]{36}$/);
  assert.equal(second.p_request_id, first.p_request_id, 'the retry carries the same request id');
  assert.ok(!('p_approved_by' in first), 'no approver is sent');
  await click(button('Adjust', modal()));
  await click(button('Confirm', modal()));
  const adj = callsOf('adjust_customer_credit').pop().args;
  assert.match(adj.p_request_id, /^[0-9a-f-]{36}$/);
  assert.notEqual(adj.p_request_id, first.p_request_id, 'a new window, a new request id');
});

// ── Add ────────────────────────────────────────────────────────────────────
test('Add goes through create_customer_quick with one request id, says who uses the phone, and writes no table', async () => {
  await mount('staff');
  await click(button('Add Customer'));
  await setValue(field('First Name'), 'Cara');
  await setValue(field('Last Name'), 'Ng');
  await setValue(modal().querySelector('input[type="tel"]'), '9141 8501');
  await wait(450);
  assert.ok(modal().textContent.includes('1 of 3 customers already use this number') && modal().textContent.includes('Ada Tan'), modal().textContent);
  assert.ok(!modal().textContent.includes('Active'), 'a new customer starts active');
  await setValue(field('Date of Birth'), '1999-09-09');
  backend.failures.set('create_customer_quick', 'the answer was lost (fixture)');
  await click(button('Save', modal()));
  backend.failures.delete('create_customer_quick');
  await click(button('Save'));
  const [first, second] = callsOf('create_customer_quick').map(c => c.args);
  assert.equal(first.p_phone, '+6591418501');
  assert.equal(first.p_date_of_birth, '1999-09-09');
  assert.match(first.p_request_id, /^[0-9a-f-]{36}$/);
  assert.equal(second.p_request_id, first.p_request_id, 'the retry carries the same request id');
  assert.equal(modal(), undefined, 'closed after saving');
  assert.deepEqual(writes(), [], 'the customers table is never written');
});

// ── Edit ───────────────────────────────────────────────────────────────────
test('Edit reads the row, then sends only what changed, with its updated_at, to update_customer', async () => {
  await mount('staff');
  await click(row('Ada Tan').querySelector('button[aria-label="Edit customer"]'));
  const read = backend.calls.find(c => c.kind === 'table' && c.name === 'customers' && c.filters.some(([k, v]) => k === 'id' && v === 'c-1'));
  assert.ok(read, 'the row is read again when Edit opens');
  await setValue(field('Occupation'), 'Teacher');
  await setValue(field('Date of Birth'), '1991-02-03');      // a missing date: staff may fill it in
  await click(button('Save', modal()));
  const call = callsOf('update_customer').pop();
  assert.deepEqual(call.args, { p_customer_id: 'c-1', p_changes: { occupation: 'Teacher', date_of_birth: '1991-02-03' },
                                p_reason: null, p_expected_updated_at: '2026-10-01T01:02:03.456789+00:00' });
  assert.deepEqual(writes(), [], 'the customers table is never written');
});

test('Edit with no change saves nothing; a stale copy is explained', async () => {
  await mount('staff');
  await click(row('Ada Tan').querySelector('button[aria-label="Edit customer"]'));
  await click(button('Save', modal()));
  assert.equal(callsOf('update_customer').length, 0, 'nothing to save');
  await click(row('Ada Tan').querySelector('button[aria-label="Edit customer"]'));
  backend.failures.set('update_customer', 'STALE_CUSTOMER: Someone else changed this customer after you opened it. Close this window and open it again.');
  await setValue(field('Notes'), 'Prefers mornings');
  await click(button('Save', modal()));
  assert.ok(modal().textContent.includes('This customer was changed after you opened it. Close this window and open it again.'), modal().textContent);
  assert.ok(!modal().textContent.includes('STALE_CUSTOMER'), 'the code word is not shown');
});

test('Edit: after a lost answer, a second Save that finds its own change already saved closes the window', async () => {
  await mount('staff');
  await click(row('Ada Tan').querySelector('button[aria-label="Edit customer"]'));
  await setValue(field('Notes'), 'Prefers mornings');
  backend.failures.set('update_customer', 'Failed to fetch (fixture)');
  await click(button('Save', modal()));
  assert.ok(modal(), 'still open after the lost answer');
  // The first Save did reach the database: the row holds the note and a new updated_at.
  Object.assign(backend.fx.customers[0], { notes: 'Prefers mornings', updated_at: '2026-10-09T09:00:00.000000+00:00' });
  backend.failures.set('update_customer', 'STALE_CUSTOMER: Someone else changed this customer after you opened it. Close this window and open it again.');
  await click(button('Save', modal()));
  const [first, second] = callsOf('update_customer').map(c => c.args);
  assert.equal(second.p_expected_updated_at, first.p_expected_updated_at, 'the same copy both times');
  assert.ok(!modal(), 'treated as saved, not as someone else\'s change: ' + (modal()?.querySelector('.alert')?.textContent ?? ''));
});

test('Edit: if the latest details cannot be read, nothing can be saved until Retry reads them', async () => {
  await mount('staff', b => b.failures.set('customers', { message: 'Failed to fetch (fixture)' }));
  await click(row('Ada Tan').querySelector('button[aria-label="Edit customer"]'));
  assert.ok(modal().textContent.includes('This customer could not be loaded.') && modal().textContent.includes('Please try again'), modal().textContent);
  assert.ok(!modal().textContent.includes('(fixture)'), 'plain words');
  assert.ok(button('Save', modal()).disabled, 'Save is off without the latest details');
  assert.ok(field('Notes').matches(':disabled'), 'the fields are locked');
  assert.equal(callsOf('update_customer').length, 0);
  backend.failures.delete('customers');
  await click(button('Retry', modal()));
  assert.ok(!button('Save', modal()).disabled && !field('Notes').matches(':disabled'), 'Retry read the details');
  assert.ok(!modal().textContent.includes('could not be loaded'));
  await setValue(field('Notes'), 'Prefers mornings');
  await click(button('Save', modal()));
  assert.equal(callsOf('update_customer').pop().args.p_expected_updated_at, '2026-10-01T01:02:03.456789+00:00');
});

test('Edit: the fields are locked while the latest details load, so nothing typed is lost', async () => {
  let release;
  await mount('staff');
  backend.gates.set('customers', new Promise(r => { release = r; }));
  await click(row('Ada Tan').querySelector('button[aria-label="Edit customer"]'));
  assert.ok(modal().textContent.includes('Loading the latest details'));
  assert.ok(field('Occupation').matches(':disabled') && field('First Name').matches(':disabled'), 'locked while loading');
  assert.ok(button('Save', modal()).disabled);
  backend.gates.delete('customers');
  await act(async () => release());
  await tick();
  assert.ok(!field('Occupation').matches(':disabled'), 'unlocked once loaded');
  assert.equal(document.activeElement, field('First Name'), 'First Name takes the cursor once loaded');
  await setValue(field('Occupation'), 'Teacher');
  await tick();
  assert.equal(field('Occupation').value, 'Teacher');
});

test('a date of birth already filled in is locked for staff, and an Owner or Manager changing it gives a reason', async () => {
  await mount('staff');
  await click(row('Ben Lee').querySelector('button[aria-label="Edit customer"]'));
  assert.ok(field('Date of Birth').disabled, 'staff cannot change a filled-in date');
  assert.ok(modal().textContent.includes('Only an Owner or Manager can change a date of birth that is already filled in'));

  await mount('manager');
  await click(row('Ben Lee').querySelector('button[aria-label="Edit customer"]'));
  assert.ok(!field('Date of Birth').disabled);
  assert.ok(!modal().textContent.includes('Reason for this change'), 'no reason asked before a change');
  await setValue(field('Date of Birth'), '1980-05-07');
  assert.ok(modal().textContent.includes('Reason for this change'), 'a reason is asked');
  await click(button('Save', modal()));
  assert.equal(callsOf('update_customer').length, 0, 'not sent without a reason');
  assert.ok(modal().textContent.includes('Give a reason for changing the date of birth'));
  await setValue(modal().querySelector('#edit-reason'), 'Customer showed her IC');
  await click(button('Save', modal()));
  assert.deepEqual(callsOf('update_customer').pop().args.p_changes, { date_of_birth: '1980-05-07' });
  assert.equal(callsOf('update_customer').pop().args.p_reason, 'Customer showed her IC');
});

test('a phone change in Edit asks for a reason and says who already uses the new number', async () => {
  await mount('staff');
  await click(row('Ben Lee').querySelector('button[aria-label="Edit customer"]'));
  await setValue(modal().querySelector('input[type="tel"]'), '9141 8501');
  await wait(450);
  assert.ok(modal().textContent.includes('Ada Tan'), 'who already uses the number');
  await click(button('Save', modal()));
  assert.ok(modal().textContent.includes('Give a reason for the new phone number'));
  await setValue(modal().querySelector('#edit-reason'), 'New number');
  await click(button('Save', modal()));
  const args = callsOf('update_customer').pop().args;
  assert.deepEqual(args.p_changes, { phone: '+6591418501' });
  assert.equal(args.p_reason, 'New number');
});

// ── Profile ────────────────────────────────────────────────────────────────
test('Profile reads that customer\'s phone history only, with Singapore dates', async () => {
  await mount('manager');
  await click(button('Profile', row('Ada Tan')));
  const reads = callsOf('customer_phone_history');
  assert.equal(reads.length, 1);
  assert.deepEqual(reads[0].filters, [['customer_id', 'c-1']]);
  // 17:30 on 8 Oct in UTC is 01:30 on 9 Oct in Singapore.
  assert.ok(modal().textContent.includes('New number · 09/10/2026'), modal().textContent);
  assert.ok(!modal().textContent.includes('+6591418598'), 'another customer\'s old number');
  await click(button('Close', modal()));
  await click(button('Profile', row('Ben Lee')));
  assert.ok(modal().textContent.includes('DOB: 06/05/1980'), 'the date of birth, dd/mm/yyyy');
});

test('453: Staff and the old Admin role see the full Profile and the Downline; Delete, Deleted Customers and credit Adjust stay Owner/Manager', async () => {
  for (const role of ['staff', 'admin']) {
    await mount(role, b => {
      b.handlers.customer_profile_stats = () => ({ purchases: 1, total_spend: 30, referred_count: 2, referrer_name: 'Ben Lee' });
      b.handlers.customer_purchase_timeline = () => [{ invoice_id: 'i-1', invoice_no: 'INV-T453', date: '2026-10-01T02:00:00Z', status: 'paid',
        store: 'Fixture Store', total: 30, paid: 30, is_topup: false, save_earth: 0,
        items: [{ kind: 'voucher', name: 'Fixture Voucher', qty: 1, unit_price: 30, line_total: 30, price_mode: null }] }];
    });
    assert.deepEqual(globalThis.__renderErrors, [], role);
    await click(button('Profile', row('Ada Tan')));
    assert.deepEqual(callsOf('customer_profile_stats').map(c => c.args), [{ p_customer_id: 'c-1' }], role + ': the figures are read');
    assert.deepEqual(callsOf('customer_purchase_timeline').map(c => c.args), [{ p_customer_id: 'c-1' }], role + ': the timeline is read');
    assert.equal(callsOf('customer_phone_history').length, 1, role + ': the phone history is read');
    const m = modal();
    for (const s of ['Paid purchases', 'Total spend', 'S$30.00', 'Customers referred', 'Referred by', 'Ben Lee',
                     'Phone history', 'New number · 09/10/2026', 'Purchase timeline', 'INV-T453']) {
      assert.ok(m.textContent.includes(s), `${role}: the Profile shows ${s}`);
    }
    assert.ok(!m.textContent.includes('Limited view'), role + ': no Limited view note');
    await click(button('Downline', m));
    assert.deepEqual(callsOf('customer_downline_visits').map(c => c.args), [{ p_customer_id: 'c-1' }], role + ': the Profile\'s Downline');
    assert.ok(modal().textContent.includes('Downline — Ada Tan'), role);
    await click(button('Close', modal()));
    await click(button('Close', modal()));
    await click(row('Ben Lee').querySelector('button[aria-label="Downline of Ben Lee"]'));
    assert.deepEqual(callsOf('customer_downline_visits').map(c => c.args).pop(), { p_customer_id: 'c-2' }, role + ': the row\'s Downline');
    await click(button('Close', modal()));
    // Still the Owner's and Manager's.
    assert.ok(!button('Deleted Customers'), role + ': no Deleted Customers');
    assert.ok(!row('Ada Tan').querySelector('button[aria-label="Delete customer"]'), role + ': no Delete');
    await click(button('View', row('Ada Tan')));
    assert.ok(modal().textContent.includes('Credit wallet'), role + ': View opens');
    assert.ok(!button('Opening balance', modal()) && !button('Adjust', modal()), role + ': no Opening balance or Adjust');
  }
});

test('453: an Inventory Manager keeps the Limited view: no figures, phone history, timeline or Downline, and none is asked for', async () => {
  await mount('invman');
  assert.ok(!document.querySelector('button[aria-label^="Downline of"]'), 'no row Downline');
  await click(button('Profile', row('Ada Tan')));
  assert.equal(callsOf('customer_profile_stats').length + callsOf('customer_purchase_timeline').length
               + callsOf('customer_phone_history').length + callsOf('customer_downline_visits').length, 0, 'nothing is asked for');
  const m = modal();
  assert.ok(m.textContent.includes('Limited view — purchases, spend, phone history and the downline are visible to Owners, Admins, Managers and Staff.'),
            m.textContent);
  for (const s of ['Paid purchases', 'Total spend', 'Phone history', 'Purchase timeline', 'No purchases yet']) {
    assert.ok(!m.textContent.includes(s), 'no ' + s);
  }
  assert.ok(!button('Downline', m), 'no Downline in the Profile');
  assert.ok(m.textContent.includes('Phone: +6591418501'), 'the contact details still show');
});

// ── the referrer picker ────────────────────────────────────────────────────
test('the referrer picker matches a phone typed with spaces or +65 on its digits', async () => {
  await mount('staff');
  await click(button('Add Customer'));
  const picker = [...modal().querySelectorAll('.form-group')].find(g => g.querySelector('label')?.textContent.startsWith('Referred by'));
  await click(picker.querySelector('button'));
  await setValue(picker.querySelector('input'), '+65 9141 8501');
  await wait(260);
  const q = backend.calls.filter(c => c.kind === 'table' && c.name === 'customers' && c.ors.length).pop();
  assert.ok(q, 'the picker searched');
  assert.ok(q.ors[0].includes('phone.ilike.%6591418501%') && q.ors[0].includes('phone.ilike.%91418501%'), q.ors[0]);
  await setValue(picker.querySelector('input'), 'Ada 2');
  await wait(260);
  const q2 = backend.calls.filter(c => c.kind === 'table' && c.name === 'customers' && c.ors.length).pop();
  assert.equal(q2.ors[0].split('phone.ilike.').length - 1, 1, 'a name search adds no digit match: ' + q2.ors[0]);
});
