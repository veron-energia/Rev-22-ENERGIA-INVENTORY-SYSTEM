// The TikTok import page shows what it could not read, never "nothing" or
// "Fully reconciled" in its place, and its spinners always stop (REPORTS-5).
// Deleting a staged settlement file closes its preview (REPORTS-8). The
// Settlements tab reads every row, a page at a time (REPORTS-15). Staff who
// work at two stores import into either and see both, and only theirs (X-9).
// The Order Items heading no longer says "latest 300" (REPORTS-16).
//
// The actual src/pages/TikTokImportPage.tsx is bundled with esbuild and
// mounted in jsdom. Only the Supabase client and the auth context are
// stubbed: the client by a small in-memory PostgREST. Every store, SKU, file
// and id below is invented.
//
// Run: node --test scripts/tiktok/tests/page-errors-and-stores.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ── the page, bundled ──────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://tiktok.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'Element', 'Node', 'Event',
  'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
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
      export { default as TikTokImportPage } from './src/pages/TikTokImportPage';
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
    // lib/supabasePaging imports the client as './supabase'.
    b.onResolve({ filter: /(^|\/)lib\/supabase$|^\.\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
  } }],
});
const { TikTokImportPage, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const NORTH = 'st-north', SOUTH = 'st-south', EAST = 'st-east';
const STORES = [
  { id: EAST, name: 'East Store', deleted_at: null, is_active: true },
  { id: NORTH, name: 'North Store', deleted_at: null, is_active: true },
  { id: SOUTH, name: 'South Store', deleted_at: null, is_active: true },
];
const storeName = id => STORES.find(s => s.id === id)?.name;

// A settlement transaction as report_tiktok_settlement returns it.
const settlementLine = (i, day) => ({
  row_id: `rs-${String(i).padStart(5, '0')}`, store_name: 'North Store', financial_date: day, order_adjustment_id: `ORD-9${String(i).padStart(5, '0')}`,
  txn_class: 'order', transaction_type: 'Order', match_status: 'matched', settlement_amount: 10, revenue_amount: 11, fee_amount: -1,
  adjustment_amount: 0, refund_amount: 0, currency: 'SGD', reconciled: true, version_no: 1,
});

// ── fake backend ───────────────────────────────────────────────────────────
function createBackend() {
  // failures: name -> message.
  const b = { calls: [], failures: new Map(), myStores: [], settlementLines: [] };
  const tables = {
    stores: STORES,
    products: [{ id: 'p-1', name: 'Sample Serum', sku: 'SERUM-1', is_active: true, deleted_at: null }],
    vouchers: [], promotions: [], tiktok_status_mappings: [], tiktok_physical_returns: [],
    tiktok_import_batches: [
      { id: 'b-order', file_name: 'orders_sample.csv', file_kind: 'order', status: 'staged', store_id: NORTH },
      { id: 'b-settle', file_name: 'income_sample.xlsx', file_kind: 'settlement', status: 'staged', store_id: NORTH },
    ],
    tiktok_order_rows: [
      { id: 'or-1', batch_id: 'b-order', store_id: NORTH, row_no: 1, order_id: 'ORD-100', seller_sku: 'SKU-NEW', quantity: 1,
        order_status: 'Shipped', staging_status: 'Unmatched SKU', stock_delta: 0, excluded: false, confirmed: false, version_no: 1 },
      // Confirmed items, one per store.
      ...[NORTH, SOUTH, EAST].map((s, i) => ({ id: `oc-${i}`, batch_id: 'b-old', store_id: s, row_no: 1, order_id: `ORD-20${i}`,
        seller_sku: `SKU-${storeName(s)}`, quantity: 1, order_status: 'Delivered', staging_status: 'New — Will Deduct', stock_delta: 1,
        excluded: false, confirmed: true, confirmed_at: `2026-09-0${i + 1}T02:00:00Z`, version_no: 1 })),
    ],
    tiktok_settlement_rows: [
      { id: 'sr-1', batch_id: 'b-settle', store_id: NORTH, row_no: 1, order_id: 'ORD-300', transaction_type: 'Order', txn_class: 'order',
        settlement_amount: 50, revenue_amount: 55, fee_amount: -5, match_status: 'matched', staging_status: 'New — Matched',
        excluded: false, confirmed: false, reconciled: true, version_no: 1 },
    ],
    tiktok_order_state: [NORTH, SOUTH, EAST].map((s, i) => ({ store_id: s, order_id: `ORD-40${i}`, seller_sku: `SKU-${storeName(s)}`,
      last_status: 'Delivered', deducted_qty: 1, was_shipped: true, updated_at: `2026-09-0${i + 1}T03:00:00Z` })),
    tiktok_corrections: [],
  };
  b.tables = tables;
  const rpcs = {
    my_assigned_store_id: () => null,
    my_assigned_stores: () => b.myStores.map((id, i) => ({ store_id: id, store_name: storeName(id), is_default: i === 0 })),
    report_tiktok_imports: () => tables.tiktok_import_batches.filter(x => !x.deleted_at).map(x => ({
      batch_id: x.id, file_name: x.file_name, file_kind: x.file_kind, status: x.status, store_name: storeName(x.store_id),
      uploaded_at: '2026-09-01T02:00:00Z', row_count: 1, units_deducted: 0, units_returned: 0 })),
    report_tiktok_settlement: () => b.settlementLines,
    report_tiktok_recon_exceptions: () => [],
    report_tiktok_unmatched_skus: () => [{ store_name: 'South Store', seller_sku: 'SKU-SOUTH-ONLY', occurrences: 2, last_seen: '2026-09-01T02:00:00Z', still_unmapped: true }],
    tiktok_settlement_totals: a => ({ year: a.p_year, month: a.p_month, period_start: '', period_end: '', timezone: 'Asia/Singapore', row_count: 0,
      revenue: 0, fee: 0, settlement: 0, expense: 0, income: 0, tiktok_net_settlement: 0, by_category: {}, unknown_count: 0,
      balance_movement_count: 0, pending_match_count: 0, currency_count: 1, undated_count: 0, needs_review: false,
      left_out_count: 0, left_out_settlement: 0 }),
    tiktok_left_out_settlement: () => [],
    tiktok_batch_balance_counts: () => ({ payouts: 0, others: 0 }),
    upsert_tiktok_sku_alias: () => 'alias-1',
    refresh_tiktok_staging: () => null,
    delete_tiktok_batch: a => { const x = tables.tiktok_import_batches.find(y => y.id === a.p_batch_id); x.deleted_at = 'now'; return null; },
    stage_tiktok_orders: () => 'b-order',
  };
  b.rpcs = rpcs;
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], where: [], orders: [], rangeV: null, one: false }); }
    select() { return this; }
    is(col, v) { this.filters.push(r => (r[col] ?? null) === v); this.where.push(`${col} is ${v}`); return this; }
    eq(col, v) { this.filters.push(r => r[col] === v); this.where.push(`${col}=${v}`); return this; }
    in(col, vs) { this.filters.push(r => vs.includes(r[col])); this.where.push(`${col} in (${vs.join(',')})`); return this; }
    order(col) { this.orders.push(col); return this; }
    range(a, z) { this.rangeV = [a, z]; return this; }
    single() { this.one = true; return this; }
    async exec() {
      b.calls.push({ name: this.name, args: this.args, where: this.where, orders: this.orders, range: this.rangeV });
      await Promise.resolve();
      if (b.failures.has(this.name)) return { data: null, error: { code: 'XX000', message: b.failures.get(this.name) } };
      const src = this.kind === 'table' ? tables[this.name] : rpcs[this.name]?.(this.args);
      if (src === undefined) return { data: null, error: { code: 'PGRST202', message: `unknown ${this.kind} ${this.name}` } };
      if (!Array.isArray(src)) return { data: src, error: null };
      let rows = src.filter(r => this.filters.every(f => f(r)));
      if (this.orders.length) rows = [...rows].sort((x, y) => {
        for (const c of this.orders) { if (x[c] === y[c]) continue; return String(x[c]) < String(y[c]) ? -1 : 1; }
        return 0;
      });
      if (this.rangeV) rows = rows.slice(this.rangeV[0], this.rangeV[1] + 1);
      return { data: this.one ? rows[0] ?? null : rows, error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

// ── driving the page ───────────────────────────────────────────────────────
let root = null;
let backend = null;
let alerts = [];
globalThis.alert = msg => { alerts.push(String(msg)); };
globalThis.confirm = () => true;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount({ role = 'owner', setup } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend();
  globalThis.__backend = backend; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: { id: 'u-1', full_name: 'Test User', role } };
  alerts = [];
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(TikTokImportPage))));
  await tick();
  assert.ok(!document.getElementById('crashed'), document.getElementById('crashed')?.textContent);
}
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await tick(); };
const buttons = (scope = document) => [...scope.querySelectorAll('button')];
const button = (label, scope = document) => buttons(scope).find(x => x.textContent.trim().startsWith(label));
const openTab = label => click(buttons().find(x => x.textContent.trim() === label));
const callsOf = name => backend.calls.filter(c => c.name === name);
const card = text => [...document.querySelectorAll('.card')].find(c => c.textContent.includes(text));
const text = el => (el?.textContent ?? '').replace(/\s+/g, ' ').trim();
const storeSelect = () => document.querySelector('select[aria-label="Store"]');
async function setValue(el, value, event = 'change') {
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => { Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value); el.dispatchEvent(new dom.window.Event(event, { bubbles: true })); });
  await tick();
}
// One option of the open SearchSelect list: its label, then its SKU.
const option = label => [...document.querySelectorAll('div')]
  .find(d => d.children.length === 2 && d.children[0].tagName === 'DIV' && d.children[0].textContent === label);
