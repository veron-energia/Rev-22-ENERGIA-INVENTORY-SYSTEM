/**
 * 547 (the Owner, 27 Nov 2026): special, consignment and rental items on an
 * invoice's Goods collected: what Record Payment asks, what "Hand over items" /
 * "Record items collected" and "Record items returned" send, what the invoice
 * shows, and what its copies say (Collected / Delivered / To collect), on a
 * paid invoice too. Products keep 399's behaviour (handover-picker.test.mjs).
 *
 * The goods are invoice_goods_status's answer; the components are mounted in
 * jsdom with a fake Supabase client. Every name and id here is invented.
 *
 * Run: node --test scripts/invoices/tests/goods-collected-special-547.test.mjs
 */
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  goodsFromRpc, needsHandoverAnswer, emptyPick, setPick, handoverProblem, handoverPayload, collectableProducts,
  collectableSpecials, returnableSpecials, returnableProducts, canHandOver, canRecordReturn, setSpecialPick, setSpecialHow,
  pickedSpecials, emptyReturn, setSpecialReturn, setReturn, returnProblem, returnPayload, collectionLists, copyTermsText,
  copyCollection, copyCollectionLines, collectionText, collectionSummary, collectionLineFitted, historyLine, historySource, copyReadsGoods,
} from '../../../src/lib/invoices/handover.mjs';
import { setupDom, bundle, driver, fakeSupabase } from '../../ui/page-harness.mjs';

const CHAIR = 'line-chair', BED = 'line-bed', LAMP = 'line-lamp', PILLOW = 'p-pillow';
const special = (o) => ({ line_kind: 'special_product', special_product_id: 'sp-' + o.invoice_item_id, is_consignment: false,
  can_deliver: false, quantity: 1, collected: 0, delivered: 0, out: 0, to_collect: 1, ...o });

// INV-2026-9201, part paid: 1 pillow (to collect), a massage chair (2: 1 collected), a consignment
// bed (1, to collect, may be Delivered) and a rented lamp (1, to collect).
const OPEN = {
  invoice_id: 'inv-9201', invoice_no: 'INV-2026-9201', status: 'partially_paid',
  store_id: 'store-a', store_name: 'Energia Test Store', open: true, fulfil_from_warehouse: false,
  required_total: 1, collected_total: 0, to_collect_total: 1, out_total: 0,
  can_hand_over: true, can_record_return: false,
  products: [{ product_id: PILLOW, name: 'Pillow', required: 1, collected: 0, to_collect: 1, out: 0, in_store: 5, via: [] }],
  history: [],
  specials: [
    special({ invoice_item_id: CHAIR, name: 'Massage Chair', quantity: 2, collected: 1, out: 1, to_collect: 1 }),
    special({ invoice_item_id: BED, name: 'Air Bed', is_consignment: true, can_deliver: true }),
    special({ invoice_item_id: LAMP, line_kind: 'rental', name: 'Heat Lamp (rental)' }),
  ],
  special_collected_total: '1', special_delivered_total: 0, special_out_total: 1, special_to_collect_total: 3,
  can_collect_special: true, can_record_special_return: true,
};
const open = goodsFromRpc(OPEN);
// The same invoice paid in full: products all collected, special items still to collect (answer 6).
const PAID = { ...OPEN, status: 'paid', open: false, collected_total: 1, to_collect_total: 0, can_hand_over: false,
  products: [{ ...OPEN.products[0], collected: 1, to_collect: 0, out: 1 }] };
const paid = goodsFromRpc(PAID);

test('the special lines are read with numbers as numbers; an answer without them has none', () => {
  assert.equal(open.specials.length, 3);
  assert.equal(open.special_collected_total, 1);
  assert.equal(open.specials[2].line_kind, 'rental');
  assert.equal(open.can_collect_special, true);
  const old = goodsFromRpc({ ...OPEN, specials: undefined, can_collect_special: undefined, special_to_collect_total: undefined });
  assert.deepEqual(old.specials, []);
  assert.equal(old.can_collect_special, false);
  assert.equal(old.special_to_collect_total, 0);
});

