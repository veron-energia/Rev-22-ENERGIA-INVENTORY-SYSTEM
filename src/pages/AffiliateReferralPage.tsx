import React from 'react';
import AffiliateLayout from '../components/AffiliateLayout';
import QRCodeCard, { publicAppUrl } from '../components/QRCodeCard';
import { usePortalRpc } from '../lib/affiliatePortal';
import { PortalError } from '../components/AffiliateResponsive';
import { AlertTriangle } from 'lucide-react';

const AffiliateReferralPage: React.FC = () => {
  const { data: info, err, retry } = usePortalRpc<any>('affiliate_portal_referral_info');

  const url = info?.referral_code ? `${publicAppUrl()}/r/${info.referral_code}` : '';
  // 454 (the owner, 22 Oct 2026): the short seminar link (<site>/<code>) of each
  // event whose website takes registrations now; none from a server before 454.
  // One card per address (the server lists each once; a site serves one event).
  const seminarLinks: { event_name: string; url: string }[] = Array.isArray(info?.seminar_links)
    ? info.seminar_links.filter((l: any, i: number, all: any[]) => typeof l?.url === 'string' && l.url
        && all.findIndex((o: any) => o?.url === l.url) === i) : [];

  return (
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>My Referral QR</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 20 }}>
        Share your personal Energia referral QR or link. Friends and family who register through it will be placed directly under you as a referral.
      </p>
      {err ? <PortalError message={err} onRetry={retry} /> : !info ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : (
        <>
          {info.accepting === false && (
            <div className="card" style={{ padding: 14, marginBottom: 18, display: 'flex', gap: 10, alignItems: 'flex-start', borderColor: 'var(--danger)' }}>
              <AlertTriangle size={18} color="var(--danger)" style={{ marginTop: 1 }} />
              <div className="portal-break" style={{ fontSize: 13.5, color: 'var(--text-secondary)', minWidth: 0 }}>
                Your affiliate account is currently suspended. New referrals cannot be registered through your link. Please contact Energia.
              </div>
            </div>
          )}
          {info.accepting !== false && url && (
            <QRCodeCard url={url} title="Your free therapy link" filename={`energia-referral-${info.referral_code}`}
              caption="Anyone who registers through this link becomes a customer under you. They do not automatically become an affiliate." />
          )}
          {info.accepting !== false && seminarLinks.map((l, i) => (
            <div key={l.url} style={{ marginTop: 18 }}>
              <QRCodeCard url={l.url} title={`Your link for ${l.event_name}`}
                filename={`energia-seminar-${info.referral_code}${i ? `-${i + 1}` : ''}`}
                caption="New people who register for the seminar through this link are placed under you. Existing Energia customers keep their own referrer. You earn commission when they upgrade to VIP." />
            </div>
          ))}
          <div style={{ marginTop: 18, color: 'var(--text-muted)', fontSize: 13 }}>
            Direct referrals so far: <b style={{ color: 'var(--text)' }}>{info.direct_referrals ?? 0}</b>
          </div>
        </>
      )}
    </AffiliateLayout>
  );
};
export default AffiliateReferralPage;
