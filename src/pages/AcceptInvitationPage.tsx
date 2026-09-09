import React, { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Leaf } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { acceptInvitation } from '../lib/userInvitations';
import '../components/users/users.css';

/**
 * Where an invitation link lands.
 *
 * Supabase turns the link into a session on arrival, exactly as the recovery
 * page does. That session is necessary but not sufficient: a link issued before
 * an invitation was cancelled still produces one, so the server checks the
 * invitation as well and refuses a cancelled or already-used one.
 *
 * Nothing here decides that setup succeeded. The password is set by Supabase
 * through the Edge Function, and only the server's answer activates the account.
 */
const AcceptInvitationPage: React.FC = () => {
  const nav = useNavigate();
  const [state, setState] = useState<'checking' | 'ready' | 'no_session' | 'done'>('checking');
  const [account, setAccount] = useState<{ email: string; name: string } | null>(null);
  const [signedInAs, setSignedInAs] = useState<string | null>(null);
  const [pw, setPw] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [refused, setRefused] = useState<string | null>(null);

  // Wait for the session before calling the link stale, or a good link looks
  // broken on a slow connection.
  useEffect(() => {
    let cancelled = false;
    const read = async (session: unknown) => {
      if (cancelled) return;
      if (!session) { setState('no_session'); return; }
      const { data } = await supabase.auth.getUser();
      if (cancelled) return;
      const user = data?.user;
      if (!user) { setState('no_session'); return; }
      const meta = (user.user_metadata ?? {}) as { full_name?: string };
      setAccount({ email: user.email ?? '', name: meta.full_name ?? '' });

      // Somebody already signed in as themselves, opening an invitation meant
      // for a colleague. Better to say so than to quietly take over the session.
      const invited = (user.user_metadata as { invited_to?: string } | null)?.invited_to;
      const alreadyActive = user.email_confirmed_at && invited !== 'energia_internal';
      setSignedInAs(alreadyActive ? (user.email ?? null) : null);
      setState('ready');
    };

    supabase.auth.getSession().then(({ data }) => void read(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => { void read(session); });
    return () => { cancelled = true; sub.subscription.unsubscribe(); };
  }, []);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (busy) return;
    setErr(null); setRefused(null);
    if (pw.length < 8) { setErr('Password must be at least 8 characters.'); return; }
    if (pw !== confirm) { setErr('Passwords do not match.'); return; }

    setBusy(true);
    const result = await acceptInvitation(pw);
    setBusy(false);

    switch (result.kind) {
      case 'activated':
        setState('done');
        setTimeout(() => nav('/', { replace: true }), 1200);
        return;
      case 'invalid_link':
        setState('no_session'); setErr(result.message); return;
      case 'password_rejected':
        setErr(result.message); return;
      case 'refused':
        setRefused(result.message); return;
      default:
        setErr(result.message);
    }
  };

  const switchAccount = async () => {
    await supabase.auth.signOut();
    setSignedInAs(null); setState('no_session');
  };

  return (
    <div style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20, background: 'var(--bg)' }}>
      <div style={{ width: '100%', maxWidth: 420 }}>
        <div style={{ textAlign: 'center', marginBottom: 28 }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', justifyContent: 'center', width: 52, height: 52, borderRadius: 14, background: 'var(--primary)', marginBottom: 14 }}>
            <Leaf size={26} color="#fff" />
          </div>
          <h1 style={{ fontSize: 26, color: 'var(--primary)' }}>Set Up Your Account</h1>
          <p style={{ color: 'var(--text-muted)', fontSize: 13.5, marginTop: 2 }}>
            Choose a password to finish joining Energia
          </p>
        </div>

        <div className="card users-scope" style={{ padding: 28 }}>
          {state === 'checking' && (
            <p style={{ color: 'var(--text-muted)', fontSize: 14, textAlign: 'center' }}>Checking your invitation…</p>
          )}

          {state === 'no_session' && (
            <>
              <div className="alert alert-danger" role="alert"><span>⚠</span><div>
                {err ?? 'This invitation link has expired or has already been used. '
                      + 'Ask whoever invited you to send a new one.'}
              </div></div>
              <Link to="/login" className="btn btn-secondary" style={{ width: '100%', marginTop: 12 }}>
                Go to sign in
              </Link>
            </>
          )}

          {state === 'ready' && refused && (
            <div className="alert alert-danger" role="alert"><span>⚠</span><div>{refused}</div></div>
          )}

          {state === 'ready' && signedInAs && (
            <div className="alert alert-warning" role="status">
              <span>⚠</span>
              <div>
                You are signed in as <strong>{signedInAs}</strong>. Setting a password here would
                change that account, not the invited one.
                <button type="button" className="btn btn-secondary btn-sm" style={{ marginTop: 8 }}
                        onClick={() => void switchAccount()}>
                  Sign out and open the invitation again
                </button>
              </div>
            </div>
          )}

          {state === 'ready' && !signedInAs && !refused && (
            <form onSubmit={submit} noValidate>
              <div className="form-group">
                <label>Your account</label>
                <p style={{ fontSize: 13.5, margin: 0 }}>
                  {account?.name && <><strong>{account.name}</strong><br /></>}
                  {account?.email}
                </p>
                <p className="users-hint">
                  This is the address you will sign in with. If it is not yours, do not continue.
                </p>
              </div>

              <div className="form-group">
                <label htmlFor="acc-pw">Choose a password *</label>
                <input id="acc-pw" type="password" value={pw} autoComplete="new-password"
                       onChange={e => setPw(e.target.value)} />
                <p className="users-hint">At least 8 characters. Nobody else will know it.</p>
              </div>

              <div className="form-group">
                <label htmlFor="acc-confirm">Confirm password *</label>
                <input id="acc-confirm" type="password" value={confirm} autoComplete="new-password"
                       onChange={e => setConfirm(e.target.value)} />
              </div>

              {err && <div className="alert alert-danger" role="alert"><span>⚠</span><div>{err}</div></div>}

              <button type="submit" className="btn btn-primary" style={{ width: '100%' }} disabled={busy}>
                {busy ? 'Setting up…' : 'Set password and continue'}
              </button>
            </form>
          )}

          {state === 'done' && (
            <div className="alert alert-success" role="status"><span>✓</span><div>
              <strong>Your account is ready.</strong> Taking you in…
            </div></div>
          )}
        </div>
      </div>
    </div>
  );
};

export default AcceptInvitationPage;
