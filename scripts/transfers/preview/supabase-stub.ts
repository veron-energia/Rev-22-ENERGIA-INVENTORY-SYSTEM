// A stand-in for src/lib/supabase, used only by the preview harness. It talks
// to nothing; every store, product and invoice here is a fixture.

const STORES = [{ id: 'st-bugis', name: 'Bugis (fixture)' }, { id: 'st-jurong', name: 'Jurong (fixture)' }];
const WAREHOUSES = [{ id: 'wh-main', name: 'Main Warehouse (fixture)' }, { id: 'wh-east', name: 'East Warehouse (fixture)' }];
const PRODUCTS = [
  { id: 'p-pillow', name: 'Fixture Pillow', sku: 'FX-PIL' },
  { id: 'p-mat', name: 'Fixture Mat', sku: 'FX-MAT' },
  { id: 'p-cup', name: 'Fixture Cup', sku: 'FX-CUP' },
];
const PROFILES = [{ id: 'u-owner', full_name: 'Preview Owner' }, { id: 'u-staff', full_name: 'Preview Staff' }];

const planAsked = {
  invoice_no: 'INV-FIXTURE-0001', action: 'refund_full', refund_amount: 3900, refund_due: 0,
  window: { created_on: '2026-09-24', deadline: '2026-09-29', within: true, days_remaining: 3, override_required: false, creation_reliable: true },
  lines: [{ invoice_item_id: 'ii-1', name: 'Fixture Promotion', line_kind: 'promotion', quantity: 1, selected_quantity: 1, amount: 3900 }],
  stock: [{ movement_id: 'm1', product_name: 'Fixture Pillow', store_name: 'Bugis (fixture)', outstanding: 1, proposed_sellable: 1 }],
  sources: [{ payment_id: 'pay-1', method: 'PayNow', wallet: false, amount: 3900 }],
  overrides_required: [], blockers: [], summary: ['Refund S$3900.00'],
  requires_override: false, blocked: false, plan_hash: 'asked',
};
const stockNow = [
  ...planAsked.stock,
  { movement_id: 'm2', product_name: 'Fixture Mat', store_name: 'Bugis (fixture)', outstanding: 2, proposed_sellable: 2 },
  { movement_id: 'm3', product_name: 'Fixture Cup', store_name: 'Bugis (fixture)', outstanding: 1, proposed_sellable: 1 },
];
const planNow = {
  ...planAsked, stock: stockNow, plan_hash: 'now',
  effects: {
    money_returned: { total: 3900, destinations: planAsked.sources },
    benefits: [], stock_returned: stockNow, overrides: [],
  },
};

