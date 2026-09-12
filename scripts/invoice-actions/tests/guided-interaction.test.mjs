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
  from: () => ({ select: () => ({ eq: () => ({ is: () => ({ order: () => Promise.resolve({ data: [
    { id: 'wh-1', name: 'Main Warehouse' }, { id: 'wh-2', name: 'Overflow Warehouse' }] }) }) }) }) }),
  rpc: (name, args) => {
    calls.push({ name, args });
    if (name === 'invoice_action_plan') return Promise.resolve({ data: planNow(args), error: null });
    if (name === 'invoice_rentals_awaiting_return') return Promise.resolve({ data: [], error: null });
    if (name === 'request_invoice_action_v2') return Promise.resolve({ data: { request_id: 'REQ-1' }, error: null });
    if (name === 'resolve_invoice_action_v2') return Promise.resolve({ data: stub.resolveResult, error: null });
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
  requires_override: false, blocked: false, plan_hash: 'HASH-A', ...over,
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
check('opens on the choice of what happened', text().includes('Refund some items'));

await click(byText('button', 'Refund some items'));
check('asks which items next', text().includes('Which items are coming back?'));
const qty = document.querySelector('.invoice-guided-lines input');
check('cannot continue without choosing a quantity', byText('button', 'Continue').disabled);
await type(qty, '1');
check('continue opens once a quantity is set', !byText('button', 'Continue').disabled);
check('quantity is capped at what was sold', Number(qty.max) === 2);

planNow = () => basePlan({ action: 'refund_partial', refund_amount: 100,
  lines: [{ invoice_item_id: 'L1', name: 'Pet Corset', line_kind: 'product', quantity: 2, selected_quantity: 1, amount: 100 }],
  summary: ['Refund S$100.00.'] });
await click(byText('button', 'Continue'));
check('asks for a reason', text().includes('Reason'));
check('review is refused without a reason', byText('button', 'Review').disabled);
await type(document.querySelector('.invoice-guided-why textarea'), 'Customer returned one');
await click(byText('button', 'Review'));
check('shows what it will do, in words', text().includes('Refund S$100.00.'));
check('a person who cannot approve is told it goes for approval', text().includes('Submit for approval'));
check('and is told nothing changes until then', text().includes('Nothing changes until they approve'));
await click(byText('button', 'Submit for approval'));
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
  summary: ['Refund S$100.00.'] }), requested_plan: basePlan() };
await render({ canApprove: true });
await click(byText('button', 'Refund everything'));
await type(document.querySelector('.invoice-guided-why textarea'), 'All back');
await click(byText('button', 'Review'));
check('an approver is offered confirm-and-record', text().includes('Confirm and record'));
await click(byText('button', 'Confirm and record'));
check('a changed plan is explained rather than silently applied', text().includes('has changed since the request was raised'));
check('and the revised figure is shown', text().includes('Refund S$100.00.'));
check('nothing is reported as done', !text().includes('Refund of S$200.00 recorded'));

// The second confirmation carries the REVISED hash, not the stale one.
stub.resolveResult = { status: 'approved', refund_recorded: true, refunded_amount: 100,
  cancellation: null, refund: { refunded_amount: 100 }, goods_returned: 0, refund_still_due: 0 };
await click(byText('button', 'Confirm and record'));
const second = calls.filter(c => c.name === 'resolve_invoice_action_v2').at(-1);
check('the retry confirms the revised plan by its own hash', second?.args.p_plan_hash === 'HASH-B', second?.args.p_plan_hash);
check('and reports the amount the server actually refunded', text().includes('Refund of S$100.00 recorded.'));

// ---------------------------------------------------------------------
// Cancelling with the money still to go back.
// ---------------------------------------------------------------------
calls.length = 0;
planNow = () => basePlan({ action: 'cancel', refund_amount: 0, refund_due: 200,
  summary: ['Cancel INV-2026-0207 and clear what is still owed.',
            'Refund due: S$200.00. No money is recorded as returned until someone confirms it was.'] });
stub.resolveResult = { status: 'approved', refund_recorded: false, refunded_amount: 0,
  cancellation: { success: true }, refund: null, goods_returned: 1, refund_still_due: 200 };
await render({ canApprove: true });
await click(byText('button', 'Cancel the invoice'));
await type(document.querySelector('.invoice-guided-why textarea'), 'Customer pulled out');
await click(byText('button', 'Review'));
check('offers the money-actually-returned choice', text().includes('has actually gone back to the customer now'));
check('and defaults to NOT claiming the money moved',
  document.querySelector('.invoice-guided-refunddue input').checked === false);
await click(byText('button', 'Confirm and record'));
check('reports the cancellation', text().includes('Invoice cancelled.'));
check('does not claim a refund that was not recorded', !text().includes('Refund of'));
check('and keeps the follow-up visible', text().includes('S$200.00 is still due back'));

// ---------------------------------------------------------------------
// A blocked invoice offers nothing to click.
// ---------------------------------------------------------------------
planNow = () => basePlan({ blocked: true,
  blockers: [{ code: 'voucher_evidence_review', message: 'Sold vouchers need original issuance evidence.' }] });
await render({ canApprove: true });
check('a blocked invoice explains why', text().includes('needs review first'));
check('and refuses every action', ['Cancel the invoice', 'Refund everything', 'Refund some items']
  .every(l => byText('button', l)?.disabled));

console.log(failures === 0
  ? '\nPASS: the guided flow steps, validates, submits what was chosen, refuses a changed plan until it is confirmed by its own hash, reports only what the server actually did, and offers nothing on a blocked invoice'
  : `\nFAILED: ${failures} check(s)`);
process.exit(failures === 0 ? 0 : 1);
