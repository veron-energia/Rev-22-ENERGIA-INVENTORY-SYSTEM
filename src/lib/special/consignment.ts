/**
 * Consignment products on the Special page (494, the user's answers of 6 Nov
 * 2026): a supplier can send one directly to the customer. A paid sale of one
 * waits in "Waiting for a warehouse" like any other, and an Owner or Manager
 * can choose one of its suppliers there instead of a warehouse or a store. Its
 * suppliers are the ones linked to its product on the Products page.
 */
export type SupplierRow = {
  id: string; name: string; phone?: string | null;
  is_active?: boolean | null; deleted_at?: string | null;
};
export type ProductSupplierRow = { product_id: string; supplier_id: string };

/** The suppliers a product can go to: linked on the Products page and still in use. */
export function suppliersOf(
  productId: string | null | undefined,
  links: readonly ProductSupplierRow[],
  suppliers: readonly SupplierRow[],
): SupplierRow[] {
  if (!productId) return [];
  const linked = new Set(links.filter(l => l.product_id === productId).map(l => l.supplier_id));
  return suppliers
    .filter(s => linked.has(s.id) && !s.deleted_at && s.is_active !== false)
    .sort((a, b) => a.name.localeCompare(b.name));
}

// The waiting list's dropdown holds "type:id" for a warehouse or a store; a
// supplier is one more type there.
const SUPPLIER_PREFIX = 'supplier:';
export const supplierChoice = (id: string) => `${SUPPLIER_PREFIX}${id}`;
export const supplierIdOfChoice = (choice: string | null | undefined): string | null =>
  choice?.startsWith(SUPPLIER_PREFIX) ? choice.slice(SUPPLIER_PREFIX.length) : null;

export const supplierOptionLabel = (s: SupplierRow) => `🚚 ${s.name}${s.phone ? ` — ${s.phone}` : ''}`;

/** Said beside a supplier's sale once its invoice is taken back: a refund moves
 *  no stock and leaves the sale "Released", and the supplier still has to be told. */
export function invoiceTakenBack(status: string | null | undefined): string | null {
  return status === 'refunded' ? 'Invoice refunded' : status === 'cancelled' ? 'Invoice cancelled' : null;
}
