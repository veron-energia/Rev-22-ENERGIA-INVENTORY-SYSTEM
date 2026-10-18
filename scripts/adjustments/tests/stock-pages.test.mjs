// The stock and product pages after 420, rendered for real against a fake
// backend: Adjustments, Approvals, Warehouse Stock, Store Stock, Products,
// Price List, Stores and Warehouses.
//
// The actual pages are bundled with esbuild and mounted in jsdom. Only the
// Supabase client and the auth context are stubbed: the client by a small
// in-memory backend that records every call. Every name is invented.
//
// It checks the audit findings this batch fixes (STOCK-2, -3, -4, -5, -7, -8,
// -10, -12a, -12c, -14 item 4, M3, ADMIN-AUTH-15's Stores part, the
// Approvals parts of INVOICES-AFTER-14 and INVOICES-CREATE-18) and the
// Owner's answers of 9 Oct 2026 (Q11, Q12, Q13, and the later ones: Managers
// see only the stores they work at on Store Stock; a store or warehouse
// holding stock is not switched off; rejecting a correction needs a reason):
//   * a counted total is typed as text: empty is not 0, a decimal is refused,
//     0 shows as 0, and setting stock above 0 to 0 asks first;
//   * a form is sent once (one call, one id per opened form, the same id on a
//     retry), for corrections and for Stock In;
//   * the Approvals card shows today's number and says when it moved; every
//     rejection needs a reason, and Adjustments shows it to the person who
//     asked;
//   * 0 or less is out of stock, below 0 also Negative;
//   * Store Stock lists the person's stores only, a Manager's too;
//   * products: Owner, Manager and Inventory Manager edit through save_product;
//     an Admin looks; delete and restore go through the server and show its
//     refusal; "Show deleted"; the No commission filter; the export's brand;
//   * Price List counts only listed products;
//   * Stores and Warehouses delete and restore through the server, and show
//     the server's refusal to switch off a place that holds stock (on Stores,
//     scrolled into view, as it sits far above Save); store staff through
//     assign_user_store, with the rules shown before a click.
//
// Run: node --test scripts/adjustments/tests/stock-pages.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');

// ── the pages, bundled ─────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://stock.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
const confirms = [];
let confirmAnswer = true;
dom.window.confirm = msg => { confirms.push(String(msg)); return confirmAnswer; };
dom.window.alert = msg => { globalThis.__alerts.push(String(msg)); };
// The pages call confirm() and alert() bare as well as through window.
globalThis.confirm = dom.window.confirm;
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
      export { default as AdjustmentsPage } from './src/pages/AdjustmentsPage';
      export { default as ApprovalsPage } from './src/pages/ApprovalsPage';
      export { default as WarehouseInventoryPage } from './src/pages/WarehouseInventoryPage';
      export { default as StoreInventoryPage } from './src/pages/StoreInventoryPage';
      export { default as ProductsPage } from './src/pages/ProductsPage';
      export { default as PriceListPage } from './src/pages/PriceListPage';
      export { default as StoresPage } from './src/pages/StoresPage';
      export { default as WarehousesPage } from './src/pages/WarehousesPage';
      export * as stock from './src/lib/stock/stockPages';
      export * as perms from './src/lib/permissions/products';
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
    b.onResolve({ filter: /^\.{1,2}\/(?:.*\/)?supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a), storage: { from: () => ({}) } };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
  } }],
});
const P = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { createRoot, act, React, ErrorBoundary, stock, perms } = P;

