import React from 'react';
import { UserPlus } from 'lucide-react';

// SPEC_PHASE6A (fee-based registration) has been rolled back. The membership-
// based affiliate system replaces it and is built over the membership phases;
// the new /affiliates page arrives in Phase 5 of that plan. Route kept live so
// existing links and the sidebar entry don't 404.
const AffiliatesPage: React.FC = () => (
  <div>
    <div className="page-header">
      <div><h2>Affiliates</h2></div>
    </div>
    <div className="card">
      <div className="empty-state" style={{ padding: '48px 24px' }}>
        <UserPlus size={40} style={{ opacity: 0.3 }} />
        <p style={{ fontWeight: 600, marginTop: 12, fontSize: 15 }}>
          The Affiliate module is being upgraded to the new membership-based system.
        </p>
        <p style={{ fontSize: 13, color: 'var(--text-muted)', marginTop: 6, maxWidth: 420, textAlign: 'center' }}>
          Affiliate eligibility will be tied to membership rather than a registration fee.
          This page will return once the membership foundation is in place.
        </p>
      </div>
    </div>
  </div>
);

export default AffiliatesPage;
