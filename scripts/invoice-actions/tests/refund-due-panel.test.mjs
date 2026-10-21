// 409: "Record refund paid" — the refund still owed on a cancelled invoice,
// recorded when it has actually gone back.
//
// A cancellation approved without "the money has gone back" ticked left the
// refund due with nowhere to record it (INV-2026-0317, S$1,000 since 25 Sep).
// The invoice footer now opens this form for an Owner or Manager. Driven here
// with real React and DOM events against a stubbed Supabase client; what the
// database does with the call is covered by
// scripts/invoice-actions/tests/refund-requests-and-refund-due.sql.
import { JSDOM } from 'jsdom';
import { build } from 'esbuild';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

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
  options: null, refundError: null, plan: null, awaiting: null, warehouses: [],
  // A query of any shape: awaited, it is empty; ordered, it is the warehouses.
  from: () => {
    const q = { select: () => q, eq: () => q, is: () => q,
      order: () => Promise.resolve({ data: stub.warehouses, error: null }),
      then: (res, rej) => Promise.resolve({ data: [], error: null }).then(res, rej) };
    return q;
  },
  rpc: (name, args) => {
    calls.push({ name, args });
    if (name === 'invoice_refund_options') return Promise.resolve({ data: stub.options, error: null });
    if (name === 'invoice_rentals_awaiting_return') return Promise.resolve({ data: stub.awaiting ?? [], error: null });
    if (name === 'receive_returned_rental') {
      stub.awaiting = (stub.awaiting ?? []).filter(r => r.rental_id !== args.p_rental_id);
      return Promise.resolve({ data: { rental_id: args.p_rental_id, returned_quantity: args.p_condition === 'good' ? 1 : 0,
        location_name: args.p_warehouse_id ? 'Overflow Warehouse' : 'Fixture Store' }, error: null });
    }
    if (name === 'refund_invoice_recorded') return Promise.resolve(stub.refundError
      ? { data: null, error: { message: stub.refundError } } : { data: { success: true, refunded_amount: 1000 }, error: null });
    if (name === 'invoice_action_plan') return Promise.resolve({ data: stub.plan, error: null });
    return Promise.resolve({ data: null, error: null });
  },
};
const cancelledBundle = (over = {}) => ({
  financial: { status: 'cancelled', total: 15000, net_received: 1000, outstanding: 0, refund_due: 1000, refunded: 0,
               overpayment_refundable: 0, ...over },
  sources: [{ payment_id: 'P1', method: 'Bank transfer', wallet: false, remaining: 1000 }],
  benefits: [], stock: [], review_required: false,
  lines: [{ invoice_item_id: 'L1', name: 'Fixture bundle', remaining: 15000, line_kind: 'premium_bundle' }],
});

