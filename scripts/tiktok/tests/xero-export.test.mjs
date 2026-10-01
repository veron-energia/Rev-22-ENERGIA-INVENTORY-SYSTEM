// The TikTok "Xero Export" on TikTok Sales Import → Settlements (374): who sees it,
// what it shows for the month on screen, and the CSV it downloads.
//
// The actual src/pages/TikTokImportPage.tsx is bundled with esbuild and mounted in
// jsdom, as in left-out-settlement.test.mjs. Only the Supabase client, the auth
// context, xlsx and papaparse are stubbed. Every amount below is invented.
//
// Run: node --test scripts/tiktok/tests/xero-export.test.mjs
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
// The export remembers account codes in the browser's storage.
Object.defineProperty(globalThis, 'localStorage', { value: dom.window.localStorage, configurable: true, writable: true });
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
const week = (payout_date, extra = {}) => {
  const start = new Date(`${payout_date}T00:00:00Z`); start.setUTCDate(start.getUTCDate() - 6);
  return { payout_date, week_start: start.toISOString().slice(0, 10), week_end: payout_date, finished: true, row_count: 3,
    revenue: 0, fee: 0, expense: 0, payout: 0, tiktok_net: 0, unknown_count: 0, balance_movement_count: 0,
    other_currency_count: 0, left_out_count: 0, left_out_settlement: 0, uncovered_days: [], ...extra };
};
// Whatever month is asked for, its own Wednesdays: the first pays 120.00, the
// second is negative, the third has a left-out line, the fourth is empty and
// the fifth (when there is one) is not over yet.
const SHAPES = [
  { revenue: 150, fee: 30, payout: 120, tiktok_net: 120 },
  { revenue: 30, fee: 6, expense: 50, payout: -26, tiktok_net: -26 },
  { revenue: 190, fee: 41, payout: 149, tiktok_net: 149, left_out_count: 1, left_out_settlement: 12 },
  { row_count: 0 },
  { finished: false, revenue: 10, fee: 2, payout: 8, tiktok_net: 8 },
];
const payouts = (year, month) => {
  const p = settlementPeriod(year, month);
  const first = new Date(Date.UTC(p.start.y, p.start.m - 1, p.start.d));
  first.setUTCDate(first.getUTCDate() + ((3 - first.getUTCDay() + 7) % 7));
  const days = [];
  for (const d = new Date(first); d.toISOString().slice(0, 10) <= toIsoDate(p.end); d.setUTCDate(d.getUTCDate() + 7)) days.push(d.toISOString().slice(0, 10));
  const weeks = days.map((d, i) => week(d, SHAPES[i] ?? {}));
  const income = weeks.reduce((s, w) => s + w.payout, 0);
  return { year, month, period_start: toIsoDate(p.start), period_end: toIsoDate(p.end), today: '', timezone: 'Asia/Singapore',
    undated_count: 0, income, month_income: income, weeks };
};

// ── fake backend ───────────────────────────────────────────────────────────
function createBackend() {
  const b = { calls: [], failures: new Map(), held: new Map() };
  b.hold = name => { let release; const gate = new Promise(r => { release = r; }); b.held.set(name, gate); return () => release(); };
  const tables = {
    stores: [{ id: STORE, name: 'North Store', deleted_at: null, is_active: true }],
    products: [], vouchers: [], promotions: [], tiktok_status_mappings: [], tiktok_physical_returns: [],
    tiktok_import_batches: [], tiktok_settlement_rows: [],
  };
  const rpcs = {
    my_assigned_store_id: () => null,
    report_tiktok_imports: () => [],
    report_tiktok_settlement: () => [],
    tiktok_settlement_totals: a => ({ year: a.p_year, month: a.p_month, period_start: '', period_end: '', timezone: 'Asia/Singapore', row_count: 9,
      revenue: 380, fee: 79, settlement: 301, expense: 50, income: 251, tiktok_net_settlement: 246, by_category: {}, unknown_count: 0,
      balance_movement_count: 0, pending_match_count: 0, currency_count: 1, undated_count: 0, needs_review: false,
      left_out_count: 0, left_out_settlement: 0 }),
    tiktok_left_out_settlement: () => [],
    tiktok_xero_payouts: a => payouts(a.p_year, a.p_month),
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], orders: [], rangeV: null, one: false }); }
    select() { return this; }
    is(col, v) { this.filters.push(r => (r[col] ?? null) === v); return this; }
    eq(col, v) { this.filters.push(r => r[col] === v); return this; }
    order(col) { this.orders.push(col); return this; }
    range(a, z) { this.rangeV = [a, z]; return this; }
    single() { this.one = true; return this; }
    async exec() {
      b.calls.push({ name: this.name, args: this.args });
      const gate = b.held.get(this.name);
      if (gate) { b.held.delete(this.name); await gate; }
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
globalThis.alert = () => {};
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
  downloads = [];
  try { dom.window.localStorage.clear(); } catch { /* none */ }
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
const title = () => [...document.querySelectorAll('h2, h3, .modal-title')].map(h => h.textContent).find(t => t.startsWith('Export TikTok payouts')) ?? '';
const weeks = () => [...document.querySelectorAll('[data-testid="tiktok-xero-weeks"] tbody tr')].map(tr => [...tr.querySelectorAll('td')].map(td => td.textContent));
// A field, found by its visible label (the label is tied to the input).
const field = text => {
  const label = [...document.querySelectorAll('label')].find(l => l.textContent.trim().replace(/ \*$/, '') === text);
  return label && document.getElementById(label.htmlFor);
};
const tickBox = day => document.querySelector(`input[type="checkbox"][aria-label="Export the payout of ${day}"]`);
async function setValue(el, value, event = 'input') {
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => { Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value); el.dispatchEvent(new dom.window.Event(event, { bubbles: true })); });
  await tick();
}
// The month selects of the Settlements tab.
async function pickMonth(year, month) {
  const [monthSel, yearSel] = document.querySelector('[data-testid="left-out"]').parentElement.querySelectorAll('select');
  await setValue(yearSel, String(year), 'change');
  await setValue(monthSel, String(month), 'change');
}
async function openExport(opts, { year = 2026, month = 9 } = {}) {
  await mount(opts); await openTab('Settlements'); await pickMonth(year, month); await click(button('Xero Export'));
}
const csvOf = async d => (await d.blob.text()).split('\r\n').filter(Boolean);
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── tests ──────────────────────────────────────────────────────────────────
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

