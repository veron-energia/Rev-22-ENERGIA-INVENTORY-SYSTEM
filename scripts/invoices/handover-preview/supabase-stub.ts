// In-memory stand-in for src/lib/supabase, used only by the goods hand-over
// preview (399). Fixture data only (this repository is public): invented
// stores, customers, products and invoices. It keeps a small model of the
// goods (on the invoice, collected, out, in the store) so Record Payment's
// question, Hand over items, Record items returned, the "Goods out" badge and
// the copies can be pressed without a database or a login. Every RPC call is
// recorded on window.__calls; nothing is real and nothing is sent anywhere.

const date = '2026-10-06T02:00:00Z';
const common = { is_active: true, deleted_at: null };
const method = (id: string, name: string, extra: Record<string, unknown> = {}) =>
  ({ id, name, created_at: date, is_wallet_credit: false, wallet_category: null, ...common, ...extra });

const product = (id: string, name: string) => ({ id, name, sku: id.toUpperCase(), product_type: 'own', ...common });
const tables: Record<string, any[]> = {
  stores: [{ id: 'st-main', name: 'Preview Main Store', code: 'MAIN', created_at: '2026-07-03T07:35:38Z', ...common }],
  customers: [
    { id: 'c-1', full_name: 'Jane Tan', first_name: 'Jane', last_name: 'Tan', phone: '+6591392001', ...common },
    { id: 'c-2', full_name: 'Rex Teo', first_name: 'Rex', last_name: 'Teo', phone: '+6591392002', ...common },
  ],
  profiles: [{ id: 'u-owner', full_name: 'Preview owner', role: 'owner', ...common }, { id: 'u-staff', full_name: 'Preview staff', role: 'staff', ...common }],
  products: [product('p-pillow', 'Preview Pillow'), product('p-socks', 'Preview Socks'), product('p-beads', 'Preview Beads'),
             product('p-bottle', 'Preview Bottle')],
  store_inventory: [
    { store_id: 'st-main', product_id: 'p-pillow', current_qty: 6 }, { store_id: 'st-main', product_id: 'p-socks', current_qty: 20 },
    { store_id: 'st-main', product_id: 'p-beads', current_qty: 9 }, { store_id: 'st-main', product_id: 'p-bottle', current_qty: 1 },
  ],
  payment_methods: [method('pm-cash', 'Cash'), method('pm-nets', 'NETS'), method('pm-paynow', 'PayNow'), method('pm-visa', 'Visa Card')],
  invoices: [
    { id: 'inv-1', invoice_no: 'INV-2026-9101', store_id: 'st-main', customer_id: 'c-1', status: 'partially_paid',
      subtotal: 700, discount_total: 0, manual_discount: 0, total_amount: 700, paid_amount: 150, created_at: date,
      business_date: '2026-10-06', created_by: 'u-owner', edit_count: 0, fulfil_warehouse_id: null, ...common },
    { id: 'inv-2', invoice_no: 'INV-2026-9102', store_id: 'st-main', customer_id: 'c-2', status: 'unpaid',
      subtotal: 300, discount_total: 0, manual_discount: 0, total_amount: 300, paid_amount: 0, created_at: date,
      business_date: '2026-10-06', created_by: 'u-owner', edit_count: 0, fulfil_warehouse_id: null, ...common },
  ],
  invoice_items: [
    { id: 'ii-1', invoice_id: 'inv-1', line_kind: 'product', product_id: 'p-pillow', quantity: 2, unit_price: 100,
      line_total: 200, foc_quantity: 0, item_name_snapshot: 'Preview Pillow' },
    { id: 'ii-2', invoice_id: 'inv-1', line_kind: 'product', product_id: 'p-socks', quantity: 3, unit_price: 100,
      line_total: 300, foc_quantity: 0, item_name_snapshot: 'Preview Socks' },
    { id: 'ii-3', invoice_id: 'inv-1', line_kind: 'promotion', promotion_id: 'promo-sleep', quantity: 1, unit_price: 200,
      line_total: 200, foc_quantity: 0, item_name_snapshot: 'Preview Sleep Set' },
    { id: 'ii-4', invoice_id: 'inv-2', line_kind: 'product', product_id: 'p-socks', quantity: 3, unit_price: 100,
      line_total: 300, foc_quantity: 0, item_name_snapshot: 'Preview Socks' },
  ],
  promotion_items: [
    { id: 'pi-1', promotion_id: 'promo-sleep', item_type: 'product', product_id: 'p-beads', quantity: 2 },
    { id: 'pi-2', promotion_id: 'promo-sleep', item_type: 'product', product_id: 'p-bottle', quantity: 1 },
  ],
  invoice_payments: [
    { id: 'pay-1', invoice_id: 'inv-1', payment_method_id: 'pm-cash', amount: 150, created_at: date, effective_at: date,
      entry_kind: 'receipt' },
  ],
  invoice_service_staff: [], invoice_promotion_selections: [], invoice_revisions: [],
};

