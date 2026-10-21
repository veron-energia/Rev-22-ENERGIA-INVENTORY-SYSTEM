/**
 * What the customer's copies of an invoice say (B16): the printed copy, the
 * PDF and the image, and so the WhatsApp and email link to the PDF. Shared so
 * the copies cannot disagree.
 */

export type CopyRow = [string, string];

const cents = (n: unknown) => Math.round((Number(n) || 0) * 100);
const sgd = (c: number) => `S$${(c / 100).toFixed(2)}`;

/**
 * AFTER-10: the money paid and given back, from invoice_financial_position.
 * 'Paid' is every receipt (what the payment rows add up to); then, when money
 * went back, 'Refunded' and 'Net paid' (what the invoice still holds); then
 * 'Refund due' when some is still owed back. Nothing paid and nothing
 * refunded: no rows. With no refund, 'Paid' is already the net figure, so it
 * is not said twice. `minus` is the sign the copy can draw ('-' on the PDF,
 * whose built-in fonts have no other).
 */
export function copyMoneyRows(p: { paid: unknown; refunded?: unknown; netPaid?: unknown; refundDue?: unknown; minus?: string }): CopyRow[] {
  const minus = p.minus ?? '−';
  const paid = cents(p.paid), refunded = cents(p.refunded);
  const net = p.netPaid == null ? paid - refunded : cents(p.netPaid);
  const due = cents(p.refundDue);
  const rows: CopyRow[] = [];
  if (paid > 0 || refunded > 0) rows.push(['Paid', sgd(paid)]);
  if (refunded > 0) {
    rows.push(['Refunded', `${minus}${sgd(refunded)}`]);
    rows.push(['Net paid', sgd(net)]);
  }
  if (due > 0) rows.push(['Refund due', sgd(due)]);
  return rows;
}

/**
 * The Owner, 9 Oct 2026 (Q7 = option 1): an FOC reason is internal. Every copy
 * says only 'FOC' and its value: "FOC (full line) — value S$x" or
 * "FOC 2 of 3 free — value S$x". Null when the line has no FOC.
 */
export function focCopyNote(line: { quantity?: unknown; foc_quantity?: unknown; foc_amount?: unknown }): string | null {
  const qty = Number(line.quantity ?? 0), free = Number(line.foc_quantity ?? 0);
  if (!(free > 0)) return null;
  return `FOC ${free === qty ? '(full line)' : `${free} of ${qty} free`} — value ${sgd(cents(line.foc_amount))}`;
}

/**
 * The Owner, 18 Oct 2026 (W4-B16-PRICE-REASON): the reason staff type when
 * they change a price by hand is internal, as an FOC reason is (Q7). Every
 * copy (the print, the PDF, the image, and so WhatsApp and email) says only
 * 'Manual price override'; the reason shows on screen for staff. Null when
 * the price was not changed by hand.
 */
export function priceOverrideCopyNote(line: { price_overridden?: unknown; override_reason?: unknown }): string | null {
  return line.price_overridden ? 'Manual price override' : null;
}

/**
 * AFTER-9: what is inside a promotion line, as the printed copy lists it:
 * each fixed item "(included)" for the line's quantity, each item picked at
 * the till "(chosen)", and the top-up when there is one.
 */
export function promotionCopyNotes(
  lineQuantity: number,
  fixed: { quantity?: unknown }[],
  chosen: { quantity?: unknown }[],
  nameOf: (x: any) => string,
  topup: unknown,
): string[] {
  return [
    ...fixed.map(f => `${nameOf(f)} × ${Number(f.quantity ?? 0) * lineQuantity} (included)`),
    ...chosen.map(s => `${nameOf(s)} × ${Number(s.quantity ?? 0)} (chosen)`),
    ...(cents(topup) > 0 ? [`incl. top-up ${sgd(cents(topup))}`] : []),
  ];
}

/**
 * AFTER-9: an exchange invoice says so on every copy: a note under the
 * header, its discount is the exchange credit, and its total the net top-up.
 */
export function exchangeCopyLabels(ex: { found?: boolean; original_invoice_no?: string | null } | null | undefined): {
  headerNote: string | null; discountLabel: string; totalLabel: string;
} {
  if (!ex?.found) return { headerNote: null, discountLabel: 'Discount', totalLabel: 'Total' };
  return {
    headerNote: `Exchange invoice: replaces items from ${ex.original_invoice_no ?? 'the original invoice'}`,
    discountLabel: 'Exchange credit applied',
    totalLabel: 'Net top-up',
  };
}

/**
 * CREATE-18: text for any place in the printed copy's HTML, attributes
 * included: &, <, >, " and ' are all escaped, so a value such as a logo's
 * address cannot end the attribute it sits in.
 */
export function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
