import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { publicAppUrl } from '../components/QRCodeCard';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';

// Global Affiliate Activation signup. Creates a Supabase Auth user with email
// verification. The affiliate identity is NOT created until the email is
// verified and complete_affiliate_onboarding() runs (see AffiliateVerifyPage).
const AffiliateJoinPage: React.FC = () => {
  const [f, setF] = useState({ first: '', last: '', phone: '', email: '', password: '', confirm: '' });
  const [agree, setAgree] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const on = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: e.target.value });

  const submit = async () => {
    setErr(null);
    if (!f.first.trim() || !f.phone.trim() || !f.email.trim()) { setErr('Please fill in your name, phone and email.'); return; }
    if (f.password.length < 8) { setErr('Password must be at least 8 characters.'); return; }
    if (f.password !== f.confirm) { setErr('Passwords do not match.'); return; }
    if (!agree) { setErr('Please agree to the Affiliate terms to continue.'); return; }
    setBusy(true);
    const { error } = await supabase.auth.signUp({
      email: f.email.trim(), password: f.password,
      options: {
        emailRedirectTo: `${publicAppUrl()}/affiliate/verify`,
        data: { first_name: f.first.trim(), last_name: f.last.trim(), phone: f.phone.trim(), role_hint: 'affiliate' },
      },
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    // Store the entered details so onboarding can complete after verification.
    try {
      localStorage.setItem('energia_aff_onboarding', JSON.stringify({ first: f.first.trim(), last: f.last.trim(), phone: f.phone.trim() }));
    } catch { /* ignore */ }
    setDone(true);
  };

  if (done) return (
    <AffiliateAuthShell title="Check your email" subtitle="We've sent you a verification link">
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        Please open the email we sent to <b>{f.email}</b> and click the verification link.
        Once verified you'll be brought back to finish setting up your affiliate account.
      </p>
      <div style={{ textAlign: 'center', marginTop: 16 }}>
        <Link to="/affiliate/login" style={{ color: 'var(--primary)', fontWeight: 600 }}>Back to login</Link>
      </div>
    </AffiliateAuthShell>
  );

  return (
    <AffiliateAuthShell title="Become an Energia Affiliate" subtitle="Create your affiliate account"
      footer={<>Already have an account? <Link to="/affiliate/login" style={{ color: 'var(--primary)', fontWeight: 600 }}>Sign in</Link></>}>
      <div className="affiliate-form-grid-2">
        <Field label="First Name"><input className="input" value={f.first} onChange={on('first')} /></Field>
        <Field label="Last Name"><input className="input" value={f.last} onChange={on('last')} /></Field>
      </div>
      <Field label="Phone Number"><input className="input" value={f.phone} onChange={on('phone')} placeholder="+65…" /></Field>
      <Field label="Email"><input className="input" type="email" value={f.email} onChange={on('email')} /></Field>
      <Field label="Password"><input className="input" type="password" value={f.password} onChange={on('password')} placeholder="At least 8 characters" /></Field>
      <Field label="Confirm Password"><input className="input" type="password" value={f.confirm} onChange={on('confirm')} /></Field>
      <label style={{ display: 'flex', gap: 8, alignItems: 'flex-start', fontSize: 12.5, color: 'var(--text-secondary)', margin: '4px 0 14px' }}>
        <input type="checkbox" checked={agree} onChange={e => setAgree(e.target.checked)} style={{ marginTop: 2 }} />
        <span>I agree to the Energia Affiliate terms and privacy statement.</span>
      </label>
      {err && <p style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Creating…' : 'Create Account'}</button>
    </AffiliateAuthShell>
  );
};
export default AffiliateJoinPage;
