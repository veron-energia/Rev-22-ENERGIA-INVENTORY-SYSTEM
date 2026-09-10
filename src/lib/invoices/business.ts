export type InstalmentDetails = {
  instalment_category: '' | 'in_house' | 'provider_funded';
  instalment_method_id: string;
  instalment_months: number | '';
};
export const singaporeToday = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
export function invoiceDate(invoice: { business_date?: string | null }) {
  return invoice.business_date || '';
}
export function displayInvoiceDate(invoice: { business_date?: string | null }) {
  return invoice.business_date ? invoice.business_date.split('-').reverse().join('/') : 'Date pending review';
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
