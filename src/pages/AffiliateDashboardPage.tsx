import React, { useEffect, useState } from 'react';
import AffiliateLayout from '../components/AffiliateLayout';
import { portalRpc, money, dateStr } from '../lib/affiliatePortal';
import { Users, TrendingUp, Wallet, Clock } from 'lucide-react';
import { Stat, StatGrid, DesktopTableCard, MobileCards, MCard, EmptyNote } from '../components/AffiliateResponsive';

const tierLabel = (t: string) => (t === 'tier1' ? 'Tier 1' : 'Tier 2');

const AffiliateDashboardPage: React.FC = () => {
  const [d, setD] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);
  useEffect(() => { portalRpc('affiliate_portal_dashboard').then(setD).catch(e => setErr(e.message)); }, []);

  const recent: any[] = d?.recent ?? [];

  return (
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>Dashboard</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 20 }}>Your Energia affiliate overview</p>
      {err && <p className="affiliate-break" style={{ color: 'var(--danger)' }}>{err}</p>}
      {!d ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : (
        <>
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>My Network</h3>
          <StatGrid>
            <Stat label="Direct Referrals" value={String(d.network?.tier1 ?? 0)} icon={<Users size={15} />} />
            <Stat label="Tier 2 Network" value={String(d.network?.tier2 ?? 0)} icon={<Users size={15} />} />
            <Stat label="Total 2-Level" value={String(d.network?.total ?? 0)} icon={<Users size={15} />} />
          </StatGrid>

          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>Earnings</h3>
          <StatGrid>
            <Stat label="Unpaid" value={money(d.earnings?.unpaid)} icon={<Clock size={15} />} accent="var(--warning)" />
            <Stat label="Paid" value={money(d.earnings?.paid)} icon={<Wallet size={15} />} accent="var(--success)" />
            <Stat label="Lifetime" value={money(d.earnings?.lifetime)} icon={<TrendingUp size={15} />} />
            {Number(d.earnings?.blocked) > 0 && <Stat label="Blocked" value={money(d.earnings?.blocked)} accent="var(--danger)" />}
            {Number(d.earnings?.reversed) > 0 && <Stat label="Reversed" value={money(d.earnings?.reversed)} />}
          </StatGrid>

          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>Tier Breakdown</h3>
          <StatGrid>
            <Stat label="Tier 1 Earnings" value={money(d.by_tier?.tier1)} />
            <Stat label="Tier 2 Earnings" value={money(d.by_tier?.tier2)} />
          </StatGrid>

          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>Recent Activity</h3>
          <DesktopTableCard>
            <table className="table" style={{ width: '100%' }}>
              <thead><tr><th>Customer</th><th>Tier</th><th>Date</th><th>Description</th><th style={{ textAlign: 'right' }}>Amount</th><th style={{ textAlign: 'right' }}>Your Earning</th></tr></thead>
              <tbody>
                {recent.length === 0 && <tr><td colSpan={6} style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 18 }}>No activity yet</td></tr>}
                {recent.map((r, i) => (
                  <tr key={i}>
                    <td>{r.customer_name}</td><td>{tierLabel(r.tier)}</td>
                    <td>{dateStr(r.purchase_date)}</td><td>Purchase</td>
                    <td style={{ textAlign: 'right' }}>{money(r.purchase_amount)}</td>
                    <td style={{ textAlign: 'right' }}>{money(r.your_commission)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </DesktopTableCard>
          <MobileCards>
            {recent.length === 0
              ? <EmptyNote>No activity yet</EmptyNote>
              : recent.map((r, i) => (
                <MCard key={i} title={`${r.customer_name} · ${tierLabel(r.tier)}`}
                  rows={[['Date', dateStr(r.purchase_date)], ['Description', 'Purchase'],
                         ['Amount', money(r.purchase_amount)], ['Your Earning', money(r.your_commission)]]} />
              ))}
          </MobileCards>
        </>
      )}
    </AffiliateLayout>
  );
};
export default AffiliateDashboardPage;
