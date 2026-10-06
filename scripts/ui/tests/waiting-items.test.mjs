/**
 * Items waiting for a warehouse (393), as the refund screens and the Special
 * page share them: src/lib/special/waitingItems.ts.
 *
 * Pins the Owner's rules of 6 Oct 2026 as the screens carry them: which rows
 * are still waiting, how a partial refund's answers travel with its lines (on
 * the first line, and not at all when there is nothing to answer), how an
 * approver reads them back, and the status labels on the Sales and Rentals
 * tabs, a cancelled item saying why. Every name and number is invented.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const built = await build({
  stdin: { contents: `export * from './src/lib/special/waitingItems';`, resolveDir: process.cwd(), loader: 'ts' },
  bundle: true, write: false, format: 'esm',
});
const w = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

const sale = over => ({ id: 's1', sale_no: 'SPS-2026-9002', status: 'pending', warehouse_id: null, source_store_id: null,
  invoice_item_id: 'L1', special_products: { name: 'Fixture Massage Chair' }, ...over });
const rental = over => ({ id: 'r1', rental_no: 'RNT-2026-9001', status: 'awaiting_fulfilment', warehouse_id: null,
  source_store_id: null, invoice_item_id: 'L2', special_products: { name: 'Fixture Foot Spa' }, ...over });

test('only unreleased, uncancelled items are waiting', () => {
  const items = w.waitingItemsFromRows([
    sale(), sale({ id: 's2', sale_no: 'SPS-2026-9001', status: 'completed', warehouse_id: 'wh' }),
    sale({ id: 's3', sale_no: 'SPS-2026-9003', status: 'cancelled' }),
    sale({ id: 's4', sale_no: 'SPS-2026-9004', source_store_id: 'st' }),
  ], [rental(), rental({ id: 'r2', rental_no: 'RNT-2026-0002', status: 'active', warehouse_id: 'wh' })]);
  assert.deepEqual(items.map(i => [i.doc_id, i.kind]), [['r1', 'rental'], ['s1', 'special_sale']],
    'by number; released (warehouse or store), cancelled and handed-over items are not waiting');
  assert.deepEqual(w.waitingItemsFromRows(null, undefined), [], 'nothing read is nothing waiting');
});

test('the answers ride on the first line, and only when there is something to answer', () => {
  const items = w.waitingItemsFromRows([sale(), sale({ id: 's2', sale_no: 'SPS-2026-9003', invoice_item_id: 'L3' })], []);
  const lines = [{ invoice_item_id: 'L9', quantity: 1 }, { invoice_item_id: 'L1', quantity: 1 }];
  assert.deepEqual(w.unansweredItems(items, { s1: true }).map(i => i.doc_id), ['s2']);
  assert.deepEqual(w.unansweredItems(items, { s1: true, s2: false }), [], 'No is an answer too');
  assert.deepEqual(w.withWaitingAnswers(lines, items, { s1: true, s2: false }), [
    { invoice_item_id: 'L9', quantity: 1, waiting: [{ doc_id: 's1', still_taking: true }, { doc_id: 's2', still_taking: false }] },
    { invoice_item_id: 'L1', quantity: 1 }]);
  assert.equal(w.withWaitingAnswers(lines, [], {}), lines, 'no waiting item: the lines go exactly as before');
  assert.equal(w.withWaitingAnswers(lines, items, {}), lines, 'nothing answered: nothing added');
  assert.deepEqual(w.withWaitingAnswers([], items, { s1: true }), [], 'no line to carry them');
  assert.deepEqual(w.withWaitingAnswers(lines, items, { gone: false, s1: false }),
    [{ ...lines[0], waiting: [{ doc_id: 's1', still_taking: false }] }, lines[1]],
    'an answer for an item no longer waiting is not sent');
});

test('an approver reads the answers back from the request', () => {
  assert.deepEqual(w.waitingAnswersOf([
    { invoice_item_id: 'L9', quantity: 1, waiting: [{ doc_id: 's1', still_taking: false }, { doc_id: 'x', still_taking: 'no' }] },
    { invoice_item_id: 'L1', quantity: 1 }]), [{ doc_id: 's1', still_taking: false }]);
  assert.deepEqual(w.waitingAnswersOf(null), []);
  assert.deepEqual(w.waitingAnswersOf([{ invoice_item_id: 'L1', quantity: 1 }]), []);
});

test('an item is named as its invoice line names it', () => {
  const [item] = w.waitingItemsFromRows([sale()], []);
  assert.equal(w.waitingItemLabel(item, id => id === 'L1' ? 'Chair (invoice line)' : undefined), 'Chair (invoice line) · SPS-2026-9002');
  assert.equal(w.waitingItemLabel(item), 'Fixture Massage Chair · SPS-2026-9002', 'else the product');
  assert.equal(w.waitingItemLabel({ ...item, product_name: null, invoice_item_id: null }), 'Special product · SPS-2026-9002');
});

test('the Sales tab says what each status means, and why an item was cancelled', () => {
  assert.deepEqual(w.specialSaleBadge({ status: 'pending' }), { label: 'Waiting for a warehouse', tone: 'primary' });
  assert.deepEqual(w.specialSaleBadge({ status: 'completed' }), { label: 'Released', tone: 'success' });
  assert.deepEqual(w.specialSaleBadge({ status: 'paid' }), { label: 'Paid', tone: 'success' });
  assert.equal(w.specialSaleBadge({ status: 'cancelled', notes: 'From invoice INV-2026-0001\nCancelled (refunded): Customer changed their mind' }).label,
    'Cancelled (refunded)');
  assert.equal(w.specialSaleBadge({ status: 'cancelled', notes: 'From invoice INV-2026-0001\nCancelled (invoice cancelled): Duplicate' }).label,
    'Cancelled (invoice cancelled)');
  assert.equal(w.specialSaleBadge({ status: 'cancelled', notes: 'Walk-in | Cancelled: wrong colour', stock_returned: true }).label,
    'Cancelled · stock back', 'a direct sale cancelled on the page');
  assert.equal(w.specialSaleBadge({ status: 'cancelled', notes: null }).label, 'Cancelled');
  assert.equal(w.specialSaleBadge({ status: 'on_hold' }).label, 'On hold', 'an unknown status is shown, not hidden');
});

test('the Rentals tab names a waiting rental and says why one was cancelled', () => {
  assert.equal(w.rentalStatusLabel('awaiting_fulfilment'), 'Waiting for a warehouse');
  assert.equal(w.rentalStatusLabel('active'), 'Active');
  assert.equal(w.rentalStatusLabel('cancelled', 'From invoice INV-2026-0003\nCancelled (refunded): Not needed'), 'Cancelled (refunded)');
  assert.equal(w.rentalStatusLabel('cancelled', 'From invoice INV-2026-0003\nCancelled with its invoice: Duplicate'),
    'Cancelled (invoice cancelled)', 'a rental cancelled with its invoice before 393');
  assert.equal(w.rentalStatusLabel('cancelled', 'From invoice INV-2026-0003\nCancelled (line removed)'), 'Cancelled (line removed)');
  assert.equal(w.rentalStatusLabel('cancelled'), 'Cancelled');
});
