/**
 * "Change rental terms" in the Special page's waiting list (426, audit
 * finding SALES-EXTRAS-7).
 *
 * Only a rental still waiting for a warehouse can be changed (the database
 * refuses any other). "Due back" follows the start, the rate and the periods,
 * worked out as the database works it out; staff may still type another date,
 * which is kept until the start, the rate or the periods change again. The
 * date may never be before the start.
 *
 * The fee (termsFee) is worked out as update_pending_rental works it out, so
 * the window's preview and the save agree. The owner, 18 Oct 2026 ("Keep the
 * same discount"): a change of the quantity, the rate type or the periods
 * prices the new terms at the list rate less the same FOC share, or the same
 * amount or percentage off, as the invoice line sold it, never below S$0. A
 * change of dates alone keeps the fee as sold.
 */

export type RateType = 'day' | 'week' | 'month' | 'year';

export interface TermsForm {
  quantity: number;
  rate_type: RateType;
  periods: number;
  start_date: string;           // YYYY-MM-DD
  expected_return_date: string; // YYYY-MM-DD, '' when cleared
}

const isDay = (v: string | null | undefined) => /^\d{4}-\d{2}-\d{2}$/.test(String(v ?? ''));

/**
 * The due date: days, weeks of 7 days, calendar months or years after the
 * start. A month after 31 Jan is the last day of February (28 Feb, or 29 Feb
 * in a leap year), as the database's date + interval gives it, never 3 Mar.
 * Worked in UTC, so the time zone can never move it a day.
 */
export function addPeriods(start: string, rateType: RateType, periods: number): string {
  if (!isDay(start)) return '';
  const n = Math.max(1, Math.floor(Number(periods) || 1));
  const [y, m, dd] = start.split('-').map(Number);
  let d: Date;
  if (rateType === 'day' || rateType === 'week') {
    d = new Date(Date.UTC(y, m - 1, dd + (rateType === 'week' ? 7 * n : n)));
  } else {
    const months = rateType === 'month' ? n : 12 * n;
    const ty = y + Math.floor((m - 1 + months) / 12);
    const tm = (m - 1 + months) % 12;
    const last = new Date(Date.UTC(ty, tm + 1, 0)).getUTCDate();
    d = new Date(Date.UTC(ty, tm, Math.min(dd, last)));
  }
  return d.toISOString().slice(0, 10);
}

/** The form for a waiting rental, as the waiting list gives it. */
export function initialTerms(row: {
  quantity?: number | null; rate_type?: string | null; periods?: number | null;
  start_date?: string | null; expected_return_date?: string | null;
}): TermsForm {
  return {
    quantity: Number(row.quantity ?? 1) || 1,
    rate_type: (row.rate_type ?? 'day') as RateType,
    periods: Number(row.periods ?? 1) || 1,
    start_date: row.start_date ? String(row.start_date).slice(0, 10) : '',
    expected_return_date: row.expected_return_date ? String(row.expected_return_date).slice(0, 10) : '',
  };
}

/**
 * The form after a change. A new start, rate or number of periods moves "Due
 * back" to match; a quantity alone leaves it; a typed "Due back" is kept.
 */
export function withTermsChange(f: TermsForm, patch: Partial<TermsForm>): TermsForm {
  const next = { ...f, ...patch };
  if ('quantity' in patch) next.quantity = Math.max(1, Math.floor(Number(patch.quantity) || 1));
  if ('periods' in patch) next.periods = Math.max(1, Math.floor(Number(patch.periods) || 1));
  const moves = ['start_date', 'rate_type', 'periods'].some(k => k in patch && (patch as any)[k] !== (f as any)[k]);
  if (moves && isDay(next.start_date)) {
    next.expected_return_date = addPeriods(next.start_date, next.rate_type, next.periods);
  }
  return next;
}

/** What stops the terms being saved, in words, or null. */
export function termsProblem(f: TermsForm): string | null {
  if (!isDay(f.start_date)) return 'Choose the start date.';
  if (!isDay(f.expected_return_date)) return 'Choose the "Due back" date.';
  if (f.expected_return_date < f.start_date) return '"Due back" cannot be before the start.';
  return null;
}

/** Anything changed since the window opened. */
export const termsChanged = (a: TermsForm, b: TermsForm) =>
  a.quantity !== b.quantity || a.rate_type !== b.rate_type || a.periods !== b.periods
  || a.start_date !== b.start_date || a.expected_return_date !== b.expected_return_date;

/** The arguments for update_pending_rental. */
export function termsRpcArgs(rentalId: string, f: TermsForm): Record<string, unknown> {
  return {
    p_rental_id: rentalId,
    p_quantity: Math.max(1, Math.floor(Number(f.quantity) || 1)),
    p_rate_type: f.rate_type,
    p_periods: Math.max(1, Math.floor(Number(f.periods) || 1)),
    p_start_date: f.start_date || null,
    p_expected_return_date: f.expected_return_date || null,
  };
}

/**
 * The invoice line that sold the rental, as invoice_items has it: how the
 * discount was given (FOC, a fixed amount off, or a percentage off).
 */
