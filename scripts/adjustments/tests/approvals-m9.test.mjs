// The staff pages after migration 533 (security audit of 17 Nov 2026, finding M9; the user's
// decisions of 20 Nov 2026), rendered for real against a fake backend. The database enforces
// every rule; these pages must not OFFER what it will refuse, and say why.
//
//   1. A Manager does not approve their own request (a stock correction on Approvals, a refund
//      request on Approvals, a transfer's review) nor resolve a transfer they received; they still
//      reject. Owners still approve their own.
//   2. A Manager decides a transfer or approves a correction only where every STORE involved is
//      one they work at; warehouses are open; an Owner has every store.
//   3. Credit by hand (Customers) and affiliate payouts/repayments (Commissions) are Owner-only.
//   4. A Manager takes back up to S$1,000 per invoice, refunds and lowered payments together.
//   5. Credit package / premium bundle FOC and moving unused credit are Owner-only.
//   6. A Manager who edited a transfer request cannot approve it, and cannot add lines or raise a
//      quantity while approving one.
//
// Every name, id and amount is invented. Run: node --test scripts/adjustments/tests/approvals-m9.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://approvals.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
dom.window.confirm = () => true; dom.window.alert = m => globalThis.__alerts.push(String(m));
globalThis.confirm = dom.window.confirm; globalThis.alert = dom.window.alert;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
if (!globalThis.crypto?.randomUUID) globalThis.crypto = { ...(globalThis.crypto ?? {}), randomUUID: () => 'req-' + Math.random().toString(16).slice(2) };
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
      export { default as ApprovalsPage } from './src/pages/ApprovalsPage';
      export { default as TransfersPage } from './src/pages/TransfersPage';
      export { InvoiceFinancePanel } from './src/components/invoices/InvoiceFinancePanel';
      export { InvoiceGuidedAction } from './src/components/invoices/InvoiceGuidedAction';
      export { AffiliatePayoutPanel } from './src/components/commissions/AffiliatePayoutPanel';
      export * as perms from './src/lib/permissions/approvals';
      export * as biz from './src/lib/invoices/business';
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
    b.onResolve({ filter: /^\.{1,2}\/(?:.*\/)?supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onResolve({ filter: /^xlsx$/, }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js', contents: 'export const utils = {}; export const writeFile = () => {};' }));
  } }],
});
const P = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { createRoot, act, React, ErrorBoundary, perms, biz } = P;

// ── fixture ────────────────────────────────────────────────────────────────
const T = '2026-11-20T02:00:00Z';
const USERS = {
  owner: { id: 'u-own', full_name: 'Owner Fixture', role: 'owner', is_active: true },
  manager: { id: 'u-mgr', full_name: 'Manager Fixture', role: 'manager', is_active: true },
  manager2: { id: 'u-mgr2', full_name: 'Other Manager Fixture', role: 'manager', is_active: true },
  staff: { id: 'u-stf', full_name: 'Staff Fixture', role: 'staff', is_active: true },
};
// The Manager works at store A only.
const ASSIGN = { manager: ['s-a'], manager2: ['s-a', 's-b'], staff: ['s-a'] };
const adj = (id, by, store, extra = {}) => ({ id, request_type: 'adjustment', status: 'pending', requested_by: by, approved_by: null, approved_at: null,
  related_record_id: 'p-mat', reason: `Count ${id}`, response_note: null, created_at: T,
  payload: { location_type: store.startsWith('w') ? 'warehouse' : 'store', location_id: store, product_id: 'p-mat', current_qty: 3, new_qty: 1, difference: -2, reference: id }, ...extra });
const transfer = (id, o) => ({ id, transfer_type: 'warehouse_to_store', source_type: 'warehouse', source_id: 'w-1', dest_type: 'store', dest_id: 's-a',
  status: 'pending', note: null, rejection_reason: null, requested_by: 'u-stf', approved_by: null, created_at: T, approved_at: null,
  completed_at: null, version: 1, edit_count: 0, edited_by: null, dispatched_at: null, received_at: null, received_by: null, ...o });
const tline = (id, request, o) => ({ id, transfer_request_id: request, line_kind: 'product', product_id: 'p-mat', quantity: 5, approved_quantity: null,
  in_transit_quantity: null, received_quantity: null, discrepancy_quantity: null, discrepancy_resolved_at: null, discrepancy_resolution: null,
  added_by_approver: false, created_at: T, ...o });
function makeFixture() {
  return {
    stores: [{ id: 's-a', name: 'Fixture Store A', is_active: true, deleted_at: null }, { id: 's-b', name: 'Fixture Store B', is_active: true, deleted_at: null }],
    warehouses: [{ id: 'w-1', name: 'Fixture Warehouse', is_active: true, deleted_at: null }],
    products: [{ id: 'p-mat', name: 'Fixture Mat', sku: 'FX-1', is_active: true, deleted_at: null }],
    profiles: Object.values(USERS).map(u => ({ ...u })),
    user_store_assignments: Object.entries(ASSIGN).flatMap(([k, ids]) => ids.map(s => ({ id: `a-${k}-${s}`, user_id: USERS[k].id, store_id: s }))),
    store_product_prices: [{ store_id: 's-a', product_id: 'p-mat', is_active: true, deleted_at: null }, { store_id: 's-b', product_id: 'p-mat', is_active: true, deleted_at: null }],
    store_inventory: [], approval_requests: [], transfer_requests: [], transfer_request_lines: [], invoice_payments: [],
  };
}

