import React, { useState } from 'react';
import { PasswordInput } from '../components/PasswordInput';
import { Link, useNavigate } from 'react-router-dom';
import AffiliateAuthShell, { Field } from '../components/AffiliateAuthShell';
import { supabase } from '../lib/supabase';
import { changePassword, AUTH_EMAIL_COPY } from '../lib/authEmail';
import { useResetSession } from '../lib/resetSession';

// Reached via the reset link. Supabase establishes the recovery session from the
// link exactly as before — that part is unchanged and works on any device,
// because an admin-generated link carries no browser-held verifier.
//
// The password change itself goes through the `auth-change-password` Edge
// Function, which makes the same user-scoped call to Supabase with this
// session's own token and then sends the "password changed" notification. Doing
// it there rather than here is what makes the notification trustworthy.
//
// ADMIN-AUTH-9: this page had no session check at all. With no session it now
// says the link has expired; with a session that did not just come from the
// link it asks for the current password and says whose account it is.
const AffiliateResetPasswordPage: React.FC = () => {
  const nav = useNavigate();
  const { mode, email, needCurrentPassword } = useResetSession();
  const [current, setCurrent] = useState('');
  const [pw, setPw] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const signedIn = mode === 'signed_in';

  const submit = async () => {
    if (busy) return;
    setErr(null);
    if (signedIn && !current) { setErr('Enter your current password.'); return; }
    if (pw.length < 8) { setErr('Password must be at least 8 characters.'); return; }
    if (pw !== confirm) { setErr('Passwords do not match.'); return; }
    setBusy(true);
    const result = await changePassword(pw, signedIn ? current : undefined);
    setBusy(false);
    if (!result.ok) {
      if (result.needsCurrentPassword) needCurrentPassword();
      setErr(result.message ?? AUTH_EMAIL_COPY.unavailable);
      return;
    }
    // The password is changed whether or not the notification email went out.
    nav('/affiliate/dashboard', { replace: true });
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    nav('/affiliate/login', { replace: true });
  };

  // Someone who has forgotten the current password (the link was opened too
  // long ago, or they are signed in) asks for a new link. Signing out first
  // keeps the new link apart from this session.
  const requestNewLink = async () => {
    await supabase.auth.signOut();
    nav('/affiliate/forgot-password', { replace: true });
  };

  if (mode === 'checking') return (
    <AffiliateAuthShell title="Set a New Password">
      <p style={{ fontSize: 14, color: 'var(--text-muted)', textAlign: 'center' }}>Checking your link…</p>
    </AffiliateAuthShell>
  );

  if (mode === 'no_session') return (
    <AffiliateAuthShell title="Set a New Password">
      <p role="alert" style={{ color: 'var(--danger)', fontSize: 14, lineHeight: 1.6, marginBottom: 12 }}>
        This password reset link has expired or has already been used. Request a new one and use the most recent email.
      </p>
      <Link to="/affiliate/forgot-password" className="btn btn-primary" style={{ width: '100%' }}>Request a new link</Link>
    </AffiliateAuthShell>
  );

  return (
    <AffiliateAuthShell
      title={signedIn ? 'Change Your Password' : 'Set a New Password'}
      subtitle={signedIn ? `Change the password for ${email}` : (email ? `For ${email}` : 'Choose a new password for your account')}
      footer={signedIn ? (
        <>
          <p style={{ margin: '0 0 6px' }}>Forgot your current password?{' '}
            <button type="button" onClick={() => void requestNewLink()}
                    style={{ background: 'none', border: 0, padding: 0, color: 'var(--primary)', fontWeight: 600, cursor: 'pointer' }}>
              Request a new link
            </button>
          </p>
          <p style={{ margin: 0 }}>Not you?{' '}
            <button type="button" onClick={() => void signOut()}
                    style={{ background: 'none', border: 0, padding: 0, color: 'var(--primary)', fontWeight: 600, cursor: 'pointer' }}>
              Sign out
            </button>
          </p>
        </>) : undefined}>
      {signedIn && (
        <Field label="Current Password">
          <PasswordInput className="input" value={current} onChange={e => setCurrent(e.target.value)} autoComplete="current-password" />
        </Field>
      )}
      <Field label="New Password"><PasswordInput className="input" value={pw} onChange={e => setPw(e.target.value)} autoComplete="new-password" /></Field>
      <Field label="Confirm Password"><PasswordInput className="input" value={confirm} onChange={e => setConfirm(e.target.value)} autoComplete="new-password" onKeyDown={e => e.key === 'Enter' && submit()} /></Field>
      {err && <p role="alert" style={{ color: 'var(--danger)', fontSize: 13, marginBottom: 12 }}>{err}</p>}
      <button className="btn btn-primary" style={{ width: '100%' }} disabled={busy} onClick={submit}>{busy ? 'Saving…' : 'Save Password'}</button>
    </AffiliateAuthShell>
  );
};
export default AffiliateResetPasswordPage;
