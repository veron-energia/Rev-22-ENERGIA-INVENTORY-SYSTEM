// The Commissions page's Balances tab filters (the Owner, 27 Oct 2026),
// rendered for real against a fake backend: a Status filter (All, Unpaid,
// Partly paid, Paid) and a Commission month filter (All months, each month
// with rows newest first, Date needs review). The table and the Excel export
// show only the rows that match; "Payable now in view" adds up their Payable
// now beside the overall "Remaining payable", which does not change; an empty
// result says "No balances match these filters."; the Payout History tab is
// as before.
//
// src/components/commissions/AffiliatePayoutPanel.tsx is bundled with esbuild
// and mounted in jsdom; only the Supabase client and xlsx (an export is
// captured, not written) are stubbed. Every name and amount below is invented.
//
// Run: node --test scripts/commissions/tests/balances-filters-panel.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://commissions.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver', 'sessionStorage']) {
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
      export { AffiliatePayoutPanel } from './src/components/commissions/AffiliatePayoutPanel';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      import React from 'react';
      export { React };`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { rpc: (...a) => globalThis.__rpc(...a), from: () => ({}) };' }));
    b.onResolve({ filter: /^xlsx$/ }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const utils = {
        json_to_sheet: (body, opts) => ({ body, header: opts && opts.header }),
        book_new: () => ({ sheets: [] }),
        book_append_sheet: (wb, ws, name) => { wb.sheets.push({ ws, name }); },
      };
      export const writeFile = (wb, filename) => { (globalThis.__exports ||= []).push({ filename, sheet: wb.sheets[0] }); };` }));
  } }],
});
const { AffiliatePayoutPanel, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// Seven months, shaped as 410/414's affiliate_payout_overview sends them.
// Alpha: October unpaid (100.00), September partly paid (150.00 left), August
// paid. Bravo: owes 20.00 back in October (Paid: nothing remaining), is owed
// 40.00 for September, of which 20.00 is payable once October is netted in.
// Charlie: a row with no month and a partly paid July, both under review.
const REFS = {
  'ref-a': { referrer: 'ref-a', owed: 250, unpaid: 250, deduction: 0, payable: 250 },
  'ref-b': { referrer: 'ref-b', owed: 20, unpaid: 20, deduction: 0, payable: 20 },
  'ref-c': { referrer: 'ref-c', owed: 90, unpaid: 90, deduction: 0, payable: 0 },
};
const month = (referrer, m, earned, adjustments, paid, payable, review = null) => ({
  referrer, month: m, earned, adjustments, paid, balance: +(earned + adjustments - paid).toFixed(2), tier1: earned, tier2: 0,
  review_reason: review, settled: 0, payable, referrer_owed: REFS[referrer].owed, referrer_payable: REFS[referrer].payable, referrer_deduction: 0,
});
const METHODS = [{ id: 'm1', name: 'Bank Transfer', is_active: true, deleted_at: null, is_wallet_credit: false }];
function overview() {
  return {
    groups: [
      month('ref-a', '2026-10-01', 100, 0, 0, 100),
      month('ref-b', '2026-10-01', 50, -10, 60, 0),
      month('ref-a', '2026-09-01', 200, 0, 50, 150),
      month('ref-b', '2026-09-01', 40, 0, 0, 20),
      month('ref-a', '2026-08-01', 80, 0, 80, 0),
      month('ref-c', '2026-07-01', 90, 0, 30, 0, 'Payout allocation needs review.'),
      month('ref-c', null, 30, 0, 0, 0, 'Commission date is missing. Review the original invoice before recording a payout.'),
    ],
    referrers: Object.values(REFS),
    payouts: [{ id: 'pay-1', referrer_customer_id: 'ref-a', payout_month: '2026-09-01', total_amount: 50, total_tier1: 50, total_tier2: 0,
      payment_date: '2026-10-05', payment_method_id: 'm1', payment_method_name: 'Bank Transfer', reference: null, notes: null,
      status: 'paid', version: 1, allocation_state: 'verified', allocation_review_reason: null }],
    settlements: [], methods: METHODS,
  };
}

let state;
function backend(initial) {
  state = initial;
  globalThis.__rpc = async (name) => {
    if (name === 'affiliate_payout_overview') return { data: structuredClone(state), error: null };
    if (name === 'commission_referrer_names') return { data: [{ id: 'ref-a', full_name: 'Alpha Affiliate' }, { id: 'ref-b', full_name: 'Bravo Affiliate' }, { id: 'ref-c', full_name: 'Charlie Affiliate' }], error: null };
    return { data: null, error: { message: 'unexpected ' + name } };
  };
}
const settle = async () => { await act(async () => { await new Promise(r => setTimeout(r, 15)); }); };
async function render(mode = 'earned') {
  const host = document.createElement('div'); document.body.appendChild(host);
  const root = createRoot(host);
  await act(async () => { root.render(React.createElement(AffiliatePayoutPanel, { mode, canPay: true, userId: 'owner', onSaved: () => {} })); });
  for (let i = 0; i < 10 && !host.textContent.includes('Charlie Affiliate'); i++) await settle();
  return { host, root, done: async () => { await act(async () => root.unmount()); host.remove(); } };
}
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await settle(); };
// The control a visible label names (label for= / id).
const control = (host, text) => {
  const label = [...host.querySelectorAll('label')].find(l => l.textContent.trim() === text);
  assert.ok(label, `a label reading "${text}"`);
  const el = label.htmlFor ? host.ownerDocument.getElementById(label.htmlFor) : label.querySelector('select,input');
  assert.ok(el && host.contains(el), `"${text}" names a control`);
  return el;
};
const choose = async (host, text, value) => {
  const el = control(host, text);
  await act(async () => {
    Object.getOwnPropertyDescriptor(dom.window.HTMLSelectElement.prototype, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event('change', { bubbles: true }));
  });
  await settle();
};
const options = el => [...el.options].map(o => o.textContent);
const shown = host => [...host.querySelectorAll('tbody tr')].map(tr => {
  const cells = [...tr.querySelectorAll('td')];
  return cells.length < 2 ? cells[0]?.textContent : `${cells[1].textContent} ${cells[0].textContent}`;
});
const inView = host => /Payable now in view: (S\$[\d.]+)/.exec(host.textContent)?.[1];
const exportButton = host => [...host.querySelectorAll('button')].find(b => b.textContent.includes('Export Excel'));

