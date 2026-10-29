// 478: the Reopen dialog shows, as its own line, the credit the reopening
// itself gives at once for a Credit Package or Premium Bundle paid in part
// ("Credit released at once on reopening"), beside the credit to reinstate
// after settlement; the explanation (the server's) says when each comes back
// (474's NOT COVERED 2; the Owner, 27 Oct 2026). And (the Owner's answer E,
// 27 Oct 2026, "Dialogs name the receiver"): a Premium Bundle's vouchers the
// reopening gives at once, the credit the payment that settles the invoice
// gives (the paid credit not yet released, and the Bonus), and a note naming
// whoever receives any of it when that is not the invoice's customer. And
// (answer E as the Owner ticked it, "plus the vouchers and extra credit the
// payment will give"): the vouchers the settling payment gives (a bundle's,
// chosen at the till or to choose later, and a Credit Package's reward
// units), a Credit Package's reward units given at once, and the same note.
//
// Driven here with real React and DOM events against a stubbed Supabase
// client: the Finance panel opened in its Reopen mode, as the invoice page
// opens it, with the preview the server returns; and the words themselves
// (src/lib/invoices/reopenReceivers.mjs) on their own. What the server works
// out is covered by scripts/invoices/tests/reopen-dialog-credit-released-478.sql.
// Fixtures only: every name and amount is made up.
import { JSDOM } from 'jsdom';
import { build, stop } from 'esbuild';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { reopenVoucherLine, reopenRewardUnitsLine, settlingPaymentLine, settlingVouchersLine, reopenReceiverNotes } from '../../../src/lib/invoices/reopenReceivers.mjs';

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>',
  { url: 'https://tests.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'Element', 'Node', 'Event',
                 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame',
                 'cancelAnimationFrame']) {
  try { globalThis[k] = dom.window[k]; }
  catch { Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true }); }
}
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
if (!globalThis.crypto?.randomUUID) {
  globalThis.crypto = { ...(globalThis.crypto ?? {}), randomUUID: () => 'req-' + Math.random().toString(16).slice(2) };
}

const calls = [];
const stub = {
  preview: null,
  from: () => {
    const q = { select: () => q, eq: () => q, is: () => q,
      order: () => Promise.resolve({ data: [], error: null }),
      then: (res, rej) => Promise.resolve({ data: [], error: null }).then(res, rej) };
    return q;
  },
  rpc: (name, args) => {
    calls.push({ name, args });
    if (name === 'invoice_refund_options') return Promise.resolve({ data: {
      financial: { status: 'cancelled', total: 100, net_received: 40, outstanding: 0, refund_due: 0, refunded: 0 },
      sources: [], benefits: [], stock: [], lines: [], review_required: false }, error: null });
    if (name === 'invoice_reopen_preview') return Promise.resolve({ data: stub.preview, error: null });
    if (name === 'invoice_rentals_awaiting_return') return Promise.resolve({ data: [], error: null });
    if (name === 'reopen_invoice') return Promise.resolve({ data: { success: true }, error: null });
    return Promise.resolve({ data: null, error: null });
  },
};

