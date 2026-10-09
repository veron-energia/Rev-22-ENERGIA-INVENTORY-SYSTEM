// 414: the Commissions page's "Mark as settled" and its Void, rendered for real
// against a fake backend. An Owner or Manager sees Mark as settled beside
// "Affiliate owes ... back"; the dialog asks how, the amount (at first, and at
// most, the deduction), the date and a note, and sends them with one request
// id that a retry after a lost answer keeps; the settlement is listed in the
// payout history with how it was settled and a Void, which needs a reason.
// Admins (who may read the page but not record payouts) get neither button.
// A save whose answer was lost comes back after a reload with the same
// request id; the date may not be before the affiliate's first payout; the
// balances export carries what each month takes of the settlements, so its
// columns add up; dates read DD/MM/YYYY like the rest of the row.
//
// src/components/commissions/AffiliatePayoutPanel.tsx is bundled with esbuild
// and mounted in jsdom; only the Supabase client and xlsx (an export is
// captured, not written) are stubbed. Every name and amount below is invented.
//
// Run: node --test scripts/commissions/tests/deduction-settlement-panel.test.mjs
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

// Alpha owes 555.27 back (September -562.35, October +7.08: the production
// case of 9 Oct 2026); Bravo is owed 100.00.
const month = (referrer, m, earned, adjustments, paid, extra = {}) =>
  ({ referrer, month: m, earned, adjustments, paid, balance: +(earned + adjustments - paid).toFixed(2), tier1: earned, tier2: 0, review_reason: null, settled: 0, ...extra });
const METHODS = [{ id: 'm1', name: 'Bank Transfer', is_active: true, deleted_at: null, is_wallet_credit: false }];
// Alpha's two payouts: September's paid on 2 Oct 2026 (the first), October's on 6 Oct.
const payout = (id, m, amount, paymentDate) => ({ id, referrer_customer_id: 'ref-a', payout_month: m, total_amount: amount, total_tier1: amount,
  total_tier2: 0, payment_date: paymentDate, payment_method_id: 'm1', payment_method_name: 'Bank Transfer', reference: null, notes: null,
  status: 'paid', version: 1, allocation_state: 'verified', allocation_review_reason: null });
function owing() {
  return {
    groups: [month('ref-a', '2026-10-01', 100.8, 0, 93.72, { payable: 0, referrer_owed: -555.27, referrer_payable: 0, referrer_deduction: 555.27 }),
             month('ref-b', '2026-10-01', 100, 0, 0, { payable: 100, referrer_owed: 100, referrer_payable: 100, referrer_deduction: 0 }),
             month('ref-a', '2026-09-01', 1705.59, -991.64, 1276.30, { payable: 0, referrer_owed: -555.27, referrer_payable: 0, referrer_deduction: 555.27 })],
    referrers: [{ referrer: 'ref-a', owed: -555.27, unpaid: 0, deduction: 555.27, payable: 0 },
                { referrer: 'ref-b', owed: 100, unpaid: 100, deduction: 0, payable: 100 }],
    payouts: [payout('pay-2', '2026-10-01', 93.72, '2026-10-06'), payout('pay-1', '2026-09-01', 1276.30, '2026-10-02')],
    settlements: [], methods: METHODS,
  };
}
const SETTLED = { id: 'set-1', referrer_customer_id: 'ref-a', amount: 555.27, settled_on: '2026-10-09', method: 'paid_outside_app',
  note: 'Taken off a payment made outside the app', created_by: 'owner', created_by_name: 'Olive Owner', created_at: '2026-10-09T03:00:00Z',
  voided_at: null, voided_by: null, voided_by_name: null, void_reason: null };
function settled() {
  const o = owing();
  o.groups = o.groups.map(g => g.referrer !== 'ref-a' ? g
    : { ...g, referrer_owed: 0, referrer_deduction: 0, ...(g.month === '2026-09-01' ? { balance: -7.08, settled: 555.27 } : {}) });
  o.referrers[0] = { referrer: 'ref-a', owed: 0, unpaid: 0, deduction: 0, payable: 0 };
  o.settlements = [SETTLED];
  return o;
}

