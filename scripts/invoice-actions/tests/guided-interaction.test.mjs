// The guided flow driven as a person drives it: real React, real DOM events,
// real state transitions.
//
// The Supabase client is stubbed because no local backend can be started here
// (see GUIDED_REFUND_CANCEL.md, "Environment limitation"); the DATABASE
// behaviour these calls reach is covered by the SQL suites. What is tested here
// is the half those cannot reach: what the person sees, what they are stopped
// from doing, and what they are told afterwards.
import { JSDOM } from 'jsdom';
import { build } from 'esbuild';
import assert from 'node:assert/strict';

const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>',
  { url: 'https://tests.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'Element', 'Node', 'Event',
                 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame',
                 'cancelAnimationFrame']) {
  // Node 25 defines some of these as getter-only on globalThis.
  try { globalThis[k] = dom.window[k]; }
  catch { Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true }); }
}
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
if (!globalThis.crypto?.randomUUID) {
  globalThis.crypto = { ...(globalThis.crypto ?? {}), randomUUID: () => 'req-' + Math.random().toString(16).slice(2) };
}

// ---- the stub, and a record of everything the component asked the server ----
const calls = [];
let planNow;
const stub = {
  // The invoice's special sales and rentals (393) are read by invoice; the
  // warehouses are the active ones, by name.
  from: table => ({ select: () => ({ eq: () => (table === 'special_sales' || table === 'rentals')
    ? Promise.resolve({ data: stub.waiting[table] ?? [], error: null })
    : ({ is: () => ({ order: () => Promise.resolve({ data: [
    { id: 'wh-1', name: 'Main Warehouse' }, { id: 'wh-2', name: 'Overflow Warehouse' }] }) }) }) }) }),
  waiting: {},
  rpc: (name, args) => {
    calls.push({ name, args });
    if (name === 'invoice_action_plan') {
      // 417: a plan that cannot be worked out (AFTER-15).
      if (stub.planError && stub.planError(args)) return Promise.resolve({ data: null, error: { message: stub.planError(args) } });
      return Promise.resolve({ data: planNow(args), error: null });
    }
    if (name === 'invoice_action_request_detail') return Promise.resolve({ data: stub.detail, error: null });
    if (name === 'invoice_rentals_awaiting_return') return Promise.resolve({ data: stub.awaiting ?? [], error: null });
    if (name === 'invoice_request_status') return Promise.resolve({ data: stub.requestStatus ?? null, error: null });
    if (name === 'receive_returned_rental') return Promise.resolve({ data: stub.receiveResult ?? { returned_quantity: 1, location_name: 'Fixture Store' }, error: null });
    if (name === 'request_invoice_action_v2') return Promise.resolve({ data: { request_id: stub.nextRequest ?? 'REQ-1' }, error: null });
    if (name === 'resolve_invoice_action_v2') {
      // 417: approvals that fail, one after another, then the result.
      if (args.p_approve && stub.resolveErrors?.length) return Promise.resolve({ data: null, error: { message: stub.resolveErrors.shift() } });
      if (!args.p_approve && stub.rejectResult) return Promise.resolve({ data: stub.rejectResult, error: null });
      return Promise.resolve({ data: stub.resolveResult, error: null });
    }
    return Promise.resolve({ data: null, error: null });
  },
  resolveResult: null,
};

const basePlan = (over = {}) => ({
  invoice_no: 'INV-2026-0207', action: 'refund_full', refund_amount: 200, refund_due: 0,
  window: { created_on: '2026-09-12', deadline: '2026-09-16', within: true, days_remaining: 4,
            override_required: false, creation_reliable: true },
  lines: [{ invoice_item_id: 'L1', name: 'Pet Corset', line_kind: 'product', quantity: 2,
            selected_quantity: 2, amount: 200 }],
  stock: [{ movement_id: 'M1', product_name: 'Pet Corset', store_name: 'Adelphi', outstanding: 2, proposed_sellable: 2 }],
  sources: [{ payment_id: 'P1', method: 'PayNow', wallet: false, amount: 200 }],
  overrides_required: [], blockers: [], summary: ['Refund S$200.00.', 'Return 2 x Pet Corset to Adelphi, once the condition is confirmed.'],
  requires_override: false, blocked: false, plan_hash: 'HASH-A', status: 'paid',
  effects: {
    money_returned: { total: 200, destinations: [{ payment_id: 'P1', method: 'PayNow', wallet: false, amount: 200 }] },
    benefits: [], stock_returned: [{ movement_id: 'M1', product_name: 'Pet Corset', store_name: 'Adelphi', outstanding: 2, proposed_sellable: 2 }],
    overrides: [],
  },
  ...over,
});

const built = await build({
  stdin: {
    contents: `
      export { InvoiceGuidedAction } from './src/components/invoices/InvoiceGuidedAction';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react-dom/test-utils';
      export { default as React } from 'react';`,
    resolveDir: process.cwd(), loader: 'ts',
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic',
  // The dialog imports its own stylesheet; a static render has no use for it.
  loader: { '.css': 'empty' },
  define: { 'process.env.NODE_ENV': '"development"' },
  plugins: [{ name: 'stub', setup(b) {
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'stub', namespace: 'st' }));
    b.onLoad({ filter: /.*/, namespace: 'st' }, () => ({
      contents: 'export const supabase = globalThis.__supabase;', loader: 'js' }));
  } }],
});
globalThis.__supabase = stub;
const mod = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { InvoiceGuidedAction, createRoot, act, React } = mod;

