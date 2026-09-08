import React, { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Leaf } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { changePassword, AUTH_EMAIL_COPY } from '../lib/authEmail';

// Staff reset page, reached from the recovery link.
//
// Supabase turns the link into a recovery session on arrival — unchanged from
// before, and it works in a different browser from the one that asked, because
// an admin-generated link carries no browser-held verifier.
//
// The change itself goes through the auth-change-password Edge Function so the
// notification is sent on Supabase's confirmation rather than on this page's word.
const ResetPasswordPage: React.FC = () => {
  const nav = useNavigate();
  const [ready, setReady] = useState<'checking' | 'ok' | 'no_session'>('checking');
  const [pw, setPw] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  // The client parses the link on load; wait for the session before deciding the
  // link is stale, or a good link looks broken on a slow connection.
  useEffect(() => {
    let cancelled = false;
    supabase.auth.getSession().then(({ data }) => {
      if (!cancelled) setReady(data.session ? 'ok' : 'no_session');
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!cancelled && session) setReady('ok');
    });
    return () => { cancelled = true; sub.subscription.unsubscribe(); };
  }, []);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setErr(null);
    if (pw.length < 8) { setErr('Password must be at least 8 characters.'); return; }
    if (pw !== confirm) { setErr('Passwords do not match.'); return; }
    setBusy(true);
    const result = await changePassword(pw);
    setBusy(false);
    if (!result.ok) {
      setErr(result.message ?? AUTH_EMAIL_COPY.unavailable);
      if (result.kind === 'unauthorized') setReady('no_session');
      return;
    }
    nav('/', { replace: true });
  };

  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20, background: 'var(--bg)' }}>
      <div style={{ width: '100%', maxWidth: 400 }}>
        <div style={{ textAlign: 'center', marginBottom: 28 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 52, height: 52, borderRadius: 14, background: 'var(--primary)', marginBottom: 14 }}>
            <Leaf size={26} color="#fff" />
          </div>
          <h1 style={{ fontSize: 26, color: 'var(--primary)' }}>Set a New Password</h1>
          <p style={{ color: 'var(--text-muted)', fontSize: 13.5, marginTop: 2 }}>Choose a new password for your account</p>
        </div>

        <div className="card" style={{ padding: 28 }}>
          {ready === 'checking' && <p style={{ color: 'var(--text-muted)', fontSize: 14, textAlign: 'center' }}>Checking your link…</p>}

          {ready === 'no_session' && (
            <>
              <div className="alert alert-danger"><span>⚠</span><div>
                This password reset link has expired or has already been used. Request a new one and use the most recent email.
              </div></div>
              <Link to="/forgot-password" className="btn btn-primary" style={{ width: '100%', marginTop: 6 }}>Request a new link</Link>
            </>
          )}

          {ready === 'ok' && (
            <form onSubmit={submit} className="form-grid">
              <div className="form-group">
                <label>New Password</label>
                <input type="password" value={pw} onChange={e => setPw(e.target.value)}
                  placeholder="At least 8 characters" autoComplete="new-password" required autoFocus />
              </div>
              <div className="form-group">
                <label>Confirm Password</label>
                <input type="password" value={confirm} onChange={e => setConfirm(e.target.value)}
                  autoComplete="new-password" required />
              </div>
              {err && <div className="alert alert-danger" style={{ marginBottom: 0 }}><span>⚠</span><div>{err}</div></div>}
              <button type="submit" className="btn btn-primary" disabled={busy} style={{ width: '100%', marginTop: 4 }}>
                {busy ? 'Saving…' : 'Save password'}
              </button>
            </form>
          )}
        </div>
      </div>
    </div>
  );
};

export default ResetPasswordPage;
