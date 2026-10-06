// In-memory stand-in for src/lib/supabase, used only by the payment QR preview.
// Fixture data only (this repository is public): invented stores, customers and
// invoices, production's payment method names, and placeholder QR images that
// say they are not payment codes. Every RPC call is recorded on window.__calls.
import paynowQr from './placeholder-paynow.svg';
import grabpayQr from './placeholder-grabpay.svg';
import atomeQr from './placeholder-atome.svg';

const date = '2026-10-06T02:00:00Z';
const common = { is_active: true, deleted_at: null };
const method = (id: string, name: string, extra: Record<string, unknown> = {}) =>
  ({ id, name, created_at: date, is_wallet_credit: false, wallet_category: null, ...common, ...extra });

const tables: Record<string, any[]> = {
  stores: [
    // Has all three images, so its own invoices show its own QR.
    { id: 'st-main', name: 'Preview Main Store', code: 'MAIN', created_at: '2026-07-03T07:35:38Z', ...common,
      qr_paynow_url: paynowQr, qr_grabpay_url: grabpayQr, qr_atome_url: atomeQr },
    // Has none, so its invoices borrow the main store's and say so.
    { id: 'st-van', name: 'Preview Van & Roadshow', code: 'VAN', created_at: '2026-07-30T04:10:44Z', ...common,
      qr_paynow_url: null, qr_grabpay_url: null, qr_atome_url: null },
  ],
  customers: [
    { id: 'c-1', full_name: 'Jane Tan', first_name: 'Jane', last_name: 'Tan', phone: '+6591392001', ...common },
    { id: 'c-2', full_name: 'John Lim', first_name: 'John', last_name: 'Lim', phone: '+6591392002', ...common },
  ],
  profiles: [{ id: 'u-owner', full_name: 'Preview owner', role: 'owner', ...common }, { id: 'u-staff', full_name: 'Preview staff', role: 'staff', ...common }],
  products: [{ id: 'p-tea', name: 'Preview Tea', sku: 'TEA', product_type: 'own', ...common }],
  store_inventory: [{ store_id: 'st-main', product_id: 'p-tea', current_qty: 50 }, { store_id: 'st-van', product_id: 'p-tea', current_qty: 50 }],
  payment_methods: [
    method('pm-amex', 'American Express'), method('pm-atome', 'Atome'), method('pm-atome-full', 'Atome full payment'),
    method('pm-bank', 'Bank Transfer'), method('pm-cash', 'Cash'), method('pm-credit', 'Credit Card'),
    method('pm-debit', 'Debit Card'), method('pm-grab', 'GrabPay'), method('pm-grab-full', 'GrabPay Full Payment'),
    method('pm-hitpay', 'HitPay (online)'), method('pm-master', 'Master Card'), method('pm-paynow', 'PayNow'),
    method('pm-stripe', 'Stripe (online)'), method('pm-visa', 'Visa Card'),
    method('pm-w-paid', 'Wallet — Paid Credit', { is_wallet_credit: true, wallet_category: 'paid' }),
  ],
  invoices: [
    { id: 'inv-1', invoice_no: 'INV-PREVIEW-0001', store_id: 'st-main', customer_id: 'c-1', status: 'unpaid',
      subtotal: 245.5, discount_total: 0, manual_discount: 0, total_amount: 245.5, paid_amount: 0, created_at: date,
      business_date: '2026-10-06', created_by: 'u-owner', edit_count: 0, ...common },
    { id: 'inv-2', invoice_no: 'INV-PREVIEW-0002', store_id: 'st-van', customer_id: 'c-2', status: 'unpaid',
      subtotal: 1080, discount_total: 0, manual_discount: 0, total_amount: 1080, paid_amount: 0, created_at: date,
      business_date: '2026-10-06', created_by: 'u-owner', edit_count: 0, ...common },
  ],
  invoice_items: [
    { id: 'ii-1', invoice_id: 'inv-1', line_kind: 'product', product_id: 'p-tea', quantity: 1, unit_price: 245.5,
      line_total: 245.5, foc_quantity: 0, item_name_snapshot: 'Preview Tea' },
    { id: 'ii-2', invoice_id: 'inv-2', line_kind: 'product', product_id: 'p-tea', quantity: 4, unit_price: 270,
      line_total: 1080, foc_quantity: 0, item_name_snapshot: 'Preview Tea' },
  ],
  invoice_payments: [], invoice_service_staff: [], invoice_promotion_selections: [], invoice_revisions: [],
};

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
      return { total: inv?.total_amount ?? 0, net_received: 0, outstanding: inv?.total_amount ?? 0, refund_due: 0, status: inv?.status };
    }
    case 'invoice_effective_affiliate': return { found: true, has_affiliate: false };
    case 'invoice_refund_options': {
      const inv = tables.invoices.find(i => i.id === a?.p_invoice_id);
      return { financial: { total: inv?.total_amount ?? 0, net_received: 0, outstanding: inv?.total_amount ?? 0, refund_due: 0, status: inv?.status },
        sources: [], stock: [], benefits: [], lines: [], review_required: false };
    }
    case 'customer_credit_balances': return { customer_id: a?.p_customer_id, categories: { paid: 0 }, available_total: 0 };
    case 'invoice_benefit_review_options': return { lines: [] };
    case 'invoice_display_names': case 'invoice_therapy_summary': case 'exchange_invoice_details': case 'invoice_event_guests': return null;
    case 'invoice_bill_to_source': return '-';
    // Recording a payment is not what this preview is for: say so plainly.
    case 'record_invoice_settlement': return { success: false, message: 'Preview only: no payment is recorded here.' };
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
    const data = rpcData(name, args);
    const q: any = new Proxy({}, {
      get(_, key) {
        if (key === 'then') return (ok: any, bad: any) => Promise.resolve({ data, error: null }).then(ok, bad);
        return () => q;
      },
    });
    return q;
  },
  auth: { getSession: async () => ({ data: { session: null } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) },
  channel: () => ({ on() { return this; }, subscribe() { return this; } }), removeChannel: () => {},
  storage: { from: () => ({ upload: async () => ({ data: null, error: null }), getPublicUrl: () => ({ data: { publicUrl: '' } }) }) },
};
