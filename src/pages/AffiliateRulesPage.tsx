import React, { useEffect } from 'react';
import { Link } from 'react-router-dom';
import { CalendarCheck, Leaf, Printer, RotateCcw, Users, Wallet } from 'lucide-react';
import AffiliateLayout from '../components/AffiliateLayout';
import { PortalError } from '../components/AffiliateResponsive';
import { useAuth } from '../context/AuthContext';
import { usePortalRpc } from '../lib/affiliatePortal';
import { effectiveTier2, longDate, pct, rulesExamples, type Rates, type RulesInfo } from '../lib/affiliateRules';

// 490 (3 Nov 2026): the Rules and regulations page, which is also the
// "Energia Affiliate terms" the sign-up page asks people to agree to. It is
// public: a signed-in affiliate sees it inside the portal, anyone else in a
// plain page with Sign in and Join. The rates, the product lists and the
// machines are read live (affiliate_rules_info), and every example is worked
// out from the live rates, rounded as the commission itself is.
// 492 (the user, 3 Nov 2026): laid out as terms: a summary with the rates as
// large figures, then numbered clauses, an effective date, the worked
// examples as an appendix, and a Print button; worded in Energia's name
// ("Energia", "Energia's"), never "we", "our" or "us". The phone clause says
// what 492's My Network shows.

/** When these terms took effect (change it with the wording). */
const EFFECTIVE = '3 November 2026';

/** A clause: its number and title, then its numbered points (n.1, n.2, ...) and anything after them. */
const Clause: React.FC<{ n: number; id: string; title: string; points: React.ReactNode[]; children?: React.ReactNode }> = ({ n, id, title, points, children }) => (
  <section id={id} data-clause={n} className="terms-clause">
    <h2 className="terms-clause-title"><span className="terms-num">{n}.</span> {title}</h2>
    <ol className="terms-points">
      {points.map((p, i) => <li key={i}><span className="terms-num">{n}.{i + 1}</span><div>{p}</div></li>)}
    </ol>
    {children}
  </section>
);

const Names: React.FC<{ title: string; names: string[]; testId: string }> = ({ title, names, testId }) => (
  <details data-list={testId} className="terms-names">
    <summary>{title} ({names.length})</summary>
    {names.length === 0
      ? <p style={{ color: 'var(--text-muted)', margin: '8px 0 0' }}>None at the moment.</p>
      : <ul>{names.map(n => <li key={n}>{n}</li>)}</ul>}
  </details>
);

/** One worked example: a title, the sums, and who gets what. */
const Example: React.FC<{ id: string; title: string; lines: string[] }> = ({ id, title, lines }) => (
  <div data-example={id} className="card terms-example">
    <h3>{title}</h3>
    <ul>{lines.map((l, i) => <li key={i}>{l}</li>)}</ul>
  </div>
);

const TYPE_LABEL = { own: 'Energia\'s own rate', third_party: 'the third-party rate', no_commission: 'no commission' } as const;

/** One tier's two rates as large figures: Energia's own products, then third-party products. */
const TierRates: React.FC<{ tier: 1 | 2; title: string; own: number; third: number; ownNote: string; thirdNote: string }> = ({ tier, title, own, third, ownNote, thirdNote }) => (
  <div className={`terms-tier terms-tier-${tier}`} data-tier={tier}>
    <div className="terms-tier-title"><b>Tier {tier}</b> · {title}</div>
    <div className="terms-rates">
      <div><div className="terms-figure" data-rate={`tier${tier}_own`}>{pct(own)}</div><div className="terms-figure-label">Energia's own products</div><div className="terms-figure-note">{ownNote}</div></div>
      <div><div className="terms-figure" data-rate={`tier${tier}_third`}>{pct(third)}</div><div className="terms-figure-label">Third-party products</div><div className="terms-figure-note">{thirdNote}</div></div>
    </div>
  </div>
);

const FACTS = [
  { icon: Wallet, title: 'Paid monthly', text: 'Early the following month, by PayNow or bank transfer. No minimum.' },
  { icon: CalendarCheck, title: 'Earned when paid', text: 'On the day each payment is recorded.' },
  { icon: RotateCcw, title: 'Refunds reduce it', text: 'A refunded or cancelled purchase reduces or takes back its commission.' },
  { icon: Users, title: 'Two tiers only', text: 'Your referrals, and the people they refer.' },
];