test('it reads the payouts of the month on screen and lists each Wednesday', async () => {
  await openExport();
  assert.deepEqual(callsOf('tiktok_xero_payouts').map(c => c.args), [{ p_year: 2026, p_month: 9 }]);
  assert.equal(title(), 'Export TikTok payouts for Xero — September 2026');
  assert.deepEqual(weeks(), [
    ['Wed 2 Sep', 'Thu 27 Aug – Wed 2 Sep 2026', 'S$150.00', '-S$30.00', 'S$0.00', 'S$120.00', 'Export'],
    ['Wed 9 Sep', 'Thu 3 Sep – Wed 9 Sep 2026', 'S$30.00', '-S$6.00', '-S$50.00', '-S$26.00', 'Export ⚠'],
    ['Wed 16 Sep', 'Thu 10 Sep – Wed 16 Sep 2026', 'S$190.00', '-S$41.00', 'S$0.00', 'S$149.00', 'Export ⚠'],
    ['Wed 23 Sep', 'Thu 17 Sep – Wed 23 Sep 2026', 'S$0.00', 'S$0.00', 'S$0.00', 'S$0.00', 'Nothing to pay ⚠'],
    ['Wed 30 Sep', 'Thu 24 Sep – Wed 30 Sep 2026', 'S$10.00', '-S$2.00', 'S$0.00', 'S$8.00', 'Not over yet'],
  ]);
  const total = document.querySelector('[data-testid="tiktok-xero-total"]').textContent;
  assert.ok(total.includes('Ticked: S$243.00 in 3 payouts.') && total.includes('Total Income for every store is S$251.00 (some Wednesdays are not over yet)'), total);
  const warnings = document.querySelector('[data-testid="tiktok-xero-warnings"]').textContent;
  assert.ok(warnings.includes('Wed 9 Sep: This week is negative (-S$26.00)'), warnings);
  assert.ok(warnings.includes('Wed 16 Sep: 1 settled line was left out at confirmation (S$12.00)'), warnings);
  assert.ok(warnings.includes('Wed 23 Sep: No settled lines were imported for this week'), warnings);
  assert.deepEqual(globalThis.__renderErrors, []);
});

test('Export CSV downloads the ticked Wednesdays, a negative week with its credit note, and remembers the codes', async () => {
  await openExport();
  assert.equal(field('Account for TikTok sales').value, '1011');
  assert.equal(field('Xero tax rate').value, 'No Tax (0%)');
  await setValue(field('Account for TikTok fees'), '6100');
  await setValue(field('Account for TikTok ads'), '6200');
  await click(button('Export CSV', footer()));
  assert.equal(downloads.length, 1);
  assert.equal(downloads[0].name, 'xero-tiktok-payouts-2026-09.csv');
  const csv = await csvOf(downloads[0]);
  assert.equal(csv.length, 1 + 2 + 1 + 2 + 2, 'the header, 2 Sep (2 lines), 9 Sep (1 + a credit note of 2), 16 Sep (2)');
  assert.ok(csv[1].startsWith('TikTok Shop,,,,,,,,,,TT-PAYOUT-2026-09-02,'));
  assert.ok(csv.some(l => l.includes(',TT-PAYOUT-2026-09-09-CN,') && l.includes(',-50.00,') && l.includes(',6200,')));
  assert.ok(!csv.some(l => l.includes('2026-09-30') || l.includes('2026-09-23')), 'unfinished and empty weeks are not exported');
  assert.ok(document.querySelector('[role="status"]').textContent.includes('Downloaded 3 Wednesday payouts, 1 of them with a credit note, totalling S$243.00'));
  assert.equal(button('Downloaded', footer()).disabled, true, 'the same file is not downloaded twice');
  assert.deepEqual(JSON.parse(dom.window.localStorage.getItem('energia.tiktokXeroCodes')),
    { salesCode: '1011', feesCode: '6100', adsCode: '6200', taxType: 'No Tax (0%)' });
  // Opened again, the codes are still there.
  await click(button('Close', footer()));
  await click(button('Xero Export'));
  assert.equal(field('Account for TikTok ads').value, '6200');
});