const TABLES: Record<string, any[]> = {
  stores: STORES, warehouses: WAREHOUSES, products: PRODUCTS, profiles: PROFILES,
  store_product_prices: [{ store_id: 'st-bugis', product_id: 'p-pillow' }, { store_id: 'st-jurong', product_id: 'p-pillow' }, { store_id: 'st-jurong', product_id: 'p-cup' }],
  store_inventory: [
    { store_id: 'st-bugis', product_id: 'p-pillow', current_qty: 12 },
    { store_id: 'st-bugis', product_id: 'p-mat', current_qty: 3 },
    { store_id: 'st-jurong', product_id: 'p-cup', current_qty: 7 },
  ],
  approval_requests: [
    { id: 'rq-1', request_type: 'invoice_refund', status: 'pending', requested_by: 'u-staff', approved_by: null,
      related_record_id: 'inv-1', reason: 'Customer returned everything (fixture)', response_note: null,
      created_at: '2026-09-26T02:00:00Z', approved_at: null,
      payload: { invoice_id: 'inv-1', invoice_no: 'INV-FIXTURE-0001', action: 'refund_full', requested_amount: '3900', plan: planAsked } },
    { id: 'rq-3', request_type: 'invoice_cancel', status: 'pending', requested_by: 'u-staff', approved_by: null,
      related_record_id: 'inv-3', reason: 'Wrong customer (fixture)', response_note: null,
      created_at: '2026-09-26T01:00:00Z', approved_at: null,
      payload: { invoice_id: 'inv-3', invoice_no: 'INV-FIXTURE-0003', action: 'cancel', requested_amount: '0',
        plan: { ...planAsked, action: 'cancel', refund_amount: 0, refund_due: 250, stock: [] } } },
    { id: 'rq-2', request_type: 'invoice_cancel', status: 'pending', requested_by: 'u-staff', approved_by: null,
      related_record_id: 'inv-2', reason: 'Raised before the guided workflow (fixture)', response_note: null,
      created_at: '2026-09-01T02:00:00Z', approved_at: null,
      payload: { invoice_id: 'inv-2', invoice_no: 'INV-FIXTURE-0002', return_stock: true } },
  ],
  transfer_requests: [
    { id: 'tr-1', transfer_type: 'store_to_warehouse', status: 'in_transit', source_type: 'store', source_id: 'st-bugis',
      dest_type: 'warehouse', dest_id: 'wh-main', requested_by: 'u-owner', note: 'End of roadshow (fixture)',
      created_at: '2026-09-26T03:00:00Z', dispatched_at: '2026-09-26T04:00:00Z', approved_at: '2026-09-26T04:00:00Z', approved_by: 'u-owner', version: 2 },
    { id: 'tr-3', transfer_type: 'store_to_warehouse', status: 'pending', source_type: 'store', source_id: 'st-jurong',
      dest_type: 'warehouse', dest_id: 'wh-east', requested_by: 'u-owner', note: 'Slow seller (fixture)',
      created_at: '2026-09-26T05:00:00Z', version: 1 },
    { id: 'tr-2', transfer_type: 'warehouse_to_store', status: 'pending', source_type: 'store', source_id: 'st-jurong',
      dest_type: 'store', dest_id: 'st-bugis', requested_by: 'u-owner', note: null,
      created_at: '2026-09-25T03:00:00Z', version: 1, edit_count: 1 },
  ],
  transfer_request_lines: [
    { id: 'l-1', transfer_request_id: 'tr-1', line_kind: 'product', product_id: 'p-pillow', quantity: 4, approved_quantity: 4, in_transit_quantity: 4 },
    { id: 'l-3', transfer_request_id: 'tr-3', line_kind: 'product', product_id: 'p-cup', quantity: 3 },
    { id: 'l-2', transfer_request_id: 'tr-2', line_kind: 'product', product_id: 'p-cup', quantity: 2 },
  ],
};

const RPC: Record<string, (args: any) => unknown> = {
  my_assigned_store_id: () => null,
  my_assigned_stores: () => [],
  invoice_rentals_awaiting_return: () => [],
  stock_transfer_details: () => null,
  transfer_revisions: () => [],
  invoice_action_request_detail: () => ({
    request_id: 'rq-1', status: 'pending', request_type: 'invoice_refund', action: 'refund_full',
    reason: 'Customer returned everything (fixture)', return_notes: null, requested_by: 'Preview Staff',
    store_id: 'st-bugis', store: 'Bugis (fixture)', invoice_id: 'inv-1', invoice_no: 'INV-FIXTURE-0001',
    requested_lines: [], requested_amount: '3900', requested_plan: planAsked, current_plan: planNow,
    changed: true, legacy: false,
  }),
};

function table(name: string) {
  let rows = [...(TABLES[name] ?? [])];
  const b: any = {
    then: (res: any, rej: any) => Promise.resolve({ data: rows, error: null }).then(res, rej),
  };
  for (const m of ['select', 'order', 'is', 'in', 'limit', 'neq', 'not', 'or', 'range']) b[m] = () => b;
  b.eq = (c: string, v: unknown) => { rows = rows.filter(r => !(c in r) || r[c] === v); return b; };
  b.gt = (c: string, v: number) => { rows = rows.filter(r => !(c in r) || r[c] > v); return b; };
  return b;
}

export const supabase = {
  from: table,
  rpc: async (fn: string, args: any) => ({ data: RPC[fn] ? RPC[fn](args) : null, error: null }),
} as any;
