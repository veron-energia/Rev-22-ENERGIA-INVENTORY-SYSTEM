// What the Exchanges page asks before it sends an exchange (408).
//
// Run: node --test scripts/exchanges/tests/rules.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  exchangePaymentMethods, componentsExchanged, bundleLineBlock, exchangePaymentProblem,
  exchangePaymentRowProblem, bundleQuoteFromRpc, affiliateHint,
} from '../../../src/lib/exchanges/rules.mjs';

test('no Wallet method, inactive or deleted method pays an exchange', () => {
  const methods = [
    { id: 'cash', name: 'Cash', is_active: true, deleted_at: null, is_wallet_credit: false },
    { id: 'w', name: 'Wallet — Exchange Credit', is_active: true, deleted_at: null, is_wallet_credit: true },
    { id: 'old', name: 'Old card', is_active: false, deleted_at: null },
    { id: 'gone', name: 'Gone', is_active: true, deleted_at: '2026-01-01T00:00:00Z' },
    { id: 'card', name: 'Card' },
  ];
  assert.deepEqual(exchangePaymentMethods(methods).map(m => m.id), ['cash', 'card']);
  assert.deepEqual(exchangePaymentMethods(null), []);
});

test('a whole bundle is one bundle whose items were not exchanged on their own', () => {
  const line = { quantity: 1, exchanged_at: null, component_exchanged: null };
  assert.equal(bundleLineBlock(line, 'bundle'), null);
  assert.equal(bundleLineBlock(line, 'component'), null);
  assert.equal(bundleLineBlock({ ...line, exchanged_at: '2026-10-09' }, 'component'), 'already exchanged');
  assert.equal(bundleLineBlock({ ...line, exchanged_at: '2026-10-09' }, 'bundle'), 'already exchanged');
  assert.equal(bundleLineBlock({ ...line, quantity: 2 }, 'bundle'), '2 bundles on this line: use Bundle component');
  assert.equal(bundleLineBlock({ ...line, quantity: 2 }, 'component'), null);
  const swapped = { ...line, component_exchanged: [{ product_id: 'p-a', qty: 1, exchange_id: 'ex' }] };
  assert.match(bundleLineBlock(swapped, 'bundle'), /already exchanged on its own/);
  assert.equal(bundleLineBlock(swapped, 'component'), null);
  assert.deepEqual(componentsExchanged(swapped), ['p-a']);
  assert.deepEqual(componentsExchanged(line), []);
});

test('nothing when nothing is due, never more than is due, a whole bundle exactly', () => {
  assert.match(exchangePaymentProblem({ due: 0, received: 50, exact: true }), /^Nothing is due .*\(S\$50\.00 entered\)/);
  assert.match(exchangePaymentProblem({ due: 0, received: 5, exact: false }), /^Nothing is due/);
  assert.equal(exchangePaymentProblem({ due: 0, received: 0, exact: true }), null);
  assert.equal(exchangePaymentProblem({ due: 160, received: 160, exact: true }), null);
  assert.equal(exchangePaymentProblem({ due: 160, received: 159.999, exact: true }), null);
  assert.equal(exchangePaymentProblem({ due: 160, received: 100, exact: true }),
    'This exchange needs exactly S$160.00 paid now (S$100.00 entered).');
  assert.equal(exchangePaymentProblem({ due: 160, received: 200, exact: true }),
    'Payments (S$200.00) exceed the additional charge of S$160.00.');
  // product and component exchanges: the rest is taken now or under an instalment
  assert.match(exchangePaymentProblem({ due: 20, received: 5, exact: false }), /^S\$15\.00 of the additional charge is unaccounted for/);
  assert.equal(exchangePaymentProblem({ due: 20, received: 20, exact: false }), null);
});

test('every payment row with an amount has a method an exchange may use', () => {
  const allowed = ['cash', 'card'];
  assert.equal(exchangePaymentRowProblem([{ payment_method_id: 'cash', amount: 20 }], allowed, 'instalment'), null);
  // left on "— Method —": counted as received, never sent
  assert.equal(exchangePaymentRowProblem([{ payment_method_id: 'cash', amount: 10 }, { payment_method_id: '', amount: 10 }], allowed, 'instalment'),
    'Choose a payment method for the S$10.00 entered, or remove that payment.');
  assert.equal(exchangePaymentRowProblem([{ payment_method_id: null, amount: '7.5' }], allowed, 'instalment'),
    'Choose a payment method for the S$7.50 entered, or remove that payment.');
  // an empty row with nothing in it is harmless (it is not sent)
  assert.equal(exchangePaymentRowProblem([{ payment_method_id: '', amount: 0 }], allowed, 'instalment'), null);
  // wallet credit (not in the allowed list) and a negative amount
  assert.equal(exchangePaymentRowProblem([{ payment_method_id: 'wallet', amount: 20 }], allowed, 'instalment'),
    'Choose a payment method for each payment. Wallet credit cannot pay an exchange.');
  assert.equal(exchangePaymentRowProblem([{ payment_method_id: 'cash', amount: 30 }, { payment_method_id: 'card', amount: -10 }], allowed, 'instalment'),
    'A payment amount cannot be negative.');
  // the Instalment choice names its real method in its own fields (portionProblem)
  assert.equal(exchangePaymentRowProblem([{ payment_method_id: 'instalment', amount: 20 }], allowed, 'instalment'), null);
  assert.equal(exchangePaymentRowProblem(null, allowed, 'instalment'), null);
});

test('the preview is read with every number a number', () => {
  assert.equal(bundleQuoteFromRpc(null), null);
  const q = bundleQuoteFromRpc({ problem: null, credit: '200', replacement: 360, topup: '160.00', nonrefundable: 0,
    returned: [{ product_id: 'p-a', name: 'A', quantity: '1' }], replacement_items: null });
  assert.deepEqual(q, { problem: null, credit: 200, replacement: 360, topup: 160, nonrefundable: 0,
    returned: [{ product_id: 'p-a', name: 'A', quantity: 1 }], replacement_items: [] });
  assert.equal(bundleQuoteFromRpc({ problem: 'Bundle "X" has ended' }).problem, 'Bundle "X" has ended');
});

test('the affiliate line says what an exchange left empty is credited to', () => {
  assert.equal(affiliateHint(null), 'The original sale had no affiliate, so left empty this exchange has none.');
  assert.equal(affiliateHint({ affiliate: 'Pat Referrer', affiliate_inherited_id: 'ca-1' }),
    "Left empty, this exchange keeps the original sale's affiliate (Pat Referrer).");
  assert.equal(affiliateHint({ affiliate: 'Pat Referrer', affiliate_inherited_id: null }),
    'Original sale: Pat Referrer (no longer eligible), so left empty this exchange has no affiliate.');
});
