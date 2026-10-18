import React, { useCallback, useEffect, useRef, useState } from 'react';
import { PasswordInput } from '../components/PasswordInput';
import { Link, useNavigate } from 'react-router-dom';
import { Leaf } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { acceptInvitation, checkInvitation } from '../lib/userInvitations';
import { signedInFromEmailLink } from '../lib/resetSession';
import { useAuth } from '../context/AuthContext';
import '../components/users/users.css';

/** The server's reason for a pending invitation whose link was opened over 30 minutes ago. */
const LINK_EXPIRED = 'link_expired';

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
 *
 * 429: the page asks the server first whether this login has a pending
 * invitation, and shows the password form only if it has. A login with none
 * (a member of staff or an affiliate who opened a reset link, perhaps long
 * ago), or with a used one, is told so and sent to sign in or reset the
 * password. A cancelled or unfinished invitation, or one for another
 * address, gets the server's words and "Go to sign in" only: that login is
 * closed, so a reset link would not help. The server refuses all of these
 * too, before any password is set.
 *
 * 18 Oct 2026 (the Owner: "30 minutes, like reset links"): with a pending
 * invitation, the password is set only in the 30 minutes after the link was
 * opened. The server decides that, by its own clock, after the checks above;
 * this page never judges the link's age by the device clock. A link opened
 * longer ago gets "This invitation link has expired. Ask for a new
 * invitation." and "Go to sign in", on arrival or when the password is sent;
 * an Owner or Manager then presses Resend on Users & Roles.
 */
const AcceptInvitationPage: React.FC = () => {
  const nav = useNavigate();
  const { refreshProfile } = useAuth();
  const [state, setState] = useState<'checking' | 'ready' | 'no_session' | 'not_invited' | 'check_failed' | 'done'>('checking');
  const [account, setAccount] = useState<{ email: string; name: string } | null>(null);
  const [signedInAs, setSignedInAs] = useState<string | null>(null);
  const [pw, setPw] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [refused, setRefused] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  // Why the server said there is no pending invitation (its `reason`).
  const [refusal, setRefusal] = useState<string | null>(null);
  // The login the server was last asked about, so a token refresh does not ask again.
  const askedFor = useRef<string | null>(null);
  const live = useRef(true);
  useEffect(() => { live.current = true; return () => { live.current = false; }; }, []);

  // Ask the server whether this login has a pending invitation. Only then the form.
  const askServer = useCallback(async () => {
    setState('checking'); setNotice(null); setRefusal(null);
    const answer = await checkInvitation();
    if (!live.current) return;
    switch (answer.kind) {
      case 'pending': setState('ready'); return;
      case 'invalid_link': setErr(answer.message); setState('no_session'); return;
      case 'not_pending': setNotice(answer.message); setRefusal(answer.reason ?? null); setState('not_invited'); return;
      default: setNotice(answer.message); setState('check_failed');
    }
  }, []);

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
      // 429: told apart by how the session signed in, not by the login's
      // details. A session opened from the emailed link (the invitation, or
      // the recovery link a confirmed login gets) may be the invitee's own, so
      // the server is asked whether the login has a pending invitation. That
      // includes a member of staff who was removed and is invited again: their
      // old login is confirmed and was never marked as invited. Any other
      // session (a password sign-in) gets the warning; the server refuses it too.
      const token = (session as { access_token?: string }).access_token;
      const alreadyActive = !!user.email_confirmed_at && !signedInFromEmailLink(token);
      if (alreadyActive) {
        setSignedInAs(user.email ?? null);
        setState('ready');
        return;
      }
      setSignedInAs(null);
      // 429: a session from an emailed link is not enough on its own. Every
      // member of staff and every affiliate who opened a reset link has one.
      if (askedFor.current === user.id) return;
      askedFor.current = user.id;
      await askServer();
    };

    supabase.auth.getSession().then(({ data }) => void read(data.session));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => { void read(session); });
    return () => { cancelled = true; sub.subscription.unsubscribe(); };
  }, [askServer]);

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
        // The app read this account when the link opened, while it was still a
        // pending invitation, and holds it as not active. Read it again now the
        // server has switched it on, or the first screen says "Your account has
        // been deactivated" until a reload (ADMIN-AUTH-5).
        await refreshProfile();
        setTimeout(() => nav('/', { replace: true }), 1200);
        return;
      case 'invalid_link':
        setState('no_session'); setErr(result.message); return;
      case 'password_rejected':
        setErr(result.message); return;
      case 'refused':
        // The link passed 30 minutes while the form was open: the same words
        // and way out as on arrival, in place of the form.
        if (result.reason === LINK_EXPIRED) {
          setNotice(result.message); setRefusal(LINK_EXPIRED); setState('not_invited'); return;
        }
        setRefused(result.message); return;
      default:
        setErr(result.message);
    }
  };

  // The advice to sign in or reset, only where it can help.
  const offersReset = refusal === 'not_invited' || refusal === 'already_accepted';

  const switchAccount = async () => {
    await supabase.auth.signOut();
    askedFor.current = null;
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

          {state === 'not_invited' && (
            <>
              <div className="alert alert-warning" role="status"><span>⚠</span><div>
                {notice ?? 'There is no invitation for this account.'}
              </div></div>
              {/* Sign in or reset only helps someone who has an account: no
                  invitation, or one already used. A cancelled or unfinished
                  invitation's login is closed, so a reset link cannot help. */}
              {offersReset && (
                <p style={{ fontSize: 13.5, margin: '12px 0 0' }}>
                  If you already have an account, sign in. If you forgot your password, ask for a reset link.
                </p>
              )}
              <Link to="/login" className="btn btn-primary" style={{ width: '100%', marginTop: 12 }}>
                Go to sign in
              </Link>
              {offersReset && (
                <>
                  <Link to="/forgot-password" className="btn btn-secondary" style={{ width: '100%', marginTop: 8 }}>
                    Reset my password
                  </Link>
                  <p className="users-hint" style={{ marginTop: 10, textAlign: 'center' }}>
                    Affiliates: <Link to="/affiliate/login">sign in here</Link>.
                  </p>
                </>
              )}
            </>
          )}

          {state === 'check_failed' && (
            <>
              <div className="alert alert-danger" role="alert"><span>⚠</span><div>{notice}</div></div>
              <button type="button" className="btn btn-secondary" style={{ width: '100%', marginTop: 12 }}
                      onClick={() => void askServer()}>
                Try again
              </button>
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
                <PasswordInput id="acc-pw" value={pw} autoComplete="new-password"
                       onChange={e => setPw(e.target.value)} />
                <p className="users-hint">At least 8 characters. Nobody else will know it.</p>
              </div>

              <div className="form-group">
                <label htmlFor="acc-confirm">Confirm password *</label>
                <PasswordInput id="acc-confirm" value={confirm} autoComplete="new-password"
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
