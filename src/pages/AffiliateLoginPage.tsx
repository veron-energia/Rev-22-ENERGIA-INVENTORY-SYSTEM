import React, { useState } from 'react';
import { PasswordInput } from '../components/PasswordInput';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';
import { resendVerification, AUTH_EMAIL_COPY } from '../lib/authEmail';

const AffiliateLoginPage: React.FC = () => {
  const nav = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  // 437: a sign-up not switched on yet can have its sign-up link sent again.
  const [notConfirmed, setNotConfirmed] = useState(false);
  const [resendBusy, setResendBusy] = useState(false);
  const [resendMsg, setResendMsg] = useState<string | null>(null);

  const submit = async () => {
    setBusy(true); setErr(null); setNotConfirmed(false); setResendMsg(null);
    const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) {
      // 437: a sign-up from before 20 Oct 2026 that never opened its email
      // link cannot sign in until it is switched on (the one-off repair), or
      // until its sign-up link is opened: that link still finishes the
      // sign-up (/affiliate/verify), and it can be sent again from here.
      const code = (error as { code?: string }).code;
      const unconfirmed = code === 'email_not_confirmed' || /email not confirmed/i.test(error.message);
      setNotConfirmed(unconfirmed);
      setErr(unconfirmed
        ? 'Your sign-up is not switched on yet. Open the link we emailed you, or send it again below. Still stuck? Contact Energia.'
        : error.message);
      setBusy(false); return;
    }
    // Route by actor: affiliate → portal; staff → staff app.
    const uid = data.user?.id;
    const { data: acct } = await supabase.from('affiliate_accounts').select('id').eq('auth_user_id', uid).maybeSingle();
    if (acct) { nav('/affiliate/dashboard', { replace: true }); return; }
    const { data: prof } = await supabase.from('profiles').select('id').eq('id', uid).maybeSingle();
    if (prof) { nav('/', { replace: true }); return; }
    // Signed in but no affiliate account yet (437: someone stuck after signing
    // up): the verify page finishes the sign-up with the details they gave,
    // like a new sign-up, and goes on to the dashboard.
    nav('/affiliate/verify', { replace: true });
  };

  const resend = async () => {
    if (resendBusy) return;
    setResendBusy(true); setResendMsg(null);
    const result = await resendVerification(email.trim());
    setResendBusy(false);
    setResendMsg(result.ok
      ? (result.kind === 'not_sent' ? (result.message ?? AUTH_EMAIL_COPY.notSent) : AUTH_EMAIL_COPY.resendSubmitted)
      : (result.message ?? AUTH_EMAIL_COPY.unavailable));
  };

  return (
    <AffiliateAuthShell title="Affiliate Login" subtitle="Sign in to your Energia Affiliate portal"
      footer={<>New affiliate? <Link to="/affiliate/join" style={{ color: 'var(--primary)', fontWeight: 600 }}>Create an account</Link></>}>
      <Field label="Email"><input className="input" type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="you@example.com" /></Field>
      <Field label="Password"><PasswordInput className="input" value={password} onChange={e => setPassword(e.target.value)} onKeyDown={e => e.key === 'Enter' && submit()} /></Field>
      {err && <p role="alert" style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      {notConfirmed && (
        <div data-state="not-confirmed" style={{ marginBottom: 12 }}>
          <button type="button" className="btn btn-secondary" style={{ width: '100%' }} disabled={resendBusy || !email.trim()} onClick={() => void resend()}>
            {resendBusy ? 'Sending…' : 'Send the sign-up link again'}
          </button>
          {resendMsg && <p role="status" style={{ fontSize: 13, color: 'var(--text-secondary)', marginTop: 8 }}>{resendMsg}</p>}
        </div>
      )}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Signing in…' : 'Sign In'}</button>
      <div style={{ textAlign: 'center', marginTop: 12 }}>
        <Link to="/affiliate/forgot-password" style={{ fontSize: 13, color: 'var(--text-muted)' }}>Forgot password?</Link>
      </div>
    </AffiliateAuthShell>
  );
};
export default AffiliateLoginPage;