const root = createRoot(document.getElementById('root'));
const flush = async () => { await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
// Each scenario gets a fresh component: a finished flow keeps its "done"
// screen, exactly as it would for a person who has not reopened the dialog.
let scenario = 0;
const render = async props => {
  scenario += 1;
  await act(async () => {
    root.render(React.createElement(InvoiceGuidedAction, {
      key: `scenario-${scenario}`,
      invoiceId: 'INV-1', canApprove: false, onDone: async () => {}, onClose: () => {}, ...props }));
  });
  await flush();
};
const text = () => document.body.textContent;
const byText = (tag, s) => Array.from(document.querySelectorAll(tag)).find(e => e.textContent.includes(s));
const click = async el => { await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await flush(); };
// React tracks the last value it wrote, so setting .value directly is ignored.
// Going through the element's OWN prototype setter is what makes it notice.
const type = async (el, value) => {
  const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value').set;
  await act(async () => { setter.call(el, value); el.dispatchEvent(new dom.window.Event('input', { bubbles: true })); });
  await flush();
};
const choose = async (el, value) => {
  const setter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value').set;
  await act(async () => { setter.call(el, value); el.dispatchEvent(new dom.window.Event('change', { bubbles: true })); });
  await flush();
};

let failures = 0;
const check = (name, cond, detail) => {
  if (cond) console.log(`  ok   ${name}`);
  else { failures++; console.log(`  FAIL ${name}${detail ? ' — ' + detail : ''}`); }
};

// ---------------------------------------------------------------------
// A staff member raising a partial refund.
// ---------------------------------------------------------------------
planNow = () => basePlan();
await render({ canApprove: false });
check('opens on the choice of what happened', text().includes('Partial refund'));

await click(byText('button', 'Partial refund'));
check('asks which items next', text().includes('Which items are coming back?'));
const qty = document.querySelector('.invoice-guided-lines input');
check('cannot continue without choosing a quantity', byText('button', 'Continue').disabled);
await type(qty, '1');
check('continue opens once a quantity is set', !byText('button', 'Continue').disabled);
check('quantity is capped at what was sold', Number(qty.max) === 2);

planNow = () => basePlan({ action: 'refund_partial', refund_amount: 100,
  lines: [{ invoice_item_id: 'L1', name: 'Pet Corset', line_kind: 'product', quantity: 2, selected_quantity: 1, amount: 100 }],
  summary: ['Refund S$100.00.'],
  effects: { money_returned: { total: 100, destinations: [{ payment_id: 'P1', method: 'PayNow', wallet: false, amount: 100 }] },
             benefits: [{ kind: 'paid', holder: 'Jenny Lim', credit_removed: 50, accounting_value: 47.62, line: 'Credit Package' }],
             stock_returned: [{ movement_id: 'M1', product_name: 'Pet Corset', store_name: 'Adelphi', outstanding: 2, proposed_sellable: 1 }],
             therapy_closed: [
               { entitlement_no: 'UTP-0000042', package: '3 months - Unlimited', used: false, benefit: 'unlimited', line: 'Bundle A' },
               { entitlement_no: 'UTP-0000043', package: 'Choice', used: false, benefit: 'voucher', line: 'Bundle B' },
               { entitlement_no: 'UTP-0000044', package: '6 months - Unlimited', used: true, benefit: 'unlimited', line: 'Bundle C' }],
             overrides: [] } });
await click(byText('button', 'Continue'));
check('asks for a reason', text().includes('Reason'));
check('review is refused without a reason', byText('button', 'Continue').disabled);
await type(document.querySelector('.invoice-guided-why textarea'), 'Customer returned one');
await click(byText('button', 'Continue'));
check('shows the money returned as its own section', text().includes('Money returned'));
check('and the figure', text().includes('S$100.00'));
check('credits are a separate section from the money',
  text().includes('Credits and benefits cancelled'));
check('reporting the credit actually removed, not the accounting share',
  text().includes('S$50.00 of paid credit') && !text().includes('S$47.62 of paid credit'));
check('naming who holds it', text().includes('Jenny Lim'));
check('stock is its own section', text().includes('Stock returned') && text().includes('Adelphi'));
// 363: therapy a promotion granted is named, and a used unit says it needs the override.
check('therapy closed is its own section', text().includes('Therapy closed') && text().includes('UTP-0000042'));
check('an unused unit says so', /UTP-0000042[^]*not used yet/.test(text()));
check('uncollected vouchers are said to be withdrawn', /UTP-0000043[^]*vouchers not yet collected are withdrawn/.test(text()));
check('a used unit ends only with the override', /UTP-0000044[^]*has been used[^]*override/.test(text()));
check('names the payment destination', text().includes('PayNow'));
check('and does not imply money is sent automatically',
  text().includes('does not send money anywhere'));
check('a person who cannot approve gets a request label', text().includes('Submit refund request'));
check('and is told nothing changes until then', text().includes('Nothing changes until they approve'));
await click(byText('button', 'Submit refund request'));
check('submitting says plainly that nothing has moved yet',
  text().includes('Nothing has changed') && text().includes('no money has moved'));
check('it sent the quantities the person chose',
  JSON.stringify(calls.find(c => c.name === 'request_invoice_action_v2')?.args.p_lines) === '[{"invoice_item_id":"L1","quantity":1}]');

// ---------------------------------------------------------------------
// An approver meeting a plan that changed under them.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = () => basePlan();
stub.resolveResult = { confirmation_required: true, revised_plan: basePlan({ refund_amount: 100, plan_hash: 'HASH-B',
  summary: ['Refund S$100.00.'],
  effects: { money_returned: { total: 100, destinations: [{ payment_id: 'P1', method: 'PayNow', wallet: false, amount: 100 }] },
             benefits: [], stock_returned: [], overrides: [] } }), requested_plan: basePlan() };
await render({ canApprove: true });
await click(byText('button', 'Full refund'));
await type(document.querySelector('.invoice-guided-why textarea'), 'All back');
await click(byText('button', 'Continue'));
check('an approver sees the amount in the button', text().includes('Confirm S$200.00 refund'));
await click(byText('button', 'Confirm S$200.00 refund'));
check('a changed plan is explained rather than silently applied', text().includes('has changed since the request was raised'));
check('and the revised figure is shown', text().includes('S$100.00'));
check('nothing is reported as done', !text().includes('Refund of S$200.00 recorded'));

// The second confirmation carries the REVISED hash, not the stale one.
stub.resolveResult = { status: 'approved', refund_recorded: true, refunded_amount: 100,
  cancellation: null, refund: { refunded_amount: 100 }, goods_returned: 0, refund_still_due: 0 };
await click(byText('button', 'Confirm S$100.00 refund'));
const second = calls.filter(c => c.name === 'resolve_invoice_action_v2').at(-1);
check('the retry confirms the revised plan by its own hash', second?.args.p_plan_hash === 'HASH-B', second?.args.p_plan_hash);
check('and reports the amount the server actually refunded', text().includes('Refund of S$100.00 recorded.'));

// ---------------------------------------------------------------------
// Cancelling with the money still to go back.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = () => basePlan({ action: 'cancel', refund_amount: 0, refund_due: 200,
  summary: ['Cancel INV-2026-0207 and clear what is still owed.'],
  effects: { money_returned: { total: 0, destinations: [] }, benefits: [], stock_returned: [], overrides: [] } });
stub.resolveResult = { status: 'approved', refund_recorded: false, refunded_amount: 0,
  cancellation: { success: true }, refund: null, goods_returned: 1, refund_still_due: 200 };
