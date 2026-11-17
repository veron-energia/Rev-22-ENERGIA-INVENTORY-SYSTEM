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
 * 'Refund due' when some is still owed back. With no refund, 'Paid' is already
 * the net figure, so it is not said twice. `minus` is the sign the copy can
 * draw ('-' on the PDF, whose built-in fonts have no other).
 *
 * The user, 17 Nov 2026: every copy also says 'Balance due', right after 'Paid'
 * (after 'Net paid' when money went back, before 'Refund due'): the figure the
 * invoice screen shows as 'Balance due' (the position's `outstanding`), even
 * when it is S$0.00, and the rows are there even when nothing is paid yet
 * ('Paid S$0.00'). `outstanding` is never negative (the position's own
 * greatest(...,0), and 0 for a cancelled or refunded invoice), so it is shown
 * as it is. When the position could not be read (`outstanding` missing), no
 * 'Balance due' is guessed and the rows are as before: nothing paid and
 * nothing refunded, no rows.
 */
export function copyMoneyRows(p: { paid: unknown; refunded?: unknown; netPaid?: unknown; refundDue?: unknown; outstanding?: unknown; minus?: string }): CopyRow[] {
  const minus = p.minus ?? '−';
  const paid = cents(p.paid), refunded = cents(p.refunded);
  const net = p.netPaid == null ? paid - refunded : cents(p.netPaid);
  const due = cents(p.refundDue);
  const known = p.outstanding != null && p.outstanding !== '' && Number.isFinite(Number(p.outstanding));
  const rows: CopyRow[] = [];
  if (known || paid > 0 || refunded > 0) rows.push(['Paid', sgd(paid)]);
  if (refunded > 0) {
    rows.push(['Refunded', `${minus}${sgd(refunded)}`]);
    rows.push(['Net paid', sgd(net)]);
  }
  if (known) rows.push(['Balance due', sgd(cents(p.outstanding))]);
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

/** 456 (the Owner, 22 Oct 2026): the most a note printed on the invoice may hold (the server refuses more). */
export const PRINT_NOTE_MAX = 500;

/**
 * A note as every copy shows it: Windows line breaks made plain, spaces at the
 * ends of lines dropped, two or more blank lines kept as one, and nothing
 * around it. Null when nothing is left.
 */
function copyNoteText(value: unknown): string | null {
  const t = String(value ?? '').replace(/\r\n?/g, '\n').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
  return t ? t : null;
}

/**
 * 456 (the Owner, 22 Oct 2026): the note every copy of an invoice prints (both
 * halves of the paper copy, the PDF, the image, and so WhatsApp and email),
 * under "Note" above the signatures, and the invoice screen shows: the
 * invoice's print_note, never its Notes. Notes are internal ("Internal notes
 * (not printed)"): they hold what the system writes (website order and Stripe
 * ids, exchange and top-up reasons, late-fee and voucher-claim references).
 */
export function printedNote(inv: { print_note?: unknown } | null | undefined): string | null {
  return copyNoteText(inv?.print_note);
}

/**
 * 456 (item 6, the exchange half): an exchange's own note
 * (product_exchanges.notes, which exchange_invoice_details returns as 'notes'
 * from 455), printed under "Exchange Details" on its replacement invoice.
 */
export function exchangeNote(ex: { found?: boolean; notes?: unknown } | null | undefined): string | null {
  return ex?.found ? copyNoteText(ex.notes) : null;
}

/** A note in the printed copy's HTML: escaped (CREATE-18), its line breaks kept. */
export function noteHtml(note: string): string {
  return escapeHtml(note).replace(/\n/g, '<br/>');
}

/**
 * The user, 17 Nov 2026: what the OFFICE COPY of the paper print adds in one
 * block, "Office notes (not on the customer copy)", right above the
 * signatures. THIS HELPER IS OFFICE-ONLY: its lines are internal (staff's own
 * and the system's notes, the reasons for a discount, an FOC, a price change,
 * a refund and a payment correction) and must never reach the customer's half,
 * the PDF, the image, WhatsApp or email. The earlier rules stand for those
 * copies: an FOC reason (Q7) and a price-change reason are internal.
 *
 * Plain text, one entry per line, each only when it has text (the page escapes
 * them with noteHtml, which keeps a multi-line note's breaks):
 *   Internal notes: <invoices.notes>, printed as it is (the system writes ids
 *     and references into it);
 *   Discount reason: <invoices.manual_discount_reason>;
 *   per item line, one entry for each, numbered as the copy numbers them
 *     ("Line 2 · Name · Discount reason: ..."):
 *     Discount reason, FOC reason (the reason's name, then the text typed with
 *     it; a saved FOC reason already starts with its name, so it is not said
 *     twice, and one no longer in the active list still shows by its saved
 *     text), Price change reason;
 *   Refund <date> (S$x): <reason>, each refund that has a reason;
 *   Payment correction <date>: <reason>, each payment row that has one.
 * Empty array: no block at all.
 */
export function officeNoteLines(d: {
  invoice?: { notes?: unknown; manual_discount_reason?: unknown } | null;
  items?: { line_discount_reason?: unknown; foc_reason_id?: unknown; foc_reason?: unknown; override_reason?: unknown }[] | null;
  /** The printed name of item line n (0-based): what the copy shows for it. */
  lineName?: (index: number) => string;
  /** An FOC reason's name by id, when it is in the list the page holds. */
  focReasonName?: (id: string) => string | null | undefined;
  refunds?: { reason?: unknown; amount?: unknown; created_at?: unknown }[] | null;
  payments?: { correction_reason?: unknown; effective_at?: unknown; created_at?: unknown }[] | null;
  /** A stored timestamp as the copy prints a day. */
  day?: (stamp: unknown) => string;
}): string[] {
  const out: string[] = [];
  const day = d.day ?? ((x: unknown) => String(x ?? ''));
  const notes = copyNoteText(d.invoice?.notes);
  if (notes) out.push(`Internal notes: ${notes}`);
  const discount = copyNoteText(d.invoice?.manual_discount_reason);
  if (discount) out.push(`Discount reason: ${discount}`);
  (d.items ?? []).forEach((it, i) => {
    const parts: string[] = [];
    const dr = copyNoteText(it.line_discount_reason);
    if (dr) parts.push(`Discount reason: ${dr}`);
    const typed = copyNoteText(it.foc_reason);
    const name = it.foc_reason_id ? copyNoteText(d.focReasonName?.(String(it.foc_reason_id))) : null;
    const foc = name && typed ? (typed === name || typed.startsWith(`${name} — `) ? typed : `${name} — ${typed}`) : (name ?? typed);
    if (foc) parts.push(`FOC reason: ${foc}`);
    const pr = copyNoteText(it.override_reason);
    if (pr) parts.push(`Price change reason: ${pr}`);
    const label = copyNoteText(d.lineName?.(i));
    for (const x of parts) out.push(`Line ${i + 1}${label ? ` · ${label}` : ''} · ${x}`);
  });
  for (const r of d.refunds ?? []) {
    const why = copyNoteText(r.reason);
    if (why) out.push(`Refund ${day(r.created_at)} (${sgd(cents(r.amount))}): ${why}`);
  }
  // One correction writes several payment rows (its reversal and each
  // replacement), every one with the same reason, at the same moment: dated by
  // when it was made (not the payment's own date, which the rows may differ
  // on), each correction says its reason once.
  const corrections = new Set<string>();
  for (const p of d.payments ?? []) {
    const why = copyNoteText(p.correction_reason);
    if (!why) continue;
    const line = `Payment correction ${day(p.created_at || p.effective_at)}: ${why}`;
    if (!corrections.has(line)) { corrections.add(line); out.push(line); }
  }
  return out;
}
