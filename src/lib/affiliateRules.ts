// 490 (3 Nov 2026): what the Rules and regulations page reads, and the
// worked examples it shows, calculated as the database calculates commission
// (earn_invoice_commission): each amount rounded to the cent, half away from
// zero, per line and per tier, and Tier 2 from the already-rounded Tier 1.
// Amounts are whole cents and rates are read as thousandths of a percent, so
// no floating-point error reaches a figure.

export type CommissionType = 'own' | 'third_party' | 'no_commission';

/** affiliate_rules_info()'s answer. */
export interface RulesInfo {
  rates: { tier1_own: number; tier1_third: number; tier2_own: number; tier2_third: number } | null;
  machines_from: string | null;
  products: { own: string[]; third_party: string[]; no_commission: string[] };
  machines: { name: string; earns: CommissionType }[];
}

/** n / d rounded to a whole number, half away from zero (n and d integers). */
export function divRound(n: number, d: number): number {
  const sign = (n < 0) !== (d < 0) ? -1 : 1;
  const an = Math.abs(n), ad = Math.abs(d);
  let q = Math.floor(an / ad);
  // The remainder is exact for whole numbers this size; it corrects a
  // quotient that floating point put one off.
  let r = an - q * ad;
  if (r < 0) { q -= 1; r += ad; } else if (r >= ad) { q += 1; r -= ad; }
  if (r * 2 >= ad) q += 1;
  return sign * q;
}

const milli = (rate: number) => Math.round(rate * 1000);

/** rate% of an amount in cents, in cents. */
export function percentOf(cents: number, rate: number): number {
  return divRound(cents * milli(rate), 100000);
}

/** cents × part / whole, in cents. */
export function share(cents: number, part: number, whole: number): number {
  return whole === 0 ? 0 : divRound(cents * part, whole);
}

export type Rates = NonNullable<RulesInfo['rates']>;

/** What a line of this value earns at Tier 1 and Tier 2. */
export function earns(cents: number, type: 'own' | 'third_party', rates: Rates): { tier1: number; tier2: number } {
  const tier1 = percentOf(cents, type === 'own' ? rates.tier1_own : rates.tier1_third);
  const tier2 = percentOf(tier1, type === 'own' ? rates.tier2_own : rates.tier2_third);
  return { tier1, tier2 };
}

/** S$1,234.50 */
export function sgd(cents: number): string {
  const neg = cents < 0;
  const abs = Math.abs(cents);
  const dollars = Math.trunc(abs / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `${neg ? '−' : ''}S$${dollars}.${String(abs % 100).padStart(2, '0')}`;
}

/** 15%, 4.5%, 1.575% (no trailing zeros). */
export function pct(rate: number): string {
  return `${Number(rate.toFixed(4))}%`;
}

/** What Tier 2 comes to as a share of the sale itself. */
export function effectiveTier2(tier1Rate: number, tier2Rate: number): number {
  return Number(((tier1Rate * tier2Rate) / 100).toFixed(4));
}

/** "3 November 2026" from "2026-11-03". */
export function longDate(iso: string | null | undefined): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso ?? '');
  if (!m) return null;
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return `${Number(m[3])} ${months[Number(m[2]) - 1]} ${m[1]}`;
}

/** The examples, from the live rates. */
export function rulesExamples(r: Rates): { id: string; title: string; lines: string[] }[] {
  const t1o = pct(r.tier1_own), t1t = pct(r.tier1_third), t2o = pct(r.tier2_own), t2t = pct(r.tier2_third);
  const corset = earns(46800, 'own', r);
  const machine = earns(288600, 'third_party', r);
  const promoOwn = earns(share(30000, 20000, 30000), 'own', r);
  const promoThird = earns(share(30000, 10000, 30000), 'third_party', r);
  const bundle = earns(1500000, 'third_party', r);
  const pkg = earns(100000, 'third_party', r);
  const therapy = earns(19900, 'own', r);
  const parts = earns(100000, 'own', r);
  const october = share(parts.tier1, 40000, 100000);
  const refunded = share(corset.tier1, 46800 - 20000, 46800);
  const ownBuy = earns(10000, 'own', r);
  return [
    { id: 'tier1', title: 'Ann, whom you referred, buys one of our own products for S$468',
      lines: [`You earn Tier 1: ${t1o} of S$468.00 = ${sgd(corset.tier1)}.`,
              `The person who referred you earns Tier 2: ${t2o} of ${sgd(corset.tier1)} = ${sgd(corset.tier2)}.`] },
    { id: 'tier2', title: 'Ben, whom Ann referred, buys the same product',
      lines: [`Ann earns Tier 1: ${sgd(corset.tier1)}.`, `You earn Tier 2: ${sgd(corset.tier2)}.`] },
    { id: 'third', title: 'Ann buys a third-party machine for S$2,886',
      lines: [`You earn Tier 1: ${t1t} of S$2,886.00 = ${sgd(machine.tier1)}.`,
              `Tier 2: ${t2t} of ${sgd(machine.tier1)} = ${sgd(machine.tier2)}.`] },
    { id: 'promotion', title: 'Ann buys a S$300 promotion whose items normally cost S$200 (ours) and S$100 (third-party)',
      lines: [`S$200.00 of it earns ${t1o}: ${sgd(promoOwn.tier1)}. S$100.00 earns ${t1t}: ${sgd(promoThird.tier1)}.`,
              `You earn Tier 1: ${sgd(promoOwn.tier1 + promoThird.tier1)}. Tier 2: ${sgd(promoOwn.tier2 + promoThird.tier2)}.`] },
    { id: 'bundle', title: 'Ann buys a S$15,000 Premium Bundle',
      lines: [`You earn Tier 1: ${t1t} of S$15,000.00 = ${sgd(bundle.tier1)}, once. Tier 2: ${sgd(bundle.tier2)}.`,
              'When Ann later spends the bundle\'s credit, nothing more is earned.'] },
    { id: 'package', title: 'Ann buys a S$1,000 Credit Package',
      lines: [`You earn Tier 1: ${sgd(pkg.tier1)}. Tier 2: ${sgd(pkg.tier2)}. Spending the credit later earns nothing more.`] },
    { id: 'therapy', title: 'Ann pays S$199 for a therapy session',
      lines: [`You earn Tier 1: ${t1o} of S$199.00 = ${sgd(therapy.tier1)}. Tier 2: ${sgd(therapy.tier2)}.`] },
    { id: 'parts', title: 'Ann pays S$1,000 for one of our products in two parts: S$400 in October and S$600 in November',
      lines: [`October: ${sgd(october)} (her S$400.00 share of the ${sgd(parts.tier1)}).`,
              `November: ${sgd(parts.tier1 - october)}, the rest, when it is paid in full.`] },
    { id: 'refund', title: 'Ann returns part of her S$468 purchase and is refunded S$200',
      lines: [`Your Tier 1 becomes ${sgd(refunded)} instead of ${sgd(corset.tier1)}.`,
              `If ${sgd(corset.tier1)} was already paid to you, ${sgd(corset.tier1 - refunded)} comes off your next commission.`] },
    { id: 'own-purchase', title: 'You buy one of our own products for S$100 yourself',
      lines: ['You earn nothing on your own purchase.',
              `The person who referred you earns Tier 1: ${sgd(ownBuy.tier1)}; their referrer earns Tier 2: ${sgd(ownBuy.tier2)}.`] },
  ];
}
