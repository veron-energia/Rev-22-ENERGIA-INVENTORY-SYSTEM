import React from 'react';
import { AlertTriangle, ShieldCheck } from 'lucide-react';

// The two notices the portal shows in place of what it may not show (the
// Owner, 17 Nov 2026):
//   'checking'   508: the login joined a customer record on the phone number
//                alone, and Energia has not confirmed yet that it is theirs;
//   'suspended'  509: the affiliate is suspended, so the portal is closed.
export const PORTAL_NOTICE_COPY = {
  checking: {
    title: 'We are checking your account',
    body: 'Thank you for joining. Energia is confirming that this customer record is yours. Your referrals, earnings and payouts will show here once that is done. Please contact Energia if you have any questions.',
  },
  suspended: {
    title: 'Your affiliate account is suspended',
    body: 'Your affiliate portal is closed for now. Please contact Energia if you have any questions.',
  },
} as const;

const AffiliatePortalNotice: React.FC<{ kind: 'checking' | 'suspended' }> = ({ kind }) => {
  const copy = PORTAL_NOTICE_COPY[kind];
  const suspended = kind === 'suspended';
  return (
    <div className="card" role="status" data-notice={kind === 'suspended' ? 'portal-suspended' : 'portal-checking'}
      style={{ padding: 18, marginBottom: 20, display: 'flex', gap: 12, alignItems: 'flex-start',
               borderColor: suspended ? 'var(--danger)' : 'var(--primary)' }}>
      <span style={{ flex: '0 0 auto', marginTop: 2 }}>
        {suspended ? <AlertTriangle size={18} color="var(--danger)" /> : <ShieldCheck size={18} color="var(--primary)" />}
      </span>
      <div className="portal-break" style={{ minWidth: 0 }}>
        <strong style={{ display: 'block', fontSize: 15, marginBottom: 6 }}>{copy.title}</strong>
        <p style={{ fontSize: 13.5, color: 'var(--text-secondary)', lineHeight: 1.6, margin: 0 }}>{copy.body}</p>
      </div>
    </div>
  );
};

export default AffiliatePortalNotice;
