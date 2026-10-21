/**
 * The Special page's rules, as its two helper modules carry them (426):
 *
 *   src/lib/special/rentalTerms.ts (SALES-EXTRAS-7): "Due back" follows the
 *   start, the rate and the periods, worked out as the database works it out
 *   (a month after 31 Jan is 28 Feb, never 3 Mar); a typed date is kept until
 *   the start, the rate or the periods change; it may never be before the
 *   start; what is sent to update_pending_rental; and the fee the window
 *   shows, as update_pending_rental works it out (the owner, 18 Oct 2026,
 *   "Keep the same discount": the list fee less the same FOC share, or the
 *   same amount or percentage off, as sold, never below S$0; a change of
 *   dates alone keeps the fee as sold; while the rental's terms are the
 *   line's, the fee before is what the line charges, also after a correction
 *   of the line's price alone). The fee cases are the SQL suite's, step for
 *   step, with the same numbers.
 *
 *   src/lib/special/specialDocs.ts (SALES-EXTRAS-8 and -16, and the owner's
 *   answer W2-B03-RENTAL-BUTTON): a receipt's store is the row's own; the
 *   invoice it names; the waiting list's button; a cancelled rental still out
 *   as "Receive returned item" takes it.
 *
 * The database checks the same rules (scripts/rentals/tests/special-page-426.sql).
 * Every name and number here is invented.
 *
 * Run: node --test scripts/special/tests/rental-terms.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const load = async file => {
  const built = await build({
    stdin: { contents: `export * from './${file}';`, resolveDir: process.cwd(), loader: 'ts' },
    bundle: true, write: false, format: 'esm', logLevel: 'silent',
  });
  return import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
};
const t = await load('src/lib/special/rentalTerms');
const d = await load('src/lib/special/specialDocs');
const rr = await load('src/lib/special/rentalReturn');

test('"Due back" is worked out as the database works it out', () => {
  assert.equal(t.addPeriods('2027-01-31', 'day', 3), '2027-02-03');
  assert.equal(t.addPeriods('2027-12-30', 'day', 3), '2028-01-02', 'across a year end');
  assert.equal(t.addPeriods('2027-02-26', 'week', 2), '2027-03-12');
  // date + interval: a calendar month keeps the day, or the month's last day.
  assert.equal(t.addPeriods('2027-01-31', 'month', 1), '2027-02-28', 'never 3 Mar');
  assert.equal(t.addPeriods('2028-01-31', 'month', 1), '2028-02-29', 'a leap year');
  assert.equal(t.addPeriods('2027-03-31', 'month', 1), '2027-04-30');
  assert.equal(t.addPeriods('2027-08-31', 'month', 6), '2028-02-29');
  assert.equal(t.addPeriods('2027-11-15', 'month', 3), '2028-02-15');
  assert.equal(t.addPeriods('2028-02-29', 'year', 1), '2029-02-28');
  assert.equal(t.addPeriods('2027-05-01', 'year', 2), '2029-05-01');
  assert.equal(t.addPeriods('2027-05-01', 'day', 0), '2027-05-02', 'at least one period');
  assert.equal(t.addPeriods('', 'day', 3), '', 'no start, no date');
});

test('a change to the start, the rate or the periods moves "Due back"; a typed date is kept otherwise', () => {
  const f = t.initialTerms({ quantity: 1, rate_type: 'day', periods: 2, start_date: '2027-01-31', expected_return_date: '2027-02-02' });
  assert.deepEqual(f, { quantity: 1, rate_type: 'day', periods: 2, start_date: '2027-01-31', expected_return_date: '2027-02-02' });
  assert.equal(t.withTermsChange(f, { periods: 5 }).expected_return_date, '2027-02-05');
  assert.equal(t.withTermsChange(f, { rate_type: 'month' }).expected_return_date, '2027-03-31', '2 months');
  assert.equal(t.withTermsChange(f, { start_date: '2027-03-01' }).expected_return_date, '2027-03-03');
  // Staff type their own date: it stays while only the quantity changes.
  const typed = { ...f, expected_return_date: '2027-02-20' };
  assert.equal(t.withTermsChange(typed, { quantity: 3 }).expected_return_date, '2027-02-20');
  assert.equal(t.withTermsChange(typed, { quantity: 3 }).quantity, 3);
  // ... and moves again when the periods change.
  assert.equal(t.withTermsChange(typed, { periods: 3 }).expected_return_date, '2027-02-03');
  // A cleared start leaves the date alone; the form then says what is missing.
  const cleared = t.withTermsChange(typed, { start_date: '' });
  assert.equal(cleared.expected_return_date, '2027-02-20');
  assert.equal(t.termsProblem(cleared), 'Choose the start date.');
  // Numbers typed as nothing or a fraction become whole periods of at least one.
  assert.equal(t.withTermsChange(f, { periods: 0 }).periods, 1);
  assert.equal(t.withTermsChange(f, { quantity: 2.7 }).quantity, 2);
});

test('"Due back" may not be before the start, and what is sent', () => {
  const f = t.initialTerms({ quantity: 2, rate_type: 'week', periods: 1, start_date: '2027-04-10', expected_return_date: '2027-04-17' });
  assert.equal(t.termsProblem(f), null);
  assert.equal(t.termsProblem({ ...f, expected_return_date: '2027-04-09' }), '"Due back" cannot be before the start.');
  assert.equal(t.termsProblem({ ...f, expected_return_date: '' }), 'Choose the "Due back" date.');
  assert.equal(t.termsProblem({ ...f, expected_return_date: '2027-04-10' }), null, 'the same day is allowed, as in the database');
  assert.deepEqual(t.termsRpcArgs('rent-1', f), {
    p_rental_id: 'rent-1', p_quantity: 2, p_rate_type: 'week', p_periods: 1,
    p_start_date: '2027-04-10', p_expected_return_date: '2027-04-17',
  });
  assert.equal(t.termsChanged(f, { ...f }), false);
  assert.equal(t.termsChanged(f, { ...f, periods: 2 }), true);
});

// ── The fee: the same cases as scripts/rentals/tests/special-page-426.sql 1b ──
// S$30 a day, S$150 a week, S$400 a month, S$3,000 a year.
const RATES = { name: 'Fixture Machine', rate_day: 30, rate_week: 150, rate_month: 400, rate_year: 3000 };
const LINE = over => ({ id: 'li-1', quantity: 1, rental_rate_type: 'day', rental_periods: 1, line_total: 0, foc_quantity: 0,
  is_foc: false, line_discount: 0, line_discount_type: null, line_discount_percent: null, ...over });
// The rental as the invoice raises it: the line's terms, its value before its discount.
const RAISED = l => ({ quantity: l.quantity, rate_type: l.rental_rate_type, periods: l.rental_periods, rental_fee: l.line_total });
/** Each step: [quantity, rate, periods, [fee, before, difference], discount words]; a save follows each. */
function steps(name, line, rental, list) {
  let now = { ...rental };
  for (const [q, rt, per, want, how = null] of list) {
    const form = { quantity: q, rate_type: rt, periods: per, start_date: '2027-06-01', expected_return_date: '2027-06-02' };
    const got = t.termsFee(now, line, RATES, form);
    assert.equal(got.problem, null, `${name}: ${q} x ${per} ${rt}`);
    assert.deepEqual([got.fee, got.before, got.difference], want, `${name}: ${q} x ${per} ${rt}`);
    assert.equal(got.discount, how, `${name}: ${q} x ${per} ${rt}: the words`);
    assert.equal(got.datesOnly, q === now.quantity && rt === now.rate_type && per === now.periods);
    now = { quantity: q, rate_type: rt, periods: per, rental_fee: got.fee };   // what the save keeps
  }
}

