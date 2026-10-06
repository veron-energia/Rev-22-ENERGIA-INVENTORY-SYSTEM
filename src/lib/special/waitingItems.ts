import { RENTAL_STATUS_LABELS, type RentalStatus } from '../../types';

/**
 * Special sales and rentals still waiting for a warehouse, and what a refund
 * does with them (393, the Owner's rules of 6 Oct 2026).
 *
 * A paid invoice's special products and rentals wait on the Special page until
 * an Owner or Manager releases them. A refund that closes the invoice, or a
 * cancellation, cancels them. A partial refund asks, for each one, "Is the
 * customer still taking this item?": Yes keeps it waiting, No cancels it when
 * the refund is recorded. The answers travel with the refund's lines as
 *   waiting: [{ doc_id, still_taking }]
 * on the first line, and the database checks them.
 *
 * Kept free of React and of the database, so the refund screens, the Special
 * page and the tests share one copy of the rules.
 */

export type WaitingItem = {
  doc_id: string;
  doc_no: string;
  kind: 'special_sale' | 'rental';
  invoice_item_id: string | null;
  /** The product's own name, for when the invoice line has none to offer. */
  product_name: string | null;
};
/** By item id: true = the customer is still taking it. */
export type WaitingAnswers = Record<string, boolean>;
export type WaitingAnswer = { doc_id: string; still_taking: boolean };

type DocRow = {
  id: string; status: string; warehouse_id?: string | null; source_store_id?: string | null;
  invoice_item_id?: string | null; sale_no?: string; rental_no?: string;
  special_products?: { name?: string | null } | null;
};

/** Released items have a warehouse or a store; waiting ones have neither. */
const unreleased = (r: DocRow) => !r.warehouse_id && !r.source_store_id;

/** An invoice's waiting items, from its special_sales and rentals rows. */
export function waitingItemsFromRows(sales: DocRow[] | null | undefined, rentals: DocRow[] | null | undefined): WaitingItem[] {
  const out: WaitingItem[] = [
    ...(sales ?? []).filter(r => r.status === 'pending' && unreleased(r)).map(r => ({
      doc_id: r.id, doc_no: r.sale_no ?? '', kind: 'special_sale' as const,
      invoice_item_id: r.invoice_item_id ?? null, product_name: r.special_products?.name ?? null })),
    ...(rentals ?? []).filter(r => r.status === 'awaiting_fulfilment' && unreleased(r)).map(r => ({
      doc_id: r.id, doc_no: r.rental_no ?? '', kind: 'rental' as const,
      invoice_item_id: r.invoice_item_id ?? null, product_name: r.special_products?.name ?? null })),
  ];
  return out.sort((a, b) => a.doc_no.localeCompare(b.doc_no));
}

/** The items nobody has answered for yet. */
export function unansweredItems(items: WaitingItem[], answers: WaitingAnswers): WaitingItem[] {
  return items.filter(i => typeof answers[i.doc_id] !== 'boolean');
}

/** The answers as the refund carries them, one per waiting item. */
export function waitingAnswerList(items: WaitingItem[], answers: WaitingAnswers): WaitingAnswer[] {
  return items.filter(i => typeof answers[i.doc_id] === 'boolean')
    .map(i => ({ doc_id: i.doc_id, still_taking: answers[i.doc_id] }));
}

/**
 * The refund's lines with the answers on the first of them. Lines are
 * returned as they came when there is nothing to answer, so a refund with no
 * waiting item sends exactly what it always sent.
 */
export function withWaitingAnswers<T extends object>(lines: T[], items: WaitingItem[], answers: WaitingAnswers): (T & { waiting?: WaitingAnswer[] })[] {
  const list = waitingAnswerList(items, answers);
  if (!list.length || !lines.length) return lines;
  return [{ ...lines[0], waiting: list }, ...lines.slice(1)];
}

/** The answers a request was raised with, read back from its lines. */
export function waitingAnswersOf(lines: unknown): WaitingAnswer[] {
  if (!Array.isArray(lines)) return [];
  return lines.flatMap(l => Array.isArray((l as any)?.waiting) ? (l as any).waiting : [])
    .filter((a: any) => typeof a?.doc_id === 'string' && typeof a?.still_taking === 'boolean');
}

/** An item as staff read it: the invoice line's name where there is one. */
export function waitingItemLabel(item: WaitingItem, lineName?: (invoiceItemId: string) => string | undefined): string {
  const name = (item.invoice_item_id && lineName?.(item.invoice_item_id)) || item.product_name
    || (item.kind === 'rental' ? 'Rental' : 'Special product');
  return item.doc_no ? `${name} · ${item.doc_no}` : name;
}

// ── Labels on the Special page ───────────────────────────────────────────────

/**
 * Why an item was cancelled, from the note written with it: "Cancelled
 * (refunded): …" since 393, "Cancelled with its invoice: …" from a rental
 * cancelled with its invoice (300). Null when the note does not say.
 */
export function cancelledBecause(notes: string | null | undefined): string | null {
  const text = notes ?? '';
  const m = /(?:^|\n)Cancelled \(([^)\n]+)\)/.exec(text);
  if (m) return m[1];
  if (/(?:^|\n)Cancelled with its invoice/.test(text)) return 'invoice cancelled';
  return null;
}

export type BadgeTone = 'success' | 'primary' | 'accent' | 'danger' | 'muted';
const humanise = (s: string) => s ? s.charAt(0).toUpperCase() + s.slice(1).replace(/_/g, ' ') : '—';

/** A special sale's status as the Sales tab shows it. */
export function specialSaleBadge(s: { status: string; notes?: string | null; stock_returned?: boolean | null }): { label: string; tone: BadgeTone } {
  switch (s.status) {
    case 'pending': return { label: 'Waiting for a warehouse', tone: 'primary' };
    case 'completed': return { label: 'Released', tone: 'success' };
    case 'paid': return { label: 'Paid', tone: 'success' };
    case 'cancelled': {
      const why = cancelledBecause(s.notes);
      return { label: `Cancelled${why ? ` (${why})` : ''}${s.stock_returned ? ' · stock back' : ''}`, tone: 'muted' };
    }
    default: return { label: humanise(s.status), tone: 'muted' };
  }
}

/** A rental's status as the Rentals tab shows it; a cancelled one says why. */
export function rentalStatusLabel(status: RentalStatus | string, notes?: string | null): string {
  const base = RENTAL_STATUS_LABELS[status as RentalStatus] ?? humanise(String(status));
  if (status !== 'cancelled') return base;
  const why = cancelledBecause(notes);
  return why ? `${base} (${why})` : base;
}