function createBackend(fx) {
  const b = { calls: [], handlers: {}, fx };
  const rpcs = {
    my_assigned_stores: () => fx.stores.map((s, i) => ({ store_id: s.id, store_name: s.name, is_default: i === 0 })),
    pending_adjustments_live: () => [],
    resolve_inventory_adjustment: () => ({ success: true }),
    resolve_invoice_action_v2: () => ({ success: true }),
    transfer_request_sourcing: () => [], transfer_product_sourcing: () => [], transfer_revisions: () => [],
    review_and_dispatch_transfer: () => ({ success: true }), reject_transfer: () => ({ success: true }),
    stock_transfer_details: a => ({ id: a.p_request_id, notes: [], lines: (fx.transfer_request_lines.filter(l => l.transfer_request_id === a.p_request_id))
      .map(l => ({ id: l.id, product: 'x', sources: fx.sources?.[l.id] ?? [] })) }),
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], single: false, span: null }); }
    select() { return this; }
    eq(c, v) { this.filters.push(r => r[c] === v); return this; }
    is(c, v) { this.filters.push(r => (r[c] ?? null) === v); return this; }
    in(c, vs) { this.filters.push(r => vs.includes(r[c])); return this; }
    gt(c, v) { this.filters.push(r => r[c] > v); return this; }
    order() { return this; }
    limit() { return this; }
    range(a, z) { this.span = [a, z]; return this; }
    maybeSingle() { this.single = true; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args });
      await Promise.resolve();
      if (this.kind === 'rpc') {
        const fn = b.handlers[this.name] ?? rpcs[this.name];
        if (!fn) return { data: null, error: { message: `unknown rpc ${this.name}` } };
        const out = fn(this.args);
        if (out && out.__error) return { data: null, error: { message: out.__error, code: '42501' } };
        return { data: structuredClone(out), error: null };
      }
      let rows = (fx[this.name] ?? []).filter(r => this.filters.every(f => f(r)));
      if (this.span) rows = rows.slice(this.span[0], this.span[1] + 1);
      return { data: structuredClone(this.single ? rows[0] ?? null : rows), error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

// ── driving ────────────────────────────────────────────────────────────────
let root = null; let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mountEl(make, who, setup) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(makeFixture());
  globalThis.__backend = backend; globalThis.__renderErrors = []; globalThis.__alerts = [];
  const me = USERS[who];
  globalThis.__auth = { profile: me, assignments: backend.fx.user_store_assignments.filter(a => a.user_id === me.id) };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, make(me))));
  await tick();
  assert.deepEqual(globalThis.__renderErrors, []);
}
const mount = (Page, who, setup) => mountEl(() => React.createElement(Page), who, setup);
const text = () => document.body.textContent;
const click = async el => { assert.ok(el, 'the element to click exists'); await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); }); await tick(); };
const buttons = (scope = document) => [...scope.querySelectorAll('button')];
const buttonWith = (label, scope = document) => buttons(scope).find(b => b.textContent.includes(label));
const row = label => [...document.querySelectorAll('tr')].find(tr => tr.textContent.includes(label));
const modal = () => document.querySelector('.modal');
const callsOf = name => backend.calls.filter(c => c.name === name);
async function setValue(el, value) {
  const proto = el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => { Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value); el.dispatchEvent(new dom.window.Event('input', { bubbles: true })); });
  await tick(2);
}
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