// Open a staged file from the Staged Import Batches list.
const openFile = name => click(button('Open', [...document.querySelectorAll('tr')].find(tr => tr.textContent.includes(name))));
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── REPORTS-5: errors are shown, spinners stop ─────────────────────────────
test('Reconciliation: a failed check is shown as a failure, never as "Fully reconciled"', async () => {
  await mount({ setup: b => b.failures.set('report_tiktok_recon_exceptions', 'JWT expired') });
  await openTab('Reconciliation');
  const c = card('Reconciliation');
  assert.equal(text(c.querySelector('[role="alert"]')), 'The reconciliation check could not be loaded: JWT expired');
  assert.doesNotMatch(c.textContent, /Fully reconciled/);
  assert.equal(c.querySelector('.spin'), null, 'the spinner stopped');

  await mount();
  await openTab('Reconciliation');
  assert.match(card('Reconciliation').textContent, /Fully reconciled — no exceptions/, 'only a check that ran and found nothing says so');
});

test('Order Items: a failed read stops the spinner and says why; the heading no longer says "latest 300"', async () => {
  await mount({ setup: b => b.failures.set('tiktok_order_rows', 'JWT expired') });
  await openTab('Order Items');
  const c = card('Confirmed Order Items');
  assert.equal(c.querySelector('h3').textContent, 'Confirmed Order Items');
  assert.equal(c.querySelector('.spin'), null, 'the spinner stopped');
  assert.equal(text(c.querySelector('[role="alert"]')), 'Confirmed order items could not be loaded: JWT expired');
  assert.equal(c.querySelector('table'), null);

  // Each tab reads again when it is opened, and works once the read does.
  backend.failures.clear();
  await openTab('Orders');
  await openTab('Order Items');
  assert.equal(card('Confirmed Order Items').querySelector('[role="alert"]'), null);
  assert.equal(card('Confirmed Order Items').querySelectorAll('tbody tr').length, 3, 'every store, as no store is chosen');
});

