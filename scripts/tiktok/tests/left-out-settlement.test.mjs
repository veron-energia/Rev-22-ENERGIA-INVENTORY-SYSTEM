// Settled TikTok money left out at confirmation: warned about, listed, and
// includable later — counting a restated line by its difference only — and a
// database from before 368 says it cannot list them, rather than "nothing".
//
// The actual src/pages/TikTokImportPage.tsx and SettlementSummary are bundled
// with esbuild and mounted in jsdom. Only the Supabase client, the auth context,
// xlsx and papaparse are stubbed: the client by a small in-memory PostgREST. The
// rows, ids, file names and amounts below are invented.
//
// Run: node --test scripts/tiktok/tests/left-out-settlement.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import { settlementPeriod, toIsoDate } from '../../../src/lib/tiktok/settlementPeriod.mjs';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ── the page, bundled ──────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://tiktok.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'Element', 'Node', 'Event',
  'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
// As in the Reports page test: act() hands work over on a MessageChannel whose
// ports would keep the runner alive after the last test.
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
      export { SettlementSummary } from './src/components/tiktok/SettlementSummary';
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
    b.onResolve({ filter: /^(xlsx|papaparse)$/ }, a => ({ path: a.path, namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    // No file is parsed here; the page only needs the imports to resolve.
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js', contents: 'export const read = () => { throw new Error("xlsx"); }; export const utils = {};' }));
    b.onLoad({ filter: /^papaparse$/, namespace: 'stub' }, () => ({ loader: 'js', contents: 'export default { parse: () => { throw new Error("papaparse"); } };' }));
  } }],
});
const { TikTokImportPage, SettlementSummary, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const STORE = 'st-1';
const BATCH = 'b-1';
// Four lines a confirmed file left unticked: two on one order, two single ones.
const leftOutLines = () => [
  { row_id: 'lo-1', order_id: 'ORD-100001', transaction_type: 'Order', settled_date: '2026-08-01', settlement_amount: 117.80, revenue_amount: 130, fee_amount: -12.20, match_status: 'pending', file_name: 'income_sample_a.xlsx' },
  { row_id: 'lo-2', order_id: 'ORD-100001', transaction_type: 'Order', settled_date: '2026-08-01', settlement_amount: 259.54, revenue_amount: 280, fee_amount: -20.46, match_status: 'pending', file_name: 'income_sample_a.xlsx' },
  { row_id: 'lo-3', order_id: 'ORD-100002', transaction_type: 'Order', settled_date: '2026-08-02', settlement_amount: 65.26, revenue_amount: 70, fee_amount: -4.74, match_status: 'pending', file_name: 'income_sample_a.xlsx' },
  { row_id: 'lo-4', order_id: 'ORD-100003', transaction_type: 'Order', settled_date: '2026-08-03', settlement_amount: 7.65, revenue_amount: 9, fee_amount: -1.35, match_status: 'pending', file_name: 'income_sample_a.xlsx' },
];
// An unticked restatement of a line that is counted at 100.00: including it
// replaces that line, so the totals change by -5.00, not +95.00.
const restatedLine = () => ({ row_id: 'lo-5', order_id: 'ORD-100004', transaction_type: 'Order', settled_date: '2026-08-04',
  settlement_amount: 95, revenue_amount: 110, fee_amount: -15, match_status: 'pending', file_name: 'income_sample_c.xlsx',
  staging_status: 'Updated — Requires Confirmation', replaces_settlement: 100, net_change: -5 });
// A staged file: matched and finance rows are pre-ticked, the pending one is not.
const stagedRows = () => [
  { id: 'sr-1', batch_id: BATCH, row_no: 1, order_id: 'ORD-200001', transaction_type: 'Order', txn_class: 'order', settlement_amount: 50, revenue_amount: 55, fee_amount: -5, match_status: 'matched', staging_status: 'New — Matched', excluded: false, confirmed: false, reconciled: true, version_no: 1 },
  { id: 'sr-2', batch_id: BATCH, row_no: 2, order_id: 'ADS-1', transaction_type: 'GMV Payment for TikTok Ads', txn_class: 'finance', settlement_amount: -20, revenue_amount: 0, fee_amount: 0, match_status: 'no_match_needed', staging_status: 'New — No Match Needed', excluded: false, confirmed: false, reconciled: true, version_no: 1 },
  { id: 'sr-3', batch_id: BATCH, row_no: 3, order_id: 'ORD-200002', transaction_type: 'Order', txn_class: 'order', settlement_amount: 65.26, revenue_amount: 70, fee_amount: -4.74, match_status: 'pending', staging_status: 'New — Pending Order', excluded: false, confirmed: false, reconciled: true, version_no: 1 },
  { id: 'sr-4', batch_id: BATCH, row_no: 4, order_id: 'ORD-200003', transaction_type: 'Order', txn_class: 'order', settlement_amount: 12, revenue_amount: 13, fee_amount: -1, match_status: 'matched', staging_status: 'Already Imported', excluded: false, confirmed: false, reconciled: true, version_no: 1 },
];

// ── fake backend ───────────────────────────────────────────────────────────
// `database: 'old'` is one from before 368: no left-out function, and totals
// without the left-out keys.
function createBackend({ database = 'new' } = {}) {
  // failures: name -> message (code XX000) or { code, message }.
  const b = { calls: [], failures: new Map(), held: new Map(), leftOut: leftOutLines(), includeError: null };
  b.hold = name => { let release; const gate = new Promise(r => { release = r; }); b.held.set(name, gate); return () => release(); };
  const tables = {
    stores: [{ id: STORE, name: 'North Store', deleted_at: null, is_active: true }],
    products: [], vouchers: [], promotions: [], tiktok_status_mappings: [], tiktok_physical_returns: [],
    tiktok_import_batches: [{ id: BATCH, file_name: 'income_sample_b.xlsx', file_kind: 'settlement', status: 'staged', store_id: STORE }],
    tiktok_settlement_rows: stagedRows(),
  };
  b.tables = tables;
  // As 368 reports it: what including the lines would change the totals by.
  const sum = rows => Number(rows.reduce((s, r) => s + (r.net_change ?? r.settlement_amount), 0).toFixed(2));
  const rpcs = {
    my_assigned_store_id: () => globalThis.__assigned ?? null,
    // Staff read every store they work at (X-9); here the one they are given.
    my_assigned_stores: () => (globalThis.__assigned ? [{ store_id: globalThis.__assigned, store_name: 'North Store', is_default: true }] : []),
    report_tiktok_imports: () => [{ batch_id: BATCH, file_name: 'income_sample_b.xlsx', file_kind: 'settlement', status: tables.tiktok_import_batches[0].status,
      store_name: 'North Store', uploaded_at: '2026-09-01T02:00:00Z', row_count: 4, units_deducted: 0, units_returned: 0 }],
    report_tiktok_settlement: () => [],
    tiktok_settlement_totals: a => ({ year: a.p_year, month: a.p_month, period_start: '', period_end: '', timezone: 'Asia/Singapore', row_count: 3,
      revenue: 1200, fee: 150, settlement: 1050, expense: 100, income: 950, tiktok_net_settlement: 950, by_category: {}, unknown_count: 0,
      balance_movement_count: 0, pending_match_count: 0, currency_count: 1, undated_count: 0, needs_review: false,
      ...(database === 'new' ? { left_out_count: b.leftOut.length, left_out_settlement: sum(b.leftOut) } : {}) }),
    tiktok_left_out_settlement: () => database === 'new' ? b.leftOut
      : { error: { code: 'PGRST202', message: 'Could not find the function public.tiktok_left_out_settlement(p_from, p_store_id, p_to) in the schema cache' } },
    include_tiktok_settlement_rows: a => {
      if (b.includeError) return { error: { code: 'P0001', message: b.includeError } };
      const before = b.leftOut.length;
      b.leftOut = b.leftOut.filter(r => !a.p_row_ids.includes(r.row_id));
      return { success: true, included: before - b.leftOut.length, skipped: 0 };
    },
    confirm_tiktok_settlement_batch: a => {
      tables.tiktok_import_batches[0].status = 'confirmed';
      for (const r of tables.tiktok_settlement_rows) {
        if (a.p_row_ids.includes(r.id)) Object.assign(r, { confirmed: true, is_current: true }); else r.excluded = true;
      }
      return { success: true, applied: a.p_row_ids.length, skipped: tables.tiktok_settlement_rows.length - a.p_row_ids.length,
        versioned_updates: 0, pending: 0, unreconciled: 0 };
    },
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], orders: [], rangeV: null, one: false }); }
    select() { return this; }
    is(col, v) { this.filters.push(r => (r[col] ?? null) === v); return this; }
    eq(col, v) { this.filters.push(r => r[col] === v); return this; }
    in(col, vs) { this.filters.push(r => vs.includes(r[col])); return this; }
    order(col) { this.orders.push(col); return this; }
    range(a, z) { this.rangeV = [a, z]; return this; }
    single() { this.one = true; return this; }
    async exec() {
      b.calls.push({ name: this.name, args: this.args });
      const gate = b.held.get(this.name);
      if (gate) { b.held.delete(this.name); await gate; }
      await Promise.resolve();
      if (b.failures.has(this.name)) {
        const f = b.failures.get(this.name);
        return { data: null, error: typeof f === 'string' ? { code: 'XX000', message: f } : f };
      }
      const src = this.kind === 'table' ? tables[this.name] : rpcs[this.name]?.(this.args);
      if (src === undefined) return { data: null, error: { code: 'PGRST202', message: `unknown ${this.kind} ${this.name}` } };
      if (src && src.error) return { data: null, error: src.error };
      if (!Array.isArray(src)) return { data: src, error: null };
      let rows = src.filter(r => this.filters.every(f => f(r)));
      if (this.orders.length) rows = [...rows].sort((x, y) => {
        for (const c of this.orders) { if (x[c] === y[c]) continue; return x[c] < y[c] ? -1 : 1; }
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
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount({ role = 'owner', assigned = null, database = 'new', setup, element } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend({ database });
  globalThis.__backend = backend; globalThis.__renderErrors = []; globalThis.__assigned = assigned;
  globalThis.__auth = { profile: { id: 'u-1', full_name: 'Test User', role } };
  alerts = [];
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, element ?? React.createElement(TikTokImportPage))));
  await tick();
}
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await tick(); };
const button = label => [...document.querySelectorAll('button')].find(x => x.textContent.trim().startsWith(label));
const openTab = label => click([...document.querySelectorAll('button')].find(x => x.textContent.trim() === label));
const callsOf = name => backend.calls.filter(c => c.name === name);
const notice = () => document.querySelector('[data-testid="left-out-notice"]');
const section = () => document.querySelector('[data-testid="left-out"]');
const listed = () => [...section().querySelectorAll('tbody tr')].map(tr => [...tr.querySelectorAll('td')].map(td => td.textContent));
const boxes = el => [...el.querySelectorAll('tbody input[type="checkbox"]')];
async function setValue(el, value, event = 'input') {
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => { Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value); el.dispatchEvent(new dom.window.Event(event, { bubbles: true })); });
  await tick();
}
const period = (y, m) => { const p = settlementPeriod(y, m); return [toIsoDate(p.start), toIsoDate(p.end)]; };
const monthOnScreen = () => { const [m, y] = section().parentElement.querySelectorAll('select'); return [Number(y.value), Number(m.value)]; };
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── tests ──────────────────────────────────────────────────────────────────
test('a database from before 368: the page works, and says the lines cannot be listed — not that none were left out', async () => {
  await mount({ database: 'old' });
  await openTab('Settlements');
  assert.ok(!document.getElementById('crashed'), document.getElementById('crashed')?.textContent);
  assert.deepEqual(globalThis.__renderErrors, []);
  assert.match(document.body.textContent, /Total Income\s*S\$950\.00/);
  assert.equal(notice(), null, 'no left-out warning without the key');
  assert.equal(callsOf('tiktok_left_out_settlement').length, 1, 'the list is asked for');
  assert.deepEqual([...section().children].map(e => e.textContent.replace(/\s+/g, ' ').trim()), ['Left out at confirmation',
    'Left-out lines cannot be listed until the database is updated. Until then, rows left unticked at confirmation are in none of the figures above.'],
    'no "tick the ones to count" either');
  assert.doesNotMatch(section().textContent, /Nothing was left out/);
  assert.equal(section().querySelector('[role="alert"]'), null, 'and is not reported as an error');
  assert.equal(button('Include selected'), undefined);
});

