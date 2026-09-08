import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';
import { changePassword, AUTH_EMAIL_COPY } from '../lib/authEmail';

// Reached via the reset link. Supabase establishes the recovery session from the
// link exactly as before — that part is unchanged and works on any device,
// because an admin-generated link carries no browser-held verifier.
//
// The password change itself goes through the `auth-change-password` Edge
// Function, which makes the same user-scoped call to Supabase with this
// session's own token and then sends the "password changed" notification. Doing
// it there rather than here is what makes the notification trustworthy.
const AffiliateResetPasswordPage: React.FC = () => {
  const nav = useNavigate();
  const [pw, setPw] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const submit = async () => {
    if (busy) return;
    setErr(null);
    if (pw.length < 8) { setErr('Password must be at least 8 characters.'); return; }
    if (pw !== confirm) { setErr('Passwords do not match.'); return; }
    setBusy(true);
    const result = await changePassword(pw);
    setBusy(false);
    if (!result.ok) { setErr(result.message ?? AUTH_EMAIL_COPY.unavailable); return; }
    // The password is changed whether or not the notification email went out.
    nav('/affiliate/dashboard', { replace: true });
  };

  return (
    <AffiliateAuthShell title="Set a New Password" subtitle="Choose a new password for your account">
      <Field label="New Password"><input className="input" type="password" value={pw} onChange={e => setPw(e.target.value)} /></Field>
      <Field label="Confirm Password"><input className="input" type="password" value={confirm} onChange={e => setConfirm(e.target.value)} onKeyDown={e => e.key === 'Enter' && submit()} /></Field>
      {err && <p role="alert" style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Saving…' : 'Save Password'}</button>
    </AffiliateAuthShell>
  );
};
export default AffiliateResetPasswordPage;
