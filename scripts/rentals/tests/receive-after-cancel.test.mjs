/**
 * A rental still with the customer after its invoice was cancelled (417,
 * audit finding INVOICES-AFTER-7): src/lib/special/rentalReturn.ts (what is
 * received, where it goes, what is said) and src/lib/special/waitingItems.ts
 * (the Rentals tab's "Cancelled, still with customer").
 *
 * The rules: nothing is chosen for the person (every item starts "Not back
 * yet"); a good item goes back where it came from, the store it was released
 * from or its warehouse, unless another warehouse is chosen; damaged and lost
 * items move no stock; a refund receives only the rentals on the lines it
 * covered, a cancellation all of them. The database checks each again
 * (scripts/rentals/tests/receive-to-source.sql). Every name and number here is
 * invented.
 *
 * Run: node --test scripts/rentals/tests/receive-after-cancel.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';

const load = async file => {
  const built = await build({
    stdin: { contents: `export * from './${file}';`, resolveDir: process.cwd(), loader: 'ts' },
    bundle: true, write: false, format: 'esm',
  });
  return import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
};
const rr = await load('src/lib/special/rentalReturn');
const w = await load('src/lib/special/waitingItems');

const row = over => ({ rental_id: 'R1', rental_no: 'RNT-2026-9301', quantity: 1, item: 'Fixture Machine',
  invoice_item_id: 'L1', source_type: 'store', source_name: 'Fixture Store', ...over });

test('nothing is chosen: every item starts "Not back yet"', () => {
  assert.deepEqual(rr.NOT_BACK_YET, { outcome: '', warehouseId: '' });
  assert.deepEqual(rr.receivedChoices([row()], { R1: rr.NOT_BACK_YET }), []);
  assert.deepEqual(rr.receivedChoices([row()], {}), [], 'no answer at all is not back either');
  assert.equal(rr.receivedChoices([row()], { R1: { outcome: 'lost', warehouseId: '' } }).length, 1);
});

test('a cancellation receives every rental still out; a refund only those on its lines', () => {
  const rows = [row(), row({ rental_id: 'R2', rental_no: 'RNT-2026-9302', invoice_item_id: 'L2' }),
                row({ rental_id: 'R3', rental_no: 'RNT-2026-9303', invoice_item_id: null })];
  assert.equal(rr.rentalsToReceive(rows, 'cancel', []).length, 3);
  assert.deepEqual(rr.rentalsToReceive(rows, 'refund_partial', ['L2']).map(r => r.rental_id), ['R2']);
  assert.deepEqual(rr.rentalsToReceive(rows, 'refund_full', ['L9']), [], 'a refund of another line receives nothing');
  assert.deepEqual(rr.rentalsToReceive(null, 'cancel', []), []);
});

test('a good item goes back where it came from unless another warehouse is chosen; damaged and lost move no stock', () => {
  assert.deepEqual(rr.receiveRpcArgs(row(), { outcome: 'good', warehouseId: '' }, '  Back today ', 'REQ-1'),
    { p_rental_id: 'R1', p_warehouse_id: null, p_condition: 'good', p_reason: 'Back today', p_request_id: 'REQ-1' });
  assert.equal(rr.receiveRpcArgs(row(), { outcome: 'good', warehouseId: 'wh-2' }, 'x', null).p_warehouse_id, 'wh-2');
  assert.equal(rr.receiveRpcArgs(row(), { outcome: 'damaged', warehouseId: 'wh-2' }, 'x', null).p_warehouse_id, null,
    'a damaged item names no warehouse: nothing goes back on sale');
  assert.equal(rr.receiveRpcArgs(row(), { outcome: 'lost', warehouseId: '' }, 'x', null).p_condition, 'lost');
});

test('where it came from, and what happened, are said in plain words', () => {
  assert.equal(rr.receiveHomeLabel(row()), 'Fixture Store (its store)');
  assert.equal(rr.receiveHomeLabel(row({ source_type: 'warehouse', source_name: 'Main Warehouse' })), 'Main Warehouse (its warehouse)');
  assert.equal(rr.receiveHomeLabel(row({ source_name: null })), 'The store it came from');
  assert.equal(rr.receiveHomeLabel(row({ source_type: null, source_name: null })), 'Where it came from');
  assert.equal(rr.receivedText(row(), 'good', { returned_quantity: 1, location_name: 'Fixture Store' }),
    'RNT-2026-9301 is back in good condition and on sale again at Fixture Store.');
  assert.equal(rr.receivedText(row(), 'good', { returned_quantity: 0, stock_note: 'It was never released from a warehouse or a store, so there is no stock to put it back into.' }),
    'RNT-2026-9301 is back in good condition. It was never released from a warehouse or a store, so there is no stock to put it back into.');
  assert.equal(rr.receivedText(row(), 'damaged', {}), 'RNT-2026-9301 is back but damaged. It is not put back on sale.');
  assert.equal(rr.receivedText(row(), 'lost', {}), 'RNT-2026-9301 is recorded as lost. It is not put back on sale.');
  assert.equal(rr.receivedText(row(), 'good', { already_returned: true }), 'RNT-2026-9301 was already recorded as back.');
});

test('the Rentals tab says "Cancelled, still with customer" for one that went out and is not back', () => {
  const out = { stock_returned: null, fulfilled_at: '2026-09-25T08:00:00Z', activated_at: '2026-09-25T08:00:00Z' };
  assert.equal(w.rentalStillWithCustomer({ status: 'cancelled', ...out }), true);
  assert.equal(w.rentalStatusLabel('cancelled', 'From invoice INV-2026-9001\nCancelled with its invoice: Duplicate', out), 'Cancelled, still with customer');
  assert.equal(w.rentalStatusLabel('cancelled', 'Cancelled with its invoice', { ...out, stock_returned: true }), 'Cancelled (invoice cancelled)',
    'once received it says why it was cancelled, as before');
  assert.equal(w.rentalStatusLabel('cancelled', 'Cancelled (refunded): Not needed', { stock_returned: null, fulfilled_at: null, activated_at: null }),
    'Cancelled (refunded)', 'one that never went out is not still with the customer');
  assert.equal(w.rentalStatusLabel('cancelled', 'Cancelled (refunded): Not needed'), 'Cancelled (refunded)', 'without the row, as before');
  assert.equal(w.rentalStatusLabel('active', null, out), 'Active');
  assert.equal(w.rentalStillWithCustomer(null), false);
});