let state, calls;
function backend(initial, answers = {}) {
  state = initial; calls = [];
  globalThis.__rpc = async (name, args) => {
    calls.push({ name, args });
    if (name === 'affiliate_payout_overview') return { data: structuredClone(state), error: null };
    if (name === 'commission_referrer_names') return { data: [{ id: 'ref-a', full_name: 'Alpha Affiliate' }, { id: 'ref-b', full_name: 'Bravo Affiliate' }], error: null };
    if (answers[name]) return answers[name](args);
    return { data: null, error: { message: 'unexpected ' + name } };
  };
}
const settle = async () => { await act(async () => { await new Promise(r => setTimeout(r, 15)); }); };
async function render(mode, canPay = true) {
  const host = document.createElement('div'); document.body.appendChild(host);
  const root = createRoot(host);
  await act(async () => { root.render(React.createElement(AffiliatePayoutPanel, { mode, canPay, userId: 'owner', onSaved: () => {} })); });
  for (let i = 0; i < 10 && !host.textContent.includes('Alpha Affiliate'); i++) await settle();
  return { host, root, done: async () => { await act(async () => root.unmount()); host.remove(); } };
}
const buttons = (el, text) => [...el.querySelectorAll('button')].filter(b => b.textContent === text);
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await settle(); };
const type = async (el, value) => {
  const proto = el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event('input', { bubbles: true }));
  });
};
const dialog = host => host.querySelector('[role="dialog"]');
const field = (host, labelStart) => [...dialog(host).querySelectorAll('label')].find(l => l.textContent.startsWith(labelStart))?.querySelector('input,textarea');

test('an Owner or Manager marks the deduction as settled: how, amount, date, note, one request', async () => {
  backend(owing(), { record_affiliate_deduction_settlement: args => { state = settled(); return { data: { id: 'set-1', referrer: args.p_referrer_customer_id, amount: Number(args.p_amount), settled_on: args.p_settled_on, method: args.p_method }, error: null }; } });
  const { host, done } = await render('earned');
  try {
    const marks = buttons(host, 'Mark as settled');
    assert.equal(marks.length, 2, 'beside "Affiliate owes ... back" on each of Alpha\'s months, and nowhere for Bravo');
    for (const b of marks) assert.match(b.closest('div').parentElement.textContent, /Affiliate owes S\$555\.27 back; recovered from later commission first\./);
    await click(marks[0]);
    assert.equal(dialog(host).querySelector('h3').textContent, 'Mark deduction as settled');
    assert.match(dialog(host).textContent, /Alpha Affiliate owes S\$555\.27 back from commission already paid out and then taken back\./);
    assert.match(dialog(host).textContent, /does not pay or collect anything/);
    assert.equal(field(host, 'Amount').value, '555.27', 'the amount starts at the deduction');
    assert.equal(field(host, 'Amount').max, '555.27', 'and may not be more');
    assert.equal(field(host, 'Date it was settled').value.length, 10, 'the date starts at today (Singapore)');
    assert.deepEqual([...dialog(host).querySelectorAll('input[type=radio]')].map(r => r.parentElement.textContent),
      ['Paid back to us', 'Written off', 'Paid off outside the app']);
    assert.ok([...dialog(host).querySelectorAll('input[type=radio]')].every(r => !r.checked), 'how it was settled is chosen, never assumed');

    await click(buttons(dialog(host), 'Mark as settled')[0]);
    assert.match(dialog(host).querySelector('[role=alert]').textContent, /Choose how it was settled\./);
    await click(dialog(host).querySelectorAll('input[type=radio]')[2]);
    await type(field(host, 'Amount'), '555.28');
    await click(buttons(dialog(host), 'Mark as settled')[0]);
    assert.match(dialog(host).querySelector('[role=alert]').textContent, /Enter at most S\$555\.27, what this affiliate owes back\./);
    await type(field(host, 'Amount'), '555.27');
    assert.equal(field(host, 'Date it was settled').min, '2026-10-02', 'not before the first payout to Alpha');
    await type(field(host, 'Date it was settled'), '2026-10-01');
    await click(buttons(dialog(host), 'Mark as settled')[0]);
    assert.equal(dialog(host).querySelector('[role=alert]').textContent,
      'The date it was settled cannot be before the first payout to this affiliate, on 2 Oct 2026.', 'said as the server says it');
    await type(field(host, 'Date it was settled'), '2026-10-09');
    await click(buttons(dialog(host), 'Mark as settled')[0]);
    assert.match(dialog(host).querySelector('[role=alert]').textContent, /A note is required/);
    assert.equal(calls.filter(c => c.name === 'record_affiliate_deduction_settlement').length, 0, 'nothing is sent while the form is incomplete');

    await type(field(host, 'Note'), '  Taken off a payment made outside the app  ');
    await click(buttons(dialog(host), 'Mark as settled')[0]);
    const sent = calls.filter(c => c.name === 'record_affiliate_deduction_settlement');
    assert.equal(sent.length, 1);
    assert.deepEqual({ ...sent[0].args, p_request_id: typeof sent[0].args.p_request_id }, {
      p_referrer_customer_id: 'ref-a', p_amount: '555.27', p_settled_on: '2026-10-09', p_method: 'paid_outside_app',
      p_note: 'Taken off a payment made outside the app', p_request_id: 'string' });
    assert.equal(dialog(host), null, 'the dialog closes');
    assert.match(host.textContent, /Marked as settled: S\$555\.27 for Alpha Affiliate \(Paid off outside the app, 09\/10\/2026\)\. The commission records and payouts are unchanged\./);
    assert.equal(sessionStorage.getItem('energia-affiliate-settlement-pending:owner'), null, 'nothing is left pending once answered');
    assert.equal(buttons(host, 'Mark as settled').length, 0, 'the deduction is gone after the refresh');
    assert.doesNotMatch(host.textContent, /Affiliate owes S\$555\.27 back/);
    assert.match(host.textContent, /Settled: S\$555\.27/, 'September shows what it took of the settlement');
    assert.match(host.textContent, /Owed back: S\$7\.08/, 'and October\'s 7.08 stays counted against it');
  } finally { await done(); }
});