test('P1: only PGRST202 for the left-out function itself means "not on this database"; 42883 and others are errors', async () => {
  const cases = [
    { code: '42883', message: 'function public.tiktok_settlement_left_out_rows(uuid) does not exist' },
    { code: 'PGRST202', message: 'Could not find the function public.tiktok_access_check in the schema cache' },
  ];
  for (const failure of cases) {
    await mount({ role: 'manager', assigned: STORE, setup: b => b.failures.set('tiktok_left_out_settlement', failure) });
    await openTab('Settlements');
    assert.equal(section().querySelector('[role="alert"]').textContent, `Left-out lines could not be loaded: ${failure.message}`);
    assert.doesNotMatch(section().textContent, /Nothing was left out|cannot be listed until/);
  }
});

test('B1: the month warns how much settled money was left out, and points to where it can be included', async () => {
  await mount({ role: 'manager', assigned: STORE });
  await openTab('Settlements');
  assert.ok(notice(), 'the warning is shown');
  assert.equal(notice().textContent.replace(/\s+/g, ' ').trim(),
    '4 settled TikTok lines were left out at confirmation. Including them would add S$450.25 to these totals. '
    + 'They are listed under Left out at confirmation below.');
  // Under the month cards, before anything else.
  const cards = [...document.querySelectorAll('.card')].find(c => c.textContent.startsWith('Total Income')).parentElement;
  assert.equal(cards.nextElementSibling, notice(), 'directly under the month cards');
});