// ── fixture ────────────────────────────────────────────────────────────────
const USERS = {
  owner: { id: 'u-own', full_name: 'Owner Fixture', role: 'owner', is_active: true },
  admin: { id: 'u-adm', full_name: 'Admin Fixture', role: 'admin', is_active: true },
  manager: { id: 'u-mgr', full_name: 'Manager Fixture', role: 'manager', is_active: true },
  manager2: { id: 'u-mgr2', full_name: 'Other Manager Fixture', role: 'manager', is_active: true },
  inventory_manager: { id: 'u-inv', full_name: 'Stock Keeper Fixture', role: 'inventory_manager', is_active: true },
  staff: { id: 'u-stf', full_name: 'Staff Fixture', role: 'staff', is_active: true },
};
const ASSIGN = { manager: ['s-a'], manager2: ['s-a', 's-b'], inventory_manager: ['s-a'], staff: ['s-a'] };
function makeFixture() {
  const t = '2026-10-09T02:00:00Z';
  return {
    stores: [
      { id: 's-a', name: 'Fixture Store A', code: 'FX-A', address: 'x', phone: '1', is_active: true, deleted_at: null, created_at: t },
      { id: 's-b', name: 'Fixture Store B', code: 'FX-B', address: 'x', phone: '1', is_active: true, deleted_at: null, created_at: t },
      { id: 's-old', name: 'Fixture Old Store', code: 'FX-OLD', address: 'x', phone: '1', is_active: false, deleted_at: '2026-09-01T00:00:00Z', created_at: t },
    ],
    warehouses: [
      { id: 'w-1', name: 'Fixture Warehouse', code: 'FX-W', address: 'x', phone: '1', is_active: true, deleted_at: null, created_at: t },
      { id: 'w-old', name: 'Fixture Old Warehouse', code: 'FX-WOLD', address: 'x', phone: '1', is_active: false, deleted_at: '2026-09-01T00:00:00Z', created_at: t },
    ],
    products: [
      { id: 'p-mat', name: 'Fixture Mat', sku: 'FX-1', product_type: 'own', brand_id: 'b-1', brand: null, uom: 'pcs', default_cost_price: 10,
        is_active: true, deleted_at: null, is_important: false, category: null, supplier_name: null, created_at: t },
      { id: 'p-lamp', name: 'Fixture Lamp', sku: 'FX-2', product_type: 'third_party', brand_id: null, brand: 'Old Brand', uom: 'pcs', default_cost_price: 0,
        is_active: true, deleted_at: null, is_important: false, category: null, supplier_name: null, created_at: t },
      { id: 'p-fee', name: 'Fixture Delivery', sku: 'FX-3', product_type: 'no_commission', brand_id: null, brand: null, uom: 'pcs', default_cost_price: 0,
        is_active: true, deleted_at: null, is_important: false, category: null, supplier_name: null, created_at: t },
      { id: 'p-gone', name: 'Fixture Gone', sku: 'FX-9', product_type: 'own', brand_id: null, brand: null, uom: 'pcs', default_cost_price: 0,
        is_active: false, deleted_at: '2026-09-14T05:00:00Z', is_important: false, category: null, supplier_name: null, created_at: t },
    ],
    brands: [{ id: 'b-1', name: 'Fixture Brand', is_active: true, deleted_at: null }],
    categories: [{ id: 'c-1', name: 'Fixture Category', is_active: true, deleted_at: null }],
    suppliers: [{ id: 'su-1', name: 'Fixture Supplier', is_active: true, deleted_at: null }],
    product_categories: [{ product_id: 'p-mat', category_id: 'c-1' }],
    product_suppliers: [{ product_id: 'p-mat', supplier_id: 'su-1' }],
    store_inventory: [
      { id: 'si-1', store_id: 's-a', product_id: 'p-mat', current_qty: 5, low_stock_threshold: 0 },
      { id: 'si-2', store_id: 's-a', product_id: 'p-lamp', current_qty: -2, low_stock_threshold: 0 },
      { id: 'si-3', store_id: 's-b', product_id: 'p-mat', current_qty: 7, low_stock_threshold: 0 },
    ],
    warehouse_inventory: [
      { id: 'wi-1', warehouse_id: 'w-1', product_id: 'p-mat', current_qty: 0, low_stock_threshold: 0 },
    ],
    store_product_prices: [
      { id: 'pr-1', store_id: 's-a', product_id: 'p-mat', selling_price: 100, is_active: true, deleted_at: null },
      { id: 'pr-2', store_id: 's-a', product_id: 'p-gone', selling_price: 100, is_active: true, deleted_at: null },
    ],
    profiles: Object.values(USERS).map(u => ({ ...u, email: `${u.id}@fixture.invalid`, deleted_at: null })),
    user_store_assignments: Object.entries(ASSIGN).flatMap(([k, ids]) => ids.map(s => ({ id: `a-${k}-${s}`, user_id: USERS[k].id, store_id: s }))),
    approval_requests: [
      { id: 'r-adj', request_type: 'adjustment', status: 'pending', requested_by: 'u-stf', approved_by: null, approved_at: null,
        related_record_id: 'p-mat', reason: 'Count', response_note: null, created_at: t,
        payload: { location_type: 'store', location_id: 's-a', product_id: 'p-mat', current_qty: 3, new_qty: 1, difference: -2, reference: 'C-1' } },
      { id: 'r-rej', request_type: 'adjustment', status: 'rejected', requested_by: 'u-stf', approved_by: 'u-mgr', approved_at: t,
        related_record_id: 'p-lamp', reason: 'Count', response_note: 'Count again: the shelf has 4', rejection_reason: 'Count again: the shelf has 4', created_at: t,
        payload: { location_type: 'store', location_id: 's-a', product_id: 'p-lamp', current_qty: -2, new_qty: 0, difference: 2 } },
      { id: 'r-inv', request_type: 'invoice_refund', status: 'pending', requested_by: 'u-stf', approved_by: null, approved_at: null,
        related_record_id: 'i-1', reason: 'Customer changed mind', response_note: null, created_at: t,
        payload: { invoice_id: 'i-1', invoice_no: 'FX-INV-1' } },
    ],
  };
}