test('a lost answer is retried with the same request; a refusal starts a new one', async () => {
  let n = 0;
  backend(owing(), { record_affiliate_deduction_settlement: () => (++n === 1
    ? { data: null, error: { message: 'Failed to fetch' } }
    : n === 2 ? { data: { id: 'set-1', amount: 100, settled_on: '2026-10-09', method: 'written_off' }, error: null }
    : { data: null, error: { code: 'P0001', message: 'This affiliate owes nothing back, so there is nothing to settle. Refresh the summary.' } }) });
  const { host, done } = await render('earned');
  try {
    await click(buttons(host, 'Mark as settled')[0]);
    await click(dialog(host).querySelectorAll('input[type=radio]')[1]);
    await type(field(host, 'Amount'), '100');
    await type(field(host, 'Note'), 'Written off by the Owner');
    await click(buttons(dialog(host), 'Mark as settled')[0]);
    assert.match(dialog(host).textContent, /The result is unconfirmed: Failed to fetch\. Retry; it cannot be recorded twice\./);
    assert.equal(buttons(dialog(host), 'Cancel')[0].disabled, true, 'the dialog stays until the answer is known');
    assert.equal(field(host, 'Note').disabled || field(host, 'Note').closest('fieldset').disabled, true, 'and the form is frozen');
    await click(buttons(dialog(host), 'Retry same save')[0]);
    const sent = calls.filter(c => c.name === 'record_affiliate_deduction_settlement');
    assert.equal(sent.length, 2);
    assert.equal(sent[1].args.p_request_id, sent[0].args.p_request_id, 'the retry sends the same request id');
    assert.equal(dialog(host), null);
  } finally { await done(); }
});

