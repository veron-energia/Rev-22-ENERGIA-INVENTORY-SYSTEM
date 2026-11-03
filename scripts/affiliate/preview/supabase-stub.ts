// Stand-in for src/lib/supabase, used only by the preview harness. The portal
// shell's email warning (3 Nov 2026) reads the email status and sends the
// verification email through it. ?verified=1: the email is verified (no
// warning); ?send=fail: the delivery service refuses the email;
// ?send=verified: the email was verified meanwhile, in another tab.
// The Rules page (490) reads affiliate_rules_info: invented products at
// production's rates of 3 Nov 2026; ?rules=fail makes the read fail.
const params = new URLSearchParams(window.location.search);
const send = params.get('send');
let verifiedAt: string | null = params.get('verified') === '1' ? '2026-11-01T02:00:00Z' : null;

const RULES = {
  rates: { tier1_own: 15, tier1_third: 4.5, tier2_own: 35, tier2_third: 35 },
  machines_from: '2026-11-03',
  products: {
    own: ['Preview Corset', 'Preview Pillow', 'Preview Bolster', 'Preview Socks', 'Preview Gloves', 'Preview Soap'],
    third_party: ['Preview Water System', 'Preview Air Purifier', 'Preview Probiotic', 'Preview Massage Chair'],
    no_commission: ['Preview Delivery Charge', 'Preview House Call'],
  },
  machines: [{ name: 'Preview Water System (special)', earns: 'third_party' }, { name: 'Preview Own Machine', earns: 'own' }],
};

// The Account page (491): ?route=free|code|staff|verify_first is what the
// login may do; the details flow answers as the server does (any 6 digits
// are right, 000000 is wrong).
const DETAILS = {
  route: params.get('route') ?? 'code', verified: params.get('route') !== 'free' && params.get('route') !== 'verify_first',
  first_name: 'Ada', last_name: 'Preview', phone: '+61255500101', email: 'ada.preview@example.com', login_email: 'ada.preview@example.com',
  request: null as null | Record<string, unknown>,
};
let pending: { changes: Record<string, string>; step: 'current' | 'new' } | null = null;
const answer = (data: unknown) => ({ data, error: null });
function detailsStep(body: Record<string, unknown>) {
  if (body.action === 'start') {
    const changes = (body.changes ?? {}) as Record<string, string>;
    if (DETAILS.route === 'free') { Object.assign(DETAILS, changes); return answer({ status: 'applied', changes }); }
    pending = { changes, step: 'current' };
    return answer({ request_id: '00000000-0000-4000-8000-0000000000bb', next: 'code', purpose: 'current', code_to: DETAILS.login_email });
  }
  if (body.action === 'verify') {
    if (body.code === '000000') return { data: null, error: { context: new Response(JSON.stringify({ error: 'wrong_code', tries_left: 4 }), { status: 400 }) } };
    if (pending?.step === 'current' && pending.changes.email) { pending.step = 'new'; return answer({ request_id: '00000000-0000-4000-8000-0000000000bb', next: 'code', purpose: 'new', code_to: pending.changes.email }); }
    if (DETAILS.route === 'staff') { DETAILS.request = { id: '00000000-0000-4000-8000-0000000000bb', route: 'staff', status: 'pending_staff' }; return answer({ next: 'pending_staff' }); }
    Object.assign(DETAILS, pending?.changes ?? {}); pending = null; return answer({ status: 'applied' });
  }
  if (body.action === 'resend') return answer({ request_id: '00000000-0000-4000-8000-0000000000bb', next: 'code', purpose: pending?.step ?? 'current', code_to: DETAILS.login_email });
  pending = null; DETAILS.request = null; return answer({ status: 'cancelled' });
}

export const supabase = {
  auth: { refreshSession: async () => ({ data: {} }) },
  rpc: async (fn: string) => {
    if (fn === 'affiliate_portal_me') return answer({ name: 'Ada Preview', email: DETAILS.login_email, referral_code: 'PREVIEW1', status: 'active', joined_at: '2026-10-01T02:00:00Z' });
    if (fn === 'affiliate_portal_details') return answer({ ...DETAILS });
    if (fn !== 'affiliate_rules_info') return { data: null, error: { message: `preview stub: ${fn} is not stubbed` } };
    if (params.get('rules') === 'fail') return { data: null, error: { message: 'Failed to fetch' } };
    return { data: RULES, error: null };
  },
  from: (table: string) => {
    const q = {
      select: () => q,
      eq: () => q,
      maybeSingle: async () => (table === 'affiliate_accounts'
        ? { data: { email_verified_at: verifiedAt }, error: null }
        : { data: null, error: { message: `preview stub: ${table} is not stubbed` } }),
    };
    return q;
  },
  functions: {
    // A moment's wait, so "Sending…" can be seen.
    invoke: async (fn: string, opts?: { body?: Record<string, unknown> }) => {
      await new Promise(r => setTimeout(r, 800));
      if (fn === 'affiliate-details') return detailsStep(opts?.body ?? {});
      if (fn !== 'auth-resend-verification') return { data: null, error: { message: `preview stub: ${fn} is not stubbed` } };
      if (send === 'verified') verifiedAt = '2026-11-03T02:00:00Z';
      return { data: { ok: true, status: send === 'fail' ? 'not_sent' : 'submitted', request_id: 'preview' }, error: null };
    },
  },
};
