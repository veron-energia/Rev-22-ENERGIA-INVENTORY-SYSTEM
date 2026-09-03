import React, { useEffect, useState } from 'react';
import AffiliateLayout from '../components/AffiliateLayout';
import { portalRpc, money, dateStr } from '../lib/affiliatePortal';

const NetTable: React.FC<{ rows: any[]; showParent?: boolean }> = ({ rows, showParent }) => (
  <div className="card" style={{ padding: 0, overflow: 'auto', marginBottom: 20 }}>
    <table className="table" style={{ width: '100%' }}>
      <thead><tr>
        <th>Customer</th>{showParent && <th>Referred By</th>}<th>Joined</th>
        <th style={{ textAlign: 'right' }}>Purchases</th><th style={{ textAlign: 'right' }}>Total Spent</th><th style={{ textAlign: 'right' }}>Your Commission</th>
      </tr></thead>
      <tbody>
        {rows.length === 0 && <tr><td colSpan={showParent ? 6 : 5} style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 18 }}>No members yet</td></tr>}
        {rows.map((r, i) => (
          <tr key={i}>
            <td>{r.customer_name}</td>{showParent && <td>{r.parent_name}</td>}
            <td>{dateStr(r.referral_date || r.joined_at)}</td>
            <td style={{ textAlign: 'right' }}>{r.purchases}</td>
            <td style={{ textAlign: 'right' }}>{money(r.total_spent)}</td>
            <td style={{ textAlign: 'right' }}>{money(r.your_commission)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);

const AffiliateNetworkPage: React.FC = () => {
  const [n, setN] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => { portalRpc('affiliate_portal_network').then(setN).catch(e => setErr(e.message)); }, []);

  return (
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>My Network</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 20 }}>Your direct referrals and their referrals — the two levels you earn from.</p>
      {err && <p style={{ color: 'var(--danger)' }}>{err}</p>}
      {!n ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : (
        <>
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>Tier 1 — Direct Referrals ({(n.tier1 ?? []).length})</h3>
          <NetTable rows={n.tier1 ?? []} />
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>Tier 2 — Their Referrals ({(n.tier2 ?? []).length})</h3>
          <NetTable rows={n.tier2 ?? []} showParent />
        </>
      )}
    </AffiliateLayout>
  );
};
export default AffiliateNetworkPage;