test('unticking a Wednesday leaves it out, and its code is no longer needed', async () => {
  await openExport();
  await setValue(field('Account for TikTok fees'), '6100');
  await click(tickBox('Wed 9 Sep'));
  assert.ok(document.querySelector('[data-testid="tiktok-xero-total"]').textContent.includes('Ticked: S$269.00 in 2 payouts.'));
  await click(button('Export CSV', footer()));
  const csv = await csvOf(downloads[0]);
  assert.ok(!csv.some(l => l.includes('TT-PAYOUT-2026-09-09')), 'the unticked week is not in the file');
  assert.equal(csv.length, 1 + 2 + 2, 'and the ads account was not needed');
});

test('a double click downloads once', async () => {
  await openExport();
  await setValue(field('Account for TikTok fees'), '6100');
  await setValue(field('Account for TikTok ads'), '6200');
  const exportButton = button('Export CSV', footer());
  await act(async () => {
    exportButton.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
    exportButton.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
  });
  await tick();
  assert.equal(downloads.length, 1);
});

test('a missing account code stops the export with the reason, next to the button', async () => {
  await openExport();
  await setValue(field('Account for TikTok fees'), '6100');
  await click(button('Export CSV', footer()));
  assert.equal(downloads.length, 0);
  const alert = document.querySelector('[role="alert"]');
  assert.ok(alert.textContent.includes('Enter the Xero account code for TikTok ads.'));
  assert.equal(alert.parentElement.lastElementChild, alert, 'the reason is the last thing before the buttons');
  assert.equal(field('Account for TikTok ads').getAttribute('aria-required'), 'true');
});

test('a slow answer for the month before never lands under the new month', async () => {
  let release;
  await mount();
  await openTab('Settlements');
  await pickMonth(2026, 9);
  release = backend.hold('tiktok_xero_payouts');
  await click(button('Xero Export'));
  await click(button('Close', footer()));
  await pickMonth(2026, 8);
  await click(button('Xero Export'));
  assert.equal(title(), 'Export TikTok payouts for Xero — August 2026');
  release();
  await tick();
  assert.equal(title(), 'Export TikTok payouts for Xero — August 2026');
  assert.deepEqual(weeks().map(w => w[0]), ['Wed 5 Aug', 'Wed 12 Aug', 'Wed 19 Aug', 'Wed 26 Aug'], 'August\'s Wednesdays, not September\'s');
  await setValue(field('Account for TikTok fees'), '6100');
  await setValue(field('Account for TikTok ads'), '6200');
  await click(button('Export CSV', footer()));
  assert.equal(downloads[0].name, 'xero-tiktok-payouts-2026-08.csv');
  assert.ok((await csvOf(downloads[0])).slice(1).every(l => l.includes('TT-PAYOUT-2026-08-')));
});

test('changing the month on the page while the export is open reads the new month', async () => {
  await openExport();
  assert.equal(title(), 'Export TikTok payouts for Xero — September 2026');
  await pickMonth(2026, 8);
  assert.deepEqual(callsOf('tiktok_xero_payouts').map(c => c.args.p_month), [9, 8]);
  assert.equal(title(), 'Export TikTok payouts for Xero — August 2026');
  assert.equal(weeks()[0][0], 'Wed 5 Aug');
});

test('payouts that come back for another month are not shown or exported', async () => {
  await openExport({ setup: b => { const real = b.client.rpc; b.client.rpc = (name, args) => real(name, name === 'tiktok_xero_payouts' ? { ...args, p_month: 8 } : args); } });
  assert.ok(document.querySelector('[role="alert"]').textContent.includes('The payouts came back for another month'));
  assert.deepEqual(weeks(), []);
  assert.equal(button('Export CSV', footer()).disabled, true);
});

test('a refusal from the database is shown, and nothing can be exported', async () => {
  await openExport({ setup: b => b.failures.set('tiktok_xero_payouts', 'Only an Owner or Manager can export TikTok payouts for Xero') });
  assert.ok(document.querySelector('[role="alert"]').textContent.includes('Only an Owner or Manager can export TikTok payouts for Xero'));
  assert.equal(button('Export CSV', footer()).disabled, true);
});