// ── fake backend ───────────────────────────────────────────────────────────
function createBackend(fx, who) {
  const b = { calls: [], handlers: {}, failures: new Map(), fx };
  const me = USERS[who];
  const rpcs = {
    my_assigned_stores: () => {
      const all = ['owner', 'admin', 'manager'].includes(me.role);
      return fx.stores.filter(s => !s.deleted_at && s.is_active && (all || fx.user_store_assignments.some(a => a.user_id === me.id && a.store_id === s.id)))
        .map((s, i) => ({ store_id: s.id, store_name: s.name, is_default: i === 0 }));
    },
    request_inventory_adjustments: a => ({ success: true, replayed: false,
      requests: a.p_lines.filter(l => l.new_qty !== 5).map(l => ({ request_id: 'r-new', product_id: l.product_id })),
      unchanged: a.p_lines.filter(l => l.new_qty === 5).map(l => ({ product_id: l.product_id, current_qty: 5 })) }),
    warehouse_stock_ins: a => ({ success: true, replayed: false, lines: a.p_lines.map(l => ({ ...l, movement_id: 'm-1' })) }),
    pending_adjustments_live: () => [{ request_id: 'r-adj', live_qty: 5, product_live: true, place_open: true }],
    resolve_inventory_adjustment: () => ({ success: true }),
    resolve_invoice_action_v2: () => ({ success: true }),
    save_product: a => ({ success: true, product_id: a.p_id ?? 'p-new', created: a.p_id == null }),
    soft_delete_product: () => ({ success: true }),
    restore_product: () => ({ success: true }),
    soft_delete_store: () => ({ success: true }),
    restore_store: () => ({ success: true }),
    soft_delete_warehouse: () => ({ success: true }),
    restore_warehouse: () => ({ success: true }),
    assign_user_store: () => ({ success: true, changed: true }),
    stock_loans_at: () => ({ loans: [], can_act: true, today: '2026-10-09' }),
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], single: false }); }
    select() { return this; }
    eq(c, v) { this.filters.push(r => r[c] === v); return this; }
    is(c, v) { this.filters.push(r => (r[c] ?? null) === v); return this; }
    not(c, op, v) { this.filters.push(r => !((r[c] ?? null) === v)); return this; }
    in(c, vs) { this.filters.push(r => vs.includes(r[c])); return this; }
    order() { return this; }
    update(v) { this.kind = 'update'; this.args = v; return this; }
    insert(v) { this.kind = 'insert'; this.args = v; return this; }
    limit() { return this; }
    maybeSingle() { this.single = true; return this; }
    single() { this.single = true; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args && structuredClone(this.args) });
      await Promise.resolve();
      if (b.failures.has(this.name)) {
        const f = b.failures.get(this.name);
        if (f.once) b.failures.delete(this.name);
        // A refusal from the database carries a code and saved nothing; a
        // failure with no code (no answer) may have saved.
        return { data: null, error: { message: f.message ?? f, code: f.code ?? null } };
      }
      if (this.kind === 'rpc') {
        const fn = b.handlers[this.name] ?? rpcs[this.name];
        if (!fn) return { data: null, error: { message: `unknown rpc ${this.name}` } };
        return { data: structuredClone(fn(this.args)), error: null };
      }
      const rows = (fx[this.name] ?? []).filter(r => this.filters.every(f => f(r)));
      return { data: structuredClone(this.single ? rows[0] ?? null : rows), error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

// ── driving a page ─────────────────────────────────────────────────────────
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount(Page, who, setup) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(makeFixture(), who);
  globalThis.__backend = backend; globalThis.__renderErrors = []; globalThis.__alerts = [];
  const me = USERS[who];
  globalThis.__auth = { profile: me, assignments: backend.fx.user_store_assignments.filter(a => a.user_id === me.id) };
  confirms.length = 0; confirmAnswer = true;
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(Page))));
  await tick();
  if (process.env.STOCK_PAGES_DEBUG) console.log('PAGE TEXT:', text().slice(0, 1500));
  assert.deepEqual(globalThis.__renderErrors, []);
}
const text = () => document.body.textContent;
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const buttons = (scope = document) => [...scope.querySelectorAll('button')];
const button = (label, scope = document) => buttons(scope).find(b => b.textContent.trim() === label);
const buttonWith = (label, scope = document) => buttons(scope).find(b => b.textContent.includes(label));
async function setValue(el, value) {
  assert.ok(el, 'the field exists');
  const proto = el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype
    : el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
  });
  await tick(2);
}
async function tick_box(el) {
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
}
const modal = () => document.querySelector('.modal');
const callsOf = name => backend.calls.filter(c => c.name === name);
const row = label => [...document.querySelectorAll('tr')].find(tr => tr.textContent.includes(label));
async function pickProduct(index, label) {
  const pickers = buttons(modal()).filter(b => b.textContent.includes('Search product name or SKU') || b.textContent.includes('(FX-'));
  await click(pickers[index]);
  const option = [...modal().querySelectorAll('div')].find(d => d.children.length === 1 && d.firstElementChild?.tagName === 'DIV'
    && d.firstElementChild.textContent === label);
  await click(option);
}
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── the shared rules ───────────────────────────────────────────────────────
test('typed totals: whole numbers only, empty is not 0; one id per form', () => {
  assert.equal(stock.parseWholeNumber(''), '');
  assert.equal(stock.parseWholeNumber(' 0 '), 0);
  assert.equal(stock.parseWholeNumber('12'), 12);
  for (const bad of ['2.5', '-1', '1e3', 'abc', '١٢']) assert.equal(stock.parseWholeNumber(bad), null, bad);
  const ok = stock.checkAdjustmentForm('s-a', [{ product_id: 'p-mat', new_qty: '0' }, { product_id: '', new_qty: '' }], ' Count ', ' ');
  assert.deepEqual(ok, { ok: true, value: { p_lines: [{ product_id: 'p-mat', new_qty: 0 }], p_reason: 'Count', p_reference: null } });
  assert.equal(stock.checkAdjustmentForm('', [], 'x', '').error, 'Select a location.');
  assert.equal(stock.checkAdjustmentForm('s-a', [{ product_id: 'p-mat', new_qty: '' }], 'x', '').error, 'Enter the counted total for every product.');
  assert.equal(stock.checkAdjustmentForm('s-a', [{ product_id: 'p-mat', new_qty: '2.5' }], 'x', '').error, 'Enter a whole number of 0 or more as the counted total.');
  assert.equal(stock.checkAdjustmentForm('s-a', [{ product_id: '', new_qty: '3' }], 'x', '').error, 'Pick a product for every counted total.');
  assert.equal(stock.checkAdjustmentForm('s-a', [{ product_id: 'p', new_qty: '1' }, { product_id: 'p', new_qty: '2' }], 'x', '').error, 'The same product is listed more than once.');
  assert.equal(stock.checkAdjustmentForm('s-a', [{ product_id: 'p', new_qty: '1' }], ' ', '').error, 'A reason is required.');
  assert.deepEqual(stock.linesSettingToZero([{ product_id: 'a', new_qty: 0 }, { product_id: 'b', new_qty: 0 }, { product_id: 'c', new_qty: 3 }], { a: 4, b: 0 }), ['a']);
  assert.deepEqual(stock.linesSettingToZero([{ product_id: 'a', new_qty: 0 }], null), ['a'], 'stock not read: ask');
  assert.equal(stock.zeroConfirmText(['Fixture Mat'], 'Fixture Store A'), 'This sets Fixture Mat at Fixture Store A to 0. Is that right?');
  assert.equal(stock.checkStockInForm([{ product_id: 'p', quantity: '0' }], { reason: 'x', note: '', reference: '' }).error,
    'Every product needs a whole quantity greater than zero.');
  assert.equal(stock.checkStockInForm([{ product_id: 'p', quantity: '1.5' }], { reason: 'x', note: '', reference: '' }).error,
    'Every product needs a whole quantity greater than zero.');
  // The page's limit is the server's: 999,999 a line (warehouse_stock_ins).
  for (const big of ['1000000', '12345678']) {
    assert.equal(stock.checkStockInForm([{ product_id: 'p', quantity: big }], { reason: 'x', note: '', reference: '' }).error,
      'A quantity can be at most 999,999.', big);
  }
  assert.deepEqual(stock.checkStockInForm([{ product_id: 'p', quantity: '999999' }], { reason: 'x', note: '', reference: '' }).value.p_lines,
    [{ product_id: 'p', quantity: 999999 }]);
  // The stores a person may count: Owner and Admin every listed store, anyone
  // else (a Manager too) only the stores they work at; unknown stays unknown.
  assert.deepEqual(stock.countableStoreIds('owner', ['s-a', 's-b'], []), ['s-a', 's-b']);
  assert.deepEqual(stock.countableStoreIds('admin', ['s-a', 's-b'], []), ['s-a', 's-b']);
  assert.deepEqual(stock.countableStoreIds('manager', ['s-a', 's-b'], ['s-a']), ['s-a']);
  assert.deepEqual(stock.countableStoreIds('staff', ['s-a'], ['s-a', 's-gone']), ['s-a']);
  assert.equal(stock.countableStoreIds('manager', null, ['s-a']), null);
});

