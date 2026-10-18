// The Dashboard, rendered for real against a fake backend (427).
//
// The actual src/pages/DashboardPage.tsx is bundled with esbuild and mounted in
// jsdom. Only the Supabase client, the auth context and the router's navigate
// are stubbed. Every name and amount below is invented.
//
// It checks what the audit of 9 Oct 2026 found and 427 fixed:
//   REPORTS-4   the alert cards show on a quiet day (no approval, no low
//               stock, no transfer), whenever any of them has something;
//   REPORTS-5   a failed read is said, never shown as nothing; the sales card
//               says why it is empty; loading always ends;
//   REPORTS-6   "Unpaid commission" and "To recover" as the Commissions page
//               shows them, and "Voucher uses this month", from the server; no
//               read of the commissions or voucher_redemptions tables;
//   REPORTS-12  the Sales card has its own padding and its rows can shrink;
//   REPORTS-13  overdue rentals against today in Singapore;
//   REPORTS-16  no "System Complete" card; transfers counted once;
//   REPORTS-M3  "Settled with no imported order"; W2-B08-ALERT: refunded or
//               cancelled sales still holding credit or rewards.
//   W4-B13-NO-SOURCE-TILE (the Owner, 18 Oct 2026): "Customers without
//               source" counts only customers added since 1 Aug 2026, and its
//               label says so.
//
// Run: node --test scripts/dashboard/tests/dashboard-page.test.mjs
process.env.TZ = 'America/Los_Angeles'; // far from Singapore, so a UTC or local date shows

