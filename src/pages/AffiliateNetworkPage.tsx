import React, { useEffect, useState } from 'react';
import AffiliateLayout from '../components/AffiliateLayout';
import { portalRpc, usePortalRpc, money, dateStr } from '../lib/affiliatePortal';
import { DesktopTableCard, MobileCards, MCard, EmptyNote, PortalError } from '../components/AffiliateResponsive';
import { progressLine, portalNotYetVisitedLine, windowLabel, sgDayOf } from '../lib/referral/campaign.mjs';
import type { PortalProgress } from '../lib/referral/campaign.mjs';
import BookingCell from '../components/referrals/BookingCell';

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

/** 484 (the Owner, 31 Oct 2026): a direct referral's phone number as the database sends it (affiliate_portal_network's
 *  'phone' on Tier 1 rows), or null when the row has none to show: null, blank, not text, or no 'phone' at all. */
const phoneOf = (row: any): string | null => (typeof row?.phone === 'string' && row.phone.trim() !== '' ? row.phone : null);

/** 484: the number in the font of the staff Downline's phone cell and kept whole; a grey "—" when the row has none. */
const PhoneCell: React.FC<{ row: any }> = ({ row }) => {
  const phone = phoneOf(row);
  return phone
    ? <span data-phone="number" style={{ fontFamily: 'var(--font-display)', whiteSpace: 'nowrap' }}>{phone}</span>
    : <span data-phone="none" style={{ color: 'var(--text-muted)' }}>—</span>;
};

// 480 (the Owner, 29 Oct 2026): each member's cal.com booking (Booking), from
// affiliate_portal_network's booking_at and booking_state: the start and the
// state only. With the extra column a word or a date in the table no longer
// breaks in the middle (the portal's cards break anywhere, for phones), so
// the table needs the content column's full width: below 1200 px
// (.portal-network in globals.css) this page shows its cards instead, and
// Your Commission is never left behind a sideways scroll (phones held
// sideways, tablets). 482 (the Owner, 30 and 31 Oct 2026): "Came in" (grey,
// no date) for a member with no booking who has come to the centre.
// 484 (the Owner, 31 Oct 2026): Tier 1 (the affiliate's direct referrals) has
// a Phone column right after Booking, and a Phone line right after Booking on
// each card (showPhone), once the database sends a Tier 1 number; until then
// both are as before. Tier 2 has neither (the database sends no Tier 2 number
// at all).
const NetTable: React.FC<{ rows: any[]; showParent?: boolean; showPhone?: boolean }> = ({ rows, showParent, showPhone }) => (
  <>
    <DesktopTableCard>
      <table className="table" style={{ width: '100%', overflowWrap: 'normal' }}>
        <thead><tr>
          <th>Customer</th>{showParent && <th>Referred By</th>}<th>Joined</th><th>Booking</th>{showPhone && <th>Phone</th>}
          <th style={{ textAlign: 'right' }}>Purchases</th><th style={{ textAlign: 'right' }}>Total Spent</th><th style={{ textAlign: 'right' }}>Your Commission</th>
        </tr></thead>
        <tbody>
          {rows.length === 0 && <tr><td colSpan={6 + (showParent ? 1 : 0) + (showPhone ? 1 : 0)} style={{ color: 'var(--text-muted)', textAlign: 'center', padding: 18 }}>No members yet</td></tr>}
          {rows.map((r, i) => (
            <tr key={i}>
              <td>{r.customer_name}</td>{showParent && <td>{r.parent_name}</td>}
              <td>{dateStr(r.referral_date || r.joined_at)}</td>
              <td><BookingCell row={r} /></td>
              {showPhone && <td><PhoneCell row={r} /></td>}
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
              ['Booking', <BookingCell row={r} />],
              ...(showPhone ? [['Phone', <PhoneCell row={r} />] as [React.ReactNode, React.ReactNode]] : []),
              ['Purchases', String(r.purchases)],
              ['Total Spent', money(r.total_spent)],
              ['Your Commission', money(r.your_commission)],
            ]} />
        ))}
    </MobileCards>
  </>
);

const AffiliateNetworkPage: React.FC = () => {
  const { data: n, err, retry } = usePortalRpc<any>('affiliate_portal_network');
  // 398. Optional: before the database has it, the page is as it was.
  const [promo, setPromo] = useState<PortalProgress | null>(null);
  useEffect(() => { portalRpc<PortalProgress>('affiliate_portal_campaign_progress').then(setPromo).catch(() => setPromo(null)); }, []);
  // 484 (the Owner, 31 Oct 2026): Tier 1's Phone column and card line, and the note's sentence about them, only once
  // the database sends at least one Tier 1 number; until then the page is as it was.
  const showPhone = (n?.tier1 ?? []).some((r: any) => phoneOf(r) !== null);

  return (
    <AffiliateLayout>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>My Network</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 20 }}>Your direct referrals and their referrals — the two levels you earn from.</p>
      <p data-booking-note style={{ color: 'var(--text-muted)', fontSize: 12.5, marginTop: -12, marginBottom: 20 }}>
        Booking is each person&apos;s next appointment at the centre, or their last one; Miss means no visit and no purchase at the centre were recorded that day.
        {' '}Came in means they have come to the centre without a booking.
        {showPhone && ' A phone number shows only for a direct referral who registered through your link after being told you would see it. Use it only to help them with their visit.'}
      </p>
      {promo?.campaign && <PromotionCard p={promo} />}
      {err ? <PortalError message={err} onRetry={retry} /> : !n ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : (
        <div className="portal-network">
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>Tier 1 — Direct Referrals ({(n.tier1 ?? []).length})</h3>
          <div style={{ marginBottom: 20 }}><NetTable rows={n.tier1 ?? []} showPhone={showPhone} /></div>
          <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 10 }}>Tier 2 — Their Referrals ({(n.tier2 ?? []).length})</h3>
          <NetTable rows={n.tier2 ?? []} showParent />
        </div>
      )}
    </AffiliateLayout>
  );
};
export default AffiliateNetworkPage;