test('the fee keeps the FOC share as sold; a free rental stays S$0', () => {
  const part = LINE({ quantity: 2, rental_periods: 2, line_total: 60, foc_quantity: 1 });
  const share = 'the same FOC share as sold (1 of 2 free)';
  steps('part FOC', part, RAISED(part), [
    [2, 'day', 2, [60, 60, 0]],
    [2, 'day', 3, [90, 60, 30], share],
    [3, 'day', 3, [135, 90, 45], share],
    [3, 'week', 1, [225, 135, 90], share],
    [3, 'week', 1, [225, 225, 0]],
  ]);
  assert.equal(t.termsFee(RAISED(part), part, RATES, { quantity: 2, rate_type: 'day', periods: 3, start_date: '', expected_return_date: '' }).list, 180);
  // Odd cents: 3 machines for a month, 2 FOC (S$400 paid), then 1 machine:
  // S$400 less 2/3 of it, S$266.67 to the cent: S$133.33.
  const odd3 = LINE({ quantity: 3, rental_rate_type: 'month', line_total: 400, foc_quantity: 2 });
  steps('part FOC, odd cents', odd3, RAISED(odd3), [[1, 'month', 1, [133.33, 400, -266.67], 'the same FOC share as sold (2 of 3 free)']]);
  const free = LINE({ rental_rate_type: 'month', line_total: 0, foc_quantity: 1, is_foc: true });
  steps('free', free, RAISED(free), [
    [1, 'month', 1, [0, 0, 0]],
    [2, 'month', 1, [0, 0, 0], 'FOC, as sold'],
    [2, 'month', 3, [0, 0, 0], 'FOC, as sold'],
    [2, 'year', 1, [0, 0, 0], 'FOC, as sold'],
  ]);
  assert.equal(t.termsFee({ quantity: 2, rate_type: 'month', periods: 3, rental_fee: 0 }, free, RATES,
    { quantity: 2, rate_type: 'year', periods: 1, start_date: '', expected_return_date: '' }).list, 6000);
});