import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://dashboard.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'Element', 'Node', 'Event', 'KeyboardEvent',
  'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
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
      export { default as DashboardPage } from './src/pages/DashboardPage';
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
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onResolve({ filter: /^react-router-dom$/ }, () => ({ path: 'router', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^router$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useNavigate = () => (to) => globalThis.__navigated.push(to);' }));
  } }],
});
const { DashboardPage, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture and fake backend ───────────────────────────────────────────────
// A quiet day: no approval waiting, no low stock, no transfer to receive.
function quietDay() {
  return {
    tables: {
      transfer_requests: [], approval_requests: [],
      products: [{ id: 'p-1', name: 'Fixture Soap', sku: 'FX-1', deleted_at: null }],
      warehouses: [{ id: 'w-1', name: 'Fixture Warehouse', deleted_at: null }],
      stores: [{ id: 's-1', name: 'Fixture North Store With A Long Name', deleted_at: null }, { id: 's-2', name: 'Fixture South', deleted_at: null }],
      payment_methods: [{ id: 'm-1', deleted_at: null }],
      warehouse_inventory: [{ id: 'wi-1', warehouse_id: 'w-1', product_id: 'p-1', current_qty: 50, low_stock_threshold: 5 }],
      store_inventory: [{ id: 'si-1', store_id: 's-1', product_id: 'p-1', current_qty: 20, low_stock_threshold: 2 }],
      rentals: [
        { id: 'r-1', status: 'active', expected_return_date: '2026-10-09' },
        { id: 'r-2', status: 'paid', expected_return_date: '2026-10-10' },
      ],
      commissions: [{ id: 'c-1', commission_amount: 96.62, status: 'earned' }],
      voucher_redemptions: [{ id: 'vr-1' }],
    },
    rpcs: {
      dashboard_sales: a => ({ period: a.p_period, label: a.p_period === 'day' ? 'Today' : 'This week', sales: 1234.5, invoice_count: 3,
        items_sold: 4, discount_total: 10, average_invoice: 411.5, previous_sales: 1000, change_percent: 23.5 }),
      dashboard_sales_by_store: () => [
        { store_id: 's-1', store_name: 'Fixture North Store With A Long Name', sales: 1000, invoice_count: 2 },
        { store_id: 's-2', store_name: 'Fixture South', sales: 234.5, invoice_count: 1 }],
      dashboard_credit_spend: () => ({ label: 'Today', credit_spent: 50, invoices: 1 }),
      dashboard_credit_by_store: () => [{ store_id: 's-1', store_name: 'Fixture North Store With A Long Name', credit_spent: 30, invoices: 1 },
        { store_id: 's-2', store_name: 'Fixture South', credit_spent: 20, invoices: 1 }],
      dashboard_summary: () => ({ role: 'owner', today_sales: 0, today_count: 0, blocked_commission: 0, therapy_awaiting: 1,
        therapy_deadline_warn: 0, discount_today: 0, unpaid_commission: 737.03, commission_deductions: 555.27, voucher_uses_month: 38 }),
      transfer_receipt_alerts: () => ({ awaiting_receipt: 0, overdue: 0, open_discrepancies: 0 }),
      report_customer_sources: () => [],
      tiktok_negative_stock_alerts: () => [{ store_name: 'Fixture South', kind: 'product', item_name: 'Fixture Soap', current_qty: -1 }],
      dashboard_alerts_summary: () => ({
        transfers: { awaiting_receipt: 0, overdue_7d: 0, open_discrepancies: 0 },
        tiktok: { imported_orders: 9, unmatched_skus: 0, staged_batches: 0, orders_awaiting_settlement: 3, settled_without_order: 1,
          settlement_mismatches: 1, awaiting_physical_return: 0, negative_stock: 1 },
        surveys: { customers_without_source: 4, customers_without_source_since: '2026-08-01' },
        sales: { holding_benefits: 1, invoice_nos: ['INV-2026-0174'] },
      }),
      report_foc_lines: () => [],
    },
  };
}
function createBackend(fx) {
  // failures: every read of that table or function fails. headFailures: only
  // the head-count reads of that table fail (the tiles' counts).
  const b = { calls: [], failures: new Map(), headFailures: new Map() };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], head: false, cols: '*', rangeV: null }); }
    select(cols, opts) { this.cols = cols ?? '*'; this.head = !!opts?.head; return this; }
    eq(col, v) { this.filters.push(r => r[col] === v); return this; }
    is(col, v) { this.filters.push(r => (r[col] ?? null) === v); return this; }
    in(col, vals) { this.filters.push(r => vals.includes(r[col])); return this; }
    order() { return this; }
    range(a, z) { this.rangeV = [a, z]; return this; }
    async exec() {
      b.calls.push({ name: this.name, args: this.args, cols: this.cols });
      await Promise.resolve();
      if (b.failures.has(this.name)) return { data: null, count: null, error: { message: b.failures.get(this.name) } };
      if (this.head && b.headFailures.has(this.name)) return { data: null, count: null, error: { message: b.headFailures.get(this.name) } };
      const src = this.kind === 'table' ? fx.tables[this.name] : fx.rpcs[this.name]?.(this.args ?? {});
      if (src === undefined) return { data: null, error: { message: `unknown ${this.kind} ${this.name}` } };
      if (!Array.isArray(src)) return { data: src, error: null };
      let rows = src.filter(r => this.filters.every(f => f(r)));
      if (this.head) return { data: null, count: rows.length, error: null };
      const [from, to] = this.rangeV ?? [0, Infinity];
      return { data: rows.slice(from, Math.min(to + 1, from + 1000)), count: null, error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount({ fixture, setup, role = 'owner' } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(fixture ?? quietDay());
  globalThis.__backend = backend; globalThis.__renderErrors = []; globalThis.__navigated = [];
  globalThis.__auth = { profile: { id: 'u-1', full_name: 'Fixture Owner', role } };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(DashboardPage))));
  await tick();
}
const text = () => document.body.textContent;
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); };
const tile = label => [...document.querySelectorAll('[data-testid="alert-tile"]')].find(t => t.firstElementChild?.textContent === label);
const statCard = label => [...document.querySelectorAll('.card')].find(c => [...c.querySelectorAll('div')].some(d => d.textContent === label && d.children.length === 0));
const statValue = label => [...document.querySelectorAll('.card div')].find(d => d.textContent === label && d.children.length === 0)?.previousElementSibling?.textContent;
const callsOf = name => backend.calls.filter(c => c.name === name);
const button = label => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === label);
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── tests ──────────────────────────────────────────────────────────────────
test('REPORTS-4: on a quiet day the alert cards still show what they have', async () => {
  await mount();
  assert.deepEqual(globalThis.__renderErrors, []);
  assert.ok(!text().includes('Pending Approvals') && !text().includes('Low Stock Alerts'), 'fixture: no approval and no low stock');
  assert.ok(document.querySelector('[data-testid="alerts-grid"]'), 'the alert cards show');
  assert.ok(text().includes('Operations Alerts'));
  assert.equal(tile('Settlement mismatches').lastElementChild.textContent, '1');
  assert.equal(tile('Orders awaiting settlement').lastElementChild.textContent, '3');
  assert.ok(text().includes('Negative TikTok Stock'), 'the negative stock card shows too');
});

