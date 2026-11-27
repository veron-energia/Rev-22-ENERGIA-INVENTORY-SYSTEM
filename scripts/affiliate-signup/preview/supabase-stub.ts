// The signed-out calls the referral page makes, answered as production
// answers them after 392. ?reply=existing answers as for somebody already
// registered. Every name is invented.
//
// 484 (push #2): the page signs up through affiliate_referral_signup_with_notice,
// answered here as affiliate_referral_signup is. ?notice=missing answers it
// with PGRST202, as a database without 484 does, so the page falls back to
// affiliate_referral_signup with the six keys. ?name= is the inviter's first
// name ('Jane' when absent; ?name=none sends none): with none, or a blank
// one, the notice says "the person who invited you".
const params = new URLSearchParams(window.location.search);
const reply = params.get('reply');
const noticeMissing = params.get('notice') === 'missing';
const name = params.get('name');
const affiliateName = name === null ? 'Jane' : name === 'none' ? null : name;
// 549: ?booking= answers referral_booking_lookup for somebody already registered:
// booked (phone and email match), needs_email (asks for the email; nia@example.invalid
// then shows the booking), gcal (booked, filled from Google Calendar: no cal.com uid),
// none; absent: PGRST202, as a database without 549.
const bookingMode = params.get('booking');
const previewBooking = { state: 'booked', start_at: '2026-12-07T02:00:00Z', uid: bookingMode === 'gcal' ? null : 't549preview' };

export const rpcCalls: { fn: string; args: unknown }[] = [];

const signedUp = () => (reply === 'existing'
  ? { data: { ok: true, outcome: 'already_registered',
              message: 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.' }, error: null }
  : { data: { ok: true, outcome: 'registered', message: 'Registration successful.',
              affiliate_label: 'Jane Tan' }, error: null });

export const supabase = {
  rpc: async (fn: string, args: unknown) => {
    rpcCalls.push({ fn, args });
    if (fn === 'public_affiliate_referral_info')
      return { data: { valid: true, affiliate_name: affiliateName, accepting: true }, error: null };
    if (fn === 'affiliate_referral_signup_with_notice' && noticeMissing)
      return { data: null, error: { code: 'PGRST202', details: null, hint: null,
        message: 'Could not find the function public.affiliate_referral_signup_with_notice(p_code, p_email, p_first_name, p_honeypot, p_last_name, p_notice, p_phone) in the schema cache' } };
    if (fn === 'affiliate_referral_signup_with_notice' || fn === 'affiliate_referral_signup') return signedUp();
    if (fn === 'referral_booking_lookup') {
      const email = (args as { p_email?: string | null } | null)?.p_email ?? null;
      if (bookingMode === 'booked' || bookingMode === 'gcal') return { data: previewBooking, error: null };
      if (bookingMode === 'needs_email')
        return { data: email === 'nia@example.invalid' ? previewBooking : { state: 'needs_email' }, error: null };
      if (bookingMode === 'none') return { data: { state: 'none' }, error: null };
      return { data: null, error: { code: 'PGRST202', details: null, hint: null,
        message: 'Could not find the function public.referral_booking_lookup(p_code, p_email, p_phone) in the schema cache' } };
    }
    return { data: null, error: { message: `preview stub: ${fn} is not stubbed` } };
  },
};
