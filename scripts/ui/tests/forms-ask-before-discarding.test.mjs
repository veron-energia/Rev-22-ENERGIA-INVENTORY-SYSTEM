// Closing a form asks "Discard what you have entered?" only once something would
// be lost (user, 7 Nov 2026: "add the discard question", "do the larger forms").
//
// Each real page or popup is mounted in jsdom and opened as staff open it. The
// point of the test is both halves: a form opened and closed untouched asks
// nothing, even one that fills itself in after opening (a therapy package's lists,
// a service's notes, a transfer's seeded allocations, a claim's defaults), and a
// changed one asks, with No keeping what was entered. A smaller popup that is not
// listed here does not ask. Every name, number and phone is made up.
//
// Run: node --test scripts/ui/tests/forms-ask-before-discarding.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, driver } from '../page-harness.mjs';

const dom = setupDom();
const mod = await bundle(`
  import React from 'react';
  export { default as StoresPage } from './src/pages/StoresPage';
  export { default as WarehousesPage } from './src/pages/WarehousesPage';
  export { default as VouchersPage } from './src/pages/VouchersPage';
  export { default as TherapyPage } from './src/pages/TherapyPage';
  export { default as TherapyServicesPage } from './src/pages/TherapyServicesPage';
  export { default as TransfersPage } from './src/pages/TransfersPage';
  export { default as WarehouseInventoryPage } from './src/pages/WarehouseInventoryPage';
  export { default as SpecialPage } from './src/pages/SpecialPage';
  export { default as CustomersPage } from './src/pages/CustomersPage';
  export { default as SurveysPage } from './src/pages/SurveysPage';
  export { default as InvoicesPage } from './src/pages/InvoicesPage';
  export { QuickCustomerModal } from './src/components/customers/QuickCustomerModal';
  export { AffiliatePayoutPanel } from './src/components/commissions/AffiliatePayoutPanel';
  export { CreditSpendingRules } from './src/components/therapy/CreditSpendingRules';
  export { VoucherClaimPanel } from './src/components/therapy/VoucherClaimPanel';
  export { PurchasedClaimPanel } from './src/components/therapy/PurchasedClaimPanel';
  export { MemoryRouter } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`, { stubAuth: true });
const { React, MemoryRouter } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });

const DISCARD = 'Discard what you have entered? It will not be saved.';
const asked = [];
let answer = false;
dom.window.confirm = q => { asked.push(q); return answer; };

/** Answers every read with its table's rows, whatever the filters; enough to open a form. */
function fakeDb(tables = {}, rpc = {}) {
  const query = rows => {
    let single = false;
    const result = () => ({ data: single ? structuredClone(rows[0] ?? null) : structuredClone(rows), error: null, count: rows.length });
    const q = new Proxy({}, { get(_, k) {
      if (k === 'then') return (res, rej) => Promise.resolve(result()).then(res, rej);
      if (k === 'maybeSingle' || k === 'single') return () => { single = true; return q; };
      return () => q;
    } });
    return q;
  };
  const answer = data => {
    const q = new Proxy({}, { get(_, k) {
      if (k === 'then') return (res, rej) => Promise.resolve({ data: structuredClone(data), error: null }).then(res, rej);
      return () => q;
    } });
    return q;
  };
  return {
    from: table => query(tables[table] ?? []),
    rpc: name => answer(name in rpc ? rpc[name] : null),
    channel: () => { const c = { on: () => c, subscribe: () => c }; return c; },
    removeChannel: async () => {},
  };
}

const OWNER = { id: 'u-own', full_name: 'Made-up Owner', role: 'owner', is_active: true };
async function show(Component, { tables, rpc, props } = {}) {
  globalThis.__supabase = fakeDb(tables, rpc);
  globalThis.__auth = { profile: OWNER, assignments: [], session: null, user: { id: OWNER.id } };
  await d.mount(React.createElement(MemoryRouter, null, React.createElement(Component, props)));
}

