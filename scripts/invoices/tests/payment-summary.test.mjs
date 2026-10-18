// The Payment Summary: daily takings by payment method (427, REPORTS-2 and
// REPORTS-3).
//
//   * It opens on the 1st of this month to today, in Singapore, whatever the
//     device's time zone and whatever the hour (before 8 am too).
//   * The Total is the money taken; wallet credit spent is shown after it,
//     marked as wallet credit, with its own total.
//   * Every day of the range has a row, zeroes where nothing was taken.
//
// The sheet is built by src/lib/paymentSummary.mjs (tested directly); the
// dialog, src/components/PaymentSummaryExport.tsx, is bundled with esbuild and
// mounted in jsdom with the Supabase client and xlsx stubbed. Every name and
// amount is invented.
//
// Run: node --test scripts/invoices/tests/payment-summary.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import { buildPaymentSummary, paymentSummaryDefaultRange, daysBetween, WALLET_TOTAL_HEADER }
  from '../../../src/lib/paymentSummary.mjs';

const methods = [
  { payment_method_id: 'm-cash', method_name: 'Cash', is_wallet_credit: false },
  { payment_method_id: 'm-paid', method_name: 'Paid Credit', is_wallet_credit: true },
  { payment_method_id: 'm-nets', method_name: 'NETS', is_wallet_credit: false },
  { payment_method_id: 'm-leg', method_name: 'Legacy Credit', is_wallet_credit: true },
];

test('the default range is the 1st of this month to today', () => {
  assert.deepEqual(paymentSummaryDefaultRange('2026-10-10'), { from: '2026-10-01', to: '2026-10-10' });
  assert.deepEqual(paymentSummaryDefaultRange('2026-10-01'), { from: '2026-10-01', to: '2026-10-01' });
  assert.deepEqual(paymentSummaryDefaultRange('2027-01-31'), { from: '2027-01-01', to: '2027-01-31' });
});

test('every day of the range, both ends included, across a month and a year', () => {
  assert.deepEqual(daysBetween('2026-12-30', '2027-01-02'), ['2026-12-30', '2026-12-31', '2027-01-01', '2027-01-02']);
  assert.equal(daysBetween('2026-09-01', '2026-09-30').length, 30);
  assert.deepEqual(daysBetween('2026-09-02', '2026-09-01'), []);
});

test('the Total is the money taken; wallet credit is after it, marked, with its own total; empty days are zeroes', () => {
  const rows = [
    { pay_date: '2026-09-01', payment_method_id: 'm-cash', method_name: 'Cash', amount: '100.10' },
    { pay_date: '2026-09-01', payment_method_id: 'm-paid', method_name: 'Paid Credit', amount: '50' },
    { pay_date: '2026-09-03', payment_method_id: 'm-nets', method_name: 'NETS', amount: '20.20' },
    { pay_date: '2026-09-03', payment_method_id: 'm-leg', method_name: 'Legacy Credit', amount: '5' },
    { pay_date: '2026-09-03', payment_method_id: 'm-cash', method_name: 'Cash', amount: '-10.10' }, // a correction reversal
  ];
  const { headers, body, moneyTaken, walletUsed } = buildPaymentSummary({ methods, rows, from: '2026-09-01', to: '2026-09-04' });
  assert.deepEqual(headers, ['Date', 'Cash', 'NETS', 'Total', 'Legacy Credit (wallet credit)', 'Paid Credit (wallet credit)',
    WALLET_TOTAL_HEADER]);
  assert.equal(WALLET_TOTAL_HEADER, 'Wallet credit used (not money taken)');
  assert.deepEqual(body.map(r => r.Date), ['01/09/2026', '02/09/2026', '03/09/2026', '04/09/2026', 'TOTAL'],
    'every day, written day first, then the total row');
  assert.deepEqual(body[0], { Date: '01/09/2026', Cash: 100.1, NETS: 0, Total: 100.1, 'Legacy Credit (wallet credit)': 0,
    'Paid Credit (wallet credit)': 50, [WALLET_TOTAL_HEADER]: 50 });
  assert.deepEqual(body[1], { Date: '02/09/2026', Cash: 0, NETS: 0, Total: 0, 'Legacy Credit (wallet credit)': 0,
    'Paid Credit (wallet credit)': 0, [WALLET_TOTAL_HEADER]: 0 }, 'a day with no takings is a row of zeroes');
  assert.deepEqual(body[2], { Date: '03/09/2026', Cash: -10.1, NETS: 20.2, Total: 10.1, 'Legacy Credit (wallet credit)': 5,
    'Paid Credit (wallet credit)': 0, [WALLET_TOTAL_HEADER]: 5 });
  assert.deepEqual(body.at(-1), { Date: 'TOTAL', Cash: 90, NETS: 20.2, Total: 110.2, 'Legacy Credit (wallet credit)': 5,
    'Paid Credit (wallet credit)': 50, [WALLET_TOTAL_HEADER]: 55 });
  assert.equal(moneyTaken, 110.2);
  assert.equal(walletUsed, 55);
});