test('a part payment asks when only special items are to collect, and a paid invoice offers only them', () => {
  const onlySpecial = goodsFromRpc({ ...OPEN, to_collect_total: 0, products: [] });
  assert.equal(needsHandoverAnswer(onlySpecial, 100, 900), true);
  assert.equal(needsHandoverAnswer(onlySpecial, 900, 900), false, 'a full payment asks nothing');
  assert.equal(needsHandoverAnswer(goodsFromRpc({ ...OPEN, can_collect_special: false, to_collect_total: 0 }), 100, 900), false);
  assert.equal(canHandOver(paid), true);
  assert.deepEqual(collectableProducts(paid), []);
  assert.deepEqual(collectableSpecials(paid).map(p => p.name), ['Massage Chair', 'Air Bed', 'Heat Lamp (rental)']);
  assert.equal(canHandOver(goodsFromRpc({ ...PAID, can_collect_special: false })), false);
});

test('the answer sends the special items with how; a products-only answer is as before', () => {
  let pick = setPick(emptyPick(), PILLOW, 1);
  assert.deepEqual(handoverPayload(open, 'items', pick), { items: [{ product_id: PILLOW, qty: 1 }] }, 'no "specials" key');
  pick = setSpecialPick(pick, CHAIR, 1);
  pick = setSpecialPick(pick, BED, 1);
  pick = setSpecialHow(pick, BED, 'delivered');
  pick = setSpecialPick(pick, LAMP, 1);
  assert.equal(handoverProblem(open, 'items', pick), null);
  assert.deepEqual(handoverPayload(open, 'items', pick), {
    items: [{ product_id: PILLOW, qty: 1 }],
    specials: [{ invoice_item_id: CHAIR, qty: 1, how: 'collected' }, { invoice_item_id: BED, qty: 1, how: 'delivered' },
               { invoice_item_id: LAMP, qty: 1, how: 'collected' }],
  });
  // How is only sent as Delivered for a line that may be delivered.
  const notDeliverable = setSpecialHow(setSpecialPick(emptyPick(), CHAIR, 1), CHAIR, 'delivered');
  assert.equal(pickedSpecials(open, notDeliverable)[0].how, 'collected');
  assert.deepEqual(handoverPayload(open, 'none', pick), { none: true });
});

test('what stops it: too many, not whole, a rental in part, nothing at all', () => {
  assert.match(handoverProblem(open, 'items', setSpecialPick(emptyPick(), CHAIR, 2)), /Only 1 of Massage Chair is still to collect/);
  assert.match(handoverProblem(open, 'items', setSpecialPick(emptyPick(), CHAIR, 0.5)), /whole number/);
  const twoLamps = goodsFromRpc({ ...OPEN, specials: [special({ invoice_item_id: LAMP, line_kind: 'rental', name: 'Heat Lamp (rental)', quantity: 2, to_collect: 2 })] });
  assert.match(handoverProblem(twoLamps, 'items', setSpecialPick(emptyPick(), LAMP, 1)), /collected whole/);
  assert.equal(handoverProblem(twoLamps, 'items', setSpecialPick(emptyPick(), LAMP, 2)), null);
  assert.match(handoverProblem(paid, 'items', emptyPick(), { button: true }), /at least one item/);
  assert.equal(handoverProblem(paid, 'items', setSpecialPick(emptyPick(), CHAIR, 1), { button: true }), null,
    'on a paid invoice a special item alone is enough');
});

