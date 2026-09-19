/**
 * The small, testable parts of keeping the invoice list current.
 *
 * The list is one page of a server-side query. Refreshing it means asking the
 * server for that same page again — never patching a row locally, never
 * downloading the table. What needs care is the traffic around that request:
 * several triggers can arrive at once (a save, its realtime echo, another
 * tab's announcement, a tab-focus), an old response can land after a newer
 * one, and per-row labels are fetched separately from the rows they label.
 */

/**
 * At most one refresh in flight and at most one waiting behind it.
 *
 * A trigger that arrives while a refresh is running does not start a second
 * request; it marks a follow-up, which runs once, after the current one, and
 * reads the latest state at that moment. Every caller's promise resolves when
 * the data it asked for is on screen (or the attempt has failed), so a save
 * can await its refresh and report the outcome.
 */
export function createRefreshQueue(run: () => Promise<void>) {
  let inflight: Promise<void> | null = null;
  let queued = false;
  const request = (): Promise<void> => {
    if (inflight) { queued = true; return inflight; }
    inflight = (async () => {
      do { queued = false; await run(); } while (queued);
    })().finally(() => { inflight = null; });
    return inflight;
  };
  return { request, busy: () => inflight !== null };
}

/**
 * Per-key ordering for writes that arrive out of order.
 *
 * Payment-method labels are loaded per page of rows. If a refresh starts
 * while an earlier label request is still out, the earlier response must not
 * overwrite the later one for the rows both requests covered. Each request
 * stamps the keys it is about to write; a response may write a key only if
 * its stamp is still the newest for that key.
 */
export function createStampedWriter() {
  let next = 0;
  const latest = new Map<string, number>();
  return {
    stamp(keys: string[]): number {
      const token = ++next;
      for (const k of keys) latest.set(k, token);
      return token;
    },
    accepts(key: string, token: number): boolean {
      return latest.get(key) === token;
    },
  };
}

/** The invoice ids a postgres_changes payload is about. */
export function invoiceIdsFromChange(table: string, payload: { new?: any; old?: any } | null | undefined): string[] {
  if (!payload) return [];
  const rows = [payload.new, payload.old].filter(Boolean);
  const ids = new Set<string>();
  for (const r of rows) {
    const id = table === 'invoices' ? r.id : r.invoice_id;
    if (typeof id === 'string' && id) ids.add(id);
  }
  return Array.from(ids);
}

/**
 * Collect a burst of change notifications into one call.
 *
 * A single save can produce several row events (the invoice, its payments,
 * its commission rows' side effects); a realtime reconnect can replay a few.
 * They are gathered for `waitMs` after the first and delivered once, with the
 * union of ids and the time the first one arrived — the receiver compares that
 * time against its last refresh to decide whether anything is actually stale.
 */
export function createChangeCollector(
  waitMs: number,
  deliver: (change: { ids: string[]; firstAt: number; rows: Record<string, any> }) => void,
  now: () => number = () => Date.now(),
  schedule: (fn: () => void, ms: number) => any = setTimeout,
  cancel: (handle: any) => void = clearTimeout,
) {
  let ids = new Set<string>();
  // The invoice row each event announced, latest per id. Never shown; only
  // compared with what the list already shows, to tell an echo from news.
  let rows: Record<string, any> = {};
  let firstAt = 0;
  let timer: any = null;
  const flush = () => {
    timer = null;
    const batch = { ids: Array.from(ids), firstAt, rows };
    ids = new Set(); rows = {}; firstAt = 0;
    deliver(batch);
  };
  return {
    push(changed: string[], announced: Record<string, any> = {}) {
      if (!firstAt) firstAt = now();
      for (const id of changed) ids.add(id);
      for (const [id, row] of Object.entries(announced)) if (row) rows[id] = row;
      if (!timer) timer = schedule(flush, waitMs);
    },
    cancel() { if (timer) { cancel(timer); timer = null; } ids = new Set(); rows = {}; firstAt = 0; },
    pending: () => timer !== null,
  };
}

/**
 * Whether an announced row says nothing the list does not already show.
 *
 * Compared on the fields the list renders and that every change to an
 * invoice's money or standing moves. A field the announcement does not carry
 * is not a difference. Null when the list does not show the row at all.
 */
const ANNOUNCED_FIELDS = ['status', 'paid_amount', 'total_amount', 'customer_id', 'store_id', 'business_date', 'deleted_at', 'affiliate_id'];
export function announcedMatchesShown(announced: any, shown: any): boolean | null {
  if (!announced || !shown) return null;
  const norm = (v: unknown) => v == null ? '' : (String(v).trim() !== '' && Number.isFinite(Number(v)) ? String(Number(v)) : String(v));
  const keys = ANNOUNCED_FIELDS.filter(k => k in announced && k in shown);
  if (keys.length === 0) return null;
  return keys.every(k => norm(announced[k]) === norm(shown[k]));
}

/** Whether a refresh that started at `startedAt` already covers a change first seen at `changeAt`. */
export function refreshCovers(startedAt: number, changeAt: number): boolean {
  return startedAt > 0 && startedAt >= changeAt;
}

/**
 * Which page to show after a refresh.
 *
 * The server says how many pages there are now. If the viewer's page has
 * gone (the last row on it moved to another filter, or was deleted), step
 * back to the last page that exists; with no rows at all, page one.
 */
export function pageAfterRefresh(current: number, pages: number, total: number): number {
  if (total <= 0) return 1;
  return Math.min(Math.max(1, current), Math.max(1, pages));
}
