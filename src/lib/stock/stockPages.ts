/**
 * The stock pages' own rules, kept out of the pages so they can be tested
 * (420; audit findings STOCK-2, -4, -5, -8, -10, M3).
 *
 *   - A counted total and a stock-in quantity are typed as text and must be
 *     whole numbers. An empty box is not 0.
 *   - A form is sent once, as one request with one id per opened form
 *     (newRequestId, shared with Record use), so a retry never adds stock or
 *     asks for a correction twice. After a failure that may have saved, the
 *     form is locked as it was sent (mayHaveSaved, saveFailure).
 *   - Stock of 0 or less is out of stock; below 0 is also shown as Negative.
 */
import type { ProductType } from '../../types';

export type Checked<T> = { ok: true; value: T } | { ok: false; error: string };

/** A whole number of 0 or more typed in a box: the number, '' for an empty
 *  box, or null for anything else (a decimal, a sign, letters). */
export function parseWholeNumber(text: string | null | undefined): number | '' | null {
  const t = String(text ?? '').trim();
  if (t === '') return '';
  if (!/^\d{1,7}$/.test(t)) return null;
  return Number(t);
}

// ── New Adjustment ───────────────────────────────────────────────────────────

/** The stores whose stock this person counts, as the server decides it
 *  (user_has_store_access): every store for an Owner or Admin, otherwise
 *  only the stores they work at, Managers included. my_assigned_stores()
 *  lists every open store for a Manager too, so a Manager's list is cut to
 *  their own stores here (New Adjustment; the server refuses the others with
 *  "You can only adjust your assigned store"). Store Stock uses the same list
 *  for a Manager (the Owner, 9 Oct 2026), although the server still lets a
 *  Manager read every store's stock for the other pages.
 *  null: the store list could not be read. */
export function countableStoreIds(
  role: string | null | undefined, listed: string[] | null, workAt: string[],
): string[] | null {
  if (listed == null) return null;
  if (role === 'owner' || role === 'admin') return listed;
  const mine = new Set(workAt);
  return listed.filter(id => mine.has(id));
}

export interface AdjustmentLine { product_id: string; new_qty: string }

export interface AdjustmentRequestArgs {
  p_lines: { product_id: string; new_qty: number }[];
  p_reason: string;
  p_reference: string | null;
}

/** The New Adjustment form before it is sent. A line with no product and an
 *  empty box is the empty starting row and is ignored. */
export function checkAdjustmentForm(
  locId: string, lines: AdjustmentLine[], reason: string, reference: string,
): Checked<AdjustmentRequestArgs> {
  if (!locId) return { ok: false, error: 'Select a location.' };
  const used = lines.filter(l => l.product_id || String(l.new_qty ?? '').trim() !== '');
  if (used.length === 0) return { ok: false, error: 'Select at least one product.' };
  if (used.some(l => !l.product_id)) return { ok: false, error: 'Pick a product for every counted total.' };
  const ids = used.map(l => l.product_id);
  if (new Set(ids).size !== ids.length) return { ok: false, error: 'The same product is listed more than once.' };
  const out: { product_id: string; new_qty: number }[] = [];
  for (const l of used) {
    const n = parseWholeNumber(l.new_qty);
    if (n === '') return { ok: false, error: 'Enter the counted total for every product.' };
    if (n === null) return { ok: false, error: 'Enter a whole number of 0 or more as the counted total.' };
    out.push({ product_id: l.product_id, new_qty: n });
  }
  if (!reason.trim()) return { ok: false, error: 'A reason is required.' };
  return { ok: true, value: { p_lines: out, p_reason: reason.trim(), p_reference: reference.trim() || null } };
}

/** The lines that would set stock above 0 (or stock the page could not read)
 *  to 0. Each needs a second confirmation (STOCK-2). */
export function linesSettingToZero(
  lines: { product_id: string; new_qty: number }[], live: Record<string, number> | null,
): string[] {
  return lines.filter(l => {
    if (l.new_qty !== 0) return false;
    if (live == null) return true;                 // the stock could not be read: ask
    return (live[l.product_id] ?? 0) > 0;          // no stock row is 0
  }).map(l => l.product_id);
}

/** The confirmation for a count of 0. */
export function zeroConfirmText(productNames: string[], place: string): string {
  const what = productNames.length === 1 ? productNames[0] : `${productNames.length} products (${productNames.join(', ')})`;
  return `This sets ${what} at ${place} to 0. Is that right?`;
}

/** What to say after the corrections were sent: how many, and which lines
 *  were left out because the count matched the system (STOCK-4). */
export function adjustmentSentMessage(
  sent: number, unchanged: { product_id: string; current_qty: number }[], nameOf: (id: string) => string,
): string {
  const head = `${sent} correction${sent === 1 ? '' : 's'} sent for approval.`;
  if (unchanged.length === 0) return head;
  const list = unchanged.map(u => `${nameOf(u.product_id)} (${u.current_qty})`).join(', ');
  return `${head} Left out, because the count matches the system: ${list}.`;
}

// ── Stock In ─────────────────────────────────────────────────────────────────