const titled = title => [...document.querySelectorAll('.modal h3')].find(h => h.textContent.startsWith(title))?.closest('.modal-overlay');
const topModal = () => [...document.querySelectorAll('.modal')].pop();
const press = label => {
  const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim().startsWith(label));
  assert.ok(b, `a button "${label}" is on the page`);
  return d.click(b);
};
/** Types into the field a label names, or the popup's first box. */
const type = (label, value = 'Changed for this test') => {
  const box = label
    ? [...topModal().querySelectorAll('.form-group, div')].find(g => g.querySelector(':scope > label')?.textContent.startsWith(label))?.querySelector('input, textarea')
    : topModal().querySelector('input:not([type=checkbox]):not([type=radio]):not([type=file]), textarea');
  assert.ok(box, `a box ${label ?? ''} is in the popup`);
  return d.setValue(box, value);
};

/** The whole rule, for one form. `outside` finds its backdrop while it is open. */
async function asksOnlyOnceChanged({ open, change, title, outside = () => titled(title) }) {
  await open();
  await d.tick();
  assert.ok(outside(), 'it opens');
  asked.length = 0;
  await d.click(outside());
  assert.deepEqual(asked, [], 'untouched: nothing is asked');
  assert.ok(!outside(), 'untouched: it closes');

  await open();
  await d.tick();
  assert.ok(outside(), 'it opens again');
  await change();
  answer = false;
  await d.click(outside());
  assert.deepEqual(asked, [DISCARD], 'changed: it asks');
  assert.ok(outside(), 'No keeps it');
  answer = true;
  asked.length = 0;
  await d.click(outside());
  assert.deepEqual(asked, [DISCARD]);
  assert.ok(!outside(), 'Yes closes it');
  answer = false;
  asked.length = 0;
}

const STORE = { id: 's1', name: 'Made-up Store', code: 'MU-S', address: '1 Made Up Road', phone: '+61491570110', is_active: true, deleted_at: null };
const WAREHOUSE = { id: 'w1', name: 'Made-up Warehouse', code: 'MU-W', address: '2 Made Up Road', phone: '+61491570111', is_active: true, deleted_at: null };
const PRODUCT = { id: 'p1', name: 'Made-up Mat', sku: 'MU-M', product_type: 'own', is_active: true, deleted_at: null };

test('Add and Edit Store', async () => {
  await show(mod.StoresPage, { tables: { stores: [STORE] } });
  await asksOnlyOnceChanged({ title: 'Add Store', open: () => press('Add Store'), change: () => type('Name') });
  await asksOnlyOnceChanged({ title: 'Edit Store', open: () => d.click(document.querySelector('button[title="Edit"]')), change: () => type('Name') });
});

test('Add and Edit Warehouse', async () => {
  await show(mod.WarehousesPage, { tables: { warehouses: [WAREHOUSE] } });
  await asksOnlyOnceChanged({ title: 'Add Warehouse', open: () => press('Add Warehouse'), change: () => type('Name') });
  await asksOnlyOnceChanged({ title: 'Edit Warehouse', open: () => d.click(document.querySelector('button[title="Edit"]')), change: () => type('Name') });
});

test('Add and Edit Voucher', async () => {
  await show(mod.VouchersPage, { tables: { stores: [STORE], vouchers: [{ id: 'v1', name: 'Made-up Voucher', code: 'MU-V', voucher_kind: 'fixed_discount', discount_amount: 5, selling_price: 10, is_active: true, deleted_at: null, qty_type: 'limited' }] } });
  await asksOnlyOnceChanged({ title: 'Add Voucher', open: () => press('Add Voucher'), change: () => type('Name') });
  await asksOnlyOnceChanged({ title: 'Edit Voucher', open: () => d.click(document.querySelector('tbody button.btn-secondary.btn-icon')), change: () => type('Name') });
});

