// A stand-in for src/lib/supabase, used only by the preview harness, so the
// invite form and the acceptance page can be checked at real phone widths
// without a database, a login, or an email being sent anywhere.
const STORES = [
  { id: '11111111-1111-1111-1111-111111111111', name: 'Orchard Central' },
  { id: '22222222-2222-2222-2222-222222222222', name: 'Jurong Point' },
  { id: '33333333-3333-3333-3333-333333333333', name: 'Tampines Mall' },
  { id: '44444444-4444-4444-4444-444444444444', name: 'Bugis Junction' },
];

const RPC: Record<string, unknown> = {
  assignable_roles: ['manager', 'inventory_manager', 'staff'],
  assignable_store_ids: STORES.map(s => s.id),
  user_admin_list: [],
};

export const supabase = {
  rpc: async (name: string) => ({ data: RPC[name] ?? null, error: null }),
  from: (table: string) => {
    const result = { data: table === 'stores' ? STORES : [], error: null };
    const chain: any = {
      select: () => chain, is: () => chain, eq: () => chain,
      maybeSingle: async () => ({ data: { full_name: 'Olivia Owner' }, error: null }),
      order: () => result, then: (r: any) => r(result),
    };
    return chain;
  },
  functions: { invoke: async () => ({ data: { ok: true }, error: null }) },
  auth: {
    getSession: async () => ({ data: { session: { access_token: 'x' } } }),
    getUser: async () => ({ data: { user: { id: 'u1', email: 'new.person@energia.test',
      user_metadata: { full_name: 'New Person', invited_to: 'energia_internal' } } } }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }),
    signOut: async () => ({}),
  },
};