test('the payout history lists the settlement with how it was settled; Void needs a reason', async () => {
  backend(settled(), { void_affiliate_deduction_settlement: args => {
    if (!args.p_reason) return { data: null, error: { code: 'P0001', message: 'A reason is required to void a settlement.' } };
    state = owing(); state.settlements = [{ ...SETTLED, voided_at: '2026-10-10T02:00:00Z', voided_by: 'mgr', voided_by_name: 'Max Manager', void_reason: args.p_reason }];
    return { data: { id: args.p_settlement_id, referrer: 'ref-a', amount: 555.27, voided: true }, error: null };
  } });
  const { host, done } = await render('payouts');
  try {
    const card = host.querySelector('[data-testid="settlement-history"]');
    assert.ok(card, 'a "Deductions marked as settled" list under the payouts');
    assert.match(card.textContent, /Filtered by the date settled, using the payment date range above\./);
    assert.match(card.textContent, /the months it covers can change when later corrections arrive/);
    const row = [...card.querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('Alpha Affiliate'));
    assert.equal(row.querySelector('td').textContent, '09/10/2026', 'the date settled reads as the other dates in the row do');
    assert.doesNotMatch(row.textContent, /2026-10-09/);
    const note = [...row.querySelectorAll('td')].find(td => td.textContent.startsWith('Taken off a payment'));
    assert.equal(note.style.minWidth, '180px', 'a long note does not squeeze its column on a phone');
    assert.match(row.textContent, /S\$555\.27/);
    assert.match(row.textContent, /Paid off outside the app/);
    assert.match(row.textContent, /Taken off a payment made outside the app/);
    assert.match(row.textContent, /Olive Owner/);
    await click(buttons(row, 'Void')[0]);
    assert.equal(dialog(host).querySelector('h3').textContent, 'Void settlement');
    assert.match(dialog(host).textContent, /owes S\$555\.27 back again, recovered from their later commission/);
    assert.match(dialog(host).textContent, /settled 09\/10\/2026/);
    await click(buttons(dialog(host), 'Void settlement')[0]);
    assert.match(dialog(host).querySelector('[role=alert]').textContent, /A reason is required to void a settlement\./);
    assert.equal(calls.filter(c => c.name === 'void_affiliate_deduction_settlement').length, 0);
    await type(dialog(host).querySelector('textarea'), 'Recorded against the wrong affiliate');
    await click(buttons(dialog(host), 'Void settlement')[0]);
    const sent = calls.filter(c => c.name === 'void_affiliate_deduction_settlement');
    assert.equal(sent.length, 1);
    assert.deepEqual({ ...sent[0].args, p_request_id: typeof sent[0].args.p_request_id },
      { p_settlement_id: 'set-1', p_reason: 'Recorded against the wrong affiliate', p_request_id: 'string' });
    assert.match(host.textContent, /Settlement voided: Alpha Affiliate owes S\$555\.27 back again/);
    const after = [...host.querySelector('[data-testid="settlement-history"]').querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('Alpha Affiliate'));
    assert.match(after.textContent, /Voided/);
    assert.match(after.textContent, /by Max Manager: Recorded against the wrong affiliate/);
    assert.equal(buttons(after, 'Void').length, 0, 'a voided settlement cannot be voided again');
  } finally { await done(); }
});

test('an Admin reads the page but gets neither Mark as settled nor Void', async () => {
  backend(owing());
  let r = await render('earned', false);
  try {
    assert.match(r.host.textContent, /Affiliate owes S\$555\.27 back/);
    assert.equal(buttons(r.host, 'Mark as settled').length, 0);
  } finally { await r.done(); }
  backend(settled());
  r = await render('payouts', false);
  try {
    assert.match(r.host.querySelector('[data-testid="settlement-history"]').textContent, /Paid off outside the app/);
    assert.equal(buttons(r.host, 'Void').length, 0);
  } finally { await r.done(); }
});

test('against a database without 414 the page works as before (no settlements sent)', async () => {
  const o = owing(); delete o.settlements; o.groups = o.groups.map(g => { const { settled: _, ...rest } = g; return rest; });
  backend(o);
  const r = await render('payouts');
  try {
    assert.match(r.host.textContent, /No deductions marked as settled with a date settled in this range\./);
  } finally { await r.done(); }
});

