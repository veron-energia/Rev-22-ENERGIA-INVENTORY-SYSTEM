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

// ---- 359: the Therapy page itself — packages covering services, one-step Claim.
const SERVICES = [
  { id: 'sv-pr', name: 'PowerRecharge', service_code: 'PR', is_active: true, deleted_at: null,
    frequency_kind: 'per_hours', frequency_max_per_period: 1, frequency_interval_hours: 5 },
  { id: 'sv-meol', name: 'MEOL', service_code: 'MEOL', is_active: true, deleted_at: null,
    frequency_kind: 'unrestricted', frequency_max_per_period: 1, frequency_interval_hours: null },
  { id: 'sv-3in1', name: '3-in-1', service_code: '3IN1', is_active: true, deleted_at: null,
    frequency_kind: 'unrestricted', frequency_max_per_period: 1, frequency_interval_hours: null },
  { id: 'sv-old', name: 'Old Facial', service_code: 'OLD', is_active: false, deleted_at: '2026-09-01T00:00:00Z',
    frequency_kind: 'unrestricted', frequency_max_per_period: 1, frequency_interval_hours: null },
];
const VOUCHERS = [
  { id: 'vc-meol', name: 'MEOL Voucher', code: 'MEOL', voucher_kind: 'normal', reward_eligible: true, qty_type: 'limited', is_active: true, deleted_at: null },
  { id: 'vc-3in1', name: '3-in-1 Vouchers', code: '3IN1', voucher_kind: 'normal', reward_eligible: true, qty_type: 'unlimited', is_active: true, deleted_at: null },
  { id: 'vc-50', name: 'Staff Own Discount (50 %)', code: 'S50', voucher_kind: 'percentage_discount', reward_eligible: true, qty_type: 'unlimited', is_active: true, deleted_at: null },
];
const PACKAGES = [
  { id: 'pk-pr', name: '3 months - Unlimited Power Recharge Therapy', sku: 'PR-3', duration_months: 3,
    description: null, is_active: true, entitlement_kind: 'unlimited', voucher_qty: null, voucher_id: null, deleted_at: null },
  { id: 'pk-ch', name: '1 month - Unlimited MEOL and 3-in-1 Therapy', sku: null, duration_months: 1,
    description: 'Or 10 vouchers', is_active: true, entitlement_kind: 'choice', voucher_qty: 10, voucher_id: null, deleted_at: null },
  { id: 'pk-v', name: '5 Eye Spa vouchers', sku: null, duration_months: 1,
    description: null, is_active: true, entitlement_kind: 'voucher', voucher_qty: 5, voucher_id: 'vc-meol', deleted_at: null },
];
const PKG_SERVICES = [
  { package_id: 'pk-pr', service_id: 'sv-pr' },
  { package_id: 'pk-ch', service_id: 'sv-meol' }, { package_id: 'pk-ch', service_id: 'sv-3in1' },
];
const PKG_VOUCHERS = [{ package_id: 'pk-ch', voucher_id: 'vc-meol' }, { package_id: 'pk-ch', voucher_id: 'vc-3in1' }];
const PTE = [
  { id: 'e-choice', entitlement_no: 'UTP-0000013', customer_id: 'c1', store_id: 's1', package_id: 'pk-ch',
    package_name: '1 month - Unlimited MEOL and 3-in-1 Therapy', duration_months: 1, price_snapshot: 0,
    purchase_date: '2026-09-24', activation_deadline: '2027-09-24', scheduled_date: null, activation_date: null,
    expiry_date: null, status: 'pending_activation', eligible_service_ids: ['sv-meol', 'sv-3in1'],
    holiday_country: null, holiday_region: null, created_at: '2026-09-24T02:00:00Z' },
  { id: 'e-active', entitlement_no: 'UTP-0000012', customer_id: 'c2', store_id: 's1', package_id: 'pk-pr',
    package_name: '3 months - Unlimited Power Recharge Therapy', duration_months: 3, price_snapshot: 386,
    purchase_date: '2026-09-20', activation_deadline: '2027-09-20', scheduled_date: null, activation_date: '2026-09-21',
    expiry_date: '2026-12-25', status: 'active', eligible_service_ids: ['sv-pr'],
    holiday_country: 'SG', holiday_region: null, created_at: '2026-09-20T02:00:00Z' },
  { id: 'e-vouch', entitlement_no: 'UTP-0000011', customer_id: 'c3', store_id: 's1', package_id: 'pk-ch',
    package_name: '1 month - Unlimited MEOL and 3-in-1 Therapy', duration_months: 1, price_snapshot: 0,
    purchase_date: '2026-09-10', activation_deadline: '2027-09-10', scheduled_date: null, activation_date: null,
    expiry_date: null, status: 'pending_activation', eligible_service_ids: ['sv-meol', 'sv-3in1'],
    holiday_country: null, holiday_region: null, created_at: '2026-09-10T02:00:00Z' },
  { id: 'e-sched', entitlement_no: 'UTP-0000010', customer_id: 'c2', store_id: 's1', package_id: 'pk-pr',
    package_name: '3 months - Unlimited Power Recharge Therapy', duration_months: 3, price_snapshot: 386,
    purchase_date: '2026-09-05', activation_deadline: '2027-09-05', scheduled_date: '2026-10-05', activation_date: '2026-10-05',
    expiry_date: '2027-01-06', status: 'scheduled', eligible_service_ids: ['sv-pr'],
    holiday_country: 'SG', holiday_region: null, created_at: '2026-09-05T02:00:00Z' },
];
const unit = (e: any, extra: any) => ({
  purchased_id: e.id, entitlement_no: e.entitlement_no, customer_id: e.customer_id, customer_name: '',
  store_id: e.store_id, package_name: e.package_name, unit_index: 1, unit_count: 1,
  unit_label: `${e.package_name} — Unit 1 of 1`, invoice_id: 'i', invoice_no: 'INV-2026-0301',
  offers_choice: false, benefit_choice: 'unlimited', choice_pending: false, choice_deadline: e.activation_deadline,
  choice_deadline_passed: false, status: e.status, duration_months: e.duration_months,
  scheduled_date: e.scheduled_date, activation_date: e.activation_date, expiry_date: e.expiry_date,
  activation_deadline: e.activation_deadline, days_remaining: e.expiry_date ? 91 : null,
  voucher_entitlement_id: null, voucher_entitled: null, voucher_claimed: null, voucher_remaining: null, ...extra });
