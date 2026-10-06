/**
 * A rental's Return on the Special page (396): src/lib/special/rentalReturn.ts.
 *
 * Pins the Owner's rules of 6 Oct 2026 as the screen carries them: "Returned
 * on" (today by default, not in the future, not before the start) and the
 * late days counted to it; "No late fee" first and needing nothing; the days
 * to charge only ever fewer; the rate typed and more than S$0; a discount (S$
 * or %) with a reason; the fee after it more than S$0; a method that is not
 * wallet credit and none chosen for staff; a store chosen only for a rental
 * with none of its own; the tick naming where the unit goes back, or saying
 * there is nowhere; "on time" never said of a late rental; what the Rentals
 * tab and the receipts say afterwards; a lost unit never ticked back into
 * stock; an old-style rental back into the old special stock it came from; a
 * cleared date never shown as "NaN days late". Also that the page uses the
 * module and calls the new Return. Every name and number is invented.
 *
 * Run: node --test scripts/rentals/tests/rental-return.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/special/rentalReturn';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm',
});
const rr = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');

const TODAY = '2026-10-06';
const rental = over => ({
  rental_no: 'RNT-2026-9001', quantity: 1, start_date: '2026-09-20', expected_return_date: '2026-10-01',
  late_fee_per_day: 0, warehouse_id: null, source_store_id: 'store-b', store_id: 'store-a', invoice_id: 'inv-1',
  fulfilled_at: '2026-09-20T02:00:00Z',
  ...over,
});
const charged = (r, over) => ({ ...rr.initialReturnForm(r, TODAY), choice: 'charge', rate: '12', paymentMethodId: 'cash', ...over });

test('the late days count to "Returned on", on the calendar dates alone', () => {
  const r = rental();
  assert.equal(rr.lateDaysOn(r, '2026-10-01'), 0, 'the due date itself is on time');
  assert.equal(rr.lateDaysOn(r, '2026-09-25'), 0, 'early is on time');
  assert.equal(rr.lateDaysOn(r, '2026-10-02'), 1);
  assert.equal(rr.lateDaysOn(r, TODAY), 5);
  assert.equal(rr.daysBetween('2026-02-27', '2026-03-01'), 2, 'across a month end');
  assert.equal(rr.daysBetween('2026-10-01T00:00:00+08:00', '2026-10-06'), 5, 'a timestamp counts by its date');
});

test('the form opens on today, good, back into stock and "No late fee", with nothing paid by yet', () => {
  const f = rr.initialReturnForm(rental(), TODAY);
  assert.deepEqual([f.returnedOn, f.condition, f.returnStock, f.choice, f.days, f.rate, f.paymentMethodId, f.discount],
    [TODAY, 'good', true, 'none', '5', '', '', '']);
  assert.equal(rr.initialReturnForm(rental({ late_fee_per_day: 8 }), TODAY).rate, '8.00', 'the rental\'s own rate is the start');
  assert.equal(rr.returnProblem(f, rental(), { today: TODAY }), null, '"No late fee" needs no reason or anything else');
  const moved = rr.withReturnedOn(f, rental(), '2026-10-03');
  assert.deepEqual([moved.returnedOn, moved.days], ['2026-10-03', '2'], 'the days follow the date');
});

test('the return date is never in the future nor before the start', () => {
  const f = rr.initialReturnForm(rental(), TODAY);
  assert.match(rr.returnProblem({ ...f, returnedOn: '2026-10-07' }, rental(), { today: TODAY }), /future/);
  assert.match(rr.returnProblem({ ...f, returnedOn: '2026-09-19' }, rental(), { today: TODAY }), /before the rental started \(20\/09\/2026\)/);
  assert.equal(rr.returnProblem({ ...f, returnedOn: '2026-09-20' }, rental(), { today: TODAY }), null);
});

test('"on time" is never said of a late rental, whatever its rate', () => {
  assert.equal(rr.lateNotice(rental(), '2026-10-01'), 'Returned on time — no late fee.');
  assert.equal(rr.lateNotice(rental({ late_fee_per_day: 0 }), TODAY), '5 days late: it was due back on 01/10/2026.');
  assert.equal(rr.lateNotice(rental(), '2026-10-02'), '1 day late: it was due back on 01/10/2026.');
});

test('charging: days only fewer, a rate above S$0, a discount with its reason, a fee above S$0, a method that is not wallet', () => {
  const r = rental();
  const ok = charged(r);
  assert.equal(rr.returnProblem(ok, r, { today: TODAY, walletMethodIds: ['wallet'] }), null);
  assert.match(rr.returnProblem({ ...ok, days: '6' }, r, { today: TODAY }), /between 1 and 5 days: it was 5 days late/);
  assert.match(rr.returnProblem({ ...ok, days: '0' }, r, { today: TODAY }), /between 1 and 5/);
  assert.match(rr.returnProblem({ ...ok, days: '2.5' }, r, { today: TODAY }), /between 1 and 5/);
  assert.equal(rr.returnProblem({ ...ok, days: '3' }, r, { today: TODAY }), null, 'fewer days need no reason');
  for (const rate of ['', '0', '-1', 'abc'])
    assert.match(rr.returnProblem({ ...ok, rate }, r, { today: TODAY }), /daily late fee/, `rate "${rate}"`);
  assert.match(rr.returnProblem({ ...ok, discount: 'manual', discountAmount: '5' }, r, { today: TODAY }), /reason for the discount/);
  assert.match(rr.returnProblem({ ...ok, discount: 'manual', discountAmount: '5', discountReason: '   ' }, r, { today: TODAY }), /reason/);
  assert.match(rr.returnProblem({ ...ok, discount: 'manual', discountAmount: '0', discountReason: 'x' }, r, { today: TODAY }), /in S\$ \(more than 0\)/);
  assert.match(rr.returnProblem({ ...ok, discount: 'manual', discountAmount: '60', discountReason: 'x' }, r, { today: TODAY }), /more than S\$0/);
  assert.match(rr.returnProblem({ ...ok, discount: 'percentage', discountPercent: '100', discountReason: 'x' }, r, { today: TODAY }), /more than S\$0/);
  assert.match(rr.returnProblem({ ...ok, discount: 'percentage', discountPercent: '101', discountReason: 'x' }, r, { today: TODAY }), /at most 100%/);
  assert.equal(rr.returnProblem({ ...ok, discount: 'percentage', discountPercent: '10', discountReason: 'Regular' }, r, { today: TODAY }), null);
  assert.match(rr.returnProblem({ ...ok, paymentMethodId: '' }, r, { today: TODAY }), /how the late fee is paid/);
  assert.match(rr.returnProblem({ ...ok, paymentMethodId: 'wallet' }, r, { today: TODAY, walletMethodIds: ['wallet'] }), /Wallet credit cannot pay/);
  // Charging an on-time return is not asked: the choice is not shown.
  assert.equal(rr.returnProblem({ ...ok, returnedOn: '2026-10-01', rate: '' }, r, { today: TODAY }), null);
});

test('the fee is worked out as the database works it out', () => {
  const r = rental({ quantity: 2 });
  const f = charged(r, { days: '3', rate: '10', discount: 'manual', discountAmount: '15', discountReason: 'x' });
  assert.deepEqual(rr.lateFeeAmounts(f, r), { days: 3, rate: 10, quantity: 2, unit: 20, gross: 60, discount: 15, total: 45 });
  assert.equal(rr.lateFeeSum(f, r), '3 days × S$10.00 × 2 = S$60.00 − S$15.00 = S$45.00');
  const g = charged(rental(), { days: '4', rate: '7.5', discount: 'percentage', discountPercent: '10', discountReason: 'x' });
  assert.equal(rr.lateFeeAmounts(g, rental()).total, 27);
  assert.equal(rr.lateFeeSum(g, rental()), '4 days × S$7.50 = S$30.00 − S$3.00 (10%) = S$27.00');
  const h = charged(rental(), { days: '1', rate: '9.995' });
  assert.equal(rr.lateFeeAmounts(h, rental()).total, 10, 'the rate is kept to the cent first');
  const p = charged(rental(), { days: '3', rate: '3.33', discount: 'percentage', discountPercent: '33.3333', discountReason: 'x' });
  assert.equal(rr.lateFeeAmounts(p, rental()).discount, 3.33, 'a percentage is kept to 3 decimals, the amount to the cent');
});

test('a store is chosen only for a rental with none of its own', () => {
  const old = rental({ store_id: null, source_store_id: null, invoice_id: null, warehouse_id: 'wh', fulfilled_at: null });
  assert.equal(rr.needsStoreChoice(old), true);
  assert.equal(rr.needsStoreChoice(rental()), false);
  assert.equal(rr.needsStoreChoice(rental({ store_id: null, source_store_id: null })), false, 'its invoice\'s store');
  assert.match(rr.returnProblem(charged(old), old, { today: TODAY }), /Choose the store/);
  assert.equal(rr.returnProblem(charged(old, { storeId: 'store-a' }), old, { today: TODAY }), null);
  assert.equal(rr.returnRpcArgs('r1', charged(old, { storeId: 'store-a' }), old).p_store_id, 'store-a');
  assert.equal(rr.returnRpcArgs('r1', charged(rental(), { storeId: 'store-a' }), rental()).p_store_id, null);
});

test('the tick names where the unit goes back, or says there is nowhere', () => {
  const ctx = { warehouses: [{ id: 'wh', name: 'Fixture Warehouse' }], stores: [{ id: 'store-b', name: 'Fixture Van' }], isWarehouseProduct: true };
  assert.deepEqual(rr.stockHome(rental(), ctx), { kind: 'store', name: 'Fixture Van', canRestock: true, label: 'Return 1 to Fixture Van stock',
    hint: 'Untick for lost or unusable items: no stock changes.', note: null });
  assert.equal(rr.stockHome(rental({ source_store_id: null, warehouse_id: 'wh', quantity: 2 }), ctx).label, 'Return 2 to Fixture Warehouse stock');
  const none = rr.stockHome(rental({ source_store_id: null, warehouse_id: 'wh' }), { ...ctx, isWarehouseProduct: false });
  assert.equal(none.canRestock, false);
  assert.match(none.note, /not a warehouse product.*recorded without a stock change/);
  // An invoice's rental not released yet has nowhere to go back to.
  const waiting = rr.stockHome(rental({ source_store_id: null, warehouse_id: null, fulfilled_at: null }), ctx);
  assert.equal(waiting.canRestock, false);
  assert.match(waiting.note, /never released/);
});

test('an old-style rental goes back into the old special stock it was taken from, never warehouse stock', () => {
  const ctx = { warehouses: [{ id: 'wh', name: 'Fixture Warehouse' }], stores: [], isWarehouseProduct: true };
  const old = rental({ rental_no: 'RENT-2026-9001', store_id: null, source_store_id: null, invoice_id: null, warehouse_id: 'wh', fulfilled_at: null });
  assert.equal(rr.isOldStyleRental(old), true);
  assert.equal(rr.isOldStyleRental(rental()), false);
  const home = rr.stockHome(old, ctx);
  assert.deepEqual([home.kind, home.canRestock, home.label], ['special_stock', true, 'Return 1 to the old special stock at Fixture Warehouse']);
  assert.match(home.hint, /not from warehouse stock.*Warehouse stock does not change/);
  // Of a deleted special product (no warehouse product): nowhere, as the Owner said.
  assert.equal(rr.stockHome(old, { ...ctx, isWarehouseProduct: false }).canRestock, false);
});

test('a lost unit is never ticked back into stock', () => {
  const r = rental();
  const f = rr.initialReturnForm(r, TODAY);
  const lost = rr.withCondition(f, 'lost');
  assert.deepEqual([lost.condition, lost.returnStock], ['lost', false], '"Lost" unticks the box');
  assert.equal(rr.returnProblem(lost, r, { today: TODAY }), null);
  assert.match(rr.returnProblem({ ...lost, returnStock: true }, r, { today: TODAY }), /A lost unit cannot go back into stock/);
  assert.deepEqual([rr.withCondition(lost, 'good').returnStock, rr.withCondition(lost, 'damaged').returnStock], [true, true],
    'leaving "lost" ticks it again, as the form opens');
  const unticked = rr.withCondition({ ...f, returnStock: false }, 'damaged');
  assert.equal(unticked.returnStock, false, 'otherwise the tick is left as staff set it');
  assert.equal(rr.returnRpcArgs('r1', lost, r).p_return_stock, false);
});

test('a cleared "Returned on" never shows "NaN days late"', () => {
  const r = rental();
  const f = rr.withReturnedOn(rr.initialReturnForm(r, TODAY), r, '2026-10-04');
  const cleared = rr.withReturnedOn(f, r, '');
  assert.equal(rr.lateDaysOn(r, ''), 0);
  assert.deepEqual([cleared.returnedOn, cleared.days], ['', '3'], 'the days are kept until a date is chosen again');
  assert.equal(rr.isDay(''), false);
  assert.equal(rr.isDay('2026-10-04'), true);
  assert.equal(rr.lateNotice(r, ''), 'Choose the date it came back.');
  assert.doesNotMatch(rr.lateNotice(r, ''), /NaN/);
  assert.equal(rr.returnProblem(cleared, r, { today: TODAY }), 'Choose the date it came back.');
  const page = read('src/pages/SpecialPage.tsx');
  assert.match(page, /!isDay\(retForm\.returnedOn\) \? null :/, 'the page shows nothing about lateness without a date');
});

test('what is sent: nothing about a fee unless one is charged', () => {
  const r = rental();
  const none = rr.returnRpcArgs('r1', { ...rr.initialReturnForm(r, TODAY), condition: 'lost', returnStock: false }, r);
  assert.deepEqual(none, { p_rental_id: 'r1', p_condition: 'lost', p_return_stock: false, p_returned_on: TODAY,
    p_charge_late_fee: false, p_late_days: null, p_daily_rate: null, p_discount_type: null, p_discount_amount: null,
    p_discount_percent: null, p_discount_reason: null, p_payment_method_id: null, p_payment_reference: null,
    p_store_id: null, p_note: null });
  const fee = rr.returnRpcArgs('r1', charged(r, { days: '3', discount: 'manual', discountAmount: '4.999',
    discountReason: '  Came back early  ', reference: ' RCPT-9001 ' }), r);
  assert.deepEqual([fee.p_charge_late_fee, fee.p_late_days, fee.p_daily_rate, fee.p_discount_type, fee.p_discount_amount,
    fee.p_discount_reason, fee.p_payment_method_id, fee.p_payment_reference],
    [true, 3, 12, 'manual', 5, 'Came back early', 'cash', 'RCPT-9001']);
  // "Charge late fee" picked, then the date moved to an on-time return: no fee.
  assert.equal(rr.returnRpcArgs('r1', charged(r, { returnedOn: '2026-10-01' }), r).p_charge_late_fee, false);
});

test('the Rentals tab and the receipts afterwards', () => {
  assert.equal(rr.lateFeeStatus({ status: 'returned', late_fee_total: 36, late_fee_invoice_id: 'i1' }, 'INV-2026-9001'), '+S$36.00 late · INV-2026-9001');
  assert.equal(rr.lateFeeStatus({ status: 'returned', late_fee_total: 15 }), '+S$15.00 late', 'one collected before 396');
  assert.equal(rr.lateFeeStatus({ status: 'returned', late_fee_total: 0, late_fee_waived: true, late_days: 3 }), '3 days late · no late fee');
  assert.equal(rr.lateFeeStatus({ status: 'returned', late_fee_total: 0 }), null);
  assert.equal(rr.lateFeeStatus({ status: 'active', late_fee_total: 0 }), null);
  assert.equal(rr.overdueNote({ ...rental(), status: 'active' }, TODAY), '5d late', 'no money shown at a rate of S$0');
  assert.equal(rr.overdueNote({ ...rental({ late_fee_per_day: 4, quantity: 2 }), status: 'active' }, TODAY), '5d late · S$40.00');
  assert.equal(rr.overdueNote({ ...rental(), status: 'returned' }, TODAY), null);
  assert.deepEqual(rr.receiptLateFee({ late_fee_total: 36, late_fee_invoice_id: 'i1' }, 'INV-2026-9001'),
    { inTotal: 0, note: 'Late return fee S$36.00, invoiced on INV-2026-9001' });
  assert.deepEqual(rr.receiptLateFee({ late_fee_total: 15 }), { inTotal: 15, note: null });
});

test('the page uses this module and the new Return, never the old one', () => {
  const page = read('src/pages/SpecialPage.tsx');
  assert.match(page, /from '\.\.\/lib\/special\/rentalReturn'/);
  assert.match(page, /rpc\('return_rental_with_fee'/);
  assert.doesNotMatch(page, /rpc\('return_rental'/);
  assert.doesNotMatch(page, /Return \{retFor\.quantity\} to warehouse stock/, 'the tick names the place');
  assert.doesNotMatch(page, /setRetMethod\(methods\[0\]/, 'no method preselected');
  assert.match(page, /\/invoices\?review=/, 'the late fee\'s invoice opens on the Invoices page');
  assert.match(page, /disabled=\{retForm\.condition === 'lost'\}/, '"Lost" locks the stock box');
  assert.match(page, /withCondition\(f, c\)/);
  const inv = read('src/pages/InvoicesPage.tsx');
  assert.match(inv, /late_fee: 'Late fee'/);
  assert.match(inv, /isLateFeeInvoice/);
  // The late-fee invoice points to the correction that exists, not to a Return that is gone.
  assert.match(inv, /corrected on the payment\s+below \(Correct amount \/ date\)/);
  assert.doesNotMatch(inv, /Change a late fee from the\s+rental's Return/);
});
