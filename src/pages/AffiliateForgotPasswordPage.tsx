import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';
import { requestPasswordRecovery, AUTH_EMAIL_COPY } from '../lib/authEmail';

// Recovery goes through the `auth-request-recovery` Edge Function. The browser
// names the flow ("affiliate"); the server maps that to the allowlisted
// /affiliate/reset-password callback. No URL is ever sent from here.
const AffiliateForgotPasswordPage: React.FC = () => {
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  const submit = async () => {
    if (busy) return;
    setBusy(true); setErr(null); setNotice(null);
    const result = await requestPasswordRecovery(email.trim(), 'affiliate');
    setBusy(false);
    if (!result.ok) { setErr(result.message ?? AUTH_EMAIL_COPY.unavailable); return; }
    setNotice(result.kind === 'not_sent' ? result.message : null);
    setSent(true);
  };

  if (sent) return (
    <AffiliateAuthShell title="Check your email" subtitle="Password reset link sent">
      {notice && <p role="alert" style={{ color: 'var(--warning, #b45309)', fontSize: 13, marginBottom: 12 }}>{notice}</p>}
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        {AUTH_EMAIL_COPY.recoverySubmitted} Please check your inbox and your spam folder.
      </p>
      <div style={{ textAlign: 'center', marginTop: 16 }}><Link to="/affiliate/login" style={{ color: 'var(--primary)', fontWeight: 600 }}>Back to login</Link></div>
    </AffiliateAuthShell>
  );

  return (
    <AffiliateAuthShell title="Forgot Password" subtitle="We'll email you a reset link"
      footer={<Link to="/affiliate/login" style={{ color: 'var(--primary)', fontWeight: 600 }}>Back to login</Link>}>
      <Field label="Email"><input className="input" type="email" value={email} onChange={e => setEmail(e.target.value)} onKeyDown={e => e.key === 'Enter' && submit()} /></Field>
      {err && <p role="alert" style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Sending…' : 'Send Reset Link'}</button>
    </AffiliateAuthShell>
  );
};
export default AffiliateForgotPasswordPage;