/** The largest quantity one Stock In line takes (the server's limit too). */
export const STOCK_IN_MAX = 999999;

export interface StockInLine { product_id: string; quantity: string }

export interface StockInArgs {
  p_lines: { product_id: string; quantity: number }[];
  p_reason: string;
  p_note: string | null;
  p_reference: string | null;
}

/** The Stock In form before it is sent. */
export function checkStockInForm(
  lines: StockInLine[], form: { reason: string; note: string; reference: string },
): Checked<StockInArgs> {
  const used = lines.filter(l => l.product_id || String(l.quantity ?? '').trim() !== '');
  if (used.length === 0) return { ok: false, error: 'Add at least one product with a quantity.' };
  if (used.some(l => !l.product_id)) return { ok: false, error: 'Pick a product for every quantity.' };
  const ids = used.map(l => l.product_id);
  if (new Set(ids).size !== ids.length) return { ok: false, error: 'The same product is listed more than once.' };
  const out: { product_id: string; quantity: number }[] = [];
  for (const l of used) {
    const n = parseWholeNumber(l.quantity);
    // Too many digits is too big, not "not a number".
    const tooBig = n === null ? /^\d+$/.test(String(l.quantity ?? '').trim()) : n !== '' && n > STOCK_IN_MAX;
    if (tooBig) return { ok: false, error: 'A quantity can be at most 999,999.' };
    if (n === '' || n === null || n <= 0) return { ok: false, error: 'Every product needs a whole quantity greater than zero.' };
    out.push({ product_id: l.product_id, quantity: n });
  }
  if (!form.reason.trim()) return { ok: false, error: 'A reason is required.' };
  return { ok: true, value: {
    p_lines: out, p_reason: form.reason.trim(),
    p_note: form.note.trim() || null, p_reference: form.reference.trim() || null,
  } };
}

// ── Stock levels (STOCK-M3) ──────────────────────────────────────────────────

export interface StockStatus { label: string; cls: string; negative: boolean }

/** 0 or less is out of stock. Below 0 (a confirmed TikTok sale may cause it)
 *  is also Negative. A threshold of 0 means no low-stock alert. */
export function stockStatus(qty: number | null | undefined, threshold: number | null | undefined): StockStatus {
  const q = Number(qty ?? 0);
  const t = Number(threshold ?? 0);
  if (q <= 0) return { label: 'Out of Stock', cls: 'badge-danger', negative: q < 0 };
  if (t > 0 && q <= t) return { label: 'Low Stock', cls: 'badge-accent', negative: false };
  return { label: 'Normal', cls: 'badge-success', negative: false };
}

/** The status as an export writes it. */
export function stockStatusText(qty: number | null | undefined, threshold: number | null | undefined): string {
  const s = stockStatus(qty, threshold);
  return s.negative ? `${s.label} (Negative ${Number(qty)})` : s.label;
}

// ── Products and prices (STOCK-8, STOCK-10) ─────────────────────────────────

/** The product type as every page shows it. */
export function productTypeLabel(t: ProductType | string | null | undefined): string {
  return t === 'own' ? 'Own' : t === 'no_commission' ? 'No commission' : '3rd Party';
}

export function productTypeBadge(t: ProductType | string | null | undefined): string {
  return t === 'own' ? 'badge-primary' : t === 'no_commission' ? 'badge-muted' : 'badge-accent';
}

/** How many of the listed products have a price at the store. A price of a
 *  deleted or switched-off product is not counted. */
export function pricedCount(productIds: string[], pricedIds: Iterable<string>): number {
  const priced = new Set(pricedIds);
  return productIds.filter(id => priced.has(id)).length;
}

// ── Adjustment requests, as the pages and exports show them ─────────────────

export interface AdjustmentPayload {
  location_type?: string; location_id?: string; product_id?: string;
  current_qty?: number; new_qty?: number; difference?: number; reference?: string | null;
}

/** "Store A" or "Warehouse W" for a request's place, with no icon. */
export function adjustmentPlace(
  p: AdjustmentPayload | null | undefined,
  storeName: (id?: string) => string | undefined, warehouseName: (id?: string) => string | undefined,
): string {
  if (!p) return '';
  if (p.location_type === 'store') return storeName(p.location_id) ?? '';
  if (p.location_type === 'warehouse') return warehouseName(p.location_id) ?? '';
  return '';
}

/** On the Approvals card: what is there now beside the count (Q11). */
export function liveNote(
  p: AdjustmentPayload | null | undefined,
  live: { live_qty: number; product_live: boolean; place_open: boolean } | undefined,
): { text: string; warn: boolean } | null {
  if (!p || !live) return null;
  if (!live.product_live) return { text: 'The product is switched off or deleted. Reject this request.', warn: true };
  if (!live.place_open) return { text: 'The place is closed or deleted. Reject this request.', warn: true };
  if (Number(live.live_qty) !== Number(p.current_qty ?? 0)) {
    return { text: `Stock changed since this count: now ${live.live_qty}. Reject it and count again.`, warn: true };
  }
  return { text: `Now ${live.live_qty}, as counted.`, warn: false };
}