test('B1: the shared summary (as the Reports page uses it) points to the import page, and says "1 line"', async () => {
  const el = () => React.createElement(SettlementSummary, { storeId: null, year: 2026, month: 8, onChangeMonth: () => {} });
  await mount({ element: el(), setup: b => { b.leftOut = b.leftOut.slice(3); } });
  assert.equal(notice().textContent.replace(/\s+/g, ' ').trim(),
    '1 settled TikTok line was left out at confirmation. Including it would add S$7.65 to these totals. '
    + 'Review them in TikTok Sales Import → Settlements, where an Owner or Manager can include them.');
  // A restatement alone lowers the totals: the notice says so rather than
  // claiming S$95.00 is missing.
  await mount({ element: el(), setup: b => { b.leftOut = [restatedLine()]; } });
  assert.match(notice().textContent.replace(/\s+/g, ' '),
    /^1 settled TikTok line was left out at confirmation\. Including it would take S\$5\.00 off these totals\. /);
  await mount({ element: el(), setup: b => { b.leftOut = []; } });
  assert.equal(notice(), null, 'nothing left out, no warning');
  assert.match(document.body.textContent, /Total Income/);
  await mount({ element: el(), database: 'old' });
  assert.equal(notice(), null, 'an absent key is read as 0');
});

