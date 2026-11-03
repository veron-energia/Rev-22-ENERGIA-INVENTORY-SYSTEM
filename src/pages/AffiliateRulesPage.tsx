import React from 'react';
import { Link } from 'react-router-dom';
import { Leaf } from 'lucide-react';
import AffiliateLayout from '../components/AffiliateLayout';
import { PortalError } from '../components/AffiliateResponsive';
import { useAuth } from '../context/AuthContext';
import { usePortalRpc } from '../lib/affiliatePortal';
import { effectiveTier2, longDate, pct, rulesExamples, type RulesInfo } from '../lib/affiliateRules';

// 490 (3 Nov 2026): the Rules and regulations page, which is also the
// "Energia Affiliate terms" the sign-up page asks people to agree to. It is
// public: a signed-in affiliate sees it inside the portal, anyone else in a
// plain page with Sign in and Join. The rates, the product lists and the
// machines are read live (affiliate_rules_info), and every example is worked
// out from the live rates, rounded as the commission itself is.

/** When these rules were last changed (change it with the wording). */
const UPDATED = '3 November 2026';

const H2: React.FC<{ id: string; children: React.ReactNode }> = ({ id, children }) => (
  <h2 id={id} style={{ fontSize: 17, fontWeight: 700, margin: '0 0 10px', scrollMarginTop: 80 }}>{children}</h2>
);

const Part: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div className="card portal-break" style={{ padding: 18, marginBottom: 16, lineHeight: 1.6, fontSize: 14 }}>{children}</div>
);

const List: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <ul style={{ margin: '0 0 0 18px', padding: 0, display: 'grid', gap: 6 }}>{children}</ul>
);

const Names: React.FC<{ title: string; names: string[]; testId: string }> = ({ title, names, testId }) => (
  <details data-list={testId} style={{ marginTop: 10 }}>
    <summary style={{ cursor: 'pointer', fontWeight: 600, minHeight: 32 }}>{title} ({names.length})</summary>
    {names.length === 0
      ? <p style={{ color: 'var(--text-muted)', margin: '8px 0 0' }}>None at the moment.</p>
      : <ul style={{ columns: '2 220px', margin: '8px 0 0 18px', padding: 0 }}>{names.map(n => <li key={n} style={{ breakInside: 'avoid' }}>{n}</li>)}</ul>}
  </details>
);

/** One worked example: a title, the sums, and who gets what. */
const Example: React.FC<{ id: string; title: string; lines: string[] }> = ({ id, title, lines }) => (
  <div data-example={id} className="card portal-break" style={{ padding: 14, background: 'var(--surface)' }}>
    <h3 style={{ fontSize: 14.5, fontWeight: 700, marginBottom: 6 }}>{title}</h3>
    <ul style={{ margin: '0 0 0 18px', padding: 0, display: 'grid', gap: 4, fontSize: 13.5, color: 'var(--text-secondary)' }}>
      {lines.map((l, i) => <li key={i}>{l}</li>)}
    </ul>
  </div>
);

const TYPE_LABEL = { own: 'our own rate', third_party: 'the third-party rate', no_commission: 'no commission' } as const;

