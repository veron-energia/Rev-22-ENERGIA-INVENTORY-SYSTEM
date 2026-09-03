import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';

const AffiliateLoginPage: React.FC = () => {
  const nav = useNavigate();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const submit = async () => {
    setBusy(true); setErr(null);
    const { data, error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    if (error) { setErr(error.message); setBusy(false); return; }
    // Route by actor: affiliate → portal; staff → staff app.
    const uid = data.user?.id;
    const { data: acct } = await supabase.from('affiliate_accounts').select('id').eq('auth_user_id', uid).maybeSingle();
    if (acct) { nav('/affiliate/dashboard', { replace: true }); return; }
    const { data: prof } = await supabase.from('profiles').select('id').eq('id', uid).maybeSingle();
    if (prof) { nav('/', { replace: true }); return; }
    // Authenticated but not yet onboarded.
    nav('/affiliate/verify', { replace: true });
  };

  return (
    <AffiliateAuthShell title="Affiliate Login" subtitle="Sign in to your Energia Affiliate portal"
      footer={<>New affiliate? <Link to="/affiliate/join" style={{ color: 'var(--primary)', fontWeight: 600 }}>Create an account</Link></>}>
      <Field label="Email"><input className="input" type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="you@example.com" /></Field>
      <Field label="Password"><input className="input" type="password" value={password} onChange={e => setPassword(e.target.value)} onKeyDown={e => e.key === 'Enter' && submit()} /></Field>
      {err && <p style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Signing in…' : 'Sign In'}</button>
      <div style={{ textAlign: 'center', marginTop: 12 }}>
        <Link to="/affiliate/forgot-password" style={{ fontSize: 13, color: 'var(--text-muted)' }}>Forgot password?</Link>
      </div>
    </AffiliateAuthShell>
  );
};
export default AffiliateLoginPage;
