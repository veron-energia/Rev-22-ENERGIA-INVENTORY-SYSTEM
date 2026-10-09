/** One affiliate's month as affiliate_payout_overview sends it. 410 adds
 *  `payable` (what may be paid for this month now, once the affiliate's other
 *  months are netted in) and the affiliate's own figures on every month. They
 *  are optional so this page still works against a database without 410. */
export type Balance = {
  referrer: string; month: string | null; earned: number; adjustments: number; paid: number; balance: number; review_reason: string | null;
  payable?: number; referrer_owed?: number; referrer_payable?: number; referrer_deduction?: number;
  /** 414: what of the affiliate's settled deductions this month takes (its
   *  balance already counts it). Missing before 414. */
  settled?: number;
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

// ── 414: a deduction marked as settled ────────────────────────────────────
// Commission paid out and then taken back is recovered from the affiliate's
// later commission (410). The Owner decided on 9 Oct 2026 that an Owner or
// Manager may also record that it was settled some other way. The settlement
// is its own dated record: the take-backs and payouts stay as they are, and a
// mistaken one is voided with a reason, never deleted.

export type SettlementMethod = 'paid_back' | 'written_off' | 'paid_outside_app';
export const SETTLEMENT_METHODS: { value: SettlementMethod; label: string }[] = [
  { value: 'paid_back', label: 'Paid back to us' },
  { value: 'written_off', label: 'Written off' },
  { value: 'paid_outside_app', label: 'Paid off outside the app' },
];
export const settlementMethodLabel = (m: string | null | undefined) =>
  SETTLEMENT_METHODS.find(x => x.value === m)?.label ?? (m || 'Unknown');

/** A settlement as affiliate_payout_overview sends it (414). */
export type Settlement = {
  id: string; referrer_customer_id: string; amount: number | string; settled_on: string; method: string; note: string;
  created_by: string | null; created_by_name?: string | null; created_at: string;
  voided_at: string | null; voided_by: string | null; voided_by_name?: string | null; void_reason: string | null;
};
export type SettlementForm = { method: string; amount: string; date: string; note: string };

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const isoDay = (iso: string | null | undefined) => /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso ?? '').slice(0, 10));
/** A calendar date (YYYY-MM-DD) as the page's other dates show (en-SG,
 *  DD/MM/YYYY); anything else as it came. */
export const sgDate = (iso: string | null | undefined) => {
  const m = isoDay(iso);
  return m ? `${m[3]}/${m[2]}/${m[1]}` : String(iso ?? '');
};
/** A calendar date as the server words it in a refusal: 2 Oct 2026. */
export const longDate = (iso: string | null | undefined) => {
  const m = isoDay(iso);
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : String(iso ?? '');
};
/** The earliest settlement date the server accepts. */
export const SETTLEMENT_EARLIEST = '2020-01-01';
/** The day of an affiliate's first payout still paid: a deduction exists only
 *  after one, so it cannot have been settled before it (414). null when none
 *  is listed (the server then decides). */
export function firstPaidPayoutDate(payouts: Pick<Payout, 'referrer_customer_id' | 'status' | 'payment_date'>[], referrer: string): string | null {
  let first: string | null = null;
  for (const p of payouts) {
    if (p.referrer_customer_id !== referrer || p.status !== 'paid' || !isoDay(p.payment_date)) continue;
    const d = p.payment_date.slice(0, 10);
    if (first === null || d < first) first = d;
  }
  return first;
}

/** What the server refuses in Mark as settled, said the same way; '' when it
 *  would be accepted. The amount is at most what the affiliate owes back; the
 *  date is not in the future, not before 1 Jan 2020 and not before the
 *  affiliate's first payout (`firstPayout`, when known). */
export function settlementFormError(f: SettlementForm, deduction: number, today: string, firstPayout?: string | null): string {
  if (!SETTLEMENT_METHODS.some(m => m.value === f.method)) return 'Choose how it was settled.';
  const amount = f.amount.trim();
  if (!/^\d+(\.\d{1,2})?$/.test(amount) || cents(amount) <= 0) return 'Enter an amount above S$0.00 with at most two decimal places.';
  if (cents(amount) > cents(deduction)) return `Enter at most ${payoutMoney(deduction)}, what this affiliate owes back.`;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(f.date) || f.date > today) return 'Enter the date it was settled. It cannot be after today in Singapore.';
  if (f.date < SETTLEMENT_EARLIEST) return 'Enter the date it was settled. It cannot be before 1 Jan 2020.';
  if (firstPayout && f.date < firstPayout) return `The date it was settled cannot be before the first payout to this affiliate, on ${longDate(firstPayout)}.`;
  if (!f.note.trim()) return 'A note is required: say how and why it was settled.';
  if (f.note.trim().length > 2000) return 'The note is too long (2,000 characters at most).';
  return '';
}

/** The settlements still counting (not voided), of one affiliate or all. */
export const settlementsInForce = (list: Settlement[], referrer?: string) =>
  list.filter(s => !s.voided_at && (!referrer || s.referrer_customer_id === referrer));
/** What the settlements still counting come to. */
export const settledTotal = (list: Settlement[], referrer?: string) =>
  fromCents(settlementsInForce(list, referrer).reduce((sum, s) => sum + cents(s.amount), 0));
export const settlementInRange = (s: Settlement, from: string, to: string) =>
  (!from || s.settled_on >= from) && (!to || s.settled_on <= to);
/** The Dashboard's "Unpaid commission" (414): what affiliates are still owed,
 *  each one's months netted and never below 0, as the Commissions page shows
 *  it (dashboard_summary's unpaid_commission), and what is still to be
 *  recovered from them. A database without 414 sends neither; the page then
 *  shows what it worked out itself (`fallback`), as before. */
export function dashboardCommissionFigures(summary: any, fallback: number): { unpaid: number; deductions: number; fromServer: boolean } {
  const unpaid = summary?.unpaid_commission, deductions = summary?.commission_deductions;
  if (unpaid === undefined || unpaid === null || !Number.isFinite(Number(unpaid))) return { unpaid: fromCents(cents(fallback)), deductions: 0, fromServer: false };
  return { unpaid: fromCents(cents(unpaid)), deductions: fromCents(Math.max(cents(deductions), 0)), fromServer: true };
}

export const settlementExportColumns = (name: (id: string) => string) => [
  { header: 'Settlement ID', value: (s: Settlement) => s.id }, { header: 'Date settled', value: (s: Settlement) => s.settled_on },
  { header: 'Affiliate', value: (s: Settlement) => name(s.referrer_customer_id) },
  { header: 'Affiliate ID', value: (s: Settlement) => s.referrer_customer_id },
  { header: 'Amount', value: (s: Settlement) => Number(s.amount) },
  { header: 'How', value: (s: Settlement) => settlementMethodLabel(s.method) },
  { header: 'Note', value: (s: Settlement) => s.note },
  { header: 'Recorded by', value: (s: Settlement) => s.created_by_name || s.created_by || '' },
  { header: 'Status', value: (s: Settlement) => (s.voided_at ? 'Voided' : 'In force') },
  { header: 'Void reason', value: (s: Settlement) => s.void_reason || '' },
];