const THERAPY_TABLES = {
  stores: [STORE],
  vouchers: [{ id: 'v1', name: 'Made-up Voucher', code: 'MU-V', voucher_kind: 'therapy', reward_eligible: true }],
  // A choice package: its voucher and service lists are read after it opens.
  unlimited_therapy_packages: [{ id: 'pk1', name: 'Made-up Package', sku: 'MU-T', duration_months: 12, description: null, is_active: true, entitlement_kind: 'choice', voucher_qty: 10, voucher_id: null }],
  therapy_package_vouchers: [{ package_id: 'pk1', voucher_id: 'v1' }],
  therapy_package_services: [{ package_id: 'pk1', service_id: 'sv1' }],
  therapy_services: [{ id: 'sv1', name: 'Made-up Service', is_active: true }],
  therapy_package_rules: [{ id: 'r1', name: 'Made-up Rule', store_id: 's1', qualifying_amount: 100, entitlement_kind: 'unlimited', duration_months: 12, voucher_qty: null, activation_deadline_days: 365, is_active: true }],
  credit_packages: [{ id: 'c1', name: 'Made-up Credit', sku: 'MU-C', customer_price: 100, paid_credit_amount: 100, is_active: true, allow_product: true }],
  credit_package_stores: [{ store_id: 's1' }],
  credit_package_vouchers: [{ voucher_id: 'v1' }],
  premium_bundles: [{ id: 'b1', name: 'Made-up Bundle', sku: 'MU-B', customer_payment_amount: 100, paid_credit_amount: 100, bonus_credit_amount: 0, is_active: true }],
  premium_bundle_stores: [{ store_id: 's1' }],
  premium_bundle_vouchers: [{ voucher_id: 'v1' }],
};

test('Premium Bundle, Credit Package, Qualification Rule and Therapy Package', async () => {
  await show(mod.TherapyPage, { tables: THERAPY_TABLES });
  const edit = () => d.click(document.querySelector('tbody button.btn-icon'));

  await press('Premium Bundles');
  await asksOnlyOnceChanged({ title: 'New Premium Bundle', open: () => press('New Bundle'), change: () => type('Bundle name') });
  await asksOnlyOnceChanged({ title: 'Edit Premium Bundle', open: edit, change: () => type('Bundle name') });

  await press('Credit Packages');
  await asksOnlyOnceChanged({ title: 'New Credit Package', open: () => press('New Package'), change: () => type('Package name') });
  await asksOnlyOnceChanged({ title: 'Edit Credit Package', open: edit, change: () => type('Package name') });

  await press('Packages');
  await asksOnlyOnceChanged({ title: 'New Therapy Package', open: () => press('New Package'), change: () => type('Name') });
  // Its voucher and service lists arrive after it opens: not a change.
  await asksOnlyOnceChanged({ title: 'Edit Package', open: edit, change: () => type('Name') });

  await press('Qualification');
  await asksOnlyOnceChanged({ title: 'New Qualification Rule', open: () => press('New Rule'), change: () => type('Name') });
});

test('Add and Edit Therapy Service, whose notes arrive after it opens', async () => {
  const row = { id: 'sv1', service_code: 'MU-SV', name: 'Made-up Service', description: null, standard_price: 50, effective_price: 50, duration_minutes: 30,
    frequency_kind: 'unlimited', frequency_max_per_period: 1, frequency_interval_hours: null, frequency_description: '', is_active: true, is_archived: false,
    store_count: 1, store_names: ['Made-up Store'], available_here: true, has_price_override: false, can_manage: true };
  await show(mod.TherapyServicesPage, { rpc: { therapy_service_catalogue: [row] }, tables: { stores: [STORE], therapy_services: [{ notes: 'Made-up notes' }] } });
  await asksOnlyOnceChanged({ title: 'Add Therapy Service', open: () => press('Add Service'), change: () => type('Name') });
  await asksOnlyOnceChanged({ title: 'Edit Made-up Service', open: () => d.click(document.querySelector('button[title="Edit"]')), change: () => type('Name') });
});

const at = '2026-10-08T03:00:00Z';
const request = (id, o) => ({ id, transfer_type: 'warehouse_to_store', source_type: 'warehouse', source_id: 'w1', dest_type: 'store', dest_id: 's1',
  status: 'pending', note: null, rejection_reason: null, requested_by: 'u-own', approved_by: null, created_at: at, approved_at: null,
  completed_at: null, version: 1, edit_count: 0, dispatched_at: null, received_at: null, ...o });