// ── the helpers ────────────────────────────────────────────────────────────
test('helpers: own request, stores, owner-only actions, the S$1,000 cap in cents', () => {
  assert.equal(perms.canApproveOwnRequest('owner', 'u-own', 'u-own'), true, 'an Owner approves their own');
  assert.equal(perms.canApproveOwnRequest('manager', 'u-mgr', 'u-mgr'), false);
  assert.equal(perms.canApproveOwnRequest('manager', 'u-stf', 'u-mgr'), true);
  assert.equal(perms.canApproveOwnRequest('staff', 'u-stf', 'u-other'), false);
  assert.equal(perms.canResolveReceivedTransfer('manager', 'u-mgr', 'u-mgr'), false);
  assert.equal(perms.canResolveReceivedTransfer('manager', 'u-stf', 'u-mgr'), true);
  assert.equal(perms.canResolveReceivedTransfer('owner', 'u-own', 'u-own'), true);
  assert.deepEqual(perms.transferStoreIds({ source_type: 'warehouse', source_id: 'w', dest_type: 'store', dest_id: 's-a' }), ['s-a']);
  assert.deepEqual(perms.transferStoreIds({ source_type: 'store', source_id: 's-b', dest_type: 'store', dest_id: 's-a' }), ['s-b', 's-a']);
  assert.deepEqual(perms.transferStoreIds({ source_type: 'warehouse', source_id: 'w', dest_type: 'warehouse', dest_id: 'w2' }), []);
  assert.deepEqual(perms.adjustmentStoreIds({ location_type: 'warehouse', location_id: 'w' }), []);
  assert.equal(perms.worksAtStores('manager', ['s-a'], ['s-a']), true);
  assert.equal(perms.worksAtStores('manager', ['s-a', 's-b'], ['s-a']), false);
  assert.equal(perms.worksAtStores('manager', [], []), true, 'a warehouse-only change is open to every Manager');
  assert.equal(perms.worksAtStores('owner', ['s-z'], []), true);
  assert.equal(perms.canAdjustCreditByHand('owner'), true);
  assert.equal(perms.canAdjustCreditByHand('manager'), false);
  assert.equal(perms.canRecordAffiliatePayout('manager'), false);
  assert.equal(perms.canRecordAffiliateRepayment('manager'), false);
  assert.equal(perms.canRecordAffiliateRepayment('owner'), true);
  assert.equal(perms.canMoveUnusedCredit('manager'), false);
  assert.equal(perms.canMoveUnusedCredit('owner'), true);
  // The cap: S$1,000 exactly is allowed, S$1,000.01 is not, and it is cumulative.
  assert.equal(perms.refundWithinRole('manager', 0, 1000), true);
  assert.equal(perms.refundWithinRole('manager', 0, 1000.01), false);
  assert.equal(perms.refundWithinRole('manager', 600, 400), true);
  assert.equal(perms.refundWithinRole('manager', 600, 400.01), false);
  assert.equal(perms.refundWithinRole('manager', 1000, 0.01), false);
  assert.equal(perms.refundWithinRole('manager', 999.99, 0.01), true, 'cents, never floats');
  assert.equal(perms.refundWithinRole('owner', 5000, 5000), true, 'an Owner has no cap');
  // Lowered payments, as the database counts them: per payment, its reversal minus the SUM of its replacements.
  const rev = (id, amount) => ({ id: `rv-${id}`, amount, entry_kind: 'correction_reversal', corrects_payment_id: id });
  const rep = (id, amount, n = 1) => ({ id: `rp-${id}-${n}`, amount, entry_kind: 'correction_replacement', corrects_payment_id: id });
  assert.equal(perms.loweredPaymentsTotal([{ id: 'a', amount: 100 }, rev('a', 100), rep('a', 60, 1), rep('a', 40, 2)]), 0, 'a split that keeps its total counts 0');
  assert.equal(perms.loweredPaymentsTotal([{ id: 'a', amount: 100 }, rev('a', 100), rep('a', 40, 1), rep('a', 30, 2)]), 30, 'a split that loses 30 counts 30, by the sum of its parts');
  assert.equal(perms.loweredPaymentsTotal([{ id: 'a', amount: 100 }, rev('a', 100)]), 100, 'a removal (no replacement) counts in full');
  assert.equal(perms.loweredPaymentsTotal([rev('a', 800), rep('a', 500), rev('b', 200), rep('b', 150)]), 350, 'corrections of different payments are summed');
  assert.equal(perms.loweredPaymentsTotal([rev('a', 800), rep('a', 500), rev('b', 100), rep('b', 150)]), 300, 'a raise after a reduction does not offset it');
  assert.equal(perms.loweredPaymentsTotal([{ id: 'a', amount: 100 }]), 0);
  assert.equal(perms.loweredPaymentsTotal(null), 0);
  assert.equal(perms.paymentDropOf([{ id: 'a', amount: 800 }, { id: 'b', amount: 100 }],
    { a: { remove: true, parts: [{ amount: 800 }] }, b: { parts: [{ amount: 40 }, { amount: 30 }] } }), 830, 'a removal in full, a split by what it falls short');
  assert.equal(perms.paymentDropOf([{ id: 'a', amount: 800 }], { a: { parts: [{ amount: 900 }] } }), 0);
  assert.equal(perms.paymentDropOf([{ id: 'a', amount: 100 }], { a: { parts: [{ amount: 60 }, { amount: 40 }] } }), 0, 'a split that keeps its total: 0');
  assert.equal(perms.paymentDropOf([{ id: 'a', amount: 100 }], { a: { parts: [{ amount: 40 }, { amount: 30 }] } }), 30, 'a split that loses 30');
  assert.equal(perms.paymentDropOf([{ id: 'a', amount: 100 }], { a: { remove: true, parts: [{ amount: 100 }] } }), 100, 'a removal in full');
  assert.equal(perms.paymentDropOf([{ id: 'a', amount: 800 }, { id: 'b', amount: 200 }], { a: { parts: [{ amount: 500 }] }, b: { parts: [{ amount: 150 }] } }), 350, 'two payments summed');
  assert.equal(perms.paymentDropOf([{ id: 'a', amount: 800 }, { id: 'b', amount: 100 }], { a: { parts: [{ amount: 500 }] }, b: { parts: [{ amount: 150 }] } }), 300, 'a raise does not offset');
  // Reviews and edits.
  assert.equal(perms.canApproveEditedTransfer('manager', 'u-mgr', 'u-mgr'), false);
  assert.equal(perms.canApproveEditedTransfer('manager', 'u-mgr2', 'u-mgr'), true);
  assert.equal(perms.canApproveEditedTransfer('owner', 'u-own', 'u-own'), true);
  assert.equal(perms.reviewRaisesRequest([{ line_id: 'l', requested_quantity: 5, approved_quantity: 5 }]), false);
  assert.equal(perms.reviewRaisesRequest([{ line_id: 'l', requested_quantity: 5, approved_quantity: 3 }]), false);
  assert.equal(perms.reviewRaisesRequest([{ line_id: 'l', requested_quantity: 5, approved_quantity: 6 }]), true);
  assert.equal(perms.reviewRaisesRequest([{ line_id: null, requested_quantity: 0, approved_quantity: 1, added_by_approver: true }]), true);
  assert.match(perms.APPROVAL_MESSAGES.refundCap, /^A Manager can take back up to S\$1,000 on an invoice, refunds and lowered payments together; an Owner does anything above that\.$/);
  // FOC on credit package / bundle lines: Owner only; vouchers and therapy stay Owner/Manager; products free for Staff.
  for (const kind of ['credit_package', 'premium_bundle']) {
    assert.equal(biz.canGiveFocOn('owner', kind), true, kind);
    assert.equal(biz.canGiveFocOn('manager', kind), false, kind);
    assert.equal(biz.canGiveFocOn('staff', kind), false, kind);
  }
  assert.equal(biz.canGiveFocOn('manager', 'voucher'), true);
  assert.equal(biz.canGiveFocOn('staff', 'product'), true);
  assert.equal(biz.canGiveFocOn('manager', 'product'), true);
});

