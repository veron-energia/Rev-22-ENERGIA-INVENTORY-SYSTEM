// What the affiliate portal shows, worked out from what its RPCs send. Kept
// apart from affiliatePortal.ts (which holds the API client) so it can be
// tested on its own.

// Maps the raw commission_status enum to affiliate-friendly wording.
// 'blocked' is commission withheld because the account was not activated
// (410: shown as such, not as "Reversed"); 'cancelled' is the older word for it.
export const statusLabel = (s?: string): { label: string; cls: string } => {
  switch (s) {
    case 'paid': return { label: 'Paid', cls: 'badge-success' };
    case 'partially_paid': return { label: 'Partly paid', cls: 'badge-warning' };
    case 'earned': return { label: 'Unpaid', cls: 'badge-warning' };
    case 'reversed': return { label: 'Reversed', cls: 'badge-muted' };
    case 'blocked':
    case 'cancelled': return { label: 'Blocked', cls: 'badge-danger' };
    default: return { label: s ?? '—', cls: 'badge-muted' };
  }
};

/** The earnings summary as the portal shows it: never a negative Unpaid.
 *  Commission already paid out and then taken back is a deduction recovered
 *  from later commission (410). Before 410 the server sent no deduction and a
 *  negative unpaid; that is shown the same way. */
export function earningsFigures(summary: { unpaid?: number | string | null; deduction?: number | string | null } | null | undefined) {
  const unpaidCents = Math.round(Number(summary?.unpaid ?? 0) * 100);
  const sentDeduction = summary?.deduction;
  const deductionCents = sentDeduction !== undefined && sentDeduction !== null
    ? Math.round(Number(sentDeduction) * 100) : Math.max(-unpaidCents, 0);
  return { unpaid: Math.max(unpaidCents, 0) / 100, deduction: Math.max(deductionCents, 0) / 100 };
}

/** A deduction settled with Energia (414): paid back, written off, or taken
 *  off a payment outside the app. The summary sends the amount only (never
 *  the note or how it was settled); 0 before 414. Shown so the figures add up:
 *  Lifetime − Paid + settled = Unpaid − Deduction. */
export function settledFigure(summary: { settled?: number | string | null } | null | undefined): number {
  return Math.max(Math.round(Number(summary?.settled ?? 0) * 100), 0) / 100 || 0;
}

/** Said beside a deduction, on the portal. */
export const DEDUCTION_NOTE =
  'Commission already paid to you was taken back, because a purchase was refunded, cancelled or changed. ' +
  'It is deducted from your next commission before anything more is paid out.';
