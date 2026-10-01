// A stand-in for src/lib/supabase, used only by the preview harness: invented
// TikTok figures behind a fake client. Every amount is made up.
// Add ?fail=<rpc name> to the URL to make that call fail and see the error state.

const week = (payout_date: string, week_start: string, extra: Record<string, unknown> = {}) => ({
  payout_date, week_start, week_end: payout_date, finished: true, row_count: 3,
  revenue: 0, fee: 0, expense: 0, payout: 0, tiktok_net: 0,
  unknown_count: 0, balance_movement_count: 0, other_currency_count: 0, left_out_count: 0, left_out_settlement: 0,
  uncovered_days: [] as string[], ...extra,
});
// The reporting month's Wednesdays; the last one of the current month is not over.
const payouts = (year: number, month: number) => ({
  year, month, period_start: '', period_end: '', today: '', timezone: 'Asia/Singapore',
  undated_count: 0, income: 480.4, month_income: 480.4,
  weeks: [
    week('2026-09-02', '2026-08-27', { revenue: 512.3, fee: 81.25, expense: 36.9, payout: 394.15, tiktok_net: 394.15 }),
    week('2026-09-09', '2026-09-03', { revenue: 40, fee: 6.2, expense: 75.5, payout: -41.7, tiktok_net: -41.7 }),
    week('2026-09-16', '2026-09-10', { revenue: 96.5, fee: 15.05, expense: 0, payout: 81.45, tiktok_net: 81.45, left_out_count: 1, left_out_settlement: 18.6 }),
    week('2026-09-23', '2026-09-17', { revenue: 0, fee: 0, expense: 0, payout: 0, tiktok_net: -4, row_count: 1, unknown_count: 1, uncovered_days: ['2026-09-17', '2026-09-18'] }),
    week('2026-09-30', '2026-09-24', { finished: false, revenue: 60, fee: 9.5, expense: 4, payout: 46.5, tiktok_net: 46.5 }),
  ],
});
const tables: Record<string, any[]> = {
  stores: [{ id: 'st-1', name: 'Preview Store', deleted_at: null, is_active: true }],
  products: [], vouchers: [], promotions: [], tiktok_status_mappings: [], tiktok_physical_returns: [],
  tiktok_import_batches: [], tiktok_settlement_rows: [],
};
const rpcs: Record<string, (a: any) => unknown> = {
  my_assigned_store_id: () => null,
  report_tiktok_imports: () => [],
  report_tiktok_settlement: () => [],
  tiktok_settlement_totals: a => ({ year: a.p_year, month: a.p_month, period_start: '', period_end: '', timezone: 'Asia/Singapore', row_count: 11,
    revenue: 708.8, fee: 112, settlement: 596.8, expense: 116.4, income: 480.4, tiktok_net_settlement: 476.4, by_category: {},
    unknown_count: 1, balance_movement_count: 0, pending_match_count: 0, currency_count: 1, undated_count: 0, needs_review: true,
    left_out_count: 1, left_out_settlement: 18.6 }),
  tiktok_left_out_settlement: () => [],
  tiktok_xero_payouts: a => payouts(a.p_year, a.p_month),
};
const failures = new Set(new URLSearchParams(location.search).getAll('fail'));
class Query {
  filters: ((r: any) => boolean)[] = [];
  constructor(public kind: 'table' | 'rpc', public name: string, public args: any) {}
  select() { return this; }
  is(col: string, v: unknown) { this.filters.push(r => (r[col] ?? null) === v); return this; }
  eq(col: string, v: unknown) { this.filters.push(r => r[col] === v); return this; }
  in() { return this; }
  order() { return this; }
  range() { return this; }
  limit() { return this; }
  single() { return this; }
  maybeSingle() { return this; }
  async exec() {
    await new Promise(r => setTimeout(r, 150));
    if (failures.has(this.name)) return { data: null, error: { code: 'P0001', message: `Preview: ${this.name} failed` } };
    const src = this.kind === 'table' ? tables[this.name] : rpcs[this.name]?.(this.args);
    if (src === undefined) return { data: [], error: null };
    return { data: Array.isArray(src) ? src.filter(r => this.filters.every(f => f(r))) : src, error: null };
  }
  then(res: any, rej: any) { return this.exec().then(res, rej); }
}
export const supabase = {
  from: (name: string) => new Query('table', name, null),
  rpc: (name: string, args?: any) => new Query('rpc', name, args),
  auth: { getSession: async () => ({ data: { session: null } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) },
} as any;