// The goods model: per invoice, what the lines need (via a promotion or not),
// what was handed over and is still out, and the history.
type Need = { product_id: string; qty: number; via?: string };
const needs: Record<string, Need[]> = {
  'inv-1': [{ product_id: 'p-pillow', qty: 2 }, { product_id: 'p-socks', qty: 3 },
            { product_id: 'p-beads', qty: 2, via: 'Preview Sleep Set' }, { product_id: 'p-bottle', qty: 1, via: 'Preview Sleep Set' }],
  'inv-2': [{ product_id: 'p-socks', qty: 3 }],
};
const out: Record<string, Record<string, number>> = { 'inv-1': { 'p-pillow': 1 }, 'inv-2': { 'p-socks': 1 } };
const history: Record<string, any[]> = {
  'inv-1': [{ id: 'h-1', kind: 'handover', source: 'payment', created_at: date, created_by_name: 'Preview staff', reason: null,
              items: [{ product_id: 'p-pillow', name: 'Preview Pillow', quantity: 1 }] }],
  'inv-2': [{ id: 'h-2', kind: 'handover', source: 'button', created_at: date, created_by_name: 'Preview staff', reason: null,
              items: [{ product_id: 'p-socks', name: 'Preview Socks', quantity: 1 }] }],
};
const nameOf = (id: string) => tables.products.find(p => p.id === id)?.name ?? id;
const shelf = (id: string) => tables.store_inventory.find(s => s.product_id === id);

function goodsStatus(invoiceId: string) {
  const inv = tables.invoices.find(i => i.id === invoiceId);
  if (!inv) return null;
  const paid = inv.status === 'paid';
  const byProduct: Record<string, { required: number; via: string[] }> = {};
  for (const n of needs[invoiceId] ?? []) {
    const r = byProduct[n.product_id] ??= { required: 0, via: [] };
    r.required += n.qty; if (n.via && !r.via.includes(n.via)) r.via.push(n.via);
  }
  const products = Object.entries(byProduct).map(([pid, r]) => {
    const o = out[invoiceId]?.[pid] ?? 0;
    const collected = paid ? r.required : Math.min(r.required, o);
    return { product_id: pid, name: nameOf(pid), required: r.required, collected, to_collect: r.required - collected,
             out: paid ? 0 : o, in_store: shelf(pid)?.current_qty ?? 0, via: r.via };
  });
  const sum = (k: string) => products.reduce((s, p: any) => s + p[k], 0);
  const open = ['unpaid', 'partially_paid'].includes(inv.status);
  return { invoice_id: inv.id, invoice_no: inv.invoice_no, status: inv.status, store_id: inv.store_id,
    store_name: 'Preview Main Store', open, fulfil_from_warehouse: !!inv.fulfil_warehouse_id,
    required_total: sum('required'), collected_total: sum('collected'), to_collect_total: sum('to_collect'), out_total: sum('out'),
    can_hand_over: open && !inv.fulfil_warehouse_id && sum('to_collect') > 0,
    can_record_return: open && sum('out') > 0 && new URLSearchParams(location.search).get('role') !== 'staff',
    products, history: history[invoiceId] ?? [] };
}

