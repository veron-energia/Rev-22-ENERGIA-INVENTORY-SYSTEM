/**
 * A rental's Return on the Special page (396, the Owner's rules of 6 Oct 2026).
 *
 * The screen asks when it came back ("Returned on", today by default, never
 * in the future or before the rental started), its condition, and whether it
 * goes back into stock where it came from (the warehouse or the store it was
 * released from; an old-style rental, the old special-product stock it was
 * taken from; a lost unit never). A rental returned after its due date offers "No late fee"
 * (the default; no reason needed) or "Charge late fee": the days start at the
 * days late and may only be fewer, the daily rate is typed (prefilled from the
 * rental's own late fee), an optional discount (S$ or %) needs a reason, and
 * the fee after it must be more than S$0. The fee is paid there and then by
 * one method that is not wallet credit, and the database invoices it on an
 * invoice of its own (return_rental_with_fee).
 *
 * Kept free of React and of the database, so the page and the tests share one
 * copy of the rules. The database checks every one of them again.
 */

export type LateFeeChoice = 'none' | 'charge';
export type ReturnDiscount = '' | 'manual' | 'percentage';
export type ReturnConditionValue = 'good' | 'damaged' | 'lost';

/** The rental columns the Return reads. */
export type ReturnRental = {
  rental_no: string;
  quantity: number;
  start_date: string;
  expected_return_date: string;
  late_fee_per_day?: number | null;
  warehouse_id?: string | null;
  source_store_id?: string | null;
  store_id?: string | null;
  invoice_id?: string | null;
  // Set when fulfil_special_doc released it from a warehouse or a store; an
  // old-style rental (create_rental, pay_rental) has none and no invoice.
  fulfilled_at?: string | null;
};

export type ReturnForm = {
  returnedOn: string;            // YYYY-MM-DD, Singapore
  condition: ReturnConditionValue;
  returnStock: boolean;
  choice: LateFeeChoice;
  days: string;                  // as typed
  rate: string;                  // S$ per day, as typed
  discount: ReturnDiscount;
  discountAmount: string;
  discountPercent: string;
  discountReason: string;
  paymentMethodId: string;
  reference: string;
  storeId: string;               // only for a rental with no store of its own
  note: string;
};

export type Place = { id: string; name: string };

const day = (d: string) => String(d ?? '').slice(0, 10);
// Half away from zero on the decimal digits, as PostgreSQL's numeric round()
// does: 9.995 is 10.00 there, though 9.995 in binary is just under it.
const round = (n: number, places: number) => {
  const f = 10 ** places;
  return Math.sign(n) * Math.round(Number(Math.abs(n * f).toPrecision(15))) / f;
};
const num = (s: string): number => {
  const t = String(s ?? '').trim();
  return t === '' ? NaN : Number(t);
};
export const money = (n: number) => `S$${(Number.isFinite(n) ? n : 0).toFixed(2)}`;
/** 2026-09-09 -> 09/09/2026, without going through a time zone. */
export const shortDate = (d: string) => { const [y, m, dd] = day(d).split('-'); return `${dd}/${m}/${y}`; };
const plural = (n: number, one: string) => `${n} ${one}${n === 1 ? '' : 's'}`;

/** Whether s is a calendar date, YYYY-MM-DD (a cleared date input gives ''). */
export const isDay = (s: string): boolean => /^\d{4}-\d{2}-\d{2}$/.test(day(s));

/** Whole days from a to b (b later is positive), on the calendar dates alone. */
export function daysBetween(a: string, b: string): number {
  const [y1, m1, d1] = day(a).split('-').map(Number);
  const [y2, m2, d2] = day(b).split('-').map(Number);
  return Math.round((Date.UTC(y2, m2 - 1, d2) - Date.UTC(y1, m1 - 1, d1)) / 86400000);
}

/** Days late when it came back on returnedOn: none on or before the due date,
 *  and none while no date is chosen. */
export const lateDaysOn = (r: ReturnRental, returnedOn: string): number =>
  isDay(returnedOn) && isDay(r.expected_return_date) ? Math.max(0, daysBetween(r.expected_return_date, returnedOn)) : 0;

/** A rental with no store of its own (an old-style one): staff choose where to invoice. */
export const needsStoreChoice = (r: ReturnRental): boolean =>
  !r.store_id && !r.source_store_id && !r.invoice_id;

/** The form as it opens: today, good, back into stock, "No late fee", nothing paid by yet. */
export function initialReturnForm(r: ReturnRental, today: string): ReturnForm {
  const ownRate = Number(r.late_fee_per_day ?? 0);
  return {
    returnedOn: today, condition: 'good', returnStock: true, choice: 'none',
    days: String(lateDaysOn(r, today)), rate: ownRate > 0 ? ownRate.toFixed(2) : '',
    discount: '', discountAmount: '', discountPercent: '', discountReason: '',
    paymentMethodId: '', reference: '', storeId: '', note: '',
  };
}

/** A new "Returned on": the days to charge follow it (all the days late).
 *  A cleared date keeps the days as they were until a date is chosen again. */