test('stock levels: 0 or less is out of stock, below 0 is also Negative; three product types', () => {
  assert.deepEqual(stock.stockStatus(0, 0), { label: 'Out of Stock', cls: 'badge-danger', negative: false });
  assert.deepEqual(stock.stockStatus(-2, 5), { label: 'Out of Stock', cls: 'badge-danger', negative: true });
  assert.equal(stock.stockStatus(3, 5).label, 'Low Stock');
  assert.equal(stock.stockStatus(6, 5).label, 'Normal');
  assert.equal(stock.stockStatusText(-2, 0), 'Out of Stock (Negative -2)');
  assert.deepEqual(['own', 'third_party', 'no_commission'].map(stock.productTypeLabel), ['Own', '3rd Party', 'No commission']);
  assert.equal(stock.pricedCount(['a', 'b', 'c'], ['a', 'gone', 'gone2']), 1);
});

test('who edits products and who puts people on stores (Q13)', () => {
  assert.deepEqual(['owner', 'admin', 'manager', 'inventory_manager', 'staff'].map(perms.canEditProducts), [true, false, true, true, false]);
  const mgr = { id: 'u-mgr', role: 'manager' };
  const own = { id: 'u-own', role: 'owner' };
  assert.equal(perms.storeAssignmentBlock(mgr, { id: 'u-stf', role: 'staff' }, 's-a', ['s-a']), null);
  assert.equal(perms.storeAssignmentBlock(mgr, { id: 'u-inv', role: 'inventory_manager' }, 's-a', ['s-a']), null);
  assert.equal(perms.storeAssignmentBlock(mgr, { id: 'u-stf', role: 'staff' }, 's-b', ['s-a']), 'You can only put people on the stores you work at.');
  assert.equal(perms.storeAssignmentBlock(mgr, { id: 'u-mgr2', role: 'manager' }, 's-a', ['s-a']), 'Only an Owner can change a Manager\'s stores.');
  assert.equal(perms.storeAssignmentBlock(mgr, { id: 'u-mgr', role: 'manager' }, 's-a', ['s-a']), 'You cannot change your own stores. Ask an Owner.');
  assert.equal(perms.storeAssignmentBlock(own, { id: 'u-mgr', role: 'manager' }, 's-b', []), null);
  assert.equal(perms.storeAssignmentBlock({ id: 'u-stf', role: 'staff' }, { id: 'u-inv', role: 'inventory_manager' }, 's-a', ['s-a']),
    'Only an Owner or Manager can change who works at a store.');
});

