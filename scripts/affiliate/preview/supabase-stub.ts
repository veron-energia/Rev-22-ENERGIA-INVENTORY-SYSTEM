// Stand-in for src/lib/supabase, used only by the preview harness. The portal
// shell's email warning (3 Nov 2026) reads the email status and sends the
// verification email through it. ?verified=1: the email is verified (no
// warning); ?send=fail: the delivery service refuses the email;
// ?send=verified: the email was verified meanwhile, in another tab.
const params = new URLSearchParams(window.location.search);
const send = params.get('send');
let verifiedAt: string | null = params.get('verified') === '1' ? '2026-11-01T02:00:00Z' : null;

export const supabase = {
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
    invoke: async (fn: string) => {
      await new Promise(r => setTimeout(r, 800));
      if (fn !== 'auth-resend-verification') return { data: null, error: { message: `preview stub: ${fn} is not stubbed` } };
      if (send === 'verified') verifiedAt = '2026-11-03T02:00:00Z';
      return { data: { ok: true, status: send === 'fail' ? 'not_sent' : 'submitted', request_id: 'preview' }, error: null };
    },
  },
};
