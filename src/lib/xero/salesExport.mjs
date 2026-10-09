// The invoice page's Xero sales export (411): what goes into the file, and
// what a person must know before downloading it.
//
// The documents come from xero_sales_events: an append-only list of money
// events, each dated by something that never changes once written:
//
//   receipt                 a payment received, on its own date, whatever
//                           happens to the invoice later              PAY
//   correction_replacement  a corrected payment, on the day of the
//                           correction                                ADJ
//   correction_reversal     the payment it replaces, reversed that day REV
//   refund                  money returned (also on a cancellation),
//                           a credit note on the day it was recorded  REF
//
// so a period that was downloaded never changes later. Two more kinds are
// listed to be explained and never exported: legacy_refund_left_out (a payment
// of an invoice refunded before refunds were recorded) and refund_unsourced (a
// refund with no payment source: the export refuses until it is reviewed).
//
// Every download is recorded (record_xero_sales_export), and
// xero_sales_export_review says what was downloaded before for the same dates
// and stores (a document counts as downloaded whatever store it was
// downloaded for: a paid invoice can move to another store).
// planXeroSalesExport sorts the documents into:
//   - already downloaded, with the same number, date and amount (left out of
//     the file unless the person asks for them again; then they are marked
//     "again", and the server records them only when so marked);
//   - downloaded with another date or amount (left out: corrected in Xero by
//     hand);
//   - new in dates already downloaded (entered afterwards; in the file);
//   - dated outside the dates but entered after their own dates were
//     downloaded (missed; added to the file unless the person says not to);
//   - downloaded but no longer listed (vanished; checked in Xero by hand),
//     or listed for another store now (moved; in Xero already, nothing to do).
// Downloads before the first recorded one were not recorded: dates that start
// on or before that day (or any dates, when nothing is recorded yet) are
// "unrecorded", and the person confirms they checked Xero before downloading.
//
// Amounts are whole cents (BigInt), so the file adds up exactly.

export const EXPORTABLE_KINDS = ['receipt', 'correction_replacement', 'correction_reversal', 'refund'];
const PREFIX = { receipt: 'PAY', correction_replacement: 'ADJ', correction_reversal: 'REV', refund: 'REF' };
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** Whole cents of an amount with at most two decimals (a number or a numeric string). */
export function amountCents(amount) {
  const match = /^(-?)(\d+)(?:\.(\d{1,2}))?$/.exec(String(amount ?? ''));
  if (!match) throw new Error('A sales event has an invalid currency amount. Review it before exporting.');
  const cents = BigInt(match[2]) * 100n + BigInt((match[3] ?? '').padEnd(2, '0'));
  return match[1] ? -cents : cents;
}

/** Cents as an amount with two decimals, e.g. -2600n -> "-26.00". */
export function formatCents(cents) {
  const absolute = cents < 0n ? -cents : cents;
  return `${cents < 0n ? '-' : ''}${absolute / 100n}.${String(absolute % 100n).padStart(2, '0')}`;
}

/** Cents for a person to read, e.g. -2600n -> "-S$26.00". */
export function sgd(cents) {
  return `${cents < 0n ? '-' : ''}S$${formatCents(cents < 0n ? -cents : cents)}`;
}

/** "16 Aug 2026" from "2026-08-16"; the text itself if it is not a date. */
export function dayLabel(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(iso ?? ''));
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}` : String(iso ?? '');
}

/** The Singapore day ("2026-10-01") of a timestamp, or null. */
export function singaporeDay(ts) {
  const d = new Date(ts ?? '');
  if (ts == null || !Number.isFinite(d.getTime())) return null;
  return new Date(d.getTime() + 8 * 3600 * 1000).toISOString().slice(0, 10);
}

/** "1 Oct 2026, 10:05" (Singapore) from a timestamp. */
export function momentLabel(ts) {
  const d = new Date(ts);
  if (!Number.isFinite(d.getTime())) return String(ts ?? '');
  const sg = new Date(d.getTime() + 8 * 3600 * 1000);
  return `${sg.getUTCDate()} ${MONTHS[sg.getUTCMonth()]} ${sg.getUTCFullYear()}, `
    + `${String(sg.getUTCHours()).padStart(2, '0')}:${String(sg.getUTCMinutes()).padStart(2, '0')}`;
}

/** The Xero number the page has always written: <invoice>-PAY|ADJ|REV|REF-<event id without dashes>. */
export function expectedDocumentNumber(event) {
  const prefix = PREFIX[event?.event_kind];
  if (!prefix || !event?.invoice_no || !event?.event_id) return null;
  return `${event.invoice_no}-${prefix}-${String(event.event_id).replace(/-/g, '')}`;
}

export const eventKey = e => `${e.event_kind}:${e.event_id}`;

const byDocument = (a, b) =>
  (a.document_date < b.document_date ? -1 : a.document_date > b.document_date ? 1 : 0)
  || (String(a.event_id) < String(b.event_id) ? -1 : String(a.event_id) > String(b.event_id) ? 1 : 0)
  || (a.event_kind < b.event_kind ? -1 : a.event_kind > b.event_kind ? 1 : 0);

/**
 * What goes into the file, and what the person is told first.
 * events: xero_sales_events between the dates; review: xero_sales_export_review
 * for the same dates and store (null when none was asked for); from: the first
 * day exported (missing counts as before any recorded download).
 */
export function planXeroSalesExport(events, review, { skipDownloaded = true, addMissed = true, from = null } = {}) {
  const downloads = new Map((review?.downloads ?? []).map(d => [eventKey(d), d]));
  const exports = review?.exports ?? [];
  const covered = e => exports.some(x => x.from_date <= e.document_date && e.document_date <= x.to_date
    && (x.covered_store_ids ?? []).includes(e.store_id));
  const legacy = [], already = [], changed = [], late = [], fresh = [];
  for (const e of events ?? []) {
    if (e.event_kind === 'legacy_refund_left_out') { legacy.push(e); continue; }
    const d = downloads.get(eventKey(e));
    if (d) {
      const same = d.document_number === e.document_number && d.document_date === e.document_date
        && amountCents(d.amount) === amountCents(e.amount);
      (same ? already : changed).push({ event: e, download: d });
    } else if (covered(e)) late.push(e);
    else fresh.push(e);
  }
  const missed = [...(review?.missed ?? [])].sort(byDocument);
  const again = skipDownloaded ? [] : already.map(a => a.event);
  const include = [...fresh, ...late, ...again, ...(addMissed ? missed : [])].sort(byDocument);
  const moved = (review?.vanished ?? []).filter(v => v.moved === true);
  const vanished = (review?.vanished ?? []).filter(v => v.moved !== true);
  const recordedSince = review?.recorded_since ?? null;
  const firstDay = singaporeDay(recordedSince);
  const unrecorded = !firstDay || !from || from <= firstDay;
  return {
    include, again, legacy, already, changed, late, missed, vanished, moved, exports, recordedSince, unrecorded,
    // Nothing in the file and nothing downloaded before: nothing to confirm.
    needsReview: (unrecorded && include.length > 0)
      || already.length + changed.length + late.length + missed.length + vanished.length + moved.length > 0,
  };
}

/** The total of some events, in cents. */
export const totalCents = events => (events ?? []).reduce((sum, e) => sum + amountCents(e.amount), 0n);
