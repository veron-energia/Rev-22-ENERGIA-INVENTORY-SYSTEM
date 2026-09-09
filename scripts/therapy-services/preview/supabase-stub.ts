// A stand-in for src/lib/supabase, used only by the preview harness.
//
// It answers the RPCs TherapyServicesPage calls with fixture data shaped exactly
// as migrations 240 and 241 return it, so the page renders its real markup at
// real widths. It talks to nothing, and the two example services here are
// fixtures — not a statement about what the business actually sells.

const SERVICES = [
  { id: 'svc-power', service_code: 'PR', name: 'Power Recharge',
    description: 'Fixture service — not a production definition.',
    standard_price: 88, effective_price: 99, duration_minutes: 30,
    frequency_kind: 'per_hours', frequency_max_per_period: 1, frequency_interval_hours: 5,
    frequency_description: 'At most once every 5 hours, measured from the start of the previous session.',
    is_active: true, is_archived: false, store_count: 2,
    store_names: ['Bugis', 'Jurong'], available_here: true, has_price_override: true,
    can_manage: true },
  { id: 'svc-detox', service_code: 'FD', name: 'Foot Detox',
    description: 'Fixture service — not a production definition.',
    standard_price: 48, effective_price: 48, duration_minutes: 45,
    frequency_kind: 'per_day', frequency_max_per_period: 1, frequency_interval_hours: null,
    frequency_description: 'At most once per calendar day (Singapore, midnight to midnight).',
    is_active: true, is_archived: false, store_count: 1,
    store_names: ['Bugis'], available_here: true, has_price_override: false,
    can_manage: true },
  { id: 'svc-draft', service_code: 'NEW', name: 'Scalp Treatment',
    description: null,
    standard_price: 120, effective_price: 120, duration_minutes: null,
    frequency_kind: 'unrestricted', frequency_max_per_period: 1, frequency_interval_hours: null,
    frequency_description: 'No frequency limit.',
    is_active: false, is_archived: false, store_count: 0,
    store_names: [], available_here: false, has_price_override: false, can_manage: true },
];

const STORES = [
  { id: 'store-bugis', name: 'Bugis' },
  { id: 'store-jurong', name: 'Jurong' },
];

const VOUCHERS = [
  { id: 'v-flex', name: 'Two Therapy Sessions', code: 'THR2' },
  { id: 'v-fixed', name: 'One Power Recharge', code: 'PR1' },
  { id: 'v-plain', name: '$20 Off', code: 'OFF20' },
];

const DEFINITIONS: Record<string, any> = {
  'v-flex': {
    voucher_id: 'v-flex', voucher_name: 'Two Therapy Sessions', voucher_code: 'THR2',
    version: 2, selling_price: 120,
    validity_kind: 'months', validity_value: 6,
    validity_text: 'Valid for 6 month(s) from issue.',
    repeat_kind: 'per_week', repeat_max_per_period: 1, repeat_interval_hours: null,
    repeat_text: 'At most once per calendar week (Singapore, Monday to Sunday).',
    terms: null, sessions_per_voucher: 3,
    components: [
      { sort_order: 1, component_kind: 'fixed', quantity: 1, label: null,
        services: [{ service_id: 'svc-power', service_code: 'PR', name: 'Power Recharge',
                     duration_minutes: 30, frequency_kind: 'per_hours',
                     frequency_max_per_period: 1, frequency_interval_hours: 5 }] },
      { sort_order: 2, component_kind: 'choice', quantity: 2, label: null,
        services: [
          { service_id: 'svc-detox', service_code: 'FD', name: 'Foot Detox',
            duration_minutes: 45, frequency_kind: 'per_day',
            frequency_max_per_period: 1, frequency_interval_hours: null },
          { service_id: 'svc-power', service_code: 'PR', name: 'Power Recharge',
            duration_minutes: 30, frequency_kind: 'per_hours',
            frequency_max_per_period: 1, frequency_interval_hours: 5 }] },
    ],
  },
};

const STORE_ROWS = [
  { store_id: 'store-bugis', is_available: true, price_override: 99 },
  { store_id: 'store-jurong', is_available: true, price_override: null },
];

const ok = (data: any) => Promise.resolve({ data, error: null });

export const supabase = {
  rpc: (fn: string, args: any = {}) => {
    switch (fn) {
      case 'therapy_service_catalogue': return ok(SERVICES);
      case 'therapy_voucher_definition': return ok(DEFINITIONS[args.p_voucher_id] ?? null);
      case 'upsert_therapy_service':
      case 'set_therapy_service_store':
      case 'archive_therapy_service':
      case 'clear_therapy_voucher_definition':
        return ok(null);
      case 'upsert_therapy_voucher_definition':
        // Refuse the case the database refuses, so the error path is visible in
        // the preview rather than only in a test.
        if (!args.p_components?.length) {
          return Promise.resolve({ data: null, error: {
            message: 'State what this voucher gives: at least one fixed session or one choice group' } });
        }
        return ok(DEFINITIONS['v-flex']);
      default: return ok(null);
    }
  },
  from: (table: string) => ({
    select: () => {
      const rows = table === 'stores' ? STORES
                 : table === 'vouchers' ? VOUCHERS
                 : table === 'therapy_service_stores' ? STORE_ROWS : [];
      const chain: any = {
        eq: () => chain, is: () => chain, order: () => ok(rows),
        then: (r: any) => Promise.resolve({ data: rows, error: null }).then(r),
      };
      return chain;
    },
  }),
};
export default supabase;
