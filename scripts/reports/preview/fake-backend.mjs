// A fake Supabase client: the query-builder surface ReportsPage uses
// (from/select/is/order/range, rpc + gte/lte/order/range, thenable), applying
// PostgREST semantics that matter here: filters on the function result, ordering,
// and the 1000-row max-rows cap on every response.

const MAX_ROWS = 1000;

export function createBackend(fx) {
  const b = {
    calls: [],              // { kind, name, args, filters, range }
    failures: new Map(),    // name -> message (resolves with { error })
    rejections: new Map(),  // name -> message (the promise rejects, like a network failure)
    held: new Set(),        // names whose responses wait for release()
    holdAll: false,
    latencyMs: 0,
    _waiters: [],
    release() { const w = this._waiters; this._waiters = []; w.forEach(f => f()); },
    reset() { this.latencyMs = 0; this.calls.length = 0; this.failures.clear(); this.rejections.clear(); this.held.clear(); this.holdAll = false; this.release(); },
  };

  const inPeriod = (d, from, to) => !!d && (!from || d >= from) && (!to || d <= to);
  const tables = {
    invoices: () => fx.invoices, stores: () => fx.stores, products: () => fx.products, commissions: () => fx.commissions,
    customers: () => fx.customers, warehouses: () => fx.warehouses, warehouse_inventory: () => fx.whInv,
    store_inventory: () => fx.stInv, invoice_items: () => fx.items, vouchers: () => fx.vouchers, promotions: () => fx.promotions,
    voucher_redemptions: () => fx.redemptions, special_sales: () => fx.specialSales, rentals: () => fx.rentals,
    special_products: () => fx.specialProducts, profiles: () => fx.profiles, invoice_refunds: () => fx.refunds,
  };

  const staffReport = (from, to) => {
    const ev = fx.ledger.filter(e => inPeriod(e.sales_date, from, to));
    const per = new Map();
    for (const e of ev) {
      const invoice = fx.invoices.find(i => i.id === e.invoice_id);
      const served = fx.serviceStaff[e.invoice_id] ?? [];
      const people = served.length ? served : [invoice.created_by];
      const cents = Math.round(e.amount * 100);
      people.forEach((pid, k) => {
        const share = (Math.trunc(cents / people.length) + (k < Math.abs(cents % people.length) ? Math.sign(cents) : 0)) / 100;
        const p = fx.profiles.find(x => x.id === pid);
        const row = per.get(pid) ?? { staff_id: pid, staff_name: p?.full_name ?? null, is_active: true, invoices: new Set(),
          shared_sales: 0, receipts_on_invoices_served: 0, credited_as_creator: 0, backfilled_in: 0 };
        row.shared_sales += share; row.receipts_on_invoices_served += e.amount;
        if (!served.length) row.credited_as_creator += share;
        row.invoices.add(e.invoice_id); per.set(pid, row);
      });
    }
    const rows = [...per.values()].map(({ invoices, ...r }) => ({ ...r, invoices_served: invoices.size }))
      .sort((a, b) => b.shared_sales - a.shared_sales);
    const revenue = ev.reduce((s, e) => s + e.amount, 0);
    const staffTotal = rows.reduce((s, r) => s + r.shared_sales, 0);
    return { basis: 'fake', from, to, store_id: null, revenue, backfill_in: 0, backfill_out: 0, staff_total: staffTotal,
      credited_as_creator: rows.reduce((s, r) => s + r.credited_as_creator, 0), wallet_credit_not_counted: 0, rows,
      difference: Math.round((staffTotal - revenue) * 100) / 100 };
  };
  const focIn = (from, to) => fx.focLines.filter(l => inPeriod(fx.sgtDate(l.settled_at), from, to));

  const rpcs = {
    invoice_sales_ledger: () => fx.ledger,
    report_affiliates: () => fx.affiliates,
    report_therapy: () => fx.therapy,
    report_customer_sources: () => fx.sources,
    report_tiktok_settlement_summary: () => fx.ttSummary,
    report_tiktok_settlement: () => fx.ttSettlement,
    report_sales_by_service_staff: a => staffReport(a?.p_from, a?.p_to),
    report_pricing: () => fx.pricing,
    report_discounts: () => fx.discounts,
    report_foc_lines: a => focIn(a?.p_from, a?.p_to),
    report_foc_summary: a => {
      const l = focIn(a?.p_from, a?.p_to);
      const ids = new Set(l.map(x => x.invoice_id));
      return { invoice_count: ids.size, full_foc_invoices: new Set(l.filter(x => x.is_full_foc).map(x => x.invoice_id)).size,
        mixed_foc_invoices: new Set(l.filter(x => !x.is_full_foc).map(x => x.invoice_id)).size,
        foc_value: l.reduce((s, x) => s + x.foc_value, 0), charged_value: l.reduce((s, x) => s + x.charged_value, 0),
        normal_value: l.reduce((s, x) => s + x.normal_value, 0), foc_units: l.reduce((s, x) => s + x.foc_quantity, 0), by_kind: [], by_reason: [] };
    },
    report_sales_reconciliation: a => {
      const ev = fx.ledger.filter(e => inPeriod(e.sales_date, a?.p_from, a?.p_to));
      const ex = fx.exchanges.filter(e => inPeriod(fx.sgtDate(e.created_at), a?.p_from, a?.p_to));
      const tt = fx.ttSettlement.filter(t => inPeriod(t.financial_date, a?.p_from, a?.p_to));
      return [
        { channel: 'normal_invoices', transactions: new Set(ev.map(e => e.invoice_id)).size, amount: ev.reduce((s, e) => s + e.amount, 0) },
        { channel: 'exchange_invoices', transactions: ex.length, amount: ex.reduce((s, e) => s + e.topup_amount, 0) },
        { channel: 'tiktok', transactions: tt.length, amount: tt.reduce((s, t) => s + t.revenue_amount, 0) },
      ];
    },
    report_tiktok_settlement_daily: () => fx.ttDaily,
    report_tiktok_settlement_by_store: () => fx.ttByStore,
    report_tiktok_qty_sold: () => fx.ttQty,
    report_tiktok_orders_by_status: () => fx.ttStatus,
    report_exchange_invoices: () => fx.exchanges,
    report_events: () => [{ event_id: 'ev-1', name: 'Fixture Event', is_active: true, first_day: '2026-09-22', last_day: '2026-09-23', early_bird_until: '2026-09-10',
      days: [{ day: '2026-09-22', capacity: 40, registered: 41, attended: 30, ticket: 30, free: 11 }, { day: '2026-09-23', capacity: null, registered: 20, attended: 12, ticket: 15, free: 5 }],
      options: [{ option_id: 'eo-1', name: '1 Day', days_count: 1, price: 61, people: 20, early_bird_people: 12, foc_people: 1, revenue: 853.5 },
                { option_id: 'eo-2', name: '2 Days', days_count: 2, price: 94, people: 10, early_bird_people: 4, foc_people: 0, revenue: 752 }],
      sales: [{ store_id: 'st-1', store_name: 'Store One', invoices: 12, total_amount: 3400, paid_amount: 3100 }] }],
    report_transfer_receipts: () => fx.trReceipts,
    report_transfer_discrepancies: () => fx.trDisc,
    report_transfers_overdue: () => fx.trOverdue,
    tiktok_settlement_totals: a => ({ year: a.p_year, month: a.p_month, period_start: '2026-08-28', period_end: '2026-09-24', timezone: 'Asia/Singapore',
      row_count: 2, revenue: 400, fee: 59.5, settlement: 340.5, expense: 0, income: 340.5, tiktok_net_settlement: 340.5, by_category: {},
      unknown_count: 0, balance_movement_count: 0, pending_match_count: 1, currency_count: 1, undated_count: 0, needs_review: false }),
  };

  class Query {
    constructor(kind, name, args) { Object.assign(this, { kind, name, args, filters: [], orders: [], rangeV: null, cols: '*' }); }
    select(cols) { this.cols = cols ?? '*'; return this; }
    is(col, v) { this.filters.push([`is.${col}`, r => (r[col] ?? null) === v]); return this; }
    eq(col, v) { this.filters.push([`eq.${col}`, r => r[col] === v]); return this; }
    gte(col, v) { this.filters.push([`gte.${col}=${v}`, r => r[col] != null && r[col] >= v]); return this; }
    lte(col, v) { this.filters.push([`lte.${col}=${v}`, r => r[col] != null && r[col] <= v]); return this; }
    order(col, opts = {}) { this.orders.push([col, opts.ascending !== false]); return this; }
    range(a, z) { this.rangeV = [a, z]; return this; }
    async exec() {
      b.calls.push({ kind: this.kind, name: this.name, args: this.args, filters: this.filters.map(f => f[0]), range: this.rangeV });
      if (b.holdAll || b.held.has(this.name)) await new Promise(r => b._waiters.push(r));
      if (b.latencyMs) await new Promise(r => setTimeout(r, b.latencyMs));
      await Promise.resolve();
      if (b.rejections.has(this.name)) throw new TypeError(b.rejections.get(this.name));
      if (b.failures.has(this.name)) return { data: null, error: { message: b.failures.get(this.name), code: 'P0001' } };
      const src = this.kind === 'table' ? tables[this.name] : rpcs[this.name];
      if (!src) return { data: null, error: { message: `unknown ${this.kind} ${this.name}` } };
      let out = src(this.args);
      if (!Array.isArray(out)) return { data: out, error: null }; // jsonb scalar
      let rows = out.map(r => ({ ...r }));
      for (const [, f] of this.filters) rows = rows.filter(f);
      if (this.orders.length) rows.sort((x, y) => {
        for (const [c, asc] of this.orders) {
          const a = x[c], z = y[c];
          if (a === z) continue;
          if (a == null) return 1; if (z == null) return -1; // nulls last (PostgREST default for asc)
          const cmp = a < z ? -1 : 1; return asc ? cmp : -cmp;
        }
        return 0;
      });
      const [from, to] = this.rangeV ?? [0, Infinity];
      rows = rows.slice(from, Math.min(to + 1, from + MAX_ROWS));
      if (this.cols && this.cols !== '*') {
        const keys = this.cols.split(',').map(s => s.trim());
        rows = rows.map(r => Object.fromEntries(keys.map(k => [k, r[k]])));
      }
      return { data: rows, error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }

  b.client = {
    from: name => new Query('table', name, null),
    rpc: (name, args) => new Query('rpc', name, args),
  };
  return b;
}