const RulesContent: React.FC = () => {
  const { data, err, retry } = usePortalRpc<RulesInfo>('affiliate_rules_info');
  const r = data?.rates ?? null;
  const from = longDate(data?.machines_from);
  return (
    <>
      <h1 style={{ fontSize: 22, fontWeight: 700, marginBottom: 4 }}>Rules and regulations</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 13.5, marginBottom: 6 }}>
        The Energia Affiliate terms: how referrals and commission work.
      </p>
      <p style={{ color: 'var(--text-muted)', fontSize: 12.5, marginBottom: 18 }}>
        Last updated {UPDATED}. The rates and product lists here are always the ones in use.
      </p>
      {err ? <PortalError message={err} onRetry={retry} /> : !data ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : !r
        ? <p role="alert" style={{ color: 'var(--danger)' }}>The commission rates could not be read. Please try again later.</p> : (
        <>
          <nav aria-label="On this page" className="card" style={{ padding: 14, marginBottom: 16, fontSize: 13.5 }}>
            <b>On this page</b>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px 14px', marginTop: 6 }}>
              {[['referrals', 'Referrals'], ['earn', 'What you earn'], ['products', 'Own and third-party'], ['kinds', 'Each kind of purchase'],
                ['nothing', 'What earns nothing'], ['examples', 'Examples'], ['when', 'When it is earned'], ['refunds', 'Refunds'],
                ['status', 'Your account'], ['payouts', 'Payouts'], ['details', 'Referrals\' details'], ['changes', 'Changes']]
                .map(([id, label]) => <a key={id} href={`#${id}`} style={{ minHeight: 28, display: 'inline-flex', alignItems: 'center' }}>{label}</a>)}
            </div>
          </nav>

          <Part>
            <H2 id="referrals">How referrals work</H2>
            <List>
              <li>Share your referral link or QR code (My Referral QR in your portal). A new customer who signs up through it becomes your referral.</li>
              <li>Someone who is already an Energia customer keeps the referrer they already have.</li>
              <li>A customer's referrer does not change once it is set. Only an Owner or Manager at Energia can correct it.</li>
              <li>You cannot refer yourself. You earn nothing on your own purchases: the person who referred you earns on them, as on any customer's.</li>
              <li>When our staff name you as the affiliate on a sale, you earn Tier 1 on that sale.</li>
            </List>
          </Part>

          <Part>
            <H2 id="earn">What you earn</H2>
            <List>
              <li><b>Tier 1</b>: on purchases by the people you referred.</li>
              <li><b>Tier 2</b>: on purchases by the people your referrals referred. Tier 2 is a share of the Tier 1 commission on the same purchase.</li>
              <li>There are only these two tiers.</li>
            </List>
            <div style={{ overflowX: 'auto', marginTop: 12 }}>
              <table className="table" data-table="rates" style={{ width: '100%', fontSize: 13.5 }}>
                <thead><tr><th></th><th>Our own products</th><th>Third-party products</th></tr></thead>
                <tbody>
                  <tr><th scope="row" style={{ whiteSpace: 'nowrap' }}>Tier 1</th><td>{pct(r.tier1_own)} of the amount paid</td><td>{pct(r.tier1_third)} of the amount paid</td></tr>
                  <tr><th scope="row" style={{ whiteSpace: 'nowrap' }}>Tier 2</th>
                    <td>{pct(r.tier2_own)} of the Tier 1 commission ({pct(effectiveTier2(r.tier1_own, r.tier2_own))} of the amount paid)</td>
                    <td>{pct(r.tier2_third)} of the Tier 1 commission ({pct(effectiveTier2(r.tier1_third, r.tier2_third))} of the amount paid)</td></tr>
                </tbody>
              </table>
            </div>
          </Part>

          <Part>
            <H2 id="products">Own and third-party products</H2>
            <p>
              Each product is set as one of our own products, a third-party product, or a product that earns no commission.
              That setting decides the rate, not the brand name on the product: some Energia-branded items are third-party.
            </p>
            <Names title="Our own products" names={data.products.own} testId="own" />
            <Names title="Third-party products" names={data.products.third_party} testId="third_party" />
            <Names title="No commission" names={data.products.no_commission} testId="no_commission" />
          </Part>

          <Part>
            <H2 id="kinds">How each kind of purchase earns</H2>
            <List>
              <li><b>Products</b> earn the rate of their type, above.</li>
              <li><b>Promotions</b> are split between their own and third-party items, in proportion to the items' normal prices, and each part earns its own rate. Vouchers in a promotion count as ours. A blind box earns our own rate on its price.</li>
              <li><b>Machines bought or rented</b> earn like the machine itself: a third-party machine earns the third-party rate, one of ours our own rate.{from ? ` This applies to sales from ${from}; earlier sales keep the rate they were made at.` : ''}</li>
              <li><b>Premium Bundles and Credit Packages</b> earn the third-party rate, once, on the money paid for them. Bonus credit and free vouchers earn nothing, and spending the credit later earns nothing more.</li>
              <li><b>Therapy packages and sessions</b> earn our own rate on the amount paid. Using the sessions later earns nothing more.</li>
              <li><b>Vouchers</b> bought (for example a MEOL voucher) earn our own rate on the price paid. Using a voucher later earns nothing more.</li>
              <li><b>Event tickets and seminar VIP upgrades</b> earn our own rate on the price paid. A free seminar registration earns nothing.</li>
              <li><b>Discounts</b> lower the amount commission is worked out on. A discount our staff give on the whole invoice is shared across all its items; a discount voucher on the invoice comes off our own products only.</li>
            </List>
            {data.machines.length > 0 && (
              <details data-list="machines" style={{ marginTop: 10 }}>
                <summary style={{ cursor: 'pointer', fontWeight: 600, minHeight: 32 }}>Machines and what they earn ({data.machines.length})</summary>
                <ul style={{ margin: '8px 0 0 18px', padding: 0 }}>
                  {data.machines.map(m => <li key={m.name}>{m.name}: {TYPE_LABEL[m.earns] ?? TYPE_LABEL.own}</li>)}
                </ul>
              </details>
            )}
          </Part>

          <Part>
            <H2 id="nothing">What earns nothing</H2>
            <List>
              <li>Items that earn no commission{data.products.no_commission.length > 0 ? `: ${data.products.no_commission.join(', ')}` : ''}.</li>
              <li>A rental's late fee.</li>
              <li>Anything given free (FOC).</li>
              <li>The part of a purchase paid with wallet credit (from a Credit Package, a Premium Bundle, a refund or an exchange).</li>
              <li>Your own purchases.</li>
              <li>Orders on Energia's TikTok Shop.</li>
            </List>
          </Part>

          <Part>
            <H2 id="examples">Examples</H2>
            <p style={{ marginBottom: 12 }}>You referred Ann, and Ann referred Ben. With today's rates:</p>
            <div style={{ display: 'grid', gap: 10 }}>
              {rulesExamples(r).map(e => <Example key={e.id} {...e} />)}
            </div>
            <p style={{ fontSize: 12.5, color: 'var(--text-muted)', marginTop: 10 }}>
              Each amount is rounded to the cent, and Tier 2 is worked out from the rounded Tier 1, as your Earnings page shows them.
            </p>
          </Part>

          <Part>
            <H2 id="when">When commission is earned</H2>
            <List>
              <li>When a purchase is paid in full, its commission is earned on the day the last payment is recorded.</li>
              <li>When a customer pays in parts, each payment earns its share on the day it is recorded, and the rest is earned when it is paid in full.</li>
              <li>Commission counts towards the month it is earned in.</li>
            </List>
          </Part>

          <Part>
            <H2 id="refunds">Refunds and cancellations</H2>
            <List>
              <li>If a purchase is refunded, in part or in full, or cancelled, its commission is reduced or taken back.</li>
              <li>If that commission was already paid to you, the difference comes off your next commission. Your Dashboard shows it as "Deduction to be recovered".</li>
            </List>
          </Part>

          <Part>
            <H2 id="status">Your affiliate account</H2>
            <List>
              <li>Commission is paid to active affiliates.</li>
              <li>If your affiliate account is suspended, commission on purchases made while it is suspended is normally shown as Blocked and is not paid, also after the account is active again. Commission you earned before the suspension is still paid.</li>
            </List>
          </Part>

          <Part>
            <H2 id="payouts">Payouts</H2>
            <List>
              <li>Each month's commission is paid early the following month by PayNow or bank transfer. There is no minimum.</li>
              <li>PayNow payouts are sent to the mobile number on your account, so keep it up to date.</li>
              <li>Your Payouts page lists every payout made to you.</li>
            </List>
          </Part>

          <Part>
            <H2 id="details">Your referrals' details</H2>
            <List>
              <li>Your portal shows your referrals' names and what they spend, so you can see what you earn.</li>
              <li>It shows a direct referral's phone number only if they were told, when they signed up through your link, that you would see it. Use it only to help them with their visit, and never share it.</li>
            </List>
          </Part>

          <Part>
            <H2 id="changes">Changes to these rules</H2>
            <p>Energia may change these rules, including the rates. This page always shows the current version, and the rates on it are the ones in use. If anything here is unclear, please ask our staff.</p>
          </Part>
        </>
      )}
    </>
  );
};