test('the two filters, labelled, with the choices the Owner named', async () => {
  backend(overview());
  const r = await render();
  try {
    const status = control(r.host, 'Status'), monthSel = control(r.host, 'Commission month');
    assert.equal(status.tagName, 'SELECT'); assert.equal(monthSel.tagName, 'SELECT');
    assert.deepEqual(options(status), ['All', 'Unpaid', 'Partly paid', 'Paid']);
    assert.deepEqual(options(monthSel), ['All months', 'Oct 2026', 'Sep 2026', 'Aug 2026', 'Jul 2026', 'Date needs review']);
    assert.equal(status.value, 'all'); assert.equal(monthSel.value, 'all');
    // What each status means is visible text the Status select is described by
    // (not a hover-only tooltip), so phone, keyboard and screen-reader users get it.
    const hint = r.host.ownerDocument.getElementById(status.getAttribute('aria-describedby'));
    assert.ok(hint && r.host.contains(hint), 'Status is described by an element in the panel');
    assert.equal(hint.textContent, 'Paid: nothing remaining, including a month the affiliate owes money back on. Partly paid: something paid and something remaining. Unpaid: nothing paid yet.');
    assert.equal(r.host.querySelector('[title^="Paid: nothing remaining"]'), null);
    // A filter change is announced: the in-view total is a polite live region.
    assert.equal([...r.host.querySelectorAll('[role="status"]')].filter(e => e.textContent.startsWith('Payable now in view:')).length, 1);
    // Unfiltered: every row, in the order it came, and the two totals agree.
    assert.equal(shown(r.host).length, 7);
    assert.match(r.host.textContent, /Remaining payable: S\$270\.00/);
    assert.equal(inView(r.host), 'S$270.00');
  } finally { await r.done(); }
});

test('status, month and both together choose the rows; Remaining payable stays the overall figure', async () => {
  backend(overview());
  const r = await render();
  try {
    await choose(r.host, 'Status', 'unpaid');
    assert.deepEqual(shown(r.host), ['Alpha Affiliate 2026-10', 'Bravo Affiliate 2026-09', 'Charlie Affiliate Date needs review']);
    assert.equal(inView(r.host), 'S$120.00');
    assert.match(r.host.textContent, /Remaining payable: S\$270\.00/, 'the overall figure does not follow the filters');

    await choose(r.host, 'Status', 'partly_paid');
    assert.deepEqual(shown(r.host), ['Alpha Affiliate 2026-09', 'Charlie Affiliate 2026-07']);
    assert.equal(inView(r.host), 'S$150.00');

    await choose(r.host, 'Status', 'paid');
    assert.deepEqual(shown(r.host), ['Bravo Affiliate 2026-10', 'Alpha Affiliate 2026-08']);
    assert.match(r.host.textContent, /Owed back: S\$20\.00/, 'a month owed back on is Paid: nothing remaining');
    assert.equal(inView(r.host), 'S$0.00');

    await choose(r.host, 'Status', 'all');
    await choose(r.host, 'Commission month', '2026-10');
    assert.deepEqual(shown(r.host), ['Alpha Affiliate 2026-10', 'Bravo Affiliate 2026-10']);
    assert.equal(inView(r.host), 'S$100.00');

    await choose(r.host, 'Status', 'unpaid');
    await choose(r.host, 'Commission month', '2026-09');
    assert.deepEqual(shown(r.host), ['Bravo Affiliate 2026-09']);
    assert.equal(inView(r.host), 'S$20.00');

    await choose(r.host, 'Commission month', 'none');
    assert.deepEqual(shown(r.host), ['Charlie Affiliate Date needs review']);
    assert.match(r.host.textContent, /Commission date is missing/, 'the review reason is still shown');
    assert.equal(inView(r.host), 'S$0.00');

    // The figures in a shown row are the same as unfiltered.
    await choose(r.host, 'Status', 'all');
    await choose(r.host, 'Commission month', '2026-09');
    const alphaSep = [...r.host.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('Alpha Affiliate'));
    assert.deepEqual([...alphaSep.querySelectorAll('td')].slice(2, 7).map(td => td.textContent.match(/S\$[\d.]+/)[0]),
      ['S$200.00', 'S$0.00', 'S$50.00', 'S$150.00', 'S$150.00']);
    assert.equal([...alphaSep.querySelectorAll('button')].find(b => b.textContent === 'Record payout').disabled, false);
  } finally { await r.done(); }
});