test('B2: the left-out lines of the store and month on screen are listed, and a new month asks again', async () => {
  await mount({ role: 'manager', assigned: STORE });
  await openTab('Settlements');
  const [y, m] = monthOnScreen();
  const [from, to] = period(y, m);
  assert.deepEqual(callsOf('tiktok_left_out_settlement').at(-1).args, { p_store_id: STORE, p_from: from, p_to: to });
  const rows = listed();
  assert.equal(rows.length, 4);
  assert.deepEqual(rows[0].slice(1), ['2026-08-01', 'ORD-100001', 'Order', 'Pending Order', '117.80', '130.00', '-12.20', 'income_sample_a.xlsx']);
  assert.deepEqual(rows.map(r => r[5]), ['117.80', '259.54', '65.26', '7.65'], 'two lines of one order are two rows');

  const monthSel = section().parentElement.querySelector('select');
  const next = m === 12 ? 11 : m + 1;
  await setValue(monthSel, String(next), 'change');
  const [from2, to2] = period(y, next);
  assert.deepEqual(callsOf('tiktok_left_out_settlement').at(-1).args, { p_store_id: STORE, p_from: from2, p_to: to2 });
});

test('B2: a slow answer for the previous month never lands under the new one', async () => {
  let release;
  await mount({ role: 'manager', assigned: STORE, setup: b => { release = b.hold('tiktok_left_out_settlement'); } });
  await openTab('Settlements');
  const [, m] = monthOnScreen();
  const monthSel = section().parentElement.querySelector('select');
  backend.leftOut = backend.leftOut.slice(3);          // the new month has one line
  await setValue(monthSel, String(m === 12 ? 11 : m + 1), 'change');
  assert.equal(listed().length, 1);
  backend.leftOut = leftOutLines();
  release(); await tick();
  assert.equal(listed().length, 1, 'the earlier month\'s four lines did not replace it');
  assert.deepEqual(listed()[0].slice(1, 3), ['2026-08-03', 'ORD-100003']);
});