const line = (id, req, o) => ({ id, transfer_request_id: req, line_kind: 'product', product_id: 'p1', quantity: 5, approved_quantity: null,
  in_transit_quantity: null, received_quantity: null, discrepancy_quantity: null, discrepancy_resolved_at: null, discrepancy_resolution: null, created_at: at, ...o });

test('every Transfers form; Review seeds its allocations after it opens', async () => {
  await show(mod.TransfersPage, {
    tables: {
      warehouses: [WAREHOUSE], stores: [STORE], products: [PRODUCT], profiles: [{ id: 'u-own', full_name: 'Made-up Owner' }],
      store_product_prices: [{ store_id: 's1', product_id: 'p1' }],
      transfer_requests: [
        request('r-pending', { note: 'Made-up note' }),
        request('r-transit', { status: 'in_transit', approved_by: 'u-own', approved_at: at, dispatched_at: at }),
        request('r-disc', { status: 'received_with_discrepancy', approved_by: 'u-own', approved_at: at, dispatched_at: at, received_at: at }),
      ],
      transfer_request_lines: [
        line('l-p', 'r-pending'),
        line('l-t', 'r-transit', { approved_quantity: 5, in_transit_quantity: 5 }),
        line('l-d', 'r-disc', { approved_quantity: 5, in_transit_quantity: 5, received_quantity: 3, discrepancy_quantity: -2 }),
      ],
    },
    rpc: {
      my_assigned_stores: [],
      transfer_request_sourcing: [{ line_id: 'l-p', source_type: 'warehouse', source_id: 'w1', source_name: 'Made-up Warehouse', on_hand: 10, reserved: 0, available: 10, allocated: 0 }],
      stock_transfer_details: { lines: [], notes: [] },
    },
  });
  await asksOnlyOnceChanged({ title: 'New Stock Transfer', open: () => press('New Transfer'), change: () => d.setValue(topModal().querySelector('input[placeholder="Qty"]'), '3') });
  await asksOnlyOnceChanged({ title: 'Review Transfer Request', open: () => press('Review'), change: () => d.setValue(topModal().querySelector('input[type=number]'), '3') });
  await asksOnlyOnceChanged({ title: 'Edit Transfer', open: () => press('Edit'), change: () => d.setValue(topModal().querySelector('input[type=number]'), '3') });
  await asksOnlyOnceChanged({ title: 'Confirm Receipt', open: () => press('Receive'), change: () => d.setValue(topModal().querySelector('input[type=number]'), '3') });
  await asksOnlyOnceChanged({ title: 'Resolve Discrepancy', open: () => press('Resolve'), change: () => type(null) });
});

test('Manual Warehouse Stock-In', async () => {
  await show(mod.WarehouseInventoryPage, { tables: { warehouses: [WAREHOUSE], products: [PRODUCT] } });
  await asksOnlyOnceChanged({ title: 'Manual Warehouse Stock-In', open: () => press('Stock In'), change: () => type(null, '3') });
});

test('Add and Edit Special Product', async () => {
  await show(mod.SpecialPage, {
    tables: { special_products: [{ id: 'sp1', product_id: 'p1', name: 'Made-up Machine', sku: 'MU-X', description: 'Made-up note', sale_price: 0, rate_day: 30, rate_week: 150, rate_month: 400, rate_year: 0, late_fee_per_day: 5, is_active: true, is_consignment: false }], warehouses: [WAREHOUSE], stores: [STORE], products: [PRODUCT] },
    rpc: { products_available_as_special: [PRODUCT], special_product_availability: [], special_docs_awaiting_fulfilment: [] },
  });
  await asksOnlyOnceChanged({ title: 'Add Special Product', open: () => press('Add Special'), change: () => type('Sale Price', '42') });
  await asksOnlyOnceChanged({ title: 'Edit Special Product', open: () => d.click(document.querySelector('tbody button.btn-icon')), change: () => type('Sale Price', '42') });
});