test('the other tabs show their failures too', async () => {
  for (const [tab, failing, heading, what] of [
    ['Orders', 'tiktok_order_state', 'Imported Orders', 'Imported orders'],
    ['Settlements', 'report_tiktok_settlement', 'Settlement Transactions', 'Settlement transactions'],
    ['Unmatched SKUs', 'report_tiktok_unmatched_skus', 'Unmatched Seller SKUs', 'Unmatched SKUs'],
    ['Physical Returns', 'tiktok_physical_returns', 'Physical Returns', 'Physical returns'],
    ['Corrections', 'tiktok_corrections', 'Correction History', 'Corrections'],
  ]) {
    await mount({ setup: b => b.failures.set(failing, 'boom') });
    if (failing === 'tiktok_physical_returns') {
      // The page's own list of returns awaiting a parcel failed too: it says so.
      assert.match(text(document.querySelector('[data-testid="load-errors"]')), /Physical returns: boom/);
    }
    await openTab(tab);
    const alert = [...card(heading).querySelectorAll('[role="alert"]')].find(a => a.dataset.testid === 'tab-error');
    assert.equal(text(alert), `${what} could not be loaded: boom`, tab);
    assert.equal(card(heading).querySelector('.spin'), null, `${tab}: the spinner stopped`);
  }
});

