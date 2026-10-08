import React, { useEffect, useState } from 'react';
import AffiliateLayout from '../components/AffiliateLayout';
import { portalRpc, money, dateStr } from '../lib/affiliatePortal';
import { DesktopTableCard, MobileCards, MCard, EmptyNote } from '../components/AffiliateResponsive';
import { progressLine, portalNotYetVisitedLine, windowLabel, sgDayOf } from '../lib/referral/campaign.mjs';
import type { PortalProgress } from '../lib/referral/campaign.mjs';

/** 398: the signed-in affiliate's own progress in the referral promotion
 *  (affiliate_portal_campaign_progress): their friends counted and the next
 *  tier. Counts only; their Tier 1 list is below. 404: a friend counts by
 *  their first visit to the centre, past customers never (the Owner, 8 Oct
 *  2026); while the promotion runs, how many friends they referred during
 *  it have not visited yet (a count, no names; hidden at 0 and after it ends). */
const PromotionCard: React.FC<{ p: PortalProgress }> = ({ p }) => {
  if (!p.campaign) return null;
  const c = p.campaign;
  const ended = c.status === 'final';
  const reached = new Set((c.tiers ?? []).filter(t => p.tier_reached != null && t <= p.tier_reached));
  const waiting = portalNotYetVisitedLine(p);
  return (
    <div className="card portal-break" data-promotion={c.code} style={{ padding: 16, marginBottom: 20 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8, alignItems: 'baseline' }}>
        <h3 style={{ fontSize: 15, fontWeight: 700 }}>{c.title}</h3>
        <span style={{ fontSize: 12.5, color: 'var(--text-muted)' }}>{windowLabel(c.starts_on, c.ends_on)}{ended ? ' · ended' : ' · so far'}</span>
      </div>
      <div style={{ fontSize: 15, fontWeight: 600, marginTop: 8 }}>{progressLine(p)}</div>
      {waiting && <div data-not-yet-visited style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: 4 }}>{waiting}</div>}
      <div style={{ display: 'flex', gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
        {(c.tiers ?? []).map(t => (
          <span key={t} className={`badge ${reached.has(t) ? 'badge-success' : 'badge-muted'}`}>{t} friends</span>
        ))}
      </div>
      <p style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: 10 }}>
        A friend counts when their first visit to the centre is during the promotion, whenever you referred them, as long as you referred them by its last day.
        {' '}Friends who were already paying customers before it started do not count.
        {ended
          ? (p.reward_given_at ? ` Your tier ${p.reward_tier} reward was given on ${sgDayOf(p.reward_given_at)}.` : ' Rewards are given now that it has ended, for the highest tier reached.')
          : ' Rewards are given after it ends, for the highest tier you reach.'}
      </p>
    </div>
  );
};

const NetTable: React.FC<{ rows: any[]; showParent?: boolean }> = ({ rows, showParent }) => (
  <>
    <DesktopTableCard>
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
    </DesktopTableCard>
    <MobileCards>
      {rows.length === 0
        ? <EmptyNote>No members yet</EmptyNote>
        : rows.map((r, i) => (
          <MCard key={i} title={r.customer_name}
            rows={[
              ...(showParent ? [['Referred By', r.parent_name] as [React.ReactNode, React.ReactNode]] : []),
              ['Joined', dateStr(r.referral_date || r.joined_at)],
              ['Purchases', String(r.purchases)],
              ['Total Spent', money(r.total_spent)],
              ['Your Commission', money(r.your_commission)],
            ]} />
        ))}
    </MobileCards>
  </>
);

const AffiliateNetworkPage: React.FC = () => {
  const [n, setN] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);
  // 398. Optional: before the database has it, the page is as it was.
  const [promo, setPromo] = useState<PortalProgress | null>(null);
  useEffect(() => { portalRpc('affiliate_portal_network').then(setN).catch(e => setErr(e.message)); }, []);
  useEffect(() => { portalRpc<PortalProgress>('affiliate_portal_campaign_progress').then(setPromo).catch(() => setPromo(null)); }, []);

  return (
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>My Network</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 20 }}>Your direct referrals and their referrals — the two levels you earn from.</p>
      {err && <p className="portal-break" style={{ color: 'var(--danger)' }}>{err}</p>}
      {promo?.campaign && <PromotionCard p={promo} />}
      {!n ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : (
        <>
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>Tier 1 — Direct Referrals ({(n.tier1 ?? []).length})</h3>
          <div style={{ marginBottom: 20 }}><NetTable rows={n.tier1 ?? []} /></div>
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>Tier 2 — Their Referrals ({(n.tier2 ?? []).length})</h3>
          <NetTable rows={n.tier2 ?? []} showParent />
        </>
      )}
    </AffiliateLayout>
  );
};
export default AffiliateNetworkPage;
