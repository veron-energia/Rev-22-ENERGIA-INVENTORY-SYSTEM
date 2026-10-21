/**
 * The correction summary (Correct Invoice → Review Changes), B16.
 *
 * CREATE-5: a summary describes the form as it was when it was asked for. Its
 * fingerprint is kept with it, and Save the correction checks the form still
 * matches; if anything changed after the review, the review is asked for
 * again rather than saving something nobody reviewed.
 *
 * CREATE-M1 (416, rule 11): sent the corrected lines, the summary says what
 * the total and status become and any refund due, worked out by the save
 * itself and then undone. Its outcome.checked is not a promise that the save
 * goes through: payment changes, and the stock and commission they move, are
 * not tried. The page says so.
 */

/** JSON with every object's keys in order, so the same form always gives the same text. */
function stable(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value as Record<string, unknown>).sort()
      .filter(k => (value as Record<string, unknown>)[k] !== undefined)
      .map(k => `${JSON.stringify(k)}:${stable((value as Record<string, unknown>)[k])}`).join(',')}}`;
  }
  return JSON.stringify(value ?? null);
}

/**
 * What the review was of: the corrected lines, the header (without the edit
 * count, which a reviewed conflict moves on purpose) and the reason. Two forms
 * with the same fingerprint save the same correction.
 */
export function correctionFingerprint(items: unknown, header: Record<string, unknown>, reason: string): string {
  const rest: Record<string, unknown> = { ...(header ?? {}) };
  delete rest.expected_edit_count;
  return stable({ items, header: rest, reason: (reason ?? '').trim() });
}

export const REVIEW_AGAIN_MESSAGE = 'You changed the invoice after reviewing it. Review the changes again.';

export type CorrectionOutcome = {
  checked: boolean; refusal?: string;
  total_before?: number | string; total_after?: number | string;
  status_before?: string; status_after?: string;
  outstanding_after?: number | string; refund_due_after?: number | string;
  lines?: { change: 'added' | 'removed' | 'changed'; label?: string | null;
            quantity_before?: number | null; quantity_after?: number | null;
            charged_before?: number | string | null; charged_after?: number | string | null }[];
};

const STATUS_WORDS: Record<string, string> = {
  draft: 'Draft', unpaid: 'Unpaid', partially_paid: 'Part paid', paid: 'Paid', completed_foc: 'FOC (completed)',
  cancelled: 'Cancelled', refunded: 'Refunded', cancellation_requested: 'Cancellation requested', refund_requested: 'Refund requested',
};
const money = (v: unknown) => `S$${(Math.round((Number(v) || 0) * 100) / 100).toFixed(2)}`;
const statusWords = (s?: string) => STATUS_WORDS[String(s ?? '')] ?? String(s ?? '').replace(/_/g, ' ');

/**
 * The outcome in short lines for the summary, or null when there is none to
 * show (no corrected lines were sent, or the try was refused: the refusal is
 * in needs_review already).
 */
export function outcomeLines(o: CorrectionOutcome | null | undefined): { total: string; status: string; money: string[]; lines: string[]; note: string } | null {
  if (!o || !o.checked) return null;
  const before = Number(o.total_before ?? 0), after = Number(o.total_after ?? 0);
  const total = Math.abs(before - after) < 0.005 ? `Total stays ${money(after)}` : `Total ${money(before)} → ${money(after)}`;
  const status = o.status_before === o.status_after
    ? `Status stays ${statusWords(o.status_after)}`
    : `Status ${statusWords(o.status_before)} → ${statusWords(o.status_after)}`;
  const moneyRows: string[] = [];
  if (Number(o.outstanding_after ?? 0) > 0.005) moneyRows.push(`${money(o.outstanding_after)} owing`);
  if (Number(o.refund_due_after ?? 0) > 0.005) moneyRows.push(`${money(o.refund_due_after)} becomes refund due`);
  const lines = (o.lines ?? []).map(l => {
    const name = l.label || 'A line';
    if (l.change === 'added') return `${name}: added, ${money(l.charged_after)}`;
    if (l.change === 'removed') return `${name}: removed (was ${money(l.charged_before)})`;
    const qty = l.quantity_before !== l.quantity_after ? `quantity ${l.quantity_before} → ${l.quantity_after}, ` : '';
    return `${name}: ${qty}${money(l.charged_before)} → ${money(l.charged_after)}`;
  });
  return {
    total, status, money: moneyRows, lines,
    // Rule 11: what was checked, and what was not.
    note: 'Checked as the save checks them: the lines, discounts, stock, goods kept, birthday discounts and the vouchers this gives. Payment changes are checked only when you save, so the save can still be refused.',
  };
}