// ── Approvals ──────────────────────────────────────────────────────────────
const approvalsSetup = b => {
  b.fx.approval_requests = [
    adj('r-own', 'u-mgr', 's-a'),              // the Manager's own correction, at their store
    adj('r-staff-a', 'u-stf', 's-a'),          // another's, at their store
    adj('r-staff-b', 'u-stf', 's-b'),          // another's, at a store they do not work at
    adj('r-staff-w', 'u-stf', 'w-1'),          // another's, at a warehouse
    { id: 'r-inv-own', request_type: 'invoice_refund', status: 'pending', requested_by: 'u-mgr', approved_by: null, related_record_id: 'i-1', reason: 'own refund',
      created_at: T, payload: { invoice_id: 'i-1', invoice_no: 'FX-INV-1' } },
    { id: 'r-inv-staff', request_type: 'invoice_refund', status: 'pending', requested_by: 'u-stf', approved_by: null, related_record_id: 'i-2', reason: 'staff refund',
      created_at: T, payload: { invoice_id: 'i-2', invoice_no: 'FX-INV-2' } },
  ];
};
const approveButton = label => buttonWith(label === 'inv' ? 'Review' : 'Approve', row(label === 'inv' ? 'FX-INV' : label));
const rowBy = reason => [...document.querySelectorAll('tr')].find(tr => tr.textContent.includes(reason));

test('Approvals: a Manager does not approve their own request or one at a store they do not work at; Reject stays; warehouses are open', async () => {
  await mount(P.ApprovalsPage, 'manager', approvalsSetup);
  const approveOf = reason => buttonWith('Approve', rowBy(reason));
  const rejectOf = reason => buttonWith('Reject', rowBy(reason));
  assert.equal(approveOf('Count r-own').disabled, true, 'own correction: Approve off');
  assert.ok(rowBy('Count r-own').textContent.includes('A Manager cannot approve their own stock correction. An Owner or another Manager approves it.'));
  assert.equal(rejectOf('Count r-own').disabled, false, 'own correction: Reject still offered');
  assert.equal(approveOf('Count r-staff-a').disabled, false, "another's correction at their store: offered");
  assert.equal(approveOf('Count r-staff-b').disabled, true, 'a store they do not work at: Approve off');
  assert.ok(rowBy('Count r-staff-b').textContent.includes('A Manager approves only for the stores they work at.'));
  assert.equal(rejectOf('Count r-staff-b').disabled, false, 'a correction can still be rejected');
  assert.equal(approveOf('Count r-staff-w').disabled, false, 'a warehouse is open to every Manager');
  assert.equal(buttonWith('Review', rowBy('own refund')).disabled, true, 'own refund request: Review (approval) off');
  assert.ok(rowBy('own refund').textContent.includes('Your own request: an Owner or another Manager approves it.'));
  assert.equal(buttonWith('Reject', rowBy('own refund')).disabled, false);
  assert.equal(buttonWith('Review', rowBy('staff refund')).disabled, false, "a Staff member's refund request is reviewable");
  // The server's message still shows when a refusal gets through.
  backend.handlers.resolve_inventory_adjustment = () => ({ __error: 'A Manager approves only for the stores they work at.' });
  await click(approveOf('Count r-staff-a'));
  assert.deepEqual(globalThis.__alerts, ['A Manager approves only for the stores they work at.']);
  // Rejecting one's own request goes through.
  await click(rejectOf('Count r-own'));
  await setValue(modal().querySelector('textarea'), 'count again');
  await click(buttonWith('Reject', modal()));
  assert.deepEqual(callsOf('resolve_inventory_adjustment').pop().args, { p_request_id: 'r-own', p_approve: false, p_note: 'count again' });
});

test('Approvals: an Owner approves their own request and every store', async () => {
  await mount(P.ApprovalsPage, 'owner', b => { approvalsSetup(b); b.fx.approval_requests[0].requested_by = 'u-own'; b.fx.approval_requests[4].requested_by = 'u-own'; });
  for (const reason of ['Count r-own', 'Count r-staff-a', 'Count r-staff-b', 'Count r-staff-w']) {
    assert.equal(buttonWith('Approve', rowBy(reason)).disabled, false, reason);
  }
  assert.equal(buttonWith('Review', rowBy('own refund')).disabled, false);
  assert.ok(!document.querySelector('[data-testid="approve-blocked"]'), 'no note for an Owner');
});

// ── Transfers ──────────────────────────────────────────────────────────────
const transfersSetup = b => {
  b.fx.transfer_requests = [
    transfer('t-own', { requested_by: 'u-mgr', note: 'T own' }),                                   // the Manager's own
    transfer('t-staff', { note: 'T staff' }),                                                        // at store A, from a warehouse
    transfer('t-edited', { note: 'T edited', edit_count: 1, edited_by: 'u-mgr' }),                   // the Manager edited it
    transfer('t-other', { note: 'T other', dest_id: 's-b' }),                                        // store B
    transfer('t-wh', { note: 'T wh', transfer_type: 'warehouse_to_warehouse', dest_type: 'warehouse', dest_id: 'w-1', source_id: 'w-1' }),
    transfer('t-disc-own', { note: 'T discown', status: 'received_with_discrepancy', received_by: 'u-mgr', approved_by: 'u-own' }),
    transfer('t-disc-ok', { note: 'T discok', status: 'received_with_discrepancy', received_by: 'u-stf', approved_by: 'u-own' }),
    transfer('t-disc-b', { note: 'T discb', status: 'received_with_discrepancy', received_by: 'u-stf', approved_by: 'u-own', dest_id: 's-b' }),
    transfer('t-disc-src', { note: 'T discsrc', status: 'received_with_discrepancy', received_by: 'u-stf', approved_by: 'u-own' }),
  ];
  b.fx.transfer_request_lines = ['t-own', 't-staff', 't-edited', 't-other', 't-wh'].map(id => tline(`l-${id}`, id))
    .concat(['t-disc-own', 't-disc-ok', 't-disc-b', 't-disc-src'].map(id => tline(`l-${id}`, id, { approved_quantity: 5, in_transit_quantity: 5, received_quantity: 3, discrepancy_quantity: -2 })));
  b.fx.sources = { 'l-t-disc-src': [{ name: 'Fixture Store B', quantity: 5 }], 'l-t-disc-ok': [{ name: 'Fixture Warehouse', quantity: 5 }] };
};
const TR_IDS = { 'T own': 't-own', 'T staff': 't-staff', 'T edited': 't-edited', 'T other': 't-other', 'T wh': 't-wh', 'T discown': 't-disc-own',
  'T discok': 't-disc-ok', 'T discb': 't-disc-b', 'T discsrc': 't-disc-src' };