// ── New Adjustment (STOCK-2, -4, -5, -8) ───────────────────────────────────
async function openAdjustment() {
  await click(buttonWith('New Adjustment'));
  const selects = modal().querySelectorAll('select');
  return { type: selects[0], place: selects[1] };
}
test('New Adjustment: the person\'s stores; empty, decimal and 0 handled; one call with one id, kept on a retry', async () => {
  await mount(P.AdjustmentsPage, 'staff');
  let f = await openAdjustment();
  const places = [...f.place.querySelectorAll('option')].map(o => o.textContent);
  assert.deepEqual(places, ['— Select —', 'Fixture Store A'], 'only the store this person works at');
  assert.ok(![...f.type.querySelectorAll('option')].some(o => o.value === 'warehouse'), 'Staff have no warehouse');
  await setValue(f.place, 's-a');
  await pickProduct(0, 'Fixture Mat (FX-1)');
  assert.ok(modal().textContent.includes('System now: 5'), 'the line shows the stock now');
  const total = modal().querySelector('input[aria-label="Counted total"]');
  await setValue(modal().querySelector('textarea'), 'Month-end count');
  await click(button('Submit Request'));
  assert.ok(modal().textContent.includes('Enter the counted total for every product.'), 'an empty box is not 0');
  await setValue(total, '2.5');
  await click(button('Submit Request'));
  assert.ok(modal().textContent.includes('Enter a whole number of 0 or more'), 'a decimal is refused');
  await setValue(total, '0');
  assert.equal(total.value, '0', '0 shows as 0');
  confirmAnswer = false;
  await click(button('Submit Request'));
  assert.deepEqual(confirms, ['This sets Fixture Mat at Fixture Store A to 0. Is that right?']);
  assert.equal(callsOf('request_inventory_adjustments').length, 0, 'not sent without the confirmation');
  // A refusal saved nothing: the form stays open to change.
  confirmAnswer = true;
  backend.failures.set('request_inventory_adjustments', { message: 'Fixture Mat: This product is switched off or deleted.', code: 'P0001', once: true });
  await click(button('Submit Request'));
  assert.ok(modal().textContent.includes('Fixture Mat: This product is switched off or deleted. Nothing was saved.'));
  assert.equal(total.disabled, false, 'a refusal leaves the form open');
  // No answer may have saved: the form is locked as it was sent, and pressing
  // again sends the same form with the same id.
  backend.failures.set('request_inventory_adjustments', { message: 'Failed to fetch', once: true });
  await click(button('Submit Request'));
  assert.ok(modal().textContent.includes('Failed to fetch It may or may not have been saved. The form is locked as it was sent'));
  assert.equal(total.disabled, true, 'the form is locked');
  assert.equal(confirms.length, 3, 'each new send of a 0 asks first');
  await click(button('Submit Request again'));
  assert.equal(confirms.length, 3, 'a locked retry does not ask again');
  const sent = callsOf('request_inventory_adjustments').slice(1);
  assert.equal(sent.length, 2);
  assert.deepEqual(sent[1].args.p_lines, [{ product_id: 'p-mat', new_qty: 0 }]);
  assert.equal(sent[1].args.p_location_type, 'store');
  assert.equal(sent[1].args.p_reason, 'Month-end count');
  assert.match(sent[0].args.p_request_id, /^[0-9a-f-]{36}$/);
  assert.equal(sent[1].args.p_request_id, sent[0].args.p_request_id, 'a retry keeps the form id');
  assert.equal(callsOf('request_inventory_adjustment').length, 0, 'the one-line function is not looped');
  assert.equal(modal(), null, 'the form closes once sent');
  assert.ok(text().includes('1 correction sent for approval.'));
  // A new form is a new id; a matching line is named.
  f = await openAdjustment();
  await setValue(f.place, 's-a');
  await pickProduct(0, 'Fixture Mat (FX-1)');
  await setValue(modal().querySelector('input[aria-label="Counted total"]'), '5');
  await setValue(modal().querySelector('textarea'), 'Count');
  await click(button('Submit Request'));
  const third = callsOf('request_inventory_adjustments')[3];
  assert.notEqual(third.args.p_request_id, sent[0].args.p_request_id, 'a new form has a new id');
  assert.ok(text().includes('Left out, because the count matches the system: Fixture Mat (5).'));
});

test('New Adjustment: a Manager is offered only the stores they work at; an Owner every store', async () => {
  // The fixture's Manager works at Store A only. my_assigned_stores() lists
  // both stores for a Manager, but the server refuses a count at Store B.
  await mount(P.AdjustmentsPage, 'manager');
  let f = await openAdjustment();
  assert.deepEqual([...f.place.querySelectorAll('option')].map(o => o.textContent), ['— Select —', 'Fixture Store A']);
  await mount(P.AdjustmentsPage, 'owner');
  f = await openAdjustment();
  assert.deepEqual([...f.place.querySelectorAll('option')].map(o => o.textContent), ['— Select —', 'Fixture Store A', 'Fixture Store B']);
});

test('New Adjustment: the server\'s "already sent" is shown as it is', async () => {
  await mount(P.AdjustmentsPage, 'manager2');
  const f = await openAdjustment();
  await setValue(f.place, 's-b');
  await pickProduct(0, 'Fixture Mat (FX-1)');
  await setValue(modal().querySelector('input[aria-label="Counted total"]'), '6');
  await setValue(modal().querySelector('textarea'), 'Count');
  const msg = 'This form was already sent, and has been changed since: nothing more was sent. Close it, and send any other correction as a new request.';
  backend.failures.set('request_inventory_adjustments', { message: msg, code: 'P0001', once: true });
  await click(button('Submit Request'));
  assert.ok(modal().textContent.includes(msg));
  assert.ok(!modal().textContent.includes('Nothing was saved.'), 'not contradicted');
  assert.equal(callsOf('request_inventory_adjustments')[0].args.p_location_id, 's-b', 'a Manager counts a store they work at');
});

test('Adjustments: a rejected request shows the approver\'s reason to the person who asked', async () => {
  await mount(P.AdjustmentsPage, 'staff');
  const rej = row('Fixture Lamp');
  assert.ok(rej.textContent.includes('Rejected') && rej.textContent.includes('Reason: Count again: the shelf has 4'), rej.textContent);
  assert.ok(!row('Fixture Mat').textContent.includes('Reason:'), 'a pending request has no reason yet');
  assert.ok(read('src/pages/AdjustmentsPage.tsx').includes("header: 'Approver\\'s note'"), 'the export has the approver\'s note');
});

test('Adjustments page: the export reads the request itself; no stale fields', () => {
  const src = read('src/pages/AdjustmentsPage.tsx');
  for (const gone of ['r.location_name', 'r.product_name', 'r.delta', "new_qty || ''", '+e.target.value']) {
    assert.ok(!src.includes(gone), `${gone} is gone`);
  }
  assert.equal(stock.adjustmentPlace({ location_type: 'warehouse', location_id: 'w-1' }, () => 'S', () => 'Fixture Warehouse'), 'Fixture Warehouse');
});

