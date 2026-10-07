// In-memory stand-in for src/lib/supabase, used only by the 398 preview.
// Fixture data only (this repository is public): invented customers, stores,
// products and referrals. ?status=final shows the promotion as ended. Every
// RPC call is recorded on window.__calls.
const params = new URLSearchParams(window.location.search);
const status = params.get('status') ?? 'provisional';

const friend = (n: number, name: string, counted: boolean, visit: string | null) => ({
  customer_id: `f-${n}`, name, phone: `+659139${String(8000 + n)}`, referred_on: '2026-10-03', first_visit_on: visit, counted });

const report = {
  campaign: { code: '2026-10', title: 'October referral promotion', reward_reason: 'October referral reward',
    starts_on: '2026-10-01', ends_on: '2026-10-31', tiers: [10, 20, 50, 80], today: '2026-10-06', status },
  campaigns: [{ code: '2026-10', title: 'October referral promotion', starts_on: '2026-10-01', ends_on: '2026-10-31' }],
  referrers: [
    { referrer_customer_id: 'c-bob', name: 'Bob Lim', phone: '+6591398070', is_affiliate: true,
      counted: 21, referred_in_window: 23, tier_reached: 20, next_tier: 50, to_next: 29,
      reward: status === 'final' ? { reward_id: 'rw-1', tier: 20, friends_counted: 21, given_at: '2026-11-02T03:00:00+00:00',
        given_by_name: 'Preview owner', store_id: 's-1', store_name: 'Preview Main Store', note: null,
        items: [{ product_id: 'p-gift', product_name: 'Preview Gift Set', quantity: 2, use_no: 'SU-PREVIEW-0001' }] } : null,
      friends: [friend(1, 'Fixture Friend 1', true, '2026-10-04')] },
    { referrer_customer_id: 'c-fay', name: 'Fay Lum', phone: '+6591398050', is_affiliate: true,
      counted: 12, referred_in_window: 15, tier_reached: 10, next_tier: 20, to_next: 8, reward: null,
      friends: [friend(2, 'Gia Lo', true, '2026-10-05'), friend(3, 'Kit Au', true, '2026-10-07'),
                friend(4, 'Ian Su', false, null), friend(5, 'Jo Yee', false, '2026-09-20')] },
    { referrer_customer_id: 'c-gia', name: 'Gia Lo', phone: '+6591398051', is_affiliate: false,
      counted: 1, referred_in_window: 1, tier_reached: null, next_tier: 10, to_next: 9, reward: null,
      friends: [friend(6, 'Oli Ting', true, '2026-10-12')] },
    { referrer_customer_id: 'c-ned', name: 'Ned Bo', phone: '+6591398058', is_affiliate: false,
      counted: 0, referred_in_window: 2, tier_reached: null, next_tier: 10, to_next: 10, reward: null,
      friends: [friend(7, 'Max Ow', false, null), friend(8, 'Lou Ang', false, null)] },
  ],
};

const downline = {
  customer_id: 'c-fay', name: 'Fay Lum',
  tier1: [
    { customer_id: 'f-2', name: 'Gia Lo', phone: '+6591398051', joined_on: '2026-10-03', joined_from_created: false, visited: true, first_visit_on: '2026-10-05' },
    { customer_id: 'f-9', name: 'Cal Ee', phone: '+6591398042', joined_on: '2026-08-04', joined_from_created: true, visited: false, first_visit_on: null },
    { customer_id: 'f-4', name: 'Ian Su', phone: '+6591398053', joined_on: '2026-10-10', joined_from_created: false, visited: false, first_visit_on: null },
  ],
  tier2: [
    { customer_id: 'f-6', name: 'Oli Ting', phone: '+6591398059', parent_id: 'f-2', parent_name: 'Gia Lo',
      joined_on: '2026-10-11', joined_from_created: false, visited: true, first_visit_on: '2026-10-12' },
  ],
};

const customers = [
  { id: 'c-fay', full_name: 'Fay Lum', first_name: 'Fay', last_name: 'Lum', phone: '+6591398050', email: 'fay@sig.invalid', notes: null,
    is_active: true, created_at: '2026-09-01T00:00:00Z', referred_by: null, is_referrer: true, source_label: 'Walk-in', first_visit_on: '2026-09-02' },
  { id: 'c-gia', full_name: 'Gia Lo', first_name: 'Gia', last_name: 'Lo', phone: '+6591398051', email: null, notes: null,
    is_active: true, created_at: '2026-10-03T00:00:00Z', referred_by: 'c-fay', is_referrer: true, source_label: 'Friend', first_visit_on: '2026-10-05' },
  { id: 'c-cal', full_name: 'Cal Ee', first_name: 'Cal', last_name: 'Ee', phone: '+6591398042', email: null, notes: null,
    is_active: true, created_at: '2026-08-04T00:00:00Z', referred_by: 'c-fay', is_referrer: true, source_label: null, first_visit_on: null },
];

