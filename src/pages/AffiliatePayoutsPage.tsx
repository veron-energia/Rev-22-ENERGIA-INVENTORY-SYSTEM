import React, { useEffect, useState } from 'react';
import AffiliateLayout from '../components/AffiliateLayout';
import { portalRpc, money, dateStr } from '../lib/affiliatePortal';

const AffiliatePayoutsPage: React.FC = () => {
  const [rows, setRows] = useState<any[] | null>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => { portalRpc('affiliate_portal_payouts').then(setRows).catch(e => setErr(e.message)); }, []);

  return (
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>Payout History</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 20 }}>Payouts issued to you by Energia.</p>
      {err && <p style={{ color: 'var(--danger)' }}>{err}</p>}
      {!rows ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : (
        <div className="card" style={{ padding: 0, overflow: 'auto' }}>
          <table className="table" style={{ width: '100%' }}>
            <thead><tr><th>Month</th><th style={{ textAlign: 'right' }}>Tier 1</th><th style={{ textAlign: 'right' }}>Tier 2</th><th style={{ textAlign: 'right' }}>Total</th><th>Paid Date</th><th>Status</th></tr></thead>
            <tbody>
              {rows.length === 0 && <tr><td colSpan={6} style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 18 }}>No payouts yet</td></tr>}
              {rows.map((r, i) => (
                <tr key={i}>
                  <td>{r.payout_month}</td>
                  <td style={{ textAlign: 'right' }}>{money(r.tier1)}</td>
                  <td style={{ textAlign: 'right' }}>{money(r.tier2)}</td>
                  <td style={{ textAlign: 'right', fontWeight: 600 }}>{money(r.total)}</td>
                  <td>{dateStr(r.paid_date)}</td>
                  <td><span className={'badge ' + (r.status === 'paid' ? 'badge-success' : 'badge-muted')}>{r.status === 'paid' ? 'Paid' : 'Cancelled'}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </AffiliateLayout>
  );
};
export default AffiliatePayoutsPage;
