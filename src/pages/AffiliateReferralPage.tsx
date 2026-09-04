import React, { useEffect, useState } from 'react';
import AffiliateLayout from '../components/AffiliateLayout';
import QRCodeCard, { publicAppUrl } from '../components/QRCodeCard';
import { portalRpc } from '../lib/affiliatePortal';
import { AlertTriangle } from 'lucide-react';

const AffiliateReferralPage: React.FC = () => {
  const [info, setInfo] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => { portalRpc('affiliate_portal_referral_info').then(setInfo).catch(e => setErr(e.message)); }, []);

  const url = info?.referral_code ? `${publicAppUrl()}/r/${info.referral_code}` : '';

  return (
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>My Referral QR</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 20 }}>
        Share your personal Energia referral QR or link. Friends and family who register through it will be placed directly under you as a referral.
      </p>
      {err && <p className="affiliate-break" style={{ color: 'var(--danger)' }}>{err}</p>}
      {!info ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : (
        <>
          {info.accepting === false && (
            <div className="card" style={{ padding: 14, marginBottom: 18, display: 'flex', gap: 10, alignItems: 'flex-start', borderColor: 'var(--danger)' }}>
              <AlertTriangle size={18} color="var(--danger)" style={{ marginTop: 1 }} />
              <div className="affiliate-break" style={{ fontSize: 13.5, color: 'var(--text-secondary)', minWidth: 0 }}>
                Your affiliate account is currently suspended. New referrals cannot be registered through your link. Please contact Energia.
              </div>
            </div>
          )}
          {info.accepting !== false && url && (
            <QRCodeCard url={url} title="Your Referral Link" filename={`energia-referral-${info.referral_code}`}
              caption="Anyone who registers through this link becomes a customer under you. They do not automatically become an affiliate." />
          )}
          <div style={{ marginTop: 18, color: 'var(--text-muted)', fontSize: 13 }}>
            Direct referrals so far: <b style={{ color: 'var(--text)' }}>{info.direct_referrals ?? 0}</b>
          </div>
        </>
      )}
    </AffiliateLayout>
  );
};
export default AffiliateReferralPage;