export interface SoldLine {
  id?: string | null;
  quantity?: number | null;
  rental_rate_type?: string | null;
  rental_periods?: number | null;
  line_total?: number | null;            // its value, the FOC already taken off
  foc_quantity?: number | null;
  is_foc?: boolean | null;
  line_discount?: number | null;         // S$ taken off that value
  line_discount_type?: string | null;    // 'manual' (an amount) or 'percentage'
  line_discount_percent?: number | null;
}

/** The columns of invoice_items that termsFee reads. */
export const SOLD_LINE_COLUMNS =
  'id,quantity,rental_rate_type,rental_periods,line_total,foc_quantity,is_foc,line_discount,line_discount_type,line_discount_percent';

/** The rental as it stands (the waiting list's row). */
export interface RentalNow {
  quantity?: number | null; rate_type?: string | null; periods?: number | null; rental_fee?: number | null;
}

/** The special product's list rates. */
export interface ListRates {
  name?: string | null;
  rate_day?: number | null; rate_week?: number | null; rate_month?: number | null; rate_year?: number | null;
}

export interface TermsFee {
  /** Only the dates change: the fee stays. */
  datesOnly: boolean;
  /** What the rental charges now: the fee as sold while its terms are the line's, else its own fee. */
  before: number;
  /** The fee after the change; null when it cannot be worked out. */
  fee: number | null;
  /** The list rate x periods x quantity for the new terms; null for the dates alone. */
  list: number | null;
  /** The discount kept, in words, as the database says it; null when none. */
  discount: string | null;
  /** fee - before; null when the fee cannot be worked out. */
  difference: number | null;
  /** Why the fee cannot be worked out, in words, or null. */
  problem: string | null;
}

// Money is worked in whole cents, as numeric(12,2) holds it, so the page
// rounds exactly as the database rounds (half a cent up).
const cents = (v: unknown) => Math.round(Number(v ?? 0) * 100);
const int = (v: unknown, min: number) => Math.max(min, Math.floor(Number(v ?? min) || min));
/** n / d rounded to the nearest whole number, a half up; n >= 0, d > 0, both whole. */
function divRound(n: number, d: number): number {
  let q = Math.floor(n / d);
  let r = n - q * d;
  while (r < 0) { q -= 1; r += d; }
  while (r >= d) { q += 1; r -= d; }
  return 2 * r >= d ? q + 1 : q;
}
const sgd = (c: number) => `S$${(c / 100).toFixed(2)}`;

/**
 * The fee for the terms in the window. `line` is the invoice line that sold
 * the rental, or null when it has none (then there is no discount to keep).
 */
export function termsFee(rental: RentalNow, line: SoldLine | null, rates: ListRates | null, f: TermsForm): TermsFee {
  const qty = int(f.quantity, 1), per = int(f.periods, 1), type = f.rate_type;
  const lq = line ? int(line.quantity, 1) : 1;
  // While the rental's terms are the line's (quantity, rate type, periods),
  // what it charges is what the line charges, whatever fee the rental carries:
  // the invoice raises it at the line's value before its discount, and a
  // correction of the line's price alone leaves the rental's fee as it was.
  // A rental whose terms were changed since charges its own fee.
  const asRaised = !!line
    && Number(rental.quantity) === lq
    && rental.rate_type === (line.rental_rate_type ?? 'day')
    && Number(rental.periods) === int(line.rental_periods, 1);
  const beforeC = asRaised
    ? Math.max(cents(line!.line_total) - cents(line!.line_discount), 0)
    : cents(rental.rental_fee);
  const datesOnly = qty === Number(rental.quantity) && type === rental.rate_type && per === Number(rental.periods);
  const out = (feeC: number | null, listC: number | null, discount: string | null, problem: string | null): TermsFee => ({
    datesOnly, before: beforeC / 100, fee: feeC === null ? null : feeC / 100, list: listC === null ? null : listC / 100,
    discount, difference: feeC === null ? null : (feeC - beforeC) / 100, problem,
  });
  if (datesOnly) return out(beforeC, null, null, null);

  const rate = Number((rates as any)?.[`rate_${type}`] ?? 0);
  if (!rates || !(rate > 0)) {
    return out(null, null, null, `"${rates?.name ?? 'This product'}" has no ${type} rate set.`);
  }
  const listC = cents(rate) * per * qty;
  const foc = !line ? 0 : line.is_foc ? lq : Math.min(Math.max(int(line.foc_quantity, 0), 0), lq);
  const pct = Number(line?.line_discount_percent ?? 0);
  let feeC = listC;
  let how: string | null = null;
  if (foc > 0) {
    feeC = listC - divRound(listC * foc, lq);
    how = foc === lq ? 'FOC, as sold' : `the same FOC share as sold (${foc} of ${lq} free)`;
  } else if (line?.line_discount_type === 'percentage' && pct > 0) {
    feeC = listC - divRound(listC * Math.round(Math.min(pct, 100) * 1000), 100000);
    how = `the same ${Number(pct.toFixed(3))}% off as sold`;
  } else if (line && cents(line.line_discount) > 0) {
    feeC = listC - cents(line.line_discount);
    how = `the same ${sgd(cents(line.line_discount))} off as sold`;
  }
  return out(Math.max(feeC, 0), listC, how, null);
}