test('Opening credit balance, Adjust credit and Customer Source', async () => {
  const customer = { id: 'c1', full_name: 'Made Up', first_name: 'Made', last_name: 'Up', phone: '+61491570112', is_active: true, total_count: 1, source_option_id: 'so1', source_details: null };
  await show(mod.CustomersPage, { rpc: {
    search_customers: [customer], active_customer_source_options: [{ id: 'so1', label: 'Made-up source', needs_details: false }, { id: 'so2', label: 'Another source', needs_details: false }],
    customer_overview: { customer, invoices: [], therapy: [], vouchers: [] }, customer_credit_balances: [], customer_credit_statement: [],
  }, tables: { stores: [STORE] } });
  await asksOnlyOnceChanged({ title: 'Customer Source', open: () => d.click(document.querySelector('button[title^="Change customer source"]')), change: () => type('Reason for change') });
  await press('View');
  await d.tick();
  await asksOnlyOnceChanged({ title: 'Opening credit balance', open: () => press('Opening balance'), change: () => d.setValue(topModal().querySelector('input[type=number]'), '42') });
  await asksOnlyOnceChanged({ title: 'Adjust credit', open: () => press('Adjust'), change: () => d.setValue(topModal().querySelector('input[type=number]'), '42') });
});

test('New Customer Form QR Link', async () => {
  await show(mod.SurveysPage, { tables: { stores: [STORE], customer_source_options: [{ id: 'so1', label: 'Made-up source', is_active: true }] } });
  await d.click(document.querySelector('[data-tab="links"]'));
  await asksOnlyOnceChanged({ title: 'New Customer Form', open: () => press('New QR'), change: () => d.setValue(document.getElementById('link-event'), 'Made-up event') });
});

test('Record payout and Mark deduction as settled', async () => {
  const month = (referrer, m, earned, adjustments, paid, extra) => ({ referrer, month: m, earned, adjustments, paid, balance: +(earned + adjustments - paid).toFixed(2), tier1: earned, tier2: 0, review_reason: null, ...extra });
  await show(mod.AffiliatePayoutPanel, {
    props: { mode: 'earned', canPay: true, userId: 'owner', onSaved: () => {} },
    rpc: {
      commission_referrer_names: [{ id: 'ref-a', full_name: 'Made-up Alpha' }, { id: 'ref-b', full_name: 'Made-up Bravo' }],
      affiliate_payout_overview: {
        groups: [
          month('ref-a', '2026-10-01', 100.8, 0, 93.72, { payable: 0, referrer_owed: -555.27, referrer_payable: 0, referrer_deduction: 555.27 }),
          month('ref-b', '2026-10-01', 100, 0, 0, { payable: 100, referrer_owed: 100, referrer_payable: 100, referrer_deduction: 0 }),
        ],
        referrers: [
          { referrer: 'ref-a', owed: -555.27, unpaid: 0, deduction: 555.27, payable: 0 },
          { referrer: 'ref-b', owed: 100, unpaid: 100, deduction: 0, payable: 100 },
        ],
        payouts: [], settlements: [],
        methods: [{ id: 'm1', name: 'Made-up Transfer', is_active: true, deleted_at: null, is_wallet_credit: false }],
      },
    },
  });
  await d.tick();
  const enabled = label => [...document.querySelectorAll('button')].find(b => b.textContent.trim() === label && !b.disabled);
  const labelled = text => [...topModal().querySelectorAll('label')].find(l => l.textContent.startsWith(text))?.querySelector('input');
  await asksOnlyOnceChanged({ title: 'Record payout', open: () => d.click(enabled('Record payout')), change: () => d.setValue(labelled('Reference'), 'Made-up reference') });
  await asksOnlyOnceChanged({ title: 'Mark deduction as settled', open: () => d.click(enabled('Mark as settled')), change: () => d.setValue(topModal().querySelector('input[type=number]'), '1.00') });
});