test('Record items returned: the special items, and products only before full payment', () => {
  assert.deepEqual(returnableSpecials(open).map(p => p.name), ['Massage Chair']);
  assert.deepEqual(returnableProducts(paid), [], 'a paid invoice\'s products go through Refund / Cancel');
  assert.equal(canRecordReturn(paid), true);
  let e = setSpecialReturn(emptyReturn(), CHAIR, 2);
  assert.match(returnProblem(open, e, 'Brought back'), /Only 1 of Massage Chair is out/);
  e = setSpecialReturn(emptyReturn(), CHAIR, 1);
  assert.match(returnProblem(open, e, ''), /reason/);
  assert.equal(returnProblem(open, e, 'Brought back'), null);
  assert.deepEqual(returnPayload(open, e), [{ invoice_item_id: CHAIR, returned: 1 }]);
  const withProduct = goodsFromRpc({ ...OPEN, can_record_return: true, products: [{ ...OPEN.products[0], out: 1 }] });
  assert.deepEqual(returnPayload(withProduct, setReturn(e, PILLOW, 'good', 1)),
    [{ product_id: PILLOW, good: 1, damaged: 0, not_returned: 0 }, { invoice_item_id: CHAIR, returned: 1 }]);
});

test('the copies: Collected / Delivered / To collect, a paid invoice included (answer 6)', () => {
  const delivered = goodsFromRpc({ ...PAID, specials: [
    special({ invoice_item_id: CHAIR, name: 'Massage Chair', quantity: 2, collected: 1, out: 1, to_collect: 1 }),
    special({ invoice_item_id: BED, name: 'Air Bed', is_consignment: true, can_deliver: true, delivered: 1, out: 1, to_collect: 0 })],
    special_to_collect_total: 1 });
  assert.deepEqual(collectionLists(delivered), {
    collected: [{ name: 'Pillow', qty: 1 }, { name: 'Massage Chair', qty: 1 }],
    delivered: [{ name: 'Air Bed', qty: 1 }],
    toCollect: [{ name: 'Massage Chair', qty: 1 }] });
  assert.equal(copyTermsText('paid', delivered), 'Goods and services sold are neither refundable nor exchangeable.');
  assert.deepEqual(copyCollectionLines('paid', delivered),
    ['Collected: Pillow × 1, Massage Chair × 1', 'Delivered: Air Bed × 1', 'To collect: Massage Chair × 1']);
  assert.equal(collectionSummary(copyCollection('paid', delivered)), 'Goods: 2 collected, 1 delivered, 1 to collect.');
  // All collected: a paid copy keeps the standard line and lists nothing, as before.
  const done = goodsFromRpc({ ...PAID, specials: [special({ invoice_item_id: CHAIR, name: 'Massage Chair', collected: 1, out: 1, to_collect: 0 })],
    special_to_collect_total: 0 });
  assert.equal(copyTermsText('paid', done), undefined);
  assert.equal(copyCollection('paid', done), null);
  assert.equal(copyTermsText('paid'), undefined, 'without the goods, as before');
  assert.equal(copyCollection('refunded', delivered), null);
  assert.equal(copyReadsGoods('paid'), true);
  assert.equal(copyReadsGoods('completed_foc'), true);
  assert.equal(copyReadsGoods('cancelled'), false);
  // An open copy with no delivery has exactly 399's two lines.
  assert.deepEqual(collectionText(copyCollection('partially_paid', open)),
    ['Collected: Massage Chair × 1', 'To collect: Pillow × 1, Massage Chair × 1, Air Bed × 1, Heat Lamp (rental) × 1']);
  assert.equal(collectionLineFitted('Delivered', [{ name: 'Air Bed', qty: 1 }], 10, t => t.length), 'Delivered: 1 item');
});

