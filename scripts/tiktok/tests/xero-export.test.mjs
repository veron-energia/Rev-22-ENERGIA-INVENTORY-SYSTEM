// The TikTok "Xero Export" on TikTok Sales Import → Settlements (375), and the
// Withdrawal records a settlement file brings: who sees the export, what it
// sends and downloads, and what an upload stages.
//
// The actual src/pages/TikTokImportPage.tsx is bundled with esbuild and mounted in
// jsdom, as in left-out-settlement.test.mjs. Only the Supabase client and the
// auth context are stubbed; the workbook is a real .xlsx built here. Every
// amount, Reference ID and bank account below is invented.
//
// Run: node --test scripts/tiktok/tests/xero-export.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import * as XLSX from 'xlsx';
import JSZip from 'jszip';
// Today in Singapore, as the dialog's default end date.
const singaporeToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore' }).format(new Date());

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
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
  } }],
});
const { TikTokImportPage, SettlementSummary, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const STORE = 'st-1';
const payout = (paid_on, wednesday, amount, extra = {}) => {
  const start = new Date(`${wednesday}T00:00:00Z`); start.setUTCDate(start.getUTCDate() - 6);
  return { reference_id: `36000000000000${paid_on.replace(/-/g, '').slice(2)}`, paid_on, amount, status: 'Transferred', transferred: true,
    wednesday, week_start: start.toISOString().slice(0, 10), app_payout: amount, app_rows: 3, uncovered_days: [], left_out_count: 0, ...extra };
};
const payouts = (from, to, over = {}) => ({
  from, to, today: '', timezone: 'Asia/Singapore',
  payouts: [payout('2026-09-02', '2026-09-02', 713), payout('2026-09-09', '2026-09-09', 61.97, { app_payout: 70 })],
  wednesdays_without_payout: [{ wednesday: '2026-09-30', week_start: '2026-09-24', app_payout: 242.97, app_rows: 4, uncovered_days: [] }],
  ...over,
});

// ── fake backend ───────────────────────────────────────────────────────────
function createBackend() {
  const b = { calls: [], failures: new Map(), payouts };
  const tables = {
    stores: [{ id: STORE, name: 'North Store', deleted_at: null, is_active: true }],
    products: [], vouchers: [], promotions: [], tiktok_status_mappings: [], tiktok_physical_returns: [],
    tiktok_import_batches: [{ id: 'b-9', file_name: 'income_sample.xlsx', file_kind: 'settlement', status: 'staged', store_id: STORE }],
    tiktok_settlement_rows: [],
  };
  const rpcs = {
    my_assigned_store_id: () => null,
    // Staff read every store they work at (X-9): here the one my_assigned_store_id gives.
    my_assigned_stores: () => { const id = rpcs.my_assigned_store_id(); return id ? [{ store_id: id, store_name: 'North Store', is_default: true }] : []; },
    report_tiktok_imports: () => [],
    report_tiktok_settlement: () => [],
    tiktok_settlement_totals: a => ({ year: a.p_year, month: a.p_month, period_start: '', period_end: '', timezone: 'Asia/Singapore', row_count: 0,
      revenue: 0, fee: 0, settlement: 0, expense: 0, income: 0, tiktok_net_settlement: 0, by_category: {}, unknown_count: 0,
      balance_movement_count: 0, pending_match_count: 0, currency_count: 1, undated_count: 0, needs_review: false,
      left_out_count: 0, left_out_settlement: 0 }),
    tiktok_left_out_settlement: () => [],
    tiktok_bank_payouts: a => b.payouts(a.p_from, a.p_to),
    stage_tiktok_settlement_file: () => 'b-9',
    stage_tiktok_orders: () => 'b-order',
    tiktok_batch_balance_counts: () => ({ payouts: 0, others: 0 }),
    confirm_tiktok_settlement_batch: () => ({ applied: 0, versioned_updates: 0, pending: 0, unreconciled: 0, skipped: 1 }),
  };
  b.tables = tables; b.rpcs = rpcs;
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
      await Promise.resolve();
      if (b.failures.has(this.name)) return { data: null, error: { code: 'P0001', message: b.failures.get(this.name) } };
      const src = this.kind === 'table' ? tables[this.name] : rpcs[this.name]?.(this.args);
      if (src === undefined) return { data: null, error: { code: 'PGRST202', message: `unknown ${this.kind} ${this.name}` } };
      if (!Array.isArray(src)) return { data: src, error: null };
      let rows = src.filter(r => this.filters.every(f => f(r)));
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
let confirms = [];
let confirmAnswer = true;
globalThis.alert = text => { alerts.push(String(text)); };
globalThis.confirm = text => { confirms.push(String(text)); return confirmAnswer; };
// The download: the CSV handed to URL.createObjectURL and the link's filename.
let downloads = [];
URL.createObjectURL = blob => { downloads.push({ blob }); return 'blob:tiktok-xero'; };
URL.revokeObjectURL = () => {};
dom.window.HTMLAnchorElement.prototype.click = function () { const d = downloads.at(-1); if (d) d.name = this.download; };
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount({ role = 'owner', setup } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend();
  globalThis.__backend = backend; globalThis.__renderErrors = []; globalThis.__assigned = null;
  globalThis.__auth = { profile: { id: 'u-1', full_name: 'Test User', role } };
  downloads = []; alerts = []; confirms = []; confirmAnswer = true;
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(TikTokImportPage))));
  await tick();
}
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await tick(); };
const button = (label, scope = document) => [...scope.querySelectorAll('button')].find(x => x.textContent.trim().startsWith(label));
const footer = () => document.querySelector('.modal-footer');
const openTab = label => click([...document.querySelectorAll('button')].find(x => x.textContent.trim() === label));
const callsOf = name => backend.calls.filter(c => c.name === name);
const field = id => document.getElementById(id);
async function setValue(el, value, event = 'input') {
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => { Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value); el.dispatchEvent(new dom.window.Event(event, { bubbles: true })); });
  await tick();
}
async function openExport(opts) { await mount(opts); await openTab('Settlements'); await click(button('Xero Export')); }
const csvOf = async d => (await d.blob.text()).split('\r\n').filter(Boolean);
const warnings = () => document.querySelector('[data-testid="tiktok-xero-warnings"]')?.textContent ?? '';
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── tests: the export ──────────────────────────────────────────────────────
test('Owners and Managers see the TikTok Xero Export on Settlements; staff do not', async () => {
  for (const role of ['owner', 'manager']) {
    await mount({ role });
    await openTab('Settlements');
    assert.ok(button('Xero Export'), `${role} sees it`);
  }
  await mount({ role: 'staff' });
  await openTab('Settlements');
  assert.equal(button('Xero Export'), undefined, 'staff do not');
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('like the invoice export: From, To, one account code and the tax rate, with this month so far', async () => {
  await openExport();
  const today = singaporeToday();
  assert.equal(field('tiktok-xero-from').value, `${today.slice(0, 7)}-01`);
  assert.equal(field('tiktok-xero-to').value, today);
  assert.equal(field('tiktok-xero-code').value, '1011');
  assert.equal(field('tiktok-xero-tax').value, 'No Tax (0%)');
  assert.equal(document.querySelectorAll('[data-testid="tiktok-xero"] input').length, 4, 'nothing else to fill in');
  assert.equal(document.querySelector('[data-testid="tiktok-xero"] table'), null, 'no table of weeks');
});

test('Export CSV downloads one invoice per TikTok payout between the dates, for what TikTok paid, and lists what to check', async () => {
  await openExport();
  await setValue(field('tiktok-xero-from'), '2026-09-01');
  await setValue(field('tiktok-xero-to'), '2026-09-30');
  await click(button('Export CSV', footer()));
  assert.deepEqual(callsOf('tiktok_bank_payouts').map(c => c.args), [{ p_from: '2026-09-01', p_to: '2026-09-30' }]);
  assert.equal(downloads.length, 1);
  assert.equal(downloads[0].name, 'xero-tiktok-payouts-2026-09-01-to-2026-09-30.csv');
  const csv = await csvOf(downloads[0]);
  assert.equal(csv.length, 3, 'the header and one line per payout');
  assert.ok(csv[1].startsWith('TikTok Shop,,,,,,,,,,TT-PAYOUT-2026-09-02,TikTok 36000000000000260902,02/09/2026,02/09/2026,,,'), csv[1]);
  assert.ok(csv[1].includes(',713.00,') && csv[1].includes(',1011,No Tax (0%),0,'), csv[1]);
  assert.ok(csv[2].includes('TT-PAYOUT-2026-09-09') && csv[2].includes(',61.97,'));
  assert.ok(document.querySelector('[role="status"]').textContent.includes('Downloaded 2 TikTok payouts totalling S$774.97'));
  const w = warnings();
  assert.ok(w.includes("Wed 9 Sep: TikTok paid S$61.97, but the app's settled lines for Thu 3 Sep – Wed 9 Sep 2026 come to S$70.00"), w);
  assert.ok(w.includes('Wed 30 Sep: no TikTok payout has been imported'), w);
});

test('no payouts between the dates: nothing downloads, and it says where payouts come from', async () => {
  await openExport({ setup: b => { b.payouts = (from, to) => payouts(from, to, { payouts: [], wednesdays_without_payout: [] }); } });
  await click(button('Export CSV', footer()));
  assert.equal(downloads.length, 0);
  assert.match(document.querySelector('[role="alert"]').textContent,
    /No TikTok payouts have been imported for those dates\..*can be uploaded again and confirmed for its Withdrawal records/);
});

test('payouts between the dates that cannot be exported: nothing downloads, and it points to the notes, not to "none"', async () => {
  await openExport({ setup: b => { b.payouts = (from, to) => payouts(from, to, { wednesdays_without_payout: [], payouts: [
    payout('2026-09-02', '2026-09-02', 713, { file_name: 'a.xlsx', disagreeing: [{ amount: 7130, file_name: 'b.xlsx' }] }),
  ] }); } });
  await click(button('Export CSV', footer()));
  assert.equal(downloads.length, 0);
  assert.match(warnings(), /imported TikTok files disagree on payout/);
  assert.equal(document.querySelector('[role="alert"]').textContent.trim(), '⚠None of the TikTok payouts between those dates can be exported: see the notes above.');
});

test('the dates and the account details are checked before anything is asked', async () => {
  await openExport();
  await setValue(field('tiktok-xero-code'), '');
  await click(button('Export CSV', footer()));
  assert.ok(document.querySelector('[role="alert"]').textContent.includes('Enter the Xero account code and tax rate.'));
  await setValue(field('tiktok-xero-code'), '1011');
  await setValue(field('tiktok-xero-from'), '2026-09-30');
  await setValue(field('tiktok-xero-to'), '2026-09-01');
  await click(button('Export CSV', footer()));
  assert.ok(document.querySelector('[role="alert"]').textContent.includes('The end date cannot be before the start date.'));
  assert.equal(callsOf('tiktok_bank_payouts').length, 0);
});

test('a double click downloads once', async () => {
  await openExport();
  const exportButton = button('Export CSV', footer());
  await act(async () => {
    exportButton.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
    exportButton.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
  });
  await tick();
  assert.equal(downloads.length, 1);
  assert.equal(callsOf('tiktok_bank_payouts').length, 1);
});

test('a refusal from the database is shown', async () => {
  await openExport({ setup: b => b.failures.set('tiktok_bank_payouts', 'Only an Owner or Manager can see the TikTok payouts') });
  await click(button('Export CSV', footer()));
  assert.ok(document.querySelector('[role="alert"]').textContent.includes('Only an Owner or Manager can see the TikTok payouts'));
  assert.equal(downloads.length, 0);
});

// ── tests: the Withdrawal records a settlement file brings ─────────────────
const incomeWorkbook = ({ withdrawals = true } = {}) => {
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([
    ['Order/Adjustment ID', 'Type', 'Order settled time', 'Currency', 'Total settlement amount', 'Total Revenue', 'Total Fees'],
    ['5800000000000001', 'Order', '2026/09/02', 'SGD', '80', '100', '-20'],
  ]), 'Order details');
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Total revenue', '100']]), 'Reports');
  if (withdrawals) {
    XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([
      ['Transaction type', 'Reference ID', 'Request time', 'Amount', 'Status', 'Success time', 'Bank account'],
      ['Payments', '3600000000000000001', '2026/09/02', '-713', 'Transferred', '2026/09/02', 'DBS ****1234'],
      ['Earnings', '3600000000000000002', '2026/09/01', '96.5', 'Transferred', '2026/09/01', ''],
    ]), 'Withdrawal records');
  }
  return new File([XLSX.write(wb, { type: 'array', bookType: 'xlsx' })], 'income_test.xlsx');
};
async function uploadSettlement(file, which = 1) {
  await setValue(document.querySelector('select'), STORE, 'change');
  const input = document.querySelectorAll('input[type="file"]')[which];
  Object.defineProperty(input, 'files', { value: [file], configurable: true });
  await act(async () => { input.dispatchEvent(new dom.window.Event('change', { bubbles: true })); });
  await tick(30);
}