test('The invoice window asks only once a payment is being entered', async () => {
  const invoice = { id: 'inv', invoice_no: 'INV-TEST', store_id: 's1', customer_id: 'c1', status: 'unpaid', subtotal: 100, total_amount: 100, paid_amount: 0,
    discount_total: 0, manual_discount: 0, created_at: at, business_date: '2026-09-01' };
  await show(mod.InvoicesPage, {
    tables: {
      invoices: [invoice], stores: [STORE], profiles: [{ id: 'u-own', full_name: 'Made-up Owner', role: 'owner', is_active: true, deleted_at: null }],
      customers: [{ id: 'c1', full_name: 'Made Up', phone: '+61491570112', is_active: true, deleted_at: null }],
      payment_methods: [{ id: 'cash', name: 'Made-up Cash', is_active: true, deleted_at: null }],
    },
    rpc: {
      invoice_list_page: { rows: [{ ...invoice, customer_name: 'Made Up' }], total: 1, pages: 1, summary: { matching: 1, total_amount: 100, outstanding: 100, paid: 0 } },
      invoice_financial_position: { total: 100, net_received: 0, outstanding: 100, refund_due: 0, status: 'unpaid' },
      invoice_effective_affiliate: { found: true, has_affiliate: false },
    },
  });
  const view = () => press('View');
  // The amount starts at what is owed, and no method is chosen: nothing entered yet.
  await asksOnlyOnceChanged({ title: 'Invoice INV-TEST', open: view, change: () => press('Split Payment') });
  await asksOnlyOnceChanged({ title: 'Invoice INV-TEST', open: view, change: async () => {
    await press('Select payment method');
    await d.click([...document.querySelectorAll('[role=listbox] button')].find(b => b.textContent.includes('Made-up Cash')));
  } });

  await view();
  await d.tick();
  await press('Split Payment');
  answer = false;
  const closeButton = () => [...topModal().querySelectorAll('.modal-footer button')].find(b => b.textContent.trim() === 'Close');
  assert.ok(closeButton(), 'the window has a Close button');
  await d.click(closeButton());
  assert.deepEqual(asked, [DISCARD], 'its Close button asks too');
  assert.ok(titled('Invoice INV-TEST'), 'and No keeps it');
  answer = true;
  await d.click(closeButton());
  assert.ok(!titled('Invoice INV-TEST'), 'Yes closes it');
  answer = false;
  asked.length = 0;
});

test('Add a customer: a click outside, the X and Escape ask; Cancel does not', async () => {
  let closed = 0;
  const open = () => show(mod.QuickCustomerModal, { rpc: { customer_match_candidates: { candidates: [], used: 0, remaining: 3 } },
    props: { initialName: 'Made', onCreated: () => {}, onPickedExisting: () => {}, onClose: () => { closed++; } } });
  const outside = () => document.querySelector('.quick-customer-backdrop');
  const first = () => document.querySelector('.quick-customer input');
  const escape = () => mod.act(async () => { document.dispatchEvent(new dom.window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true })); });

  await open();
  asked.length = 0;
  await d.click(outside());
  await escape();
  await d.click(document.querySelector('.quick-customer-close'));
  assert.deepEqual(asked, [], 'prefilled with what was typed in the picker, and untouched: nothing is asked');
  assert.equal(closed, 3);

  closed = 0;
  await d.setValue(first(), 'Made-up name');
  await d.click(outside());
  await escape();
  await d.click(document.querySelector('.quick-customer-close'));
  assert.deepEqual(asked, [DISCARD, DISCARD, DISCARD], 'changed: each one asks');
  assert.equal(closed, 0, 'and No keeps it');
  await d.click([...document.querySelectorAll('.quick-customer-foot button')].find(b => b.textContent === 'Cancel'));
  assert.equal(asked.length, 3, 'Cancel does not ask');
  assert.equal(closed, 1);
  asked.length = 0;
});

