import React, { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';
import PhoneInput from '../components/PhoneInput';

// Public /r/:referralCode — creates a CUSTOMER under the affiliate. It does NOT
// create a login or an affiliate. The insert is done by a scoped SECURITY
// DEFINER RPC; the browser never writes to customers directly.
const ReferralSignupPage: React.FC = () => {
  const { referralCode } = useParams();
  const [info, setInfo] = useState<any>(null);
  const [f, setF] = useState({ first: '', last: '', phone: '', email: '' });
  const [phoneValid, setPhoneValid] = useState(false);
  const [hp, setHp] = useState(''); // honeypot
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const on = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: e.target.value });

  useEffect(() => {
    supabase.rpc('public_affiliate_referral_info', { p_code: referralCode })
      .then(({ data }) => setInfo(data ?? { valid: false }));
  }, [referralCode]);

  const submit = async () => {
    setErr(null);
    if (!f.first.trim()) { setErr('Please enter your name.'); return; }
    if (!f.phone || !phoneValid) { setErr('Please enter a valid mobile/phone number.'); return; }
    setBusy(true);
    const { data, error } = await supabase.rpc('affiliate_referral_signup', {
      p_code: referralCode, p_first_name: f.first.trim(), p_last_name: f.last.trim(),
      p_phone: f.phone.trim(), p_email: f.email.trim() || null, p_honeypot: hp || null,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    const res = data as any;
    if (res?.ok === false) { setErr(res.message || 'Registration could not be completed.'); return; }
    setDone(res?.message || 'Registration successful.');
  };

  if (info && !info.valid) return (
    <AffiliateAuthShell title="Invalid referral link">
      <p style={{ fontSize: 14, color: 'var(--text-secondary)' }}>This referral link is not valid. Please check the link or contact Energia.</p>
    </AffiliateAuthShell>
  );

  if (info && info.accepting === false) return (
    <AffiliateAuthShell title="Not accepting registrations">
      <p style={{ fontSize: 14, color: 'var(--text-secondary)' }}>This referral link is not accepting new registrations right now. Please contact Energia.</p>
    </AffiliateAuthShell>
  );

  if (done) return (
    <AffiliateAuthShell title="Registration Successful">
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        Thank you for registering with Energia. Your referral has been recorded successfully.
      </p>
    </AffiliateAuthShell>
  );

  return (
    <AffiliateAuthShell title="Welcome to Energia"
      subtitle={info?.affiliate_name ? `You've been invited by ${info.affiliate_name}` : 'Register with Energia'}
      footer={<Link to="/affiliate/join" style={{ color: 'var(--primary)', fontWeight: 600 }}>Want to become an affiliate instead?</Link>}>
      <div className="affiliate-form-grid-2">
        <Field label="First Name"><input className="input" value={f.first} onChange={on('first')} /></Field>
        <Field label="Last Name"><input className="input" value={f.last} onChange={on('last')} /></Field>
      </div>
      <Field label="Phone Number"><PhoneInput value={f.phone} onChange={(e164, valid) => { setF(s => ({ ...s, phone: e164 })); setPhoneValid(valid); }} /></Field>
      <Field label="Email"><input className="input" type="email" value={f.email} onChange={on('email')} /></Field>
      {/* Honeypot: hidden from real users */}
      <input tabIndex={-1} autoComplete="off" value={hp} onChange={e => setHp(e.target.value)}
        style={{ position: 'absolute', left: '-9999px', width: 1, height: 1 }} aria-hidden="true" />
      {err && <p style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Registering…' : 'Register'}</button>
    </AffiliateAuthShell>
  );
};
export default ReferralSignupPage;
