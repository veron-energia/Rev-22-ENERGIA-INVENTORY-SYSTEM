import { calendarDate } from '../calendarDates';
export type InstalmentDetails = {
  instalment_category: '' | 'in_house' | 'provider_funded';
  instalment_method_id: string;
  instalment_months: number | '';
};
export const singaporeToday = () => calendarDate(new Date(), 'Asia/Singapore');
export function invoiceDate(invoice: { business_date?: string | null }) {
  return invoice.business_date || '';
}
export function displayInvoiceDate(invoice: { business_date?: string | null }) {
  return invoice.business_date ? invoice.business_date.split('-').reverse().join('/') : 'Date pending review';
}
/** Informational only; never a substitute for the invoice business date. */
export function invoiceCreatedOn(invoice: { created_at?: string | null }) {
  const day = calendarDate(invoice.created_at, 'Asia/Singapore');
  return day ? day.split('-').reverse().join('/') : '';
}
export function invoiceDateSearch(invoice: { business_date?: string | null }) {
  const day = invoiceDate(invoice);
  if (!day) return 'Date pending review';
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