test('a failed import list says so, in Staged Imports and Import History, never "No imports yet"', async () => {
  await mount({ setup: b => b.failures.set('report_tiktok_imports', 'permission denied') });
  assert.equal(text(document.querySelector('[data-testid="imports-error"]')), 'Could not load imports: permission denied');
  assert.match(text(document.querySelector('[data-testid="load-errors"]')), /Part of this page could not be loaded\..*Imports: permission denied/);
  assert.doesNotMatch(document.body.textContent, /No imports yet|No staged imports/);
  await openTab('Import History');
  assert.match(card('Import History').textContent, /Could not load imports: permission denied/);
  assert.doesNotMatch(card('Import History').textContent, /No imports yet/);

  // Refresh reads again, and the warning goes.
  backend.failures.clear();
  await openTab('Staged Imports');
  await click(button('Refresh'));
  assert.equal(document.querySelector('[data-testid="load-errors"]'), null);
  assert.equal(document.querySelector('[data-testid="imports-error"]'), null);
  assert.match(card('Staged Import Batches').textContent, /orders_sample\.csv/);
});

test('mapping a SKU: a failed save or a failed re-check keeps the window open with the reason', async () => {
  await mount({ role: 'manager' });
  await openFile('orders_sample.csv');
  const pickTarget = async () => {
    await click(button('Search product name or SKU'));
    await click(option('Sample Serum'));
  };
  const modalTitle = () => [...document.querySelectorAll('*')].find(e => e.textContent === 'Map Seller SKU — SKU-NEW' && e.children.length === 0);

  // 1. The mapping is refused.
  backend.failures.set('upsert_tiktok_sku_alias', 'Cannot map to an inactive product');
  await click(button('Map'));
  await pickTarget();
  await click(button('Save Mapping'));
  assert.ok(modalTitle(), 'the window stays open');
  assert.equal(text(document.querySelector('[data-testid="map-error"]')), 'Cannot map to an inactive product');
  assert.equal(callsOf('refresh_tiktok_staging').length, 0);

  // 2. Saved, but the open file could not be checked again.
  backend.failures.delete('upsert_tiktok_sku_alias');
  backend.failures.set('refresh_tiktok_staging', 'statement timeout');
  await click(button('Save Mapping'));
  assert.ok(modalTitle(), 'still open');
  assert.equal(text(document.querySelector('[data-testid="map-error"]')),
    'The mapping is saved, but the open file could not be checked again: statement timeout. Press Save Mapping to try again.');
  assert.deepEqual(callsOf('upsert_tiktok_sku_alias').at(-1).args,
    { p_store_id: NORTH, p_seller_sku: 'SKU-NEW', p_target_kind: 'product', p_target_id: 'p-1' }, 'for the file\'s store');

  // 3. Both work: the window closes and the file is read again.
  backend.failures.clear();
  const reads = callsOf('tiktok_order_rows').length;
  await click(button('Save Mapping'));
  assert.equal(modalTitle(), undefined, 'closed');
  assert.deepEqual(callsOf('refresh_tiktok_staging').at(-1).args, { p_batch_id: 'b-order' });
  assert.ok(callsOf('tiktok_order_rows').length > reads, 'the file is read again');
});

