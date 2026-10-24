/**
 * Rentals follow their invoice's Edit, Cancel and Refund (458; the Owner,
 * 22 Oct 2026, item 1).
 *
 * The database does the following (supabase/458_rentals_follow_invoice_changes.sql):
 * a correction moves a rental waiting for a warehouse with its line (machine,
 * quantity, rate, periods, start, Due back) and with the invoice's customer and
 * store; a rental out with the customer takes its line's rate, periods and Due
 * back, and a change of its machine or quantity is refused; a refund that takes
 * back a rental's line in full (or the whole invoice) ends a rental out like
 * Cancel, and a refund of some units of a several-machine rental ends those
 * units only (a waiting machine first); a rental waits for its invoice to be
 * paid in full before it is released. These helpers are what the pages say about it, kept free of React
 * and of the database so the node tests read the same rules.
 */
import { addPeriods, type RateType } from './rentalTerms';

const isDay = (v: string | null | undefined) => /^\d{4}-\d{2}-\d{2}$/.test(String(v ?? ''));
const dmy = (d: string) => { const [y, m, dd] = d.split('-'); return `${dd}/${m}/${y}`; };

/** The rental fields of an invoice line, as the invoice form holds them. */
export type RentalLineTerms = {
  rental_rate_type?: RateType | string | null;
  rental_periods?: number | null;
  rental_start_date?: string | null;
  rental_return_date?: string | null;
};

/**
 * "Due back" as the database works it out when it is left blank: the start
 * plus the periods by the rate type (a month after 31 Jan is 28 Feb). '' when
 * there is no start yet.
 */
export function dueBackFor(l: RentalLineTerms): string {
  const start = String(l.rental_start_date ?? '').slice(0, 10);
  if (!isDay(start)) return '';
  return addPeriods(start, (l.rental_rate_type ?? 'day') as RateType, Number(l.rental_periods ?? 1) || 1);
}

/**
 * The line after a change of its rental terms. A new start, rate or number of
 * periods moves "Due back" to the start plus the periods, as on the Special
 * page; a typed "Due back" is kept until one of them changes. With no start the
 * date is left as it was.
 */
export function withRentalDueBack<T extends RentalLineTerms>(before: T, after: T): T {
  const moved = (['rental_start_date', 'rental_rate_type', 'rental_periods'] as const)
    .some(k => (after[k] ?? null) !== (before[k] ?? null));
  if (!moved) return after;
  const due = dueBackFor(after);
  return due ? { ...after, rental_return_date: due } : after;
}

/** Under a blank "Due back": the date the rental will be given. */
export function blankDueBackHint(l: RentalLineTerms): string | null {
  if (String(l.rental_return_date ?? '').trim()) return null;
  const due = dueBackFor(l);
  return due ? `Left blank, it is due back ${dmy(due)} (the start plus the periods).` : null;
}

/** Under a rental line of a saved invoice in the correction form. */
export const RENTAL_FOLLOWS_HINT =
  'Saving changes this line’s rental to match. While it waits for a warehouse it follows the line, the customer and the store '
  + '(machines already refunded stay off it), and it is released only once the invoice is paid in full; '
  + 'once it is out with the customer only its rate, periods and Due back can change (its machine and quantity stay until it is returned).';

/** One entry of correct_invoice's answer 'rentals' (458). */
export type RentalFollowed = { rental_id: string; rental_no: string; state: 'waiting' | 'out' | string; what: string };

/** After a correction is saved: what it did to the invoice's rentals, or null. */
export function correctionRentalNote(rentals: RentalFollowed[] | null | undefined): string | null {
  const list = (rentals ?? []).filter(r => r && typeof r.what === 'string' && r.what);
  if (!list.length) return null;
  return `The ${list.length === 1 ? 'rental follows' : 'rentals follow'} the corrected invoice: ${list.map(r => r.what).join('; ')}.`;
}

/** What a refund or a cancellation does to a rental out, said in its review. */
export function rentalOutReviewNote(action: string): string | null {
  if (action === 'cancel') {
    return 'A rented item still with the customer stays out until it comes back. After the cancellation you can record it as back, damaged or lost.';
  }
  if (action === 'refund_full' || action === 'refund_partial') {
    return 'A rental out with the customer on a line this refund takes back in full ends here (no late fee) and stays out until it comes back; '
      + 'refunding some machines of a rental ends those machines only, and the rest keep running. '
      + 'After the refund you can record what came back, damaged or lost.';
  }
  return null;
}

/** The done screen's words over the items still with the customer. */
export function rentalOutDoneNote(action: string): string {
  return `${action === 'cancel' ? 'Cancelling' : 'The refund'} ends the rental but does not bring the item back.`;
}

/**
 * The finance section's words for rentals still with the customer: after the
 * cancellation, after the refund, or, on an invoice that is neither (a rental
 * line refunded on a paid invoice, or a rental cancelled while out on an
 * invoice reopened and not yet paid again), after the rental ended.
 */
export function stillOutAfter(status: string | null | undefined): string {
  if (status === 'cancelled') return 'after the cancellation';
  if (status === 'refunded') return 'after the refund';
  return 'after the rental ended';
}