// ── Approvals (STOCK-3, Q11; INVOICES-AFTER-14; INVOICES-CREATE-18) ────────
test('Approvals: the live number beside the count; a moved count is flagged; every rejection needs a reason', async () => {
  await mount(P.ApprovalsPage, 'manager');
  const adj = row('Fixture Mat');
  assert.ok(adj.textContent.includes('3 → 1 (-2)'));
  assert.ok(adj.textContent.includes('Stock changed since this count: now 5. Reject it and count again.'), adj.textContent);
  // Approve shows the server's refusal and reloads.
  backend.failures.set('resolve_inventory_adjustment', { message: 'Stock changed since this count (was 3, now 5). Reject this request and count again.', once: true });
  await click(buttonWith('Approve', adj));
  assert.deepEqual(globalThis.__alerts, ['Stock changed since this count (was 3, now 5). Reject this request and count again.']);
  // An invoice request: Reject stays off until a reason is typed.
  await click(buttonWith('Reject', row('FX-INV-1')));
  const reject = buttons(modal()).find(b => b.textContent === 'Reject');
  assert.ok(modal().textContent.includes('Reason for rejecting *'));
  assert.equal(reject.disabled, true, 'no reason, no rejection');
  await setValue(modal().querySelector('textarea'), 'The goods were used');
  assert.equal(reject.disabled, false);
  await click(reject);
  const inv = callsOf('resolve_invoice_action_v2');
  assert.equal(inv.length, 1);
  assert.equal(inv[0].args.p_note, 'The goods were used');
  // A stock correction needs a reason too, and the person who asked sees it
  // (the Owner, 9 Oct 2026).
  await click(buttonWith('Reject', row('Fixture Mat')));
  assert.ok(modal().textContent.includes('Reason for rejecting *'));
  assert.ok(modal().textContent.includes('The person who asked sees this reason on the Adjustments page.'));
  const rejectAdj = buttons(modal()).find(b => b.textContent === 'Reject');
  assert.equal(rejectAdj.disabled, true, 'no reason, no rejection');
  await setValue(modal().querySelector('textarea'), '   ');
  assert.equal(rejectAdj.disabled, true, 'spaces are not a reason');
  await setValue(modal().querySelector('textarea'), ' Count again ');
  await click(rejectAdj);
  const rejected = callsOf('resolve_inventory_adjustment').filter(c => c.args.p_approve === false);
  assert.equal(rejected.length, 1);
  assert.equal(rejected[0].args.p_note, 'Count again');
  assert.ok(!read('src/pages/ApprovalsPage.tsx').includes('useNavigate'), 'the unused navigate is gone');
});

test('Approvals: a count that still matches says so; a closed place says to reject', async () => {
  await mount(P.ApprovalsPage, 'owner', b => {
    b.handlers.pending_adjustments_live = () => [{ request_id: 'r-adj', live_qty: 3, product_live: true, place_open: false }];
  });
  assert.ok(row('Fixture Mat').textContent.includes('The place is closed or deleted. Reject this request.'));
  assert.deepEqual(stock.liveNote({ current_qty: 3 }, { live_qty: 3, product_live: true, place_open: true }), { text: 'Now 3, as counted.', warn: false });
});

// ── Warehouse Stock (STOCK-5, M3, STOCK-14 item 4) ─────────────────────────
test('Stock In: one call for every line with one id, kept on a retry; the old loop is gone', async () => {
  await mount(P.WarehouseInventoryPage, 'inventory_manager');
  assert.ok(row('Fixture Mat').textContent.includes('Out of Stock'));
  await click(buttonWith('Stock In'));
  await pickProduct(0, 'Fixture Mat (FX-1)');
  await click(buttonWith('+ Add another product', modal()));
  await pickProduct(1, 'Fixture Lamp (FX-2)');
  const qty = modal().querySelectorAll('input[aria-label="Quantity"]');
  await setValue(qty[0], '3');
  await setValue(qty[1], '1.5');
  const reason = [...modal().querySelectorAll('input')].find(i => i.placeholder === 'e.g. New delivery from supplier');
  await setValue(reason, 'Supplier delivery');
  await click(button('Add Stock'));
  assert.ok(modal().textContent.includes('Every product needs a whole quantity greater than zero.'));
  await setValue(qty[1], '4');
  backend.failures.set('warehouse_stock_ins', { message: 'Nothing was added. Switched off or deleted: Fixture Lamp.', code: 'P0001', once: true });
  await click(button('Add Stock'));
  assert.ok(modal().textContent.includes('Nothing was added. Switched off or deleted: Fixture Lamp. Nothing was saved.'));
  assert.equal(qty[0].disabled, false);
  backend.failures.set('warehouse_stock_ins', { message: 'Failed to fetch', once: true });
  await click(button('Add Stock'));
  assert.ok(modal().textContent.includes('It may or may not have been saved. The form is locked as it was sent'));
  assert.equal(qty[0].disabled, true);
  await click(button('Add Stock again'));
  const sent = callsOf('warehouse_stock_ins').slice(1);
  assert.equal(sent.length, 2);
  assert.deepEqual(sent[1].args.p_lines, [{ product_id: 'p-mat', quantity: 3 }, { product_id: 'p-lamp', quantity: 4 }]);
  assert.equal(sent[1].args.p_warehouse_id, 'w-1');
  assert.equal(sent[1].args.p_request_id, sent[0].args.p_request_id);
  assert.equal(callsOf('warehouse_stock_in').length, 0);
  assert.ok(text().includes('Stock added for 2 products at Fixture Warehouse.'));
  assert.ok(!read('src/pages/WarehouseInventoryPage.tsx').includes('07_phase2_fix_rls'));
});

// ── Store Stock (STOCK-12c, M3) ────────────────────────────────────────────
test('Store Stock: only the person\'s stores, a Manager\'s too; below 0 is out of stock and Negative', async () => {
  await mount(P.StoreInventoryPage, 'staff');
  assert.ok(buttonWith('Fixture Store A') && !buttonWith('Fixture Store B'), 'one store for one-store staff');
  assert.equal(callsOf('my_assigned_stores').length >= 1, true);
  const lamp = row('Fixture Lamp');
  assert.ok(lamp.textContent.includes('Out of Stock') && lamp.textContent.includes('Negative (-2)'), lamp.textContent);
  assert.ok(!row('Fixture Mat').textContent.includes('Negative'));
  // A Manager sees only the stores they work at, like Staff (the Owner,
  // 9 Oct 2026), although my_assigned_stores() lists every store for them.
  await mount(P.StoreInventoryPage, 'manager');
  assert.ok(buttonWith('Fixture Store A') && !buttonWith('Fixture Store B'), 'a one-store Manager sees that store only');
  assert.ok(row('Fixture Mat').textContent.includes('5'), 'and opens on it');
  await mount(P.StoreInventoryPage, 'manager2');
  assert.ok(buttonWith('Fixture Store A') && buttonWith('Fixture Store B'), 'a Manager on two stores sees both');
  await click(buttonWith('Fixture Store B'));
  const matB = row('Fixture Mat');
  assert.ok(matB.textContent.includes('7') && matB.textContent.includes('Normal'), matB.textContent);
  await mount(P.StoreInventoryPage, 'owner');
  assert.ok(buttonWith('Fixture Store A') && buttonWith('Fixture Store B'), 'an Owner sees every open store');
  assert.ok(!read('src/pages/StoreInventoryPage.tsx').includes('07_phase2_fix_rls'));
});