test('a lost answer survives a reload: the dialog comes back and the retry sends the same request', async () => {
  let n = 0;
  backend(owing(), { record_affiliate_deduction_settlement: () => (++n === 1
    ? { data: null, error: { message: 'Failed to fetch' } }
    : { data: { id: 'set-1', amount: 100, settled_on: '2026-10-09', method: 'written_off' }, error: null }) });
  let r = await render('earned');
  try {
    await click(buttons(r.host, 'Mark as settled')[0]);
    await click(dialog(r.host).querySelectorAll('input[type=radio]')[1]);
    await type(field(r.host, 'Amount'), '100');
    await type(field(r.host, 'Date it was settled'), '2026-10-09');
    await type(field(r.host, 'Note'), 'Written off by the Owner');
    await click(buttons(dialog(r.host), 'Mark as settled')[0]);
    assert.match(dialog(r.host).textContent, /The result is unconfirmed: Failed to fetch\./);
    assert.ok(sessionStorage.getItem('energia-affiliate-settlement-pending:owner'), 'kept for this tab');
  } finally { await r.done(); }
  // The tab is reloaded: the page mounts again.
  r = await render('earned');
  try {
    assert.ok(dialog(r.host), 'the dialog comes back');
    assert.match(dialog(r.host).querySelector('[role=alert]').textContent, /A previous save has an unconfirmed result\. Retry the same save/);
    assert.equal(field(r.host, 'Amount').value, '100');
    assert.equal(field(r.host, 'Note').value, 'Written off by the Owner');
    assert.equal(buttons(dialog(r.host), 'Cancel')[0].disabled, true, 'it is not dropped until the answer is known');
    await click(buttons(dialog(r.host), 'Retry same save')[0]);
    const sent = calls.filter(c => c.name === 'record_affiliate_deduction_settlement');
    assert.equal(sent.length, 2);
    assert.equal(sent[1].args.p_request_id, sent[0].args.p_request_id, 'the retry after the reload sends the first request id');
    assert.equal(dialog(r.host), null);
    assert.equal(sessionStorage.getItem('energia-affiliate-settlement-pending:owner'), null);
  } finally { await r.done(); }
});

test('a Void whose answer was lost comes back after a reload too; a refusal is not kept', async () => {
  let n = 0;
  backend(settled(), { void_affiliate_deduction_settlement: args => (++n === 1
    ? { data: null, error: { message: 'Failed to fetch' } }
    : { data: null, error: { code: 'P0001', message: 'This settlement was already voided. Refresh the payouts.' } }) });
  let r = await render('payouts');
  try {
    const row = [...r.host.querySelector('[data-testid="settlement-history"]').querySelectorAll('tbody tr')].find(tr => tr.textContent.includes('Alpha Affiliate'));
    await click(buttons(row, 'Void')[0]);
    await type(dialog(r.host).querySelector('textarea'), 'Recorded twice');
    await click(buttons(dialog(r.host), 'Void settlement')[0]);
    assert.match(dialog(r.host).textContent, /The result is unconfirmed/);
  } finally { await r.done(); }
  r = await render('payouts');
  try {
    assert.equal(dialog(r.host)?.querySelector('h3').textContent, 'Void settlement');
    assert.equal(dialog(r.host).querySelector('textarea').value, 'Recorded twice');
    await click(buttons(dialog(r.host), 'Retry same void')[0]);
    const sent = calls.filter(c => c.name === 'void_affiliate_deduction_settlement');
    assert.equal(sent[1].args.p_request_id, sent[0].args.p_request_id);
    assert.match(dialog(r.host).querySelector('[role=alert]').textContent, /already voided/);
    assert.equal(sessionStorage.getItem('energia-affiliate-settlement-pending:owner'), null, 'a definite answer is not kept');
  } finally { await r.done(); }
});

test('the balances export carries settled, so earned + adjustments - paid + settled = balance', async () => {
  backend(settled());
  const r = await render('earned');
  try {
    globalThis.__exports = [];
    await click(buttons(r.host, 'Export Excel')[0] ?? [...r.host.querySelectorAll('button')].find(b => b.textContent.includes('Export Excel')));
    const sheet = globalThis.__exports.at(-1)?.sheet;
    assert.ok(sheet, 'exported');
    assert.deepEqual(sheet.ws.header.slice(3, 8), ['earned', 'adjustments', 'paid', 'settled', 'balance']);
    const sep = sheet.ws.body.find(x => x['Affiliate ID'] === 'ref-a' && x.Month === '2026-09-01');
    assert.deepEqual([sep.earned, sep.adjustments, sep.paid, sep.settled, sep.balance], [1705.59, -991.64, 1276.3, 555.27, -7.08]);
    for (const x of sheet.ws.body) {
      assert.equal(Math.round((x.earned + x.adjustments - x.paid + x.settled) * 100), Math.round(x.balance * 100), `${x['Affiliate ID']} ${x.Month} adds up`);
    }
  } finally { await r.done(); }
});