test('the history says Collected, Delivered and Returned for special items; products as 399', () => {
  assert.equal(historyLine({ kind: 'handover', items: [
    { name: 'Pillow', quantity: 1 }, { name: 'Massage Chair', quantity: 1, special: true, how: 'collected' },
    { name: 'Air Bed', quantity: 1, special: true, how: 'delivered' }] }),
    'Handed over Pillow × 1; Collected Massage Chair × 1; Delivered Air Bed × 1');
  assert.equal(historyLine({ kind: 'handover', items: [{ name: 'Heat Lamp (rental)', quantity: 1, special: true, how: 'collected' }] }),
    'Collected Heat Lamp (rental) × 1');
  // Where it was recorded: the button the invoice shows.
  const onlySpecial = { kind: 'handover', source: 'button', items: [{ name: 'Massage Chair', quantity: 1, special: true, how: 'collected' }] };
  assert.equal(historySource(onlySpecial, paid), 'Record items collected', 'a paid invoice: Record items collected');
  assert.equal(historySource(onlySpecial, open), 'Hand over items', 'one with products to hand over: Hand over items');
  assert.equal(historySource({ ...onlySpecial, source: 'payment' }, paid), 'with a payment');
  assert.equal(historySource({ kind: 'handover', source: 'button', items: [{ name: 'Pillow', quantity: 1 }] }, paid), 'Hand over items', 'products as 399');
  assert.equal(historySource({ kind: 'handover', source: 'button', items: [{ name: 'Pillow', quantity: 1 }] }), 'Hand over items', 'without the goods, as 399');
  assert.equal(historyLine({ kind: 'return', items: [{ name: 'Massage Chair', returned: 1, special: true }] }),
    'Returned — Massage Chair: 1 returned');
  assert.equal(historyLine({ kind: 'handover', items: [{ name: 'Pillow', quantity: 2 }] }), 'Handed over Pillow × 2', 'as 399');
});

// ── The components, mounted ─────────────────────────────────────────────────
const dom = setupDom();
const mod = await bundle(`
  import React from 'react';
  export { InvoiceGoodsPanel, HandoverModal, ReturnItemsModal, HandoverQuestion } from './src/components/invoices/InvoiceGoods';
  export { copyCollectionDrawn } from './src/lib/invoicePdf';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`, { stubAuth: true });
const { InvoiceGoodsPanel, HandoverModal, ReturnItemsModal, HandoverQuestion, copyCollectionDrawn, React } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });
const h = React.createElement;

test('the PDF and image copies\' short form adds Delivered only when there is one', () => {
  const g = goodsFromRpc({ ...PAID, specials: [
    special({ invoice_item_id: CHAIR, name: 'Massage Chair', quantity: 2, collected: 1, out: 1, to_collect: 1 }),
    special({ invoice_item_id: BED, name: 'Air Bed', is_consignment: true, can_deliver: true, delivered: 1, out: 1, to_collect: 0 })],
    special_to_collect_total: 1 });
  const measure = t => t.length;
  assert.deepEqual(copyCollectionDrawn({ collection: copyCollection('paid', g), collectionFit: 'short' }, 200, t => [t], measure),
    ['Collected: Pillow × 1, Massage Chair × 1', 'Delivered: Air Bed × 1', 'To collect: Massage Chair × 1']);
  assert.equal(copyCollectionDrawn({ collection: copyCollection('partially_paid', open), collectionFit: 'short' }, 200, t => [t], measure).length, 2);
  assert.deepEqual(copyCollectionDrawn({ collection: copyCollection('paid', g), collectionFit: 'full' }, 200, t => [t], measure),
    collectionText(copyCollection('paid', g)));
});

test('the panel lists the special lines with Delivered, on a paid invoice too', async () => {
  const g = goodsFromRpc({ ...PAID, specials: [
    special({ invoice_item_id: CHAIR, name: 'Massage Chair', quantity: 2, collected: 1, out: 1, to_collect: 1 }),
    special({ invoice_item_id: BED, name: 'Air Bed', is_consignment: true, can_deliver: true, delivered: 1, out: 1, to_collect: 0 })],
    special_collected_total: 1, special_delivered_total: 1, special_to_collect_total: 1 });
  await d.mount(h(InvoiceGoodsPanel, { goods: g, onRecordReturn: () => {} }));
  const table = document.querySelector('[data-testid="invoice-goods-specials"]');
  assert.ok(table, 'the special lines are shown');
  assert.match(table.textContent, /Massage Chair/);
  assert.match(table.textContent, /Delivered/);
  assert.match(d.text(), /Goods — 2 collected, 1 delivered, 1 to collect/);
  assert.ok(d.button('Record items returned'), 'the Owner or Manager can record them returned');
});