const built = await build({
  stdin: {
    contents: `
      export { InvoiceFinancePanel, splitRefundDue, paymentDay } from './src/components/invoices/InvoiceFinancePanel';
      export { usedValueCodes, usedValueText } from './src/lib/invoices/business';
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
globalThis.__supabase = stub;
const { InvoiceFinancePanel, splitRefundDue, paymentDay, usedValueCodes, usedValueText, createRoot, act, React } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const root = createRoot(document.getElementById('root'));
const flush = async () => { for (let i = 0; i < 3; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
let scenario = 0; let changed = 0;
const render = async (props = {}) => {
  scenario += 1;
  await act(async () => {
    root.render(React.createElement(InvoiceFinancePanel, {
      key: `s-${scenario}`, invoiceId: 'INV-1', canManage: true, payments: [], methods: [],
      requestedMode: 'refund_due', onRequestHandled: () => {}, onChanged: async () => { changed++; }, ...props }));
  });
  await flush();
};
const text = () => document.body.textContent;
const byText = (tag, s) => Array.from(document.querySelectorAll(tag)).find(e => e.textContent.includes(s));
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await flush(); };
const type = async (el, value) => {
  const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value').set;
  await act(async () => { setter.call(el, value); el.dispatchEvent(new dom.window.Event('input', { bubbles: true })); });
  await flush();
};
const tick = async el => { await act(async () => { el.click(); }); await flush(); };
let failures = 0;
const check = (name, cond, detail) => {
  if (cond) console.log(`  ok   ${name}`);
  else { failures++; console.log(`  FAIL ${name}${detail ? ' — ' + detail : ''}`); }
};
const recordButton = () => Array.from(document.querySelectorAll('button')).find(b => /refund paid$/.test(b.textContent));

// ---- the split -----------------------------------------------------------
assert.deepEqual(splitRefundDue(1000, [{ payment_id: 'P1', remaining: 1000 }]), { P1: 1000 });
assert.deepEqual(splitRefundDue(150.5, [{ payment_id: 'A', remaining: 100 }, { payment_id: 'B', remaining: 80 }]), { A: 100, B: 50.5 });
assert.deepEqual(splitRefundDue(0, [{ payment_id: 'A', remaining: 100 }]), {});
assert.deepEqual(splitRefundDue(50, [{ payment_id: 'A', remaining: 0 }, { payment_id: 'B', remaining: 70 }]), { B: 50 });
check('the refund due is taken from the original payments in order, each up to what it holds', true);

// ---- a cancelled bundle with S$1,000 still held ---------------------------
stub.options = cancelledBundle();
await render();
check('the form opens from the footer as "Record refund paid"', text().includes('Record refund paid'));
check('it says what is owed back and that recording sends nothing',
  text().includes('S$1000.00') && text().includes('recording does not send money anywhere'));
const amount = document.querySelector('input[aria-label^="Bank transfer"]');
check('the original payment is offered, prefilled with what is due', amount && Number(amount.value) === 1000, amount?.value);
check('nothing can be recorded without a reason and the confirmation', recordButton()?.disabled === true);
await type(document.querySelector('textarea'), 'Paid back by bank transfer');
check('still not without the confirmation', recordButton()?.disabled === true);
await tick(byText('label', 'has actually').querySelector('input'));
check('then it can be recorded', recordButton()?.disabled === false, recordButton()?.textContent);
await type(amount, '1000.01');
check('never more than is due', recordButton()?.disabled === true && text().includes('more than the S$1000.00 still due'));
await type(amount, '1000');
await click(recordButton());
const sent = calls.filter(c => c.name === 'refund_invoice_recorded');
check('one call records it', sent.length === 1);
check('as one line without an item, for the amount, against the original payment, with no stock',
  JSON.stringify(sent[0]?.args.p_lines) === '[{"invoice_item_id":null,"amount":1000}]'
  && JSON.stringify(sent[0]?.args.p_sources) === '[{"payment_id":"P1","amount":1000}]'
  && JSON.stringify(sent[0]?.args.p_stock) === '[]'
  && sent[0]?.args.p_reason === 'Paid back by bank transfer' && !!sent[0]?.args.p_request_id,
  JSON.stringify(sent[0]?.args));
check('and the invoice is reloaded', changed === 1);
check('no cancellation, guided request or old request is sent',
  !calls.some(c => ['cancel_invoice_recorded', 'request_invoice_action', 'request_invoice_action_v2'].includes(c.name)));

// ---- a refusal keeps what was entered, and a retry is the same request -----
calls.length = 0;
stub.refundError = 'Amount exceeds the correction refund due';
await render();
await type(document.querySelector('textarea'), 'Paid back');
await tick(byText('label', 'has actually').querySelector('input'));
await click(recordButton());
await click(recordButton());
const tries = calls.filter(c => c.name === 'refund_invoice_recorded');
check('a refusal is shown', text().includes('Amount exceeds the correction refund due'));
check('a retry sends the same request ID, so the server can never record it twice',
  tries.length === 2 && tries[0].args.p_request_id === tries[1].args.p_request_id);

// ---- issued credit: the line-by-line form is offered, prefilled ------------
calls.length = 0;
stub.refundError = 'Allocate a correction refund to the original unused purchased benefits; it cannot be cashed out as an unallocated overpayment';
stub.options = { ...cancelledBundle({ net_received: 240, refund_due: 240 }),
  sources: [{ payment_id: 'P2', method: 'Cash', wallet: false, remaining: 240 }],
  benefits: [{ id: 'B1', invoice_item_id: 'L1', customer_name: 'Fixture Buyer', remaining_value: 0, max_refund: 140, cancelled_unused_value: 140 }],
  lines: [{ invoice_item_id: 'L1', name: 'Fixture bundle', remaining: 140, line_kind: 'premium_bundle' },
          { invoice_item_id: 'L2', name: 'Fixture item', remaining: 100, line_kind: 'product' }] };
stub.plan = { refund_due: 240, lines: [
  { invoice_item_id: 'L1', amount: 140, benefits: [{ benefit_id: 'B1', amount: 140 }] },
  { invoice_item_id: 'L2', amount: 100, benefits: [] }],
  sources: [{ payment_id: 'P2', amount: 240 }] };
await render();
await type(document.querySelector('textarea'), 'Paid back');
await tick(byText('label', 'has actually').querySelector('input'));
await click(recordButton());
const byLine = byText('button', 'Allocate it line by line instead');
check('when the purchase\'s credit was issued, the line-by-line form is offered', !!byLine);
await click(byLine);
check('which is worked out as the cancellation would return it',
  calls.some(c => c.name === 'invoice_action_plan' && c.args.p_action === 'cancel'));
const val = label => Number(document.querySelector(`input[aria-label^="${label}"]`)?.value);
check('prefilled line by line, with the benefit and the payment',
  val('Fixture bundle') === 140 && val('Fixture item') === 100 && val('Fixture Buyer') === 140 && val('Cash') === 240,
  [val('Fixture bundle'), val('Fixture item'), val('Fixture Buyer'), val('Cash')].join(','));

// ---- 409 review: a cancelled invoice whose customer already had part of it --
// The cancellation kept what was used (sessions delivered, therapy started,
// vouchers redeemed, credit spent), so not all the money held is owed back.
assert.deepEqual(usedValueCodes({ overrides_required: [{ code: 'time_window' }, { code: 'session_used' }, { code: 'credit_used' },
  { code: 'session_used' }] }), ['session_used', 'credit_used'], 'only what was used counts, once each; the five-day rule does not');
assert.deepEqual(usedValueCodes(null), []);
assert.deepEqual(usedValueCodes([]), [], 'an unreadable plan names nothing');
assert.equal(usedValueText(['session_used', 'therapy_activated', 'voucher_redeemed', 'credit_used']),
  'sessions delivered, therapy started or its vouchers collected, vouchers redeemed, credit spent');
check('the plan\'s used-value codes are read, and named in plain words', true);
calls.length = 0;
stub.refundError = null;
stub.options = cancelledBundle({ total: 90, net_received: 30, refund_due: 30 });
await render({ requestedMode: null, usedValue: ['session_used'] });
const note = document.querySelector('[data-testid="refund-due-used"]');
check('the finance section says the S$30 held is not all owed back, and why',
  !!note && note.textContent.includes('S$30.00') && note.textContent.includes('sessions delivered')
  && note.textContent.includes('Not all of it is owed back'), note?.textContent);
await render({ requestedMode: 'refund_due', usedValue: ['session_used'] });
const held = document.querySelector('input[aria-label^="Bank transfer"]');
check('and nothing is prefilled as owed back even if the form is opened', !held || !Number(held.value), held?.value);
await render({ requestedMode: null, usedValue: [] });
check('with nothing used there is no such note', !document.querySelector('[data-testid="refund-due-used"]'));
await render({ requestedMode: null, usedValue: ['session_used'], canManage: false });
check('staff do not see it (they cannot record refunds)', !document.querySelector('[data-testid="refund-due-used"]'));
stub.options = cancelledBundle();

// ---- 417 (the Owner's Q2): the amount owed back was stated when cancelling --
// Its refund due is that amount, recorded here like any other; the rest is
// kept for what the customer used.
calls.length = 0;
stub.options = cancelledBundle({ total: 900, net_received: 500, refund_due: 250, refund_owed_stated: true, kept_for_used: 250 });
await render({ requestedMode: null, usedValue: ['session_used'] });
const owedNote = document.querySelector('[data-testid="refund-owed-stated"]');
check('the stated amount owed back is shown, and what is kept for what was used',
  !!owedNote && owedNote.textContent.includes('S$250.00, as stated') && owedNote.textContent.includes('S$250.00 is kept'), owedNote?.textContent);
check('the "not all of it is owed back" refusal is not shown', !document.querySelector('[data-testid="refund-due-used"]'));
const panelRecord = Array.from(document.querySelectorAll('button')).find(b => b.textContent === 'Record refund paid');
check('the panel offers "Record refund paid" itself (the footer leaves this invoice out)', !!panelRecord);
await click(panelRecord);
const owedInput = document.querySelector('input[aria-label^="Bank transfer"]');
check('prefilled with the amount owed back, not all the money held', owedInput && Number(owedInput.value) === 250, owedInput?.value);
await render({ requestedMode: null, usedValue: [] });
check('with nothing used the footer offers it, so the panel does not',
  !Array.from(document.querySelectorAll('button')).some(b => b.textContent === 'Record refund paid'));
stub.options = cancelledBundle();

// ---- 417 (AFTER-7): a rented item still with the customer after the
// cancellation, received from the finance section ----------------------------
calls.length = 0; changed = 0;
stub.options = cancelledBundle({ refund_due: 0, net_received: 0 });
stub.awaiting = [{ rental_id: 'R1', rental_no: 'RNT-2026-9201', quantity: 1, item: 'Fixture Machine', invoice_item_id: 'L1',
  source_type: 'store', source_name: 'Fixture Store' }];
stub.warehouses = [{ id: 'wh-2', name: 'Overflow Warehouse' }];
await render({ requestedMode: null });
check('a cancelled invoice lists the rented item still out, by name and number',
  text().includes('still with the customer after the cancellation: Fixture Machine (RNT-2026-9201)'));
const receiveButton = byText('button', 'Receive RNT-2026-9201');
check('with a "Receive" action, short enough for a phone, that names the item to a screen reader',
  receiveButton?.textContent.trim() === 'Receive RNT-2026-9201'
  && receiveButton?.getAttribute('aria-label') === 'Receive returned item: Fixture Machine (RNT-2026-9201)',
  receiveButton?.outerHTML);
await click(receiveButton);
const outcomeSelect = document.querySelector('select[aria-label="What happened to RNT-2026-9201"]');
check('nothing is chosen for the person', outcomeSelect?.value === '' && byText('button', 'Record what came back')?.disabled === true);
await act(async () => {
  const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(outcomeSelect), 'value').set;
  setter.call(outcomeSelect, 'good'); outcomeSelect.dispatchEvent(new dom.window.Event('change', { bubbles: true }));
});
await flush();
const homeSelect = document.querySelector('select[aria-label="Where RNT-2026-9201 goes back to"]');
check('a good item goes back where it came from by default, named', homeSelect?.value === '' && homeSelect.options[0].textContent.includes('Fixture Store'));
check('or to another active warehouse', Array.from(homeSelect?.options ?? []).some(o => o.textContent === 'Overflow Warehouse'));
check('not without a note', byText('button', 'Record what came back')?.disabled === true);
await type(document.querySelector('textarea'), 'Machine collected from the customer');
await click(byText('button', 'Record what came back'));
const got = calls.filter(c => c.name === 'receive_returned_rental');
check('it is recorded once, to where it came from',
  got.length === 1 && got[0].args.p_rental_id === 'R1' && got[0].args.p_warehouse_id === null && got[0].args.p_condition === 'good'
  && got[0].args.p_reason === 'Machine collected from the customer' && !!got[0].args.p_request_id, JSON.stringify(got[0]?.args));
check('what happened is said, and the item is no longer listed',
  text().includes('RNT-2026-9201 is back in good condition and on sale again at Fixture Store') && !byText('button', 'Receive RNT-'));
check('and the invoice is reloaded', changed === 1);
stub.awaiting = [{ rental_id: 'R2', rental_no: 'RNT-2026-9202', quantity: 1, item: 'Fixture Chair', invoice_item_id: 'L1',
  source_type: 'warehouse', source_name: 'Main Warehouse' }];
await render({ requestedMode: null, canManage: false });
check('staff are not offered it (an Owner or Manager receives)', !byText('button', 'Receive RNT-'));
await render({ requestedMode: null });
check('an Owner or Manager is', byText('button', 'Receive RNT-2026-9202')?.getAttribute('aria-label')
  === 'Receive returned item: Fixture Chair (RNT-2026-9202)');
stub.awaiting = null; stub.options = cancelledBundle();

// ---- 417 (AFTER-16): payment days in Singapore time, never in the future ----
check('a payment at 00:30 in Singapore is that Singapore day, whatever the device\'s zone',
  paymentDay('2026-10-08T16:30:00Z') === '9/10/2026' && paymentDay('2026-10-09') === '9/10/2026' && paymentDay(null) === '', paymentDay('2026-10-08T16:30:00Z'));
const panelSrc = readFileSync('src/components/invoices/InvoiceFinancePanel.tsx', 'utf8');
check('the actual payment date cannot be after today in Singapore',
  /Actual payment date<input type="date" value=\{date\} max=\{singaporeToday\(\)\}/.test(panelSrc)
  && panelSrc.includes("if (mode === 'payment' && date > singaporeToday())") && !panelSrc.includes("toLocaleDateString('en-SG')"));

// ---- the page wires it: Owner/Manager, cancelled or refunded, refund due ---
const page = readFileSync('src/pages/InvoicesPage.tsx', 'utf8');
check('the footer offers it only to an Owner or Manager, on a cancelled or refunded invoice with a refund due',
  /const recordRefundDueButton = detail && canManageInvoice && \['cancelled', 'refunded'\]\.includes\(String\(detail\.status\)\)\s*&& refundStillDue > 0\.005/.test(page)
  && page.includes("setFinanceRequest({ mode: 'refund_due' })") && page.includes('{recordRefundDueButton}{refundCancelButton}'));
check('the dead refund / cancel chooser is gone', !page.includes('InvoiceRefundCancelChooser') && !page.includes('chooserOpen'));
check('and not on a cancelled invoice whose customer had part of it: the page reads the cancellation\'s plan first',
  page.includes("supabase.rpc('invoice_action_plan', { p_invoice_id: inv.id, p_action: 'cancel', p_lines: [] })")
  && page.includes('setDetailUsedValue(error ? [] : usedValueCodes(data as any))')
  && page.includes("&& (String(detail.status) === 'refunded' || (detailUsedValue !== null && detailUsedValue.length === 0))")
  && page.includes('usedValue={detailUsedValue}'));

console.log(failures === 0
  ? '\nPASS: "Record refund paid" offers the original payments prefilled with what is due, records only with a reason and a confirmation, never more than is due, as one line through those payments, retries as the same request, and hands issued credit to the line-by-line form'
  : `\nFAILED: ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);