test('nothing matching says so; no balances at all still says "No commission balances."', async () => {
  backend(overview());
  const r = await render();
  try {
    await choose(r.host, 'Status', 'unpaid');
    await choose(r.host, 'Commission month', '2026-08');
    assert.deepEqual(shown(r.host), ['No balances match these filters.']);
    assert.equal(inView(r.host), 'S$0.00');
    assert.equal(exportButton(r.host).disabled, true, 'nothing to export');
    assert.doesNotMatch(r.host.textContent, /No commission balances\./);
  } finally { await r.done(); }

  backend({ ...overview(), groups: [], referrers: [] });
  const empty = await render();
  try {
    for (let i = 0; i < 5 && !empty.host.textContent.includes('No commission balances.'); i++) await settle();
    assert.deepEqual(shown(empty.host), ['No commission balances.']);
    assert.deepEqual(options(control(empty.host, 'Commission month')), ['All months']);
    assert.doesNotMatch(empty.host.textContent, /No balances match these filters\./);
  } finally { await empty.done(); }
});

test('the export holds only the rows shown, with the same columns as before', async () => {
  backend(overview());
  const r = await render();
  try {
    globalThis.__exports = [];
    await click(exportButton(r.host));
    const all = globalThis.__exports.at(-1).sheet.ws;
    assert.equal(all.body.length, 7, 'unfiltered: every row');
    assert.deepEqual(all.header, ['Affiliate', 'Affiliate ID', 'Month', 'earned', 'adjustments', 'paid', 'settled', 'balance', 'payable now', 'affiliate deduction to recover', 'Review']);

    await choose(r.host, 'Commission month', '2026-09');
    await click(exportButton(r.host));
    const sep = globalThis.__exports.at(-1).sheet.ws;
    assert.deepEqual(sep.body.map(x => [x.Affiliate, x.Month, x['payable now']]), [['Alpha Affiliate', '2026-09-01', 150], ['Bravo Affiliate', '2026-09-01', 20]]);
    assert.deepEqual(sep.header, all.header);

    await choose(r.host, 'Commission month', 'all');
    await choose(r.host, 'Status', 'unpaid');
    await click(exportButton(r.host));
    const unpaid = globalThis.__exports.at(-1).sheet.ws;
    assert.deepEqual(unpaid.body.map(x => [x['Affiliate ID'], x.Month]), [['ref-a', '2026-10-01'], ['ref-b', '2026-09-01'], ['ref-c', 'Date needs review']]);
    assert.equal(unpaid.body.reduce((s, x) => s + Math.round(x['payable now'] * 100), 0), 12000, 'the export adds up to Payable now in view');
  } finally { await r.done(); }
});

test('a chosen month that a refresh leaves with no rows goes back to All months', async () => {
  backend(overview());
  const r = await render();
  try {
    await choose(r.host, 'Commission month', '2026-07');
    assert.deepEqual(shown(r.host), ['Charlie Affiliate 2026-07']);
    state = { ...overview(), groups: overview().groups.filter(g => g.month !== '2026-07-01') };
    await click([...r.host.querySelectorAll('button')].find(b => b.textContent === 'Refresh payouts'));
    const monthSel = control(r.host, 'Commission month');
    assert.equal(monthSel.value, 'all');
    assert.deepEqual(options(monthSel), ['All months', 'Oct 2026', 'Sep 2026', 'Aug 2026', 'Date needs review']);
    assert.equal(shown(r.host).length, 6);
  } finally { await r.done(); }
});

test('the Payout History tab is as before: no balance filters and no Payable now in view', async () => {
  backend(overview());
  const r = await render('payouts');
  try {
    assert.equal([...r.host.querySelectorAll('label')].some(l => /^(Status|Commission month)$/.test(l.textContent.trim())), false);
    assert.doesNotMatch(r.host.textContent, /Payable now in view/);
    assert.match(r.host.textContent, /Remaining payable: S\$270\.00/);
    assert.ok([...r.host.querySelectorAll('label')].some(l => l.textContent.startsWith('Payment date from')));
    assert.equal(r.host.querySelectorAll('tbody tr').length >= 1, true);
    assert.match(r.host.querySelector('tbody').textContent, /2026-10-05/);
  } finally { await r.done(); }
});