test('Record items collected on a paid invoice: Delivered for the consignment line, the payload sent', async () => {
  const fake = fakeSupabase({ rpc: { record_invoice_handover: args => ({ success: true, items: [],
    specials: [{ name: 'Air Bed', quantity: 1, how: 'delivered' }] }) } });
  globalThis.__supabase = fake;
  let done = null;
  await d.mount(h(HandoverModal, { goods: paid, onClose: () => {}, onDone: m => { done = m; } }));
  assert.match(d.text(), /Record items collected — INV-2026-9201/);
  assert.ok(document.querySelector('[data-testid="handover-special-note"]'));
  assert.equal(document.querySelectorAll('[data-testid="handover-special"]').length, 3);
  assert.ok(!document.querySelector('input[aria-label="Pillow: how many taken now"]'), 'no product on a paid invoice');
  const how = document.querySelector('select[aria-label="Air Bed: collected or delivered"]');
  assert.ok(how, 'the consignment line offers Delivered');
  assert.equal(document.querySelectorAll('select').length, 1, 'only the consignment line has the choice');
  // Nothing entered yet: the hint under the lines and one line above Record.
  assert.equal(document.querySelector('[data-testid="handover-hint"]').textContent, 'Enter how many the customer takes now.');
  assert.equal(document.querySelector('[data-testid="handover-need-one"]').textContent, 'Enter at least one item.');
  assert.ok(!d.text().includes('Enter how many of at least one item'), 'not the old words');
  await d.setValue(how, 'delivered');
  await d.setValue(document.querySelector('input[aria-label="Air Bed: how many delivered now"]'), '1');
  assert.equal(document.querySelector('[data-testid="handover-need-one"]'), null, 'gone once one is entered');
  assert.equal(document.querySelector('[data-testid="handover-hint"]'), null);
  await d.click(d.button('Record'));
  const call = fake.calls.find(c => c.rpc === 'record_invoice_handover');
  assert.deepEqual(call.args.p_handover, { items: [], specials: [{ invoice_item_id: BED, qty: 1, how: 'delivered' }] });
  assert.equal(done, 'Recorded: Air Bed × 1 delivered.');
});

test('Record Payment\'s question lists the special items with the products', async () => {
  await d.mount(h(HandoverQuestion, { goods: open, answer: 'items', pick: emptyPick(), onAnswer: () => {}, onPick: () => {} }));
  assert.ok(document.querySelector('input[aria-label="Pillow: how many taken now"]'));
  assert.ok(document.querySelector('input[aria-label="Massage Chair: how many taken now"]'));
  assert.ok(document.querySelector('input[aria-label="Heat Lamp (rental): how many taken now"]'));
  assert.match(d.text(), /recorded as collected; an Owner or Manager then releases them/);
});

test('Record items returned: a Returned box per special line out; the payload sent', async () => {
  const fake = fakeSupabase({ rpc: { record_invoice_goods_return: () => ({ success: true }) } });
  globalThis.__supabase = fake;
  await d.mount(h(ReturnItemsModal, { goods: paid, onClose: () => {}, onDone: () => {} }));
  assert.equal(document.querySelectorAll('[data-testid="return-special"]').length, 1);
  assert.ok(!document.querySelector('input[aria-label="Pillow: good"]'), 'a paid invoice\'s products are not offered');
  await d.setValue(document.querySelector('input[aria-label="Massage Chair: returned"]'), '1');
  await d.setValue([...document.querySelectorAll('input')].find(i => i.placeholder.startsWith('e.g.')), 'Brought back');
  await d.click(d.button('Record'));
  const call = fake.calls.find(c => c.rpc === 'record_invoice_goods_return');
  assert.deepEqual(call.args.p_items, [{ invoice_item_id: CHAIR, returned: 1 }]);
});