const tRow = note => document.querySelector(`tr[data-request-id="${TR_IDS[note]}"]`);

test('Transfers: Review only at the Manager\'s stores; own and edited requests cannot be approved but can be rejected; warehouses open', async () => {
  await mount(P.TransfersPage, 'manager', transfersSetup);
  assert.ok(buttonWith('Review', tRow('T staff')), 'store A: Review offered');
  assert.ok(tRow('T other'), 'the other-store request is listed');
  assert.ok(!buttonWith('Review', tRow('T other')), 'store B: no Review');
  assert.ok(tRow('T other').textContent.includes('Not one of your stores'), 'with a note');
  assert.ok(buttonWith('Review', tRow('T wh')), 'warehouse to warehouse: open');
  // Own request: the window opens, Approve is off, Reject is on.
  await click(buttonWith('Review', tRow('T own')));
  let approve = buttonWith('Approve', modal()); const reject = buttonWith('Reject', modal());
  assert.equal(approve.disabled, true);
  assert.ok(modal().textContent.includes('Your own request: an Owner or another Manager approves it.'));
  assert.equal(reject.disabled, false);
  await click(buttonWith('Cancel', modal()) ?? buttonWith('Close', modal()) ?? modal().querySelector('button'));
  await mount(P.TransfersPage, 'manager', transfersSetup);
  await click(buttonWith('Review', tRow('T edited')));
  assert.equal(buttonWith('Approve', modal()).disabled, true, 'a request the Manager edited');
  assert.ok(modal().textContent.includes('A Manager who changed this transfer request cannot also approve it.'));
  assert.equal(buttonWith('Reject', modal()).disabled, false);
  await mount(P.TransfersPage, 'manager', transfersSetup);
  await click(buttonWith('Review', tRow('T staff')));
  assert.equal(buttonWith('Approve', modal()).disabled, false, "another's request at their store: Approve on");
});

test('Transfers: in the review a Manager lowers quantities but does not add lines or raise one; an Owner may', async () => {
  await mount(P.TransfersPage, 'manager', transfersSetup);
  await click(buttonWith('Review', tRow('T staff')));
  assert.ok(!buttonWith('Add Product', modal()) && !buttonWith('Add Manual Item', modal()), 'no Add for a Manager');
  assert.ok(modal().textContent.includes('lowers quantities'), 'and it says why');
  const qty = [...modal().querySelectorAll('input[type=number]')].find(i => i.value === '5');
  assert.equal(qty.getAttribute('max'), '5');
  await setValue(qty, '9');
  assert.equal([...modal().querySelectorAll('input[type=number]')].find(i => i.getAttribute('max') === '5').value, '5', 'clamped at what was requested');
  await setValue([...modal().querySelectorAll('input[type=number]')].find(i => i.getAttribute('max') === '5'), '3');
  assert.equal([...modal().querySelectorAll('input[type=number]')].find(i => i.getAttribute('max') === '5').value, '3', 'lowering is allowed');
  await mount(P.TransfersPage, 'owner', transfersSetup);
  await click(buttonWith('Review', tRow('T staff')));
  assert.ok(buttonWith('Add Product', modal()) && buttonWith('Add Manual Item', modal()), 'an Owner adds lines');
});

test('Transfers: a Manager does not resolve a discrepancy on a transfer they received, or at other stores; an Owner does', async () => {
  await mount(P.TransfersPage, 'manager', transfersSetup);
  assert.equal(buttonWith('Resolve', tRow('T discown')).disabled, true, 'received by themselves');
  assert.ok(tRow('T discown').textContent.includes('You received this transfer'));
  assert.equal(buttonWith('Resolve', tRow('T discok')).disabled, false);
  assert.equal(buttonWith('Resolve', tRow('T discb')).disabled, true, 'a store they do not work at');
  // Lines sent from another store: the window opens, Resolve & Complete is off.
  await click(buttonWith('Resolve', tRow('T discsrc')));
  assert.equal(buttonWith('Resolve & Complete', modal()).disabled, true);
  assert.ok(modal().textContent.includes('A Manager approves only for the stores they work at.'));
  await mount(P.TransfersPage, 'owner', transfersSetup);
  for (const n of ['T discown', 'T discok', 'T discb']) assert.equal(buttonWith('Resolve', tRow(n)).disabled, false, `owner: ${n}`);
});

