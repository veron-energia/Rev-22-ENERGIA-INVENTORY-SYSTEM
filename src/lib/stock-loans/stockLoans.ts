/**
 * Record use and stock lent out (401), as the Store and Warehouse stock pages
 * and the customer's profile carry them. Pure: no React, no database.
 *
 * The Owner's rules of 6 Oct 2026: Record use sends every line at once (one
 * transaction on the server) with one request id per form, so pressing again
 * after a lost answer records nothing twice. A loan names a customer or a
 * typed name, an expected return date (required, not in the past) and its
 * product lines; lent stock leaves the shelf. Taking back: part returns, into
 * any store (a warehouse only for Owner/Manager), the rest closed as used /
 * given away or lost / damaged; an item back damaged goes back to stock or is
 * recorded as used. Overdue: still open and due before today (Singapore).
 */

export type LocationType = 'store' | 'warehouse';
export type LineDraft = { product_id: string; quantity: number };
export type LinePayload = { product_id: string; quantity: number };
type Checked<T> = { ok: true; value: T } | { ok: false; error: string };

export interface LoanLine {
  line_id: string; product_id: string; product_name: string; sku: string | null;
  qty_out: number; qty_returned: number; qty_used: number; qty_lost: number; outstanding: number;
}
export interface LoanEvent {
  id: string; line_id: string; product_name: string;
  outcome: 'returned' | 'used' | 'lost'; quantity: number; condition: 'good' | 'damaged' | null;
  location_type: LocationType | null; location_name: string | null;
  note: string | null; recorded_at: string; recorded_by_name: string | null;
}
export interface StockLoan {
  id: string; loan_no: string; status: 'open' | 'closed';
  location_type: LocationType; location_id: string; location_name: string;
  customer_id: string | null; borrower: string; borrower_phone: string | null; is_affiliate: boolean;
  purpose: string | null; lent_at: string; lent_by_name: string | null;
  expected_return_date: string; overdue: boolean; days_overdue: number; closed_at: string | null;
  outstanding: number; lines: LoanLine[]; events: LoanEvent[];
}

