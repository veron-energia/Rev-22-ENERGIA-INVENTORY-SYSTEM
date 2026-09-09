// A stand-in for src/lib/supabase, used only by the preview harness.
//
// It answers the RPCs the therapy components call with fixture data shaped
// exactly like migrations 220-223 return, so the components render their real
// markup at real widths. It talks to nothing.

const CUSTOMERS = [
  { customer_id: 'c1', customer_name: 'Nurul Aisyah binte Abdullah', customer_phone: '+6591230001',
    therapy_vouchers_issued: 16, therapy_vouchers_redeemed: 3, therapy_vouchers_remaining: 12,
    money_vouchers_remaining: 4, vouchers_revoked: 1,
    unlimited_active: 1, unlimited_scheduled: 1, unlimited_pending: 0, unlimited_finished: 2,
    current_unlimited_expiry: '2026-11-08', current_unlimited_days_remaining: 61,
    next_unlimited_start: '2026-11-09', needs_review: false, total_customers: 3 },
  { customer_id: 'c2', customer_name: 'Tan Wei Ming', customer_phone: '+6598887777',
    therapy_vouchers_issued: 10, therapy_vouchers_redeemed: 10, therapy_vouchers_remaining: 0,
    money_vouchers_remaining: 0, vouchers_revoked: 0,
    unlimited_active: 0, unlimited_scheduled: 0, unlimited_pending: 1, unlimited_finished: 0,
    current_unlimited_expiry: null, current_unlimited_days_remaining: null,
    next_unlimited_start: null, needs_review: true, total_customers: 3 },
  { customer_id: 'c3', customer_name: 'Chen Mei', customer_phone: '+6598887777',
    therapy_vouchers_issued: 8, therapy_vouchers_redeemed: 0, therapy_vouchers_remaining: 8,
    money_vouchers_remaining: 2, vouchers_revoked: 0,
    unlimited_active: 0, unlimited_scheduled: 1, unlimited_pending: 0, unlimited_finished: 0,
    current_unlimited_expiry: null, current_unlimited_days_remaining: null,
    next_unlimited_start: '2026-10-09', needs_review: false, total_customers: 3 },
];

const EXPLANATION = {
  activation_date: '2026-09-05', months: 2, convention: 'purchased',
  country: 'SG', region: null,
  base_expiry: '2026-11-04', adjusted_expiry: '2026-11-08', added_days: 4,
  expiry_is_inclusive: true,
  applied: [
    { date: '2026-09-14', weekday: 'Mon', names: ['Company closure — refurbishment'], kinds: ['company_closure'], scope: 'all countries' },
    { date: '2026-10-09', weekday: 'Fri', names: ['Public holiday'], kinds: ['public_holiday'], scope: 'SG' },
    { date: '2026-11-09', weekday: 'Mon', names: ['Deepavali (observed)'], kinds: ['public_holiday'], observed_for: '2026-11-08', scope: 'SG' },
    { date: '2026-11-05', weekday: 'Thu', names: ['Stocktake'], kinds: ['company_closure'], scope: 'SG' },
  ],
  skipped_sundays: [
    { date: '2026-11-08', names: ['Deepavali'], why: 'Sunday — the business is closed anyway' },
  ],
};

const DETAIL = {
  customer: { id: 'c1', name: 'Nurul Aisyah binte Abdullah', phone: '+6591230001' },
  as_of: '2026-09-08', expiry_is_inclusive: true,
  vouchers: [
    { voucher_id: 'v1', name: 'Therapy Session', kind: 'normal', unit: 'session',
      source_type: 'legacy_entitlement', source: 'Legacy qualification reward', source_ref: 'e1',
      issued: 10, redeemed: 0, revoked: 0, remaining: 10,
      valid_until: null, expired: false, voucher_active: true },
    { voucher_id: 'v1', name: 'Therapy Session', kind: 'normal', unit: 'session',
      source_type: 'premium_bundle', source: 'Premium bundle', source_ref: 'b1',
      issued: 6, redeemed: 3, revoked: 1, remaining: 2,
      valid_until: '2027-01-31', expired: false, voucher_active: true },
    { voucher_id: 'v2', name: 'S$20 off any treatment', kind: 'fixed_discount', unit: 'money',
      source_type: 'promotion', source: 'Promotion', source_ref: 'p1',
      issued: 4, redeemed: 0, revoked: 0, remaining: 4,
      valid_until: '2026-12-31', expired: false, voucher_active: true },
  ],
  redemptions: [{ at: '2026-08-20T04:00:00Z', voucher: 'Therapy Session', invoice_id: 'i1', discount_applied: 0 }],
  revocations: [{ voucher: 'Therapy Session', quantity: 1, notes: 'Bundle refunded', issued_at: '2026-07-02T04:00:00Z' }],
  unlimited: [{
    kind: 'purchased', id: 'u1', entitlement_no: 'PTE-000412', package_name: '2 Month Unlimited',
    months: 2, source: 'Purchased', status: 'active',
    scheduled_date: null, activation_date: '2026-09-05',
    base_expiry: '2026-11-04', closure_days_added: 4, expiry_date: '2026-11-08',
    holiday_country: 'SG', holiday_region: null, holiday_country_source: 'phone',
    calendar_days_remaining: 61,
    coverage: { verified: false, country: 'SG', missing_years: [2027],
                reasons: ['SG has no verified holiday calendar for 2027.'] },
    explanation: EXPLANATION,
    adjustments: [{ at: '2026-09-05T02:00:00Z', action: 'country_assigned', reason: null,
                    old_expiry: null, new_expiry: '2026-11-08', old_country: null, new_country: 'SG' }],
  }],
  pending: [{ kind: 'legacy', entitlement_no: 'ENT-000891', status: 'pending_activation',
              reward_kind: 'unlimited', voucher_qty: null, months: 1, deadline: '2027-03-31' }],
};

