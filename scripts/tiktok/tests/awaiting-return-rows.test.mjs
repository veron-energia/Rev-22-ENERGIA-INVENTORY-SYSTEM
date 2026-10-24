// A cancelled TikTok order that had shipped is confirmed with the rest of its
// file (465). An "Awaiting Physical Return" row (cancelled after a shipped
// import) and a "New — Will Deduct, Awaiting Return" row (shipped, then
// cancelled before any file brought it in) are ticked like any row that moves
// or records stock, and Confirm sends them: confirming is what opens their
// physical return. Before 465 the page left "Awaiting Physical Return" out of
// the rows it lets staff tick, so the row was excluded at confirm and no
// physical return was ever opened.
//
// The actual src/pages/TikTokImportPage.tsx is bundled with esbuild and
// mounted in jsdom, as in page-errors-and-stores.test.mjs. Only the Supabase
// client and the auth context are stubbed. Every store, SKU, file and id below
// is invented.
//
// Run: node --test scripts/tiktok/tests/awaiting-return-rows.test.mjs
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
        render() { return this.state.error ? React.createElement('div', { id: 'crashed' }, String(this.state.error.message)) : this.props.children; }
      }`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
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
const STORE = 'st-north';
const row = (id, no, status, delta, extra = {}) => ({ id, batch_id: 'b-order', store_id: STORE, row_no: no, order_id: `ORD-46${no}`,
  seller_sku: 'SKU-SOAP', product_name: 'Sample Soap', quantity: 1, order_status: 'Canceled', staging_status: status, stock_delta: delta,
  matched_kind: 'product', matched_id: 'p-1', excluded: false, confirmed: false, version_no: 1, ...extra });

function createBackend() {
  const b = { calls: [] };
  const tables = {
    stores: [{ id: STORE, name: 'North Store', deleted_at: null, is_active: true }],
    products: [{ id: 'p-1', name: 'Sample Soap', sku: 'SOAP-1', is_active: true, deleted_at: null }],
    vouchers: [], promotions: [], tiktok_status_mappings: [],
    tiktok_physical_returns: [{ id: 'pr-1', store_id: STORE, order_id: 'ORD-400', seller_sku: 'SKU-SOAP', expected_qty: 1,
      status: 'awaiting', created_at: '2026-10-24T02:00:00Z' }],
    tiktok_import_batches: [{ id: 'b-order', file_name: 'orders_sample.csv', file_kind: 'order', status: 'staged', store_id: STORE }],
    tiktok_order_rows: [
      row('r-first-seen', 1, 'New — Will Deduct, Awaiting Return', 1),
      row('r-awaiting', 2, 'Awaiting Physical Return', 0, { previous_row_id: 'r-old', version_no: 2, prev_quantity: 1, prev_order_status: 'Shipped' }),
      row('r-new', 3, 'New — Will Deduct', 1, { order_status: 'Completed' }),
      row('r-already', 4, 'Already Imported', 0),
      row('r-unmatched', 5, 'Unmatched SKU', 0, { seller_sku: 'SKU-NEW', matched_kind: null, matched_id: null }),
    ],
    tiktok_settlement_rows: [], tiktok_order_state: [], tiktok_corrections: [],
  };
  const rpcs = {
    my_assigned_store_id: () => null,
    report_tiktok_imports: () => tables.tiktok_import_batches.map(x => ({
      batch_id: x.id, file_name: x.file_name, file_kind: x.file_kind, status: x.status, store_name: 'North Store',
      uploaded_at: '2026-10-24T02:00:00Z', row_count: 5, units_deducted: 0, units_returned: 0 })),
    report_tiktok_settlement: () => [], report_tiktok_recon_exceptions: () => [], report_tiktok_unmatched_skus: () => [],
    tiktok_settlement_totals: a => ({ year: a.p_year, month: a.p_month, period_start: '', period_end: '', timezone: 'Asia/Singapore', row_count: 0,
      revenue: 0, fee: 0, settlement: 0, expense: 0, income: 0, tiktok_net_settlement: 0, by_category: {}, unknown_count: 0,
      balance_movement_count: 0, pending_match_count: 0, currency_count: 1, undated_count: 0, needs_review: false,
      left_out_count: 0, left_out_settlement: 0 }),
    tiktok_left_out_settlement: () => [],
    tiktok_batch_balance_counts: () => ({ payouts: 0, others: 0 }),
    confirm_tiktok_batch: () => ({ success: true, applied: 4, skipped: 1, units_deducted: 2, units_returned: 0, awaiting_physical_return: 2 }),
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], orders: [], rangeV: null, one: false }); }
    select() { return this; }
    is(col, v) { this.filters.push(r => (r[col] ?? null) === v); return this; }
    eq(col, v) { this.filters.push(r => r[col] === v); return this; }
    in(col, vs) { this.filters.push(r => vs.includes(r[col])); return this; }
    order(col) { this.orders.push(col); return this; }
    range(a, z) { this.rangeV = [a, z]; return this; }
    limit() { return this; }
    single() { this.one = true; return this; }
    async exec() {
      b.calls.push({ name: this.name, args: this.args });
      await Promise.resolve();
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
async function mount() {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend();
  globalThis.__backend = backend;
  globalThis.__auth = { profile: { id: 'u-1', full_name: 'Test Owner', role: 'owner' } };
  alerts = [];
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(TikTokImportPage))));
  await tick();
  assert.ok(!document.getElementById('crashed'), document.getElementById('crashed')?.textContent);
}
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await tick(); };
const button = (label, scope = document) => [...scope.querySelectorAll('button')].find(x => x.textContent.trim().startsWith(label));
const card = text => [...document.querySelectorAll('.card')].find(c => c.textContent.includes(text));
const rowOf = orderId => [...document.querySelectorAll('tr')].find(tr => [...tr.querySelectorAll('td')].some(td => td.textContent.trim() === orderId));
const tickBox = orderId => rowOf(orderId)?.querySelector('input[type="checkbox"]');
const badge = orderId => [...(rowOf(orderId)?.querySelectorAll('.badge') ?? [])].find(x => x.textContent.includes('—') || /Awaiting|Imported|Unmatched/.test(x.textContent));

after(async () => { if (root) await act(async () => root.unmount()); });

async function openStagedFile() {
  await mount();
  await click(button('Open', card('Staged Import Batches')));
  assert.ok(card('Preview (no stock moved yet)'), 'the staged file opens');
}

test('a cancelled order that had shipped is ticked with the rest of its file', async () => {
  await openStagedFile();
  for (const [orderId, what] of [['ORD-461', 'first seen already cancelled, shipped (465)'], ['ORD-462', 'cancelled after a shipped import'],
                                 ['ORD-463', 'a new deduction'], ['ORD-464', 'already imported']]) {
    const box = tickBox(orderId);
    assert.ok(box, `${orderId} has a tick box`);
    assert.equal(box.checked, true, `${orderId} (${what}) is ticked`);
    assert.equal(box.disabled, false, `${orderId} (${what}) can be unticked`);
  }
  const unmatched = tickBox('ORD-465');
  assert.equal(unmatched.checked, false, 'an unmatched SKU is still not ticked');
  assert.equal(unmatched.disabled, true, 'nor can it be');
});

test('both waiting statuses stand out', async () => {
  await openStagedFile();
  assert.match(badge('ORD-461').className, /badge-warning/);
  assert.equal(badge('ORD-461').textContent, 'New — Will Deduct, Awaiting Return');
  assert.match(badge('ORD-462').className, /badge-warning/);
  assert.equal(badge('ORD-462').textContent, 'Awaiting Physical Return');
  assert.match(rowOf('ORD-461').textContent, /−1/, 'the first-seen row shows its unit coming off');
});

test('Confirm sends the waiting rows, so their physical returns are opened', async () => {
  await openStagedFile();
  await click(button('Confirm Selected Rows'));
  const call = backend.calls.find(c => c.name === 'confirm_tiktok_batch');
  assert.ok(call, 'the file is confirmed');
  assert.deepEqual([...call.args.p_row_ids].sort(), ['r-already', 'r-awaiting', 'r-first-seen', 'r-new']);
  assert.match(alerts.join('\n'), /2 awaiting physical return/);
});

test('the Awaiting Physical Return list says a first-seen cancelled order waits there too', async () => {
  await mount();
  const list = card('Awaiting Physical Return');
  assert.ok(list, 'the list is shown');
  assert.match(list.textContent, /first imported after it was already cancelled/);
  assert.match(list.textContent, /ORD-400/);
});
