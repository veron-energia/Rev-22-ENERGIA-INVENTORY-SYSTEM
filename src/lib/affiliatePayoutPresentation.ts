/** One affiliate's month as affiliate_payout_overview sends it. 410 adds
 *  `payable` (what may be paid for this month now, once the affiliate's other
 *  months are netted in) and the affiliate's own figures on every month. They
 *  are optional so this page still works against a database without 410. */
export type Balance = {
  referrer: string; month: string | null; earned: number; adjustments: number; paid: number; balance: number; review_reason: string | null;
  payable?: number; referrer_owed?: number; referrer_payable?: number; referrer_deduction?: number;
};
/** An affiliate's months netted (410's affiliate_referrer_balances). */
export type ReferrerBalance = { referrer: string; owed: number; unpaid: number; deduction: number; payable: number };
export type Payout = { id: string; referrer_customer_id: string; payout_month: string; total_amount: number; total_tier1: number; total_tier2: number; payment_date: string; payment_method_id: string | null; payment_method_name: string | null; reference: string | null; notes: string | null; status: string; version: number; allocation_state: string; allocation_review_reason: string | null };
export const payoutMoney = (value: number | string) => `S$${Number(value).toFixed(2)}`;
export const unavailableName = (id: string) => `Name unavailable · ${id.slice(0, 8)}`;
export const payoutInRange = (p: Payout, from: string, to: string) => (!from || p.payment_date >= from) && (!to || p.payment_date <= to);
export const payoutExportColumns = (name: (id: string) => string) => [
  { header: 'Payout ID', value: (p: Payout) => p.id }, { header: 'Payment date', value: (p: Payout) => p.payment_date },
  { header: 'Commission month', value: (p: Payout) => p.payout_month.slice(0, 7) },
  { header: 'Affiliate', value: (p: Payout) => name(p.referrer_customer_id) },
  { header: 'Affiliate ID', value: (p: Payout) => p.referrer_customer_id },
  { header: 'Amount', value: (p: Payout) => Number(p.total_amount) },
  { header: 'Tier 1', value: (p: Payout) => Number(p.total_tier1) }, { header: 'Tier 2', value: (p: Payout) => Number(p.total_tier2) },
  { header: 'Method', value: (p: Payout) => p.payment_method_name || 'Historical method unavailable' },
  { header: 'Reference', value: (p: Payout) => p.reference || '' }, { header: 'Notes', value: (p: Payout) => p.notes || '' },
  { header: 'Status', value: (p: Payout) => p.status }, { header: 'Review', value: (p: Payout) => p.allocation_review_reason || '' },
];

const cents = (n: unknown) => Math.round(Number(n || 0) * 100);
const fromCents = (c: number) => c / 100;

/** A signed net figure (what an affiliate's months add up to) as the pages
 *  show it: never a negative "Unpaid"; what is owed back is the deduction to
 *  be recovered from later commission (410, the Owner's rule of 3 Oct 2026). */
export function owedSplit(net: number | string | null | undefined): { unpaid: number; deduction: number } {
  const c = cents(net);
  return { unpaid: fromCents(Math.max(c, 0)), deduction: fromCents(Math.max(-c, 0)) };
}

const usable = (g: Balance) => (g.month && !g.review_reason ? Math.max(cents(g.balance), 0) : 0);

/** Each affiliate's months netted, as affiliate_referrer_balances works them
 *  out. Used only when the server does not send them (before 410). */
export function referrerBalancesFrom(groups: Balance[]): ReferrerBalance[] {
  const by = new Map<string, { owed: number; payable: number }>();
  for (const g of groups) {
    const r = by.get(g.referrer) ?? { owed: 0, payable: 0 };
    r.owed += cents(g.balance);
    r.payable += g.month && !g.review_reason ? cents(g.balance) : Math.min(cents(g.balance), 0);
    by.set(g.referrer, r);
  }
  return [...by.entries()].map(([referrer, r]) => ({
    referrer, owed: fromCents(r.owed), unpaid: fromCents(Math.max(r.owed, 0)),
    deduction: fromCents(Math.max(-r.owed, 0)), payable: fromCents(Math.max(r.payable, 0)),
  }));
}

/** The affiliates' figures: the server's when it sends them (410), else
 *  worked out from the months the same way. */
export function referrerBalances(groups: Balance[], fromServer?: ReferrerBalance[] | null): Map<string, ReferrerBalance> {
  const list = Array.isArray(fromServer) ? fromServer : referrerBalancesFrom(groups);
  return new Map(list.map(r => [r.referrer, {
    referrer: r.referrer, owed: Number(r.owed), unpaid: Number(r.unpaid), deduction: Number(r.deduction), payable: Number(r.payable),
  }]));
}

const key = (g: Balance) => `${g.referrer}/${g.month ?? ''}`;

/** What may be paid for each month now: the affiliate's payable shown against
 *  their months with a positive balance, oldest first, so the months add up to
 *  it (410). The server's figure when it sends one. */
export function monthPayable(groups: Balance[], referrers: Map<string, ReferrerBalance>): Map<string, number> {
  const out = new Map<string, number>();
  if (groups.length && groups.every(g => g.payable !== undefined && g.payable !== null)) {
    for (const g of groups) out.set(key(g), Number(g.payable));
    return out;
  }
  const left = new Map<string, number>();
  for (const [id, r] of referrers) left.set(id, cents(r.payable));
  const oldestFirst = [...groups].sort((a, b) =>
    a.referrer.localeCompare(b.referrer) || (a.month ?? '9999').localeCompare(b.month ?? '9999'));
  for (const g of oldestFirst) {
    const room = left.get(g.referrer) ?? 0;
    const take = Math.max(Math.min(usable(g), room), 0);
    left.set(g.referrer, room - take);
    out.set(key(g), fromCents(take));
  }
  return out;
}

/** "Remaining payable": every affiliate's payable added up. */
export const remainingPayable = (referrers: Map<string, ReferrerBalance>) =>
  fromCents([...referrers.values()].reduce((s, r) => s + cents(r.payable), 0));

/** Deductions still to be recovered, across affiliates. */
export const deductionsOutstanding = (referrers: Map<string, ReferrerBalance>) => {
  const owing = [...referrers.values()].filter(r => cents(r.deduction) > 0);
  return { count: owing.length, total: fromCents(owing.reduce((s, r) => s + cents(r.deduction), 0)) };
};

export const monthKey = key;