const UNITS = [
  unit(PTE[0], { offers_choice: true, benefit_choice: null, choice_pending: true }),
  unit(PTE[1], {}),
  unit(PTE[2], { offers_choice: true, benefit_choice: 'voucher', voucher_entitlement_id: 'te-1',
                 voucher_entitled: 10, voucher_claimed: 3, voucher_remaining: 7 }),
  unit(PTE[3], {}),
];
const COVERS = (ids: string[]) => SERVICES.filter(s => ids.includes(s.id)).map(s => ({
  service_id: s.id, name: s.name, archived: !!s.deleted_at,
  limit: s.frequency_kind === 'per_hours' ? 'At most once every 5 hours, measured from the start of the previous session.' : null }));
const UNIT_STATE: Record<string, unknown> = {
  'e-choice': { ...UNITS[0], offered_choices: ['unlimited', 'voucher'], voucher_qty: 10, vouchers: null,
    eligible_vouchers: [{ voucher_id: 'vc-3in1', name: '3-in-1 Vouchers' }, { voucher_id: 'vc-meol', name: 'MEOL Voucher' }],
    eligible_services: COVERS(['sv-meol', 'sv-3in1']), can_switch: false, holiday_country: null, holiday_region: null },
  'e-vouch': { ...UNITS[2], offered_choices: ['unlimited', 'voucher'], voucher_qty: 10,
    vouchers: { entitled: 10, claimed: 3, remaining: 7, deadline_passed: false },
    eligible_vouchers: [{ voucher_id: 'vc-3in1', name: '3-in-1 Vouchers' }, { voucher_id: 'vc-meol', name: 'MEOL Voucher' }],
    eligible_services: COVERS(['sv-meol', 'sv-3in1']), can_switch: false, holiday_country: null, holiday_region: null },
  'e-sched': { ...UNITS[3], offered_choices: ['unlimited'], voucher_qty: 0, vouchers: null, eligible_vouchers: [],
    eligible_services: COVERS(['sv-pr']), can_switch: false, holiday_country: 'SG', holiday_region: null },
};
(DETAIL.unlimited[0] as any).covers = COVERS(['sv-pr']);

const TABLES: Record<string, unknown[]> = {
  therapy_holiday_countries: COUNTRIES, therapy_closure_dates: CLOSURES,
  therapy_services: SERVICES, vouchers: VOUCHERS, unlimited_therapy_packages: PACKAGES,
  therapy_package_services: PKG_SERVICES, therapy_package_vouchers: PKG_VOUCHERS,
  purchased_therapy_entitlements: PTE, stores: [{ id: 's1', name: 'Energia Rev 22 (Adelphi)' }],
  voucher_store_stock: [{ voucher_id: 'vc-meol', current_qty: 40 }],
};

export async function fetchCustomersByIds(_ids: unknown[]) {
  return [{ id: 'c1', full_name: 'Moh Leng Chan', phone: '+19729483114' },
          { id: 'c2', full_name: 'Moses Toh', phone: '+6581113059' },
          { id: 'c3', full_name: 'Nurul Aisyah', phone: '+6591230001' }];
}
export function mergeCustomers<T extends { id: string }>(existing: T[], extra: any[]): T[] {
  const seen = new Set(existing.map(x => x.id));
  return [...existing, ...extra.filter(x => !seen.has(x.id))];
}

export const supabase = {
  rpc: async (name: string, args?: any) => {
    if (name === 'purchased_therapy_units') return { data: UNITS, error: null };
    if (name === 'purchased_therapy_unit_state') return { data: UNIT_STATE[args?.p_purchased_id] ?? null, error: null };
    if (name === 'claim_purchased_therapy') {
      return { data: args?.p_choice === 'unlimited'
        ? { success: true, choice: 'unlimited', activation: { status: 'active', activation_date: args.p_activation_date,
            expiry_date: '2026-10-26', base_expiry: '2026-10-24', closure_days_added: 2 } }
        : { success: true, choice: 'voucher', claim: args?.p_voucher_selections ? { claimed_now: 2, invoice_no: 'VC-INV-0007',
            issued: [{ quantity: 2, name: 'MEOL Voucher' }], state: { remaining: 5 } } : null }, error: null };
    }
    if (name === 'save_therapy_package') return { data: 'pk-new', error: null };
    return { data: RESPONSES[name] ?? null, error: null };
  },
  from: (table: string) => {
    let rows: any[] = (TABLES[table] ?? []) as any[];
    const chain: any = {};
    for (const m of ['select', 'is', 'gte', 'lte', 'order', 'limit', 'range', 'neq', 'not'])
      chain[m] = () => chain;
    chain.eq = (col: string, val: unknown) => { rows = rows.filter(r => !(col in r) || r[col] === val); return chain; };
    chain.in = (col: string, vals: unknown[]) => { rows = rows.filter(r => !(col in r) || vals.includes(r[col])); return chain; };
    chain.then = (r: any, j?: any) => Promise.resolve({ data: rows, error: null }).then(r, j);
    return chain;
  },
};
