import React, { useEffect, useState } from 'react';
import { useLocation } from 'react-router-dom';
import { PasswordInput } from '../components/PasswordInput';
import AffiliateLayout from '../components/AffiliateLayout';
import { usePortalRpc, dateStr } from '../lib/affiliatePortal';
import { PortalError } from '../components/AffiliateResponsive';
import { changePassword, resendVerification, AUTH_EMAIL_COPY } from '../lib/authEmail';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';

const Row: React.FC<{ label: string; value: React.ReactNode }> = ({ label, value }) => (
  <div className="portal-kv">
    <span className="k">{label}</span>
    <span className="v">{value}</span>
  </div>
);

const AffiliateAccountPage: React.FC = () => {
  const { data: me, err, retry } = usePortalRpc<any>('affiliate_portal_me');
  const { session } = useAuth();
  const location = useLocation();
  // 437 (the Owner, 20 Oct 2026, decisions 2 and 3): the app's own "email
  // verified". Unknown (not shown) until read, or when the server has no 437;
  // 'error' when the read failed (said, with Try again).
  const [verified, setVerified] = useState<'unknown' | 'yes' | 'no' | 'error'>('unknown');
  const [readTick, setReadTick] = useState(0);
  const [verifyBusy, setVerifyBusy] = useState(false);
  const [verifyMsg, setVerifyMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const navState = location.state as { emailVerified?: boolean; emailVerifyFailed?: boolean } | null;
  const justVerified = navState?.emailVerified === true;
  // The emailed link was opened but could not verify the email (verify page).
  const verifyFailed = navState?.emailVerifyFailed === true;
  const [current, setCurrent] = useState('');
  const [pw, setPw] = useState(''); const [confirm, setConfirm] = useState('');
  const [pwMsg, setPwMsg] = useState<string | null>(null); const [pwBusy, setPwBusy] = useState(false);

  const uid = session?.user?.id ?? null;
  // Is the email verified now? null: unknown (no 437 on the server, or no
  // account); throws when the read itself failed.
  const readVerified = async (id: string): Promise<boolean | null> => {
    const { data, error } = await supabase.from('affiliate_accounts').select('email_verified_at').eq('auth_user_id', id).maybeSingle();
    if (error) {
      // Before 437 the column is not there: say nothing rather than "not verified".
      if ((error as { code?: string }).code === '42703' || /does not exist/i.test(error.message ?? '')) return null;
      throw new Error(error.message);
    }
    if (!data) return null;
    return !!(data as { email_verified_at: string | null }).email_verified_at;
  };
  useEffect(() => {
    if (!uid) return;
    let live = true;
    readVerified(uid).then(
      v => { if (live) setVerified(v === null ? 'unknown' : v ? 'yes' : 'no'); },
      () => { if (live) setVerified('error'); });
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [uid, justVerified, readTick]);

  // The verification email goes through auth-resend-verification, as the
  // other Auth emails do (Pabbly). Its link signs the affiliate in at
  // /affiliate/verify, which marks the email verified and comes back here.
  const sendVerification = async () => {
    if (verifyBusy || !me?.email) return;
    setVerifyBusy(true); setVerifyMsg(null);
    const result = await resendVerification(me.email);
    if (!result.ok) { setVerifyBusy(false); setVerifyMsg({ ok: false, text: result.message ?? AUTH_EMAIL_COPY.unavailable }); return; }
    if (result.kind === 'not_sent') { setVerifyBusy(false); setVerifyMsg({ ok: false, text: result.message ?? AUTH_EMAIL_COPY.notSent }); return; }
    // The server answers "submitted" whether or not it sent anything (it
    // tells no one which addresses need it). Verified meanwhile, in another
    // tab, nothing was sent: read it again and say so.
    let nowVerified: boolean | null = null;
    if (uid) { try { nowVerified = await readVerified(uid); } catch { /* keep the answer the server gave */ } }
    setVerifyBusy(false);
    if (nowVerified) { setVerified('yes'); setVerifyMsg({ ok: true, text: 'Your email is already verified.' }); return; }
    setVerifyMsg({ ok: true, text: AUTH_EMAIL_COPY.verifyEmailSent });
  };

  // Goes through the auth-change-password Edge Function rather than
  // supabase.auth.updateUser, so the "your password was changed" notification is
  // sent by a server that saw Supabase confirm the change. A notification that
  // fails to send does not make the password change a failure.
  // ADMIN-AUTH-9: the current password is needed too, so a phone left signed
  // in cannot be used to take the account over.
  const changePw = async () => {
    if (pwBusy) return;
    setPwMsg(null);
    if (!current) { setPwMsg('Enter your current password.'); return; }
    if (pw.length < 8) { setPwMsg('Password must be at least 8 characters.'); return; }
    if (pw !== confirm) { setPwMsg('Passwords do not match.'); return; }
    setPwBusy(true);
    const result = await changePassword(pw, current);
    setPwBusy(false);
    if (!result.ok) { setPwMsg(result.message ?? AUTH_EMAIL_COPY.unavailable); return; }
    setCurrent(''); setPw(''); setConfirm(''); setPwMsg('Password updated.');
  };

  return (
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>Account</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 20 }}>Your affiliate account details.</p>
      {err ? <PortalError message={err} onRetry={retry} /> : !me ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : (
        <>
          <div className="card" style={{ padding: 18, marginBottom: 20 }}>
            <Row label="Name" value={me.name} />
            <Row label="Email" value={<>
              {me.email}
              {(verified === 'yes' || verified === 'no') && (
                <span data-email-verified={verified} className={'badge ' + (verified === 'yes' ? 'badge-success' : 'badge-accent')} style={{ marginLeft: 8 }}>
                  {verified === 'yes' ? 'Verified' : 'Not verified'}
                </span>
              )}
              {verified === 'error' && (
                <span data-email-verified="error" style={{ marginLeft: 8, fontSize: 12.5, color: 'var(--danger)' }}>
                  Could not check your email status.{' '}
                  <button type="button" className="btn btn-secondary btn-sm" onClick={() => setReadTick(t => t + 1)}>Try again</button>
                </span>
              )}
            </>} />
            <Row label="Affiliate Status" value={<span className={'badge ' + (me.status === 'suspended' ? 'badge-danger' : 'badge-success')}>{me.status === 'suspended' ? 'Suspended' : 'Active'}</span>} />
            <Row label="Referral Code" value={me.referral_code} />
            <Row label="Joined" value={dateStr(me.joined_at)} />
          </div>
          {verified === 'yes' && (justVerified || verifyMsg) && (
            <div className="card" role="status" data-note="email-verified" style={{ padding: 14, marginBottom: 20, borderColor: 'var(--success)', color: 'var(--success)', fontSize: 13.5 }}>
              {justVerified ? 'Thank you. Your email is verified.' : verifyMsg?.text}
            </div>
          )}
          {verified === 'no' && (
            <div className="card" data-section="verify-email" style={{ padding: 18, marginBottom: 20 }}>
              <h3 style={{ fontSize: 15, fontWeight: 600, marginBottom: 8 }}>Verify your email</h3>
              <p style={{ fontSize: 13.5, color: 'var(--text-secondary)', lineHeight: 1.6, marginBottom: 12 }}>
                We will send a link to <b>{me.email}</b>. Open it to confirm the address is yours. Your portal, referral link,
                commission and payouts work the same until then.
              </p>
              {verifyFailed && !verifyMsg && (
                <p role="alert" data-note="verify-failed" style={{ fontSize: 13, marginBottom: 10, color: 'var(--danger)' }}>
                  We could not verify your email from that link. Send a new one.
                </p>
              )}
              {verifyMsg && <p role={verifyMsg.ok ? 'status' : 'alert'} style={{ fontSize: 13, marginBottom: 10, color: verifyMsg.ok ? 'var(--success)' : 'var(--danger)' }}>{verifyMsg.text}</p>}
              <button className="btn btn-primary" disabled={verifyBusy} onClick={() => void sendVerification()} style={{ minHeight: 44 }}>
                {verifyBusy ? 'Sending…' : 'Send verification email'}
              </button>
            </div>
          )}
          <div className="card" style={{ padding: 18 }}>
            <h3 style={{ fontSize: 15, fontWeight: 600, marginBottom: 12 }}>Change Password</h3>
            <div style={{ marginBottom: 12 }}>
              <label htmlFor="account-current-password" style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Current Password</label>
              <PasswordInput id="account-current-password" className="input" value={current} onChange={e => setCurrent(e.target.value)} autoComplete="current-password" />
            </div>
            <div style={{ marginBottom: 12 }}>
              <label htmlFor="account-new-password" style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>New Password</label>
              <PasswordInput id="account-new-password" className="input" value={pw} onChange={e => setPw(e.target.value)} autoComplete="new-password" />
            </div>
            <div style={{ marginBottom: 12 }}>
              <label htmlFor="account-confirm-password" style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Confirm Password</label>
              <PasswordInput id="account-confirm-password" className="input" value={confirm} onChange={e => setConfirm(e.target.value)} autoComplete="new-password" />
            </div>
            {pwMsg && <p role={pwMsg === 'Password updated.' ? 'status' : 'alert'} style={{ fontSize: 13, marginBottom: 10, color: pwMsg === 'Password updated.' ? 'var(--success)' : 'var(--danger)' }}>{pwMsg}</p>}
            <button className="btn btn-primary" disabled={pwBusy} onClick={changePw} style={{ minHeight: 44 }}>{pwBusy ? 'Saving…' : 'Update Password'}</button>
          </div>
        </>
      )}
    </AffiliateLayout>
  );
};
export default AffiliateAccountPage;
