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

/* ---- invoice sorting ------------------------------------------------------
   The list loader pages through EVERY accessible invoice before the page
   renders, so ordering the loaded set is ordering all matching records — the
   sort is never applied to just one page. Fields are a closed union rather
   than a string, so nothing a person types can reach a query.            */

export type InvoiceSortField =
  | 'invoice_no' | 'created_at' | 'business_date'
  | 'customer' | 'store' | 'total' | 'outstanding' | 'status';
export type SortDirection = 'asc' | 'desc';

export const INVOICE_SORT_FIELDS: { value: InvoiceSortField; label: string }[] = [
  { value: 'created_at', label: 'Created' },
  { value: 'invoice_no', label: 'Invoice no.' },
  { value: 'business_date', label: 'Invoice date' },
  { value: 'customer', label: 'Customer' },
  { value: 'store', label: 'Store' },
  { value: 'total', label: 'Total' },
  { value: 'outstanding', label: 'Outstanding' },
  { value: 'status', label: 'Status' },
];

const SORT_FIELD_SET = new Set<string>(INVOICE_SORT_FIELDS.map(f => f.value));
/** Only a field this list knows about is ever used. */
export function isInvoiceSortField(v: unknown): v is InvoiceSortField {
  return typeof v === 'string' && SORT_FIELD_SET.has(v);
}

/** What the comparator needs that an invoice row does not carry itself. */
export type InvoiceSortContext = {
  customerName: (id: string | null | undefined) => string;
  storeName: (id: string | null | undefined) => string;
  outstanding: (invoice: any) => number;
};

const text = (s: unknown) => String(s ?? '').trim().toLowerCase();

/**
 * Order two invoices by one field.
 *
 * Two deliberate choices:
 *
 *  - a row with no recorded business date always sorts LAST, in both
 *    directions. Those are the invoices still awaiting date review, and
 *    flipping the direction should not bury them in the middle of the list;
 *  - the tie-break is always invoice_no, which is NOT NULL and UNIQUE, so
 *    equal values never reorder between renders or pages.
 */
export function compareInvoices(
  a: any, b: any, field: InvoiceSortField, dir: SortDirection, ctx: InvoiceSortContext,
): number {
  const sign = dir === 'asc' ? 1 : -1;
  let d = 0;
  switch (field) {
    case 'invoice_no':
      d = compareInvoiceNo(a.invoice_no ?? '', b.invoice_no ?? '');
      break;
    case 'created_at':
      d = text(a.created_at) < text(b.created_at) ? -1 : text(a.created_at) > text(b.created_at) ? 1 : 0;
      break;
    case 'business_date': {
      const av = a.business_date ?? null, bv = b.business_date ?? null;
      // Undated rows keep to the bottom whichever way the column is sorted.
      if (!av && !bv) { d = 0; break; }
      if (!av) return 1;
      if (!bv) return -1;
      d = av < bv ? -1 : av > bv ? 1 : 0;
      break;
    }
    case 'customer': {
      const av = text(ctx.customerName(a.customer_id)), bv = text(ctx.customerName(b.customer_id));
      d = av < bv ? -1 : av > bv ? 1 : 0;
      break;
    }
    case 'store': {
      const av = text(ctx.storeName(a.store_id)), bv = text(ctx.storeName(b.store_id));
      d = av < bv ? -1 : av > bv ? 1 : 0;
      break;
    }
    case 'total':
      d = Number(a.total_amount ?? 0) - Number(b.total_amount ?? 0);
      break;
    case 'outstanding':
      d = ctx.outstanding(a) - ctx.outstanding(b);
      break;
    case 'status':
      d = text(a.status) < text(b.status) ? -1 : text(a.status) > text(b.status) ? 1 : 0;
      break;
  }
  if (d !== 0) return d * sign;
  // Stable, unique tie-break so rows never swap places on a re-render.
  return compareInvoiceNo(b.invoice_no ?? '', a.invoice_no ?? '');
}

/** Sort a copy; the caller's array is left alone. */
export function sortInvoices<T>(
  rows: T[], field: InvoiceSortField, dir: SortDirection, ctx: InvoiceSortContext,
): T[] {
  return [...rows].sort((a, b) => compareInvoices(a, b, field, dir, ctx));
}