test('B2: a manager includes ticked lines with a reason; the list, the figures and the transactions reload', async () => {
  await mount({ role: 'manager', assigned: STORE });
  await openTab('Settlements');
  const include = () => button('Include selected');
  assert.ok(include().disabled, 'nothing ticked yet');
  const [first, second] = boxes(section());
  await click(first); await click(second);
  assert.match(section().textContent, /2 selected · S\$377\.34/);
  assert.ok(include().disabled, 'a reason is required');
  await setValue(section().querySelector('input:not([type])'), '   ');
  assert.ok(include().disabled, 'blank is not a reason');
  await setValue(section().querySelector('input:not([type])'), 'Owner decision: count in August');

  const before = { list: callsOf('tiktok_left_out_settlement').length, totals: callsOf('tiktok_settlement_totals').length,
    txns: callsOf('report_tiktok_settlement').length };
  assert.equal(include().disabled, false);
  await click(include());
  assert.deepEqual(callsOf('include_tiktok_settlement_rows').at(-1).args,
    { p_row_ids: ['lo-1', 'lo-2'], p_reason: 'Owner decision: count in August' });
  assert.equal(alerts.at(-1), 'Included in the settlement totals: 2 line(s).');
  assert.ok(callsOf('tiktok_left_out_settlement').length > before.list, 'the list reloads');
  assert.ok(callsOf('tiktok_settlement_totals').length > before.totals, 'the month figures reload');
  assert.ok(callsOf('report_tiktok_settlement').length > before.txns, 'the transactions reload');
  assert.deepEqual(listed().map(r => r[2]), ['ORD-100002', 'ORD-100003']);
  assert.match(notice().textContent.replace(/\s+/g, ' '), /2 settled TikTok lines were left out at confirmation\. Including them would add S\$72\.91 /);
  assert.equal(section().querySelector('input:not([type])').value, '', 'the reason is cleared');
  assert.ok(boxes(section()).every(x => !x.checked), 'and the selection');

  // Select all, then include everything left.
  await click(section().querySelector('thead input[type="checkbox"]'));
  assert.ok(boxes(section()).every(x => x.checked));
  await setValue(section().querySelector('input:not([type])'), 'Owner decision: count in August');
  await click(include());
  assert.deepEqual(callsOf('include_tiktok_settlement_rows').at(-1).args.p_row_ids, ['lo-3', 'lo-4']);
  assert.match(section().textContent, /Nothing was left out for this period\./);
  assert.equal(notice(), null, 'the warning goes once nothing is left out');
});

test('B2: a refused include shows its reason beside the list, which stays as it was', async () => {
  await mount({ role: 'owner', setup: b => { b.includeError = 'Only a left-out settlement row can be included'; } });
  await openTab('Settlements');
  assert.equal(callsOf('tiktok_left_out_settlement').at(-1).args.p_store_id, null, 'no store chosen: every store, as the figures');
  await click(boxes(section())[2]);
  await setValue(section().querySelector('input:not([type])'), 'Checked against Seller Center');
  await click(button('Include selected'));
  assert.match(section().querySelector('[role="alert"]').textContent, /Only a left-out settlement row can be included/);
  assert.equal(listed().length, 4);
  assert.equal(alerts.length, 0);
});