// ── Commissions ────────────────────────────────────────────────────────────
const payoutData = () => ({
  groups: [{ referrer: 'ref-a', month: '2026-10-01', earned: 100, adjustments: 0, paid: 0, balance: 100, tier1: 100, tier2: 0, review_reason: null, settled: 0,
    payable: 100, referrer_owed: 100, referrer_payable: 100, referrer_deduction: 0 },
    { referrer: 'ref-b', month: '2026-10-01', earned: 0, adjustments: -50, paid: 0, balance: -50, tier1: 0, tier2: 0, review_reason: null, settled: 0,
      payable: 0, referrer_owed: -50, referrer_payable: 0, referrer_deduction: 50 }],
  referrers: [{ referrer: 'ref-a', owed: 100, unpaid: 100, deduction: 0, payable: 100 }, { referrer: 'ref-b', owed: -50, unpaid: 0, deduction: 50, payable: 0 }],
  payouts: [{ id: 'pay-1', referrer_customer_id: 'ref-a', payout_month: '2026-09-01', total_amount: 10, total_tier1: 10, total_tier2: 0, payment_date: '2026-10-02',
    payment_method_id: 'm1', payment_method_name: 'Bank Transfer', reference: null, notes: null, status: 'paid', version: 1, allocation_state: 'verified', allocation_review_reason: null }],
  settlements: [{ id: 'set-1', referrer_customer_id: 'ref-a', amount: 5, settled_on: '2026-10-09', method: 'paid_outside_app', note: 'x', created_by: 'o', created_by_name: 'Olive Owner',
    created_at: T, voided_at: null, voided_by: null, voided_by_name: null, void_reason: null }],
  methods: [{ id: 'm1', name: 'Bank Transfer', is_active: true, deleted_at: null, is_wallet_credit: false }],
});
async function payoutPanel(mode, props) {
  await mountEl(() => React.createElement(P.AffiliatePayoutPanel, { mode, userId: 'u', onSaved: () => {}, ...props }), 'manager', b => {
    b.handlers.affiliate_payout_overview = () => payoutData();
    b.handlers.commission_referrer_names = () => [{ id: 'ref-a', full_name: 'Alpha Affiliate' }, { id: 'ref-b', full_name: 'Bravo Affiliate' }];
  });
  await tick(10);
}
test('Affiliate payouts and repayments: only an Owner records, corrects or voids; a Manager still sees them', async () => {
  for (const [who, canRecord] of [['Owner', true], ['Manager', false]]) {
    await payoutPanel('earned', { canPay: true, canRecord });
    assert.ok(text().includes('Alpha Affiliate'), `${who}: balances are shown`);
    assert.equal(!!buttonWith('Record payout'), canRecord, `${who}: Record payout`);
    assert.equal(!!buttonWith('Mark as settled'), canRecord, `${who}: Mark as settled (a repayment)`);
    assert.equal(text().includes('Only an Owner can record or correct an affiliate payout.'), !canRecord, `${who}: the note`);
    await payoutPanel('payouts', { canPay: true, canRecord });
    assert.ok(text().includes('Bank Transfer'), `${who}: payouts are shown`);
    assert.equal(!!buttonWith('Edit payout'), canRecord, `${who}: Edit payout`);
    assert.equal(!!buttonWith('Void'), canRecord, `${who}: Void a repayment`);
    assert.ok(buttonWith('History & allocations'), `${who}: history stays`);
  }
});

// ── the invoice panel: the S$1,000 cap, shared by refunds and lowered payments; moving credit ──
const bundleOptions = (refunded, extra = {}) => ({
  financial: { status: 'paid', total: 5000, net_received: 5000, outstanding: 0, refund_due: 0, refunded, overpayment_refundable: 0 },
  sources: [{ payment_id: 'P1', method: 'Bank transfer', wallet: false, remaining: 5000 }],
  benefits: extra.benefits ?? [], stock: [], review_required: false,
  lines: [{ invoice_item_id: 'L1', name: 'Fixture item', remaining: 5000, line_kind: 'product' }],
});
const PAYMENTS = [{ id: 'P1', amount: 5000, payment_method_id: 'm1', entry_kind: 'payment', created_at: T, effective_at: T }];
async function financePanel(who, refunded, mode, extra = {}, payments = PAYMENTS) {
  await mountEl(me => React.createElement(P.InvoiceFinancePanel, { invoiceId: 'i-1', canManage: true, role: me.role, payments, methods: [{ id: 'm1', name: 'Bank transfer' }],
    requestedMode: mode, onRequestHandled: () => {}, onChanged: async () => {}, ...extra }), who, b => { b.handlers.invoice_refund_options = () => bundleOptions(refunded, extra); });
  await tick(10);
}
const recordBtn = () => buttonWith('Record with audit history');
async function refundOf(amount) {
  await setValue(modal().querySelector('input[aria-label]') ?? document.querySelector('.invoice-finance-amount input'), String(amount));
}
test('Invoice panel: a lowered payment counts toward a Manager\'s S$1,000; an Owner has no cap', async () => {
  // Payment correction (the "Correct payment" action): lowering 5000 to 4000 takes back 1000.
  const lower = async (who, refunded, to, payments) => {
    await financePanel(who, refunded, 'payment', {}, payments);
    const amountInput = [...document.querySelectorAll('input[type=number]')].find(i => i.value === '5000');
    assert.ok(amountInput, 'the payment amount field');
    await setValue(amountInput, String(to));
    return { blocked: !!document.querySelector('[data-testid="refund-cap"]'), disabled: recordBtn()?.disabled };
  };
  const reason = async () => setValue(document.querySelector('textarea'), 'fixture');
  let r = await lower('manager', 0, 4000);
  await reason();
  assert.equal(r.blocked, false, 'exactly S$1,000 lowered: allowed');
  assert.equal(recordBtn().disabled, false);
  r = await lower('manager', 0, 3999.99);
  assert.equal(r.blocked, true, 'S$1,000.01 lowered: refused with the note');
  assert.ok(text().includes('A Manager can take back up to S$1,000 on an invoice, refunds and lowered payments together; an Owner does anything above that.'));
  await reason(); assert.equal(recordBtn().disabled, true);
  r = await lower('manager', 600, 4600);   // 600 refunded + 400 lowered
  assert.equal(r.blocked, false, 'cumulative: 600 refunded + 400 lowered is exactly S$1,000');
  r = await lower('manager', 600, 4599.99);
  assert.equal(r.blocked, true, 'cumulative: S$1,000.01 together');
  const earlier = [...PAYMENTS, { id: 'P2', amount: 200, entry_kind: 'payment' }, { id: 'P2r', amount: 200, entry_kind: 'correction_reversal', corrects_payment_id: 'P2' }, { id: 'P3', amount: 100, entry_kind: 'correction_replacement', corrects_payment_id: 'P2' }];
  r = await lower('manager', 0, 4100, earlier);
  assert.equal(r.blocked, false, 'an earlier S$100 lowering counts: 900 now + 100 before is exactly S$1,000');
  r = await lower('manager', 0, 4099.99, earlier);
  assert.equal(r.blocked, true, 'and 900.01 now + 100 before is over');
  r = await lower('owner', 0, 100);
  assert.equal(r.blocked, false, 'an Owner has no cap');
});
test('Invoice panel: a Manager\'s refund is held to S$1,000 in total with earlier refunds', async () => {
  const refundForm = async (who, refunded) => {
    await financePanel(who, refunded, 'refund');
    const amount = [...document.querySelectorAll('input[aria-label]')].find(i => i.type === 'number');
    return amount;
  };
  let amount = await refundForm('manager', 600);
  assert.ok(amount, 'the refund form opens');
  const stateOf = async v => { await setValue(amount, String(v)); return !!document.querySelector('[data-testid="refund-cap"]'); };
  assert.equal(await stateOf(400), false, '600 + 400 = S$1,000 exactly');
  assert.equal(await stateOf(400.01), true, '600 + 400.01 is over');
  amount = await refundForm('owner', 600);
  assert.equal(await stateOf(4000), false, 'an Owner has no cap');
});
test('Invoice panel: only an Owner moves unused credit or vouchers to another customer', async () => {
  const benefit = { id: 'b1', invoice_item_id: 'L1', remaining_value: 50, max_refund: 50, customer_name: 'Ada Fixture', granted_value: 50 };
  await financePanel('manager', 0, null, { benefits: [benefit] });
  assert.ok(!buttonWith('Correct unused benefit recipient'), 'no button for a Manager');
  assert.ok(text().includes('Only an Owner can move unused credit or vouchers to another customer.'));
  await financePanel('owner', 0, null, { benefits: [benefit] });
  assert.ok(buttonWith('Correct unused benefit recipient'), 'an Owner has it');
});

