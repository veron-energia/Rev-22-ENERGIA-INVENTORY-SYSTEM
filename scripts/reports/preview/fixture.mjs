// Synthetic fixture for the ReportsPage UI harness. No real data: every name
// is invented ("Customer 01", "Staff One"). Shapes follow the production
// function results (pg_get_function_result) and the table columns the page reads.

const sgtDate = iso => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(iso));

export function makeFixture({ extraCustomers = 0, extraInvoices = 0 } = {}) {
  const stores = [
    { id: 'st-1', name: 'North Store', is_active: true },
    { id: 'st-2', name: 'South Store', is_active: true },
  ];
  const warehouses = [
    { id: 'wh-1', name: 'Main Warehouse', is_active: true },
    { id: 'wh-2', name: 'Overflow Warehouse', is_active: true },
  ];
  const products = [
    { id: 'p-1', name: 'Product Alpha', sku: 'A-1' },
    { id: 'p-2', name: 'Product Beta', sku: 'B-1' },
    { id: 'p-3', name: 'Product Gamma', sku: 'C-1' },
  ];
  const profiles = [
    { id: 'u-0', full_name: 'Owner User', role: 'owner' },
    { id: 'u-1', full_name: 'Staff One', role: 'staff' },
    { id: 'u-2', full_name: 'Staff Two', role: 'manager' },
  ];
  const customers = Array.from({ length: 6 }, (_, i) => ({
    id: `c-${String(i + 1).padStart(2, '0')}`, full_name: `Customer ${String(i + 1).padStart(2, '0')}`,
    phone: `+650000000${i + 1}`, date_of_birth: i % 2 ? '1990-01-15' : null,
    gender: ['female', 'male', 'other', null, 'female', 'male'][i], gender_other: i === 2 ? 'Prefer not to say' : null,
    occupation: i % 3 === 0 ? 'Engineer' : null, deleted_at: null,
  }));
  const vouchers = [{ id: 'v-1', name: 'Voucher Facial', voucher_kind: 'single' }];
  const promotions = [{ id: 'pr-1', name: 'Promo Bundle', code: 'PROMO1' }];
  const specialProducts = [{ id: 'sp-1', name: 'Special Device' }];

  const invoices = [], items = [], ledger = [], serviceStaff = {};
  const inv = (n, store, cust, creator, status, date, total, lines, events, served = [creator]) => {
    const id = `inv-${String(n).padStart(2, '0')}`;
    invoices.push({ id, invoice_no: `INV-2026-${String(n).padStart(4, '0')}`, store_id: store, customer_id: cust, affiliate_id: null,
      created_by: creator, status, subtotal: total, discount_total: 0, total_amount: total, paid_amount: total,
      business_date: date, created_at: `${date}T03:00:00Z`, paid_at: `${date}T03:00:00Z`, locked_at: null, deleted_at: null });
    lines.forEach((l, i) => items.push({ id: `${id}-l${i + 1}`, invoice_id: id, product_id: null, special_product_id: null,
      voucher_id: null, promotion_id: null, topup_amount: 0, line_discount: 0, ...l }));
    events.forEach(([evid, sales_date, amount, event_kind]) => ledger.push({ invoice_id: id, event_id: evid, sales_date, amount, event_kind }));
    serviceStaff[id] = served;
    return id;
  };
  inv(1, 'st-1', 'c-01', 'u-1', 'paid', '2026-08-05', 200, [{ product_id: 'p-1', quantity: 2, line_total: 200, line_kind: 'product' }],
    [['ev-01', '2026-08-05', 200, 'receipt']]);
  inv(2, 'st-1', 'c-02', 'u-1', 'paid', '2026-08-12', 200, [
    { product_id: 'p-2', quantity: 1, line_total: 150, line_kind: 'product' },
    { voucher_id: 'v-1', quantity: 1, line_total: 50, line_kind: 'voucher' }],
    [['ev-02', '2026-08-12', 200, 'receipt'], ['rf-02', '2026-09-11', -10, 'refund']], ['u-1', 'u-2']);
  inv(3, 'st-2', 'c-03', 'u-2', 'paid', '2026-08-20', 300, [{ promotion_id: 'pr-1', quantity: 1, line_total: 300, topup_amount: 20, line_kind: 'promotion' }],
    [['ev-03a', '2026-08-20', 100, 'receipt'], ['ev-03b', '2026-09-03', 200, 'receipt']], []);
  inv(4, 'st-2', 'c-01', 'u-2', 'paid', '2026-08-28', 180, [
    { product_id: 'p-1', quantity: 1, line_total: 100, line_kind: 'product' },
    { product_id: 'p-3', quantity: 1, line_total: 80, line_kind: 'product' }],
    [['ev-04', '2026-08-28', 180, 'receipt'], ['rf-04', '2026-09-10', -80, 'refund']]);
  inv(5, 'st-1', 'c-04', 'u-1', 'paid', '2026-09-02', 500, [{ special_product_id: 'sp-1', quantity: 1, line_total: 500, line_kind: 'special_product' }],
    [['ev-05', '2026-09-02', 500, 'receipt']]);
  inv(6, 'st-1', 'c-05', 'u-1', 'paid', '2026-09-05', 60, [{ special_product_id: 'sp-1', quantity: 1, line_total: 60, line_kind: 'rental' }],
    [['ev-06', '2026-09-05', 60, 'receipt']]);
  inv(7, 'st-2', 'c-02', 'u-2', 'paid', '2026-09-15', 400, [{ product_id: 'p-2', quantity: 3, line_total: 450, line_discount: 50, line_kind: 'product' }],
    [['ev-07', '2026-09-15', 400, 'receipt']]);
  inv(8, 'st-1', 'c-03', 'u-1', 'paid', '2026-09-20', 100, [{ product_id: 'p-1', quantity: 1, line_total: 100, line_kind: 'product' }],
    [['ev-08a', '2026-09-20', 100, 'receipt'], ['ev-08b', '2026-09-21', -100, 'correction_reversal'], ['ev-08c', '2026-09-21', 100, 'correction_replacement']]);
  inv(9, 'st-2', 'c-06', 'u-2', 'completed_foc', '2026-09-25', 0, [{ product_id: 'p-3', quantity: 1, line_total: 0, line_kind: 'product' }], []);
  inv(10, 'st-1', 'c-01', 'u-1', 'unpaid', '2026-09-26', 250, [{ product_id: 'p-2', quantity: 1, line_total: 250, line_kind: 'product' }], []);

  const refunds = [
    { id: 'rf-02', invoice_id: 'inv-02', request_id: 'rq-02', amount: 10, credit_returned: 0, outcome: null },
    { id: 'rf-04', invoice_id: 'inv-04', request_id: 'rq-04', amount: 80, credit_returned: 0, outcome: { lines: [{ invoice_item_id: 'inv-04-l2', amount: 80 }] } },
  ];
  const commissions = [
    { id: 'cm-1', referrer_customer_id: 'c-06', invoice_id: 'inv-02', tier: 'tier1', status: 'paid', commission_amount: 20 },
    { id: 'cm-2', referrer_customer_id: 'c-06', invoice_id: 'inv-07', tier: 'tier1', status: 'earned', commission_amount: 40 },
    { id: 'cm-3', referrer_customer_id: 'c-05', invoice_id: 'inv-07', tier: 'tier2', status: 'earned', commission_amount: 10 },
    { id: 'cm-4', referrer_customer_id: 'c-06', invoice_id: 'inv-04', tier: 'tier1', status: 'reversed', commission_amount: 15 },
  ];
  const redemptions = [
    // 17:30 UTC on 31 Aug is 01:30 on 1 Sep in Singapore; 16:30 UTC on 27 Sep is 00:30 on 28 Sep.
    { id: 'rd-1', voucher_id: 'v-1', created_at: '2026-08-31T17:30:00Z', discount_applied: 30 },
    { id: 'rd-2', voucher_id: 'v-1', created_at: '2026-09-27T16:30:00Z', discount_applied: 20 },
    { id: 'rd-3', voucher_id: 'v-1', created_at: '2026-09-08T02:00:00Z', discount_applied: 25 },
  ];
  const specialSales = [
    { id: 'ss-1', special_product_id: 'sp-1', invoice_id: null, status: 'paid', created_at: '2026-09-10T03:00:00Z', total_amount: 700 },
    { id: 'ss-2', special_product_id: 'sp-1', invoice_id: 'inv-05', status: 'paid', created_at: '2026-09-02T03:00:00Z', total_amount: 500 },
  ];
  const rentals = [
    { id: 'rn-1', special_product_id: 'sp-1', invoice_id: null, status: 'returned', created_at: '2026-09-12T02:00:00Z', paid_at: '2026-09-12T02:00:00Z', returned_at: '2026-09-19T05:00:00Z', rental_fee: 90, late_fee_total: 15 },
    { id: 'rn-2', special_product_id: 'sp-1', invoice_id: 'inv-06', status: 'returned', created_at: '2026-09-05T03:00:00Z', paid_at: '2026-09-05T03:00:00Z', returned_at: '2026-09-06T03:00:00Z', rental_fee: 60, late_fee_total: 0 },
    { id: 'rn-3', special_product_id: 'sp-1', invoice_id: null, status: 'draft', created_at: '2026-09-13T02:00:00Z', paid_at: null, returned_at: null, rental_fee: 40, late_fee_total: 0 },
  ];
  const whInv = [
    { id: 'wi-1', warehouse_id: 'wh-1', product_id: 'p-1', current_qty: 50 },
    { id: 'wi-2', warehouse_id: 'wh-1', product_id: 'p-2', current_qty: 0 },
    { id: 'wi-3', warehouse_id: 'wh-1', product_id: 'p-3', current_qty: 10 },
    { id: 'wi-4', warehouse_id: 'wh-2', product_id: 'p-1', current_qty: 5 },
  ];
  const stInv = [
    { id: 'si-1', store_id: 'st-1', product_id: 'p-1', current_qty: 3 },
    { id: 'si-2', store_id: 'st-1', product_id: 'p-2', current_qty: 2 },
    { id: 'si-3', store_id: 'st-2', product_id: 'p-3', current_qty: 0 },
  ];

  // ---- scale-up for the performance run ----
  for (let i = 0; i < extraCustomers; i++) {
    customers.push({ id: `cx-${String(i).padStart(6, '0')}`, full_name: `Customer X${i}`, phone: `+6590${String(i).padStart(6, '0')}`,
      date_of_birth: null, gender: i % 2 ? 'female' : 'male', gender_other: null, occupation: null, deleted_at: null });
  }
  for (let i = 0; i < 147 && extraInvoices; i++) products.push({ id: `px-${i}`, name: `Product X${i}`, sku: `X-${i}` });
  for (let i = 0; i < 19 && extraInvoices; i++) vouchers.push({ id: `vx-${i}`, name: `Voucher X${i}`, voucher_kind: 'single' });
  for (let i = 0; i < 7 && extraInvoices; i++) promotions.push({ id: `prx-${i}`, name: `Promo X${i}`, code: `PX${i}` });
  for (let i = 0; i < extraInvoices; i++) {
    const n = 100 + i;
    const day = 1 + (i % 27);
    const month = i % 2 ? '08' : '09';
    const date = `2026-${month}-${String(day).padStart(2, '0')}`;
    const cust = extraCustomers ? `cx-${String((i * 37) % extraCustomers).padStart(6, '0')}` : 'c-01';
    const pa = `px-${i % 147}`, pb = `px-${(i * 7) % 147}`;
    const lines = [
      { product_id: pa, quantity: 1 + (i % 3), line_total: 100, line_kind: 'product' },
      { product_id: pb, quantity: 1, line_total: 50, line_kind: 'product' },
    ];
    if (i % 5 === 0) lines.push({ voucher_id: `vx-${i % 19}`, quantity: 1, line_total: 40, line_kind: 'voucher' });
    if (i % 11 === 0) lines.push({ promotion_id: `prx-${i % 7}`, quantity: 1, line_total: 60, topup_amount: 5, line_kind: 'promotion' });
    const total = lines.reduce((s, l) => s + l.line_total, 0);
    const events = i % 4 === 0
      ? [[`evx-${i}a`, date, total / 2, 'receipt'], [`evx-${i}b`, '2026-09-27', total / 2, 'receipt']]
      : [[`evx-${i}`, date, total, 'receipt']];
    inv(n, i % 2 ? 'st-1' : 'st-2', cust, i % 2 ? 'u-1' : 'u-2', 'paid', date, total, lines, events);
    if (i % 6 === 0) commissions.push({ id: `cmx-${i}`, referrer_customer_id: `cx-${String((i * 13) % Math.max(extraCustomers, 1)).padStart(6, '0')}`,
      invoice_id: `inv-${String(n).padStart(2, '0')}`, tier: 'tier1', status: 'earned', commission_amount: 10 });
    if (i % 2 === 0) redemptions.push({ id: `rdx-${i}`, voucher_id: `vx-${i % 19}`, created_at: `${date}T04:00:00Z`, discount_applied: 5 });
  }

  // ---- server-side report rows (the RPC result shapes) ----
  const storeName = id => stores.find(s => s.id === id)?.name ?? null;
  const custName = id => customers.find(c => c.id === id)?.full_name ?? null;
  const itemName = it => products.find(p => p.id === it.product_id)?.name ?? vouchers.find(v => v.id === it.voucher_id)?.name
    ?? promotions.find(p => p.id === it.promotion_id)?.name ?? specialProducts.find(p => p.id === it.special_product_id)?.name ?? 'Line';
  const paidInvoices = invoices.filter(i => ['paid', 'completed_foc'].includes(i.status));
  const pricing = items.filter(it => paidInvoices.some(i => i.id === it.invoice_id)).map(it => {
    const i = invoices.find(x => x.id === it.invoice_id);
    return { invoice_id: i.id, invoice_no: i.invoice_no, paid_date: i.id === 'inv-09' ? null : i.business_date, store_id: i.store_id,
      store_name: storeName(i.store_id), customer_name: custName(i.customer_id), line_kind: it.line_kind, item_name: itemName(it),
      quantity: it.quantity, unit_price: it.line_total / it.quantity, price_mode: 'member', price_overridden: false,
      override_reason: null, member_price: it.line_total / it.quantity, non_member_price: it.line_total / it.quantity };
  });
  const discounts = [
    { invoice_id: 'inv-02', invoice_no: 'INV-2026-0002', paid_date: '2026-08-12', store_name: 'North Store', staff_names: 'Staff One, Staff Two',
      customer_name: 'Customer 02', save_earth: 0, voucher_discount: 30, promotion_discount: 0, line_discount: 0, manual_discount: 0, total_discount: 30 },
    { invoice_id: 'inv-07', invoice_no: 'INV-2026-0007', paid_date: '2026-09-15', store_name: 'South Store', staff_names: 'Staff Two',
      customer_name: 'Customer 02', save_earth: 0, voucher_discount: 0, promotion_discount: 0, line_discount: 50, manual_discount: 0, total_discount: 50 },
  ];
  const focLines = [
    { invoice_id: 'inv-01', invoice_no: 'INV-2026-0001', invoice_status: 'paid', store_id: 'st-1', customer_name: 'Customer 01', line_kind: 'product',
      description: 'Product Alpha', quantity: 3, foc_quantity: 1, unit_price: 100, normal_value: 300, foc_value: 100, charged_value: 200,
      is_full_foc: false, foc_reason: 'Loyalty', foc_by_name: 'Staff One', settled_at: '2026-08-05T04:00:00Z' },
    // 17:00 UTC on 24 Sep is 01:00 on 25 Sep in Singapore.
    { invoice_id: 'inv-09', invoice_no: 'INV-2026-0009', invoice_status: 'completed_foc', store_id: 'st-2', customer_name: 'Customer 06', line_kind: 'product',
      description: 'Product Gamma', quantity: 1, foc_quantity: 1, unit_price: 80, normal_value: 80, foc_value: 80, charged_value: 0,
      is_full_foc: true, foc_reason: 'Goodwill', foc_by_name: 'Staff Two', settled_at: '2026-09-24T17:00:00Z' },
  ];
  const affiliates = [
    { customer_id: 'c-06', customer_name: 'Customer 06', member_id: 'M006', affiliate_state: 'active', block_reason: null, store_name: 'North Store',
      direct_referrals: 2, downline: 1, earned: 60, paid: 12, reversed: 15, blocked: 0, tier1_earned: 60, tier2_earned: 0 },
    { customer_id: 'c-05', customer_name: 'Customer 05', member_id: 'M005', affiliate_state: 'blocked', block_reason: 'Not verified', store_name: null,
      direct_referrals: 0, downline: 0, earned: 10, paid: 0, reversed: 0, blocked: 10, tier1_earned: 0, tier2_earned: 10 },
  ];
  const therapy = [
    { entitlement_no: 'UTP-T001', customer_name: 'Customer 01', package_name: '3 months - Unlimited', store_name: 'North Store', price_snapshot: 300,
      price_mode: 'member', purchase_date: '2026-08-20', activation_deadline: '2026-09-20', activation_date: '2026-08-21', expiry_date: '2026-11-21', status: 'active', is_legacy: false },
    { entitlement_no: 'UTP-T002', customer_name: 'Customer 03', package_name: 'Choice', store_name: null, price_snapshot: 0,
      price_mode: 'member', purchase_date: null, activation_deadline: null, activation_date: null, expiry_date: null, status: 'pending_activation', is_legacy: true },
  ];
  const sources = [
    { source_label: 'TikTok', is_active: true, customers_count: 4, surveys_count: 3 },
    { source_label: 'Walk-in', is_active: false, customers_count: 2, surveys_count: 0 },
  ];
  const ttSettlement = [
    { row_id: 'tt-1', store_name: 'North Store', financial_date: '2026-08-27', order_adjustment_id: 'ORD-1', txn_class: 'order', transaction_type: 'Order',
      finance_category: 'sale', matched_order_id: 'ORD-1', match_status: 'matched', settlement_amount: 180, revenue_amount: 200, fee_amount: 20,
      adjustment_amount: 0, refund_amount: 0, currency: 'SGD', reconciled: true, version_no: 1 },
    { row_id: 'tt-2', store_name: 'North Store', financial_date: '2026-09-03', order_adjustment_id: 'ORD-2', txn_class: 'order', transaction_type: 'Order',
      finance_category: 'sale', matched_order_id: null, match_status: 'pending', settlement_amount: 340.5, revenue_amount: 400, fee_amount: 59.5,
      adjustment_amount: 0, refund_amount: 0, currency: 'SGD', reconciled: false, version_no: 2 },
    { row_id: 'tt-3', store_name: 'South Store', financial_date: '2026-09-04', order_adjustment_id: 'ADJ-1', txn_class: 'adjustment', transaction_type: 'Ads',
      finance_category: 'expense', matched_order_id: null, match_status: 'matched', settlement_amount: 0, revenue_amount: 0, fee_amount: 0,
      adjustment_amount: 0, refund_amount: 0, currency: 'SGD', reconciled: null, version_no: 1 },
  ];
  const ttSummary = [{ total_settlement: 520.5, total_revenue: 600, total_fees: 79.5, total_adjustments: 0, total_refunds: 0,
    transactions: 3, matched_count: 2, pending_count: 1, unreconciled_count: 1 }];
  const ttDaily = [
    { day: '2026-08-27', transactions: 1, settlement: 180, revenue: 200, fees: 20, expense: 0, income: 180 },
    { day: '2026-09-03', transactions: 1, settlement: 340.5, revenue: 400, fees: 59.5, expense: 0, income: 340.5 },
  ];
  const ttByStore = [
    { store_name: 'North Store', transactions: 2, settlement: 520.5, revenue: 600, fees: 79.5, expense: 0, income: 520.5, pending_count: 1, unreconciled_count: 1 },
  ];
  const ttQty = [{ dimension: 'product', item_key: 'SKU-1', item_name: 'Product Alpha', orders: 2, net_units: 3 }];
  const ttStatus = [{ order_status: 'Completed', order_items: 3, net_deducted: 3 }];
  const exchanges = [
    { exchange_id: 'ex-1', exchange_no: 'EX-0001', invoice_no: 'INV-2026-0011', store_name: 'North Store', customer_name: 'Customer 04',
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

  return { stores, warehouses, products, profiles, customers, vouchers, promotions, specialProducts, invoices, items, ledger, serviceStaff,
    refunds, commissions, redemptions, specialSales, rentals, whInv, stInv, pricing, discounts, focLines, affiliates, therapy, sources,
    ttSettlement, ttSummary, ttDaily, ttByStore, ttQty, ttStatus, exchanges, trReceipts, trDisc, trOverdue, sgtDate };
}