// The plain page for someone not signed in to the portal.
const PublicShell: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <div style={{ minHeight: '100vh', background: 'var(--bg)' }}>
    <div className="portal-mobile-bar" style={{ position: 'sticky', top: 0, zIndex: 30 }}>
      <Link to="/affiliate/login" className="portal-brand" style={{ textDecoration: 'none', color: 'inherit' }}>
        <span style={{ width: 30, height: 30, borderRadius: 8, background: 'var(--primary)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flex: '0 0 auto' }}>
          <Leaf size={17} color="#fff" />
        </span>
        <span>Energia Affiliate</span>
      </Link>
      <div style={{ display: 'flex', gap: 8 }}>
        <Link to="/affiliate/login" className="btn btn-secondary" style={{ minHeight: 40 }}>Sign in</Link>
        <Link to="/affiliate/join" className="btn btn-primary" style={{ minHeight: 40 }}>Join</Link>
      </div>
    </div>
    <main className="portal-main"><div className="portal-content">{children}</div></main>
  </div>
);

const AffiliateRulesPage: React.FC = () => {
  const { session, actorType, loading } = useAuth();
  if (loading) return null;
  return session && actorType === 'affiliate'
    ? <AffiliateLayout><RulesContent /></AffiliateLayout>
    : <PublicShell><RulesContent /></PublicShell>;
};

export default AffiliateRulesPage;