test('the fee keeps the same amount off as sold, never below S$0', () => {
  // S$120 less S$25: S$95 sold; the rental is raised at S$120.
  const off = LINE({ quantity: 2, rental_periods: 2, line_total: 120, line_discount: 25, line_discount_type: 'manual' });
  const how = 'the same S$25.00 off as sold';
  steps('amount off', off, RAISED(off), [
    [2, 'day', 2, [95, 95, 0]],
    [2, 'day', 3, [155, 95, 60], how],
    [1, 'day', 3, [65, 155, -90], how],
    [1, 'week', 3, [425, 65, 360], how],
  ]);
  const big = LINE({ rental_rate_type: 'week', line_total: 150, line_discount: 140, line_discount_type: 'manual' });
  steps('never below 0', big, RAISED(big), [[1, 'day', 1, [0, 10, -10], 'the same S$140.00 off as sold']]);
});

test('the fee keeps the same percentage off as sold, rounded as the invoice rounds', () => {
  const pct = LINE({ rental_rate_type: 'week', line_total: 150, line_discount: 18.75, line_discount_type: 'percentage',
    line_discount_percent: 12.5 });
  const how = 'the same 12.5% off as sold';
  steps('percent off', pct, RAISED(pct), [
    [2, 'week', 1, [262.5, 131.25, 131.25], how],
    [2, 'week', 3, [787.5, 262.5, 525], how],
    [2, 'day', 3, [157.5, 787.5, -630], how],
    [2, 'day', 3, [157.5, 157.5, 0]],
  ]);
  // 33.333% off S$30 is S$10.00 off (9.9999); off S$150, S$50.00 (49.9995 rounds up).
  const odd = LINE({ line_total: 30, line_discount: 10, line_discount_type: 'percentage', line_discount_percent: 33.333 });
  steps('percent rounding', odd, RAISED(odd), [[1, 'week', 1, [100, 20, 80], 'the same 33.333% off as sold']]);
});

test("a line whose price was corrected afterwards: the fee before is what the line charges", () => {
  // Sold as 2 machines for 2 days (S$120), then the invoice corrected to 1 of
  // 2 FOC (S$60): the rental still carries S$120, its terms are the line's.
  const fixedLine = LINE({ quantity: 2, rental_periods: 2, line_total: 60, foc_quantity: 1 });
  const stale = { quantity: 2, rate_type: 'day', periods: 2, rental_fee: 120 };
  const share = 'the same FOC share as sold (1 of 2 free)';
  steps('corrected to part FOC', fixedLine, stale, [
    [2, 'day', 2, [60, 60, 0]],
    [2, 'day', 3, [90, 60, 30], share],
  ]);
  // The periods changed first: S$30 to collect, never S$30 to refund.
  steps('corrected to part FOC, periods first', fixedLine, stale, [[2, 'day', 3, [90, 60, 30], share]]);
});