const tables: Record<string, any[]> = {
  stores: [{ id: 's-1', name: 'Preview Main Store', deleted_at: null, is_active: true }, { id: 's-2', name: 'Preview Van', deleted_at: null, is_active: true }],
  products: [{ id: 'p-gift', name: 'Preview Gift Set', sku: 'PV-GIFT', deleted_at: null }, { id: 'p-bottle', name: 'Preview Water Bottle', sku: 'PV-BOT', deleted_at: null }],
  store_inventory: [{ id: 'si-1', store_id: 's-1', product_id: 'p-gift', current_qty: 5 }, { id: 'si-2', store_id: 's-1', product_id: 'p-bottle', current_qty: 3 }],
  customer_phone_history: [],
  customers,
};

(window as any).__calls = [];

function rpcData(name: string, a: any): any {
  switch (name) {
    case 'search_customers': {
      let rows = customers;
      if (a?.p_visited === 'visited') rows = rows.filter(c => c.first_visit_on);
      if (a?.p_visited === 'not_visited') rows = rows.filter(c => !c.first_visit_on);
      if (a?.p_visit_from) rows = rows.filter(c => c.first_visit_on && c.first_visit_on >= a.p_visit_from);
      if (a?.p_visit_to) rows = rows.filter(c => c.first_visit_on && c.first_visit_on <= a.p_visit_to);
      return rows.map(c => ({ ...c, total_count: rows.length }));
    }
    case 'active_customer_source_options': return [];
    case 'customer_profile_stats': return { purchases: 2, total_spend: 480, referred_count: 3, referrer_name: null };
    case 'customer_purchase_timeline': return [];
    case 'customer_downline_visits': return downline;
    case 'affiliate_admin_directory': return [{ customer_id: 'c-fay', name: 'Fay Lum', status: 'active', manually_suspended: false,
      referral_code: 'PVFAY', portal_account: 'claimed', direct_referrals: 3, tier2: 1, lifetime: 0, unpaid: 0, blocked: 0, last_commission: null }];
    case 'affiliate_staff_directory': return { total: 1, rows: [{ customer_id: 'c-fay', full_name: 'Fay Lum', referral_code: 'PVFAY', status: 'active', link_usable: true }] };
    case 'affiliate_pending_claims': case 'affiliate_rejected_claims': return [];
    case 'referral_campaign_report': return report;
    case 'give_referral_campaign_reward': return { success: true, reward_id: 'rw-2', tier: 10, store_name: 'Preview Main Store',
      items: (a?.p_items ?? []).map((i: any, k: number) => ({ ...i, use_no: `SU-PREVIEW-010${k}` })) };
    case 'void_referral_campaign_reward': return { success: true };
    case 'affiliate_portal_network': return { tier1: [
      { customer_name: 'Gia Lo', tier: 'tier1', referral_date: '2026-10-03T02:00:00Z', joined_at: '2026-10-03T02:00:00Z', purchases: 1, total_spent: 120, your_commission: 18 },
      { customer_name: 'Cal Ee', tier: 'tier1', referral_date: null, joined_at: '2026-08-04T02:00:00Z', purchases: 0, total_spent: 0, your_commission: 0 },
    ], tier2: [] };
    case 'affiliate_portal_campaign_progress': return { campaign: { ...report.campaign }, counted: 12, referred_in_window: 15,
      tier_reached: 10, next_tier: 20, to_next: 8, reward_tier: null, reward_given_at: null };
    default: return null;
  }
}

class Query {
  filters: ((r: any) => boolean)[] = [];
  from: number | null = null; to: number | null = null; one = false;
  constructor(public kind: 'table' | 'rpc', public name: string, public args: any) {}
  select() { return this; }
  eq(c: string, v: any) { this.filters.push(r => r[c] === v); return this; }
  is(c: string, v: any) { this.filters.push(r => (r[c] ?? null) === v); return this; }
  gt(c: string, v: number) { this.filters.push(r => Number(r[c]) > v); return this; }
  in(c: string, vs: any[]) { this.filters.push(r => vs.includes(r[c])); return this; }
  or() { return this; }
  ilike() { return this; }
  order() { return this; }
  limit() { return this; }
  range(a: number, z: number) { this.from = a; this.to = z; return this; }
  maybeSingle() { this.one = true; return this; }
  single() { this.one = true; return this; }
  async exec() {
    (window as any).__calls.push({ kind: this.kind, name: this.name, args: this.args });
    await new Promise(r => setTimeout(r, 60));
    if (this.kind === 'rpc') return { data: structuredClone(rpcData(this.name, this.args)), error: null };
    let rows = (tables[this.name] ?? []).filter(r => this.filters.every(f => f(r)));
    if (this.from != null) rows = rows.slice(this.from, (this.to ?? rows.length) + 1);
    return { data: structuredClone(this.one ? rows[0] ?? null : rows), error: null };
  }
  then(res: any, rej: any) { return this.exec().then(res, rej); }
}

export const supabase: any = {
  from: (name: string) => new Query('table', name, null),
  rpc: (name: string, args?: any) => new Query('rpc', name, args),
  auth: { getSession: async () => ({ data: { session: null } }), onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }) },
};
export default supabase;