const REWARD_OPTIONS = [
  { rule_id: 'r1', name: '1 Month Unlimited Therapy', entitlement_kind: 'unlimited',
    duration_months: 1, voucher_qty: null, tier_key: 't1', applies_to: 'customer', is_current_choice: true },
  { rule_id: 'r2', name: '10 Therapy Vouchers', entitlement_kind: 'voucher',
    duration_months: null, voucher_qty: 10, tier_key: 't1', applies_to: 'customer', is_current_choice: false },
];

const VOUCHER_OPTIONS = [
  { voucher_id: 'v1', name: 'Therapy Session', code: 'TS', available_qty: null },
  { voucher_id: 'v3', name: 'Deep Tissue Session', code: 'DT', available_qty: 6 },
  { voucher_id: 'v4', name: 'Hot Stone Session', code: 'HS', available_qty: 2 },
];

const RESPONSES: Record<string, unknown> = {
  therapy_customer_summary: CUSTOMERS,
  therapy_customer_detail: DETAIL,
  legacy_reward_options: REWARD_OPTIONS,
  legacy_reward_options_diagnostic: { found: true, option_count: 2, has_choice: true, reasons: [] },
  legacy_reward_voucher_options: VOUCHER_OPTIONS,
  therapy_calendar_gaps: { verified: false, country: 'SG', missing_years: [2027],
                           reasons: ['SG has no verified holiday calendar for 2027.'] },
  therapy_recalculation_preview: [
    { entitlement_kind: 'purchased', entitlement_id: 'u1', entitlement_no: 'PTE-000412',
      customer_id: 'c1', customer_name: 'Nurul Aisyah binte Abdullah', status: 'active',
      activation_date: '2026-09-05', months: 2, holiday_country: 'SG', holiday_region: null,
      current_expiry: '2026-11-04', base_expiry: '2026-11-04', proposed_expiry: '2026-11-08',
      days_added: 4, change_days: 4, shortens: false, needs_country: false,
      coverage: { verified: false, reasons: ['SG has no verified holiday calendar for 2027.'] } },
    { entitlement_kind: 'legacy', entitlement_id: 'u2', entitlement_no: 'ENT-000733',
      customer_id: 'c2', customer_name: 'Tan Wei Ming', status: 'scheduled',
      activation_date: '2026-10-01', months: 1, holiday_country: null, holiday_region: null,
      current_expiry: '2026-10-31', base_expiry: '2026-10-31', proposed_expiry: '2026-10-31',
      days_added: 0, change_days: 0, shortens: false, needs_country: true,
      coverage: { verified: false, reasons: ['No holiday country is assigned.'] } },
  ],
  therapy_reward_mapping_preview: [
    { entitlement_id: 'e9', entitlement_no: 'ENT-000512', customer_id: 'c2',
      customer_name: 'Tan Wei Ming', recipient: 'customer', qualifying_amount: '794.00',
      current_kind: 'unlimited', current_months: 1, current_qty: null,
      activation_deadline: '2027-01-15', option_count: 0, mapped_tier: null,
      candidates: [{ tier_key: 'customer:994.00:s1', qualifying_amount: '994.00',
                     kinds: ['unlimited', 'voucher'],
                     names: ['1 Month Unlimited Therapy', '10 Therapy Vouchers'],
                     alternatives: 2, closeness: 0, threshold_differs: true }] },
  ],
};

const CLOSURES = [
  { id: 'x1', closure_date: '2026-08-09', kind: 'public_holiday', name: 'National Day',
    country_code: 'SG', region: null, observed_for: null, source: 'mom.gov.sg', source_reference: null },
  { id: 'x2', closure_date: '2026-08-10', kind: 'public_holiday', name: 'National Day (observed)',
    country_code: 'SG', region: null, observed_for: '2026-08-09', source: 'mom.gov.sg', source_reference: null },
  { id: 'x3', closure_date: '2026-09-14', kind: 'company_closure', name: 'Refurbishment — all outlets',
    country_code: null, region: null, observed_for: null, source: 'Management notice', source_reference: null },
];

const COUNTRIES = [
  { code: 'SG', name: 'Singapore', is_active: true, requires_region: false, notes: null },
  { code: 'MY', name: 'Malaysia', is_active: true, requires_region: true, notes: null },
];

export const supabase = {
  rpc: async (name: string, _args?: unknown) => ({ data: RESPONSES[name] ?? null, error: null }),
  from: (table: string) => {
    const rows = table === 'therapy_holiday_countries' ? COUNTRIES
               : table === 'therapy_closure_dates' ? CLOSURES : [];
    const result = { data: rows, error: null };
    const chain: any = {
      select: () => chain, is: () => chain, gte: () => chain, lte: () => chain,
      order: () => result, then: (r: any) => r(result),
    };
    return chain;
  },
};
