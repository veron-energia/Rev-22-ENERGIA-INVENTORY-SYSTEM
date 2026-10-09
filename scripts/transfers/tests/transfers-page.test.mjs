// The Transfers page with 421, rendered for real against a fake backend.
//
// The actual src/pages/TransfersPage.tsx is bundled with esbuild and mounted in
// jsdom. Only the Supabase client and the auth context are stubbed: the client
// by a small in-memory backend that records every call. Every name, number and
// id below is invented (TFX fixtures).
//
// It checks that:
//   * staff at two stores must choose the store a request is for, and staff
//     at one store are not asked (STOCK-1); the page no longer reads
//     my_assigned_store_id;
//   * a rejected transfer reads "Rejected by ... : reason", not "Approved by"
//     (STOCK-9);
//   * Owners and Managers see Cancel on someone else's pending request, with a
//     confirmation naming the requester; staff see it only on their own
//     (STOCK-14 item 3);
//   * Receive has a reason box on each line that differs, sends it, and its
//     helper button ("Fill approved", short enough for a phone) only fills in
//     the approved quantities, the figure the mismatch check uses (STOCK-14
//     item 1);
//   * an edit sends the note as typed, so an empty note clears it (item 2);
//   * Receive and Resolve show where each line was sent from; Resolve names
//     that place on "Correct source" and "Return excess", leaves both out for
//     a line sent from several places, and never offers the linked adjustment
//     on extra units (STOCK-M2); Resolve & Complete waits for the sources, and
//     a choice the line no longer offers is neither sent nor swapped for
//     another: the person is asked to choose again.
//
// Run: node --test scripts/transfers/tests/transfers-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ── the page, bundled ──────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://transfers.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
const confirms = [];
let confirmAnswer = true;
dom.window.confirm = m => { confirms.push(String(m)); return confirmAnswer; };
globalThis.confirm = dom.window.confirm;
const alerts = [];
dom.window.alert = m => alerts.push(String(m));
globalThis.alert = dom.window.alert;
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
      export { default as TransfersPage } from './src/pages/TransfersPage';
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
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };` }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
  } }],
});
const { TransfersPage, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const PEOPLE = {
  owner: { id: 'u-own', full_name: 'TFX Owner', role: 'owner', is_active: true },
  staff2: { id: 'u-s2', full_name: 'TFX Staff Two', role: 'staff', is_active: true },
  staff1: { id: 'u-s1', full_name: 'TFX Staff One', role: 'staff', is_active: true },
};
const at = '2026-10-08T03:00:00Z';
const req = (id, o) => ({ id, transfer_type: 'warehouse_to_store', source_type: 'warehouse', source_id: 'w1', dest_type: 'store', dest_id: 'sa',
  status: 'pending', note: null, rejection_reason: null, requested_by: 'u-own', approved_by: null, created_at: at, approved_at: null,
  completed_at: null, version: 1, edit_count: 0, dispatched_at: null, received_at: null, ...o });
const line = (id, request, product, o) => ({ id, transfer_request_id: request, line_kind: 'product', product_id: product, quantity: 5,
  approved_quantity: null, in_transit_quantity: null, received_quantity: null, discrepancy_quantity: null, discrepancy_resolved_at: null,
  discrepancy_resolution: null, created_at: at, ...o });
function makeFixture() {
  return {
    warehouses: [{ id: 'w1', name: 'TFX WH 1', is_active: true, deleted_at: null }, { id: 'w2', name: 'TFX WH 2', is_active: true, deleted_at: null }],
    stores: [{ id: 'sa', name: 'TFX Store A', is_active: true, deleted_at: null }, { id: 'sb', name: 'TFX Store B', is_active: true, deleted_at: null }],
    products: [{ id: 'p1', name: 'TFX Pillow', sku: 'TFX-P', is_active: true, deleted_at: null },
               { id: 'p2', name: 'TFX Mat', sku: 'TFX-M', is_active: true, deleted_at: null }],
    prices: ['sa', 'sb'].flatMap(s => ['p1', 'p2'].map(p => ({ store_id: s, product_id: p, is_active: true, deleted_at: null }))),
    profiles: Object.values(PEOPLE).map(({ id, full_name }) => ({ id, full_name })),
    requests: [
      req('r-staff', { source_type: null, source_id: null, requested_by: 'u-s2', note: 'TFX shelf is low' }),
      req('r-mine', { note: 'TFX for the weekend' }),
      req('r-rej', { status: 'rejected', approved_by: 'u-own', approved_at: at, rejection_reason: 'TFX nothing to spare' }),
      req('r-transit', { status: 'in_transit', approved_by: 'u-own', approved_at: at, dispatched_at: at }),
      req('r-disc', { status: 'received_with_discrepancy', approved_by: 'u-own', approved_at: at, dispatched_at: at, received_at: at }),
    ],
    lines: [
      line('l-staff', 'r-staff', 'p1'),
      line('l-mine', 'r-mine', 'p1', { quantity: 2 }),
      line('l-rej', 'r-rej', 'p1'),
      line('l-t1', 'r-transit', 'p1', { approved_quantity: 5, in_transit_quantity: 5 }),
      line('l-t2', 'r-transit', 'p2', { approved_quantity: 2, in_transit_quantity: 2 }),
      // two short, sent from WH 2 though the header says WH 1
      line('l-short', 'r-disc', 'p1', { approved_quantity: 5, in_transit_quantity: 5, received_quantity: 3, discrepancy_quantity: -2 }),
      // two extra, sent from both warehouses
      line('l-extra', 'r-disc', 'p2', { approved_quantity: 2, in_transit_quantity: 2, received_quantity: 4, discrepancy_quantity: 2 }),
    ],
    sources: {
      'l-t1': [{ name: 'TFX WH 2', quantity: 5 }], 'l-t2': [{ name: 'TFX WH 1', quantity: 2 }],
      'l-short': [{ name: 'TFX WH 2', quantity: 5 }],
      'l-extra': [{ name: 'TFX WH 1', quantity: 1 }, { name: 'TFX WH 2', quantity: 1 }],
    },
    assignments: { 'u-s2': ['sa', 'sb'], 'u-s1': ['sa'] },
  };
}
function createBackend(fx, me) {
  const b = { calls: [], fx, detailsDelay: 0 };
  const storeName = id => fx.stores.find(s => s.id === id)?.name;
  const rpcs = {
    my_assigned_stores: () => (me.role === 'staff' ? fx.assignments[me.id] ?? [] : fx.stores.map(s => s.id))
      .map((id, i) => ({ store_id: id, store_name: storeName(id), is_default: i === 0 })),
    stock_transfer_details: a => ({ id: a.p_request_id, status: fx.requests.find(r => r.id === a.p_request_id)?.status,
      destination: 'TFX Store A', notes: [],
      lines: fx.lines.filter(l => l.transfer_request_id === a.p_request_id).map(l => ({ id: l.id, product: 'x', sources: fx.sources[l.id] ?? [] })) }),
    create_staff_transfer_request: () => ({ success: true, id: 'r-new' }),
    edit_transfer_request: a => ({ id: a.p_transfer_id, new_version: 2, edit_count: 1 }),
    receive_transfer: () => ({ success: true }),
    resolve_transfer_discrepancy: () => ({ success: true, completed: true, remaining: 0 }),
    cancel_transfer_request: () => ({ success: true }),
    transfer_revisions: () => [],
  };
  const tables = {
    transfer_requests: fx.requests, transfer_request_lines: fx.lines, warehouses: fx.warehouses, stores: fx.stores,
    products: fx.products, profiles: fx.profiles, store_product_prices: fx.prices, store_inventory: [],
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], single: false }); }
    select() { return this; }
    eq(c, v) { this.filters.push(r => r[c] === v); return this; }
    is(c, v) { this.filters.push(r => (r[c] ?? null) === v); return this; }
    in(c, vs) { this.filters.push(r => vs.includes(r[c])); return this; }
    gt(c, v) { this.filters.push(r => r[c] > v); return this; }
    order() { return this; }
    limit() { return this; }
    maybeSingle() { this.single = true; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args });
      await Promise.resolve();
      if (this.kind === 'rpc') {
        if (this.name === 'stock_transfer_details' && b.detailsDelay) await new Promise(r => setTimeout(r, b.detailsDelay));
        const fn = rpcs[this.name];
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
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(who = 'owner', tweak = () => {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  const me = PEOPLE[who];
  const fx = makeFixture(); tweak(fx);
  backend = createBackend(fx, me);
  globalThis.__backend = backend; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: me };
  confirms.length = 0; alerts.length = 0; confirmAnswer = true;
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(TransfersPage))));
  await tick();
  assert.deepEqual(globalThis.__renderErrors, []);
}
const text = () => document.body.textContent;
const modal = () => [...document.querySelectorAll('.modal')].at(-1);
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const button = (label, scope = document) => [...scope.querySelectorAll('button')].find(b => b.textContent.trim() === label);
async function setValue(el, value) {
  assert.ok(el, 'the field exists');
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype
    : el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
  });
  await tick(3);
}
// The table row of a request (the fake backend keeps the fixture's order; a
// request's own row has 8 cells, its opened details 2).
const rowOf = id => {
  const rows = [...document.querySelectorAll('tbody > tr')].filter(tr => tr.children.length === 8);
  return rows[backend.fx.requests.findIndex(x => x.id === id)] ?? assert.fail(`no row for ${id}`);
};
const expand = async id => click(rowOf(id).querySelector('td button'));
const callsOf = name => backend.calls.filter(c => c.name === name);
async function pickProduct(label) {
  await click([...modal().querySelectorAll('button')].find(b => b.textContent.trim().startsWith('Search product name or SKU')));
  await click([...modal().querySelectorAll('div')].find(d => d.firstElementChild?.textContent === label && d.children.length <= 2));
}
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── STOCK-1 ────────────────────────────────────────────────────────────────
test('staff at two stores must choose the store; the choice is sent', async () => {
  await mount('staff2');
  assert.equal(callsOf('my_assigned_store_id').length, 0, 'the oldest-store guess is no longer read');
  await click(button('New Transfer'));
  const choose = modal().querySelector('select[aria-label="Store this request is for"]');
  assert.ok(choose, 'a store choice is shown');
  assert.equal(choose.value, '', 'no store is chosen for them');
  assert.deepEqual([...choose.options].map(o => o.textContent), ['— choose a store —', 'TFX Store A', 'TFX Store B']);
  await pickProduct('TFX Pillow (TFX-P)');
  await setValue(modal().querySelector('input[placeholder="Qty"]'), '3');
  await click(button('Submit Request', modal()));
  assert.ok(modal().textContent.includes('Choose which store this request is for.'), modal().textContent);
  assert.equal(callsOf('create_staff_transfer_request').length, 0, 'nothing is sent without a store');
  await setValue(choose, 'sb');
  await click(button('Submit Request', modal()));
  const sent = callsOf('create_staff_transfer_request');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].args.p_store_id, 'sb', 'the store chosen is sent');
  assert.equal(modal(), undefined, 'the window closes');
});

test('staff at one store are not asked: their store is sent', async () => {
  await mount('staff1');
  await click(button('New Transfer'));
  assert.equal(modal().querySelector('select[aria-label="Store this request is for"]'), null);
  assert.ok(modal().textContent.includes('Requesting into TFX Store A.'), modal().textContent);
  await pickProduct('TFX Pillow (TFX-P)');
  await setValue(modal().querySelector('input[placeholder="Qty"]'), '1');
  await click(button('Submit Request', modal()));
  assert.equal(callsOf('create_staff_transfer_request')[0]?.args.p_store_id, 'sa');
});

test('staff with no store are told to ask for one', async () => {
  await mount('staff1', fx => { fx.assignments['u-s1'] = []; });
  await click(button('New Transfer'));
  assert.ok(modal().textContent.includes('No store assigned'));
  await pickProduct('TFX Pillow (TFX-P)');
  await setValue(modal().querySelector('input[placeholder="Qty"]'), '1');
  await click(button('Submit Request', modal()));
  assert.ok(modal().textContent.includes('You are not assigned to a store yet.'), modal().textContent);
  assert.equal(callsOf('create_staff_transfer_request').length, 0);
});

// ── STOCK-9 ────────────────────────────────────────────────────────────────
test('a rejected transfer reads Rejected by, with the reason', async () => {
  await mount('owner');
  await expand('r-rej');
  assert.match(text(), /Rejected by TFX Owner on .+: TFX nothing to spare/);
  assert.doesNotMatch(text(), /Approved by TFX Owner/);
  await expand('r-transit');
  assert.match(text(), /Dispatched by TFX Owner on /, 'a dispatched transfer still says so');
  await expand('r-mine');
  assert.doesNotMatch(text(), /(Approved|Dispatched|Rejected) by/, 'a pending transfer has no decision line');
});

// ── STOCK-14 item 3 ────────────────────────────────────────────────────────
test('an Owner can cancel someone else\'s pending request, after a confirmation naming them', async () => {
  await mount('owner');
  const cancelBtn = rowOf('r-staff').querySelector('button[aria-label="Cancel request"]');
  assert.ok(cancelBtn, 'Cancel is offered on a staff member\'s pending request');
  confirmAnswer = false;
  await click(cancelBtn);
  assert.equal(confirms.at(-1), "Cancel TFX Staff Two's pending transfer request? It cannot be reopened.");
  assert.equal(callsOf('cancel_transfer_request').length, 0, 'saying no cancels nothing');
  confirmAnswer = true;
  await click(rowOf('r-staff').querySelector('button[aria-label="Cancel request"]'));
  assert.deepEqual(callsOf('cancel_transfer_request').map(c => c.args.p_request_id), ['r-staff']);
  await click(rowOf('r-mine').querySelector('button[aria-label="Cancel request"]'));
  assert.equal(confirms.at(-1), 'Cancel this pending transfer request?', 'one\'s own request keeps the short question');
  assert.equal(rowOf('r-rej').querySelector('button[aria-label="Cancel request"]'), null, 'only pending requests');
});

test('staff see Cancel only on their own pending request', async () => {
  await mount('staff2');
  assert.ok(rowOf('r-staff').querySelector('button[aria-label="Cancel request"]'));
  assert.equal(rowOf('r-mine').querySelector('button[aria-label="Cancel request"]'), null);
});

// ── STOCK-14 item 2 ────────────────────────────────────────────────────────
test('an edit sends the note as typed, so an empty note clears it', async () => {
  await mount('owner');
  await click(button('Edit', rowOf('r-mine')));
  const noteField = modal().querySelector('input[placeholder="Optional note"]');
  assert.equal(noteField.value, 'TFX for the weekend');
  await setValue(noteField, '');
  await setValue(modal().querySelector('textarea[placeholder="Why is this transfer being edited?"]'), 'TFX not needed');
  await click(button('Save Changes', modal()));
  const sent = callsOf('edit_transfer_request');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].args.p_note, '', 'the empty note is sent, not left out');
});

test('an edit that leaves the note alone sends it unchanged', async () => {
  await mount('owner');
  await click(button('Edit', rowOf('r-mine')));
  await setValue(modal().querySelector('textarea[placeholder="Why is this transfer being edited?"]'), 'TFX quantity');
  await click(button('Save Changes', modal()));
  assert.equal(callsOf('edit_transfer_request')[0].args.p_note, 'TFX for the weekend');
});

// ── STOCK-14 item 1, and where each line came from ─────────────────────────
test('Receive shows each line\'s source, asks a reason on a line that differs, and sends it', async () => {
  await mount('owner');
  await click(button('Receive', rowOf('r-transit')));
  assert.ok(modal().textContent.includes('From TFX WH 2 (5)'), 'the line sent from WH 2 says so');
  assert.ok(modal().textContent.includes('From TFX WH 1 (2)'));
  assert.equal(modal().querySelector('input[aria-label="TFX Pillow: reason"]'), null, 'no reason box while the counts match');
  await setValue(modal().querySelector('input[aria-label="TFX Pillow: received"]'), '4');
  const reason = modal().querySelector('input[aria-label="TFX Pillow: reason"]');
  assert.ok(reason, 'a reason box appears on the line that differs');
  await setValue(reason, 'TFX one box crushed');
  // the helper only fills in the counts; it saves nothing
  const fill = button('Fill approved', modal());
  assert.ok(fill, 'the helper says what it does');
  assert.match(fill.title, /approved quantity\. Nothing is saved until Confirm Receipt/);
  assert.equal(button('Confirm All Received', modal()), undefined);
  await click(fill);
  assert.equal(callsOf('receive_transfer').length, 0, 'filling in saves nothing');
  assert.equal(modal().querySelector('input[aria-label="TFX Pillow: received"]').value, '5');
  await setValue(modal().querySelector('input[aria-label="TFX Pillow: received"]'), '4');
  await setValue(modal().querySelector('textarea[placeholder="Explain the difference"]'), 'TFX one damaged');
  await click(button('Confirm Receipt', modal()));
  const sent = callsOf('receive_transfer');
  assert.equal(sent.length, 1);
  assert.deepEqual(sent[0].args.p_lines, [
    { line_id: 'l-t1', received_quantity: 4, reason: 'TFX one box crushed' },
    { line_id: 'l-t2', received_quantity: 2, reason: null },
  ]);
  assert.equal(sent[0].args.p_note, 'TFX one damaged');
});

// ── STOCK-M2 ───────────────────────────────────────────────────────────────
const optionsOf = sel => [...sel.options].map(o => o.textContent);
const resolveSelects = () => [...modal().querySelectorAll('select')];

test('Resolve acts where each line came from', async () => {
  await mount('owner');
  await click(button('Resolve', rowOf('r-disc')));
  const [short, extra] = resolveSelects();
  assert.ok(modal().textContent.includes('From TFX WH 2 (5)'), modal().textContent);
  assert.ok(modal().textContent.includes('From TFX WH 1 (1), TFX WH 2 (1)'));
  assert.deepEqual(optionsOf(short), ['Accept missing as loss', 'Correct source stock at TFX WH 2', 'Correct destination stock',
    'Create linked inventory adjustment', 'Other / acknowledge (reason required)'], 'the source named is the line\'s, not the header\'s WH 1');
  assert.deepEqual(optionsOf(extra), ['Accept extra as surplus', 'Correct destination stock', 'Other / acknowledge (reason required)'],
    'a line from several places offers neither source option, and extra units no adjustment');
  assert.ok(modal().textContent.includes('Sent from several places: accept it, or record a stock adjustment at the right place.'));
  await setValue(short, 'correct_source');
  await click(button('Resolve & Complete', modal()));
  const sent = callsOf('resolve_transfer_discrepancy');
  assert.equal(sent.length, 1);
  assert.deepEqual(sent[0].args.p_resolutions, [
    { line_id: 'l-short', resolution: 'correct_source', reason: null },
    { line_id: 'l-extra', resolution: 'accept_surplus', reason: null },
  ]);
});

test('a line with no recorded source and no header source offers neither source option', async () => {
  await mount('owner', fx => {
    Object.assign(fx.requests.find(r => r.id === 'r-disc'), { source_type: null, source_id: null });
    fx.sources['l-short'] = [];
  });
  await click(button('Resolve', rowOf('r-disc')));
  assert.deepEqual(optionsOf(resolveSelects()[0]), ['Accept missing as loss', 'Correct destination stock',
    'Create linked inventory adjustment', 'Other / acknowledge (reason required)']);
  assert.ok(modal().textContent.includes('No source is recorded for this line'));
});

test('a line from before allocations uses the transfer\'s source, as the server does', async () => {
  await mount('owner', fx => { fx.sources['l-short'] = []; });
  await click(button('Resolve', rowOf('r-disc')));
  assert.ok(optionsOf(resolveSelects()[0]).includes('Correct source stock at TFX WH 1'));
});

test('a choice picked before the sources arrive, and no longer offered, must be chosen again', async () => {
  await mount('owner');
  backend.detailsDelay = 30;
  await act(async () => { rowOf('r-disc').querySelector('.btn-danger').dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  assert.equal(button('Resolve & Complete', modal()).disabled, true, 'Resolve & Complete waits for the sources');
  const extra = resolveSelects()[1];
  assert.ok(optionsOf(extra).includes('Return excess to source'), 'while loading, every option is offered');
  await act(async () => {
    Object.getOwnPropertyDescriptor(dom.window.HTMLSelectElement.prototype, 'value').set.call(extra, 'return_excess');
    extra.dispatchEvent(new dom.window.Event('change', { bubbles: true }));
  });
  await new Promise(r => setTimeout(r, 60)); await tick();
  assert.equal(button('Resolve & Complete', modal()).disabled, false, 'and is ready once they arrive');
  assert.ok(!optionsOf(resolveSelects()[1]).some(o => o.startsWith('Return excess')), 'the option is gone once the sources show two places');
  assert.equal(resolveSelects()[1].value, '', 'no other option is put in its place');
  assert.equal(optionsOf(resolveSelects()[1])[0], '— choose again —');
  assert.ok(modal().textContent.includes('That option is not available for this line. Choose again.'));
  // typing a reason does not bring a choice back
  await setValue(modal().querySelectorAll('input[placeholder="Reason (optional)"]')[1], 'TFX counted twice');
  assert.equal(resolveSelects()[1].value, '');
  await click(button('Resolve & Complete', modal()));
  assert.equal(callsOf('resolve_transfer_discrepancy').length, 0, 'nothing is sent');
  assert.ok(modal().textContent.includes('Choose again for TFX Mat: that option is not available for this line.'), modal().textContent);
  // choosing again sends that choice, with the reason typed
  await setValue(resolveSelects()[1], 'accept_surplus');
  await click(button('Resolve & Complete', modal()));
  assert.deepEqual(callsOf('resolve_transfer_discrepancy')[0]?.args.p_resolutions[1],
    { line_id: 'l-extra', resolution: 'accept_surplus', reason: 'TFX counted twice' });
});

test('Fill approved fills the approved quantity, the one the mismatch check uses', async () => {
  // (in transit and approved are the same on every shipped line today; this
  // pins which one the page reads)
  await mount('owner', fx => { fx.lines.find(l => l.id === 'l-t1').in_transit_quantity = 6; });
  await click(button('Receive', rowOf('r-transit')));
  const qty = () => modal().querySelector('input[aria-label="TFX Pillow: received"]');
  assert.equal(qty().value, '5', 'the window opens at the approved quantity');
  assert.equal(modal().querySelector('input[aria-label="TFX Pillow: reason"]'), null, 'and shows no mismatch');
  await setValue(qty(), '2');
  await click(button('Fill approved', modal()));
  assert.equal(qty().value, '5');
  assert.equal(modal().querySelector('input[aria-label="TFX Pillow: reason"]'), null, 'no mismatch after filling in');
  assert.equal(modal().querySelector('textarea[placeholder="Explain the difference"]'), null);
});