export const withReturnedOn = (f: ReturnForm, r: ReturnRental, returnedOn: string): ReturnForm =>
  isDay(returnedOn) ? { ...f, returnedOn, days: String(lateDaysOn(r, returnedOn)) } : { ...f, returnedOn };

/** A new condition. A lost unit never goes back into stock, so "lost" unticks
 *  the stock box; leaving "lost" ticks it again, as the form opens. */
export const withCondition = (f: ReturnForm, condition: ReturnConditionValue): ReturnForm =>
  ({ ...f, condition, returnStock: condition === 'lost' ? false : f.condition === 'lost' ? true : f.returnStock });

/** The fee, worked out as the database works it out (to the cent). */
export function lateFeeAmounts(f: ReturnForm, r: ReturnRental) {
  const days = Math.trunc(num(f.days));
  const rate = round(num(f.rate), 2);
  const qty = Math.max(1, Number(r.quantity) || 1);
  const unit = round(rate * qty, 2);
  const gross = round(days * unit, 2);
  let discount = 0;
  if (f.discount === 'manual') discount = round(num(f.discountAmount), 2);
  if (f.discount === 'percentage') discount = round(gross * round(num(f.discountPercent), 3) / 100, 2);
  const total = round(gross - (Number.isFinite(discount) ? discount : 0), 2);
  return { days, rate, quantity: qty, unit, gross, discount, total };
}

/** What the Return says about lateness. Never "on time" for a late rental, whatever its rate. */
export function lateNotice(r: ReturnRental, returnedOn: string): string {
  if (!isDay(returnedOn)) return 'Choose the date it came back.';
  const late = lateDaysOn(r, returnedOn);
  if (late === 0) return 'Returned on time — no late fee.';
  return `${plural(late, 'day')} late: it was due back on ${shortDate(r.expected_return_date)}.`;
}

/** The fee as a sum staff can check, e.g. "3 days × S$12.00 × 2 = S$72.00 − S$5.00 = S$67.00". */
export function lateFeeSum(f: ReturnForm, r: ReturnRental): string {
  const a = lateFeeAmounts(f, r);
  if (!(a.days > 0) || !(a.rate > 0)) return '';
  const base = `${plural(a.days, 'day')} × ${money(a.rate)}${a.quantity > 1 ? ` × ${a.quantity}` : ''} = ${money(a.gross)}`;
  if (!f.discount || !(a.discount > 0)) return base;
  const what = f.discount === 'percentage' ? ` (${round(num(f.discountPercent), 3)}%)` : '';
  return `${base} − ${money(a.discount)}${what} = ${money(a.total)}`;
}

/** An old-style rental (create_rental, pay_rental): no invoice, never released by fulfil_special_doc. */
export const isOldStyleRental = (r: ReturnRental): boolean => !r.invoice_id && !r.fulfilled_at;

/**
 * Where a ticked return puts the unit back, as rental_put_back_stock does, and
 * what the tick says. A rental released from a store or a warehouse goes back
 * there. An old-style rental was taken from the old special-product stock,
 * never from warehouse stock, so it goes back there and warehouse stock does
 * not change.
 */
export function stockHome(r: ReturnRental, ctx: { warehouses: Place[]; stores: Place[]; isWarehouseProduct: boolean }) {
  const qty = Math.max(1, Number(r.quantity) || 1);
  const oldStyle = isOldStyleRental(r);
  const kind: 'store' | 'warehouse' | 'special_stock' | null = oldStyle
    ? (r.warehouse_id ? 'special_stock' : null)
    : !r.fulfilled_at ? null : r.source_store_id ? 'store' : r.warehouse_id ? 'warehouse' : null;
  const whName = ctx.warehouses.find(w => w.id === r.warehouse_id)?.name ?? 'its warehouse';
  const name = kind === 'store' ? (ctx.stores.find(s => s.id === r.source_store_id)?.name ?? 'its store')
    : kind ? whName : null;
  if (!kind || !ctx.isWarehouseProduct) {
    return {
      kind: null, name: null, canRestock: false,
      label: `Return ${qty} to stock`, hint: null as string | null,
      note: !ctx.isWarehouseProduct
        ? 'Its special product is not a warehouse product, so there is no stock to put it back into. The return is recorded without a stock change.'
        : 'It was never released from a warehouse or a store, so there is no stock to put it back into. The return is recorded without a stock change.',
    };
  }
  if (kind === 'special_stock') {
    return { kind, name, canRestock: true, label: `Return ${qty} to the old special stock at ${name}`,
      hint: 'An old-style rental: it was taken from the old special-product stock, not from warehouse stock, so it goes back there. Warehouse stock does not change. Untick for lost or unusable items.',
      note: null as string | null };
  }
  return { kind, name, canRestock: true, label: `Return ${qty} to ${name} stock`,
    hint: 'Untick for lost or unusable items: no stock changes.', note: null as string | null };
}