function handOver(invoiceId: string, items: { product_id: string; qty: number }[], source: string) {
  const done: any[] = [];
  for (const it of items) {
    const s = shelf(it.product_id);
    if (!s || s.current_qty < it.qty) throw new Error(`Not enough stock at Preview Main Store for "${nameOf(it.product_id)}": handing over ${it.qty}, the store has ${s?.current_qty ?? 0}`);
    s.current_qty -= it.qty;
    (out[invoiceId] ??= {})[it.product_id] = (out[invoiceId][it.product_id] ?? 0) + it.qty;
    done.push({ product_id: it.product_id, name: nameOf(it.product_id), quantity: it.qty });
  }
  const entry = { id: `h-${Math.random().toString(16).slice(2)}`, kind: 'handover', source, created_at: new Date().toISOString(),
                  created_by_name: 'Preview owner', reason: null, items: done };
  (history[invoiceId] ??= []).push(entry);
  return { success: true, replayed: false, handover_id: entry.id, kind: 'handover', source, items: done };
}

(window as any).__calls = [];
(window as any).__tables = tables;

function rpcData(name: string, a: any): any {
  switch (name) {
    case 'invoice_list_page': {
      const rows = tables.invoices.filter(i => !i.deleted_at).map(i => ({ ...i,
        customer_name: tables.customers.find(c => c.id === i.customer_id)?.full_name ?? null }));
      const sum = (k: string) => rows.reduce((s, i) => s + Number(i[k] || 0), 0);
      return { rows, total: rows.length, pages: rows.length ? 1 : 0,
        summary: { matching: rows.length, total_amount: sum('total_amount'), paid: sum('paid_amount'),
          outstanding: rows.reduce((s, i) => s + Math.max(0, Number(i.total_amount) - Number(i.paid_amount)), 0) } };
    }
    case 'my_assigned_store_id': return 'st-main';
    case 'my_assigned_stores': return [{ store_id: 'st-main', store_name: 'Preview Main Store' }];
    case 'customer_search': return tables.customers;
    case 'invoice_financial_position': {
      const inv = tables.invoices.find(i => i.id === a?.p_invoice_id);
      return { total: inv?.total_amount ?? 0, net_received: inv?.paid_amount ?? 0,
        outstanding: Math.max(0, Number(inv?.total_amount ?? 0) - Number(inv?.paid_amount ?? 0)), refund_due: 0, status: inv?.status };
    }
    case 'invoice_effective_affiliate': return { found: true, has_affiliate: false };
    case 'invoice_refund_options': {
      const inv = tables.invoices.find(i => i.id === a?.p_invoice_id);
      return { financial: { total: inv?.total_amount ?? 0, net_received: inv?.paid_amount ?? 0, outstanding: 0, refund_due: 0, status: inv?.status },
        sources: [], stock: [], benefits: [], lines: [], review_required: false };
    }
    case 'customer_credit_balances': return { customer_id: a?.p_customer_id, categories: { paid: 0 }, available_total: 0 };
    case 'invoice_benefit_review_options': return { lines: [] };
    case 'invoice_display_names': case 'invoice_therapy_summary': case 'exchange_invoice_details': case 'invoice_event_guests': return null;
    case 'invoice_bill_to_source': return '-';
    case 'invoice_goods_status': return goodsStatus(a?.p_invoice_id);
    case 'invoice_list_goods_out':
      return (a?.p_invoice_ids ?? []).map((id: string) => ({ invoice_id: id, quantity: goodsStatus(id)?.out_total ?? 0 }))
        .filter((r: any) => r.quantity > 0);
    case 'record_invoice_handover': return handOver(a.p_invoice_id, a.p_handover.items, 'button');
    case 'record_invoice_goods_return': {
      const done: any[] = [];
      for (const it of a.p_items) {
        const o = out[a.p_invoice_id] ?? {};
        o[it.product_id] = (o[it.product_id] ?? 0) - it.good - it.damaged - it.not_returned;
        const s = shelf(it.product_id); if (s) s.current_qty += it.good;
        done.push({ product_id: it.product_id, name: nameOf(it.product_id), good: it.good, damaged: it.damaged, not_returned: it.not_returned });
      }
      (history[a.p_invoice_id] ??= []).push({ id: `r-${Math.random().toString(16).slice(2)}`, kind: 'return', source: 'return',
        created_at: new Date().toISOString(), created_by_name: 'Preview owner', reason: a.p_reason, items: done });
      return { success: true, items: done };
    }
    case 'record_invoice_settlement': {
      const inv = tables.invoices.find(i => i.id === a.p_invoice_id);
      const amount = (a.p_payload?.receipts ?? []).reduce((s: number, r: any) => s + Number(r.amount || 0), 0);
      inv.paid_amount = Number(inv.paid_amount) + amount;
      for (const r of a.p_payload?.receipts ?? []) tables.invoice_payments.push({ id: `pay-${Math.random().toString(16).slice(2)}`,
        invoice_id: inv.id, payment_method_id: r.payment_method_id, amount: r.amount, created_at: new Date().toISOString(),
        effective_at: new Date().toISOString(), entry_kind: 'receipt' });
      inv.status = inv.paid_amount >= inv.total_amount - 0.001 ? 'paid' : 'partially_paid';
      const h = a.p_payload?.handover;
      let handover: any = undefined;
      if (h?.none) {
        (history[inv.id] ??= []).push({ id: `n-${Math.random().toString(16).slice(2)}`, kind: 'nothing_taken', source: 'payment',
          created_at: new Date().toISOString(), created_by_name: 'Preview owner', reason: null, items: [] });
        handover = { kind: 'nothing_taken', items: [] };
      } else if (h?.items) handover = handOver(inv.id, h.items, 'payment');
      return { success: true, receipts_recorded: 1, ...(handover ? { handover } : {}) };
    }
    default: return [];
  }
}