test('B2: staff see the left-out lines but cannot include them', async () => {
  await mount({ role: 'staff', assigned: STORE });
  await openTab('Settlements');
  assert.equal(listed().length, 4);
  assert.equal(boxes(section()).length, 0, 'no checkboxes');
  assert.equal(button('Include selected'), undefined, 'no include button');
  assert.match(section().textContent, /An Owner or Manager can include them\./);
});

test('B2: a failing left-out read shows its error; the month figures still show', async () => {
  await mount({ role: 'manager', assigned: STORE, setup: b => b.failures.set('tiktok_left_out_settlement', 'boom') });
  await openTab('Settlements');
  assert.match(section().querySelector('[role="alert"]').textContent, /Left-out lines could not be loaded: boom/);
  assert.doesNotMatch(section().textContent, /Nothing was left out/, 'an error is not shown as "nothing"');
  assert.match(document.body.textContent, /Total Income\s*S\$950\.00/);
});

test('B2: confirmation keeps the pre-tick rule, and says unticked rows can be included later', async () => {
  await mount({ role: 'manager', assigned: STORE });
  await click(button('Open'));
  const preview = [...document.querySelectorAll('.card')].find(c => c.textContent.includes('Settlement Preview'));
  const ticks = Object.fromEntries([...preview.querySelectorAll('tbody tr')].map(tr => [tr.children[1].textContent, tr.querySelector('input').checked]));
  assert.deepEqual(ticks, { 'ORD-200001': true, 'ADS-1': true, 'ORD-200002': false, 'ORD-200003': false },
    'matched and finance rows pre-ticked; pending and already-imported rows not');
  assert.equal(callsOf('tiktok_left_out_settlement').length, 1, 'the page asks once whether left-out lines can be listed');
  assert.equal(callsOf('tiktok_left_out_settlement')[0].args.p_store_id, STORE, 'for the file\'s store');
  assert.equal(preview.querySelector('[data-testid="settle-unticked"]').textContent.replace(/\s+/g, ' ').trim(),
    '⚠1 row is not ticked (S$65.26 settled). Confirming leaves it out of the settlement totals — not lost: '
    + 'an Owner or Manager can include it later under Settlements → Left out at confirmation.');

  await click(button('Confirm Selected Rows'));
  assert.deepEqual(callsOf('confirm_tiktok_settlement_batch').at(-1).args, { p_batch_id: BATCH, p_row_ids: ['sr-1', 'sr-2'] });
  assert.match(alerts.at(-1), /^Settlement confirmed: 2 rows/);
  assert.match(alerts.at(-1), /1 unticked row\(s\) \(S\$65\.26 settled\) are left out of the settlement totals\. An Owner or Manager can include them later under Settlements → Left out at confirmation\.$/);
  const locked = [...document.querySelectorAll('.card')].find(c => c.textContent.includes('Settlement Confirmed (locked)'));
  assert.equal(locked.querySelector('[data-testid="settle-unticked"]'), null, 'a confirmed file no longer warns');
});

test('P1: on a database from before 368, confirmation warns about unticked rows but promises no "include later"', async () => {
  for (const setup of [undefined, b => b.failures.set('tiktok_left_out_settlement', 'boom')]) {
    // Old database: the function is missing. New one that failed to answer: not known either way.
    await mount({ role: 'manager', assigned: STORE, database: setup ? 'new' : 'old', setup });
    await click(button('Open'));
    const preview = [...document.querySelectorAll('.card')].find(c => c.textContent.includes('Settlement Preview'));
    assert.equal(preview.querySelector('[data-testid="settle-unticked"]').textContent.replace(/\s+/g, ' ').trim(),
      '⚠1 row is not ticked (S$65.26 settled). Confirming leaves it out of the settlement totals.');
    await click(button('Confirm Selected Rows'));
    assert.match(alerts.at(-1), /\n\n1 unticked row\(s\) \(S\$65\.26 settled\) are left out of the settlement totals\.$/);
    assert.doesNotMatch(alerts.at(-1), /include them later/);
  }
});

