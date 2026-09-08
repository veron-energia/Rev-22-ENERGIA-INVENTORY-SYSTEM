import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { Leaf } from 'lucide-react';
import { requestPasswordRecovery, AUTH_EMAIL_COPY } from '../lib/authEmail';

// Staff password recovery. Staff accounts are created by an Owner or Manager, so
// there is no signup here — only a way back in for somebody who has an account
// and has forgotten the password.
//
// The response is identical whether or not an account exists, which is the point:
// this page must not become a way to find out who has a staff login.
const AuthShell: React.FC<{ title: string; subtitle: string; children: React.ReactNode }> = ({ title, subtitle, children }) => (
  <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20, background: 'var(--bg)' }}>
    <div style={{ width: '100%', maxWidth: 400 }}>
      <div style={{ textAlign: 'center', marginBottom: 28 }}>
        <div style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 52, height: 52, borderRadius: 14, background: 'var(--primary)', marginBottom: 14 }}>
          <Leaf size={26} color="#fff" />
        </div>
        <h1 style={{ fontSize: 26, color: 'var(--primary)' }}>{title}</h1>
        <p style={{ color: 'var(--text-muted)', fontSize: 13.5, marginTop: 2 }}>{subtitle}</p>
      </div>
      <div className="card" style={{ padding: 28 }}>{children}</div>
    </div>
  </div>
);

const ForgotPasswordPage: React.FC = () => {
  const [email, setEmail] = useState('');
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setBusy(true); setErr(null); setNotice(null);
    const result = await requestPasswordRecovery(email.trim(), 'staff');
    setBusy(false);
    if (!result.ok) { setErr(result.message ?? AUTH_EMAIL_COPY.unavailable); return; }
    setNotice(result.kind === 'not_sent' ? result.message : null);
    setSent(true);
  };

  if (sent) return (
    <AuthShell title="Check your email" subtitle="Password reset instructions sent">
      {notice && <div className="alert alert-danger" style={{ marginBottom: 14 }}><span>⚠</span><div>{notice}</div></div>}
      <p style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
        {AUTH_EMAIL_COPY.recoverySubmitted} Please check your inbox and your spam folder.
      </p>
      <div style={{ textAlign: 'center', marginTop: 18 }}>
        <Link to="/login" style={{ color: 'var(--primary)', fontWeight: 600, fontSize: 14 }}>Back to sign in</Link>
      </div>
    </AuthShell>
  );

  return (
    <AuthShell title="Forgot Password" subtitle="We'll email you a reset link">
      <form onSubmit={submit} className="form-grid">
        <div className="form-group">
          <label>Email</label>
          <input type="email" value={email} onChange={e => setEmail(e.target.value)}
            placeholder="you@energia.sg" autoComplete="email" required autoFocus />
        </div>
        {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
        <button type="submit" className="btn btn-primary" disabled={busy} style={{ width: '100%', marginTop: 4 }}>
          {busy ? 'Sending…' : 'Send reset link'}
        </button>
      </form>
      <div style={{ textAlign: 'center', marginTop: 16 }}>
        <Link to="/login" style={{ color: 'var(--text-muted)', fontSize: 13 }}>Back to sign in</Link>
      </div>
    </AuthShell>
  );
};

export default ForgotPasswordPage;