test('mapping from Unmatched SKUs uses that row\'s store, and a confirmed open file is not re-checked', async () => {
  await mount({ role: 'owner' });
  backend.tables.tiktok_import_batches[0].status = 'confirmed';
  await openFile('orders_sample.csv');
  await openTab('Unmatched SKUs');
  await click(button('Map', card('Unmatched Seller SKUs')));
  await click(button('Search product name or SKU'));
  await click(option('Sample Serum'));
  const unmatchedReads = callsOf('report_tiktok_unmatched_skus').length;
  await click(button('Save Mapping'));
  assert.equal(callsOf('upsert_tiktok_sku_alias').at(-1).args.p_store_id, SOUTH, 'the row\'s store, though no store is chosen');
  assert.equal(callsOf('refresh_tiktok_staging').length, 0, 'a confirmed file is locked: not checked again');
  assert.equal(document.querySelector('[data-testid="map-error"]'), null);
  assert.ok(callsOf('report_tiktok_unmatched_skus').length > unmatchedReads, 'the list is read again');
});

// ── REPORTS-8: a deleted settlement file closes its preview ────────────────
test('deleting a staged settlement file closes its preview and its Confirm button', async () => {
  await mount({ role: 'manager' });
  await openFile('income_sample.xlsx');
  assert.ok(card('Settlement Preview'), 'the preview is open');
  assert.ok(button('Confirm Selected Rows'));
  const row = [...card('Staged Import Batches').querySelectorAll('tr')].find(tr => tr.textContent.includes('income_sample.xlsx'));
  await click(row.querySelector('button[title="Delete unconfirmed batch"]'));
  assert.deepEqual(callsOf('delete_tiktok_batch').at(-1).args, { p_batch_id: 'b-settle' });
  assert.equal(card('Settlement Preview'), undefined, 'the preview is closed');
  assert.equal(button('Confirm Selected Rows'), undefined, 'no Confirm button that would answer "Batch not found"');
  assert.doesNotMatch(card('Staged Import Batches').textContent, /income_sample\.xlsx/);

  // The order file's preview, as before.
  await openFile('orders_sample.csv');
  assert.ok(card('Preview (no stock moved yet)'));
  const orderRow = [...card('Staged Import Batches').querySelectorAll('tr')].find(tr => tr.textContent.includes('orders_sample.csv'));
  await click(orderRow.querySelector('button[title="Delete unconfirmed batch"]'));
  assert.equal(card('Preview (no stock moved yet)'), undefined);
});

// ── REPORTS-15: the Settlements tab reads every row ────────────────────────
test('the Settlements tab reads every transaction a page at a time, newest first, undated first', async () => {
  const lines = [];
  for (let i = 0; i < 2300; i++) {
    const day = `2026-${String(1 + (i % 9)).padStart(2, '0')}-${String(1 + (i % 28)).padStart(2, '0')}`;
    lines.push(settlementLine(i, day));
  }
  lines.push(settlementLine(99999, null));
  await mount({ setup: b => { b.settlementLines = lines; } });
  await openTab('Settlements');
  const calls = callsOf('report_tiktok_settlement');
  assert.deepEqual(calls.map(c => c.range), [[0, 999], [1000, 1999], [2000, 2999]], 'three pages of 1,000');
  assert.ok(calls.every(c => c.orders.join() === 'row_id'), 'paged in a stable order');
  const shown = [...card('Settlement Transactions').querySelectorAll('tbody tr')]
    .filter(tr => tr.closest('[data-testid="left-out"]') === null);
  assert.equal(shown.length, 2301, 'every row, not the first 1,000');
  const days = shown.map(tr => tr.children[0].textContent);
  assert.equal(days[0], 'No settled date', 'a row with no settled date first');
  const dated = days.slice(1);
  assert.deepEqual(dated, [...dated].sort().reverse(), 'then newest first');
});