const Glance: React.FC<{ r: Rates }> = ({ r }) => (
  <section id="summary" data-glance className="card terms-glance" aria-labelledby="summary-title">
    <h2 id="summary-title" className="terms-glance-title">At a glance</h2>
    <div className="terms-tiers">
      <TierRates tier={1} title="your referrals' purchases" own={r.tier1_own} third={r.tier1_third}
        ownNote="of the amount paid" thirdNote="of the amount paid" />
      <TierRates tier={2} title="purchases by the people your referrals refer" own={effectiveTier2(r.tier1_own, r.tier2_own)}
        third={effectiveTier2(r.tier1_third, r.tier2_third)}
        ownNote={`of the amount paid (${pct(r.tier2_own)} of the Tier 1 commission)`}
        thirdNote={`of the amount paid (${pct(r.tier2_third)} of the Tier 1 commission)`} />
    </div>
    <div className="terms-facts">
      {FACTS.map(({ icon: Icon, title, text }) => (
        <div key={title} className="terms-fact">
          <Icon size={18} color="var(--primary)" aria-hidden="true" />
          <div><b>{title}</b><div>{text}</div></div>
        </div>
      ))}
    </div>
    <p className="terms-small">This summary is for convenience. The terms below apply.</p>
  </section>
);

const CONTENTS: [string, string][] = [
  ['about', '1. About these terms'], ['definitions', '2. Definitions'], ['referrals', '3. Referrals'],
  ['earn', '4. Commission rates'], ['products', '5. Energia\'s own and third-party products'],
  ['kinds', '6. How each kind of purchase earns'], ['nothing', '7. What earns no commission'],
  ['when', '8. When commission is earned'], ['refunds', '9. Refunds and cancellations'],
  ['status', '10. Your affiliate account'], ['payouts', '11. Payouts'], ['details', '12. Your referrals\' details'],
  ['changes', '13. Changes to these terms'], ['examples', 'Appendix A. Worked examples'],
];

// The product lists sit in collapsed lists on screen; on paper every list is open, and closed again afterwards.
function useOpenListsForPrint() {
  useEffect(() => {
    let opened: HTMLDetailsElement[] = [];
    const before = () => {
      opened = [...document.querySelectorAll<HTMLDetailsElement>('.terms-doc details:not([open])')];
      opened.forEach(d => { d.open = true; });
    };
    const after = () => { opened.forEach(d => { d.open = false; }); opened = []; };
    window.addEventListener('beforeprint', before);
    window.addEventListener('afterprint', after);
    return () => { window.removeEventListener('beforeprint', before); window.removeEventListener('afterprint', after); };
  }, []);
}