test('REPORTS-16 and M3: transfers are counted once; the new alerts are there; no "System Complete" card', async () => {
  await mount();
  for (const gone of ['Transfers awaiting receipt', 'Transfers overdue > 7 days', 'Open transfer discrepancies']) {
    assert.equal(tile(gone), undefined, `no "${gone}" tile: the Transfers card counts them`);
  }
  assert.ok(!text().includes('System Complete'), 'the leftover card is gone');
  assert.equal(tile('Settled with no imported order').lastElementChild.textContent, '1');
  await click(tile('Settled with no imported order'));
  assert.deepEqual(globalThis.__navigated, ['/tiktok-import']);
  const held = tile('Refunded or cancelled sales still holding credit or rewards');
  assert.ok(held, 'the refunded-sales alert is there');
  assert.ok(held.textContent.includes('INV-2026-0174'), 'and names the invoice');
  assert.equal(held.children[1].textContent, '1');
  await click(held);
  assert.deepEqual(globalThis.__navigated, ['/tiktok-import', '/invoices']);
});

test('W4-B13-NO-SOURCE-TILE: the tile says it counts customers added since 1 Aug 2026', async () => {
  await mount();
  assert.deepEqual(globalThis.__renderErrors, []);
  // The page runs in Los Angeles time: a date read through Date would say 31 Jul.
  const t = tile('Customers without source (added since 1 Aug 2026)');
  assert.ok(t, 'the tile names the day it counts from: ' + [...document.querySelectorAll('[data-testid="alert-tile"]')].map(x => x.firstElementChild?.textContent).join(' | '));
  assert.equal(t.lastElementChild.textContent, '4');
  assert.equal(tile('Customers without source'), undefined, 'no tile without the day');
  await click(t);
  assert.deepEqual(globalThis.__navigated, ['/customers']);
});

test('W4-B13-NO-SOURCE-TILE: a server that sends no day keeps the plain label (it still counts everyone)', async () => {
  const fx = quietDay();
  const alerts = fx.rpcs.dashboard_alerts_summary;
  fx.rpcs.dashboard_alerts_summary = () => ({ ...alerts(), surveys: { customers_without_source: 12800 } });
  await mount({ fixture: fx });
  assert.equal(tile('Customers without source').lastElementChild.textContent, '12800');
  assert.ok(!text().includes('added since'));
});

test('REPORTS-16: the Transfers card shows when there is something to receive', async () => {
  const fx = quietDay();
  fx.rpcs.transfer_receipt_alerts = () => ({ awaiting_receipt: 2, overdue: 1, open_discrepancies: 0 });
  await mount({ fixture: fx });
  assert.ok(text().includes('Awaiting receipt: 2') && text().includes('Overdue > 7 days: 1'));
});

test('REPORTS-6: unpaid commission, what is to recover and voucher uses come from the server', async () => {
  await mount();
  const unpaid = statCard('Unpaid commission');
  assert.ok(unpaid, 'the tile is there');
  assert.ok(unpaid.textContent.includes('S$737.03'), unpaid.textContent);
  assert.ok(unpaid.textContent.includes('To recover S$555.27'), unpaid.textContent);
  const uses = statCard('Voucher uses this month');
  assert.ok(uses && uses.textContent.includes('38'), 'voucher uses this month, labelled');
  assert.equal(callsOf('commissions').length, 0, 'the commissions table is not read');
  assert.equal(callsOf('voucher_redemptions').length, 0, 'voucher_redemptions is not read');
});

test('REPORTS-13: a rental due yesterday in Singapore is overdue, also before 8 am', async () => {
  const RealDate = globalThis.Date;
  // 01:30 on 10 Oct in Singapore: still 9 Oct in UTC and in Los Angeles.
  const fixed = RealDate.parse('2026-10-09T17:30:00Z');
  class FrozenDate extends RealDate { constructor(...a) { super(...(a.length ? a : [fixed])); } static now() { return fixed; } }
  globalThis.Date = FrozenDate;
  try {
    await mount();
    assert.equal(statValue('Overdue rentals'), '1', 'r-1, due 9 Oct, is overdue on 10 Oct in Singapore');
    assert.equal(statValue('Rentals out (paid/active)'), '2');
  } finally { globalThis.Date = RealDate; }
});

test('REPORTS-5: a failed sales read is said in the Sales card, with the server\'s reason', async () => {
  await mount({ setup: b => b.failures.set('dashboard_sales', 'The end date cannot be before the start date') });
  const card = document.querySelector('[data-testid="sales-card"]');
  assert.ok(card.querySelector('[role="alert"]').textContent.includes('The end date cannot be before the start date'));
  assert.ok(!card.textContent.includes('Loading…'), 'loading ends');
});