await render({ canApprove: true });
await click(byText('button', 'Cancel invoice'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Customer pulled out');
await click(byText('button', 'Continue'));
check('offers the money-actually-returned choice', text().includes('has actually gone back to the customer now'));
check('a cancellation with no rental says nothing about rented items', !text().includes('A rented item still with the customer'));
check('and defaults to NOT claiming the money moved',
  document.querySelector('.invoice-guided-refunddue input').checked === false);
check('cancellation without money uses a cancellation label', !!byText('button', 'Confirm cancellation'));
await click(byText('button', 'Confirm cancellation'));
check('reports the cancellation', text().includes('Invoice cancelled.'));
check('does not claim a refund that was not recorded', !text().includes('Refund of'));
check('and keeps the follow-up visible', text().includes('S$200.00 is still due back'));

// ---------------------------------------------------------------------
// 363: two lines whose therapy has been used, each with its own override.
// ---------------------------------------------------------------------
calls.length = 0;
const therapyOverride = (id, name) => ({ code: 'therapy_activated', amount_required: true, default_amount: 0, invoice_item_id: id,
  message: `Therapy from ${name} has been started or has ended (UTP-${id}). An Owner or Manager must state the refund amount.` });
planNow = () => basePlan({ action: 'cancel', refund_amount: 0, refund_due: 0,
  lines: [{ invoice_item_id: 'LA', name: 'Bundle A', line_kind: 'promotion', quantity: 1, selected_quantity: 1, amount: 0 },
          { invoice_item_id: 'LB', name: 'Bundle B', line_kind: 'promotion', quantity: 1, selected_quantity: 1, amount: 0 }],
  stock: [], sources: [],
  overrides_required: [therapyOverride('LA', 'Bundle A'), therapyOverride('LB', 'Bundle B')], requires_override: true,
  summary: ['Cancel INV-2026-0207 and clear what is still owed.'],
  effects: { money_returned: { total: 0, destinations: [] }, benefits: [], stock_returned: [], overrides: [],
             therapy_closed: [{ entitlement_no: 'UTP-A', package: '3 months', used: true, line: 'Bundle A' },
                              { entitlement_no: 'UTP-B', package: 'Choice', used: true, line: 'Bundle B' }],
             therapy_left: [{ entitlement_no: 'UTP-OLD', package: '6 months', line: 'no invoice line' }] } });
stub.resolveResult = { status: 'approved', refund_recorded: false, refunded_amount: 0,
  cancellation: { success: true }, refund: null, goods_returned: 0, refund_still_due: 0 };
await render({ canApprove: true });
await click(byText('button', 'Cancel invoice'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Customer withdrew');
await click(byText('button', 'Continue'));
check('therapy left running is shown to the approver', text().includes('Therapy left running') && text().includes('UTP-OLD'));
check('two lines needing the same override are not sent back one at a time', !text().includes('one at a time'));
const field = label => document.querySelector(`input[aria-label="${label}"]`);
check('each line has its own reason and amount',
  !!field('Reason for override: therapy_activated (Bundle A)') && !!field('Reason for override: therapy_activated (Bundle B)')
  && !!field('Amount for override: therapy_activated (Bundle A)') && !!field('Amount for override: therapy_activated (Bundle B)'));
await type(field('Reason for override: therapy_activated (Bundle A)'), 'A month used');
await type(field('Amount for override: therapy_activated (Bundle A)'), '100');
await type(field('Reason for override: therapy_activated (Bundle B)'), 'One facial collected');
await type(field('Amount for override: therapy_activated (Bundle B)'), '50');
await click(byText('button', 'Confirm cancellation'));
const sent = calls.find(c => c.name === 'resolve_invoice_action_v2')?.args.p_overrides ?? [];
check('each override is sent with its own line, reason and amount',
  JSON.stringify(sent) === JSON.stringify([
    { code: 'therapy_activated', reason: 'A month used', amount: 100, invoice_item_id: 'LA' },
    { code: 'therapy_activated', reason: 'One facial collected', amount: 50, invoice_item_id: 'LB' }]),
  JSON.stringify(sent));

// ---------------------------------------------------------------------
// 363: a reason-only override still needs its reason, and a cancellation
// that records its refund states the amount the approver gave.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = () => basePlan({ action: 'cancel', refund_amount: 0, refund_due: 610,
  lines: [{ invoice_item_id: 'LV', name: 'Voucher Bundle', line_kind: 'promotion', quantity: 1, selected_quantity: 1, amount: 500 },
          { invoice_item_id: 'LP', name: 'Therapy Bundle', line_kind: 'promotion', quantity: 1, selected_quantity: 1, amount: 110 }],
  stock: [], sources: [{ payment_id: 'P1', method: 'PayNow', wallet: false, amount: 610 }],
  overrides_required: [
    { code: 'therapy_activated', amount_required: false, default_amount: 500, invoice_item_id: 'LV', message: 'Therapy from Voucher Bundle has been started. The refund for this line is the value of its unused vouchers or credit, as shown above; an Owner or Manager must give a reason.' },
    { code: 'therapy_activated', amount_required: true, default_amount: 110, invoice_item_id: 'LP', message: 'Therapy from Therapy Bundle has been started. An Owner or Manager must state the refund amount.' }],
  requires_override: true, summary: ['Cancel INV-2026-0207 and clear what is still owed.'],
  effects: { money_returned: { total: 0, destinations: [] }, benefits: [], stock_returned: [], overrides: [] } });
stub.resolveResult = { status: 'approved', refund_recorded: true, refunded_amount: 600, cancellation: { success: true }, refund: {}, goods_returned: 0, refund_still_due: 0 };
await render({ canApprove: true });
await click(byText('button', 'Cancel invoice'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Customer withdrew');
await click(byText('button', 'Continue'));
await type(field('Reason for override: therapy_activated (Therapy Bundle)'), 'A month used');
await type(field('Amount for override: therapy_activated (Therapy Bundle)'), '100');
check('a reason-only override without its reason keeps Confirm disabled',
  byText('button', 'Confirm cancellation')?.disabled === true && text().includes('Give a reason for each override.'));
await type(field('Reason for override: therapy_activated (Voucher Bundle)'), 'Vouchers unused');
check('once every reason is given Confirm is enabled', byText('button', 'Confirm cancellation')?.disabled === false);
check('a cancellation compares the stated figure with the refund due, not with 0',
  text().includes('Refund stated by override: S$600.00') && text().includes('the plan above shows S$610.00'));
await click(document.querySelector('.invoice-guided-refunddue input'));
check('recording the refund names the amount that will be refunded', !!byText('button', 'Confirm cancellation and S$600.00 refund'));

// ---------------------------------------------------------------------
// Layout, and abandoning a half-filled form.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = () => basePlan();
let closed = 0;
await render({ canApprove: true, onClose: () => { closed += 1; } });
check('header, scrolling body and footer are separate',
  !!document.querySelector('.invoice-guided-head')
  && !!document.querySelector('.invoice-guided-body')
  && !!document.querySelector('.invoice-guided-foot'));
check('the confirming action lives in the footer, not the scrolling body',
  !document.querySelector('.invoice-guided-body .invoice-guided-foot'));
// The number belongs in the title, once. It used to appear again in the
// subtitle, which is what the reported screenshot showed.
check('the invoice number appears exactly once',
  (document.querySelector('.invoice-guided').textContent.match(/INV-2026-0207/g) || []).length === 1);
check('and it is in the title', document.querySelector('#ga-title').textContent.includes('INV-2026-0207'));
check('with status and a readable date beneath it',
  /paid/i.test(document.querySelector('.invoice-guided-status').textContent)
  && /Created \d{1,2} \w{3} \d{4}/.test(document.querySelector('.invoice-guided-status').textContent));
check('the dialog does not inherit the other chooser\u2019s rules',
  !document.querySelector('.invoice-guided').classList.contains('invoice-chooser'));
check('action descriptions are short enough not to overrun their card',
  Array.from(document.querySelectorAll('.invoice-guided-choices .btn span'))
    .every(s2 => s2.textContent.trim().length <= 70),
  Array.from(document.querySelectorAll('.invoice-guided-choices .btn span')).map(s2=>s2.textContent.trim().length).join(','));
check('the four steps are labelled',
  ['Action', 'Items', 'Reason', 'Review'].every(l => text().includes(l)));

// Nothing typed yet: closing is immediate.
let confirmed = 0;
dom.window.confirm = () => { confirmed += 1; return true; };
globalThis.confirm = dom.window.confirm;
await click(document.querySelector('.invoice-guided-close'));
check('closing an untouched form asks nothing', confirmed === 0 && closed === 1);

// Something typed: the project's confirm() guards it.
await render({ canApprove: true, onClose: () => { closed += 1; } });
await click(byText('button', 'Full refund'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Half-written reason');
await click(document.querySelector('.invoice-guided-close'));
check('abandoning typed input asks first', confirmed === 1, String(confirmed));
check('and closes when confirmed', closed === 2, String(closed));

// ---------------------------------------------------------------------
// The action saved, but reloading the invoice failed.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = () => basePlan();
stub.resolveResult = { status: 'approved', refund_recorded: true, refunded_amount: 200,
  cancellation: null, refund: { refunded_amount: 200 }, goods_returned: 0, refund_still_due: 0 };
let refreshAttempts = 0;
let refreshWorks = false;
await render({ canApprove: true, onDone: async () => {
  refreshAttempts += 1;
  if (!refreshWorks) throw new Error('network');
} });
await click(byText('button', 'Full refund'));
await type(document.querySelector('.invoice-guided-why textarea'), 'All back');
await click(byText('button', 'Continue'));
await click(byText('button', 'Confirm S$200.00 refund'));
check('a failed reload still reports the refund as recorded', text().includes('Refund of S$200.00 recorded.'));
check('and says plainly that it was saved', text().includes('This was saved'));
check('and warns the figures behind may be out of date', text().includes('may be out of date'));
check('and promises the retry does not repeat the refund', text().includes('does not repeat the refund'));
check('the refresh was attempted once', refreshAttempts === 1, String(refreshAttempts));

const beforeRetry = calls.filter(c => c.name === 'resolve_invoice_action_v2').length;
refreshWorks = true;
await click(byText('button', 'Reload the invoice'));
check('retrying re-reads only — it does not resubmit',
  calls.filter(c => c.name === 'resolve_invoice_action_v2').length === beforeRetry,
  `${beforeRetry} -> ${calls.filter(c => c.name === 'resolve_invoice_action_v2').length}`);
check('a successful retry clears the warning', !text().includes('This was saved'));
check('and the outcome is still shown', text().includes('Refund of S$200.00 recorded.'));
const beforeDoneClose = confirmed;
await click(byText('button', 'Close'));
check('closing a finished success message asks nothing', confirmed === beforeDoneClose);

// ---------------------------------------------------------------------
// 393: a partial refund asks about each machine still waiting for a
// warehouse; the answer goes with the request and the approver sees it.
// ---------------------------------------------------------------------
calls.length = 0;
stub.waiting = { special_sales: [
  { id: 'SPS-A', sale_no: 'SPS-2026-0010', status: 'pending', warehouse_id: null, source_store_id: null,
    invoice_item_id: 'L2', special_products: { name: 'Fixture Chair' } },
  { id: 'SPS-B', sale_no: 'SPS-2026-0011', status: 'completed', warehouse_id: 'wh-1', source_store_id: null,
    invoice_item_id: 'L2', special_products: { name: 'Fixture Chair' } }], rentals: [] };
const chairLines = [
  { invoice_item_id: 'L1', name: 'Pet Corset', line_kind: 'product', quantity: 2, selected_quantity: 2, amount: 200 },
  { invoice_item_id: 'L2', name: 'Massage Chair', line_kind: 'special_product', quantity: 1, selected_quantity: 1, amount: 900 }];
planNow = () => basePlan({ lines: chairLines });
await render({ canApprove: false });
await click(byText('button', 'Partial refund'));
check('a partial refund asks about the waiting machine, by its invoice line',
  text().includes('Is the customer still taking this item?') && text().includes('Massage Chair · SPS-2026-0010'));
check('a released machine is not asked about', !text().includes('SPS-2026-0011'));
check('nothing is chosen for the person',
  Array.from(document.querySelectorAll('input[name="waiting-SPS-A"]')).every(r => !r.checked));
await type(document.querySelector('.invoice-guided-lines input'), '1');
check('continuing waits for the answer, and says so',
  byText('button', 'Continue').disabled && text().includes('Answer for each item waiting for a warehouse'));
await click(document.querySelectorAll('input[name="waiting-SPS-A"]')[1]);
check('"No" is an answer', !byText('button', 'Continue').disabled);
planNow = () => basePlan({ action: 'refund_partial', refund_amount: 100,
  lines: [{ invoice_item_id: 'L1', name: 'Pet Corset', line_kind: 'product', quantity: 2, selected_quantity: 1, amount: 100 }] });
await click(byText('button', 'Continue'));
await type(document.querySelector('.invoice-guided-why textarea'), 'One corset back; the chair is not wanted');
await click(byText('button', 'Continue'));
check('the review says what happens to the machine',
  text().includes('Massage Chair · SPS-2026-0010: the customer is not taking it, so it is cancelled'));
await click(byText('button', 'Submit refund request'));
check('the answer goes with the request, on its first line',
  JSON.stringify(calls.find(c => c.name === 'request_invoice_action_v2')?.args.p_lines)
    === '[{"invoice_item_id":"L1","quantity":1,"waiting":[{"doc_id":"SPS-A","still_taking":false}]}]',
  JSON.stringify(calls.find(c => c.name === 'request_invoice_action_v2')?.args.p_lines));

// A full refund does not ask: it cancels every waiting machine, and says so.
calls.length = 0;
planNow = () => basePlan({ lines: chairLines });
await render({ canApprove: false });
await click(byText('button', 'Full refund'));
check('a full refund does not ask', !text().includes('Is the customer still taking this item?'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Everything back');
await click(byText('button', 'Continue'));
check('and the review says the waiting machine is cancelled',
  text().includes('A refund of the whole invoice cancels') && text().includes('Massage Chair · SPS-2026-0010'));
await click(byText('button', 'Submit refund request'));
check('and sends no answers', JSON.stringify(calls.find(c => c.name === 'request_invoice_action_v2')?.args.p_lines) === '[]');

// The approver sees the requester's answer.
calls.length = 0;
planNow = () => basePlan({ lines: chairLines });
const oneCorset = basePlan({ action: 'refund_partial', refund_amount: 100,
  lines: [{ invoice_item_id: 'L1', name: 'Pet Corset', line_kind: 'product', quantity: 2, selected_quantity: 1, amount: 100 }] });
stub.detail = { request_id: 'REQ-9', status: 'pending', action: 'refund_partial', reason: 'One corset back',
  requested_by: 'Fixture Staff', store: 'Adelphi', changed: false, legacy: false,
  requested_lines: [{ invoice_item_id: 'L1', quantity: 1, waiting: [{ doc_id: 'SPS-A', still_taking: true }] }],
  requested_plan: oneCorset, current_plan: oneCorset };
await render({ canApprove: true, requestId: 'REQ-9' });
check('the approver sees what the requester answered',
  text().includes('Massage Chair · SPS-2026-0010: the customer is still taking it, so it keeps waiting'));
check('and cannot change it', !document.querySelector('input[name="waiting-SPS-A"]'));

// A "partial" refund of every line in full closes the invoice, which cancels
// every waiting machine whatever was answered: it does not ask, and neither
// review says the machine keeps waiting.
calls.length = 0;
planNow = () => basePlan({ lines: chairLines });
await render({ canApprove: false });
await click(byText('button', 'Partial refund'));
const lineInputs = document.querySelectorAll('.invoice-guided-lines input');
await type(lineInputs[0], '1');
check('one corset of two still asks', text().includes('Is the customer still taking this item?'));
await type(lineInputs[0], '2');
await type(lineInputs[1], '1');
check('every line in full does not ask',
  !text().includes('Is the customer still taking this item?') && text().includes('Every line goes back in full'));
check('and continues without an answer', !byText('button', 'Continue').disabled);
planNow = () => basePlan({ action: 'refund_partial', refund_amount: 1100, lines: chairLines });
await click(byText('button', 'Continue'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Everything back after all');
await click(byText('button', 'Continue'));
check('the review says the refund closes the invoice and cancels the machine',
  text().includes('closes the invoice and cancels every item still waiting') && text().includes('Massage Chair · SPS-2026-0010')
  && !text().includes('keeps waiting'));
await click(byText('button', 'Submit refund request'));
check('and sends no answers',
  JSON.stringify(calls.find(c => c.name === 'request_invoice_action_v2')?.args.p_lines)
    === '[{"invoice_item_id":"L1","quantity":2},{"invoice_item_id":"L2","quantity":1}]',
  JSON.stringify(calls.find(c => c.name === 'request_invoice_action_v2')?.args.p_lines));

// The approver of such a request, answered "still taking", is told the truth.
calls.length = 0;
planNow = () => basePlan({ lines: chairLines });
stub.detail = { ...stub.detail, request_id: 'REQ-10',
  requested_lines: [{ invoice_item_id: 'L1', quantity: 2, waiting: [{ doc_id: 'SPS-A', still_taking: true }] },
                    { invoice_item_id: 'L2', quantity: 1 }],
  requested_plan: basePlan({ action: 'refund_partial', refund_amount: 1100, lines: chairLines }),
  current_plan: basePlan({ action: 'refund_partial', refund_amount: 1100, lines: chairLines }) };
await render({ canApprove: true, requestId: 'REQ-10' });
check('an approver of a refund that closes the invoice is not told the machine keeps waiting',
  !text().includes('keeps waiting') && text().includes('closes the invoice and cancels every item still waiting')
  && text().includes('whatever was answered'));
stub.waiting = {};

// ---------------------------------------------------------------------
// 409: a request raised the old way (no plan) can only be rejected, and
// rejecting it puts the invoice back to the status its payments show; the
// approver is told so. A guided request's rejection still changes nothing.
// ---------------------------------------------------------------------
calls.length = 0;
stub.detail = { request_id: 'REQ-OLD', status: 'pending', action: null, reason: 'Customer changed their mind',
  requested_by: 'Fixture Staff', store: 'Adelphi', legacy: true, invoice_status: 'refund_requested',
  legacy_note: 'This request predates the guided workflow.', requested_lines: [], requested_plan: null, current_plan: null };
stub.resolveResult = { request_id: 'REQ-OLD', status: 'rejected', invoice_status_restored: 'paid' };
await render({ canApprove: true, requestId: 'REQ-OLD' });
check('an old-style request says it cannot be approved', text().includes('cannot be approved as it stands'));
check('and that rejecting it puts the invoice back', text().includes('Rejecting it puts the invoice back to the status its payments show')
  && text().includes('refund requested'));
check('it offers no approval', !byText('button', 'Confirm'));
await type(document.querySelector('.invoice-guided-block textarea'), 'Outside our refund terms');
await click(Array.from(document.querySelectorAll('.invoice-guided-block button')).find(b => b.textContent === 'Reject'));
check('rejecting sends a rejection, nothing else',
  calls.filter(c => c.name === 'resolve_invoice_action_v2').length === 1
  && calls.find(c => c.name === 'resolve_invoice_action_v2').args.p_approve === false
  && !calls.some(c => c.name === 'request_invoice_action' || c.name === 'refund_invoice_recorded'));
check('the approver is told the invoice is back to paid', text().includes('The invoice is back to paid, as its payments show'),
  text().slice(0, 300));

calls.length = 0;
stub.detail = { request_id: 'REQ-NEW', status: 'pending', action: 'refund_full', reason: 'Customer returned it',
  requested_by: 'Fixture Staff', store: 'Adelphi', legacy: false, invoice_status: 'paid', changed: false,
  requested_lines: [], requested_amount: 200, requested_plan: basePlan(), current_plan: basePlan() };
stub.resolveResult = { request_id: 'REQ-NEW', status: 'rejected', invoice_status_restored: null };
planNow = () => basePlan();
await render({ canApprove: true, requestId: 'REQ-NEW' });
check('a guided request has no restore note', !text().includes('Rejecting it puts the invoice back'));
await click(byText('button', 'Reject'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Not this time');
await click(byText('button', 'Confirm rejection'));
check('and its rejection says nothing on the invoice changed', text().includes('Nothing on the invoice has changed')
  && !text().includes('is back to'));
stub.resolveResult = null;

// 409: staff open this on an unpaid invoice too. With nothing held there is
// nothing to refund (a refund request could never be approved): only the
// cancellation is offered, and it is sent as a request.
calls.length = 0;
planNow = args => basePlan({ action: args.p_action, refund_amount: 0, refund_due: 0, sources: [], stock: [],
  status: 'unpaid', effects: { money_returned: { total: 0, destinations: [] }, benefits: [], stock_returned: [], overrides: [] } });
await render({ canApprove: false });
check('nothing held: Full and Partial refund are not offered',
  byText('button', 'Full refund')?.disabled === true && byText('button', 'Partial refund')?.disabled === true
  && text().includes('Nothing has been paid on this invoice, so it can only be cancelled.'));
check('but the cancellation is', byText('button', 'Cancel invoice')?.disabled === false);
await click(byText('button', 'Cancel invoice'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Customer no longer wants it');
await click(byText('button', 'Continue'));
await click(byText('button', 'Submit cancellation request'));
check('and is sent as a request that an Owner or Manager approves',
  calls.some(c => c.name === 'request_invoice_action_v2' && c.args.p_action === 'cancel')
  && !calls.some(c => c.name === 'resolve_invoice_action_v2' || c.name === 'request_invoice_action'));
// 409 review: money can be held while no line has anything to refund (a
// part-paid bundle that has released nothing, like INV-2026-0317 before it
// was cancelled). The message says what is held, never that nothing is.
calls.length = 0;
planNow = args => basePlan({ action: args.p_action, refund_amount: 0, refund_due: 0, net_held: 1000, sources: [], stock: [],
  status: 'partially_paid', effects: { money_returned: { total: 0, destinations: [] }, benefits: [], stock_returned: [], overrides: [] } });
await render({ canApprove: true });
check('money held but nothing refundable: still only cancellation, and the message says what is held',
  byText('button', 'Full refund')?.disabled === true && byText('button', 'Partial refund')?.disabled === true
  && text().includes('No item on this invoice can be refunded, so it can only be cancelled. It holds S$1000.00 of payments.')
  && !text().includes('Nothing has been paid'));

// ---------------------------------------------------------------------
// 417 (AFTER-15): a plan that cannot be worked out keeps the step and says
// why; no earlier plan is reviewed under the new choice.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = args => basePlan({ action: args.p_action });
stub.planError = args => args.p_action === 'cancel' ? 'Fixture: the plan could not be worked out' : null;
await render({ canApprove: true });
await click(byText('button', 'Cancel invoice'));
check('a failed plan keeps the action step', text().includes('Partial refund') && !text().includes('What happened, in a sentence'));
check('and shows why', text().includes('Fixture: the plan could not be worked out'));
await click(byText('button', 'Partial refund'));
await type(document.querySelector('.invoice-guided-lines input'), '1');
stub.planError = args => args.p_action === 'refund_partial' ? 'Fixture: partial plan refused' : null;
await click(byText('button', 'Continue'));
check('a failed partial plan keeps the items step', text().includes('Which items are coming back?') && text().includes('Fixture: partial plan refused'));
check('and the items are still listed from the full plan', !!document.querySelector('.invoice-guided-lines input'));
stub.planError = null;

// ---------------------------------------------------------------------
// 417 (AFTER-M2): an approval that failed, then a different choice. The
// request this window raised is withdrawn first, with a reason, and the new
// one goes under a new request ID. The label and the refund tick follow the
// plan on screen.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = args => args.p_action === 'cancel'
  ? basePlan({ action: 'cancel', refund_amount: 0, refund_due: 200, plan_hash: 'HASH-C',
      effects: { money_returned: { total: 0, destinations: [] }, benefits: [], stock_returned: [], overrides: [] } })
  : basePlan({ action: args.p_action });
stub.resolveErrors = ['Fixture: approval refused'];
stub.rejectResult = { status: 'rejected' };
stub.resolveResult = { status: 'approved', refund_recorded: false, refunded_amount: 0, cancellation: { success: true }, refund: null,
  goods_returned: 0, refund_still_due: 200 };
await render({ canApprove: true });
await click(byText('button', 'Full refund'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Customer changed their mind');
await click(byText('button', 'Continue'));
await click(byText('button', 'Confirm S$200.00 refund'));
check('a failed approval is shown', text().includes('Fixture: approval refused'));
const firstReq = calls.find(c => c.name === 'request_invoice_action_v2');
await click(byText('button', 'Back'));
await click(byText('button', 'Back'));
await click(byText('button', 'Cancel invoice'));
await click(byText('button', 'Continue'));
check('the label follows the plan on screen', !!byText('button', 'Confirm cancellation'));
check('the refund tick is offered for the cancellation', !!document.querySelector('.invoice-guided-refunddue input'));
stub.nextRequest = 'REQ-2';
await click(byText('button', 'Confirm cancellation'));
const rejects = calls.filter(c => c.name === 'resolve_invoice_action_v2' && c.args.p_approve === false);
check('the first request is withdrawn before the new one is raised',
  rejects.length === 1 && rejects[0].args.p_request_id === 'REQ-1' && /Replaced by a different choice/.test(rejects[0].args.p_note),
  JSON.stringify(rejects));
const reqs = calls.filter(c => c.name === 'request_invoice_action_v2');
check('the new request goes under a new request ID',
  reqs.length === 2 && reqs[1].args.p_action === 'cancel' && reqs[1].args.p_request_id !== firstReq.args.p_request_id);
check('and its approval is of the new request', calls.filter(c => c.name === 'resolve_invoice_action_v2' && c.args.p_approve).at(-1)?.args.p_request_id === 'REQ-2');
check('the cancellation is reported', text().includes('Invoice cancelled.'));
stub.nextRequest = null; stub.rejectResult = null;

// The same choice again is the same request: nothing is withdrawn.
calls.length = 0;
stub.resolveErrors = ['Fixture: approval refused'];
stub.resolveResult = { status: 'approved', refund_recorded: true, refunded_amount: 200, cancellation: null, refund: {}, goods_returned: 0, refund_still_due: 0 };
planNow = args => basePlan({ action: args.p_action });
await render({ canApprove: true });
await click(byText('button', 'Full refund'));
await type(document.querySelector('.invoice-guided-why textarea'), 'All back');
await click(byText('button', 'Continue'));
await click(byText('button', 'Confirm S$200.00 refund'));
await click(byText('button', 'Confirm S$200.00 refund'));
const sameReqs = calls.filter(c => c.name === 'request_invoice_action_v2');
check('a retry of the same choice sends the same request ID and withdraws nothing',
  sameReqs.length === 2 && sameReqs[0].args.p_request_id === sameReqs[1].args.p_request_id
  && !calls.some(c => c.name === 'resolve_invoice_action_v2' && c.args.p_approve === false));

// A revised plan for another action is not shown under this choice.
calls.length = 0;
stub.resolveErrors = [];
stub.resolveResult = { confirmation_required: true, revised_plan: basePlan({ action: 'cancel', refund_amount: 0, refund_due: 200 }) };
await render({ canApprove: true });
await click(byText('button', 'Full refund'));
await type(document.querySelector('.invoice-guided-why textarea'), 'All back');
await click(byText('button', 'Continue'));
await click(byText('button', 'Confirm S$200.00 refund'));
check('a revised plan for another action stops and says so',
  text().includes('is for a cancellation, not a full refund') && !!byText('button', 'Confirm S$200.00 refund'));
stub.resolveResult = null;

// ---------------------------------------------------------------------
// 417 (AFTER-M2, AFTER-14): a request already waiting on the invoice.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = args => basePlan({ action: args.p_action });
stub.requestStatus = { invoice_id: 'INV-1', pending: true, can_review: false,
  request: { request_id: 'REQ-W', status: 'pending', action: 'refund_full', requested_by: 'Fixture Staff',
             requested_at: '2026-10-08T16:30:00Z' } };
await render({ canApprove: false });
check('staff are told a request is waiting, since when and by whom',
  text().includes('A full refund request for this invoice is already waiting for approval since 9 Oct 2026 (raised by Fixture Staff)'));
check('and cannot raise a second', ['Cancel invoice', 'Full refund', 'Partial refund'].every(l => byText('button', l)?.disabled));
stub.detail = { request_id: 'REQ-W', status: 'pending', action: 'refund_full', reason: 'Customer returned it',
  requested_by: 'Fixture Staff', store: 'Adelphi', legacy: false, invoice_status: 'paid', changed: false,
  requested_lines: [], requested_amount: 200, requested_plan: basePlan(), current_plan: basePlan() };
await render({ canApprove: true });
check('an Owner or Manager opening it reviews the waiting request',
  calls.some(c => c.name === 'invoice_action_request_detail' && c.args.p_request_id === 'REQ-W')
  && text().includes('asked to') && text().includes('Customer returned it'));
check('the requester\'s reason is shown, not put in the approver\'s note',
  Array.from(document.querySelectorAll('textarea')).every(t => t.value === ''));
await click(byText('button', 'Reject'));
check('a rejection needs the approver\'s own reason', byText('button', 'Confirm rejection')?.disabled === true);
await type(document.querySelector('.invoice-guided-why textarea'), 'Outside the refund terms');
stub.rejectResult = { request_id: 'REQ-W', status: 'rejected', invoice_status_restored: null };
await click(byText('button', 'Confirm rejection'));
const rej = calls.filter(c => c.name === 'resolve_invoice_action_v2').at(-1);
check('and sends that reason', rej?.args.p_approve === false && rej?.args.p_note === 'Outside the refund terms' && rej?.args.p_request_id === 'REQ-W');
check('saying what the invoice will show', text().includes('The invoice shows it was rejected, with your reason'));
stub.rejectResult = null;

// Approving a request with no note of the approver's own sends none.
calls.length = 0;
stub.resolveResult = { status: 'approved', refund_recorded: true, refunded_amount: 200, cancellation: null, refund: {}, goods_returned: 0, refund_still_due: 0 };
await render({ canApprove: true, requestId: 'REQ-W' });
await click(byText('button', 'Confirm S$200.00 refund'));
check('an approval without a note of the approver\'s own sends none (the request\'s reason is kept)',
  calls.find(c => c.name === 'resolve_invoice_action_v2')?.args.p_note === null);
stub.requestStatus = null; stub.detail = null; stub.resolveResult = null;

// ---------------------------------------------------------------------
// 417 (AFTER-M1): a credit package's reward entitlements are shown with the
// credits, and their overrides take a reason, not an amount.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = args => basePlan({ action: args.p_action, refund_amount: 4000,
  lines: [{ invoice_item_id: 'LC', name: 'Fixture Package', line_kind: 'credit_package', quantity: 1, selected_quantity: 1, amount: 4000 }],
  stock: [], overrides_required: [
    { code: 'reward_withdrawal', message: 'Reward entitlements from this credit package that were not claimed yet (LEG-9000001, LEG-9000002) are withdrawn with this refund.' },
    { code: 'reward_consumed_kept', message: 'Reward entitlements from this credit package were already activated or claimed (LEG-9000003). They stay with the customer and keep their history.' }],
  effects: { money_returned: { total: 4000, destinations: [{ payment_id: 'P1', method: 'PayNow', wallet: false, amount: 4000 }] },
             benefits: [], stock_returned: [], overrides: [],
             rewards: { withdrawn: ['LEG-9000001', 'LEG-9000002'], kept: ['LEG-9000003'] } } });
stub.resolveResult = { status: 'approved', refund_recorded: true, refunded_amount: 4000, cancellation: null, refund: {}, goods_returned: 0, refund_still_due: 0 };
await render({ canApprove: true });
await click(byText('button', 'Full refund'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Package returned');
await click(byText('button', 'Continue'));
check('the review names the reward entitlements withdrawn and kept',
  text().includes('Reward entitlements withdrawn: LEG-9000001, LEG-9000002') && text().includes('LEG-9000003'));
check('each takes a reason and no amount',
  !!field('Reason for override: reward_withdrawal') && !!field('Reason for override: reward_consumed_kept')
  && !field('Amount for override: reward_withdrawal'));
await type(field('Reason for override: reward_withdrawal'), 'Package refunded');
await type(field('Reason for override: reward_consumed_kept'), 'The used one stays');
await click(byText('button', 'Confirm S$4000.00 refund'));
check('both reasons go with the approval',
  JSON.stringify(calls.find(c => c.name === 'resolve_invoice_action_v2')?.args.p_overrides) === JSON.stringify([
    { code: 'reward_withdrawal', reason: 'Package refunded' }, { code: 'reward_consumed_kept', reason: 'The used one stays' }]));

// ---------------------------------------------------------------------
// 417 (the Owner's Q2): cancelling a sale the customer already used part of.
// The Owner or Manager states how much is owed back.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = args => basePlan({ action: 'cancel', refund_amount: 0, refund_due: 300, net_held: 500,
  lines: [{ invoice_item_id: 'LS', name: 'Fixture Sessions', line_kind: 'therapy', quantity: 1, selected_quantity: 1, amount: 300 }],
  stock: [], sources: [{ payment_id: 'P1', method: 'PayNow', wallet: false, amount: 300 }],
  overrides_required: [{ code: 'session_used', message: 'Sessions from this purchase have been delivered.' }],
  refund_owed: { needed: true, held: 500, used: ['session_used'], message: 'Part of what this invoice sold has been used, so not all of the S$500.00 it holds is owed back. State how much is owed back to the customer. The rest is kept for what was used.' },
  effects: { money_returned: { total: 0, destinations: [] }, benefits: [], stock_returned: [], overrides: [] } });
stub.resolveResult = { status: 'approved', refund_recorded: false, refunded_amount: 0, cancellation: { success: true }, refund: null,
  goods_returned: 0, refund_still_due: 250, refund_owed: 250 };
await render({ canApprove: true });
await click(byText('button', 'Cancel invoice'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Customer stopped after two sessions');
await click(byText('button', 'Continue'));
const owed = () => document.querySelector('input[aria-label="Amount owed back to the customer"]');
check('the amount owed back is asked for, starting at the reviewed figure', owed() && Number(owed().value) === 300, owed()?.value);
check('saying why not all the money is owed back', text().includes('not all of the S$500.00 it holds is owed back'));
await type(field('Reason for override: session_used'), 'Two sessions given');
await type(owed(), '600');
check('never more than the invoice holds', byText('button', 'Confirm cancellation')?.disabled === true && text().includes('more than the S$500.00'));
await type(owed(), '250');
check('the refund due shows the amount stated', text().includes('S$250.00'));
await click(byText('button', 'Confirm cancellation'));
check('the amount owed back goes with the approval',
  JSON.stringify(calls.find(c => c.name === 'resolve_invoice_action_v2')?.args.p_overrides?.find(o => o.code === 'refund_owed'))
    === JSON.stringify({ code: 'refund_owed', amount: 250, reason: 'Customer stopped after two sessions' }));
check('and the follow-up names it', text().includes('S$250.00 is still due back'));
// Ticking "the money has gone back" records the refund now: no amount owed is asked.
await render({ canApprove: true });
await click(byText('button', 'Cancel invoice'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Paid back now');
await click(byText('button', 'Continue'));
await click(document.querySelector('.invoice-guided-refunddue input'));
check('with the money paid back now, no amount owed is asked', !owed());

// ---------------------------------------------------------------------
// 417 (AFTER-7): a rental still with the customer after the cancellation is
// received on the next screen, only when it is back. Nothing is chosen.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = args => basePlan({ action: args.p_action, refund_amount: 0, refund_due: 0, sources: [], stock: [],
  lines: [{ invoice_item_id: 'LR', name: 'Fixture Machine Rental', line_kind: 'rental', quantity: 1, selected_quantity: 1, amount: 0 }],
  effects: { money_returned: { total: 0, destinations: [] }, benefits: [], stock_returned: [], overrides: [] } });
stub.awaiting = [
  { rental_id: 'R1', rental_no: 'RNT-2026-9101', quantity: 1, item: 'Fixture Machine', invoice_item_id: 'LR', source_type: 'store', source_name: 'Fixture Store' },
  { rental_id: 'R2', rental_no: 'RNT-2026-9102', quantity: 1, item: 'Fixture Chair', invoice_item_id: 'LR', source_type: 'warehouse', source_name: 'Main Warehouse' }];
stub.resolveResult = { status: 'approved', refund_recorded: false, refunded_amount: 0, cancellation: { success: true }, refund: null, goods_returned: 0, refund_still_due: 0 };
await render({ canApprove: true });
check('nothing about rentals is read before the action is approved', !calls.some(c => c.name === 'invoice_rentals_awaiting_return'));
await click(byText('button', 'Cancel invoice'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Customer cancelled the rental');
await click(byText('button', 'Continue'));
check('a cancellation with a rental line says a rented item stays out until it comes back',
  text().includes('A rented item still with the customer stays out until it comes back'));
await click(byText('button', 'Confirm cancellation'));
check('after the cancellation the rentals still out are read again', calls.some(c => c.name === 'invoice_rentals_awaiting_return'));
const outcome = no => document.querySelector(`select[aria-label="What happened to ${no}"]`);
check('each starts as "Not back yet"', outcome('RNT-2026-9101')?.value === '' && outcome('RNT-2026-9102')?.value === '');
check('nothing can be recorded until one is marked back', byText('button', 'Record what came back')?.disabled === true);
await choose(outcome('RNT-2026-9101'), 'good');
const home = document.querySelector('select[aria-label="Where RNT-2026-9101 goes back to"]');
check('a good item goes back where it came from by default, named', home?.value === '' && home?.options[0].textContent.includes('Fixture Store'));
await click(byText('button', 'Record what came back'));
const recv = calls.filter(c => c.name === 'receive_returned_rental');
check('only the item marked back is recorded, to where it came from',
  recv.length === 1 && recv[0].args.p_rental_id === 'R1' && recv[0].args.p_warehouse_id === null && recv[0].args.p_condition === 'good'
  && recv[0].args.p_reason === 'Customer cancelled the rental' && recv[0].args.p_request_id === 'REQ-1', JSON.stringify(recv));
check('what happened is said', text().includes('RNT-2026-9101 is back in good condition and on sale again at Fixture Store'));
check('the other stays listed as not back yet', !!outcome('RNT-2026-9102') && !outcome('RNT-2026-9101'));
check('each receive choice has a row of its own, so the choice can be read',
  !!outcome('RNT-2026-9102')?.closest('.invoice-guided-receive-row'));
// A partial refund receives only the rentals on the lines it covered.
calls.length = 0;
stub.awaiting = [
  { rental_id: 'R3', rental_no: 'RNT-2026-9103', quantity: 1, item: 'Fixture Machine', invoice_item_id: 'L-OTHER', source_type: 'store', source_name: 'Fixture Store' }];
planNow = args => basePlan({ action: args.p_action });
stub.resolveResult = { status: 'approved', refund_recorded: true, refunded_amount: 200, cancellation: null, refund: {}, goods_returned: 0, refund_still_due: 0 };
await render({ canApprove: true });
await click(byText('button', 'Full refund'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Corset back');
await click(byText('button', 'Continue'));
await click(byText('button', 'Confirm S$200.00 refund'));
check('a refund of another line offers no rental to receive', !outcome('RNT-2026-9103'));
stub.awaiting = null; stub.resolveResult = null;

// ---------------------------------------------------------------------
// A blocked invoice offers nothing to click.
// ---------------------------------------------------------------------
planNow = () => basePlan({ blocked: true,
  blockers: [{ code: 'voucher_evidence_review', message: 'Sold vouchers need original issuance evidence.' }] });
await render({ canApprove: true });
check('a blocked invoice explains why', text().includes('needs review first'));
check('and refuses every action', ['Cancel invoice', 'Full refund', 'Partial refund']
  .every(l => byText('button', l)?.disabled));
// 436 (the owner, 21 Oct 2026): a VIP whose voucher kind was given as a
// discount on a later invoice is not refunded in full automatically. The plan
// carries an Owner's or Manager's override instead of a blocker: staff can
// only ask, and an approver must give a reason, which goes to the server.
const vipLater = { code: 'vip_voucher_used_later', invoice_no: 'INV-LATER',
  message: 'A discount with the $72 discount Voucher was given to Ann on INV-LATER, an invoice made after this VIP invoice (INV-1), so the VIP ticket is not refunded in full automatically. An Owner or Manager may allow the full refund, giving a reason (it is recorded).' };
planNow = args => basePlan({ action: args.p_action, stock: [], overrides_required: [vipLater], requires_override: true,
  summary: ['Refund S$200.00.', `Owner/Manager override required: ${vipLater.message}`],
  effects: { money_returned: { total: 200, destinations: [{ payment_id: 'P1', method: 'PayNow', wallet: false, amount: 200 }] },
             benefits: [], stock_returned: [], overrides: [vipLater] } });
calls.length = 0;
await render({ canApprove: false });
check('a VIP refund that needs the override is not blocked: staff can ask for it',
  byText('button', 'Full refund')?.disabled === false && !text().includes('Every action is unavailable'));
await click(byText('button', 'Full refund'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Cannot come');
await click(byText('button', 'Continue'));
check('staff see the override with what it does, give no reason for it, and are told an Owner or Manager decides',
  text().includes(vipLater.message) && !field('Reason for override: vip_voucher_used_later')
  && text().includes('This will be sent to an Owner or Manager'));
await click(byText('button', 'Submit refund request'));
check('and their request is sent for approval, never approved by them',
  calls.some(c => c.name === 'request_invoice_action_v2' && c.args.p_action === 'refund_full')
  && !calls.some(c => c.name === 'resolve_invoice_action_v2'));
calls.length = 0;
stub.resolveResult = { status: 'approved', refund_recorded: true, refunded_amount: 200, refund: {}, cancellation: null,
  goods_returned: 0, refund_still_due: 0 };
await render({ canApprove: true });
await click(byText('button', 'Full refund'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Cannot come');
await click(byText('button', 'Continue'));
check('an Owner or Manager is asked for the override\'s reason, and cannot confirm without it',
  !!field('Reason for override: vip_voucher_used_later')
  && byText('button', 'Confirm S$200.00 refund')?.disabled === true && text().includes('Give a reason for each override.'));
await type(field('Reason for override: vip_voucher_used_later'), 'The SAVE72 on INV-LATER was a separate offer');
await click(byText('button', 'Confirm S$200.00 refund'));
const vipSent = calls.find(c => c.name === 'resolve_invoice_action_v2')?.args.p_overrides ?? [];
check('with it, the approval carries the reason for the override',
  JSON.stringify(vipSent) === JSON.stringify([{ code: 'vip_voucher_used_later', reason: 'The SAVE72 on INV-LATER was a separate offer' }]),
  JSON.stringify(vipSent));

console.log(failures === 0
  ? '\nPASS: the guided flow steps, validates, submits what was chosen, refuses a changed plan until it is confirmed by its own hash, reports only what the server actually did, and offers nothing on a blocked invoice'
  : `\nFAILED: ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);