// ── Products (STOCK-7, -8, -10, -12a, -14 item 4) ─────────────────────────
test('Products: an Admin looks; an Inventory Manager adds and edits through save_product', async () => {
  await mount(P.ProductsPage, 'admin');
  assert.ok(!buttonWith('Add Product'), 'no Add for an Admin');
  assert.ok(!document.querySelector('button[title="Edit"]'), 'no Edit for an Admin');
  await mount(P.ProductsPage, 'inventory_manager');
  assert.ok(text().includes('Stock levels and low-stock thresholds are set on the Warehouse Stock and Store Stock pages.'));
  assert.ok(!text().includes('Phase 2'));
  await click(document.querySelector('button[title="Edit"]'));
  const cost = [...modal().querySelectorAll('input')].find(i => i.placeholder === '0.00');
  await setValue(cost, '12.345');
  await click(button('Save Changes'));
  assert.ok(modal().textContent.includes('Cost price must be 0 or more, with at most 2 decimal places.'));
  await setValue(cost, '12.5');
  backend.failures.set('save_product', { message: 'That SKU already exists (Fixture Lamp). Use a unique product code.', once: true });
  await click(button('Save Changes'));
  assert.ok(modal().textContent.includes('That SKU already exists (Fixture Lamp).'), 'the refusal is shown');
  await click(button('Save Changes'));
  const saves = callsOf('save_product');
  assert.equal(saves.length, 2);
  assert.equal(saves[1].args.p_id !== null, true);
  assert.equal(saves[1].args.p_fields.default_cost_price, '12.5');
  assert.deepEqual(saves[1].args.p_category_ids, ['c-1']);
  assert.deepEqual(saves[1].args.p_supplier_ids, ['su-1']);
  const src = read('src/pages/ProductsPage.tsx');
  assert.ok(!/from\('product_(categories|suppliers)'\)\.(insert|delete)/.test(src) && !/from\('products'\)\.(insert|update)/.test(src),
    'no direct product writes left');
});

test('Products: Delete shows the server\'s refusal; Show deleted lists Restore; No commission filter', async () => {
  await mount(P.ProductsPage, 'manager');
  assert.ok(!row('Fixture Gone'), 'deleted products are hidden');
  backend.failures.set('soft_delete_product', { message: 'Fixture Mat cannot be deleted yet. Still open: stock (5 at Fixture Store A).', once: true });
  await click(row('Fixture Mat').querySelector('button[title="Delete"]'));
  assert.ok(text().includes('Fixture Mat cannot be deleted yet. Still open: stock (5 at Fixture Store A).'));
  assert.deepEqual(callsOf('soft_delete_product').map(c => c.args), [{ p_product_id: 'p-mat' }]);
  await tick_box([...document.querySelectorAll('input[type="checkbox"]')].find(i => i.parentElement.textContent.includes('Show deleted')));
  assert.ok(row('Fixture Gone') && !row('Fixture Mat'), 'only deleted products');
  await click(buttonWith('Restore', row('Fixture Gone')));
  assert.deepEqual(callsOf('restore_product').map(c => c.args), [{ p_product_id: 'p-gone' }]);
  assert.ok(text().includes('Fixture Gone is back'));
  assert.ok(buttonWith('No commission'), 'a No commission filter');
});

// ── Price List (STOCK-10) ───────────────────────────────────────────────────
test('Price List: a deleted product\'s price is not counted; the three type labels', async () => {
  await mount(P.PriceListPage, 'owner');
  assert.ok(text().includes('1 of 3 products priced'), text());
  assert.ok(buttonWith('No price (2)'));
  assert.ok(row('Fixture Delivery').textContent.includes('No commission'));
  assert.ok(row('Fixture Lamp').textContent.includes('3rd Party'));
});

// ── Stores and Warehouses (STOCK-7; ADMIN-AUTH-15) ─────────────────────────
test('Stores: staff through assign_user_store, with the rules shown; delete and restore through the server', async () => {
  await mount(P.StoresPage, 'manager');
  await click(buttonWith('Staff', row('Fixture Store A')));
  const line = name => [...modal().querySelectorAll('label')].find(l => l.textContent.includes(name));
  const box = name => line(name).querySelector('input');
  assert.ok(!line('Owner Fixture') && !line('Admin Fixture'), 'Owners and Admins are not listed');
  assert.equal(box('Manager Fixture').disabled, true);
  assert.ok(line('Manager Fixture').textContent.includes('You cannot change your own stores.'));
  assert.equal(box('Other Manager Fixture').disabled, true);
  assert.ok(line('Other Manager Fixture').textContent.includes('Only an Owner can change a Manager\'s stores.'));
  assert.equal(box('Stock Keeper Fixture').disabled, false);
  backend.failures.set('assign_user_store', { message: 'You can only put people on the stores you work at.', once: true });
  await tick_box(box('Staff Fixture'));
  assert.ok(modal().textContent.includes('Staff Fixture: You can only put people on the stores you work at.'));
  assert.deepEqual(callsOf('assign_user_store').map(c => c.args), [{ p_user_id: 'u-stf', p_store_id: 's-a', p_assigned: false }]);
  await click(button('Done'));
  // On another store, a Manager who does not work there changes nothing.
  await click(buttonWith('Staff', row('Fixture Store B')));
  assert.equal([...modal().querySelectorAll('input[type="checkbox"]')].every(i => i.disabled), true);
  await click(button('Done'));
  backend.failures.set('soft_delete_store', { message: 'Fixture Store A cannot be deleted yet. Still open: stock of 1 product (5 units).', once: true });
  await click(row('Fixture Store A').querySelector('button[title="Delete"]'));
  assert.ok(text().includes('Fixture Store A cannot be deleted yet.'));
  await tick_box([...document.querySelectorAll('input[type="checkbox"]')].find(i => i.parentElement.textContent.includes('Show deleted')));
  await click(buttonWith('Restore', row('Fixture Old Store')));
  assert.deepEqual(callsOf('restore_store').map(c => c.args), [{ p_store_id: 's-old' }]);
  const src = read('src/pages/StoresPage.tsx');
  assert.ok(!/from\('user_store_assignments'\)\.(insert|delete)/.test(src) && !/deleted_at: new Date/.test(src));
  assert.ok(!src.includes('RLS automatically limits stores'));
});

