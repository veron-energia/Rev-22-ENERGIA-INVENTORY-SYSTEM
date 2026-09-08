import React, { useEffect, useState } from 'react';
import AffiliateLayout from '../components/AffiliateLayout';
import { portalRpc, dateStr } from '../lib/affiliatePortal';
import { changePassword, AUTH_EMAIL_COPY } from '../lib/authEmail';

const Row: React.FC<{ label: string; value: React.ReactNode }> = ({ label, value }) => (
  <div className="affiliate-kv">
    <span className="k">{label}</span>
    <span className="v">{value}</span>
  </div>
);

const AffiliateAccountPage: React.FC = () => {
  const [me, setMe] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);
  const [pw, setPw] = useState(''); const [confirm, setConfirm] = useState('');
  const [pwMsg, setPwMsg] = useState<string | null>(null); const [pwBusy, setPwBusy] = useState(false);

  useEffect(() => { portalRpc('affiliate_portal_me').then(setMe).catch(e => setErr(e.message)); }, []);

  // Goes through the auth-change-password Edge Function rather than
  // supabase.auth.updateUser, so the "your password was changed" notification is
  // sent by a server that saw Supabase confirm the change. A notification that
  // fails to send does not make the password change a failure.
  const changePw = async () => {
    if (pwBusy) return;
    setPwMsg(null);
    if (pw.length < 8) { setPwMsg('Password must be at least 8 characters.'); return; }
    if (pw !== confirm) { setPwMsg('Passwords do not match.'); return; }
    setPwBusy(true);
    const result = await changePassword(pw);
    setPwBusy(false);
    if (!result.ok) { setPwMsg(result.message ?? AUTH_EMAIL_COPY.unavailable); return; }
    setPw(''); setConfirm(''); setPwMsg('Password updated.');
  };

  return (
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>Account</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 20 }}>Your affiliate account details.</p>
      {err && <p className="affiliate-break" style={{ color: 'var(--danger)' }}>{err}</p>}
      {!me ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : (
        <>
          <div className="card" style={{ padding: 18, marginBottom: 20 }}>
            <Row label="Name" value={me.name} />
            <Row label="Email" value={me.email} />
            <Row label="Affiliate Status" value={<span className={'badge ' + (me.status === 'suspended' ? 'badge-danger' : 'badge-success')}>{me.status === 'suspended' ? 'Suspended' : 'Active'}</span>} />
            <Row label="Referral Code" value={me.referral_code} />
            <Row label="Joined" value={dateStr(me.joined_at)} />
          </div>
          <div className="card" style={{ padding: 18 }}>
            <h3 style={{ fontSize: 15, fontWeight: 600, marginBottom: 12 }}>Change Password</h3>
            <div style={{ marginBottom: 12 }}>
              <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>New Password</label>
              <input className="input" type="password" value={pw} onChange={e => setPw(e.target.value)} />
            </div>
            <div style={{ marginBottom: 12 }}>
              <label style={{ display: 'block', fontSize: 13, fontWeight: 600, marginBottom: 6 }}>Confirm Password</label>
              <input className="input" type="password" value={confirm} onChange={e => setConfirm(e.target.value)} />
            </div>
            {pwMsg && <p style={{ fontSize: 13, marginBottom: 10, color: pwMsg === 'Password updated.' ? 'var(--success)' : 'var(--danger)' }}>{pwMsg}</p>}
            <button className="btn btn-primary" disabled={pwBusy} onClick={changePw} style={{ minHeight: 44 }}>{pwBusy ? 'Saving…' : 'Update Password'}</button>
          </div>
        </>
      )}
    </AffiliateLayout>
  );
};
export default AffiliateAccountPage;
