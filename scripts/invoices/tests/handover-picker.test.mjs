/**
 * Goods handed over before full payment (399, the Owner, 6 Oct 2026): what
 * Record Payment asks, what Hand over items and Record items returned send,
 * and what the copies of an unpaid or part-paid invoice say instead of
 * "checked and collected".
 *
 * The goods are invoice_goods_status's answer; every name and id here is
 * invented.
 *
 * Run: node --test scripts/invoices/tests/handover-picker.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  goodsFromRpc, collectable, returnable, needsHandoverAnswer, emptyPick, setPick, pickedItems, handoverProblem,
  handoverPayload, emptyReturn, setReturn, returnProblem, returnPayload, collectionLists, copyTermsText, copyCollectionLines,
  copyCollection, collectionText, collectionLineFitted, collectionSummary,
  historyLine, historySource, goodsOutBadge, goodsRefusal,
} from '../../../src/lib/invoices/handover.mjs';

const PILLOW = 'p-pillow', SOCKS = 'p-socks', BEADS = 'p-beads', BOTTLE = 'p-bottle';

// INV-2026-9101 for Jane Tan: 2 pillows (1 taken with the deposit), 3 socks,
// and a sleep set holding 2 beads and a bottle; the store has 1 bottle left.
const RPC = {
  invoice_id: 'inv-9101', invoice_no: 'INV-2026-9101', status: 'partially_paid',
  store_id: 'store-a', store_name: 'Energia Test Store', open: true, fulfil_from_warehouse: false,
  required_total: '8', collected_total: '1', to_collect_total: '7', out_total: 1,
  can_hand_over: true, can_record_return: true,
  products: [
    { product_id: BEADS, name: 'Beads', required: 2, collected: 0, to_collect: 2, out: 0, in_store: 9, via: ['Sleep Set'] },
    { product_id: BOTTLE, name: 'Bottle', required: 1, collected: 0, to_collect: 1, out: 0, in_store: 1, via: ['Sleep Set'] },
    { product_id: PILLOW, name: 'Pillow', required: 2, collected: 1, to_collect: 1, out: 1, in_store: 7, via: [] },
    { product_id: SOCKS, name: 'Socks', required: 3, collected: 0, to_collect: 3, out: 0, in_store: 20, via: [] },
  ],
  history: [
    { id: 'h1', kind: 'handover', source: 'payment', created_at: '2026-10-06T03:00:00Z', created_by_name: 'Test Staff',
      reason: null, items: [{ product_id: PILLOW, name: 'Pillow', quantity: 1 }] },
  ],
};
const goods = goodsFromRpc(RPC);

test('the status is read with numbers as numbers', () => {
  assert.equal(goods.required_total, 8);
  assert.equal(goods.to_collect_total, 7);
  assert.equal(goods.products.length, 4);
  assert.equal(goods.history[0].items[0].quantity, 1);
  assert.equal(goodsFromRpc(null), null);
  assert.deepEqual(goodsFromRpc({}).products, []);
});

test('the picker offers the products still to collect, promotion contents included', () => {
  assert.deepEqual(collectable(goods).map(p => p.name), ['Beads', 'Bottle', 'Pillow', 'Socks']);
  assert.deepEqual(returnable(goods).map(p => p.name), ['Pillow']);
  const all = goodsFromRpc({ ...RPC, products: RPC.products.map(p => ({ ...p, to_collect: p.product_id === PILLOW ? 0 : p.to_collect })) });
  assert.ok(!collectable(all).some(p => p.product_id === PILLOW), 'a product taken in full is not offered');
});

test('only a part payment on an invoice with goods to collect asks what was taken', () => {
  assert.equal(needsHandoverAnswer(goods, 100, 450), true, 'part payment');
  assert.equal(needsHandoverAnswer(goods, 450, 450), false, 'full payment takes everything');
  assert.equal(needsHandoverAnswer(goods, 449.999, 450), false, 'within half a cent is full');
  assert.equal(needsHandoverAnswer(goods, 0, 450), false, 'no payment yet');
  assert.equal(needsHandoverAnswer({ ...goods, can_hand_over: false }, 100, 450), false,
    'fulfilled from a warehouse, or nothing to hand over');
  assert.equal(needsHandoverAnswer({ ...goods, to_collect_total: 0 }, 100, 450), false, 'everything collected already');
  assert.equal(needsHandoverAnswer(null, 100, 450), false, 'goods not read');
});

test('a part payment needs an answer before it saves', () => {
  assert.match(handoverProblem(goods, null, emptyPick()), /Nothing taken/);
  assert.equal(handoverProblem(goods, 'none', emptyPick()), null);
  assert.match(handoverProblem(goods, 'items', emptyPick()), /at least one item.*or choose "Nothing taken"/);
  assert.deepEqual(handoverPayload(goods, 'none', emptyPick()), { none: true });
});

test('per product, up to what is still to collect and what the store has', () => {
  let pick = setPick(emptyPick(), PILLOW, '1');
  pick = setPick(pick, BEADS, 2);
  assert.equal(handoverProblem(goods, 'items', pick), null);
  assert.deepEqual(handoverPayload(goods, 'items', pick),
    { items: [{ product_id: BEADS, qty: 2 }, { product_id: PILLOW, qty: 1 }] }, 'in the goods order, zeros left out');
  assert.match(handoverProblem(goods, 'items', setPick(pick, PILLOW, 2)), /Only 1 of Pillow is still to collect/);
  assert.match(handoverProblem(goods, 'items', setPick(pick, SOCKS, 1.5)), /whole number for Socks/);
  assert.match(handoverProblem(goods, 'items', setPick(pick, SOCKS, -1)), /whole number for Socks/);
  assert.equal(handoverProblem(goods, 'items', setPick(emptyPick(), BOTTLE, 1)), null, 'the last bottle may go');
  const shortStore = goodsFromRpc({ ...RPC, products: RPC.products.map(p => p.product_id === BOTTLE ? { ...p, in_store: 0 } : p) });
  assert.match(handoverProblem(shortStore, 'items', setPick(emptyPick(), BOTTLE, 1)), /Only 0 of Bottle are in Energia Test Store now/);
  assert.equal(setPick(pick, SOCKS, '')[SOCKS], 0, 'an emptied box is 0');
  assert.deepEqual(pickedItems(goods, setPick(pick, BEADS, 0)).map(x => x.product.name), ['Pillow']);
});

test('Hand over items records items only', () => {
  assert.match(handoverProblem(goods, null, emptyPick(), { button: true }), /at least one item the customer takes/);
  assert.equal(handoverProblem(goods, null, setPick(emptyPick(), SOCKS, 3), { button: true }), null);
  assert.deepEqual(handoverPayload(goods, 'items', setPick(emptyPick(), SOCKS, 3)), { items: [{ product_id: SOCKS, qty: 3 }] });
});

test('Record items returned: good, damaged or not returned, up to what is out, with a reason', () => {
  let ret = setReturn(emptyReturn(), PILLOW, 'good', '1');
  assert.equal(returnProblem(goods, ret, 'Brought back unused'), null);
  assert.deepEqual(returnPayload(goods, ret), [{ product_id: PILLOW, good: 1, damaged: 0, not_returned: 0 }]);
  assert.match(returnProblem(goods, ret, '  '), /reason/);
  assert.match(returnProblem(goods, setReturn(ret, PILLOW, 'damaged', 1), 'Torn'), /Only 1 of Pillow is out with the customer/);
  assert.match(returnProblem(goods, emptyReturn(), 'Torn'), /at least one item/);
  assert.match(returnProblem(goods, setReturn(emptyReturn(), PILLOW, 'not_returned', 0.5), 'Lost'), /whole numbers for Pillow/);
  ret = setReturn(emptyReturn(), PILLOW, 'not_returned', 1);
  assert.deepEqual(returnPayload(goods, ret), [{ product_id: PILLOW, good: 0, damaged: 0, not_returned: 1 }]);
  assert.deepEqual(returnPayload(goods, setReturn(emptyReturn(), SOCKS, 'good', 1)), [], 'only goods that are out');
});

test('the copies of a part-paid invoice list Collected and To collect instead of "checked and collected"', () => {
  assert.deepEqual(collectionLists(goods), {
    collected: [{ name: 'Pillow', qty: 1 }],
    toCollect: [{ name: 'Beads', qty: 2 }, { name: 'Bottle', qty: 1 }, { name: 'Pillow', qty: 1 }, { name: 'Socks', qty: 3 }],
  });
  assert.deepEqual(copyCollectionLines('partially_paid', goods),
    ['Collected: Pillow × 1', 'To collect: Beads × 2, Bottle × 1, Pillow × 1, Socks × 3']);
  assert.equal(copyTermsText('partially_paid'), 'Goods and services sold are neither refundable nor exchangeable.');
  assert.doesNotMatch(copyTermsText('unpaid'), /checked and collected/i);
  const none = goodsFromRpc({ ...RPC, products: RPC.products.map(p => ({ ...p, collected: 0, to_collect: p.required })) });
  assert.equal(copyCollectionLines('unpaid', none)[0], 'Collected: none');
  const done = goodsFromRpc({ ...RPC, products: RPC.products.map(p => ({ ...p, collected: p.required, to_collect: 0 })) });
  assert.equal(copyCollectionLines('partially_paid', done)[1], 'To collect: none');
});

test('a fully paid invoice keeps the standard line; an open one without goods or unread lists nothing', () => {
  assert.equal(copyTermsText('paid'), undefined);
  assert.equal(copyTermsText('completed_foc'), undefined);
  assert.equal(copyTermsText('cancelled'), undefined);
  assert.equal(copyCollectionLines('paid', goods), null);
  assert.equal(copyCollectionLines('cancelled', goods), null);
  assert.equal(copyCollectionLines('unpaid', null), null, 'goods not read: no claim either way');
  assert.equal(copyCollectionLines('partially_paid', { ...goods, products: [] }), null, 'no goods on the invoice');
});

test('the PDF and image copies get the same lists, and shorter forms for a long invoice', () => {
  const c = copyCollection('partially_paid', goods);
  assert.deepEqual(c, collectionLists(goods));
  assert.deepEqual(collectionText(c), copyCollectionLines('partially_paid', goods));
  assert.equal(copyCollection('paid', goods), null);
  assert.equal(copyCollection('unpaid', null), null);
  assert.equal(copyCollection('partially_paid', { ...goods, products: [] }), null);
  // One line each: as many products as fit, then "+N more"; a character is 1 wide here.
  const len = t => t.length;
  assert.equal(collectionLineFitted('To collect', c.toCollect, 100, len), 'To collect: Beads × 2, Bottle × 1, Pillow × 1, Socks × 3');
  assert.equal(collectionLineFitted('To collect', c.toCollect, 42, len), 'To collect: Beads × 2, Bottle × 1, +2 more');
  assert.equal(collectionLineFitted('To collect', c.toCollect, 30, len), 'To collect: Beads × 2, +3 more');
  assert.equal(collectionLineFitted('To collect', c.toCollect, 10, len), 'To collect: 7 items', 'not even one fits: the count');
  assert.equal(collectionLineFitted('Collected', [], 10, len), 'Collected: none');
  for (const w of [100, 50, 42, 41, 30]) assert.ok(len(collectionLineFitted('To collect', c.toCollect, w, len)) <= w, `fits ${w}`);
  // A few words for the terms, in units.
  assert.equal(collectionSummary(c), 'Goods: 1 collected, 7 to collect.');
  assert.equal(collectionSummary({ collected: [], toCollect: [{ name: 'Pillow', qty: 1 }] }), 'Goods: 0 collected, 1 to collect.');
});

test('the history reads as sentences', () => {
  assert.equal(historyLine(goods.history[0]), 'Handed over Pillow × 1');
  assert.equal(historySource(goods.history[0]), 'with a payment');
  assert.equal(historyLine({ kind: 'nothing_taken', items: [] }), 'Nothing taken');
  assert.equal(historyLine({ kind: 'return', source: 'return', items: [{ name: 'Pillow', good: 1, damaged: 1, not_returned: 0 }] }),
    'Returned — Pillow: 1 good, 1 damaged');
  assert.equal(historySource({ source: 'button' }), 'Hand over items');
});

test('the list badge and the correction refusal', () => {
  assert.deepEqual(goodsOutBadge(3), { label: 'Goods out', title: '3 items handed over before full payment' });
  assert.deepEqual(goodsOutBadge(1).title, '1 item handed over before full payment');
  assert.equal(goodsOutBadge(0), null);
  assert.equal(goodsOutBadge(undefined), null);
  assert.equal(goodsRefusal('GOODS_HANDED_OVER: This correction takes off goods the customer already took: "Pillow" (1 with the customer, the corrected invoice keeps 0).'),
    'This correction takes off goods the customer already took: "Pillow" (1 with the customer, the corrected invoice keeps 0).');
  assert.equal(goodsRefusal('Keep at least one line'), null);
});
