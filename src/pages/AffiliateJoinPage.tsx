import PhoneInput, { isPhoneValid } from '../components/PhoneInput';
import { PasswordInput } from '../components/PasswordInput';
import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';
import { requestAffiliateSignup, resendVerification, AUTH_EMAIL_COPY } from '../lib/authEmail';

// Global Affiliate Activation signup.
//
// 437 (the Owner's decisions of 20 Oct 2026): Create Account takes the person
// straight in. The `auth-signup-request` Edge Function makes the Supabase Auth
// login already confirmed, this page signs in with the password typed, and
// /affiliate/verify finishes the sign-up (complete_affiliate_onboarding, with
// the details the server stored) and lands on the affiliate dashboard. No
// email is waited for: the email is verified later, from the Account page.
//
// An address that already has a login is told so, with Sign in and Reset
// password (decision 4; the Owner accepted that this shows the address is
// registered). Before the 437 sign-up function is deployed the server still
// answers "submitted" and sends a verification email; this page then shows the
// old "check your email" screen.
//
// One browser holds one login. When this browser is already signed in (a
// member of staff, say), the page says that Create Account signs that login
// out here, and signs it out on this device only before signing in as the new
// affiliate.
const ONBOARDING_KEY = 'energia_aff_onboarding';

const AffiliateJoinPage: React.FC = () => {
  const nav = useNavigate();
  const { session } = useAuth();
  const signedInAs = session?.user?.email ?? null;
  const [f, setF] = useState({ first: '', last: '', phone: '', email: '', password: '', confirm: '' });
  const [agree, setAgree] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  // 437: the address already has a login (decision 4).
  const [inUse, setInUse] = useState<string | null>(null);
  // 437: the login was made but signing in with it failed (a connection blip).
  const [signInFailed, setSignInFailed] = useState(false);
  const [resendBusy, setResendBusy] = useState(false);
  const [resendMsg, setResendMsg] = useState<string | null>(null);
  const on = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement>) => setF({ ...f, [k]: e.target.value });

  const submit = async () => {
    if (busy) return;                                    // no double submission
    setErr(null); setNotice(null); setInUse(null); setSignInFailed(false);
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

    if (result.kind === 'email_in_use') {
      setBusy(false);
      setInUse(result.message ?? AUTH_EMAIL_COPY.signupEmailInUse);
      return;
    }
    if (!result.ok) { setBusy(false); setErr(result.message ?? AUTH_EMAIL_COPY.unavailable); return; }

    // This browser's copy of the details, in case the account's own copy is
    // not readable when the sign-up is finished.
    try {
      localStorage.setItem(ONBOARDING_KEY, JSON.stringify({ first: f.first.trim(), last: f.last.trim(), phone: f.phone.trim() }));
    } catch { /* ignore */ }

    if (result.kind === 'created') {
      // Straight in: sign in with the password just typed, then finish the
      // sign-up and land on the dashboard. A login already signed in here is
      // signed out first, on this device only, so the app forgets it before
      // the new one arrives.
      if (session) { try { await supabase.auth.signOut({ scope: 'local' }); } catch { /* the sign-in replaces it anyway */ } }
      const { error } = await supabase.auth.signInWithPassword({ email: f.email.trim(), password: f.password });
      setBusy(false);
      if (error) { setSignInFailed(true); return; }
      nav('/affiliate/verify', { replace: true });
      return;
    }

    // An older sign-up function answered: it sent a verification email.
    // `not_sent` only means the email could not be handed over, which the
    // Resend button on the next screen exists to fix.
    setBusy(false);
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

  // 437: the account is made; only signing in failed. Sign in from the login
  // page, which finishes the sign-up the same way.
  if (signInFailed) return (
    <AffiliateAuthShell title="Your account is ready" subtitle="Sign in to continue">
      <p role="alert" style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        Your affiliate account for <b>{f.email}</b> was created, but we could not sign you in just now. Sign in with the
        password you chose to go to your dashboard.
      </p>
      <Link className="btn btn-primary" style={{ width: '100%', textAlign: 'center', marginTop: 16 }} to="/affiliate/login">Sign in</Link>
    </AffiliateAuthShell>
  );

  // Only for an older sign-up function, which still emailed a verification
  // link: the screen states both possibilities, as before.
  if (done) return (
    <AffiliateAuthShell title="Next step" subtitle="Check your email, or sign in">
      {notice && <p role="alert" style={{ color: 'var(--warning, #b45309)', fontSize: 13, marginBottom: 12 }}>{notice}</p>}
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        If <b>{f.email}</b> is new to Energia, we have sent it a verification link — open it and you
        will be brought back to finish setting up your affiliate account.
      </p>
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6, marginTop: 10 }}>
        If you already have an affiliate login with that address, <b>no new email is sent</b>. Sign in
        below, or reset your password if you have forgotten it.
      </p>
      {resendMsg && <p role="status" style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 10 }}>{resendMsg}</p>}
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 16 }}>
        <Link className="btn btn-primary" style={{ width: '100%', textAlign: 'center' }} to="/affiliate/login">
          Sign in
        </Link>
        <Link className="btn btn-secondary" style={{ width: '100%', textAlign: 'center' }} to="/affiliate/forgot-password">
          Reset my password
        </Link>
        <button className="btn btn-secondary" style={{ width: '100%' }} disabled={resendBusy} onClick={resend}>
          {resendBusy ? 'Sending…' : 'Resend verification email'}
        </button>
      </div>
      <p style={{ fontSize: 12, color: 'var(--text-muted)', lineHeight: 1.6, marginTop: 14 }}>
        {AUTH_EMAIL_COPY.signupExistingHint} Still stuck? Contact Energia and we will help.
      </p>
    </AffiliateAuthShell>
  );

  return (
    <AffiliateAuthShell title="Become an Energia Affiliate" subtitle="Create your affiliate account"
      footer={<>Already have an account? <Link to="/affiliate/login" style={{ color: 'var(--primary)', fontWeight: 600 }}>Sign in</Link></>}>
      <p style={{ fontSize: 13, color: 'var(--text-secondary)', lineHeight: 1.6, marginBottom: 14 }}>
        Already an Energia customer? Use this form with the phone number we have for you: your affiliate account is
        joined to your customer record, so your purchases, credit, vouchers and therapy stay exactly as they are. You can
        start using your affiliate account straight away.
      </p>
      <div className="portal-form-grid-2">
        <Field label="First Name"><input className="input" value={f.first} onChange={on('first')} /></Field>
        <Field label="Last Name"><input className="input" value={f.last} onChange={on('last')} /></Field>
      </div>
      <Field label="Phone Number"><PhoneInput value={f.phone} onChange={phone => setF(s => ({ ...s, phone }))} /></Field>
      <Field label="Email"><input className="input" type="email" value={f.email} onChange={e => { on('email')(e); setInUse(null); }} /></Field>
      <Field label="Password"><PasswordInput className="input" value={f.password} onChange={on('password')} placeholder="At least 8 characters" /></Field>
      <Field label="Confirm Password"><PasswordInput className="input" value={f.confirm} onChange={on('confirm')} /></Field>
      <label style={{ display: 'flex', gap: 8, alignItems: 'flex-start', fontSize: 12.5, color: 'var(--text-secondary)', margin: '4px 0 14px' }}>
        <input type="checkbox" checked={agree} onChange={e => setAgree(e.target.checked)} style={{ marginTop: 2 }} />
        <span>I agree to the Energia Affiliate terms and privacy statement.</span>
      </label>
      {err && <p role="alert" style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      {inUse && (
        <div role="alert" data-state="email-in-use" style={{ marginBottom: 12 }}>
          <p style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 10 }}>{inUse}</p>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <Link className="btn btn-primary btn-sm" to="/affiliate/login">Sign in</Link>
            <Link className="btn btn-secondary btn-sm" to="/affiliate/forgot-password">Reset password</Link>
          </div>
        </div>
      )}
      {signedInAs && (
        <p data-note="signed-in-elsewhere" style={{ fontSize: 12.5, color: 'var(--warning, #b45309)', lineHeight: 1.5, marginBottom: 12 }}>
          This browser is signed in as <b>{signedInAs}</b>. Creating an affiliate account here signs that login out.
        </p>
      )}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Creating…' : 'Create Account'}</button>
    </AffiliateAuthShell>
  );
};
export default AffiliateJoinPage;