test('P2: a left-out restatement shows the line it restates, and is totalled by its net change', async () => {
  await mount({ role: 'manager', assigned: STORE, setup: b => { b.leftOut = [leftOutLines()[2], restatedLine()]; } });
  await openTab('Settlements');
  assert.equal(notice().textContent.replace(/\s+/g, ' ').trim(),
    '2 settled TikTok lines were left out at confirmation. Including them would add S$60.26 to these totals. '
    + 'They are listed under Left out at confirmation below.');
  const rows = listed();
  assert.equal(rows[0][5], '65.26', 'a new line has no note');
  assert.equal(rows[1][5].replace(/\s+/g, ' '), '95.00restates S$100.00');
  const [plain, restated] = boxes(section());
  await click(restated);
  assert.match(section().textContent, /1 selected · S\$-5\.00 net \(1 restates a counted line\)/);
  await click(plain);   // no net_change: counted at its settlement amount
  assert.match(section().textContent, /2 selected · S\$60\.26 net \(1 restates a counted line\)/);
  await click(restated);
  assert.match(section().textContent, /1 selected · S\$65\.26(?! net)/);
});

// Staged restatements: 'Updated' rows whose replaced line is counted already.
const updatedRow = (id, row_no, amount, extra) => ({ id, batch_id: BATCH, row_no, order_id: `ORD-3000${row_no}`, transaction_type: 'Order', txn_class: 'order',
  settlement_amount: amount, revenue_amount: amount, fee_amount: 0, match_status: 'pending', staging_status: 'Updated — Requires Confirmation',
  excluded: false, confirmed: false, reconciled: true, version_no: 2, ...extra });

test('P3: an unticked restatement counts only its change in the confirmation figures', async () => {
  await mount({ role: 'manager', assigned: STORE, setup: b => b.tables.tiktok_settlement_rows.push(
    // 100.00 counted, restated as 95.00: leaving it out keeps -5.00 out.
    updatedRow('sr-5', 5, 95, { previous_row_id: 'cur-5', value_diff: { settlement_amount: { old: 100, new: 95 }, fee_amount: { old: -10, new: -15 } } }),
    // Only the order time differs: the amount is unchanged, so 0.00.
    updatedRow('sr-6', 6, 40, { previous_row_id: 'cur-6', value_diff: { order_created_time: { old: '2026-08-01', new: '2026-08-01T09:00:00' } } }),
  ) });
  await click(button('Open'));
  const preview = [...document.querySelectorAll('.card')].find(c => c.textContent.includes('Settlement Preview'));
  assert.equal(preview.querySelector('[data-testid="settle-unticked"]').textContent.replace(/\s+/g, ' ').trim(),
    '⚠3 rows are not ticked (S$60.26 settled; 2 restated lines count only their change). Confirming leaves them out of the '
    + 'settlement totals — not lost: an Owner or Manager can include them later under Settlements → Left out at confirmation.');
  await click(button('Confirm Selected Rows'));
  assert.match(alerts.at(-1), /\n\n3 unticked row\(s\) \(S\$60\.26 settled; 2 restated lines count only their change\) are left out/);
});

test('P3: a restatement whose replaced amount the page does not know is counted in full, and said to be included', async () => {
  await mount({ role: 'manager', assigned: STORE, setup: b => b.tables.tiktok_settlement_rows.push(
    updatedRow('sr-7', 7, 30, { previous_row_id: null, value_diff: null })) });
  await click(button('Open'));
  const preview = [...document.querySelectorAll('.card')].find(c => c.textContent.includes('Settlement Preview'));
  assert.match(preview.querySelector('[data-testid="settle-unticked"]').textContent.replace(/\s+/g, ' '),
    /^⚠2 rows are not ticked \(S\$95\.26 settled; includes 1 restated line\)\. /);
  await click(button('Confirm Selected Rows'));
  assert.match(alerts.at(-1), /\n\n2 unticked row\(s\) \(S\$95\.26 settled; includes 1 restated line\) are left out/);
});