test('Stores: Staff see the stores they work at; Warehouses delete and restore through the server', async () => {
  await mount(P.StoresPage, 'staff');
  assert.ok(row('Fixture Store A') && !row('Fixture Store B'));
  assert.ok(text().includes("You're viewing the 1 store you work at."));
  assert.ok(!buttonWith('Add Store') && !buttonWith('Staff'));
  await mount(P.WarehousesPage, 'owner');
  backend.failures.set('soft_delete_warehouse', { message: 'Fixture Warehouse cannot be deleted yet. Still open: 1 open transfer.', once: true });
  await click(row('Fixture Warehouse').querySelector('button[title="Delete"]'));
  assert.ok(text().includes('Fixture Warehouse cannot be deleted yet. Still open: 1 open transfer.'));
  assert.deepEqual(callsOf('soft_delete_warehouse').map(c => c.args), [{ p_warehouse_id: 'w-1' }]);
  await tick_box([...document.querySelectorAll('input[type="checkbox"]')].find(i => i.parentElement.textContent.includes('Show deleted')));
  await click(buttonWith('Restore', row('Fixture Old Warehouse')));
  assert.deepEqual(callsOf('restore_warehouse').map(c => c.args), [{ p_warehouse_id: 'w-old' }]);
  assert.ok(!/deleted_at: new Date/.test(read('src/pages/WarehousesPage.tsx')));
});

test('Stores and Warehouses: switching off a place that holds stock shows the server\'s refusal and saves nothing', async () => {
  // The Owner, 9 Oct 2026: a store or warehouse is not switched off while it
  // still holds stock. The database refuses the whole save and says why.
  await mount(P.StoresPage, 'owner');
  await click(row('Fixture Store A').querySelector('button[title="Edit"]'));
  const active = [...modal().querySelectorAll('label')].find(l => l.textContent.trim() === 'Active').querySelector('input');
  assert.ok(!modal().textContent.includes('cannot be switched off'), 'no hint while it stays on');
  await tick_box(active);
  assert.ok(modal().textContent.includes('A store that still holds stock, or has stock on the way, cannot be switched off.'));
  const refusal = 'Fixture Store A cannot be switched off yet. Still open: stock of 1 product (5 units).';
  backend.failures.set('stores', { message: refusal, code: 'P0001', once: true });
  // The reason sits at the top of a long form, far above Save: it is brought
  // into view (jsdom has no scrolling, so scrollIntoView is recorded).
  const scrolled = [];
  const hadScroll = Object.prototype.hasOwnProperty.call(dom.window.Element.prototype, 'scrollIntoView');
  const oldScroll = dom.window.Element.prototype.scrollIntoView;
  dom.window.Element.prototype.scrollIntoView = function (opts) { scrolled.push({ text: this.textContent, role: this.getAttribute('role'), opts }); };
  try {
    await click(button('Save'));
    assert.ok(modal(), 'the form stays open');
    assert.ok(modal().textContent.includes(refusal), modal().textContent);
    assert.equal(scrolled.length, 1, 'the refusal is scrolled into view once');
    assert.ok(scrolled[0].text.includes(refusal) && scrolled[0].role === 'alert', JSON.stringify(scrolled));
    assert.deepEqual(scrolled[0].opts, { block: 'nearest' });
    const sent = backend.calls.filter(c => c.kind === 'update' && c.name === 'stores');
    assert.equal(sent.length, 1);
    assert.equal(sent[0].args.is_active, false);
    // A code that is taken is still said as such (by the error's code), and
    // brought into view too.
    backend.failures.set('stores', { message: 'duplicate key value violates unique constraint "stores_code_key"', code: '23505', once: true });
    await click(button('Save'));
    assert.ok(modal().textContent.includes('That code already exists.'));
    assert.equal(scrolled.length, 2, 'the second message is scrolled into view');
    assert.ok(scrolled[1].text.includes('That code already exists.'));
  } finally {
    if (hadScroll) dom.window.Element.prototype.scrollIntoView = oldScroll;
    else delete dom.window.Element.prototype.scrollIntoView;
  }

  await mount(P.WarehousesPage, 'manager');
  await click(row('Fixture Warehouse').querySelector('button[title="Edit"]'));
  await tick_box([...modal().querySelectorAll('label')].find(l => l.textContent.trim() === 'Active').querySelector('input'));
  assert.ok(modal().textContent.includes('A warehouse that still holds stock, or has stock on the way, cannot be switched off.'));
  const whRefusal = 'Fixture Warehouse cannot be switched off yet. Still open: 1 open transfer.';
  backend.failures.set('warehouses', { message: whRefusal, code: 'P0001', once: true });
  await click(button('Save'));
  assert.ok(modal() && modal().textContent.includes(whRefusal));
});