test('REPORTS-5: a failed credit read is said, and the sales still show', async () => {
  await mount({ setup: b => b.failures.set('dashboard_credit_spend', 'credit read failed') });
  const card = document.querySelector('[data-testid="sales-card"]');
  assert.ok(card.textContent.includes('S$1,234.50'), 'the sales figure shows');
  assert.ok(card.querySelector('[role="alert"]').textContent.includes('Settled from credit: credit read failed'));
});

test('REPORTS-5: a failed read below the Sales panel is listed, and the other cards still load', async () => {
  await mount({ setup: b => { b.failures.set('warehouse_inventory', 'inventory read failed'); b.failures.set('dashboard_alerts_summary', 'alerts failed'); } });
  const banner = document.querySelector('[data-testid="alerts-error"]');
  assert.ok(banner, 'a notice says something could not be loaded');
  assert.ok(banner.textContent.includes('Low stock: inventory read failed'), banner.textContent);
  assert.ok(banner.textContent.includes('Operations alerts: alerts failed'), banner.textContent);
  assert.ok(text().includes('Negative TikTok Stock'), 'the other cards still load');
  assert.ok(statCard('Unpaid commission').textContent.includes('S$737.03'));
  assert.ok(!statCard('Active products').textContent.includes('—'), 'loading ends');
});

test('REPORTS-5: counts that could not be read show a dash and are named, not 0', async () => {
  await mount({ setup: b => { for (const t of ['products', 'warehouses', 'stores']) b.headFailures.set(t, `${t} count failed`); } });
  assert.deepEqual(globalThis.__renderErrors, []);
  for (const label of ['Active products', 'Warehouses', 'Stores']) assert.equal(statValue(label), '—', `${label} shows a dash`);
  const banner = document.querySelector('[data-testid="alerts-error"]');
  assert.ok(banner, 'a notice says something could not be loaded');
  for (const [label, t] of [['Active products', 'products'], ['Warehouses', 'warehouses'], ['Stores', 'stores']]) {
    assert.ok(banner.textContent.includes(`${label}: ${t} count failed`), banner.textContent);
  }
  assert.ok(text().includes('Operations Alerts'), 'the other cards still load');
  assert.equal(callsOf('payment_methods').length, 0, 'the unused payment methods count is not read');
});

test('REPORTS-5: one count failing beside a failed alert read: both are named, the other counts show', async () => {
  await mount({ setup: b => { b.headFailures.set('warehouses', 'warehouses count failed'); b.failures.set('warehouse_inventory', 'inventory read failed'); } });
  assert.equal(statValue('Warehouses'), '—');
  assert.equal(statValue('Active products'), '1');
  assert.equal(statValue('Stores'), '2');
  const banner = document.querySelector('[data-testid="alerts-error"]');
  assert.ok(banner.textContent.includes('Warehouses: warehouses count failed'), banner.textContent);
  assert.ok(banner.textContent.includes('Low stock: inventory read failed'), banner.textContent);
});

test('REPORTS-5: a failed summary shows a dash, not S$0.00', async () => {
  await mount({ setup: b => b.failures.set('dashboard_summary', 'summary failed') });
  assert.ok(statCard('Unpaid commission').textContent.includes('—'));
  assert.ok(!statCard('Unpaid commission').textContent.includes('S$0.00'));
  assert.ok(document.querySelector('[data-testid="alerts-error"]').textContent.includes('Summary cards: summary failed'));
});

test('REPORTS-12: the Sales card has its own padding and its rows can shrink on a phone', async () => {
  await mount();
  await click(button('This week')); await tick();
  const card = document.querySelector('[data-testid="sales-card"]');
  assert.equal(card.style.padding, '20px');
  const rows = [...card.querySelectorAll('[data-testid="store-row"], [data-testid="credit-store-row"]')];
  assert.equal(rows.length, 4, 'two by-store rows and two credit rows');
  for (const row of rows) {
    const [name] = row.children;
    assert.equal(name.style.flex, '1 1 120px', 'the name column shrinks');
    assert.equal(name.style.minWidth, '0px');
    assert.ok(![...row.children].some(c => /170px|110px|60px/.test(c.style.flex)), 'no fixed-width column');
  }
});

test('Staff see the Sales panel and the alerts, not the Manager cards', async () => {
  await mount({ role: 'staff' });
  assert.equal(callsOf('dashboard_summary').length, 0);
  assert.equal(statCard('Unpaid commission'), undefined);
  assert.ok(text().includes('Operations Alerts'));
  assert.equal(document.querySelector('[data-testid="alerts-error"]'), null, 'nothing failed');
});
