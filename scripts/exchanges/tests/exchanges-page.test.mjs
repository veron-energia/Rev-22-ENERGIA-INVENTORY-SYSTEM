// The Exchanges page against 408, rendered for real against a fake backend.
//
// The actual src/pages/ExchangesPage.tsx is bundled with esbuild and mounted in
// jsdom. Only the Supabase client and the auth context are stubbed: the client
// by a small in-memory backend that records every call. Every name, number and
// id below is invented.
//
// It checks that the page offers no Wallet method for an exchange's payment
// (SALES-EXTRAS-M1); that a whole-bundle exchange shows the server's preview
// (credit, replacement, what is due) before Confirm, takes exactly that amount
// by a normal method and no instalment, refuses a short payment and a swap the
// server refuses, and greys out a line of two bundles or one with an item
// already exchanged (SALES-EXTRAS-2, -4); and that the affiliate picker says
// the exchange keeps the original sale's affiliate when left empty (EXC-3);
// and that money entered on a payment row left without a method is refused
// rather than counted as received and then dropped.
//
// 424: a returned item counts for the lower of today's price and what was
// paid (the server's exchange_credit_preview), and the page shows both and
// says which counts; without the preview nothing is valued or sent
// (SALES-EXTRAS-5). The replacement bundle picker offers only promotions on
// sale today (SALES-EXTRAS-9). Each new exchange starts empty, the list shows
// the exchange date, no "balance stays owed", and an instalment's method and
// months go with the exchange (SALES-EXTRAS-14). The exchange date runs from
// the 1st of this month (Singapore), never before the original sale, and the
// screen says the sale counts on it (the Owner, 9 Oct 2026, SALES-EXTRAS-M3).
//
// Run: node --test scripts/exchanges/tests/exchanges-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import { displayDay } from '../../../src/lib/exchanges/rules.mjs';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ── the page, bundled ──────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://exchanges.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement', 'HTMLTextAreaElement', 'Element',
  'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