function query(table: string) {
  let rows = [...(tables[table] ?? [])];
  let one = false;
  const q: any = new Proxy({}, {
    get(_, key) {
      if (key === 'then') return (ok: any, bad: any) => Promise.resolve({ data: one ? (rows[0] ?? null) : rows, error: null, count: rows.length }).then(ok, bad);
      return (...args: any[]) => {
        if (key === 'eq') rows = rows.filter(r => r[args[0]] === args[1]);
        if (key === 'in') rows = rows.filter(r => args[1].includes(r[args[0]]));
        if (key === 'single' || key === 'maybeSingle') one = true;
        return q;
      };
    },
  });
  return q;
}

export const supabase: any = {
  from: (table: string) => query(table),
  rpc(name: string, args: any) {
    (window as any).__calls.push({ name, args });
    let data: any = null; let error: any = null;
    try { data = rpcData(name, args); } catch (e: any) { error = { message: e.message }; }
    const q: any = new Proxy({}, {
      get(_, key) {
        if (key === 'then') return (ok: any, bad: any) => Promise.resolve({ data, error }).then(ok, bad);
        return () => q;
      },
    });
    return q;
  },
  auth: { getSession: async () => ({ data: { session: null } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) },
  channel: () => ({ on() { return this; }, subscribe() { return this; } }), removeChannel: () => {},
  storage: { from: () => ({ upload: async () => ({ data: null, error: null }), getPublicUrl: () => ({ data: { publicUrl: '' } }) }) },
};