test('a settlement file is staged with its Withdrawal records, without the bank account', async () => {
  await mount();
  await uploadSettlement(incomeWorkbook());
  const [call] = callsOf('stage_tiktok_settlement_file');
  assert.ok(call, 'the file went to stage_tiktok_settlement_file');
  assert.equal(call.args.p_store_id, STORE);
  assert.equal(call.args.p_sheet_name, 'Order details');
  assert.equal(call.args.p_rows.length, 1);
  assert.deepEqual(call.args.p_balance_rows, [
    { transaction_type: 'Payments', reference_id: '3600000000000000001', request_time: '2026/09/02', amount: '-713', status: 'Transferred', success_time: '2026/09/02' },
    { transaction_type: 'Earnings', reference_id: '3600000000000000002', request_time: '2026/09/01', amount: '96.5', status: 'Transferred', success_time: '2026/09/01' },
  ]);
  assert.ok(!JSON.stringify(call.args).includes('1234'), 'the bank account is not sent');
  assert.equal(callsOf('stage_tiktok_settlement').length, 0);
  assert.ok(document.querySelector('[data-testid="import-note"]').textContent.includes('1 payout and 1 other balance record'));
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('a settlement file without Withdrawal records is staged as before, and says it brings no payouts', async () => {
  await mount();
  await uploadSettlement(incomeWorkbook({ withdrawals: false }));
  const [call] = callsOf('stage_tiktok_settlement_file');
  assert.deepEqual(call.args.p_balance_rows, []);
  assert.ok(document.querySelector('[data-testid="import-note"]').textContent.includes('has no Withdrawal records sheet'));
});

test('an order file is staged as before: no Withdrawal records, no note', async () => {
  await mount();
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([
    ['Order ID', 'Order Status', 'Seller SKU', 'Quantity'],
    ['5800000000000001', 'Completed', 'SKU-1', '1'],
  ]), 'OrderSKUList');
  await uploadSettlement(new File([XLSX.write(wb, { type: 'array', bookType: 'xlsx' })], 'orders_test.xlsx'), 0);
  const [call] = callsOf('stage_tiktok_orders');
  assert.ok(call, 'the file went to stage_tiktok_orders');
  assert.deepEqual(Object.keys(call.args).sort(), ['p_file_name', 'p_rows', 'p_sheet_name', 'p_store_id']);
  assert.equal(callsOf('stage_tiktok_settlement_file').length, 0);
  assert.equal(document.querySelector('[data-testid="import-note"]'), null);
});

test('a settlement CSV is staged as before, with no Withdrawal records', async () => {
  await mount();
  const csv = 'Order/Adjustment ID,Type,Order settled time,Currency,Total settlement amount,Total Revenue,Total Fees\n'
    + '5800000000000001,Order,2026/09/02,SGD,80,100,-20\n';
  await uploadSettlement(new File([csv], 'income_test.csv'));
  const [call] = callsOf('stage_tiktok_settlement_file');
  assert.equal(call.args.p_sheet_name, 'CSV');
  assert.equal(call.args.p_rows.length, 1);
  assert.deepEqual(call.args.p_balance_rows, []);
  assert.ok(document.querySelector('[data-testid="import-note"]').textContent.includes('has no Withdrawal records sheet'));
});

test('TikTok\'s own workbook says its Withdrawal records sheet ends on row 2: every record is still sent', async () => {
  await mount();
  // TikTok writes a stale <dimension> (A1:G2 for a sheet of many rows); the
  // page must not trust it.
  const zip = await JSZip.loadAsync(await incomeWorkbook().arrayBuffer());
  const sheet = Object.keys(zip.files).find(n => /^xl\/worksheets\/sheet3\.xml$/.test(n));
  const xml = await zip.file(sheet).async('string');
  assert.match(xml, /<dimension ref="A1:G3"\/>/);
  zip.file(sheet, xml.replace('<dimension ref="A1:G3"/>', '<dimension ref="A1:G2"/>'));
  const stale = new File([await zip.generateAsync({ type: 'uint8array' })], 'income_test.xlsx');
  await uploadSettlement(stale);
  const [call] = callsOf('stage_tiktok_settlement_file');
  assert.deepEqual(call.args.p_balance_rows.map(r => r.transaction_type), ['Payments', 'Earnings']);
});

// A staged file whose only line was imported before, as when an income export
// from before 375 is uploaded again for its payouts.
const alreadyImported = b => {
  b.tables.tiktok_settlement_rows.push({ id: 'r-1', batch_id: 'b-9', store_id: STORE, row_no: 1, order_id: '5800000000000001',
    transaction_type: 'Order', settlement_amount: 80, revenue_amount: 100, fee_amount: -20, currency: 'SGD',
    settled_time: '2026-09-01T16:00:00+00:00', staging_status: 'Already Imported', excluded: true, confirmed: false, match_status: 'matched' });
};

test('a file whose lines were all imported before is confirmed for its Withdrawal records alone, once someone says so', async () => {
  await mount({ setup: b => { alreadyImported(b); b.rpcs.tiktok_batch_balance_counts = () => ({ payouts: 5, others: 34 }); } });
  await uploadSettlement(incomeWorkbook());
  assert.equal(callsOf('tiktok_batch_balance_counts').at(-1).args.p_batch_id, 'b-9');
  assert.match(document.querySelector('[data-testid="settle-balance"]').textContent,
    /5 payouts and 34 other balance records\. None of its lines are new, so confirm it to save the records alone/);
  confirmAnswer = false;
  await click(button('Confirm Withdrawal Records Only'));
  assert.equal(confirms.length, 1);
  assert.match(confirms[0], /only to save TikTok's Withdrawal records \(5 payouts and 34 other balance records\)/);
  assert.equal(callsOf('confirm_tiktok_settlement_batch').length, 0, 'nothing is confirmed when the person says no');
  confirmAnswer = true;
  await click(button('Confirm Withdrawal Records Only'));
  const [call] = callsOf('confirm_tiktok_settlement_batch');
  assert.deepEqual(call.args, { p_batch_id: 'b-9', p_row_ids: [] }, 'no line is confirmed');
  assert.match(alerts.at(-1), /Withdrawal records \(5 payouts and 34 other balance records\) now count for the Xero export/);
  assert.equal(document.querySelector('[role="alert"]'), null);
});

test('a file with nothing ticked and no Withdrawal records still asks for a row, as before', async () => {
  await mount({ setup: b => { alreadyImported(b); b.failures.set('tiktok_batch_balance_counts', 'function not found'); } });
  await uploadSettlement(incomeWorkbook({ withdrawals: false }));
  assert.equal(document.querySelector('[data-testid="settle-balance"]'), null);
  await click(button('Confirm Selected Rows'));
  assert.equal(confirms.length, 0);
  assert.equal(callsOf('confirm_tiktok_settlement_batch').length, 0);
  assert.ok(document.body.textContent.includes('Select at least one settlement row to confirm.'));
});

test('a file with new lines, none ticked: staff are asked to tick one; an Owner may confirm the records alone, leaving the lines out', async () => {
  const fresh = b => {
    b.tables.tiktok_settlement_rows.push({ id: 'r-2', batch_id: 'b-9', store_id: STORE, row_no: 1, order_id: '5800000000000002',
      transaction_type: 'Order', settlement_amount: 40, revenue_amount: 50, fee_amount: -10, currency: 'SGD',
      settled_time: '2026-09-01T16:00:00+00:00', staging_status: 'New — Pending Order', excluded: false, confirmed: false, match_status: 'pending' });
    b.rpcs.tiktok_batch_balance_counts = () => ({ payouts: 1, others: 1 });
  };
  await mount({ role: 'staff', setup: b => { fresh(b); b.rpcs.my_assigned_store_id = () => STORE; } });
  const input = document.querySelectorAll('input[type="file"]')[1];
  Object.defineProperty(input, 'files', { value: [incomeWorkbook()], configurable: true });
  await act(async () => { input.dispatchEvent(new dom.window.Event('change', { bubbles: true })); });
  await tick(30);
  assert.equal(callsOf('stage_tiktok_settlement_file')[0].args.p_store_id, STORE, 'staff upload into their store');
  assert.match(document.querySelector('[data-testid="settle-balance"]').textContent, /They count for the Xero export once this file is confirmed/);
  await click(button('Confirm Selected Rows'));
  assert.equal(confirms.length, 0);
  assert.equal(callsOf('confirm_tiktok_settlement_batch').length, 0);
  assert.ok(document.body.textContent.includes('Select at least one settlement row to confirm.'));

  await mount({ role: 'owner', setup: fresh });
  await uploadSettlement(incomeWorkbook());
  assert.equal(button('Confirm Withdrawal Records Only'), undefined, 'the button does not suggest leaving the new line out');
  await click(button('Confirm Selected Rows'));
  assert.equal(confirms.length, 1);
  assert.match(confirms[0], /only to save TikTok's Withdrawal records \(1 payout and 1 other balance record\)[\s\S]*1 unticked row\(s\) \(S\$40\.00 settled\) are left out of the settlement totals/);
  assert.deepEqual(callsOf('confirm_tiktok_settlement_batch')[0].args, { p_batch_id: 'b-9', p_row_ids: [] });
});

test('Withdrawal records without a payout add nothing: no records-only confirm', async () => {
  await mount({ setup: b => { alreadyImported(b); b.rpcs.tiktok_batch_balance_counts = () => ({ payouts: 0, others: 5 }); } });
  await uploadSettlement(incomeWorkbook());
  assert.match(document.querySelector('[data-testid="settle-balance"]').textContent,
    /0 payouts and 5 other balance records\. With no payout among them, they add nothing to the Xero export\./);
  assert.equal(button('Confirm Withdrawal Records Only'), undefined);
  await click(button('Confirm Selected Rows'));
  assert.equal(confirms.length, 0);
  assert.equal(callsOf('confirm_tiktok_settlement_batch').length, 0);
  assert.ok(document.body.textContent.includes('Select at least one settlement row to confirm.'));
});
