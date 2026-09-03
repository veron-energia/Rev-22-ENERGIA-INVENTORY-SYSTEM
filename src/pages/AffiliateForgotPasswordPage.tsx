import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { publicAppUrl } from '../components/QRCodeCard';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';

const AffiliateForgotPasswordPage: React.FC = () => {
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const submit = async () => {
    setBusy(true); setErr(null);
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${publicAppUrl()}/affiliate/reset-password`,
    });
    setBusy(false);
    if (error) { setErr(error.message); return; }
    setSent(true);
  };

  if (sent) return (
    <AffiliateAuthShell title="Check your email" subtitle="Password reset link sent">
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        If an account exists for <b>{email}</b>, a reset link is on its way. Follow it to choose a new password.
      </p>
      <div style={{ textAlign: 'center', marginTop: 16 }}><Link to="/affiliate/login" style={{ color: 'var(--primary)', fontWeight: 600 }}>Back to login</Link></div>
    </AffiliateAuthShell>
  );

  return (
    <AffiliateAuthShell title="Forgot Password" subtitle="We'll email you a reset link"
      footer={<Link to="/affiliate/login" style={{ color: 'var(--primary)', fontWeight: 600 }}>Back to login</Link>}>
      <Field label="Email"><input className="input" type="email" value={email} onChange={e => setEmail(e.target.value)} onKeyDown={e => e.key === 'Enter' && submit()} /></Field>
      {err && <p style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Sending…' : 'Send Reset Link'}</button>
    </AffiliateAuthShell>
  );
};
export default AffiliateForgotPasswordPage;