const RulesContent: React.FC = () => {
  const { data, err, retry } = usePortalRpc<RulesInfo>('affiliate_rules_info');
  const r = data?.rates ?? null;
  const from = longDate(data?.machines_from);
  useOpenListsForPrint();
  return (
    <div className="terms-doc">
      <header className="terms-hero">
        <div className="terms-eyebrow">Energia Affiliate Programme</div>
        <h1>Rules and regulations</h1>
        <p className="terms-lead">The Energia Affiliate terms: how referrals and commission work.</p>
        <div className="terms-meta">
          <span>Effective <b data-effective>{EFFECTIVE}</b> · The rates and product lists on this page are always the ones in use.</span>
          <button type="button" className="btn btn-secondary terms-noprint" data-print onClick={() => window.print()} style={{ minHeight: 40 }}>
            <Printer size={16} aria-hidden="true" /> Print
          </button>
        </div>
      </header>
      {err ? <PortalError message={err} onRetry={retry} /> : !data ? <p style={{ color: 'var(--text-muted)' }}>Loading…</p> : !r
        ? <p role="alert" style={{ color: 'var(--danger)' }}>The commission rates could not be read. Please try again later.</p> : (
        <>
          <Glance r={r} />

          <nav aria-label="Contents" className="card terms-contents">
            <h2>Contents</h2>
            <ol>{CONTENTS.map(([id, label]) => <li key={id}><a href={`#${id}`}>{label}</a></li>)}</ol>
          </nav>

          <div className="card terms-body">
            <Clause n={1} id="about" title="About these terms" points={[
              'These terms are between you and Energia. They apply to every Energia affiliate account, and they are the Energia Affiliate terms you agree to when you join.',
              'If anything in them is unclear, please ask Energia staff at any Energia outlet.',
            ]} />

            <Clause n={2} id="definitions" title="Definitions" points={[
              <><b>You</b> and <b>affiliate</b> mean the holder of an Energia affiliate account.</>,
              <>A <b>referral</b> (Tier 1) is a customer whose referrer is you.</>,
              <>A <b>Tier 2 referral</b> is a customer whose referrer is one of your referrals.</>,
              <>The <b>amount paid</b> is what a customer pays for an item after any discount. The part paid with wallet credit is not included (clause 7).</>,
              <><b>Energia's own products</b> and <b>third-party products</b> are products as Energia sets them (clause 5).</>,
            ]} />

            <Clause n={3} id="referrals" title="Referrals" points={[
              'Share your referral link or QR code (My Referral QR in your portal). A new customer who signs up through it becomes your referral.',
              'Someone who is already an Energia customer keeps the referrer they already have.',
              'A customer\'s referrer does not change once it is set. Only an Owner or Manager at Energia can correct it.',
              'You cannot refer yourself. You earn nothing on your own purchases: the person who referred you earns on them, as on any customer\'s.',
              'When Energia staff name you as the affiliate on a sale, you earn Tier 1 on that sale.',
            ]} />

            <Clause n={4} id="earn" title="Commission rates" points={[
              <><b>Tier 1</b>: on purchases by your referrals.</>,
              <><b>Tier 2</b>: on purchases by your referrals' referrals. Tier 2 is a share of the Tier 1 commission on the same purchase.</>,
              'There are only these two tiers. The rates in use are:',
            ]}>
              <div className="terms-table">
                <table className="table" data-table="rates">
                  <thead><tr><th></th><th>Energia's own products</th><th>Third-party products</th></tr></thead>
                  <tbody>
                    <tr><th scope="row" style={{ whiteSpace: 'nowrap' }}>Tier 1</th><td>{pct(r.tier1_own)} of the amount paid</td><td>{pct(r.tier1_third)} of the amount paid</td></tr>
                    <tr><th scope="row" style={{ whiteSpace: 'nowrap' }}>Tier 2</th>
                      <td>{pct(r.tier2_own)} of the Tier 1 commission ({pct(effectiveTier2(r.tier1_own, r.tier2_own))} of the amount paid)</td>
                      <td>{pct(r.tier2_third)} of the Tier 1 commission ({pct(effectiveTier2(r.tier1_third, r.tier2_third))} of the amount paid)</td></tr>
                  </tbody>
                </table>
              </div>
            </Clause>

            <Clause n={5} id="products" title="Energia's own and third-party products" points={[
              'Each product is set as one of Energia\'s own products, a third-party product, or a product that earns no commission. That setting decides the rate, not the brand name on the product: some Energia-branded items are third-party.',
              'The products in each group today:',
            ]}>
              <div className="terms-lists">
                <Names title="Energia's own products" names={data.products.own} testId="own" />
                <Names title="Third-party products" names={data.products.third_party} testId="third_party" />
                <Names title="No commission" names={data.products.no_commission} testId="no_commission" />
              </div>
            </Clause>

            <Clause n={6} id="kinds" title="How each kind of purchase earns" points={[
              <><b>Products</b> earn the rate of their group (clause 5).</>,
              <><b>Promotions</b> are split between the items in them that are Energia's own and those that are third-party, in proportion to the items' normal prices, and each part earns its own rate. Vouchers in a promotion count as Energia's own. A blind box earns Energia's own rate on its price.</>,
              <><b>Machines bought or rented</b> earn like the machine itself: a third-party machine earns the third-party rate, and one of Energia's own machines earns Energia's own rate.{from ? ` This applies to sales from ${from}; earlier sales keep the rate they were made at.` : ''}</>,
              <><b>Premium Bundles and Credit Packages</b> earn the third-party rate, once, on the money paid for them. Bonus credit and free vouchers earn nothing, and spending the credit later earns nothing more.</>,
              <><b>Therapy packages and sessions</b> earn Energia's own rate on the amount paid. Using the sessions later earns nothing more.</>,
              <><b>Vouchers</b> bought (for example a MEOL voucher) earn Energia's own rate on the price paid. Using a voucher later earns nothing more.</>,
              <><b>Event tickets and seminar VIP upgrades</b> earn Energia's own rate on the price paid. A free seminar registration earns nothing.</>,
              <><b>Discounts</b> lower the amount commission is worked out on. A discount Energia staff give on the whole invoice is shared across all its items; a discount voucher on the invoice comes off Energia's own products only.</>,
            ]}>
              {data.machines.length > 0 && (
                <div className="terms-lists">
                  <details data-list="machines" className="terms-names">
                    <summary>Machines and what they earn ({data.machines.length})</summary>
                    <ul>{data.machines.map(m => <li key={m.name}>{m.name}: {TYPE_LABEL[m.earns] ?? TYPE_LABEL.own}</li>)}</ul>
                  </details>
                </div>
              )}
            </Clause>

            <Clause n={7} id="nothing" title="What earns no commission" points={[
              `Items that earn no commission${data.products.no_commission.length > 0 ? `: ${data.products.no_commission.join(', ')}` : ''}.`,
              'A rental\'s late fee.',
              'Anything given free (FOC).',
              'The part of a purchase paid with wallet credit (from a Credit Package, a Premium Bundle, a refund or an exchange).',
              'Your own purchases.',
              'Orders on Energia\'s TikTok Shop.',
            ]} />

            <Clause n={8} id="when" title="When commission is earned" points={[
              'When a purchase is paid in full, its commission is earned on the day the last payment is recorded.',
              'When a customer pays in parts, each payment earns its share on the day it is recorded, and the rest is earned when it is paid in full.',
              'Commission counts towards the month it is earned in.',
            ]} />

            <Clause n={9} id="refunds" title="Refunds and cancellations" points={[
              'If a purchase is refunded, in part or in full, or cancelled, its commission is reduced or taken back.',
              'If that commission was already paid to you, the difference comes off your next commission. Your Dashboard shows it as "Deduction to be recovered".',
            ]} />

            <Clause n={10} id="status" title="Your affiliate account" points={[
              'Commission is paid to active affiliates.',
              'If your affiliate account is suspended, commission on purchases made while it is suspended is normally shown as Blocked and is not paid, also after the account is active again. Commission you earned before the suspension is still paid.',
            ]} />

            <Clause n={11} id="payouts" title="Payouts" points={[
              'Each month\'s commission is paid early the following month by PayNow or bank transfer. There is no minimum.',
              'PayNow payouts are sent to the mobile number on your account, so keep it up to date.',
              'Your Payouts page lists every payout made to you.',
            ]} />

            <Clause n={12} id="details" title="Your referrals' details" points={[
              'Your portal shows your referrals\' names, their bookings and visits, and what they spend, so you can see what you earn.',
              'It shows the phone numbers of your direct referrals (Tier 1), unless a referral has asked Energia to hide theirs, and never the phone number of a Tier 2 referral. No numbers are shown while your affiliate account is suspended, or until Energia has confirmed that your portal login belongs to your customer record.',
              'Use a referral\'s phone number only to help them with their visit to Energia, and never share it.',
            ]} />

            <Clause n={13} id="changes" title="Changes to these terms" points={[
              'Energia may change these terms, including the rates. This page always shows the current version, and the rates on it are the ones in use.',
            ]} />
          </div>

          <section id="examples" className="terms-appendix" aria-labelledby="examples-title">
            <h2 id="examples-title"><span className="terms-num">Appendix A.</span> Worked examples</h2>
            <p>You referred Ann, and Ann referred Ben. With today's rates:</p>
            <div className="terms-examples">
              {rulesExamples(r).map(e => <Example key={e.id} {...e} />)}
            </div>
            <p className="terms-small">
              Each amount is rounded to the cent, and Tier 2 is worked out from the rounded Tier 1, as your Earnings page shows them.
              These examples explain the terms above; where they differ, the terms apply.
            </p>
          </section>

          <footer className="terms-footer">
            <span>Energia Affiliate terms · Effective {EFFECTIVE}</span>
            <span>Questions? Please ask Energia staff at any Energia outlet.</span>
          </footer>
        </>
      )}
    </div>
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
