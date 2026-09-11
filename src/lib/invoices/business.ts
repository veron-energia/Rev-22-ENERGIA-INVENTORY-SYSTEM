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