// ── X-9: staff at two stores ───────────────────────────────────────────────
test('staff at two stores choose either for an upload, and see both of theirs (only theirs) until they do', async () => {
  await mount({ role: 'staff', setup: b => { b.myStores = [NORTH, SOUTH]; } });
  assert.equal(callsOf('my_assigned_stores').length, 1, 'staff read every store they work at');
  assert.equal(callsOf('my_assigned_store_id').length, 0, 'not only the first one');
  const sel = storeSelect();
  assert.equal(sel.disabled, false);
  assert.deepEqual([...sel.options].map(o => o.textContent), ['— Choose your store —', 'North Store', 'South Store'], 'their two stores, not East');
  assert.equal(sel.value, '', 'nothing chosen for them');
  const uploads = buttons().filter(x => x.textContent.includes('Upload .xlsx / .csv'));
  assert.equal(uploads.length, 2);
  assert.ok(uploads.every(x => x.disabled), 'an upload needs a store');

  // No store chosen: the tabs show both their stores, and nothing of East.
  await openTab('Orders');
  assert.match(callsOf('tiktok_order_state').at(-1).where.join(), new RegExp(`store_id in \\(${NORTH},${SOUTH}\\)`));
  assert.deepEqual([...card('Imported Orders').querySelectorAll('tbody tr')].map(tr => tr.children[1].textContent).sort(),
    ['SKU-North Store', 'SKU-South Store']);
  await openTab('Settlements');
  assert.equal(callsOf('report_tiktok_settlement').at(-1).args.p_store_id, null, 'the report keeps to their stores itself');

  // The second store: chosen, uploaded into, and the only one shown.
  await openTab('Staged Imports');
  await setValue(storeSelect(), SOUTH);
  assert.ok(buttons().filter(x => x.textContent.includes('Upload .xlsx / .csv')).every(x => !x.disabled));
  const input = document.querySelectorAll('input[type="file"]')[0];
  const csv = 'Order ID,Seller SKU,Quantity,Order Status\n5800000000000001,SKU-SOUTH,1,Shipped\n';
  Object.defineProperty(input, 'files', { value: [new File([csv], 'orders_south.csv', { type: 'text/csv' })], configurable: true });
  await act(async () => { input.dispatchEvent(new dom.window.Event('change', { bubbles: true })); });
  await tick(30);
  assert.equal(callsOf('stage_tiktok_orders').at(-1)?.args.p_store_id, SOUTH, 'staged at the second store');
  await openTab('Orders');
  assert.deepEqual(callsOf('tiktok_order_state').at(-1).where, [`store_id=${SOUTH}`]);
  assert.deepEqual([...card('Imported Orders').querySelectorAll('tbody tr')].map(tr => tr.children[1].textContent), ['SKU-South Store']);
});