test('Credit spending rules: the rules load after it opens', async () => {
  let closed = 0;
  await show(mod.CreditSpendingRules, {
    props: { packageId: 'c1', packageName: 'Made-up Credit', canEdit: true, onClose: () => { closed++; } },
    rpc: { credit_spendable_categories: ['product', 'voucher'], credit_package_effective_rules: { paid: ['product'], bonus: [] } },
  });
  await d.tick();
  const outside = () => document.querySelector('.credit-rules-backdrop');
  asked.length = 0;
  await d.click(outside());
  assert.deepEqual(asked, [], 'untouched: nothing is asked');
  assert.equal(closed, 1);
  await d.toggle(document.querySelector('.credit-rules input[type=checkbox]'));
  await d.click(outside());
  assert.deepEqual(asked, [DISCARD], 'a box changed: it asks');
  await d.click([...document.querySelectorAll('.credit-rules-foot button')].find(b => b.textContent === 'Close'));
  assert.equal(asked.length, 2, 'its Close button asks too');
  assert.equal(closed, 1, 'and No keeps it');
  asked.length = 0;
});

test('Claim vouchers', async () => {
  let closed = 0;
  await show(mod.VoucherClaimPanel, {
    props: { entitlementId: 'e1', canClaim: true, onClose: () => { closed++; } },
    rpc: { entitlement_voucher_state: { entitlement_id: 'e1', entitlement_no: 'ENT-TEST', package_name: 'Made-up Package', entitled: 5, claimed: 0, revoked: 0, remaining: 5,
      claim_deadline: null, deadline_passed: false, status: 'active', cancelled: false, snapshot_present: true,
      eligible: [{ voucher_id: 'v1', name: 'Made-up Voucher', available: 10, still_offered: true }] } },
  });
  await d.tick();
  const outside = () => document.querySelector('.credit-rules-backdrop');
  asked.length = 0;
  await d.click(outside());
  assert.deepEqual(asked, [], 'untouched: nothing is asked');
  assert.equal(closed, 1);
  await d.setValue(document.querySelector('.credit-rules input:not([type=checkbox])'), '2');
  await d.click(outside());
  await d.click([...document.querySelectorAll('.credit-rules-foot button')].find(b => b.textContent === 'Close'));
  assert.deepEqual(asked, [DISCARD, DISCARD], 'changed: a click outside and Close both ask');
  assert.equal(closed, 1, 'and No keeps it');
  asked.length = 0;
});

test('Claim a purchased package, whose choice and country are set as it loads', async () => {
  let closed = 0;
  await show(mod.PurchasedClaimPanel, {
    props: { purchasedId: 'u1', customerName: 'Made Up', customerPhone: '+61491570112', canCollectVouchers: true, canSwitch: true, onDone: () => {}, onSwitch: () => {}, onClose: () => { closed++; } },
    tables: { therapy_holiday_countries: [{ code: 'SG', name: 'Singapore' }] },
    rpc: { purchased_therapy_unit_state: { purchased_id: 'u1', entitlement_no: 'ENT-TEST', unit_label: 'Made-up Package', store_id: 's1',
      offered_choices: ['unlimited'], offers_choice: false, benefit_choice: null, choice_pending: true, choice_deadline: null, choice_deadline_passed: false,
      status: 'pending_activation', duration_months: 12, voucher_qty: 0, activation_deadline: null, scheduled_date: null, activation_date: null, expiry_date: null,
      voucher_entitlement_id: null, vouchers: null, eligible_vouchers: [], eligible_services: [], can_switch: false, holiday_country: 'SG', holiday_region: null } },
  });
  await d.tick();
  const outside = () => document.querySelector('.modal-overlay');
  asked.length = 0;
  await d.click(outside());
  assert.deepEqual(asked, [], 'untouched: nothing is asked');
  assert.equal(closed, 1);
  await d.setValue(document.querySelector('.modal input[type=date]'), '2030-01-02');
  await d.click(outside());
  assert.deepEqual(asked, [DISCARD], 'the start date changed: it asks');
  assert.equal(closed, 1, 'and No keeps it');
  asked.length = 0;
});
