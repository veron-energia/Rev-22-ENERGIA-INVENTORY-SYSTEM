/**
 * The Special page's sales and rentals: whose letterhead their receipts carry,
 * which invoice they name, the waiting list's button, and a cancelled rental
 * still with the customer (426, audit findings SALES-EXTRAS-8 and -16, and the
 * owner's answer W2-B03-RENTAL-BUTTON of 10 Oct 2026).
 */
import type { AwaitingRental } from './rentalReturn';

type DocRow = { store_id?: string | null; source_store_id?: string | null };
type StoreRow = { id: string; name?: string | null };

/**
 * The store whose letterhead, PayNow details and send log a receipt uses:
 * the store of the invoice that sold it, else the store it was released from.
 * Only an old-style sale or rental, which has neither, falls back to the
 * first store, as every receipt used to.
 */
export function docStoreId(row: DocRow | null | undefined): string | null {
  return row?.store_id ?? row?.source_store_id ?? null;
}

export function docStore<S extends StoreRow>(row: DocRow | null | undefined, stores: readonly S[], fallback?: S | null): S | null {
  const id = docStoreId(row);
  return (id ? stores.find(s => s.id === id) : undefined) ?? fallback ?? null;
}

/** The invoices the rows name: the one that sold each, and a late fee's own. */
export function docInvoiceIds(rows: readonly { invoice_id?: string | null; late_fee_invoice_id?: string | null }[]): string[] {
  const ids = new Set<string>();
  for (const r of rows) {
    if (r.invoice_id) ids.add(r.invoice_id);
    if (r.late_fee_invoice_id) ids.add(r.late_fee_invoice_id);
  }
  return [...ids];
}

/** The line a receipt prints for the invoice that sold it, or null. */
export const invoiceLine = (invoiceNo: string | null | undefined) => (invoiceNo ? `Invoice ${invoiceNo}` : null);

/** The waiting list's button: how many wait, nothing, or that it could not be read. */
export function waitingButton(count: number, failed: boolean): { label: string; tone: 'waiting' | 'none' | 'failed' } {
  if (failed) return { label: 'Could not load the waiting list. Press Refresh.', tone: 'failed' };
  if (count > 0) return { label: 'Waiting for a warehouse', tone: 'waiting' };
  return { label: 'Nothing waiting for a warehouse', tone: 'none' };
}

/**
 * A rental cancelled while still with the customer, as 417's "Receive
 * returned item" takes it: where it came from is the store it was released
 * from, or its warehouse.
 */
export function toReceive(r: {
  id: string; rental_no: string; quantity: number; invoice_item_id?: string | null;
  source_store_id?: string | null; warehouse_id?: string | null; status?: string; cancelled_at?: string | null;
}, names: { item: string; store?: string | null; warehouse?: string | null }): AwaitingRental {
  const fromStore = !!r.source_store_id;
  return {
    rental_id: r.id,
    rental_no: r.rental_no,
    quantity: Number(r.quantity) || 1,
    item: names.item,
    invoice_item_id: r.invoice_item_id ?? null,
    default_warehouse_id: fromStore ? null : (r.warehouse_id ?? null),
    default_warehouse: fromStore ? null : (names.warehouse ?? null),
    source_type: fromStore ? 'store' : r.warehouse_id ? 'warehouse' : null,
    source_name: (fromStore ? names.store : names.warehouse) ?? null,
    cancelled_at: r.cancelled_at ?? null,
    status: r.status,
  };
}