// ── the guided action: own request, and the cap on approving ──────────────
const plan = (amount, action = 'refund_full') => ({ invoice_no: 'FX-INV-9', action, refund_amount: action === 'cancel' ? 0 : amount, refund_due: action === 'cancel' ? amount : 0,
  window: { created_on: '2026-11-01', deadline: '2026-11-30', within: true, days_remaining: 10, override_required: false, creation_reliable: true },
  lines: [], stock: [], sources: [], overrides_required: [], blockers: [], summary: [], requires_override: false, blocked: false, plan_hash: 'h', status: 'paid' });
async function review(who, { requester, amount, refunded = 0, lowered = [], action = 'refund_full' }) {
  await mountEl(me => React.createElement(P.InvoiceGuidedAction, { invoiceId: 'i-9', requestId: 'r-9', canApprove: true, role: me.role, viewerId: me.id, onDone: async () => {}, onClose: () => {} }), who, b => {
    b.fx.approval_requests = [{ id: 'r-9', requested_by: requester }];
    b.fx.invoice_payments = lowered.map(p => ({ invoice_id: 'i-9', ...p }));
    b.handlers.invoice_action_request_detail = () => ({ request_id: 'r-9', status: 'pending', action, reason: 'fixture', requested_lines: [],
      current_plan: plan(amount, action), requested_plan: plan(amount, action), legacy: false });
    b.handlers.invoice_refund_options = () => ({ financial: { refunded } });
    b.handlers.invoice_action_plan = () => plan(amount, action);
    b.handlers.invoice_request_status = () => ({ pending: false });
  });
  await tick(10);
  return buttonWith('Confirm');
}
test('Guided action: a Manager does not approve their own request; the S$1,000 cap holds, exactly, over, and cumulatively', async () => {
  let btn = await review('manager', { requester: 'u-mgr', amount: 100 });
  assert.equal(btn.disabled, true, 'own request');
  assert.ok(text().includes('Your own request: an Owner or another Manager approves it.'));
  assert.ok(buttonWith('Reject') && !buttonWith('Reject').disabled, 'Reject stays');
  btn = await review('owner', { requester: 'u-own', amount: 100 });
  assert.equal(btn.disabled, false, 'an Owner approves their own');
  btn = await review('manager', { requester: 'u-stf', amount: 1000 });
  assert.equal(btn.disabled, false, 'S$1,000 exactly');
  btn = await review('manager', { requester: 'u-stf', amount: 1000.01 });
  assert.equal(btn.disabled, true, 'S$1,000.01');
  assert.ok(text().includes('A Manager can take back up to S$1,000 on an invoice, refunds and lowered payments together; an Owner does anything above that.'));
  btn = await review('manager', { requester: 'u-stf', amount: 400, refunded: 600 });
  assert.equal(btn.disabled, false, '600 refunded + 400');
  btn = await review('manager', { requester: 'u-stf', amount: 400.01, refunded: 600 });
  assert.equal(btn.disabled, true, '600 refunded + 400.01');
  btn = await review('manager', { requester: 'u-stf', amount: 300.01, refunded: 600, lowered: [{ id: 'a', amount: 200, entry_kind: 'payment' }, { id: 'ar', amount: 200, entry_kind: 'correction_reversal', corrects_payment_id: 'a' }, { id: 'a2', amount: 100, entry_kind: 'correction_replacement', corrects_payment_id: 'a' }] });
  assert.equal(btn.disabled, true, '600 refunded + 100 lowered earlier + 300.01');
  btn = await review('manager', { requester: 'u-stf', amount: 300, refunded: 600, lowered: [{ id: 'a', amount: 200, entry_kind: 'payment' }, { id: 'ar', amount: 200, entry_kind: 'correction_reversal', corrects_payment_id: 'a' }, { id: 'a2', amount: 100, entry_kind: 'correction_replacement', corrects_payment_id: 'a' }] });
  assert.equal(btn.disabled, false, '600 + 100 + 300 is exactly S$1,000');
  btn = await review('manager', { requester: 'u-stf', amount: 5000, refunded: 900, action: 'cancel' });
  assert.equal(btn.disabled, false, 'a cancellation is not capped, whatever it leaves owed');
  btn = await review('manager', { requester: 'u-mgr', amount: 5000, action: 'cancel' });
  assert.equal(btn.disabled, true, 'but a Manager still does not approve their own cancellation');
  btn = await review('owner', { requester: 'u-stf', amount: 50000, refunded: 9000 });
  assert.equal(btn.disabled, false, 'an Owner has no cap');
});