test('staff at one store have it chosen for them, as before; staff at none are told', async () => {
  await mount({ role: 'staff', setup: b => { b.myStores = [SOUTH]; } });
  const sel = storeSelect();
  assert.equal(sel.value, SOUTH);
  assert.equal(sel.disabled, true, 'nothing to choose');
  assert.deepEqual([...sel.options].map(o => o.textContent), ['South Store']);
  assert.ok(buttons().filter(x => x.textContent.includes('Upload .xlsx / .csv')).every(x => !x.disabled));

  await mount({ role: 'staff', setup: b => { b.myStores = []; } });
  assert.match(document.body.textContent, /You are not assigned to a store yet\. Ask an Owner or Manager\./);
  await openTab('Reconciliation');
  assert.doesNotMatch(card('Reconciliation').textContent, /Fully reconciled/);
  assert.match(card('Reconciliation').textContent, /Nothing to show: you are not assigned to a store\./);
  await openTab('Orders');
  assert.equal(callsOf('tiktok_order_state').length, 0, 'nothing of any store is read');

  // Their stores could not be read: said, and nothing is read for them. The
  // tabs say the list failed, not that they have no store.
  await mount({ role: 'staff', setup: b => { b.failures.set('my_assigned_stores', 'boom'); } });
  assert.match(text(document.querySelector('[data-testid="load-errors"]')), /Your stores: boom/);
  assert.doesNotMatch(document.body.textContent, /not assigned to a store/);
  await openTab('Orders');
  assert.equal(callsOf('tiktok_order_state').length, 0);
  assert.doesNotMatch(card('Imported Orders').textContent, /not assigned to a store/);
  assert.equal(text(card('Imported Orders').querySelector('[data-testid="stores-unknown"]')),
    'Your stores could not be loaded, so nothing is shown. Press Refresh to try again.');
  await openTab('Reconciliation');
  assert.equal(callsOf('report_tiktok_recon_exceptions').length, 0);
  assert.doesNotMatch(card('Reconciliation').textContent, /Fully reconciled|not assigned to a store/);
  assert.match(card('Reconciliation').textContent, /Your stores could not be loaded/);

  // Once the list loads, the tab reads.
  backend.failures.clear();
  await click(button('Refresh'));
  assert.equal(document.querySelector('[data-testid="load-errors"]'), null);
  await openTab('Reconciliation');
  assert.equal(document.querySelector('[data-testid="stores-unknown"]'), null);
  assert.match(card('Reconciliation').textContent, /Nothing to show: you are not assigned to a store\./, 'this login has none');
});

test('a failed reload of their stores keeps the store a member of staff chose, and the tabs keep to it', async () => {
  await mount({ role: 'staff', setup: b => { b.myStores = [NORTH, SOUTH]; } });
  await setValue(storeSelect(), SOUTH);
  await openTab('Reconciliation');
  assert.match(card('Reconciliation').textContent, /Fully reconciled — no exceptions/);

  // The list fails on Refresh: said, and nothing else changes.
  backend.failures.set('my_assigned_stores', 'JWT expired');
  await click(button('Refresh'));
  assert.match(text(document.querySelector('[data-testid="load-errors"]')), /Your stores: JWT expired/);
  assert.doesNotMatch(document.body.textContent, /not assigned to a store/);
  assert.match(card('Reconciliation').textContent, /Fully reconciled — no exceptions/);
  assert.equal(callsOf('report_tiktok_recon_exceptions').at(-1).args.p_store_id, SOUTH);
  await openTab('Order Items');
  assert.doesNotMatch(card('Confirmed Order Items').textContent, /not assigned to a store/);
  assert.deepEqual(callsOf('tiktok_order_rows').at(-1).where, ['confirmed=true', `store_id=${SOUTH}`]);
  assert.equal(card('Confirmed Order Items').querySelectorAll('tbody tr').length, 1, 'the chosen store only');
  await openTab('Staged Imports');
  assert.equal(storeSelect().value, SOUTH, 'still chosen');

  // It works again: the choice is still there.
  backend.failures.clear();
  await click(button('Refresh'));
  assert.equal(document.querySelector('[data-testid="load-errors"]'), null);
  assert.equal(storeSelect().value, SOUTH, 'kept after the failure');
  await openTab('Order Items');
  assert.deepEqual(callsOf('tiktok_order_rows').at(-1).where, ['confirmed=true', `store_id=${SOUTH}`]);
  assert.equal(card('Confirmed Order Items').querySelectorAll('tbody tr').length, 1);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('Owners and Managers keep any store, starting from their first one', async () => {
  await mount({ role: 'manager', setup: b => { b.rpcs.my_assigned_store_id = () => NORTH; } });
  assert.equal(callsOf('my_assigned_stores').length, 0);
  const sel = storeSelect();
  assert.equal(sel.value, NORTH);
  assert.deepEqual([...sel.options].map(o => o.textContent), ['— Select store —', 'East Store', 'North Store', 'South Store']);
  await setValue(sel, '');
  await openTab('Orders');
  assert.deepEqual(callsOf('tiktok_order_state').at(-1).where, [], 'no store chosen: every store');
  assert.equal(card('Imported Orders').querySelectorAll('tbody tr').length, 3);
  assert.deepEqual(globalThis.__renderErrors, []);
});