test('with no invoice line, or a rate not set', () => {
  const form = { quantity: 1, rate_type: 'day', periods: 3, start_date: '', expected_return_date: '' };
  const r = { quantity: 1, rate_type: 'day', periods: 2, rental_fee: 60 };
  assert.deepEqual(t.termsFee(r, null, RATES, form), { datesOnly: false, before: 60, fee: 90, list: 90, discount: null, difference: 30, problem: null });
  const noYear = t.termsFee(r, null, { ...RATES, rate_year: 0 }, { ...form, rate_type: 'year', periods: 1 });
  assert.equal(noYear.fee, null);
  assert.equal(noYear.problem, '"Fixture Machine" has no year rate set.');
  // A rental changed since it was raised is not "as raised": what it charges is its own fee.
  const off = LINE({ quantity: 2, rental_periods: 2, line_total: 120, line_discount: 25, line_discount_type: 'manual' });
  assert.equal(t.termsFee({ quantity: 2, rate_type: 'day', periods: 3, rental_fee: 155 }, off, RATES,
    { ...form, quantity: 2, periods: 3 }).before, 155);
  assert.equal(t.SOLD_LINE_COLUMNS.split(',').includes('line_discount_percent'), true);
});

test("a receipt's store is the row's own: the invoice's, else where it was released from", () => {
  const stores = [{ id: 'st-a', name: 'Fixture Main Store' }, { id: 'st-b', name: 'Fixture Roadshow Van' }];
  assert.equal(d.docStoreId({ store_id: 'st-b', source_store_id: 'st-a' }), 'st-b');
  assert.equal(d.docStoreId({ store_id: null, source_store_id: 'st-b' }), 'st-b');
  assert.equal(d.docStore({ store_id: 'st-b' }, stores, stores[0]).name, 'Fixture Roadshow Van', 'never simply the first store');
  assert.equal(d.docStore({}, stores, stores[0]).name, 'Fixture Main Store', 'an old-style row with no store keeps the first');
  assert.equal(d.docStore({ store_id: 'st-gone' }, stores, stores[0]).name, 'Fixture Main Store');
  assert.equal(d.docStore({}, stores, null), null);
});

test('the invoice a receipt names, and the invoices to read', () => {
  assert.equal(d.invoiceLine('INV-2026-9901'), 'Invoice INV-2026-9901');
  assert.equal(d.invoiceLine(null), null);
  assert.deepEqual(d.docInvoiceIds([{ invoice_id: 'i1', late_fee_invoice_id: 'i2' }, { invoice_id: 'i1' }, {}]).sort(), ['i1', 'i2']);
});

test('the waiting list says how many wait, nothing, or that it could not be read', () => {
  assert.deepEqual(d.waitingButton(2, false), { label: 'Waiting for a warehouse', tone: 'waiting' });
  assert.deepEqual(d.waitingButton(0, false), { label: 'Nothing waiting for a warehouse', tone: 'none' });
  assert.deepEqual(d.waitingButton(0, true), { label: 'Could not load the waiting list. Press Refresh.', tone: 'failed' });
  assert.doesNotMatch(d.waitingButton(0, true).label, /Nothing waiting/);
});

test('a rental cancelled while out, as "Receive returned item" takes it', () => {
  const fromStore = d.toReceive({ id: 'r1', rental_no: 'RNT-2026-9911', quantity: 1, source_store_id: 'st-b', warehouse_id: null,
    invoice_item_id: 'l1', status: 'cancelled' }, { item: 'Fixture Machine', store: 'Fixture Roadshow Van', warehouse: null });
  assert.equal(rr.receiveHomeLabel(fromStore), 'Fixture Roadshow Van (its store)');
  assert.equal(fromStore.source_type, 'store');
  assert.deepEqual(rr.receiveRpcArgs(fromStore, { outcome: 'good', warehouseId: '' }, ' Back at the counter ', 'REQ-1'),
    { p_rental_id: 'r1', p_warehouse_id: null, p_condition: 'good', p_reason: 'Back at the counter', p_request_id: 'REQ-1' });
  const fromWh = d.toReceive({ id: 'r2', rental_no: 'RNT-2026-9912', quantity: 2, warehouse_id: 'wh-1' },
    { item: 'Fixture Machine', warehouse: 'Fixture Warehouse' });
  assert.equal(rr.receiveHomeLabel(fromWh), 'Fixture Warehouse (its warehouse)');
  assert.equal(fromWh.default_warehouse_id, 'wh-1');
  const closedWh = d.toReceive({ id: 'r3', rental_no: 'RNT-2026-9913', quantity: 1, warehouse_id: 'wh-closed' },
    { item: 'Fixture Machine', warehouse: null });
  assert.equal(rr.receiveHomeLabel(closedWh), 'Its warehouse', 'a closed warehouse is not named "—"');
});
