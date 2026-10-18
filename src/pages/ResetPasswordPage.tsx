import React, { useState } from 'react';
import { PasswordInput } from '../components/PasswordInput';
import { Link, useNavigate } from 'react-router-dom';
import { Leaf } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { changePassword, AUTH_EMAIL_COPY } from '../lib/authEmail';
import { useResetSession } from '../lib/resetSession';

// Staff reset page, reached from the recovery link.
//
// Supabase turns the link into a recovery session on arrival — unchanged from
// before, and it works in a different browser from the one that asked, because
// an admin-generated link carries no browser-held verifier.
//
// The change itself goes through the auth-change-password Edge Function so the
// notification is sent on Supabase's confirmation rather than on this page's word.
//
// ADMIN-AUTH-9: a session that did not just come from the email link (someone
// already signed in on a shared device) must give the current password, and
// the page says whose password it is, with "Not you? Sign out". Staff have no
// other screen to change their own password, so this stays their way to do it.
// That rule is the server's (auth-change-password), not Supabase Auth's: see
// src/lib/resetSession.ts for what it does not stop.
const ResetPasswordPage: React.FC = () => {
  const nav = useNavigate();
  const { mode, email, needCurrentPassword } = useResetSession();
  const [current, setCurrent] = useState('');
  const [pw, setPw] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const signedIn = mode === 'signed_in';

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
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
    nav('/', { replace: true });
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    nav('/login', { replace: true });
  };

  // Someone who has forgotten the current password (the link was opened too
  // long ago, or they are signed in) asks for a new link. Signing out first
  // keeps the new link apart from this session.
  const requestNewLink = async () => {
    await supabase.auth.signOut();
    nav('/forgot-password', { replace: true });
  };

  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20, background: 'var(--bg)' }}>
      <div style={{ width: '100%', maxWidth: 400 }}>
        <div style={{ textAlign: 'center', marginBottom: 28 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 52, height: 52, borderRadius: 14, background: 'var(--primary)', marginBottom: 14 }}>
            <Leaf size={26} color="#fff" />
          </div>
          <h1 style={{ fontSize: 26, color: 'var(--primary)' }}>{signedIn ? 'Change Your Password' : 'Set a New Password'}</h1>
          <p style={{ color: 'var(--text-muted)', fontSize: 13.5, marginTop: 2 }}>
            {signedIn ? <>Change the password for <strong>{email}</strong></> : 'Choose a new password for your account'}
          </p>
        </div>

        <div className="card" style={{ padding: 28 }}>
          {mode === 'checking' && <p style={{ color: 'var(--text-muted)', fontSize: 14, textAlign: 'center' }}>Checking your link…</p>}

          {mode === 'no_session' && (
            <>
              <div className="alert alert-danger" role="alert"><span>⚠</span><div>
                This password reset link has expired or has already been used. Request a new one and use the most recent email.
              </div></div>
              <Link to="/forgot-password" className="btn btn-primary" style={{ width: '100%', marginTop: 6 }}>Request a new link</Link>
            </>
          )}

          {(mode === 'from_link' || signedIn) && (
            <form onSubmit={submit} className="form-grid">
              {mode === 'from_link' && email && (
                <p style={{ fontSize: 13, color: 'var(--text-secondary)', margin: 0 }}>For <strong>{email}</strong></p>
              )}
              {signedIn && (
                <div className="form-group">
                  <label htmlFor="reset-current">Current Password</label>
                  <PasswordInput id="reset-current" value={current} onChange={e => setCurrent(e.target.value)}
                    autoComplete="current-password" required autoFocus />
                </div>
              )}
              <div className="form-group">
                <label htmlFor="reset-new">New Password</label>
                <PasswordInput id="reset-new" value={pw} onChange={e => setPw(e.target.value)}
                  placeholder="At least 8 characters" autoComplete="new-password" required autoFocus={!signedIn} />
              </div>
              <div className="form-group">
                <label htmlFor="reset-confirm">Confirm Password</label>
                <PasswordInput id="reset-confirm" value={confirm} onChange={e => setConfirm(e.target.value)}
                  autoComplete="new-password" required />
              </div>
              {err && <div className="alert alert-danger" role="alert" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
              <button type="submit" className="btn btn-primary" disabled={busy} style={{ width: '100%', marginTop: 4 }}>
                {busy ? 'Saving…' : 'Save password'}
              </button>
              {signedIn && (
                <p style={{ fontSize: 13, color: 'var(--text-muted)', textAlign: 'center', margin: 0 }}>
                  Forgot your current password?{' '}
                  <button type="button" className="btn-link" onClick={() => void requestNewLink()}
                          style={{ background: 'none', border: 0, padding: 0, color: 'var(--primary)', fontWeight: 600, cursor: 'pointer' }}>
                    Request a new link
                  </button>
                </p>
              )}
              {signedIn && (
                <p style={{ fontSize: 13, color: 'var(--text-muted)', textAlign: 'center', margin: 0 }}>
                  Not you?{' '}
                  <button type="button" className="btn-link" onClick={() => void signOut()}
                          style={{ background: 'none', border: 0, padding: 0, color: 'var(--primary)', fontWeight: 600, cursor: 'pointer' }}>
                    Sign out
                  </button>
                </p>
              )}
            </form>
          )}
        </div>
      </div>
    </div>
  );
};

export default ResetPasswordPage;
