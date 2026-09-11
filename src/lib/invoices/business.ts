import { calendarDate } from '../calendarDates';
export type InstalmentDetails = {
  instalment_category: '' | 'in_house' | 'provider_funded';
  instalment_method_id: string;
  instalment_months: number | '';
};
export const singaporeToday = () => calendarDate(new Date(), 'Asia/Singapore');
/**
 * The invoice's own date: what was recorded, or failing that the Singapore
 * calendar date it was created on. One definition, so the list, the filters,
 * the outputs and the exports cannot disagree.
 */
export function invoiceDate(invoice: { business_date?: string | null; created_at?: string | null }) {
  return invoice.business_date || calendarDate(invoice.created_at, 'Asia/Singapore') || '';
}
/**
 * The date an invoice shows.
 *
 * Where no business date was ever recorded, the Singapore calendar date the
 * invoice was created on IS the invoice's date — that is the decision the
 * business made, and it is what staff saw before the field existed. It is no
 * longer a financial attribution: since 292, received money is reported on the
 * day it was received, so this date describes the document, not the period the
 * cash lands in.
 */
export function displayInvoiceDate(invoice: { business_date?: string | null; created_at?: string | null }) {
  const day = invoiceDate(invoice);
  return day ? day.split('-').reverse().join('/') : '—';
}
/** The creation date on its own, for the rare places that need it explicitly. */
export function invoiceCreatedOn(invoice: { created_at?: string | null }) {
  const day = calendarDate(invoice.created_at, 'Asia/Singapore');
  return day ? day.split('-').reverse().join('/') : '';
}
export function invoiceDateSearch(invoice: { business_date?: string | null; created_at?: string | null }) {
  const day = invoiceDate(invoice);
  if (!day) return '';
  const month = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][Number(day.slice(5, 7)) - 1];
  return `${day} ${displayInvoiceDate(invoice)} ${day.slice(8)} ${month} ${day.slice(0, 4)}`;
}
export function instalmentText(invoice: Partial<InstalmentDetails>, methods: { id: string; name: string }[]) {
  if (!invoice.instalment_category) return '';
  return `${invoice.instalment_category === 'in_house' ? 'In-house' : 'Provider-funded'} instalments · ${invoice.instalment_months} months · ${methods.find(m => m.id === invoice.instalment_method_id)?.name ?? 'Saved payment method'}`;
}
export function validateInstalment(value: InstalmentDetails) {
  if (!value.instalment_category) return null;
  if (!['in_house', 'provider_funded'].includes(value.instalment_category)) return 'Choose an instalment category.';
  if (!value.instalment_method_id) return 'Choose the underlying payment method.';
  if (!Number.isInteger(value.instalment_months) || Number(value.instalment_months) <= 0) return 'Instalment duration must be a positive whole number of months.';
  return null;
}
/**
 * Order two invoice numbers the way a person reads them.
 *
 * Two formats are in use, and both have to sort sensibly:
 *   INV-2026-0172                normal invoices, sequence padded to 4
 *   SG-ADL-EX-INV-2026-00001     exchange invoices, padded to 5, per store
 *
 * A plain string comparison is right for almost all of this, and wrong in one
 * place: once a year passes its padding width the number grows a digit, and
 * "INV-2026-10000" would sort BEFORE "INV-2026-9999" because '1' < '9'. So
 * digit runs are compared as numbers and everything else as text, which orders
 * the sequence correctly at any length and still groups the two formats apart
 * by their prefix.
 */
export function compareInvoiceNo(a: string, b: string) {
  const parts = (s: string) => (s ?? '').match(/\d+|\D+/g) ?? [];
  const left = parts(a), right = parts(b);
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    const x = left[i], y = right[i];
    if (x === undefined) return -1;
    if (y === undefined) return 1;
    const bothNumeric = /^\d/.test(x) && /^\d/.test(y);
    if (bothNumeric) {
      // Number() is exact well past any realistic invoice sequence.
      if (Number(x) !== Number(y)) return Number(x) < Number(y) ? -1 : 1;
    } else if (x !== y) {
      return x < y ? -1 : 1;
    }
  }
  return 0;
}
/** Newest invoice number first, which is how the invoice list reads. */
export function byInvoiceNoDesc(
  a: { invoice_no?: string | null }, b: { invoice_no?: string | null },
) {
  return compareInvoiceNo(b.invoice_no ?? '', a.invoice_no ?? '');
}
