/**
 * Which QR a payment method shows at the till, and whose (Owner, 6 Oct 2026).
 *
 * PayNow, GrabPay and Atome, matched by name, show the invoice's store's QR;
 * a store without one borrows another active store's, always the same one.
 * Every other method, wallet credit included, shows nothing. The method names
 * below are production's active ones; store ids and image addresses are
 * invented.
 *
 * Run: node --test scripts/invoices/tests/payment-qr.test.mjs
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PAYMENT_QR_KINDS, paymentQrKind, paymentQrImage, paymentQrFor, paymentQrAmount }
  from '../../../src/lib/invoices/paymentQr.mjs';

const field = name => paymentQrKind({ name })?.field ?? null;
const img = (store, kind) => `https://assets.invalid/store-assets/${store}/${kind}.png?v=1`;

const ADELPHI = {
  id: 'store-adelphi', name: 'Energia Rev 22 (Adelphi)', is_active: true, deleted_at: null,
  created_at: '2026-07-03T07:35:38.0706+00:00',
  qr_paynow_url: img('adelphi', 'qr_paynow_url'), qr_grabpay_url: img('adelphi', 'qr_grabpay_url'),
  qr_atome_url: img('adelphi', 'qr_atome_url'),
};
const VAN = {
  id: 'store-van', name: 'Energia Van & RoadShow', is_active: true, deleted_at: null,
  created_at: '2026-07-30T04:10:44.370518+00:00',
  qr_paynow_url: null, qr_grabpay_url: null, qr_atome_url: null,
};

test('PayNow, GrabPay and Atome each show their own image', () => {
  assert.equal(field('PayNow'), 'qr_paynow_url');
  assert.equal(field('GrabPay'), 'qr_grabpay_url');
  assert.equal(field('Atome'), 'qr_atome_url');
  assert.deepEqual(PAYMENT_QR_KINDS.map(k => k.label), ['PayNow', 'GrabPay', 'Atome']);
});

test('the full-payment methods show the same image as their app', () => {
  assert.equal(field('GrabPay Full Payment'), 'qr_grabpay_url');
  assert.equal(field('Atome full payment'), 'qr_atome_url');
  assert.equal(paymentQrKind({ name: 'Atome full payment' })?.label, 'Atome');
});

test('every other active production method shows nothing', () => {
  for (const name of ['HitPay (online)', 'Stripe (online)', 'Cash', 'Visa Card', 'Master Card',
    'American Express', 'Credit Card', 'Debit Card', 'Bank Transfer']) {
    assert.equal(field(name), null, `${name} must not pop up a QR`);
  }
});

test('wallet credit never shows one, by its flag and whatever its name', () => {
  for (const name of ['Wallet — Bonus Credit', 'Wallet — Exchange Credit', 'Wallet — Legacy Credit',
    'Wallet — Paid Credit', 'Wallet — Promotional/FOC Credit', 'Wallet — PayNow top-up']) {
    assert.equal(paymentQrKind({ name, is_wallet_credit: true }), null, `${name} must not pop up a QR`);
  }
});

test('names match whatever their case or spacing', () => {
  assert.equal(field('PAYNOW'), 'qr_paynow_url');
  assert.equal(field('Pay Now'), 'qr_paynow_url');
  assert.equal(field('grab-pay'), 'qr_grabpay_url');
  assert.equal(field(' atome '), 'qr_atome_url');
  // Retired plans are no longer offered, but read by name they are still Atome or GrabPay.
  assert.equal(field('Atome 6 months plan'), 'qr_atome_url');
  assert.equal(field('GrabPay 1 year plan'), 'qr_grabpay_url');
});

test('no method, or a nameless one, shows nothing', () => {
  assert.equal(paymentQrKind(null), null);
  assert.equal(paymentQrKind(undefined), null);
  assert.equal(paymentQrKind({ name: '' }), null);
  assert.equal(paymentQrKind({ name: null }), null);
  assert.equal(paymentQrFor({ name: 'Cash' }, ADELPHI.id, [ADELPHI]), null);
});

test("the invoice's own store's image comes first", () => {
  assert.deepEqual(paymentQrImage('qr_paynow_url', ADELPHI.id, [VAN, ADELPHI]), {
    url: ADELPHI.qr_paynow_url, storeId: ADELPHI.id, storeName: ADELPHI.name, borrowed: false,
  });
  const ownGrab = { ...VAN, qr_grabpay_url: img('van', 'qr_grabpay_url') };
  assert.equal(paymentQrImage('qr_grabpay_url', VAN.id, [ADELPHI, ownGrab])?.url, ownGrab.qr_grabpay_url,
    'a store with its own image never borrows');
});

test('a store without one borrows the other store’s, and says so', () => {
  const qr = paymentQrFor({ name: 'GrabPay Full Payment' }, VAN.id, [VAN, ADELPHI]);
  assert.deepEqual(qr, {
    field: 'qr_grabpay_url', label: 'GrabPay', methodName: 'GrabPay Full Payment',
    image: { url: ADELPHI.qr_grabpay_url, storeId: ADELPHI.id, storeName: ADELPHI.name, borrowed: true },
  });
});

test('the store borrowed from is always the same one: oldest, then by name, then id', () => {
  const later = { ...ADELPHI, id: 'store-later', name: 'A Newer Store', created_at: '2026-09-01T00:00:00+00:00',
    qr_atome_url: img('later', 'qr_atome_url') };
  for (const stores of [[VAN, later, ADELPHI], [ADELPHI, later, VAN], [later, VAN, ADELPHI]]) {
    assert.equal(paymentQrImage('qr_atome_url', VAN.id, stores)?.storeId, ADELPHI.id,
      'the oldest store with an image wins, whatever order the stores arrived in');
  }
  const twinA = { ...ADELPHI, id: 'store-b', name: 'Beta', created_at: '2026-07-03T07:35:38.0706+00:00' };
  const twinB = { ...ADELPHI, id: 'store-a', name: 'alpha', created_at: '2026-07-03T15:35:38.0706+08:00' };
  assert.equal(paymentQrImage('qr_paynow_url', VAN.id, [twinA, twinB])?.storeId, 'store-a',
    'the same moment in two time zones ties, and the name decides');
  const undated = { ...ADELPHI, id: 'store-undated', name: 'Aardvark', created_at: null };
  assert.equal(paymentQrImage('qr_paynow_url', VAN.id, [undated, ADELPHI])?.storeId, ADELPHI.id,
    'a store with no date comes after the dated ones');
});

test('inactive and deleted stores are never shown, not even as the invoice’s own', () => {
  const closed = { ...ADELPHI, is_active: false };
  const gone = { ...ADELPHI, deleted_at: '2026-10-01T00:00:00+00:00' };
  assert.equal(paymentQrImage('qr_paynow_url', VAN.id, [VAN, closed]), null);
  assert.equal(paymentQrImage('qr_paynow_url', VAN.id, [VAN, gone]), null);
  assert.equal(paymentQrImage('qr_paynow_url', ADELPHI.id, [closed]), null);
});

test('a blank image is no image', () => {
  const blank = { ...VAN, qr_paynow_url: '   ' };
  assert.equal(paymentQrImage('qr_paynow_url', VAN.id, [blank, ADELPHI])?.storeId, ADELPHI.id);
  const padded = { ...VAN, qr_paynow_url: `  ${img('van', 'qr_paynow_url')}  ` };
  assert.equal(paymentQrImage('qr_paynow_url', VAN.id, [padded])?.url, img('van', 'qr_paynow_url'));
});

test('when no store has the image there is nothing to pop up', () => {
  const qr = paymentQrFor({ name: 'PayNow' }, VAN.id, [VAN]);
  assert.deepEqual(qr, { field: 'qr_paynow_url', label: 'PayNow', methodName: 'PayNow', image: null });
  assert.equal(paymentQrFor({ name: 'PayNow' }, VAN.id, [])?.image, null);
  assert.equal(paymentQrFor({ name: 'PayNow' }, VAN.id, null)?.image, null);
});

test('an invoice with no store still borrows', () => {
  assert.equal(paymentQrImage('qr_atome_url', null, [VAN, ADELPHI])?.borrowed, true);
  assert.equal(paymentQrImage('qr_atome_url', 'store-unknown', [VAN, ADELPHI])?.storeId, ADELPHI.id);
});

test('only the three image fields are ever read', () => {
  assert.equal(paymentQrImage('company_logo_url', ADELPHI.id, [{ ...ADELPHI, company_logo_url: img('a', 'logo') }]), null);
});

test('the amount reads as the page prints money, or not at all', () => {
  assert.equal(paymentQrAmount(1080), 'S$1080.00');
  assert.equal(paymentQrAmount('12.5'), 'S$12.50');
  assert.equal(paymentQrAmount(0.1 + 0.2), 'S$0.30');
  for (const none of [0, -5, '', null, undefined, NaN, 'abc']) {
    assert.equal(paymentQrAmount(none), null, `${String(none)} is no amount`);
  }
});
