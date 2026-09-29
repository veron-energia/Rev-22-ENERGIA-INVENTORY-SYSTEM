// In-memory stand-in for src/lib/supabase, used only by the invoice preview.
// Fixture data only (this repository is public). Every RPC call is recorded on
// window.__calls so the preview can be checked from the browser.
const date = '2026-10-05T02:00:00Z';
const common = { is_active: true, deleted_at: null };

// One event: Mon 19 and Tue 20 Oct 2026 at the van, 50% early bird until 9 Oct.
const EVENT = { id: 'ev-1', name: 'Preview Birthday', early_bird_until: '2026-10-09', early_bird_percent: 50 };
const DAYS = [{ day: '2026-10-19', capacity: 40, registered: 39 }, { day: '2026-10-20', capacity: null, registered: 12 }];
const OPTIONS = [
  { option_id: 'eo-1', option_name: '1 Day', days_count: 1, price: 61 },
  { option_id: 'eo-2', option_name: '2 Days', days_count: 2, price: 94 },
];

const tables: Record<string, any[]> = {
  stores: [{ id: 'st-van', name: 'Preview Van & Roadshow', code: 'VAN', ...common }],
  customers: [
    { id: 'c-1', full_name: 'Customer One', first_name: 'Customer', last_name: 'One', phone: '+65 9123 0001', ...common },
    { id: 'c-2', full_name: 'Customer Two', first_name: 'Customer', last_name: 'Two', phone: '+65 9123 0002', ...common },
  ],
  profiles: [{ id: 'u-owner', full_name: 'Preview owner', role: 'owner', ...common }, { id: 'u-staff', full_name: 'Preview staff', role: 'staff', ...common }],
  products: [{ id: 'p-tea', name: 'Preview Tea', sku: 'TEA', product_type: 'own', ...common }],
  store_inventory: [{ store_id: 'st-van', product_id: 'p-tea', current_qty: 50 }],
  payment_methods: [{ id: 'pm-cash', name: 'Cash', ...common }],
  invoices: [{
    id: 'inv-1', invoice_no: 'INV-2026-9001', store_id: 'st-van', customer_id: 'c-2', status: 'unpaid',
    subtotal: 61, discount_total: 0, manual_discount: 0, total_amount: 61, paid_amount: 0, created_at: date,
    business_date: '2026-10-05', created_by: 'u-owner', edit_count: 0, ...common,
  }],
  invoice_items: [{
    id: 'ii-1', invoice_id: 'inv-1', line_kind: 'event_ticket', product_id: null, quantity: 2, unit_price: 30.5,
    line_total: 61, foc_quantity: 0, event_ticket_option_id: 'eo-1', event_days: ['2026-10-19'],
    item_name_snapshot: 'Preview Birthday — 1 Day',
  }],
  invoice_payments: [], invoice_service_staff: [], invoice_promotion_selections: [], invoice_revisions: [],
};
const guests: Record<string, any[]> = {
  'ii-1': [{ guest_id: 'g-1', name: 'Customer Two', phone: '+65 9123 0002', customer_id: 'c-2', status: 'registered' },
           { guest_id: 'g-2', name: 'Guest Friend', phone: null, customer_id: null, status: 'registered' }],
};

(window as any).__calls = [];
(window as any).__tables = tables;

const optionsFor = (bdate: string) => OPTIONS.map(o => {
  const early = bdate <= EVENT.early_bird_until;
  return { ...o, unit_price: early ? Math.round(o.price * (100 - EVENT.early_bird_percent)) / 100 : o.price,
    early_bird: early, early_bird_until: EVENT.early_bird_until, event_id: EVENT.id, event_name: EVENT.name, days: DAYS };
});

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
    case 'my_assigned_store_id': return 'st-van';
    case 'my_assigned_stores': return [{ store_id: 'st-van', store_name: 'Preview Van & Roadshow' }];
    case 'customer_search': return tables.customers;
    case 'event_ticket_options_for_sale': return optionsFor(a?.p_business_date ?? '2026-10-05');
    case 'events_list': return [{ id: EVENT.id, name: EVENT.name }];
    case 'invoice_events': return (a?.p_invoice_ids ?? []).filter((id: string) =>
      tables.invoice_items.some(it => it.invoice_id === id && it.line_kind === 'event_ticket'))
      .map((id: string) => ({ invoice_id: id, event_id: EVENT.id, event_name: EVENT.name, source: 'ticket' }));
    case 'invoice_event_guests': {
      const lines = tables.invoice_items.filter(it => it.invoice_id === a?.p_invoice_id && it.line_kind === 'event_ticket');
      return { event: lines.length ? { event_id: EVENT.id, event_name: EVENT.name, source: 'ticket', override: false } : null,
        marked_not_event: false,
        lines: lines.map(it => ({ invoice_item_id: it.id, event_id: EVENT.id, event_name: EVENT.name,
          option_id: it.event_ticket_option_id, option_name: OPTIONS.find(o => o.option_id === it.event_ticket_option_id)?.option_name,
          days_count: OPTIONS.find(o => o.option_id === it.event_ticket_option_id)?.days_count,
          days: it.event_days, event_days: DAYS.map(d => d.day), guests: guests[it.id] ?? [] })) };
    }
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
    case 'invoice_benefit_review_options': return { lines: [] };
    case 'invoice_display_names': case 'invoice_therapy_summary': case 'exchange_invoice_details': return null;
    case 'invoice_bill_to_source': return '-';
    case 'preview_invoice_correction': return { invoice_no: tables.invoices.find(i => i.id === a?.p_invoice_id)?.invoice_no, status: 'unpaid', effects: [], needs_review: [], blocking: false };
    case 'create_invoice_with_details': {
      const id = `inv-${tables.invoices.length + 1}`;
      const lines = (a?.p_items ?? []) as any[];
      const items = lines.map((l, k) => {
        const o = optionsFor(a.p_header.business_date).find(x => x.option_id === l.event_ticket_option_id);
        const unit = o ? o.unit_price : 20;
        return { id: `${id}-l${k}`, invoice_id: id, line_kind: l.kind, product_id: l.product_id ?? null, quantity: l.quantity,
          unit_price: unit, line_total: unit * (l.quantity - (l.foc_quantity ?? 0)), foc_quantity: l.foc_quantity ?? 0,
          event_ticket_option_id: l.event_ticket_option_id ?? null, event_days: l.event_days ?? null,
          item_name_snapshot: o ? `${EVENT.name} — ${o.option_name}` : 'Preview Tea' };
      });
      for (const it of items) if (it.line_kind === 'event_ticket') {
        guests[it.id] = (lines[items.indexOf(it)].attendees ?? []).map((p: any, k: number) => ({ guest_id: `${it.id}-g${k}`, ...p, status: 'registered' }));
      }
      const total = items.reduce((s, it) => s + it.line_total, 0);
      tables.invoice_items.push(...items);
      tables.invoices.push({ id, invoice_no: `INV-2026-90${String(tables.invoices.length + 1).padStart(2, '0')}`, store_id: a.p_store_id,
        customer_id: a.p_customer_id, status: 'unpaid', subtotal: total, discount_total: 0, manual_discount: 0, total_amount: total,
        paid_amount: 0, created_at: new Date().toISOString(), business_date: a.p_header.business_date, created_by: 'u-owner', edit_count: 0, ...common });
      return id;
    }
    case 'correct_invoice': return { success: true };
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
