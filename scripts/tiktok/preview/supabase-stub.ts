// A stand-in for src/lib/supabase, used only by the preview harness: invented
// TikTok figures behind a fake client. Every amount is made up.
// Add ?fail=<rpc name> to the URL to make that call fail and see the error state.

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
  // TikTok's real payouts (375): one differs from the app's figure, two files
  // disagree on another, and two Wednesdays have none yet.
  tiktok_bank_payouts: a => ({ from: a.p_from, to: a.p_to, today: '', timezone: 'Asia/Singapore',
    payouts: [
      { reference_id: '3600000000000000101', paid_on: '2026-09-02', amount: 394.15, status: 'Transferred', transferred: true,
        file_name: 'income_preview_1.xlsx', disagreeing: [],
        wednesday: '2026-09-02', week_start: '2026-08-27', app_payout: 394.15, app_rows: 5, uncovered_days: [], left_out_count: 0 },
      { reference_id: '3600000000000000102', paid_on: '2026-09-09', amount: 20, status: 'Transferred', transferred: true,
        file_name: 'income_preview_1.xlsx', disagreeing: [{ amount: 200, file_name: 'income_preview_2.xlsx' }],
        wednesday: '2026-09-09', week_start: '2026-09-03', app_payout: 20, app_rows: 2, uncovered_days: [], left_out_count: 0 },
      { reference_id: '3600000000000000103', paid_on: '2026-09-16', amount: 39.75, status: 'Transferred', transferred: true,
        file_name: 'income_preview_2.xlsx', disagreeing: [],
        wednesday: '2026-09-16', week_start: '2026-09-10', app_payout: 81.45, app_rows: 4, uncovered_days: [], left_out_count: 1 },
    ],
    wednesdays_without_payout: [
      { wednesday: '2026-09-23', week_start: '2026-09-17', app_payout: 12.5, app_rows: 2, uncovered_days: ['2026-09-23'] },
      { wednesday: '2026-09-30', week_start: '2026-09-24', app_payout: 0, app_rows: 0,
        uncovered_days: ['2026-09-24', '2026-09-25', '2026-09-26', '2026-09-27', '2026-09-28', '2026-09-29', '2026-09-30'] },
    ] }),
  stage_tiktok_settlement_file: () => 'b-preview',
  tiktok_batch_balance_counts: () => ({ payouts: 5, others: 34 }),
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