const built = await build({
  stdin: {
    contents: `
      export { InvoiceFinancePanel } from './src/components/invoices/InvoiceFinancePanel';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react-dom/test-utils';
      export { default as React } from 'react';`,
    resolveDir: process.cwd(), loader: 'ts',
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic',
  loader: { '.css': 'empty' },
  define: { 'process.env.NODE_ENV': '"development"' },
  plugins: [{ name: 'stub', setup(b) {
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'stub', namespace: 'st' }));
    b.onLoad({ filter: /.*/, namespace: 'st' }, () => ({
      contents: 'export const supabase = globalThis.__supabase;', loader: 'js' }));
  } }],
});
// esbuild's service would keep the process alive once the tests are done.
await stop();
globalThis.__supabase = stub;
const { InvoiceFinancePanel, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const root = createRoot(document.getElementById('root'));
const flush = async () => { for (let i = 0; i < 3; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
let scenario = 0;
const render = async () => {
  scenario += 1;
  await act(async () => {
    root.render(React.createElement(InvoiceFinancePanel, {
      key: `s-${scenario}`, invoiceId: 'INV-1', canManage: true, payments: [], methods: [],
      requestedMode: 'reopen', onRequestHandled: () => {}, onChanged: async () => {} }));
  });
  await flush();
};
// The dialog's lines, in order (each a <p> of the form).
const lines = () => Array.from(document.querySelectorAll('.form-grid p')).map(p => p.textContent);
const notes = () => Array.from(document.querySelectorAll('[data-testid="reopen-receiver-note"]')).map(p => p.textContent);

// The server's words (478's preview): 474's, with 478's sentence where the
// reopening gives credit at once.
const EXPL_474 = 'Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. Previously revoked credit is reinstated once the reopened invoice is fully settled.';
const EXPL_478 = 'Existing refunds remain recorded. Only net unrefunded payments settle the reopened invoice. Package or bundle credit the net payments already pay for is released at once when the invoice is reopened. Previously revoked credit is reinstated once the reopened invoice is fully settled.';
const SETTLING = 'Credit the settling payment gives (package or bundle paid credit not yet released, and the Bonus): ';
const SETTLING_V = 'Vouchers the settling payment gives: ';
const REWARD_AT_ONCE = 'Credit Package reward units given at once on reopening: ';
const receiver = (id, name, own, over = {}) => ({ customer_id: id, customer_name: name, invoice_customer: own,
  credit_released_on_reopen: 0, bundle_vouchers_given_on_reopen: 0, bundle_vouchers_to_choose_on_reopen: 0,
  reward_units_given_on_reopen: 0, credit_from_settling_payment: 0, bundle_vouchers_from_settling_payment: 0,
  bundle_vouchers_to_choose_from_settling_payment: 0, reward_units_from_settling_payment: 0,
  credit_to_reinstate_after_settlement: 0, ...over });
// 478's preview: 474's keys and 478's (nothing given unless a test says so).
const preview = over => ({ can_reopen: true, blockers: [], total: 100, net_received: 40,
  voucher_units_to_reinstate_after_settlement: 0, credit_to_reinstate_after_settlement: 0,
  sessions_to_reinstate_after_settlement: 0, stock_to_issue: [], explanation: EXPL_474,
  credit_released_on_reopen: 0, bundle_vouchers_given_on_reopen: 0, bundle_vouchers_to_choose_on_reopen: 0,
  reward_units_given_on_reopen: 0, credit_from_settling_payment: 0, bundle_vouchers_from_settling_payment: 0,
  bundle_vouchers_to_choose_from_settling_payment: 0, reward_units_from_settling_payment: 0, credit_receivers: [], ...over });

test('PT0: a package paid in part shows what the reopening gives at once, beside what comes after settlement, and what the settling payment gives', async () => {
  calls.length = 0;
  stub.preview = preview({ credit_released_on_reopen: 20, credit_from_settling_payment: 60, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', true, { credit_released_on_reopen: 20, credit_from_settling_payment: 60 })] });
  await render();
  assert.ok(calls.some(c => c.name === 'invoice_reopen_preview' && c.args.p_invoice_id === 'INV-1'), 'the dialog reads the preview');
  const l = lines();
  assert.equal(l[0], EXPL_478, 'the explanation, the server\'s, says when each comes back');
  assert.ok(l.includes('Invoice total: S$100.00 · Net payments: S$40.00 · Payment required to settle again: S$60.00'));
  const atOnce = l.indexOf('Credit released at once on reopening: S$20.00');
  const after = l.indexOf('Revoked credit to reinstate after settlement: S$0.00');
  assert.ok(atOnce > 0, 'the credit given at once has its own line: ' + JSON.stringify(l));
  assert.equal(after, atOnce + 1, 'just above the credit to reinstate after settlement (no bundle vouchers here)');
  assert.equal(l[after + 1], SETTLING + 'S$60.00', 'what the settling payment gives, just below');
  assert.ok(l.includes('Voucher units to replace after settlement: 0'));
  assert.ok(!l.some(t => t.startsWith('Bundle vouchers')), 'no bundle voucher line');
  assert.ok(!l.some(t => t.startsWith(SETTLING_V) || t.startsWith(REWARD_AT_ONCE)), 'no voucher or reward unit line: a package that gives none');
  assert.deepEqual(notes(), [], 'everything goes to the invoice\'s customer: no note');
});

test('both figures (a package settled before beside one paid in part, AL)', async () => {
  stub.preview = preview({ total: 200, net_received: 140, credit_released_on_reopen: 40, credit_to_reinstate_after_settlement: 60,
    credit_from_settling_payment: 60, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', true, { credit_released_on_reopen: 40, credit_from_settling_payment: 60, credit_to_reinstate_after_settlement: 60 })] });
  await render();
  const l = lines();
  assert.ok(l.includes('Credit released at once on reopening: S$40.00'));
  assert.ok(l.includes('Revoked credit to reinstate after settlement: S$60.00'));
  assert.ok(l.includes(SETTLING + 'S$60.00'));
  assert.ok(l.includes('Invoice total: S$200.00 · Net payments: S$140.00 · Payment required to settle again: S$60.00'));
  assert.deepEqual(notes(), []);
});

test('nothing given at once, nothing from the settling payment: no new line, the dialog as it was', async () => {
  for (const figure of [0, undefined, null]) {
    stub.preview = preview({ credit_released_on_reopen: figure, credit_to_reinstate_after_settlement: 60,
      bundle_vouchers_given_on_reopen: figure, bundle_vouchers_to_choose_on_reopen: figure, credit_from_settling_payment: figure,
      reward_units_given_on_reopen: figure, bundle_vouchers_from_settling_payment: figure,
      bundle_vouchers_to_choose_from_settling_payment: figure, reward_units_from_settling_payment: figure,
      credit_receivers: figure === 0 ? [receiver('cust-a', 'Ada Fixture', true, { credit_to_reinstate_after_settlement: 60 })] : figure });
    await render();
    const l = lines();
    assert.ok(!l.some(t => t.startsWith('Credit released at once') || t.startsWith('Bundle vouchers') || t.startsWith('Credit the settling payment')
                          || t.startsWith(SETTLING_V) || t.startsWith(REWARD_AT_ONCE)),
      'no new line for ' + figure + ': ' + JSON.stringify(l));
    assert.equal(l[0], EXPL_474);
    assert.ok(l.includes('Revoked credit to reinstate after settlement: S$60.00'));
    assert.deepEqual(notes(), []);
  }
});

test('before 478 (the preview has none of its keys): the dialog as 474 showed it', async () => {
  stub.preview = { can_reopen: true, blockers: [], total: 100, net_received: 40, voucher_units_to_reinstate_after_settlement: 0,
    credit_to_reinstate_after_settlement: 0, sessions_to_reinstate_after_settlement: 0, stock_to_issue: [], explanation: EXPL_474 };
  await render();
  assert.deepEqual(lines(), [EXPL_474, 'Invoice total: S$100.00 · Net payments: S$40.00 · Payment required to settle again: S$60.00',
    'Voucher units to replace after settlement: 0', 'Revoked credit to reinstate after settlement: S$0.00']);
});

test('PTk: after a \'keep\' change the buyer receives it all, and a note says so', async () => {
  stub.preview = preview({ credit_released_on_reopen: 20, credit_from_settling_payment: 60, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', false, { credit_released_on_reopen: 20, credit_from_settling_payment: 60 })] });
  await render();
  const l = lines();
  assert.deepEqual(notes(), ['S$20.00 released at once and S$60.00 from the settling payment go to Ada Fixture, who holds the benefits, not to this invoice\'s customer.']);
  assert.equal(l.indexOf(notes()[0]), l.indexOf(SETTLING + 'S$60.00') + 1, 'the note comes just below the credit lines');
  assert.equal(document.querySelector('[data-testid="reopen-receiver-note"]').getAttribute('role'), 'note');
});

test('PTsv: a bundle settled at once by the reopening gives its vouchers then: a line just below the credit given at once', async () => {
  stub.preview = preview({ total: 140, net_received: 140, credit_released_on_reopen: 120, bundle_vouchers_given_on_reopen: 2, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', true, { credit_released_on_reopen: 120, bundle_vouchers_given_on_reopen: 2 })] });
  await render();
  const l = lines();
  const atOnce = l.indexOf('Credit released at once on reopening: S$120.00');
  assert.ok(atOnce > 0);
  assert.equal(l[atOnce + 1], 'Bundle vouchers given at once on reopening: 2');
  assert.equal(l[atOnce + 2], 'Revoked credit to reinstate after settlement: S$0.00');
  assert.ok(!l.some(t => t.startsWith('Credit the settling payment')), 'settled at once: nothing comes from a later payment');
  assert.deepEqual(notes(), []);
});

test('PTsv1 and PTkv: vouchers to choose later; after a \'keep\' change the note names the buyer for them too', async () => {
  stub.preview = preview({ total: 140, net_received: 140, credit_released_on_reopen: 120, bundle_vouchers_given_on_reopen: 1,
    bundle_vouchers_to_choose_on_reopen: 1, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', false, { credit_released_on_reopen: 120, bundle_vouchers_given_on_reopen: 1, bundle_vouchers_to_choose_on_reopen: 1 })] });
  await render();
  assert.ok(lines().includes('Bundle vouchers given at once on reopening: 1 (and 1 more to choose later)'));
  assert.deepEqual(notes(), ['S$120.00 released at once, 1 bundle voucher given at once and 1 bundle voucher to choose later go to Ada Fixture, who holds the benefits, not to this invoice\'s customer.']);
});

test('KALr: two receivers; only the one who is not the invoice\'s customer gets a note', async () => {
  stub.preview = preview({ total: 200, net_received: 140, credit_released_on_reopen: 40, credit_to_reinstate_after_settlement: 80,
    credit_from_settling_payment: 60, explanation: EXPL_478,
    credit_receivers: [receiver('cust-b', 'Bo Fixture', true, { credit_released_on_reopen: 40, credit_from_settling_payment: 60 }),
                       receiver('cust-a', 'Ada Fixture', false, { credit_to_reinstate_after_settlement: 80 })] });
  await render();
  assert.deepEqual(notes(), ['S$80.00 reinstated after settlement goes to Ada Fixture, who holds the benefits, not to this invoice\'s customer.']);
});

test('PTv: a bundle paid in part: the vouchers the settling payment gives, just below the credit it gives', async () => {
  stub.preview = preview({ total: 140, net_received: 40, credit_released_on_reopen: 20, credit_from_settling_payment: 100,
    bundle_vouchers_from_settling_payment: 2, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', true, { credit_released_on_reopen: 20, credit_from_settling_payment: 100,
      bundle_vouchers_from_settling_payment: 2 })] });
  await render();
  const l = lines();
  const settling = l.indexOf(SETTLING + 'S$100.00');
  assert.ok(settling > 0, JSON.stringify(l));
  assert.equal(l[settling + 1], SETTLING_V + '2 bundle vouchers', 'the vouchers the settling payment gives, just below its credit');
  assert.ok(!l.some(t => t.startsWith('Bundle vouchers given at once') || t.startsWith(REWARD_AT_ONCE)), 'nothing given at once but credit');
  assert.deepEqual(notes(), [], 'all of it the invoice\'s customer\'s: no note');
});

test('PTv1 and PTr2p: one voucher to choose later; a Credit Package\'s reward units from the settling payment', async () => {
  stub.preview = preview({ total: 140, net_received: 40, credit_released_on_reopen: 20, credit_from_settling_payment: 100,
    bundle_vouchers_from_settling_payment: 1, bundle_vouchers_to_choose_from_settling_payment: 1, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', true, { credit_released_on_reopen: 20, credit_from_settling_payment: 100,
      bundle_vouchers_from_settling_payment: 1, bundle_vouchers_to_choose_from_settling_payment: 1 })] });
  await render();
  assert.ok(lines().includes(SETTLING_V + '1 bundle voucher (and 1 more to choose later)'), JSON.stringify(lines()));
  stub.preview = preview({ credit_released_on_reopen: 20, credit_from_settling_payment: 60, reward_units_from_settling_payment: 2,
    explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', true, { credit_released_on_reopen: 20, credit_from_settling_payment: 60,
      reward_units_from_settling_payment: 2 })] });
  await render();
  const l = lines();
  assert.equal(l[l.indexOf(SETTLING + 'S$60.00') + 1], SETTLING_V + '2 Credit Package reward units', JSON.stringify(l));
  assert.deepEqual(notes(), []);
});

test('PTr2: a Credit Package settled at once by the reopening gives its reward units then: a line just below the credit given at once', async () => {
  stub.preview = preview({ total: 100, net_received: 100, credit_released_on_reopen: 80, reward_units_given_on_reopen: 2, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', true, { credit_released_on_reopen: 80, reward_units_given_on_reopen: 2 })] });
  await render();
  const l = lines();
  const atOnce = l.indexOf('Credit released at once on reopening: S$80.00');
  assert.ok(atOnce > 0, JSON.stringify(l));
  assert.equal(l[atOnce + 1], REWARD_AT_ONCE + '2');
  assert.equal(l[atOnce + 2], 'Revoked credit to reinstate after settlement: S$0.00');
  assert.ok(!l.some(t => t.startsWith(SETTLING_V) || t.startsWith('Credit the settling payment')), 'settled at once: nothing from a later payment');
  assert.deepEqual(notes(), []);
});

test('PTkvl and PTkr: after a \'keep\' change the note names the buyer for the vouchers and reward units too', async () => {
  stub.preview = preview({ total: 140, net_received: 40, credit_released_on_reopen: 20, credit_from_settling_payment: 100,
    bundle_vouchers_from_settling_payment: 2, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', false, { credit_released_on_reopen: 20, credit_from_settling_payment: 100,
      bundle_vouchers_from_settling_payment: 2 })] });
  await render();
  assert.deepEqual(notes(), ['S$20.00 released at once, S$100.00 from the settling payment and 2 bundle vouchers from the settling payment go to Ada Fixture, who holds the benefits, not to this invoice\'s customer.']);
  const l = lines();
  assert.equal(l.indexOf(notes()[0]), l.indexOf(SETTLING_V + '2 bundle vouchers') + 1, 'the note comes just below the vouchers line');
  stub.preview = preview({ total: 100, net_received: 100, credit_released_on_reopen: 80, reward_units_given_on_reopen: 2, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', false, { credit_released_on_reopen: 80, reward_units_given_on_reopen: 2 })] });
  await render();
  assert.deepEqual(notes(), ['S$80.00 released at once and 2 reward units given at once go to Ada Fixture, who holds the benefits, not to this invoice\'s customer.']);
});

test('KALv: two receivers; the added bundle\'s vouchers are the invoice\'s customer\'s, the first package\'s credit the buyer\'s', async () => {
  stub.preview = preview({ total: 240, net_received: 40, credit_released_on_reopen: 20, credit_from_settling_payment: 200,
    bundle_vouchers_from_settling_payment: 2, explanation: EXPL_478,
    credit_receivers: [receiver('cust-b', 'Bo Fixture', true, { credit_from_settling_payment: 140, bundle_vouchers_from_settling_payment: 2 }),
                       receiver('cust-a', 'Ada Fixture', false, { credit_released_on_reopen: 20, credit_from_settling_payment: 60 })] });
  await render();
  assert.ok(lines().includes(SETTLING_V + '2 bundle vouchers'));
  assert.deepEqual(notes(), ['S$20.00 released at once and S$60.00 from the settling payment go to Ada Fixture, who holds the benefits, not to this invoice\'s customer.']);
});

test('Confirm reopening still sends the reopening alone', async () => {
  calls.length = 0;
  stub.preview = preview({ credit_released_on_reopen: 20, credit_from_settling_payment: 60, explanation: EXPL_478,
    credit_receivers: [receiver('cust-a', 'Ada Fixture', false, { credit_released_on_reopen: 20, credit_from_settling_payment: 60 })] });
  await render();
  const reason = document.querySelector('textarea');
  const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(reason), 'value').set;
  await act(async () => { setter.call(reason, 'Cancelled by mistake'); reason.dispatchEvent(new dom.window.Event('input', { bubbles: true })); });
  await flush();
  const confirm = Array.from(document.querySelectorAll('button')).find(b => b.textContent === 'Confirm reopening');
  assert.equal(confirm?.disabled, false);
  await act(async () => { confirm.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await flush();
  const sent = calls.filter(c => c.name === 'reopen_invoice');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].args.p_invoice_id, 'INV-1');
  assert.equal(sent[0].args.p_reason, 'Cancelled by mistake');
});

test('the words: vouchers, the settling payment and the notes', () => {
  assert.equal(reopenVoucherLine(null), null);
  assert.equal(reopenVoucherLine({}), null);
  assert.equal(reopenVoucherLine({ bundle_vouchers_given_on_reopen: 0, bundle_vouchers_to_choose_on_reopen: 0 }), null);
  assert.equal(reopenVoucherLine({ bundle_vouchers_given_on_reopen: 2 }), 'Bundle vouchers given at once on reopening: 2');
  assert.equal(reopenVoucherLine({ bundle_vouchers_given_on_reopen: 0, bundle_vouchers_to_choose_on_reopen: 2 }),
    'Bundle vouchers given at once on reopening: 0 (2 to choose later)');
  assert.equal(settlingPaymentLine({ credit_from_settling_payment: '70.00' }), SETTLING + 'S$70.00');
  assert.equal(settlingPaymentLine({ credit_from_settling_payment: 0 }), null);
  assert.equal(settlingPaymentLine(undefined), null);
  assert.equal(reopenRewardUnitsLine(null), null);
  assert.equal(reopenRewardUnitsLine({ reward_units_given_on_reopen: 0 }), null);
  assert.equal(reopenRewardUnitsLine({ reward_units_given_on_reopen: 1 }), REWARD_AT_ONCE + '1');
  assert.equal(settlingVouchersLine(undefined), null);
  assert.equal(settlingVouchersLine({}), null, 'before this build the preview has no such keys');
  assert.equal(settlingVouchersLine({ bundle_vouchers_from_settling_payment: 0, bundle_vouchers_to_choose_from_settling_payment: 0,
    reward_units_from_settling_payment: 0 }), null);
  assert.equal(settlingVouchersLine({ bundle_vouchers_from_settling_payment: 1 }), SETTLING_V + '1 bundle voucher');
  assert.equal(settlingVouchersLine({ bundle_vouchers_to_choose_from_settling_payment: 2 }), SETTLING_V + '2 bundle vouchers to choose later');
  assert.equal(settlingVouchersLine({ reward_units_from_settling_payment: 1 }), SETTLING_V + '1 Credit Package reward unit');
  assert.equal(settlingVouchersLine({ bundle_vouchers_from_settling_payment: 2, bundle_vouchers_to_choose_from_settling_payment: 1,
    reward_units_from_settling_payment: 3 }), SETTLING_V + '2 bundle vouchers (and 1 more to choose later) and 3 Credit Package reward units');
  assert.deepEqual(reopenReceiverNotes(undefined), []);
  assert.deepEqual(reopenReceiverNotes({ credit_receivers: null }), []);
  assert.deepEqual(reopenReceiverNotes({ credit_receivers: [receiver('cust-a', 'Ada Fixture', true, { credit_released_on_reopen: 20 })] }), []);
  // Nothing for that customer (a server entry with only zeros): no note.
  assert.deepEqual(reopenReceiverNotes({ credit_receivers: [receiver('cust-a', 'Ada Fixture', false)] }), []);
  assert.deepEqual(reopenReceiverNotes({ credit_receivers: [receiver('cust-f', null, false, { credit_to_reinstate_after_settlement: '80.00' })] }),
    ['S$80.00 reinstated after settlement goes to another customer, who holds the benefits, not to this invoice\'s customer.']);
  assert.deepEqual(reopenReceiverNotes({ credit_receivers: [receiver('cust-a', 'Ada Fixture', false, { bundle_vouchers_given_on_reopen: 2 })] }),
    ['2 bundle vouchers given at once go to Ada Fixture, who holds the benefits, not to this invoice\'s customer.']);
  assert.deepEqual(reopenReceiverNotes({ credit_receivers: [receiver('cust-a', 'Ada Fixture', false, { reward_units_given_on_reopen: 1 })] }),
    ['1 reward unit given at once goes to Ada Fixture, who holds the benefits, not to this invoice\'s customer.']);
  assert.deepEqual(reopenReceiverNotes({ credit_receivers: [receiver('cust-a', 'Ada Fixture', false, { reward_units_from_settling_payment: 2 })] }),
    ['2 reward units from the settling payment go to Ada Fixture, who holds the benefits, not to this invoice\'s customer.']);
  assert.deepEqual(reopenReceiverNotes({ credit_receivers: [receiver('cust-a', 'Ada Fixture', false, { bundle_vouchers_from_settling_payment: 1,
      bundle_vouchers_to_choose_from_settling_payment: 1 })] }),
    ['1 bundle voucher from the settling payment and 1 bundle voucher to choose later from the settling payment go to Ada Fixture, who holds the benefits, not to this invoice\'s customer.']);
  assert.deepEqual(reopenReceiverNotes({ credit_receivers: [
      receiver('cust-a', 'Ada Fixture', false, { credit_released_on_reopen: 20 }),
      receiver('cust-c', 'Cy Fixture', false, { credit_from_settling_payment: 100 })] }),
    ['S$20.00 released at once goes to Ada Fixture, who holds the benefits, not to this invoice\'s customer.',
     'S$100.00 from the settling payment goes to Cy Fixture, who holds the benefits, not to this invoice\'s customer.'],
    'a note each, in the order the server lists them');
});

test('the page reads the keys the server sends, and shows each line only when there is something to show', () => {
  const panel = readFileSync('src/components/invoices/InvoiceFinancePanel.tsx', 'utf8');
  assert.match(panel, /import \{ reopenVoucherLine, reopenRewardUnitsLine, settlingPaymentLine, settlingVouchersLine, reopenReceiverNotes \} from '\.\.\/\.\.\/lib\/invoices\/reopenReceivers\.mjs';/);
  assert.match(panel, /\{Number\(preview\.credit_released_on_reopen \|\| 0\) > 0 && <p>Credit released at once on reopening: \{money\(preview\.credit_released_on_reopen\)\}<\/p>\}\n\s*\{reopenVoucherLine\(preview\) && <p>\{reopenVoucherLine\(preview\)\}<\/p>\}\n\s*\{reopenRewardUnitsLine\(preview\) && <p>\{reopenRewardUnitsLine\(preview\)\}<\/p>\}\n\s*<p>Revoked credit to reinstate after settlement: \{money\(preview\.credit_to_reinstate_after_settlement\)\}<\/p>\n\s*\{settlingPaymentLine\(preview\) && <p>\{settlingPaymentLine\(preview\)\}<\/p>\}\n\s*\{settlingVouchersLine\(preview\) && <p>\{settlingVouchersLine\(preview\)\}<\/p>\}\n\s*\{reopenReceiverNotes\(preview\)\.map\(note => <p role="note" key=\{note\} data-testid="reopen-receiver-note">\{note\}<\/p>\)\}/);
  const mig = readFileSync('supabase/478_reopen_dialog_credit_released_at_once.sql', 'utf8');
  for (const key of ["'credit_released_on_reopen',v478,", "'bundle_vouchers_given_on_reopen',v478v,", "'bundle_vouchers_to_choose_on_reopen',v478a,",
                     "'credit_from_settling_payment',v478s,", "'credit_receivers',v478r,", "'reward_units_given_on_reopen',v478u,",
                     "'bundle_vouchers_from_settling_payment',v478sv,", "'bundle_vouchers_to_choose_from_settling_payment',v478sa,",
                     "'reward_units_from_settling_payment',v478su,"]) {
    assert.ok(mig.includes(key), 'the migration sends ' + key);
  }
  for (const key of ["'customer_id',r.receiver,'customer_name',c.full_name,'invoice_customer',r.receiver=i.customer_id,",
                     "'credit_released_on_reopen',r.at_once,'bundle_vouchers_given_on_reopen',r.vouchers,",
                     "'bundle_vouchers_to_choose_on_reopen',r.allowance,'reward_units_given_on_reopen',r.units,",
                     "'credit_from_settling_payment',r.later,'bundle_vouchers_from_settling_payment',r.later_vouchers,",
                     "'bundle_vouchers_to_choose_from_settling_payment',r.later_allowance,'reward_units_from_settling_payment',r.later_units,",
                     "'credit_to_reinstate_after_settlement',r.back)"]) {
    assert.ok(mig.includes(key), 'each receiver carries ' + key);
  }
  assert.ok(mig.includes("then 'Package or bundle credit the net payments already pay for is released at once when the invoice is reopened. '"),
    'and the sentence this test reads');
});

// Once every test has run: unmount and close the window. React's act, bundled
// here, schedules its work through MessageChannel ports, which would keep the
// process alive (refund-due-panel.test.mjs exits for the same reason): they
// are let go.
test.after(async () => {
  await act(async () => { root.unmount(); });
  dom.window.close();
  for (const h of process._getActiveHandles?.() ?? []) if (h?.constructor?.name === 'MessagePort') h.unref?.();
});