/** One new id per form; kept across retries of that form. */
export function newRequestId(): string {
  const c = (globalThis as any).crypto;
  if (c?.randomUUID) return c.randomUUID();
  // Fallback for an old browser: RFC 4122 version 4 from Math.random.
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, ch => {
    const r = Math.random() * 16 | 0;
    return (ch === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

type SaveError = { message?: string; code?: string | null };

/**
 * A failure that may have saved: no answer from the database (a dropped
 * connection, a timeout). A refusal from the database has a code and saved
 * nothing, the whole call being one transaction. After an uncertain failure
 * the form is locked, so pressing again sends exactly what may have been
 * saved: the server answers a repeat of the same form with what it recorded,
 * and refuses the same request id with changed details.
 */
export const mayHaveSaved = (error: SaveError) => !error.code;

/** What to tell staff when a save fails (see mayHaveSaved). */
export function saveFailure(error: SaveError, pressAgain: string): string {
  const message = (error.message ?? '').trim();
  if (!mayHaveSaved(error)) {
    // The server's "already saved as …, and has been changed since: nothing
    // more was recorded" says itself what was and was not saved.
    return /already saved/i.test(message) ? message : `${message} Nothing was saved.`;
  }
  return `${message || 'The connection failed.'} It may or may not have been saved. ${pressAgain}`;
}

/** "USE-000001 (Mat ×1), USE-000002 (Lamp ×2)": what a Record use saved. */
export function usesSummary(uses: { use_no: string; product_id: string; quantity: number }[],
  nameOf: (productId: string) => string): string {
  return uses.map(u => `${u.use_no} (${nameOf(u.product_id)} ×${u.quantity})`).join(', ');
}

/** "Mat ×2, Lamp ×1": what went out on a loan. */
export const loanItemsSummary = (loan: Pick<StockLoan, 'lines'> | null | undefined) =>
  (loan?.lines ?? []).map(l => `${l.product_name} ×${l.qty_out}`).join(', ');

/** Today in Singapore, YYYY-MM-DD (the database's sg_today()). */
export function sgToday(now: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

/** "13 Oct 2026" from a YYYY-MM-DD or a timestamp. */
export function formatDay(value: string | null | undefined): string {
  if (!value) return '—';
  const d = /^\d{4}-\d{2}-\d{2}$/.test(value) ? new Date(`${value}T00:00:00+08:00`) : new Date(value);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString('en-GB', { timeZone: 'Asia/Singapore', day: '2-digit', month: 'short', year: 'numeric' });
}

export const blankLine = (): LineDraft => ({ product_id: '', quantity: 0 });

const wholePositive = (n: unknown) => typeof n === 'number' && Number.isInteger(n) && n > 0 && n <= 999999;

/**
 * The product lines of a form. A row with neither product nor quantity is
 * ignored (the empty row the form starts with); anything else must be a
 * product with a whole quantity above zero, each product once.
 */
export function checkLines(lines: LineDraft[]): Checked<LinePayload[]> {
  const used = lines.filter(l => l.product_id || (l.quantity && l.quantity !== 0));
  if (used.some(l => !l.product_id)) return { ok: false, error: 'Pick a product for every quantity.' };
  if (used.some(l => !wholePositive(l.quantity))) return { ok: false, error: 'Every product needs a whole quantity greater than zero.' };
  if (used.length === 0) return { ok: false, error: 'Add at least one product with a quantity.' };
  const ids = used.map(l => l.product_id);
  if (new Set(ids).size !== ids.length) return { ok: false, error: 'The same product is listed more than once.' };
  return { ok: true, value: used.map(l => ({ product_id: l.product_id, quantity: l.quantity })) };
}

/** Record use: the lines and a reason; the note is optional. */
export function checkRecordUse(lines: LineDraft[], reason: string, note: string) {
  const checked = checkLines(lines);
  if (!checked.ok) return checked;
  if (!reason.trim()) return { ok: false as const, error: 'A reason is required.' };
  return { ok: true as const, value: { p_lines: checked.value, p_reason: reason.trim(), p_note: note.trim() || null } };
}

export type BorrowerMode = 'customer' | 'name';
export interface LendDraft {
  lines: LineDraft[];
  borrowerMode: BorrowerMode;
  customerId: string;
  borrowerName: string;
  expectedReturn: string;   // YYYY-MM-DD
  purpose: string;
}

/**
 * A loan: the lines (and, when known, enough stock for each), a customer or a
 * typed name, and an expected return date that is today or later.
 * `available` and `nameOf` let the form say "Only 2 here" before the server does.
 */
export function checkLend(d: LendDraft, today: string,
  available?: Record<string, number>, nameOf?: (productId: string) => string) {
  const checked = checkLines(d.lines);
  if (!checked.ok) return checked;
  if (available) {
    for (const l of checked.value) {
      const have = available[l.product_id] ?? 0;
      if (l.quantity > have) {
        return { ok: false as const, error: `Only ${have} of "${nameOf ? nameOf(l.product_id) : 'this product'}" in stock here, so ${l.quantity} cannot be lent.` };
      }
    }
  }
  const name = d.borrowerName.replace(/\s+/g, ' ').trim();
  if (d.borrowerMode === 'customer' && !d.customerId) return { ok: false as const, error: 'Pick the customer who is borrowing it.' };
  if (d.borrowerMode === 'name' && !name) return { ok: false as const, error: 'Type who is borrowing it (a name, a roadshow, an event).' };
  if (d.borrowerMode === 'name' && name.length > 120) return { ok: false as const, error: 'The borrower’s name is too long (120 characters at most).' };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d.expectedReturn)) return { ok: false as const, error: 'An expected return date is required.' };
  if (d.expectedReturn < today) return { ok: false as const, error: 'The expected return date cannot be in the past.' };
  if (d.purpose.trim().length > 500) return { ok: false as const, error: 'The purpose is too long (500 characters at most).' };
  return {
    ok: true as const,
    value: {
      p_lines: checked.value,
      p_expected_return_date: d.expectedReturn,
      p_customer_id: d.borrowerMode === 'customer' ? d.customerId : null,
      p_borrower_name: d.borrowerMode === 'name' ? name : null,
      p_purpose: d.purpose.trim() || null,
    },
  };
}

export const outstanding = (l: Pick<LoanLine, 'qty_out' | 'qty_returned' | 'qty_used' | 'qty_lost'>) =>
  Math.max(0, l.qty_out - l.qty_returned - l.qty_used - l.qty_lost);

/** Open and due before today. */
export const isOverdue = (loan: Pick<StockLoan, 'status' | 'expected_return_date'>, today: string) =>
  loan.status === 'open' && loan.expected_return_date < today;

export function daysOverdue(loan: Pick<StockLoan, 'status' | 'expected_return_date'>, today: string): number {
  if (!isOverdue(loan, today)) return 0;
  const a = Date.parse(`${loan.expected_return_date}T00:00:00Z`), b = Date.parse(`${today}T00:00:00Z`);
  return Math.round((b - a) / 86400000);
}

/** "Out on loan" per product: what is still out on the open loans. */
export function outByProduct(loans: Pick<StockLoan, 'status' | 'lines'>[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const loan of loans) {
    if (loan.status !== 'open') continue;
    for (const l of loan.lines) {
      const n = outstanding(l);
      if (n > 0) out[l.product_id] = (out[l.product_id] ?? 0) + n;
    }
  }
  return out;
}

export const borrowerLabel = (loan: Pick<StockLoan, 'borrower' | 'is_affiliate' | 'customer_id'>) =>
  `${loan.borrower}${loan.is_affiliate ? ' · Affiliate' : loan.customer_id ? ' · Customer' : ''}`;

export function eventLabel(e: Pick<LoanEvent, 'outcome' | 'condition'>): string {
  if (e.outcome === 'returned') return e.condition === 'damaged' ? 'Returned damaged, back in stock' : 'Returned';
  if (e.outcome === 'used') return e.condition === 'damaged' ? 'Came back damaged, recorded as used' : 'Used / given away';
  return 'Lost / damaged';
}

/** What staff enter for one line when taking a loan back. */
export interface TakeBackDraft { returned: number; damagedToStock: number; damagedUsed: number; used: number; lost: number }
export const TAKE_BACK_FIELDS: { key: keyof TakeBackDraft; label: string; hint: string }[] = [
  { key: 'returned', label: 'Returned', hint: 'back in stock' },
  { key: 'damagedToStock', label: 'Damaged, to stock', hint: 'came back damaged, back in stock' },
  { key: 'damagedUsed', label: 'Damaged, as used', hint: 'came back damaged, recorded as used' },
  { key: 'used', label: 'Used / given away', hint: 'not coming back' },
  { key: 'lost', label: 'Lost / damaged', hint: 'not coming back' },
];
export const blankTakeBack = (): TakeBackDraft => ({ returned: 0, damagedToStock: 0, damagedUsed: 0, used: 0, lost: 0 });
const draftTotal = (d: TakeBackDraft) => d.returned + d.damagedToStock + d.damagedUsed + d.used + d.lost;

/** "Everything came back": every line's outstanding as returned. */
export function takeBackAll(loan: Pick<StockLoan, 'lines'>): Record<string, TakeBackDraft> {
  return Object.fromEntries(loan.lines.map(l => [l.line_id, { ...blankTakeBack(), returned: outstanding(l) }]));
}

export type TakeBackEntry = {
  line_id: string; outcome: 'returned' | 'used' | 'lost'; quantity: number;
  condition?: 'good' | 'damaged'; location_type?: LocationType; location_id?: string;
};

/**
 * The entries return_stock_loan takes, from the form. Nothing may account for
 * more than is still out on its line; a return needs the place it came back
 * to. `closes` says whether the loan will close (every line accounted for).
 */
export function takeBackEntries(loan: Pick<StockLoan, 'lines'>, drafts: Record<string, TakeBackDraft>,
  location: { type: LocationType; id: string } | null) {
  const entries: TakeBackEntry[] = [];
  let closes = true;
  for (const l of loan.lines) {
    const d = drafts[l.line_id] ?? blankTakeBack();
    for (const f of TAKE_BACK_FIELDS) {
      const v = d[f.key];
      if (v !== 0 && !(Number.isInteger(v) && v > 0)) {
        return { ok: false as const, error: `"${l.product_name}": every quantity must be a whole number, 0 or more.` };
      }
    }
    const total = draftTotal(d), left = outstanding(l);
    if (total > left) {
      return { ok: false as const, error: `Only ${left} of "${l.product_name}" ${left === 1 ? 'is' : 'are'} still out, but ${total} ${total === 1 ? 'is' : 'are'} entered.` };
    }
    if (total < left) closes = false;
    const back = (quantity: number, condition: 'good' | 'damaged') => {
      if (quantity > 0) entries.push({ line_id: l.line_id, outcome: 'returned', quantity, condition,
        location_type: location?.type, location_id: location?.id });
    };
    back(d.returned, 'good');
    back(d.damagedToStock, 'damaged');
    if (d.damagedUsed > 0) entries.push({ line_id: l.line_id, outcome: 'used', quantity: d.damagedUsed, condition: 'damaged' });
    if (d.used > 0) entries.push({ line_id: l.line_id, outcome: 'used', quantity: d.used });
    if (d.lost > 0) entries.push({ line_id: l.line_id, outcome: 'lost', quantity: d.lost });
  }
  if (entries.length === 0) {
    return { ok: false as const, error: 'Enter what came back, or what was used or lost, for at least one item.' };
  }
  if (entries.some(e => e.outcome === 'returned') && !location) {
    return { ok: false as const, error: 'Choose the store or warehouse it came back to.' };
  }
  return { ok: true as const, value: { entries, closes } };
}

/** Places a take-back may go: every active store; warehouses only with the warehouse permission. */
export function returnPlaces(stores: { id: string; name: string }[], warehouses: { id: string; name: string }[],
  canWarehouse: boolean): { value: string; label: string; type: LocationType; id: string }[] {
  return [
    ...stores.map(s => ({ value: `store:${s.id}`, label: `${s.name} (Store)`, type: 'store' as const, id: s.id })),
    ...(canWarehouse ? warehouses.map(w => ({ value: `warehouse:${w.id}`, label: `${w.name} (Warehouse)`, type: 'warehouse' as const, id: w.id })) : []),
  ];
}
