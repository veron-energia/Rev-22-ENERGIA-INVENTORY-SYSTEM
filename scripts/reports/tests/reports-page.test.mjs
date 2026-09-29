// The Reports page, rendered for real against a fake backend.
//
// The actual src/pages/ReportsPage.tsx is bundled with esbuild and mounted in
// jsdom. Only the Supabase client, the auth context and xlsx are stubbed: the
// client by a small in-memory PostgREST (filters, ordering, the 1,000-row cap),
// xlsx so an export is captured instead of written. Every name, phone and
// amount below is invented.
//
// It checks what the page promises: separately loaded reports fail on their
// own tab only and never show as empty, periods reach the reports that take
// them, the figures follow the owner's rules (tier-1 commission on the listed
// invoices, Outstanding = Earned − Paid Out, voucher uses read from the sale
// invoices), and every export carries the headings of the table on screen.
//
// Run: node --test scripts/reports/tests/reports-page.test.mjs
process.env.TZ = 'America/Los_Angeles'; // west of UTC, where a date-only value parsed as a Date shows a day early

import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import { settlementPeriod, toIsoDate } from '../../../src/lib/tiktok/settlementPeriod.mjs';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

// ── the page, bundled ──────────────────────────────────────────────────────
const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url: 'https://reports.invalid', pretendToBeVisual: true });
for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'Element', 'Node', 'Event', 'KeyboardEvent',
  'MouseEvent', 'getComputedStyle', 'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver']) {
  Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
}
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
// Bundled as ESM, React's act() queues each task on a new MessageChannel and
// never closes it; Node's ports then keep the runner alive after the last test.
// The same hand-off on setImmediate holds nothing open.
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
      export { default as ReportsPage } from './src/pages/ReportsPage';
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
    b.onResolve({ filter: /^xlsx$/ }, () => ({ path: 'xlsx', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { from: (...a) => globalThis.__backend.client.from(...a), rpc: (...a) => globalThis.__backend.client.rpc(...a) };' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
    b.onLoad({ filter: /^xlsx$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const utils = {
        json_to_sheet: (body, opts) => ({ body, header: opts && opts.header }),
        book_new: () => ({ sheets: [] }),
        book_append_sheet: (wb, ws, name) => { wb.sheets.push({ ws, name }); },
      };
      export const writeFile = (wb, filename) => { globalThis.__exports.push({ filename, sheet: wb.sheets[0] }); };` }));
  } }],
});
const { ReportsPage, createRoot, act, React, ErrorBoundary } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const sgtDate = iso => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(iso));

function makeFixture({ extraCustomers = 0 } = {}) {
  const stores = [{ id: 'st-1', name: 'North Store' }, { id: 'st-2', name: 'South Store' }];
  const warehouses = [{ id: 'wh-1', name: 'Main Warehouse' }, { id: 'wh-2', name: 'Overflow Warehouse' }];
  const products = [
    { id: 'p-1', name: 'Product Alpha', deleted_at: null }, { id: 'p-2', name: 'Product Beta', deleted_at: null },
    { id: 'p-3', name: 'Product Gamma', deleted_at: null }, { id: 'p-4', name: 'Product Retired', deleted_at: '2026-09-01T00:00:00Z' },
  ];
  const profiles = [{ id: 'u-0', full_name: 'Owner User', role: 'owner' }, { id: 'u-1', full_name: 'Staff One', role: 'staff' }, { id: 'u-2', full_name: 'Staff Two', role: 'manager' }];
  // c-07 has been deleted: the customers table (RLS) no longer returns them.
  const customers = Array.from({ length: 6 }, (_, i) => ({
    id: `c-0${i + 1}`, full_name: `Customer 0${i + 1}`, phone: `+65 9123 000${i + 1}`,
    date_of_birth: i % 2 ? '1990-01-15' : null, gender: ['female', 'male', 'other', null, 'female', 'male'][i],
    gender_other: i === 2 ? 'Prefer not to say' : null, occupation: i % 3 === 0 ? 'Engineer' : null,
  }));
  for (let i = 0; i < extraCustomers; i++) customers.push({ id: `cx-${String(i).padStart(6, '0')}`, full_name: `Customer X${i}`,
    phone: `+65 9123 ${String(i % 10000).padStart(4, '0')}`, date_of_birth: null, gender: 'female', gender_other: null, occupation: null });
  // v-9 and pr-9 have been deleted from the catalogue.
  const vouchers = [{ id: 'v-1', name: 'Voucher Facial', voucher_kind: 'single' }];
  const promotions = [{ id: 'pr-1', name: 'Promo Bundle', code: 'PROMO1' }];
  const specialProducts = [{ id: 'sp-1', name: 'Special Device' }];

  const invoices = [], items = [], ledger = [];
  const inv = (n, store, cust, creator, status, date, total, lines, events, extra = {}) => {
    const id = `inv-${String(n).padStart(2, '0')}`;
    invoices.push({ id, invoice_no: `INV-2026-${String(n).padStart(4, '0')}`, store_id: store, customer_id: cust, created_by: creator, status,
      subtotal: total, discount_total: 0, manual_discount: 0, save_earth_applied: false, save_earth_amount: 0, discount_voucher_id: null,
      total_amount: total, business_date: date, deleted_at: null, ...extra });
    lines.forEach((l, i) => items.push({ id: `${id}-l${i + 1}`, invoice_id: id, product_id: null, special_product_id: null, voucher_id: null,
      promotion_id: null, topup_amount: 0, line_discount: 0, line_voucher_id: null, ...l }));
    // The ledger counts sales only (invoice_counts_as_sale), so cancelled invoices have no events.
    events.forEach(([event_id, sales_date, amount, event_kind]) => ledger.push({ invoice_id: id, event_id, sales_date, amount, event_kind }));
  };
  inv(1, 'st-1', 'c-01', 'u-1', 'paid', '2026-08-05', 200, [{ product_id: 'p-1', quantity: 2, line_total: 200, line_kind: 'product' }], [['ev-01', '2026-08-05', 200, 'receipt']]);
  inv(2, 'st-1', 'c-02', 'u-1', 'paid', '2026-08-12', 200, [{ product_id: 'p-2', quantity: 1, line_total: 150, line_kind: 'product' },
    { voucher_id: 'v-1', quantity: 1, line_total: 50, line_kind: 'voucher' }], [['ev-02', '2026-08-12', 200, 'receipt'], ['rf-02', '2026-09-11', -10, 'refund']]);
  inv(3, 'st-2', 'c-03', 'u-2', 'paid', '2026-08-20', 300, [{ promotion_id: 'pr-1', quantity: 1, line_total: 300, topup_amount: 20, line_kind: 'promotion' }],
    [['ev-03a', '2026-08-20', 100, 'receipt'], ['ev-03b', '2026-09-03', 200, 'receipt']]);
  inv(4, 'st-2', 'c-01', 'u-2', 'paid', '2026-08-28', 180, [{ product_id: 'p-1', quantity: 1, line_total: 100, line_kind: 'product' },
    { product_id: 'p-3', quantity: 1, line_total: 80, line_kind: 'product' }], [['ev-04', '2026-08-28', 180, 'receipt'], ['rf-04', '2026-09-10', -80, 'refund']]);
  inv(5, 'st-1', 'c-04', 'u-1', 'paid', '2026-09-02', 500, [{ special_product_id: 'sp-1', quantity: 1, line_total: 500, line_kind: 'special_product' }], [['ev-05', '2026-09-02', 500, 'receipt']]);
  inv(6, 'st-1', 'c-05', 'u-1', 'paid', '2026-09-05', 60, [{ special_product_id: 'sp-1', quantity: 1, line_total: 60, line_kind: 'rental' }], [['ev-06', '2026-09-05', 60, 'receipt']]);
  inv(7, 'st-2', 'c-02', 'u-2', 'paid', '2026-09-15', 400, [{ product_id: 'p-2', quantity: 3, line_total: 450, line_discount: 50, line_kind: 'product' }], [['ev-07', '2026-09-15', 400, 'receipt']]);
  inv(8, 'st-1', 'c-03', 'u-1', 'paid', '2026-09-20', 100, [{ product_id: 'p-1', quantity: 1, line_total: 100, line_kind: 'product' }],
    [['ev-08a', '2026-09-20', 100, 'receipt'], ['ev-08b', '2026-09-21', -100, 'correction_reversal'], ['ev-08c', '2026-09-21', 100, 'correction_replacement']]);
  inv(9, 'st-2', 'c-06', 'u-2', 'completed_foc', '2026-09-25', 0, [{ product_id: 'p-3', quantity: 1, line_total: 0, line_kind: 'product' }], []);
  inv(10, 'st-1', 'c-01', 'u-1', 'unpaid', '2026-09-26', 250, [{ product_id: 'p-2', quantity: 1, line_total: 250, line_kind: 'product' }], []);
  // A deleted customer's sale, with a line redeemed with v-1 (a use worth 10).
  inv(11, 'st-1', 'c-07', 'u-1', 'paid', '2026-09-16', 90, [{ product_id: 'p-3', quantity: 1, line_total: 100, line_discount: 10, line_voucher_id: 'v-1', line_kind: 'product' }],
    [['ev-11', '2026-09-16', 90, 'receipt']]);
  // v-1 as an invoice-level discount: 30 total − 5 manual − 0 line = 25.
  inv(12, 'st-2', 'c-04', 'u-2', 'paid', '2026-09-18', 220, [{ product_id: 'p-2', quantity: 1, line_total: 250, line_kind: 'product' }],
    [['ev-12', '2026-09-18', 220, 'receipt']], { discount_voucher_id: 'v-1', discount_total: 30, manual_discount: 5, subtotal: 250 });
  // A voucher and a promotion since deleted from the catalogue.
  inv(13, 'st-1', 'c-05', 'u-1', 'paid', '2026-09-19', 100, [{ voucher_id: 'v-9', quantity: 1, line_total: 40, line_kind: 'voucher' },
    { promotion_id: 'pr-9', quantity: 1, line_total: 60, line_kind: 'promotion' }], [['ev-13', '2026-09-19', 100, 'receipt']]);
  // Cancelled: its voucher use is not a sale.
  inv(14, 'st-1', 'c-02', 'u-1', 'cancelled', '2026-09-21', 85, [{ product_id: 'p-1', quantity: 1, line_total: 100, line_discount: 15, line_voucher_id: 'v-1', line_kind: 'product' }], []);

  const refunds = [
    { id: 'rf-02', invoice_id: 'inv-02', request_id: 'rq-02', amount: 10, credit_returned: 0, outcome: null },
    { id: 'rf-04', invoice_id: 'inv-04', request_id: 'rq-04', amount: 80, credit_returned: 0, outcome: { lines: [{ invoice_item_id: 'inv-04-l2', amount: 80 }] } },
  ];
  const commissions = [
    { id: 'cm-1', referrer_customer_id: 'c-06', invoice_id: 'inv-02', tier: 'tier1', status: 'paid', commission_amount: 20 },
    { id: 'cm-2', referrer_customer_id: 'c-06', invoice_id: 'inv-07', tier: 'tier1', status: 'earned', commission_amount: 40 },
    { id: 'cm-3', referrer_customer_id: 'c-05', invoice_id: 'inv-07', tier: 'tier2', status: 'earned', commission_amount: 10 },
    { id: 'cm-4', referrer_customer_id: 'c-06', invoice_id: 'inv-04', tier: 'tier1', status: 'reversed', commission_amount: 15 },
    { id: 'cm-5', referrer_customer_id: 'c-06', invoice_id: 'inv-05', tier: 'tier2', status: 'earned', commission_amount: 7 },
    { id: 'cm-6', referrer_customer_id: 'c-07', invoice_id: 'inv-12', tier: 'tier1', status: 'reversed', commission_amount: 12 },
  ];
  const specialSales = [{ id: 'ss-1', special_product_id: 'sp-1', invoice_id: null, status: 'paid', created_at: '2026-09-10T03:00:00Z', total_amount: 700 }];
  const rentals = [{ id: 'rn-1', special_product_id: 'sp-1', invoice_id: null, status: 'returned', created_at: '2026-09-12T02:00:00Z', paid_at: '2026-09-12T02:00:00Z', returned_at: '2026-09-19T05:00:00Z', rental_fee: 90, late_fee_total: 15 }];
  const whInv = [
    { id: 'wi-1', warehouse_id: 'wh-1', product_id: 'p-1', current_qty: 50 }, { id: 'wi-2', warehouse_id: 'wh-1', product_id: 'p-2', current_qty: 0 },
    { id: 'wi-3', warehouse_id: 'wh-1', product_id: 'p-3', current_qty: 10 }, { id: 'wi-4', warehouse_id: 'wh-2', product_id: 'p-1', current_qty: 5 },
    { id: 'wi-5', warehouse_id: 'wh-2', product_id: 'p-4', current_qty: 9 },
  ];
  const stInv = [{ id: 'si-1', store_id: 'st-1', product_id: 'p-1', current_qty: 3 }, { id: 'si-2', store_id: 'st-1', product_id: 'p-4', current_qty: 7 }];

  const affiliates = [
    { customer_id: 'c-05', customer_name: 'Customer 05', member_id: null, affiliate_state: 'blocked', block_reason: 'Not verified', store_name: null,
      direct_referrals: 0, downline: 0, earned: 10, paid: 0, reversed: 0, blocked: 10, tier1_earned: 0, tier2_earned: 10 },
    { customer_id: 'c-06', customer_name: 'Customer 06', member_id: null, affiliate_state: 'active', block_reason: null, store_name: 'North Store',
      direct_referrals: 2, downline: 1, earned: 67, paid: 12, reversed: 15, blocked: 0, tier1_earned: 60, tier2_earned: 7 },
    { customer_id: 'c-10', customer_name: 'Customer 00', member_id: null, affiliate_state: 'active', block_reason: null, store_name: 'South Store',
      direct_referrals: 1, downline: 0, earned: 0, paid: 0, reversed: 0, blocked: 0, tier1_earned: 0, tier2_earned: 0 },
  ];
  const therapy = [{ entitlement_no: 'UTP-T001', customer_name: 'Customer 01', package_name: '3 months - Unlimited', store_name: 'North Store', price_snapshot: 300,
    price_mode: 'member', purchase_date: '2026-09-01', activation_deadline: '2026-10-01', activation_date: '2026-09-02', expiry_date: '2026-12-02', status: 'active', is_legacy: false }];
  const sources = [
    { source_label: 'Walk in', is_active: true, customers_count: 4, surveys_count: 3 },
    { source_label: 'Facebook', is_active: false, customers_count: 2, surveys_count: 0 },
  ];
  const tt = (row_id, financial_date, id, txn_class, match_status, settlement, revenue, fee, reconciled) => ({ row_id, store_name: 'North Store', financial_date,
    order_adjustment_id: id, txn_class, transaction_type: txn_class, finance_category: null, matched_order_id: null, match_status,
    settlement_amount: settlement, revenue_amount: revenue, fee_amount: fee, adjustment_amount: 0, refund_amount: 0, currency: 'SGD', reconciled, version_no: 1 });
  const ttSettlement = [
    tt('tt-1', '2026-08-27', 'ORD-1', 'order', 'matched', 180, 200, 20, true),
    tt('tt-2', '2026-09-03', 'ORD-2', 'order', 'pending', 340.5, 400, 59.5, false),
    tt('tt-3', '2026-09-04', 'ADJ-1', 'adjustment', 'matched', 0, 0, 0, null),
    tt('tt-4', '2026-09-05', 'ADS-1', 'finance', 'no_match_needed', -25, 0, 0, true),
    tt('tt-5', null, 'ORD-5', 'order', 'matched', 10, 12, 2, true),
  ];
  const ttSummary = [{ total_settlement: 505.5, total_revenue: 612, total_fees: -81.5, total_adjustments: 0, total_refunds: 0,
    transactions: 5, matched_count: 3, pending_count: 1, unreconciled_count: 1 }];
  const ttDaily = [{ day: '2026-09-03', transactions: 1, settlement: 340.5, revenue: 400, fees: 59.5, expense: 0, income: 340.5 }];
  const ttByStore = [{ store_name: 'North Store', transactions: 2, settlement: 520.5, revenue: 600, fees: 79.5, expense: 0, income: 520.5, pending_count: 1, unreconciled_count: 1 }];
  const ttQty = [{ dimension: 'sku', item_key: 'SKU-1', item_name: 'SKU-1', orders: 1, net_units: 1 }, { dimension: 'product', item_key: 'p-1', item_name: 'Product Alpha', orders: 2, net_units: 3 }];
  const ttStatus = [{ order_status: 'Shipped', order_items: 1, net_deducted: 1 }, { order_status: 'Completed', order_items: 3, net_deducted: 3 }];
  const exchanges = [
    { exchange_id: 'ex-1', exchange_no: 'EX-0001', invoice_no: 'INV-2026-0001', store_name: 'North Store', customer_name: 'Customer 04',
      created_at: '2026-08-18T03:00:00Z', returned_credit: 120, replacement_total: 150, topup_amount: 30, nonrefundable_amount: 0, is_foc: false, foc_amount: 0 },
    { exchange_id: 'ex-2', exchange_no: 'EX-0002', invoice_no: null, store_name: 'South Store', customer_name: null,
      created_at: '2026-09-18T03:00:00Z', returned_credit: 80, replacement_total: 80, topup_amount: 0, nonrefundable_amount: 5, is_foc: true, foc_amount: 10 },
  ];
  const trReceipts = [
    { transfer_id: 'tr-1', transfer_type: 'warehouse_to_store', source_name: 'Main Warehouse', dest_name: 'North Store', status: 'received',
      dispatched_at: '2026-08-10T02:00:00Z', received_at: '2026-08-11T05:00:00Z', received_by_name: 'Staff One', line_count: 2, received_units: 10, had_discrepancy: true, discrepancy_resolved: false },
    { transfer_id: 'tr-2', transfer_type: 'warehouse_to_store', source_name: 'Overflow Warehouse', dest_name: 'South Store', status: 'received',
      dispatched_at: '2026-09-01T02:00:00Z', received_at: '2026-09-02T05:00:00Z', received_by_name: 'Staff Two', line_count: 1, received_units: 4, had_discrepancy: false, discrepancy_resolved: false },
  ];
  const trDisc = [{ transfer_id: 'tr-1', dest_name: 'North Store', product_id: 'p-1', product_name: 'Product Alpha', approved_quantity: 6, received_quantity: 5,
    discrepancy: -1, status: 'open', resolution: null, discrepancy_reason: 'Damaged', received_at: '2026-08-11T05:00:00Z', resolved_at: null }];
  const trOverdue = [{ transfer_id: 'tr-3', transfer_type: 'warehouse_to_store', source_name: 'Main Warehouse', dest_name: 'South Store',
    dispatched_at: '2026-09-10T02:00:00Z', days_in_transit: 18, line_count: 1, units_in_transit: 4 }];
  return { stores, warehouses, products, profiles, customers, vouchers, promotions, specialProducts, invoices, items, ledger, refunds, commissions,
    specialSales, rentals, whInv, stInv, affiliates, therapy, sources, ttSettlement, ttSummary, ttDaily, ttByStore, ttQty, ttStatus, exchanges,
    trReceipts, trDisc, trOverdue };
}

// ── fake backend ───────────────────────────────────────────────────────────
function createBackend(fx) {
  const b = { calls: [], failures: new Map(), held: new Set(), waiters: [], release() { const w = b.waiters; b.waiters = []; w.forEach(f => f()); } };
  const inPeriod = (d, from, to) => !!d && (!from || d >= from) && (!to || d <= to);
  const tables = {
    invoices: fx.invoices, stores: fx.stores, products: fx.products, commissions: fx.commissions, customers: fx.customers, warehouses: fx.warehouses,
    warehouse_inventory: fx.whInv, store_inventory: fx.stInv, invoice_items: fx.items, vouchers: fx.vouchers, promotions: fx.promotions,
    special_sales: fx.specialSales, rentals: fx.rentals, special_products: fx.specialProducts, profiles: fx.profiles, invoice_refunds: fx.refunds,
    // Present, but the page must not read it (voucher uses come from the invoices).
    voucher_redemptions: [{ id: 'rd-1', voucher_id: 'v-1', invoice_id: 'inv-14', created_at: '2026-09-21T03:00:00Z', discount_applied: 15 }],
  };
  const rpcs = {
    invoice_sales_ledger: () => fx.ledger,
    report_affiliates: () => fx.affiliates,
    report_therapy: () => fx.therapy,
    report_customer_sources: () => fx.sources,
    report_tiktok_settlement_summary: () => fx.ttSummary,
    report_tiktok_settlement: () => fx.ttSettlement,
    report_sales_by_service_staff: a => {
      const ev = fx.ledger.filter(e => inPeriod(e.sales_date, a?.p_from, a?.p_to));
      const revenue = ev.reduce((s, e) => s + e.amount, 0);
      return { revenue, backfill_in: 0, backfill_out: 0, staff_total: revenue, credited_as_creator: 0, wallet_credit_not_counted: 0, difference: 0,
        rows: [{ staff_id: 'u-1', staff_name: 'Staff One', is_active: true, invoices_served: new Set(ev.map(e => e.invoice_id)).size,
          shared_sales: revenue, receipts_on_invoices_served: revenue, credited_as_creator: 0, backfilled_in: 0 }] };
    },
    report_pricing: () => [{ invoice_id: 'inv-01', invoice_no: 'INV-2026-0001', paid_date: '2026-08-05', store_name: 'North Store', customer_name: 'Customer 01',
      line_kind: 'product', item_name: 'Product Alpha', quantity: 2, unit_price: 100 }],
    report_discounts: () => [{ invoice_id: 'inv-12', invoice_no: 'INV-2026-0012', paid_date: '2026-09-18', store_name: 'South Store', staff_names: 'Staff Two',
      customer_name: 'Customer 04', save_earth: 0, voucher_discount: 25, promotion_discount: 0, line_discount: 0, manual_discount: 5, total_discount: 30 }],
    report_foc_lines: () => [{ invoice_id: 'inv-09', invoice_no: 'INV-2026-0009', customer_name: 'Customer 06', line_kind: 'product', description: 'Product Gamma',
      quantity: 1, foc_quantity: 1, normal_value: 80, foc_value: 80, charged_value: 0, foc_reason: 'Goodwill', foc_by_name: 'Staff Two', settled_at: '2026-09-24T17:00:00Z' }],
    report_foc_summary: () => ({ normal_value: 80, foc_value: 80, charged_value: 0, full_foc_invoices: 1, mixed_foc_invoices: 0 }),
    report_sales_reconciliation: () => [{ channel: 'normal_invoices', transactions: 11, amount: 2260 }, { channel: 'exchange_invoices', transactions: 2, amount: 30 },
      { channel: 'tiktok', transactions: 2, amount: 600 }],
    report_tiktok_settlement_daily: () => fx.ttDaily,
    report_tiktok_settlement_by_store: () => fx.ttByStore,
    report_tiktok_qty_sold: () => fx.ttQty,
    report_tiktok_orders_by_status: () => fx.ttStatus,
    report_exchange_invoices: a => fx.exchanges.filter(e => inPeriod(sgtDate(e.created_at), a?.p_from, a?.p_to) || (!a?.p_from && !a?.p_to)),
    report_transfer_receipts: () => fx.trReceipts,
    report_transfer_discrepancies: () => fx.trDisc,
    report_transfers_overdue: () => fx.trOverdue,
    tiktok_settlement_totals: a => ({ year: a.p_year, month: a.p_month, period_start: '', period_end: '', timezone: 'Asia/Singapore', row_count: 1,
      revenue: 400, fee: 59.5, settlement: 340.5, expense: 0, income: 340.5, tiktok_net_settlement: 340.5, by_category: {}, unknown_count: 0,
      balance_movement_count: 0, pending_match_count: 1, currency_count: 1, undated_count: 0, needs_review: false }),
  };
  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], orders: [], rangeV: null, cols: '*' }); }
    select(cols) { this.cols = cols ?? '*'; return this; }
    is(col, v) { this.filters.push(r => (r[col] ?? null) === v); return this; }
    gte(col, v) { this.filters.push(r => r[col] != null && r[col] >= v); return this; }
    lte(col, v) { this.filters.push(r => r[col] != null && r[col] <= v); return this; }
    order(col) { this.orders.push(col); return this; }
    range(a, z) { this.rangeV = [a, z]; return this; }
    async exec() {
      b.calls.push({ name: this.name, args: this.args, orders: this.orders, range: this.rangeV, cols: this.cols });
      if (b.held.has(this.name)) await new Promise(r => b.waiters.push(r));
      await Promise.resolve();
      if (b.failures.has(this.name)) return { data: null, error: { message: b.failures.get(this.name) } };
      const src = this.kind === 'table' ? tables[this.name] : rpcs[this.name]?.(this.args);
      if (!src) return { data: null, error: { message: `unknown ${this.kind} ${this.name}` } };
      if (!Array.isArray(src)) return { data: src, error: null };
      let rows = src.filter(r => this.filters.every(f => f(r)));
      if (this.orders.length) rows = [...rows].sort((x, y) => {
        for (const c of this.orders) { if (x[c] === y[c]) continue; if (x[c] == null) return 1; if (y[c] == null) return -1; return x[c] < y[c] ? -1 : 1; }
        return 0;
      });
      const [from, to] = this.rangeV ?? [0, Infinity];
      rows = rows.slice(from, Math.min(to + 1, from + 1000));
      if (this.cols !== '*') { const keys = this.cols.split(','); rows = rows.map(r => Object.fromEntries(keys.map(k => [k, r[k]]))); }
      return { data: rows, error: null };
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
async function mount({ setup, fixture } = {}) {
  if (root) await act(async () => root.unmount());
  document.body.innerHTML = '<div id="root"></div>';
  backend = createBackend(fixture ?? makeFixture());
  globalThis.__backend = backend; globalThis.__exports = []; globalThis.__renderErrors = [];
  globalThis.__auth = { profile: { id: 'u-0', full_name: 'Owner User', role: 'owner' } };
  setup?.(backend);
  root = createRoot(document.getElementById('root'));
  await act(async () => root.render(React.createElement(ErrorBoundary, null, React.createElement(ReportsPage))));
  await tick();
}
const text = () => document.body.textContent;
const click = async el => { await act(async () => {
  el.dispatchEvent(new dom.window.MouseEvent('mousedown', { bubbles: true }));
  el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
}); };
const picker = () => document.querySelector('button[type="button"]');
async function selectTab(label, { wait = true } = {}) {
  await click(picker());
  const list = [...document.querySelectorAll('div')].find(d => d.style.zIndex === '60');
  const option = [...list.children].find(d => d.firstElementChild?.textContent === label);
  assert.ok(option, `the picker offers "${label}"`);
  await click(option);
  if (wait) await tick();
}
const tables = () => [...document.querySelectorAll('.table-wrap table')].map(t => ({
  headers: [...t.querySelectorAll('thead th')].map(x => x.textContent),
  rows: [...t.querySelectorAll('tbody tr')].map(r => [...r.querySelectorAll('td')].map(x => x.textContent)),
}));
const dataRows = (i = 0) => (tables()[i]?.rows ?? []).filter(r => r.length > 1);
const headline = () => document.querySelector('.page-header p strong')?.textContent;
const cards = () => Object.fromEntries([...document.querySelectorAll('.card')].filter(c => c.children.length >= 2 && c.children[0].tagName === 'DIV')
  .map(c => [c.children[0].textContent, c.children[1].textContent]));
const alerts = () => [...document.querySelectorAll('[role="alert"]')].map(a => a.textContent);
const button = label => [...document.querySelectorAll('button')].find(b => b.textContent.trim().startsWith(label));
const pageExport = () => document.querySelector('.page-header button');
const spinning = () => !!document.querySelector('.table-wrap .spin');
const callsOf = name => backend.calls.filter(c => c.name === name);
async function setDate(idx, value) {
  const el = document.querySelectorAll('input[type="date"]')[idx];
  const setter = Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value').set;
  await act(async () => { setter.call(el, value); el.dispatchEvent(new dom.window.Event('input', { bubbles: true })); });
  await tick();
}
async function exportWith(btn) {
  globalThis.__exports = [];
  await click(btn); await tick(2);
  return globalThis.__exports.at(-1);
}
after(async () => { if (root) await act(async () => root.unmount()); dom.window.close(); });

const TABS = ['Sales by Store', 'Top Products', 'Sales by Creator', 'Sales by Service Staff', 'Sales by Referrer', 'Vouchers', 'Promotions',
  'Specials & Rentals', 'Commission', 'Customers', 'Stock Balance', 'Pricing', 'Affiliate', 'Therapy', 'Discounts', 'FOC', 'Sources', 'TikTok',
  'Exchange Invoices', 'Transfers', 'Sales Reconciliation'];
const INVOICE_SALES = ['Sales by Store', 'Top Products', 'Sales by Creator', 'Sales by Service Staff', 'Sales by Referrer', 'Vouchers', 'Promotions',
  'Specials & Rentals', 'Customers', 'Sales Reconciliation'];

// ── tests ──────────────────────────────────────────────────────────────────
test('all 21 tabs render, and the export of each carries the headings of the table on screen', async () => {
  await mount();
  assert.equal(headline(), 'S$2260.00');
  for (const label of TABS) {
    await selectTab(label);
    assert.ok(!document.getElementById('crashed'), `${label} crashed: ${document.getElementById('crashed')?.textContent}`);
    assert.equal(picker().textContent, label);
    const shown = tables();
    assert.ok(shown.length > 0, `${label} shows a table`);
    // The page Export carries the main table: the receipts on Transfers, the first table elsewhere.
    const main = label === 'Transfers' ? shown[1] : shown[0];
    const exported = await exportWith(pageExport());
    assert.ok(exported, `${label} exports`);
    assert.deepEqual(exported.sheet.ws.header, main.headers, `${label}: export headings match the table`);
    assert.equal(exported.sheet.ws.body.length, main.rows.filter(r => r.length > 1).length, `${label}: one export row per table row`);
  }
  // The TikTok and Transfers tables that are not the main one have exports of their own.
  for (const [label, count] of [['TikTok', 4], ['Transfers', 2]]) {
    await selectTab(label);
    const own = [...document.querySelectorAll('.table-wrap button')].filter(b => b.textContent.trim() === 'Export');
    assert.equal(own.length, count, `${label} offers an export per secondary table`);
    for (const btn of own) {
      const heading = btn.parentElement.querySelector('h3');
      const table = btn.parentElement.nextElementSibling.tagName === 'TABLE' ? btn.parentElement.nextElementSibling : btn.parentElement.nextElementSibling.nextElementSibling;
      const exported = await exportWith(btn);
      assert.deepEqual(exported.sheet.ws.header, [...table.querySelectorAll('thead th')].map(x => x.textContent), `${heading.textContent}: headings match`);
    }
  }
  assert.deepEqual(globalThis.__renderErrors, []);
  assert.equal(callsOf('voucher_redemptions').length, 0, 'voucher uses are read from the invoices, not voucher_redemptions');
});

test('B1: an on-demand report that fails shows its error, never an empty table, and cannot be exported', async () => {
  const cases = [
    ['Exchange Invoices', 'report_exchange_invoices', 'No exchanges'],
    ['Transfers', 'report_transfers_overdue', 'Nothing overdue'],
    ['Transfers', 'report_transfer_receipts', 'No receipts'],
    ['Transfers', 'report_transfer_discrepancies', 'No discrepancies'],
    ['TikTok', 'report_tiktok_settlement_daily', 'No data'],
    ['TikTok', 'report_tiktok_settlement_by_store', 'No data'],
    ['TikTok', 'report_tiktok_qty_sold', 'No confirmed TikTok sales'],
    ['TikTok', 'report_tiktok_orders_by_status', 'No orders'],
  ];
  for (const [label, rpc, emptyText] of cases) {
    await mount({ setup: b => b.failures.set(rpc, `${rpc} failed`) });
    await selectTab(label);
    assert.ok(alerts().some(a => a.includes(`${rpc} failed`)), `${rpc}: the error is shown`);
    assert.ok(!text().includes(emptyText), `${rpc}: no "${emptyText}"`);
  }
  await mount({ setup: b => b.failures.set('report_exchange_invoices', 'boom') });
  await selectTab('Exchange Invoices');
  assert.equal(pageExport().disabled, true, 'a failed report cannot be exported');
  await mount({ setup: b => b.failures.set('report_transfer_receipts', 'boom') });
  await selectTab('Transfers');
  assert.equal(pageExport().disabled, true, 'failed receipts cannot be exported');
});

test('B1: while an on-demand report loads it shows a spinner, not an empty state, and Export waits', async () => {
  for (const [label, rpc, emptyText] of [['Exchange Invoices', 'report_exchange_invoices', 'No exchanges'], ['Transfers', 'report_transfers_overdue', 'Nothing overdue'],
    ['Transfers', 'report_transfer_receipts', 'No receipts'], ['TikTok', 'report_tiktok_settlement_daily', 'No data']]) {
    await mount({ setup: b => b.held.add(rpc) });
    await selectTab(label);
    assert.ok(spinning(), `${rpc}: a spinner while it loads`);
    assert.ok(!text().includes(emptyText), `${rpc}: no "${emptyText}" while it loads`);
    if (rpc !== 'report_transfers_overdue' && rpc !== 'report_tiktok_settlement_daily') assert.equal(pageExport().disabled, true, `${rpc}: Export waits`);
    backend.release(); await tick();
    assert.ok(!spinning(), `${rpc}: the spinner goes once it has loaded`);
  }
});

test('B1: on-demand reports are paged, and Refresh loads them again', async () => {
  await mount();
  await selectTab('Transfers');
  await selectTab('TikTok');
  await selectTab('Exchange Invoices');
  for (const rpc of ['report_exchange_invoices', 'report_transfer_receipts', 'report_transfer_discrepancies', 'report_transfers_overdue',
    'report_tiktok_settlement_daily', 'report_tiktok_settlement_by_store', 'report_tiktok_qty_sold', 'report_tiktok_orders_by_status']) {
    const c = callsOf(rpc).at(-1);
    assert.deepEqual(c.range, [0, 999], `${rpc} is fetched a page at a time`);
    assert.ok(c.orders.length > 0, `${rpc} has a paging order`);
  }
  const before = callsOf('report_exchange_invoices').length;
  await click(button('Refresh')); await tick();
  assert.equal(callsOf('report_exchange_invoices').length, before + 1, 'Refresh reloads the open on-demand tab');
  await selectTab('Transfers');
  const receipts = callsOf('report_transfer_receipts').length;
  await click(button('Refresh')); await tick();
  assert.equal(callsOf('report_transfer_receipts').length, receipts + 1, 'Refresh reloads Transfers');
  const totals = callsOf('tiktok_settlement_totals').length;
  await selectTab('TikTok');
  const daily = callsOf('report_tiktok_settlement_daily').length;
  await click(button('Refresh')); await tick();
  assert.equal(callsOf('report_tiktok_settlement_daily').length, daily + 1, 'Refresh reloads the TikTok tables');
  assert.ok(callsOf('tiktok_settlement_totals').length > totals + 1, "Refresh reloads the month's TikTok cards too");
});

test('B2: a failure in a separately loaded report shows on its own tab only', async () => {
  const cases = [
    ['report_tiktok_settlement', 'TikTok'], ['report_tiktok_settlement_summary', 'TikTok'],
    ['report_affiliates', 'Affiliate'], ['report_affiliates', 'Commission'], ['report_therapy', 'Therapy'], ['report_customer_sources', 'Sources'],
  ];
  for (const [rpc, label] of cases) {
    await mount({ setup: b => b.failures.set(rpc, `${rpc} failed`) });
    assert.equal(headline(), 'S$2260.00', `${rpc}: the headline is unaffected`);
    assert.equal(dataRows(0).length, 2, `${rpc}: Sales by Store still shows its stores`);
    assert.ok(!alerts().some(a => a.includes(`${rpc} failed`)), `${rpc}: not reported on Sales by Store`);
    await selectTab(label);
    assert.ok(alerts().some(a => a.includes(`${rpc} failed`)), `${rpc}: reported on ${label}`);
    if (label !== 'TikTok') assert.equal(pageExport().disabled, true, `${rpc}: ${label} cannot be exported`);
  }
});

test('B2: without the invoice records the headline and cards show no S$0.00; the other reports still work', async () => {
  await mount({ setup: b => b.held.add('invoice_sales_ledger') });
  assert.notEqual(headline(), 'S$0.00', 'no S$0.00 while loading');
  assert.equal(cards()['Revenue'], undefined, 'no cards while loading');
  backend.release(); await tick();
  assert.equal(cards()['Revenue'], 'S$2260.00');

  await mount({ setup: b => b.failures.set('invoice_sales_ledger', 'ledger failed') });
  assert.equal(headline(), 'unavailable');
  assert.equal(cards()['Revenue'], undefined, 'no cards');
  assert.ok(text().includes('The complete report is unavailable'));
  await selectTab('Affiliate');
  assert.equal(dataRows(0).length, 3, 'the Affiliate report does not need the invoice records');
  await selectTab('Exchange Invoices');
  assert.equal(dataRows(0).length, 2, 'nor does Exchange Invoices');
});

test('B3: the period reaches the reports that take one; the TikTok tables follow the reporting month', async () => {
  await mount();
  await setDate(0, '2026-09-01'); await setDate(1, '2026-09-27');
  for (const [label, rpc] of [['Exchange Invoices', 'report_exchange_invoices'], ['Transfers', 'report_transfer_receipts'], ['Sources', 'report_customer_sources']]) {
    await selectTab(label);
    const args = callsOf(rpc).at(-1).args;
    assert.equal(args.p_from, '2026-09-01', `${rpc} gets the start`);
    assert.equal(args.p_to, '2026-09-27', `${rpc} gets the end`);
  }
  await selectTab('Exchange Invoices');
  assert.deepEqual(dataRows(0).map(r => r[0]), ['EX-0002'], 'only the period exchange is listed');
  assert.deepEqual(dataRows(0).length, 1);

  await selectTab('TikTok');
  const [monthSel, yearSel] = document.querySelectorAll('select');
  const expect = (y, m) => { const p = settlementPeriod(y, m); return [toIsoDate(p.start), toIsoDate(p.end)]; };
  const now = expect(Number(yearSel.value), Number(monthSel.value));
  for (const rpc of ['report_tiktok_settlement_daily', 'report_tiktok_settlement_by_store']) {
    const a = callsOf(rpc).at(-1).args;
    assert.deepEqual([a.p_from, a.p_to], now, `${rpc} covers the reporting month`);
  }
  await act(async () => { monthSel.value = monthSel.value === '8' ? '7' : '8';
    monthSel.dispatchEvent(new dom.window.Event('change', { bubbles: true })); });
  await tick();
  const moved = expect(Number(yearSel.value), Number(monthSel.value));
  const a = callsOf('report_tiktok_settlement_daily').at(-1).args;
  assert.deepEqual([a.p_from, a.p_to], moved, 'a new reporting month moves the day table');
  assert.equal(callsOf('report_tiktok_qty_sold').at(-1).args.p_from, null, 'quantity sold stays all periods');
  const headings = [...document.querySelectorAll('.table-wrap h3')].map(h => h.textContent);
  assert.ok(headings.some(h => h.startsWith('Quantity Sold') && h.includes('all periods')));
  assert.ok(headings.some(h => h.startsWith('Orders by Status') && h.includes('all periods')));
  assert.ok(headings.some(h => h.startsWith('Settlement by Day') && h.includes('reporting month')));
});

test('B3: the invoice-sales cards show only where the table follows that period; the others say what they cover', async () => {
  await mount();
  for (const label of TABS) {
    await selectTab(label);
    assert.equal(!!cards()['Revenue'], INVOICE_SALES.includes(label), `${label}: invoice-sales cards ${INVOICE_SALES.includes(label) ? 'shown' : 'hidden'}`);
  }
  const notes = { Commission: 'Lifetime', Affiliate: 'Lifetime', Therapy: 'All therapy', 'Stock Balance': 'Current stock position' };
  for (const [label, start] of Object.entries(notes)) {
    await selectTab(label);
    assert.ok(document.querySelector('[data-testid="period-note"]')?.textContent.startsWith(start), `${label} says it is ${start.toLowerCase()}`);
  }
  await selectTab('Top Products');
  assert.ok(document.querySelector('[data-testid="wallet-note"]')?.textContent.includes('wallet credit'), 'counts note wallet-only purchases');
});

test('B4: Sales by Referrer commission is the tier-1 commission on the invoices listed in the period', async () => {
  await mount();
  await selectTab('Sales by Referrer');
  // All time: tier-1 on inv-02 (20) and inv-07 (40); the tier-2 row (7) and the reversal are not.
  assert.deepEqual(dataRows(0), [['Customer 06', '2', 'S$590.00', 'S$60.00']]);
  await setDate(0, '2026-08-01'); await setDate(1, '2026-08-31');
  assert.deepEqual(dataRows(0), [['Customer 06', '1', 'S$200.00', 'S$20.00']], 'August lists inv-02 only, with its own commission');
});

test('B5 and B11: Commission shows Outstanding = Earned − Paid Out, and a deleted referrer by that name', async () => {
  await mount();
  await selectTab('Commission');
  assert.deepEqual(tables()[0].headers, ['Referrer', 'Earned (lifetime)', 'Paid Out', 'Reversed', 'Outstanding']);
  assert.deepEqual(dataRows(0), [
    ['Customer 06', 'S$67.00', 'S$12.00', '−S$15.00', 'S$55.00'],
    ['Customer 05', 'S$10.00', '—', '—', 'S$10.00'],
    ['Deleted customer', 'S$0.00', '—', '−S$12.00', 'S$0.00'],
  ]);
});

test('B11: the Affiliate tab lists affiliates by name', async () => {
  await mount();
  await selectTab('Affiliate');
  assert.deepEqual(dataRows(0).map(r => r[0]), ['Customer 00', 'Customer 05', 'Customer 06']);
});

test('B6 and B15: voucher uses come from the sale invoices; retired catalogue items keep their sales', async () => {
  await mount();
  await selectTab('Vouchers');
  assert.deepEqual(tables()[0].headers, ['Voucher', 'Type', 'Invoiced qty', 'Sales Value', 'Uses', 'Discount Given']);
  // v-1: the line on inv-11 (10) and the invoice-level discount on inv-12 (30 − 5 manual = 25).
  // The cancelled inv-14 is not a sale, so its use is not counted.
  assert.deepEqual(dataRows(0), [
    ['Voucher Facial', 'single', '1', 'S$50.00', '2', '−S$35.00'],
    ['Deleted voucher', '—', '1', 'S$40.00', '0', '—'],
  ]);
  await setDate(0, '2026-08-01'); await setDate(1, '2026-08-31');
  assert.deepEqual(dataRows(0), [['Voucher Facial', 'single', '1', 'S$50.00', '0', '—']], 'no uses in August');
  await setDate(0, ''); await setDate(1, '');
  await selectTab('Promotions');
  assert.deepEqual(dataRows(0), [['Promo Bundle', 'PROMO1', '1', 'S$20.00', 'S$300.00'], ['Deleted promotion', '—', '1', '—', 'S$60.00']]);
});

test('B7: Customers is built from the recognized invoices, so it totals Revenue and keeps deleted customers', async () => {
  await mount();
  await selectTab('Customers');
  const rows = dataRows(0);
  const total = rows.reduce((s, r) => s + Number(r[6].replace('S$', '')), 0);
  assert.equal(total.toFixed(2), cards()['Revenue'].replace('S$', ''), 'the tab totals the Revenue card');
  assert.equal(rows.length, Number(cards()['Customers served']));
  assert.deepEqual(rows.find(r => r[0] === 'Deleted customer'), ['Deleted customer', '', '—', '—', '—', '1', 'S$90.00']);
  await setDate(0, '2026-09-01'); await setDate(1, '2026-09-27');
  const period = dataRows(0).reduce((s, r) => s + Number(r[6].replace('S$', '')), 0);
  assert.equal(period.toFixed(2), cards()['Revenue'].replace('S$', ''), 'and for a period');
});

test('B7: the heavy report data is memoised and grouped with lookups', () => {
  const page = readFileSync(new URL('../../../src/pages/ReportsPage.tsx', import.meta.url), 'utf8');
  assert.match(page, /const custRows = useMemo\(/, 'the Customers rows are memoised');
  assert.match(page, /const basis = useMemo\(/, 'the period basis is memoised');
  assert.doesNotMatch(page, /customers\.map\(c => \{\s*const cInv = paid\.filter/, 'no customers × invoices scan');
  assert.doesNotMatch(page, /\.find\(p => p\.id === id\)/, 'names come from maps, not a search per row');
});

test('B7: switching tabs with 13,000 customers keeps working', async () => {
  await mount({ fixture: makeFixture({ extraCustomers: 13000 - 6 }) });
  await selectTab('Customers');
  assert.equal(dataRows(0).length, 6);
  await selectTab('Sales by Store');
  assert.equal(dataRows(0).length, 2);
});

test('B12: therapy dates are shown as stored, with no shift west of UTC', async () => {
  await mount();
  await selectTab('Therapy');
  assert.deepEqual(dataRows(0)[0].slice(5, 8), ['01/09/2026', '02/09/2026', '02/12/2026']);
});

test('B13: stock under a deleted product is not counted', async () => {
  await mount();
  await selectTab('Stock Balance');
  assert.deepEqual(dataRows(0), [
    ['🏭 Main Warehouse', 'Warehouse', '2', '60'], ['🏭 Overflow Warehouse', 'Warehouse', '1', '5'],
    ['🏪 North Store', 'Store', '1', '3'], ['🏪 South Store', 'Store', '0', '0'],
  ]);
});

test('B14: TikTok rows say "No match needed", run newest first, and the all-period cards say what they total', async () => {
  await mount();
  await selectTab('TikTok');
  const rows = dataRows(0);
  assert.deepEqual(rows.map(r => r[1]), ['ORD-5', 'ADS-1', 'ADJ-1', 'ORD-2', 'ORD-1'], 'undated first, then newest settled date');
  assert.equal(rows.find(r => r[1] === 'ADS-1')[4], 'No match needed');
  assert.equal(rows.find(r => r[1] === 'ORD-2')[4], 'Pending');
  assert.ok(!text().includes('Total Settlement (main)'));
  assert.equal(cards()['TikTok reported net settlement'], 'S$505.50');
  assert.equal(cards()['Fees as imported'], 'S$-81.50');
});

test('B16: the Discounts headings say what the columns hold', async () => {
  await mount();
  await selectTab('Discounts');
  assert.deepEqual(tables()[0].headers.slice(5, 8), ['Save Earth', 'Invoice voucher', 'Promotion lines (in Line)']);
});
