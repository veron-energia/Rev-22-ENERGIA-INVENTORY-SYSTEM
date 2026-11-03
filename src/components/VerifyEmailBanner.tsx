import React, { useEffect, useState } from 'react';
import { AlertTriangle } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { readEmailVerified, lastEmailVerified, sendVerificationEmail, VerificationSent } from '../lib/affiliateEmailStatus';

// 3 Nov 2026: a warning at the top of the portal while the affiliate's email
// is not verified, asking them to verify it, with the same Send verification
// email as the Account page. Nothing shows while that is unknown or could
// not be read (the Account page says so, with Try again).
const VerifyEmailBanner: React.FC = () => {
  const { session } = useAuth();
  const uid = session?.user?.id ?? null;
  // The login's own address, which affiliate_portal_me shows on the Account page.
  const email = session?.user?.email ?? null;
  const [verified, setVerified] = useState<boolean | null>(() => lastEmailVerified(uid));
  const [readTick, setReadTick] = useState(0);
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState<VerificationSent | null>(null);

  useEffect(() => {
    if (!uid) return;
    let live = true;
    readEmailVerified(uid).then(v => { if (live) setVerified(v); }, () => { /* keep what shows */ });
    return () => { live = false; };
  }, [uid, readTick]);

  // The emailed link opens in another tab: coming back to this one, read again.
  useEffect(() => {
    if (verified !== false) return;
    const onShow = () => { if (document.visibilityState === 'visible') setReadTick(t => t + 1); };
    document.addEventListener('visibilitychange', onShow);
    return () => document.removeEventListener('visibilitychange', onShow);
  }, [verified]);

  const send = async () => {
    if (busy || !email) return;
    setBusy(true); setSent(null);
    const result = await sendVerificationEmail(uid, email);
    setBusy(false);
    if (result.verified) setVerified(true);
    setSent(result);
  };

  // Verified meanwhile, in another tab: say so where the warning was.
  if (verified && sent?.verified) {
    return (
      <div className="card" role="status" data-banner="email-verified" style={{ padding: 14, marginBottom: 20, borderColor: 'var(--success)', color: 'var(--success)', fontSize: 13.5 }}>
        {sent.text}
      </div>
    );
  }
  if (verified !== false || !email) return null;
  return (
    <div className="alert alert-warning" data-banner="verify-email" style={{ marginBottom: 20 }}>
      <span style={{ flex: '0 0 auto', marginTop: 1 }}><AlertTriangle size={16} /></span>
      <div className="portal-break" style={{ flex: '1 1 auto', minWidth: 0 }}>
        <strong style={{ display: 'block', fontSize: 14, marginBottom: 4 }}>Please verify your email</strong>
        <p style={{ lineHeight: 1.6, marginBottom: 10 }}>
          Energia will send a link to <b>{email}</b>. Open it to confirm the address is yours.
        </p>
        {sent && (
          <p role={sent.ok ? 'status' : 'alert'} style={{ lineHeight: 1.6, marginBottom: 10, fontWeight: 600, color: sent.ok ? undefined : 'var(--danger)' }}>
            {sent.text}
          </p>
        )}
        <button type="button" className="btn btn-primary" disabled={busy} onClick={() => void send()} style={{ minHeight: 44 }}>
          {busy ? 'Sending…' : 'Send verification email'}
        </button>
      </div>
    </div>
  );
};
export default VerifyEmailBanner;