// ── Edit Invoice (InvoicesPage): the drop in recorded payments is checked before a Manager saves ──
test('Edit Invoice: a Manager\'s removal or split of payments is checked against the S$1,000 before saving; Make FOC names the Owner for bundles', () => {
  const page = readFileSync(new URL('../../../src/pages/InvoicesPage.tsx', import.meta.url), 'utf8');
  const guard = page.indexOf("profile?.role === 'manager') {\n      const drop = paymentDropOf(paymentsBeforeEdit, payEdits);");
  assert.ok(guard > 0, 'the Manager check reads the drop from the payment edits');
  assert.match(page.slice(guard, guard + 700), /refundWithinRole\('manager'[\s\S]*loweredPaymentsTotal\(paymentsBeforeEdit\)[\s\S]*setCErr\(APPROVAL_MESSAGES\.refundCap\); return;/);
  assert.ok(guard < page.indexOf("supabase.rpc('preview_invoice_correction'"), 'and it runs before the preview and the save');
  assert.match(page, /FOC_OWNER_ONLY_KINDS\.includes\(String\(it\.line_kind\)\) \? APPROVAL_MESSAGES\.focOwnerOnly/);
});

// ── Correct payment: only an Owner moves a payment into or out of wallet credit ──
const METHODS9 = [
  { id: 'cash', name: 'Cash', is_active: true, is_wallet_credit: false },
  { id: 'paynow', name: 'PayNow', is_active: true, is_wallet_credit: false },
  { id: 'nets', name: 'NETS', is_active: true, is_wallet_credit: false },
  { id: 'bonus', name: 'Bonus Credit', is_active: true, is_wallet_credit: true },
  { id: 'paid', name: 'Paid Credit', is_active: true, is_wallet_credit: true },
];
test('helper: a Manager is offered only methods on the payment\'s own side of the wallet line; an Owner all', () => {
  const names = (role, orig) => perms.methodsAllowedForPayment(role, METHODS9, orig).map(m => m.name);
  assert.deepEqual(names('manager', 'cash'), ['Cash', 'PayNow', 'NETS'], 'cash: no wallet method');
  assert.deepEqual(names('manager', 'paynow'), ['Cash', 'PayNow', 'NETS'], 'PayNow to NETS is fine');
  assert.deepEqual(names('manager', 'bonus'), ['Bonus Credit', 'Paid Credit'], 'wallet: no money method, the other wallet method stays');
  assert.deepEqual(names('owner', 'cash'), METHODS9.map(m => m.name));
  assert.deepEqual(names('owner', 'bonus'), METHODS9.map(m => m.name));
  assert.equal(perms.methodsAllowedForPayment('manager', METHODS9, 'unknown').length, 5, 'an unknown original leaves the choice to the server');
  assert.equal(perms.APPROVAL_MESSAGES.walletChangeOwnerOnly, 'Only an Owner can change a payment into or out of wallet credit.');
});
async function offeredMethods(who, originalMethod) {
  const payments = [{ id: 'P1', amount: 100, payment_method_id: originalMethod, entry_kind: 'payment', created_at: T, effective_at: T }];
  await financePanel(who, 0, 'payment', { methods: METHODS9 }, payments);
  await click(document.querySelector('button[aria-label="Payment method"]'));
  return [...document.querySelectorAll('[role=listbox][aria-label="Payment method"] [role=option]')].map(o => o.textContent);
}
test('Correct payment: what a Manager and an Owner are offered', async () => {
  assert.deepEqual(await offeredMethods('manager', 'cash'), ['Cash', 'PayNow', 'NETS'], 'a Manager, cash payment: no wallet method');
  assert.ok(text().includes('Only an Owner can change a payment into or out of wallet credit.'));
  assert.deepEqual(await offeredMethods('manager', 'paynow'), ['Cash', 'PayNow', 'NETS'], 'PayNow to NETS');
  assert.deepEqual(await offeredMethods('manager', 'bonus'), ['Bonus Credit', 'Paid Credit'], 'a Manager, wallet payment: only wallet methods');
  assert.deepEqual(await offeredMethods('owner', 'cash'), METHODS9.map(m => m.name), 'an Owner is offered all');
  assert.deepEqual(await offeredMethods('owner', 'bonus'), METHODS9.map(m => m.name));
});