dom.window.confirm = () => true;
const alerts = [];
dom.window.alert = m => alerts.push(String(m));
globalThis.alert = dom.window.alert;
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
      export { default as ExchangesPage } from './src/pages/ExchangesPage';
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
    b.onResolve({ filter: /(^|\/)lib\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };
      export async function fetchCustomersByIds(ids) {
        const want = new Set(ids.filter(Boolean));
        return globalThis.__backend.fx.customers.filter(c => want.has(c.id));
      }
      export function mergeCustomers(existing, extra) {
        const seen = new Set(existing.map(c => c.id));
        return [...existing, ...extra.filter(c => !seen.has(c.id))];
      }` }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
  } }],
});
const { ExchangesPage, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const BENEFIT = 'Bundle "XM Bundle Treat" includes vouchers, therapy or other benefits. A whole-bundle exchange swaps bundles of products only, because those cannot be taken back or issued here yet.';
function makeFixture() {
  return {
    stores: [{ id: 'st-1', name: 'XM Store', is_active: true, deleted_at: null }],
    customers: [{ id: 'c-buyer', full_name: 'Sam Buyer', phone: '+6591400201' }],
    products: [
      { id: 'p-a', name: 'XM A', sku: 'XMA', product_type: 'own', is_active: true, deleted_at: null },
      { id: 'p-b', name: 'XM B', sku: 'XMB', product_type: 'own', is_active: true, deleted_at: null },
      { id: 'p-c', name: 'XM C', sku: 'XMC', product_type: 'own', is_active: true, deleted_at: null },
    ],
    prices: [
      { store_id: 'st-1', product_id: 'p-a', selling_price: 100, is_active: true },
      { store_id: 'st-1', product_id: 'p-b', selling_price: 100, is_active: true },
      { store_id: 'st-1', product_id: 'p-c', selling_price: 120, is_active: true },
    ],
    inventory: [
      { store_id: 'st-1', product_id: 'p-a', current_qty: 50 },
      { store_id: 'st-1', product_id: 'p-b', current_qty: 50 },
      { store_id: 'st-1', product_id: 'p-c', current_qty: 50 },
    ],
    methods: [
      { id: 'm-cash', name: 'Cash', is_active: true, deleted_at: null, is_wallet_credit: false },
      { id: 'm-card', name: 'Card', is_active: true, deleted_at: null, is_wallet_credit: false },
      { id: 'm-w1', name: 'Wallet — Exchange Credit', is_active: true, deleted_at: null, is_wallet_credit: true },
      { id: 'm-w2', name: 'Wallet — Paid Credit', is_active: true, deleted_at: null, is_wallet_credit: true },
    ],
    promotions: [
      { id: 'pr-ab', name: 'XM Bundle AB', code: 'XMAB', fixed_price: 150, is_active: true, deleted_at: null },
      { id: 'pr-ccc', name: 'XM Bundle CCC', code: 'XMC3', fixed_price: 300, is_active: true, deleted_at: null },
      { id: 'pr-tr', name: 'XM Bundle Treat', code: 'XMTR', fixed_price: 90, is_active: true, deleted_at: null },
      { id: 'pr-old', name: 'XM Bundle Old', code: 'XMOLD', fixed_price: 90, is_active: true, deleted_at: null, end_date: '2026-10-01' },
      { id: 'pr-soon', name: 'XM Bundle Soon', code: 'XMSOON', fixed_price: 90, is_active: true, deleted_at: null, start_date: '2999-01-01' },
    ],
    invoices: [{ id: 'inv-1', invoice_no: 'INV-T-0001', customer_id: 'c-buyer', store_id: 'st-1', status: 'paid',
                 paid_at: '2026-10-08T03:00:00Z', is_exchange: false, exchange_id: null },
               // a walk-in sale: no customer
               { id: 'inv-2', invoice_no: 'INV-T-0002', customer_id: null, store_id: 'st-1', status: 'paid',
                 paid_at: '2026-10-08T03:00:00Z', is_exchange: false, exchange_id: null }],
    items: [
      { id: 'li-a', invoice_id: 'inv-1', line_kind: 'product', product_id: 'p-a', quantity: 1, exchanged_at: null, component_exchanged: null },
      // bought at S$60 (a discount); S$100 today
      { id: 'li-b', invoice_id: 'inv-1', line_kind: 'product', product_id: 'p-b', quantity: 1, exchanged_at: null, component_exchanged: null },
      { id: 'li-w', invoice_id: 'inv-2', line_kind: 'product', product_id: 'p-a', quantity: 1, exchanged_at: null, component_exchanged: null },
      { id: 'li-ab', invoice_id: 'inv-1', line_kind: 'promotion', promotion_id: 'pr-ab', quantity: 1, exchanged_at: null, component_exchanged: null },
      { id: 'li-ab2', invoice_id: 'inv-1', line_kind: 'promotion', promotion_id: 'pr-ab', quantity: 2, exchanged_at: null, component_exchanged: null },
      { id: 'li-ab3', invoice_id: 'inv-1', line_kind: 'promotion', promotion_id: 'pr-ab', quantity: 1, exchanged_at: null,
        component_exchanged: [{ product_id: 'p-a', qty: 1, exchange_id: 'ex-old' }] },
    ],
    profiles: [
      { id: 'u-own', full_name: 'Owner One', role: 'owner', is_active: true },
      { id: 'u-c', full_name: 'Staff C', role: 'staff', is_active: true },
    ],
    exchanges: [
      // dated back by staff, and one from before exchange dates (saved 01:30 on 9 Oct in Singapore)
      { id: 'ex-1', exchange_no: 'EX-T-0001', customer_id: 'c-buyer', processing_store_id: 'st-1', exchange_date: '2026-10-05',
        created_at: '2026-10-08T03:00:00Z', returned_credit_total: 100, replacement_total: 120, topup_amount: 20, nonrefundable_amount: 0 },
      { id: 'ex-2', exchange_no: 'EX-T-0002', customer_id: 'c-buyer', processing_store_id: 'st-1', exchange_date: null,
        created_at: '2026-10-08T17:30:00Z', returned_credit_total: 100, replacement_total: 100, topup_amount: 0, nonrefundable_amount: 0 },
    ],
  };
}
const fig = (todays, paid) => ({ todays, paid, credit: Math.min(todays, paid) });
// exchange_credit_preview as 424 answers it, for the fixture's invoices
function creditPreview(invoiceId) {
  if (invoiceId === 'inv-2') return { lines: [{ invoice_item_id: 'li-w', line_kind: 'product', quantity: 1, ...fig(100, 100) }] };
  const bundle = (id, n) => ({ invoice_item_id: id, line_kind: 'promotion', quantity: n, ...fig(200 * n, 150 * n),
    components: ['p-a', 'p-b'].map(p => ({ product_id: p, quantity: n,
      options: Array.from({ length: n }, (_, i) => ({ quantity: i + 1, ...fig(100 * (i + 1), 75 * (i + 1)) })) })) });
  return { lines: [
    { invoice_item_id: 'li-a', line_kind: 'product', quantity: 1, ...fig(100, 100) },
    { invoice_item_id: 'li-b', line_kind: 'product', quantity: 1, ...fig(100, 60) },
    bundle('li-ab', 1), bundle('li-ab2', 2), bundle('li-ab3', 1),
  ] };
}
function createBackend(fx) {
  const b = { calls: [], fx, preview: {}, previewFails: false };
  const rpcs = {
    my_assigned_store_id: () => null,
    my_assigned_stores: () => [],
    exchange_ineligibility_reason: () => '',
    exchange_original_context: () => ({ invoice_id: 'inv-1', invoice_no: 'INV-T-0001', invoice_date: '2026-10-08',
      customer: 'Sam Buyer', served_by: [], affiliate_id: 'ca-1', affiliate: 'Pat Referrer',
      affiliate_still_eligible: true, affiliate_inherited_id: 'ca-1' }),
    bundle_line_components: () => [{ product_id: 'p-a', quantity: 1 }, { product_id: 'p-b', quantity: 1 }],
    store_commission_staff: () => [{ staff_id: 'u-c', staff_name: 'Staff C' }],
    exchange_credit_preview: a => {
      if (b.previewFails) throw new Error('function public.exchange_credit_preview does not exist');
      return creditPreview(a.p_original_invoice_id);
    },
    exchange_bundle_preview: a => a.p_new_promotion_id === 'pr-tr'
      ? { problem: BENEFIT }
      : { problem: null, credit: 200, todays_value: 250, paid: 200, replacement: 360, topup: 160, nonrefundable: 0,
          returned: [{ product_id: 'p-a', name: 'XM A', quantity: 1 }, { product_id: 'p-b', name: 'XM B', quantity: 1 }],
          replacement_items: [{ product_id: 'p-c', name: 'XM C', quantity: 3 }] },
    create_exchange_with_details: () => ({ success: true, id: 'ex-new', exchange_no: 'EXB-20261009-abc123' }),
  };
  const tables = {
    product_exchanges: fx.exchanges, products: fx.products, stores: fx.stores, payment_methods: fx.methods,
    store_product_prices: fx.prices, store_inventory: fx.inventory, promotions: fx.promotions,
    invoices: fx.invoices, invoice_items: fx.items, profiles: fx.profiles, customer_affiliates: [],
    product_exchange_items: [], customers: fx.customers,
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], single: false }); }
    select() { return this; }
    eq(c, v) { this.filters.push(r => r[c] === v); return this; }
    is(c, v) { this.filters.push(r => (r[c] ?? null) === v); return this; }
    in(c, vs) { this.filters.push(r => vs.includes(r[c])); return this; }
    order() { return this; }
    limit() { return this; }
    maybeSingle() { this.single = true; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args });
      await Promise.resolve();
      if (this.kind === 'rpc') {
        const fn = rpcs[this.name];
        if (!fn) return { data: null, error: { message: `unknown rpc ${this.name}` } };
        try { return { data: structuredClone(fn(this.args)), error: null }; }
        catch (e) { return { data: null, error: { message: String(e.message) } }; }
      }
      const rows = (tables[this.name] ?? []).filter(r => this.filters.every(f => f(r)));
      return { data: structuredClone(this.single ? rows[0] ?? null : rows), error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  b.client = { from: name => new Query('table', name, null), rpc: (name, args) => new Query('rpc', name, args) };
  return b;
}

// ── driving the page ───────────────────────────────────────────────────────
let root = null;
let backend = null;
const tick = async (n = 10) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
async function mount() {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(makeFixture());
  globalThis.__backend = backend; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: { id: 'u-own', full_name: 'Owner One', role: 'owner', is_active: true } };
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(ExchangesPage))));
  await tick();
}
const text = () => document.body.textContent;
const modal = () => [...document.querySelectorAll('.modal')].at(-1);
const click = async el => {
  assert.ok(el, 'the element to click exists');
  await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
  await tick();
};
const button = (label, scope = document) => [...scope.querySelectorAll('button')].find(b => b.textContent.trim() === label);
async function setValue(el, value) {
  assert.ok(el, 'the field exists');
  const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype
    : el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
  await act(async () => {
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new dom.window.Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
  });
  await tick(3);
}
const selectWithOption = text => [...modal().querySelectorAll('select')].find(s => [...s.options].some(o => o.textContent.includes(text)));
async function pickSearch(placeholder, label) {
  await click([...modal().querySelectorAll('button')].find(b => b.textContent.trim().startsWith(placeholder)));
  const opt = [...modal().querySelectorAll('div')].find(d => d.firstElementChild?.textContent === label && d.children.length <= 2);
  await click(opt);
}
const callsOf = name => backend.calls.filter(c => c.name === name);
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

async function openOnInvoice() {
  await mount();
  await click(button('New Exchange'));
  await setValue(selectWithOption('XM Store'), 'st-1');
  await setValue(modal().querySelector('input[placeholder="Enter invoice number"]'), 'INV-T-0001');
  await click(button('Find', modal()));
}
const paymentSelects = () => [...modal().querySelectorAll('select')].filter(s => [...s.options].some(o => o.textContent === '— Method —'));
async function readyToConfirm() {
  await setValue(modal().querySelector('input[placeholder="Required"]'), 'Customer prefers the bigger bundle');
  const staff = [...modal().querySelectorAll('label')].find(l => l.textContent.trim() === 'Staff C');
  await click(staff.querySelector('input'));
}

// ── tests ──────────────────────────────────────────────────────────────────
test('a product exchange with a top-up offers no Wallet method, and keeps the instalment', async () => {
  await openOnInvoice();
  assert.deepEqual(globalThis.__renderErrors, []);
  const ret = [...modal().querySelectorAll('label')].find(l => l.textContent.includes('XM A × 1'));
  await click(ret.querySelector('input'));
  await pickSearch('Search product name or SKU', 'XM C — S$120.00 (stock 50)');
  assert.ok(text().includes('Additional payment (S$20.00 due)'), 'the top-up is due');
  await click(button('Add payment', modal()));
  const sel = paymentSelects()[0];
  const names = [...sel.options].map(o => o.textContent);
  assert.ok(names.includes('Cash') && names.includes('Card'), names.join('|'));
  assert.ok(!names.some(n => n.startsWith('Wallet')), `a Wallet method is offered: ${names.join('|')}`);
  assert.ok(names.includes('Instalment'), 'product exchanges keep their instalment');
  assert.equal(sel.value, 'm-cash', 'the first payment defaults to a normal method');
});

test('money entered on a row with no method is refused, not counted and dropped', async () => {
  await openOnInvoice();
  const ret = [...modal().querySelectorAll('label')].find(l => l.textContent.includes('XM A × 1'));
  await click(ret.querySelector('input'));
  await pickSearch('Search product name or SKU', 'XM C — S$120.00 (stock 50)');
  await click(button('Add payment', modal()));
  await click(button('Add payment', modal()));
  const sels = paymentSelects();
  const amounts = [...modal().querySelectorAll('input[placeholder="Amount"]')];
  await setValue(amounts[0], '10');
  await setValue(sels[1], '');            // left on "— Method —"
  await setValue(amounts[1], '10');
  await readyToConfirm();
  await click(button('Complete Exchange'));
  assert.ok(text().includes('Choose a payment method for the S$10.00 entered, or remove that payment.'), text().slice(0, 600));
  assert.equal(document.querySelectorAll('.modal').length, 1, 'no confirmation opens');
  assert.equal(callsOf('create_exchange_with_details').length, 0);
  // with a method chosen it goes through, and both payments are sent
  await setValue(paymentSelects()[1], 'm-card');
  await click(button('Complete Exchange'));
  await setValue(modal().querySelector('input[placeholder="Owner One"]'), 'Owner One');
  await click(button('Confirm & Complete'));
  const sent = callsOf('create_exchange_with_details');
  assert.equal(sent.length, 1);
  assert.deepEqual(sent[0].args.p_payload.payments.map(p => [p.payment_method_id, p.amount]), [['m-cash', 10], ['m-card', 10]]);
});

test('a whole bundle shows the server\'s figures, and is paid exactly, now, by a normal method', async () => {
  await openOnInvoice();
  await click(button('Whole bundle', modal()));
  const lines = selectWithOption('XM Bundle AB × 1');
  const opt = id => [...lines.options].find(o => o.value === id);
  assert.ok(opt('li-ab2').disabled && opt('li-ab2').textContent.includes('2 bundles on this line: use Bundle component'));
  assert.ok(opt('li-ab3').disabled && opt('li-ab3').textContent.includes('an item was already exchanged on its own'));
  assert.ok(!opt('li-ab').disabled);
  await setValue(lines, 'li-ab');
  await pickSearch('Search bundle name, code or price', 'XM Bundle CCC — S$300.00');
  const asked = callsOf('exchange_bundle_preview').at(-1);
  assert.deepEqual(asked.args, { p_original_invoice_id: 'inv-1', p_processing_store_id: 'st-1',
    p_original_invoice_item_id: 'li-ab', p_new_promotion_id: 'pr-ccc' });
  for (const s of ["Returned bundle, today's valueS$250.00", 'Returned bundle, what was paidS$200.00',
                   'Exchange credit (the lower of the two)S$200.00', 'Replacement bundleS$360.00',
                   'Additional charge (paid in full now)S$160.00', 'Back to stock: XM A ×1, XM B ×1', 'Out of stock: XM C ×3']) {
    assert.ok(text().includes(s), `missing: ${s}`);
  }
  assert.ok(text().includes('Additional payment (S$160.00 due) — exactly this amount, now'));
  await click(button('Add payment', modal()));
  const sel = paymentSelects()[0];
  const names = [...sel.options].map(o => o.textContent);
  assert.ok(!names.some(n => n.startsWith('Wallet')), `a Wallet method is offered: ${names.join('|')}`);
  assert.ok(!names.includes('Instalment'), 'a whole bundle is not paid by instalment');
  const amount = modal().querySelector('input[placeholder="Amount"]');
  assert.equal(amount.value, '160');
  await readyToConfirm();

  // short: refused on the page, nothing sent
  await setValue(amount, '100');
  await click(button('Complete Exchange'));
  assert.ok(text().includes('This exchange needs exactly S$160.00 paid now (S$100.00 entered).'), text().slice(0, 400));
  assert.equal(callsOf('create_exchange_with_details').length, 0);

  // exact: confirmed with the figures, and sent as entered
  await setValue(amount, '160');
  await click(button('Complete Exchange'));
  assert.ok(modal().textContent.includes('Credit S$200.00 · Replacement S$360.00 · S$160.00 paid now'), modal().textContent);
  await setValue(modal().querySelector('input[placeholder="Owner One"]'), 'Owner One');
  await click(button('Confirm & Complete'));
  const sent = callsOf('create_exchange_with_details');
  assert.equal(sent.length, 1);
  assert.equal(sent[0].args.p_kind, 'bundle');
  assert.deepEqual(sent[0].args.p_payload.payments, [{ payment_method_id: 'm-cash', amount: 160, reference: '' }]);
  assert.equal(sent[0].args.p_payload.new_promotion_id, 'pr-ccc');
  assert.deepEqual(sent[0].args.p_payload.affiliate, { mode: 'inherit' });
  assert.ok(alerts.at(-1).includes('EXB-20261009-abc123'));
});

test('a swap the server refuses is shown with its reason and never sent', async () => {
  await openOnInvoice();
  await click(button('Whole bundle', modal()));
  await setValue(selectWithOption('XM Bundle AB × 1'), 'li-ab');
  await pickSearch('Search bundle name, code or price', 'XM Bundle Treat — S$90.00');
  assert.ok(modal().querySelector('.alert-danger')?.textContent.includes(BENEFIT));
  assert.ok(!text().includes('Additional payment ('), 'no payment is asked for a refused swap');
  await readyToConfirm();
  await click(button('Complete Exchange'));
  assert.ok([...document.querySelectorAll('.alert-danger')].some(a => a.textContent.includes(BENEFIT)));
  assert.equal(document.querySelectorAll('.modal').length, 1, 'no confirmation opens');
  assert.equal(callsOf('create_exchange_with_details').length, 0);
});

test('the affiliate picker says the exchange keeps the original sale\'s affiliate when left empty', async () => {
  await openOnInvoice();
  assert.ok(text().includes("Left empty, this exchange keeps the original sale's affiliate (Pat Referrer)."), text().slice(-1500));
  assert.ok([...modal().querySelectorAll('button')].some(b => b.textContent.includes('Same as the original sale (Pat Referrer)')));
});

// ── 424 ────────────────────────────────────────────────────────────────────
const SG_TODAY = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const returnLine = async label => {
  const l = [...modal().querySelectorAll('label')].find(x => x.textContent.includes(label));
  assert.ok(l, `no line to return: ${label}`);
  await click(l.querySelector('input'));
};

test('a discounted item counts for what was paid, and the page shows both figures', async () => {
  await openOnInvoice();
  const line = [...modal().querySelectorAll('label')].find(x => x.textContent.includes('XM B × 1'));
  assert.ok(line.textContent.includes('paid S$60.00 · today S$100.00'), line.textContent);
  await returnLine('XM B × 1');
  await pickSearch('Search product name or SKU', 'XM C — S$120.00 (stock 50)');
  for (const t of ["Returned, today's priceS$100.00", 'Returned, what was paidS$60.00',
                   'Exchange credit (the lower of the two)S$60.00',
                   "Counts for what was paid (S$60.00), which is less than today's price (S$100.00).",
                   'Additional payment (S$60.00 due)']) {
    assert.ok(text().includes(t), `missing: ${t}`);
  }
  await click(button('Add payment', modal()));
  assert.equal(modal().querySelector('input[placeholder="Amount"]').value, '60');
  await readyToConfirm();
  await click(button('Complete Exchange'));
  assert.ok(modal().textContent.includes('Credit S$60.00 · Replacement S$120.00 · S$60.00 paid now'), modal().textContent);
  await setValue(modal().querySelector('input[placeholder="Owner One"]'), 'Owner One');
  await click(button('Confirm & Complete'));
  const sent = callsOf('create_exchange_with_details');
  assert.equal(sent.length, 1);
  assert.deepEqual(sent[0].args.p_payload.returned, [{ invoice_item_id: 'li-b', quantity: 1 }]);
  assert.deepEqual(sent[0].args.p_payload.payments, [{ payment_method_id: 'm-cash', amount: 60, reference: '' }]);
  assert.equal(sent[0].args.p_payload.instalment, null);
  const asked = callsOf('exchange_credit_preview').at(-1);
  assert.deepEqual(asked.args, { p_original_invoice_id: 'inv-1', p_processing_store_id: 'st-1' });
});

test('one item of a bundle counts for its share of what the bundle was paid', async () => {
  await openOnInvoice();
  await click(button('Bundle component', modal()));
  await setValue(selectWithOption('XM Bundle AB × 1'), 'li-ab');
  await setValue(selectWithOption('— Select component —'), 'p-a');
  await pickSearch('Search product name or SKU', 'XM C — S$120.00 (stock 50)');
  for (const t of ['Exchange credit (the lower of the two)S$75.00', 'Returned, its share of what the bundle was paidS$75.00',
                   "Counts for its share of what the bundle was paid (S$75.00), which is less than today's price (S$100.00).",
                   'Additional payment (S$45.00 due)']) {
    assert.ok(text().includes(t), `missing: ${t}`);
  }
  // The bundle's whole price is never called what was paid for one item.
  assert.ok(!text().includes('Returned, what was paid'), 'the item\'s share is labelled as what was paid');
});

test('without the server\'s figures nothing is valued or sent', async () => {
  await mount();
  backend.previewFails = true;
  await click(button('New Exchange'));
  await setValue(selectWithOption('XM Store'), 'st-1');
  await setValue(modal().querySelector('input[placeholder="Enter invoice number"]'), 'INV-T-0001');
  await click(button('Find', modal()));
  await returnLine('XM A × 1');
  await pickSearch('Search product name or SKU', 'XM C — S$120.00 (stock 50)');
  await readyToConfirm();
  await click(button('Complete Exchange'));
  assert.ok([...document.querySelectorAll('.alert-danger')].some(a =>
    a.textContent.includes('What the returned items count for could not be worked out. Refresh the page and try again.')));
  assert.equal(document.querySelectorAll('.modal').length, 1, 'no confirmation opens');
  assert.equal(callsOf('create_exchange_with_details').length, 0);
});

test('an instalment sends its method and months for the replacement invoice; nothing is left owed', async () => {
  await openOnInvoice();
  await returnLine('XM A × 1');
  await pickSearch('Search product name or SKU', 'XM C — S$120.00 (stock 50)');
  await click(button('Add payment', modal()));
  await setValue(paymentSelects()[0], 'instalment');
  await click(modal().querySelector('button[aria-label="Actual payment method"]'));
  await click([...modal().querySelectorAll('[role="option"]')].find(o => o.textContent === 'Card'));
  await click([...modal().querySelectorAll('.instalment-months button')].find(b => b.textContent === '6'));
  assert.ok(!text().includes('Outstanding'), 'the wizard still shows an Outstanding line');
  assert.ok(!text().includes('stays owed'), 'the wizard still says a balance stays owed');
  await readyToConfirm();
  await click(button('Complete Exchange'));
  await setValue(modal().querySelector('input[placeholder="Owner One"]'), 'Owner One');
  await click(button('Confirm & Complete'));
  const sent = callsOf('create_exchange_with_details');
  assert.equal(sent.length, 1, text().slice(0, 600));
  assert.deepEqual(sent[0].args.p_payload.payments, [{ payment_method_id: 'm-card', amount: 20, reference: '' }]);
  assert.deepEqual(sent[0].args.p_payload.instalment, { method_id: 'm-card', months: 6 });
});

test('the next exchange starts empty: staff, affiliate, issuer and date', async () => {
  await openOnInvoice();
  await pickSearch('Who is issuing this exchange', 'Owner One');
  await setValue(modal().querySelector('input[type="date"]'), '2026-10-01');
  const staff = [...modal().querySelectorAll('label')].find(l => l.textContent.trim() === 'Staff C');
  await click(staff.querySelector('input'));
  await click(button('Cancel', modal()));
  assert.equal(document.querySelectorAll('.modal').length, 0);
  // a walk-in sale (no customer) used to keep the last exchange's date
  await click(button('New Exchange'));
  await setValue(selectWithOption('XM Store'), 'st-1');
  await setValue(modal().querySelector('input[placeholder="Enter invoice number"]'), 'INV-T-0002');
  await click(button('Find', modal()));
  assert.equal(modal().querySelector('input[type="date"]').value, SG_TODAY);
  assert.ok([...modal().querySelectorAll('button')].some(b => b.textContent.trim().startsWith('Who is issuing this exchange')),
    'Raised by kept the last exchange\'s choice');
  assert.ok(![...modal().querySelectorAll('.exchange-staff input')].some(i => i.checked), 'a staff member is still ticked');
});

test('the list and the export show the exchange date, else the Singapore day it was saved', async () => {
  await mount();
  const rows = [...document.querySelectorAll('tbody tr')].map(tr => tr.textContent);
  assert.ok(rows.some(t => t.includes('EX-T-0001') && t.includes('5 Oct 2026')), rows.join(' | '));
  assert.ok(rows.some(t => t.includes('EX-T-0002') && t.includes('9 Oct 2026')), rows.join(' | '));
});

test('only promotions on sale today are offered as the replacement bundle', async () => {
  await openOnInvoice();
  await click(button('Whole bundle', modal()));
  await setValue(selectWithOption('XM Bundle AB × 1'), 'li-ab');
  await click([...modal().querySelectorAll('button')].find(b => b.textContent.trim().startsWith('Search bundle name, code or price')));
  const offered = modal().textContent;
  assert.ok(offered.includes('XM Bundle CCC — S$300.00'));
  assert.ok(!offered.includes('XM Bundle Old'), 'an ended promotion is offered');
  assert.ok(!offered.includes('XM Bundle Soon'), 'a promotion that has not started is offered');
});

// ── 424: the day the sale counts on (the Owner, 9 Oct 2026) ───────────────
const FIRST = `${SG_TODAY.slice(0, 7)}-01`;
const PREV_MONTH_END = (() => { const d = new Date(`${FIRST}T00:00:00Z`); d.setUTCDate(0); return d.toISOString().slice(0, 10); })();
const dateInput = () => modal().querySelector('input[type="date"]');
const dangerText = () => [...document.querySelectorAll('.alert-danger')].map(a => a.textContent).join(' | ');

test('the exchange date runs from the 1st of this month, and the sale counts on it', async () => {
  await openOnInvoice();
  assert.equal(dateInput().min, FIRST);
  assert.equal(dateInput().max, SG_TODAY);
  for (const t of ['The replacement sale counts on this date in the sales reports, commission and Xero.',
                   'The earliest is the 1st of this month, so a month already sent to Xero never changes.',
                   'It cannot be before the original sale.']) {
    assert.ok(text().includes(t), `missing: ${t}`);
  }
  assert.ok(!text().includes('dated the day you save it'), 'the old wording is still shown');
  await returnLine('XM A × 1');
  await pickSearch('Search product name or SKU', 'XM C — S$120.00 (stock 50)');
  await click(button('Add payment', modal()));
  await readyToConfirm();
  // The month before: refused here, and never sent.
  await setValue(dateInput(), PREV_MONTH_END);
  await click(button('Complete Exchange'));
  assert.ok(dangerText().includes(`An exchange can be dated from the 1st of this month (${displayDay(FIRST)}) at the earliest. An earlier month may already be in Xero.`),
    dangerText());
  assert.equal(document.querySelectorAll('.modal').length, 1, 'no confirmation opens');
  // The 1st: taken, and the screen says the day it counts on.
  await setValue(dateInput(), FIRST);
  const backdated = FIRST < SG_TODAY;
  const counts = `This exchange counts on ${displayDay(FIRST)} in the sales reports, commission and Xero, not on the day you save it.`;
  if (backdated) assert.ok(text().includes(counts), `missing: ${counts}`);
  await click(button('Complete Exchange'));
  if (backdated) assert.ok(modal().textContent.includes(counts), 'the confirmation does not say the day it counts on');
  await setValue(modal().querySelector('input[placeholder="Owner One"]'), 'Owner One');
  await click(button('Confirm & Complete'));
  const sent = callsOf('create_exchange_with_details');
  assert.equal(sent.length, 1, dangerText());
  assert.equal(sent[0].args.p_payload.exchange_date, FIRST);
});

test('an exchange cannot be dated before the original sale', async () => {
  await mount();
  backend.fx.invoices[0].business_date = SG_TODAY;   // the sale was today
  await click(button('New Exchange'));
  await setValue(selectWithOption('XM Store'), 'st-1');
  await setValue(modal().querySelector('input[placeholder="Enter invoice number"]'), 'INV-T-0001');
  await click(button('Find', modal()));
  assert.equal(dateInput().min, SG_TODAY);
  if (FIRST < SG_TODAY) {
    await returnLine('XM A × 1');
    await pickSearch('Search product name or SKU', 'XM C — S$120.00 (stock 50)');
    await click(button('Add payment', modal()));
    await readyToConfirm();
    await setValue(dateInput(), FIRST);
    await click(button('Complete Exchange'));
    assert.ok(dangerText().includes(`An exchange cannot be dated before the original sale (${displayDay(SG_TODAY)}).`), dangerText());
    assert.equal(callsOf('create_exchange_with_details').length, 0);
  }
});
