import React, { useEffect, useState } from 'react';
import AffiliateLayout from '../components/AffiliateLayout';
import { portalRpc, money, dateStr, statusLabel } from '../lib/affiliatePortal';

const Stat: React.FC<{ label: string; value: string; accent?: string }> = ({ label, value, accent }) => (
  <div className="card" style={{ padding: 16 }}>
    <div style={{ color: 'var(--text-muted)', fontSize: 12.5, marginBottom: 6 }}>{label}</div>
    <div style={{ fontSize: 20, fontWeight: 700, color: accent }}>{value}</div>
  </div>
);

const AffiliateEarningsPage: React.FC = () => {
  const [e, setE] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => { portalRpc('affiliate_portal_earnings').then(setE).catch(x => setErr(x.message)); }, []);

  return (
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>Earnings</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 20 }}>A full breakdown of the commission your network has generated.</p>
      {err && <p style={{ color: 'var(--danger)' }}>{err}</p>}
      {!e ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : (
        <>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(140px,1fr))', gap: 12, marginBottom: 22 }}>
            <Stat label="Lifetime Earned" value={money(e.summary?.lifetime)} />
            <Stat label="Unpaid" value={money(e.summary?.unpaid)} accent="var(--warning)" />
            <Stat label="Paid" value={money(e.summary?.paid)} accent="var(--success)" />
            <Stat label="Blocked" value={money(e.summary?.blocked)} accent="var(--danger)" />
            <Stat label="Reversed" value={money(e.summary?.reversed)} />
          </div>

          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>By Tier</h3>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(150px,1fr))', gap: 12, marginBottom: 22 }}>
            <Stat label="Tier 1" value={money(e.by_tier?.tier1)} />
            <Stat label="Tier 2" value={money(e.by_tier?.tier2)} />
          </div>

          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>By Month</h3>
          <div className="card" style={{ padding: 0, overflow: 'auto', marginBottom: 22 }}>
            <table className="table" style={{ width: '100%' }}>
              <thead><tr><th>Month</th><th style={{ textAlign: 'right' }}>Tier 1</th><th style={{ textAlign: 'right' }}>Tier 2</th><th style={{ textAlign: 'right' }}>Total</th></tr></thead>
              <tbody>
                {(e.by_month ?? []).length === 0 && <tr><td colSpan={4} style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 16 }}>No earnings yet</td></tr>}
                {(e.by_month ?? []).map((m: any, i: number) => (
                  <tr key={i}><td>{m.month}</td><td style={{ textAlign: 'right' }}>{money(m.tier1)}</td><td style={{ textAlign: 'right' }}>{money(m.tier2)}</td><td style={{ textAlign: 'right', fontWeight: 600 }}>{money(m.total)}</td></tr>
                ))}
              </tbody>
            </table>
          </div>

          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>By Purchase</h3>
          <div className="card" style={{ padding: 0, overflow: 'auto' }}>
            <table className="table" style={{ width: '100%' }}>
              <thead><tr><th>Date</th><th>Customer</th><th>Description</th><th style={{ textAlign: 'right' }}>Purchase</th><th style={{ textAlign: 'right' }}>Commission</th><th>Status</th></tr></thead>
              <tbody>
                {(e.by_purchase ?? []).length === 0 && <tr><td colSpan={6} style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 16 }}>No purchases yet</td></tr>}
                {(e.by_purchase ?? []).map((p: any, i: number) => {
                  const st = statusLabel(p.status);
                  return (
                    <tr key={i}>
                      <td>{dateStr(p.purchase_date)}</td><td>{p.customer_name}</td><td>Purchase</td>
                      <td style={{ textAlign: 'right' }}>{money(p.purchase_amount)}</td>
                      <td style={{ textAlign: 'right' }}>{money(p.your_commission)}</td>
                      <td><span className={'badge ' + st.cls}>{st.label}</span></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </>
      )}
    </AffiliateLayout>
  );
};
export default AffiliateEarningsPage;
