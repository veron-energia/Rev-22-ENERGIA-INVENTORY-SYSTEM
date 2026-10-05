// The two signed-out calls the referral page makes, answered as production
// answers them after 392. ?reply=existing answers as for somebody already
// registered. Every name is invented.
const reply = new URLSearchParams(window.location.search).get('reply');

export const rpcCalls: { fn: string; args: unknown }[] = [];

export const supabase = {
  rpc: async (fn: string, args: unknown) => {
    rpcCalls.push({ fn, args });
    if (fn === 'public_affiliate_referral_info')
      return { data: { valid: true, affiliate_name: 'Jane', accepting: true }, error: null };
    if (fn === 'affiliate_referral_signup')
      return reply === 'existing'
        ? { data: { ok: true, outcome: 'already_registered',
                    message: 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.' }, error: null }
        : { data: { ok: true, outcome: 'registered', message: 'Registration successful.',
                    affiliate_label: 'Jane Tan' }, error: null };
    return { data: null, error: { message: `preview stub: ${fn} is not stubbed` } };
  },
};
