/**
 * Rentals follow their invoice's Edit, Cancel and Refund (458; the Owner,
 * 22 Oct 2026, item 1): what the pages say and send.
 *
 *   src/lib/special/rentalFollows.ts: "Due back" on the invoice form follows
 *   the start, the rate and the periods as the database works it out (a blank
 *   one is the start plus the periods by rate type, rule 7); the hint under a
 *   rental line of a saved invoice; the note after a correction that moved a
 *   rental; the words a refund's review and done screen use for a rental out
 *   (rule 1); the finance section's "after the cancellation", "after the
 *   refund" or "after the rental ended".
 *   src/lib/special/waitingItems.ts: a rental a refund ended while it was out
 *   reads "Refunded, still with customer" on the Special page.
 *   The pages wire them (read from the sources): the finance section lists
 *   rentals still out for any invoice, not only a cancelled one; the guided
 *   refund's review and done screen speak of refunds; the correction summary
 *   names the rentals area; the invoice form moves "Due back" and shows the
 *   hints; the saved correction says what it did to the rentals.
 *
 * The database checks the rules (scripts/rentals/tests/invoice-follows-458.sql).
 * Every name and number here is invented.
 *
 * Run: node --test scripts/rentals/tests/rentals-follow-458.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const load = async file => {
  const built = await build({
    stdin: { contents: `export * from './${file}';`, resolveDir: process.cwd(), loader: 'ts' },
    bundle: true, write: false, format: 'esm', logLevel: 'silent',
  });
  return import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
};
const f = await load('src/lib/special/rentalFollows');
const w = await load('src/lib/special/waitingItems');
const src = p => readFileSync(p, 'utf8');

test('"Due back" left blank is the start plus the periods by the rate type (rule 7)', () => {
  assert.equal(f.dueBackFor({ rental_rate_type: 'month', rental_periods: 2, rental_start_date: '2026-10-25' }), '2026-12-25',
    'a 2-month rental from 25 Oct is due back 25 Dec, not 2 days later');
  assert.equal(f.dueBackFor({ rental_rate_type: 'month', rental_periods: 1, rental_start_date: '2027-01-31' }), '2027-02-28');
  assert.equal(f.dueBackFor({ rental_rate_type: 'week', rental_periods: 2, rental_start_date: '2027-03-01' }), '2027-03-15');
  assert.equal(f.dueBackFor({ rental_rate_type: 'year', rental_periods: 1, rental_start_date: '2028-02-29' }), '2029-02-28');
  assert.equal(f.dueBackFor({ rental_rate_type: 'day', rental_periods: 3, rental_start_date: '2026-10-24' }), '2026-10-27');
  assert.equal(f.dueBackFor({ rental_rate_type: 'day', rental_periods: 3, rental_start_date: '' }), '', 'no start, no date');
  assert.equal(f.blankDueBackHint({ rental_rate_type: 'month', rental_periods: 2, rental_start_date: '2026-10-25', rental_return_date: '' }),
    'Left blank, it is due back 25/12/2026 (the start plus the periods).');
  assert.equal(f.blankDueBackHint({ rental_rate_type: 'month', rental_periods: 2, rental_start_date: '2026-10-25', rental_return_date: '2026-12-01' }),
    null, 'no hint when a date is given');
});

test('a new start, rate or number of periods moves "Due back"; a typed date is kept otherwise', () => {
  const l = { kind: 'rental', rental_rate_type: 'day', rental_periods: 2, rental_start_date: '2026-10-24', rental_return_date: '2026-10-30' };
  assert.equal(f.withRentalDueBack(l, { ...l, rental_periods: 4 }).rental_return_date, '2026-10-28', 'an extension');
  assert.equal(f.withRentalDueBack(l, { ...l, rental_periods: 1 }).rental_return_date, '2026-10-25', 'a shortening');
  assert.equal(f.withRentalDueBack(l, { ...l, rental_rate_type: 'week' }).rental_return_date, '2026-11-07');
  assert.equal(f.withRentalDueBack(l, { ...l, rental_start_date: '2026-11-01' }).rental_return_date, '2026-11-03');
  assert.equal(f.withRentalDueBack(l, { ...l, quantity: 2 }).rental_return_date, '2026-10-30', 'a quantity alone keeps the typed date');
  assert.equal(f.withRentalDueBack(l, { ...l, rental_return_date: '2026-11-02' }).rental_return_date, '2026-11-02', 'a typed date is kept');
  const noStart = { ...l, rental_start_date: '' };
  assert.equal(f.withRentalDueBack(noStart, { ...noStart, rental_periods: 5 }).rental_return_date, '2026-10-30',
    'with no start the date is left as it was (the database counts from the rental\'s own start)');
});

test('after a correction the page says what it did to the rentals (rule 3)', () => {
  assert.equal(f.correctionRentalNote(null), null);
  assert.equal(f.correctionRentalNote([]), null);
  assert.equal(f.correctionRentalNote([{ rental_id: 'R1', rental_no: 'RNT-2026-9401', state: 'waiting',
    what: 'RNT-2026-9401 (waiting for a warehouse): 2 × 3 days, S$180.00, due back 27/10/2026 (was 26/10/2026)' }]),
    'The rental follows the corrected invoice: RNT-2026-9401 (waiting for a warehouse): 2 × 3 days, S$180.00, due back 27/10/2026 (was 26/10/2026).');
  assert.match(f.correctionRentalNote([{ what: 'A' }, { what: 'B' }]), /^The rentals follow the corrected invoice: A; B\.$/);
  assert.match(f.RENTAL_FOLLOWS_HINT, /machine and quantity stay until it is returned/);
  assert.match(f.RENTAL_FOLLOWS_HINT, /machines already refunded stay off it/);
  assert.match(f.RENTAL_FOLLOWS_HINT, /released only once the invoice is paid in full/);
});

test('a refund speaks of a rental out as Cancel does (rule 1)', () => {
  assert.equal(f.rentalOutReviewNote('cancel'),
    'A rented item still with the customer stays out until it comes back. After the cancellation you can record it as back, damaged or lost.',
    'the cancellation\'s words are unchanged');
  for (const a of ['refund_full', 'refund_partial']) {
    assert.match(f.rentalOutReviewNote(a), /refund takes back in full ends here \(no late fee\)/);
    assert.match(f.rentalOutReviewNote(a), /ends those machines only, and the rest keep running/);
  }
  assert.equal(f.rentalOutReviewNote('other'), null);
  assert.equal(f.rentalOutDoneNote('cancel'), 'Cancelling ends the rental but does not bring the item back.');
  assert.equal(f.rentalOutDoneNote('refund_full'), 'The refund ends the rental but does not bring the item back.');
  assert.equal(f.stillOutAfter('cancelled'), 'after the cancellation');
  assert.equal(f.stillOutAfter('refunded'), 'after the refund');
  assert.equal(f.stillOutAfter('paid'), 'after the rental ended', 'a rental line refunded on a paid invoice');
  for (const s of ['unpaid', 'partially_paid']) {
    assert.equal(f.stillOutAfter(s), 'after the rental ended',
      'a rental cancelled while out on an invoice reopened and not yet paid again: nothing was refunded');
  }
  assert.equal(f.stillOutAfter(undefined), 'after the rental ended');
});

test('the Special page: a rental a refund ended while out reads "Refunded, still with customer"', () => {
  const out = { stock_returned: false, fulfilled_at: '2026-10-20T02:00:00Z', activated_at: '2026-10-20T02:00:00Z' };
  assert.equal(w.rentalStatusLabel('cancelled', 'From invoice INV-9\nRefunded while still out; awaiting physical return: Fixture refund', out),
    'Refunded, still with customer');
  assert.equal(w.rentalStatusLabel('cancelled', 'Split from RNT-2026-9401: 1 of its 2 refunded.\nRefunded while still out; awaiting physical return: x', out),
    'Refunded, still with customer', 'the machines split off a part refund');
  assert.equal(w.rentalStatusLabel('cancelled', 'Cancelled with its invoice while still out; awaiting physical return: x', out),
    'Cancelled, still with customer', 'Cancel unchanged');
  assert.equal(w.rentalStatusLabel('cancelled', 'Refunded while still out; awaiting physical return: a\nRunning again: invoice INV-9 was reopened\nCancelled with its invoice while still out; awaiting physical return: b', out),
    'Cancelled, still with customer', 'the last thing that ended it counts');
  assert.equal(w.rentalStatusLabel('cancelled', 'Refunded while still out; awaiting physical return: x\nReceived good: back', { ...out, stock_returned: true }),
    'Cancelled (refunded)', 'received back: cancelled, refunded');
  assert.equal(w.cancelledBecause('Refunded while still out; awaiting physical return: x'), 'refunded');
  assert.equal(w.cancelledBecause('Cancelled (refunded): x'), 'refunded', '393 unchanged');
  assert.equal(w.cancelledBecause('Cancelled with its invoice: x'), 'invoice cancelled', '300 unchanged');
});

test('the pages wire them', () => {
  const panel = src('src/components/invoices/InvoiceFinancePanel.tsx');
  assert.ok(panel.includes("if (!canManage || !statusNow) { setAwaitingRentals([]); return; }")
    && !panel.includes('cancelledNow'), 'the finance section reads the rentals still out for any invoice, not only a cancelled one');
  assert.ok(panel.includes('still with the customer {stillOutAfter(statusNow)}:'), 'and says after the cancellation, the refund or the rental ended');
  const guided = src('src/components/invoices/InvoiceGuidedAction.tsx');
  assert.ok(guided.includes("{canApprove && planAction && plan.lines.some(l => l.line_kind === 'rental') && rentalOutReviewNote(planAction) && ("),
    'the review says what a refund or cancellation does to a rental out');
  assert.ok(guided.includes("<p className=\"muted\">{rentalOutDoneNote(plan?.action ?? '')} Record each one only"),
    'the done screen speaks of the refund or the cancellation');
  assert.ok(guided.includes("rentalsToReceive(data as AwaitingRental[], p.action, (p.lines ?? []).map(l => l.invoice_item_id))"),
    'the done screen offers the receive step for the rentals on the lines a refund covered (417, unchanged)');
  assert.ok(src('src/components/invoices/CorrectionPreview.tsx').includes("rentals: 'Rentals',"), 'the summary names the rentals area');
  const page = src('src/pages/InvoicesPage.tsx');
  assert.ok(page.includes('withRentalDueBack(l, withCatalogueItem(l, { rental_rate_type: e.target.value as any }))')
    && page.includes('withRentalDueBack(l, withCatalogueItem(l, { rental_periods:')
    && page.includes('withRentalDueBack(l, { ...l, rental_start_date: e.target.value })'),
    'the invoice form moves "Due back" with the rate, the periods and the start');
  assert.ok(page.includes('{blankDueBackHint(line)}') && page.includes('{RENTAL_FOLLOWS_HINT}'), 'and shows the hints');
  assert.ok(page.includes('const rentalNote = correctionRentalNote((data as any)?.rentals);')
    && page.includes("if (rentalNote) setTherapyNote(n => [n, rentalNote].filter(Boolean).join(' '));"),
    'the saved correction says what it did to the rentals, after the therapy and voucher notes');
});