/** The first thing stopping Confirm Return, in words, or null. */
export function returnProblem(f: ReturnForm, r: ReturnRental,
  ctx: { today: string; walletMethodIds?: string[] }): string | null {
  if (!isDay(f.returnedOn)) return 'Choose the date it came back.';
  if (day(f.returnedOn) > day(ctx.today)) return 'The return date cannot be in the future.';
  if (day(f.returnedOn) < day(r.start_date)) return `The return date cannot be before the rental started (${shortDate(r.start_date)}).`;
  if (f.condition === 'lost' && f.returnStock) return 'A lost unit cannot go back into stock. Untick the stock box for a lost rental.';
  const late = lateDaysOn(r, f.returnedOn);
  if (f.choice !== 'charge' || late === 0) return null;
  const a = lateFeeAmounts(f, r);
  if (!Number.isInteger(num(f.days)) || a.days < 1 || a.days > late)
    return `Charge between 1 and ${late} day${late === 1 ? '' : 's'}: it was ${plural(late, 'day')} late.`;
  if (!(a.rate > 0)) return 'Type the daily late fee (more than S$0).';
  if (f.discount === 'manual' && !(round(num(f.discountAmount), 2) > 0)) return 'Enter the discount in S$ (more than 0).';
  if (f.discount === 'percentage') {
    const p = num(f.discountPercent);
    if (!(round(p, 3) > 0) || p > 100) return 'The percentage discount must be more than 0% and at most 100%.';
  }
  if (f.discount && !f.discountReason.trim())
    return 'Give the reason for the discount. It stays on the invoice for staff and is never printed.';
  if (!(a.total > 0)) return 'The late fee after the discount must be more than S$0. Choose "No late fee" instead.';
  if (!f.paymentMethodId) return 'Choose how the late fee is paid.';
  if ((ctx.walletMethodIds ?? []).includes(f.paymentMethodId)) return 'Wallet credit cannot pay a late fee. Choose another payment method.';
  if (needsStoreChoice(r) && !f.storeId) return 'Choose the store to invoice this late fee in: this rental has no store of its own.';
  return null;
}

/** The arguments for return_rental_with_fee. */
export function returnRpcArgs(rentalId: string, f: ReturnForm, r: ReturnRental): Record<string, unknown> {
  const charge = f.choice === 'charge' && lateDaysOn(r, f.returnedOn) > 0;
  const a = lateFeeAmounts(f, r);
  return {
    p_rental_id: rentalId,
    p_condition: f.condition,
    p_return_stock: f.returnStock,
    p_returned_on: day(f.returnedOn),
    p_charge_late_fee: charge,
    p_late_days: charge ? a.days : null,
    p_daily_rate: charge ? a.rate : null,
    p_discount_type: charge && f.discount ? f.discount : null,
    p_discount_amount: charge && f.discount === 'manual' ? round(num(f.discountAmount), 2) : null,
    p_discount_percent: charge && f.discount === 'percentage' ? num(f.discountPercent) : null,
    p_discount_reason: charge && f.discount ? f.discountReason.trim() : null,
    p_payment_method_id: charge ? f.paymentMethodId : null,
    p_payment_reference: charge ? (f.reference.trim() || null) : null,
    p_store_id: charge && needsStoreChoice(r) ? (f.storeId || null) : null,
    p_note: f.note.trim() || null,
  };
}

/** What the Rentals tab says about a returned rental's late fee, or null. */
export function lateFeeStatus(r: { status: string; late_days?: number | null; late_fee_total?: number | null;
  late_fee_waived?: boolean | null; late_fee_invoice_id?: string | null }, invoiceNo?: string | null): string | null {
  if (r.status !== 'returned') return null;
  const fee = Number(r.late_fee_total ?? 0);
  if (fee > 0) return `+${money(fee)} late${r.late_fee_invoice_id ? ` · ${invoiceNo ?? 'invoiced'}` : ''}`;
  if (r.late_fee_waived) return `${plural(Number(r.late_days ?? 0), 'day')} late · no late fee`;
  return null;
}

/** Overdue while still out: how late, and the fee at the rental's own rate when it has one. */
export function overdueNote(r: ReturnRental & { status: string }, today: string): string | null {
  if (!['paid', 'active', 'overdue'].includes(r.status)) return null;
  const late = lateDaysOn(r, today);
  if (late === 0) return null;
  const rate = Number(r.late_fee_per_day ?? 0);
  return rate > 0 ? `${late}d late · ${money(late * rate * Math.max(1, Number(r.quantity) || 1))}` : `${late}d late`;
}

/**
 * A rental receipt and its late fee. A fee invoiced at the Return (396) is on
 * its own invoice, so the receipt names that invoice and leaves it out of its
 * total; a fee from before 396 was collected on the rental and stays in.
 */
export function receiptLateFee(r: { late_fee_total?: number | null; late_fee_invoice_id?: string | null },
  invoiceNo?: string | null): { inTotal: number; note: string | null } {
  const fee = Number(r.late_fee_total ?? 0);
  if (!(fee > 0)) return { inTotal: 0, note: null };
  if (r.late_fee_invoice_id) return { inTotal: 0, note: `Late return fee ${money(fee)}, invoiced on ${invoiceNo ?? 'its own invoice'}` };
  return { inTotal: fee, note: null };
}
