import PhoneInput, { isPhoneValid } from '../components/PhoneInput';
import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';
import { requestAffiliateSignup, resendVerification, AUTH_EMAIL_COPY } from '../lib/authEmail';

// Global Affiliate Activation signup.
//
// The account is created by the `auth-signup-request` Edge Function, which calls
// Supabase Auth server-side and has the verification email delivered through
// Pabbly. Supabase still owns the user, the password hash and the verification
// token; only the delivery route changed.
//
// The response is deliberately the same whether the address is new, already
// signed up but unverified, or already verified — so this screen says "check
// your email" in every case and never reveals which one happened. The affiliate
// identity is still not created until the email is verified and
// complete_affiliate_onboarding() runs (see AffiliateVerifyPage).
const AffiliateJoinPage: React.FC = () => {
  const [f, setF] = useState({ first: '', last: '', phone: '', email: '', password: '', confirm: '' });
  const [agree, setAgree] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const [resendBusy, setResendBusy] = useState(false);
  const [resendMsg, setResendMsg] = useState<string | null>(null);
  const on = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: e.target.value });

  const submit = async () => {
    if (busy) return;                                    // no double submission
    setErr(null); setNotice(null);
    if (!f.first.trim() || !f.phone.trim() || !f.email.trim()) { setErr('Please fill in your name, phone and email.'); return; }
    if (!isPhoneValid(f.phone)) { setErr('Enter a valid international phone number.'); return; }
    if (f.password.length < 8) { setErr('Password must be at least 8 characters.'); return; }
    if (f.password !== f.confirm) { setErr('Passwords do not match.'); return; }
    if (!agree) { setErr('Please agree to the Affiliate terms to continue.'); return; }

    setBusy(true);
    const result = await requestAffiliateSignup({
      firstName: f.first.trim(), lastName: f.last.trim(), phone: f.phone.trim(),
      email: f.email.trim(), password: f.password, termsAccepted: agree,
    });
    setBusy(false);

    if (!result.ok) { setErr(result.message ?? AUTH_EMAIL_COPY.unavailable); return; }

    // Keep the entered details so onboarding can complete after verification.
    try {
      localStorage.setItem('energia_aff_onboarding', JSON.stringify({ first: f.first.trim(), last: f.last.trim(), phone: f.phone.trim() }));
    } catch { /* ignore */ }

    // The account exists either way; `not_sent` only means the email could not be
    // handed over, which the Resend button on the next screen exists to fix.
    setNotice(result.kind === 'not_sent' ? result.message : null);
    setDone(true);
  };

  const resend = async () => {
    if (resendBusy) return;
    setResendBusy(true); setResendMsg(null);
    const result = await resendVerification(f.email.trim());
    setResendBusy(false);
    setResendMsg(result.ok
      ? (result.kind === 'not_sent' ? result.message : AUTH_EMAIL_COPY.resendSubmitted)
      : (result.message ?? AUTH_EMAIL_COPY.unavailable));
  };

  if (done) return (
    <AffiliateAuthShell title="Check your email" subtitle="We've sent you a verification link">
      {notice && <p role="alert" style={{ color: 'var(--warning, #b45309)', fontSize: 13, marginBottom: 12 }}>{notice}</p>}
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        Please open the email we sent to <b>{f.email}</b> and click the verification link.
        Once verified you'll be brought back to finish setting up your affiliate account.
      </p>
      <p style={{ fontSize: 13, color: 'var(--text-muted)', lineHeight: 1.6, marginTop: 10 }}>
        {AUTH_EMAIL_COPY.signupSubmitted}
      </p>
      {resendMsg && <p role="status" style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 10 }}>{resendMsg}</p>}
      <button className="btn btn-secondary" style={{ width: '100%', marginTop: 14 }} disabled={resendBusy} onClick={resend}>
        {resendBusy ? 'Sending…' : 'Resend verification email'}
      </button>
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
      <Field label="Phone Number"><PhoneInput value={f.phone} onChange={phone => setF(s => ({ ...s, phone }))} /></Field>
      <Field label="Email"><input className="input" type="email" value={f.email} onChange={on('email')} /></Field>
      <Field label="Password"><input className="input" type="password" value={f.password} onChange={on('password')} placeholder="At least 8 characters" /></Field>
      <Field label="Confirm Password"><input className="input" type="password" value={f.confirm} onChange={on('confirm')} /></Field>
      <label style={{ display: 'flex', gap: 8, alignItems: 'flex-start', fontSize: 12.5, color: 'var(--text-secondary)', margin: '4px 0 14px' }}>
        <input type="checkbox" checked={agree} onChange={e => setAgree(e.target.checked)} style={{ marginTop: 2 }} />
        <span>I agree to the Energia Affiliate terms and privacy statement.</span>
      </label>
      {err && <p role="alert" style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Creating…' : 'Create Account'}</button>
    </AffiliateAuthShell>
  );
};
export default AffiliateJoinPage;