test('with no wallet credit in the range there are no wallet columns', () => {
  const { headers, body } = buildPaymentSummary({ methods: methods.filter(m => !m.is_wallet_credit),
    rows: [{ pay_date: '2026-09-01', payment_method_id: 'm-cash', amount: 1 }], from: '2026-09-01', to: '2026-09-01' });
  assert.deepEqual(headers, ['Date', 'Cash', 'NETS', 'Total']);
  assert.deepEqual(body.at(-1), { Date: 'TOTAL', Cash: 1, NETS: 0, Total: 1 });
});

// ── the dialog ─────────────────────────────────────────────────────────────
const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://summary.invalid', pretendToBeVisual: true });
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
      export { PaymentSummaryExport } from './src/components/PaymentSummaryExport';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      export { React };`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /^xlsx$/ }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { rpc: (...a) => globalThis.__rpc(...a) };' }));
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const utils = {
        json_to_sheet: (body, opts) => ({ body, header: opts && opts.header }),
        book_new: () => ({ sheets: [] }),
        book_append_sheet: (wb, ws, name) => { wb.sheets.push({ ws, name }); },
      };
      export const writeFile = (wb, filename) => { globalThis.__exports.push({ filename, sheet: wb.sheets[0] }); };` }));
  } }],
});
const { PaymentSummaryExport, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

let root = null;
const tick = async (n = 6) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); };
const button = label => [...document.querySelectorAll('button')].find(b => b.textContent.trim().endsWith(label));
async function openAt(instant, tz) {
  const RealDate = globalThis.Date;
  const fixed = RealDate.parse(instant);
  class FrozenDate extends RealDate { constructor(...a) { super(...(a.length ? a : [fixed])); } static now() { return fixed; } }
  const realTz = process.env.TZ;
  process.env.TZ = tz;
  globalThis.Date = FrozenDate;
  try {
    if (root) await act(async () => root.unmount());
    document.body.innerHTML = '<div id="root"></div>';
    root = createRoot(document.getElementById('root'));
    await act(async () => root.render(React.createElement(PaymentSummaryExport, { stores: [{ id: 's-1', name: 'Fixture Store' }] })));
    await click(button('Payment Summary'));
    return [...document.querySelectorAll('input[type="date"]')].map(i => i.value);
  } finally { globalThis.Date = RealDate; process.env.TZ = realTz; }
}
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

test('REPORTS-2: the dialog opens on the 1st to today in Singapore, whatever the zone and the hour', async () => {
  for (const tz of ['Asia/Singapore', 'UTC', 'America/Los_Angeles']) {
    // 12:00 on 10 Oct 2026 in Singapore.
    assert.deepEqual(await openAt('2026-10-10T04:00:00Z', tz), ['2026-10-01', '2026-10-10'], `noon, ${tz}`);
    // 07:30 on 10 Oct in Singapore: still 9 Oct in UTC.
    assert.deepEqual(await openAt('2026-10-09T23:30:00Z', tz), ['2026-10-01', '2026-10-10'], `07:30, ${tz}`);
    // 07:30 on 1 Oct in Singapore: still September in UTC.
    assert.deepEqual(await openAt('2026-09-30T23:30:00Z', tz), ['2026-10-01', '2026-10-01'], `07:30 on the 1st, ${tz}`);
  }
});

test('REPORTS-3: the sheet has the money taken, then the wallet credit, and a row for every day', async () => {
  globalThis.__exports = [];
  globalThis.__rpc = (name, args) => ({
    range: async () => name === 'payment_methods_in_range'
      ? { data: methods.slice(0, 2), error: null }
      : { data: [{ pay_date: args.p_from, payment_method_id: 'm-cash', method_name: 'Cash', amount: 100, payment_count: 1 },
                 { pay_date: args.p_from, payment_method_id: 'm-paid', method_name: 'Paid Credit', amount: 40, payment_count: 1 }], error: null },
  });
  await openAt('2026-10-10T04:00:00Z', 'Asia/Singapore');
  await click(button('Export Excel')); await tick();
  const exported = globalThis.__exports.at(-1);
  assert.ok(exported, 'a sheet is written');
  assert.deepEqual(exported.sheet.ws.header, ['Date', 'Cash', 'Total', 'Paid Credit (wallet credit)', WALLET_TOTAL_HEADER]);
  assert.equal(exported.sheet.ws.body.length, 11, 'ten days and the total row');
  assert.deepEqual(exported.sheet.ws.body.at(-1), { Date: 'TOTAL', Cash: 100, Total: 100, 'Paid Credit (wallet credit)': 40, [WALLET_TOTAL_HEADER]: 40 });
  assert.equal(exported.filename, 'daily-payments-all-stores-2026-10-01-to-2026-10-10.xlsx');
  const note = document.body.textContent;
  assert.ok(!note.includes('Days with no takings are included as zeroes, so a gap'), 'the old note is gone');
});

test('REPORTS-3: the dialog says what the sheet holds', async () => {
  await openAt('2026-10-10T04:00:00Z', 'Asia/Singapore');
  const t = document.body.textContent;
  assert.ok(t.includes('Payments on deleted invoices are left out'));
  assert.ok(t.includes('Wallet credit spent is not money taken'));
  assert.ok(t.includes('a day with no takings shows zeroes'));
  assert.ok(t.includes('Refunds are not deducted'));
});
