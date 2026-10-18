// What the Exchanges page asks before it sends an exchange (408, 424).
//
// Run: node --test scripts/exchanges/tests/rules.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  exchangePaymentMethods, componentsExchanged, bundleLineBlock, exchangePaymentProblem,
  exchangePaymentRowProblem, bundleQuoteFromRpc, affiliateHint,
  creditPreviewFromRpc, productLinesCredit, componentCredit, creditBasisText,
  exchangeDay, displayDay, instalmentLabelFrom,
  saleDay, exchangeDateFloor, exchangeDateProblem, exchangeDateHint,
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
  // product and component exchanges: the whole charge is taken now too; an
  // instalment only labels it (no "balance stays owed")
  assert.equal(exchangePaymentProblem({ due: 20, received: 5, exact: false }),
    'S$15.00 of the additional charge is not entered yet. The whole charge is taken now; an instalment only records how it is paid.');
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
    todays_value: null, paid: null,
    returned: [{ product_id: 'p-a', name: 'A', quantity: 1 }], replacement_items: [] });
  // 424: the two figures behind the credit
  const q2 = bundleQuoteFromRpc({ problem: null, credit: '150', todays_value: '200.00', paid: 150, replacement: 360, topup: 210 });
  assert.equal(q2.todays_value, 200); assert.equal(q2.paid, 150); assert.equal(q2.credit, 150);
  assert.equal(bundleQuoteFromRpc({ problem: 'Bundle "X" has ended' }).problem, 'Bundle "X" has ended');
});

test('the affiliate line says what an exchange left empty is credited to', () => {
  assert.equal(affiliateHint(null), 'The original sale had no affiliate, so left empty this exchange has none.');
  assert.equal(affiliateHint({ affiliate: 'Pat Referrer', affiliate_inherited_id: 'ca-1' }),
    "Left empty, this exchange keeps the original sale's affiliate (Pat Referrer).");
  assert.equal(affiliateHint({ affiliate: 'Pat Referrer', affiliate_inherited_id: null }),
    'Original sale: Pat Referrer (no longer eligible), so left empty this exchange has no affiliate.');
});

// ── 424 ────────────────────────────────────────────────────────────────────
const PREVIEW = {
  lines: [
    { invoice_item_id: 'li-a', line_kind: 'product', quantity: 1, todays: '100.00', paid: '75.00', credit: '75.00' },
    { invoice_item_id: 'li-d', line_kind: 'product', quantity: 2, todays: 100, paid: 120, credit: 100 },
    { invoice_item_id: 'li-x', line_kind: 'product', quantity: 1, todays: null, paid: 50, credit: null },
    { invoice_item_id: 'li-ab', line_kind: 'promotion', quantity: 1, todays: 200, paid: 150, credit: 150,
      components: [{ product_id: 'p-a', quantity: 2, options: [
        { quantity: 1, todays: 100, paid: 75, credit: 75 }, { quantity: 2, todays: 200, paid: 150, credit: 150 }] }] },
  ],
};

test('the credit preview is read with every number a number, a missing price as null', () => {
  assert.equal(creditPreviewFromRpc(null), null);
  assert.equal(creditPreviewFromRpc({ problem: 'x' }), null);
  const p = creditPreviewFromRpc(PREVIEW);
  assert.deepEqual(p.lines[0], { invoice_item_id: 'li-a', line_kind: 'product', quantity: 1, todays: 100, paid: 75, credit: 75, components: [] });
  assert.equal(p.lines[2].credit, null);
  assert.equal(p.lines[3].components[0].options[1].credit, 150);
});

test('the chosen lines count for the lower figure each; a line with no price stops it', () => {
  const p = creditPreviewFromRpc(PREVIEW);
  assert.deepEqual(productLinesCredit(p, ['li-a']), { todays: 100, paid: 75, credit: 75, missing: false });
  assert.deepEqual(productLinesCredit(p, ['li-a', 'li-d']), { todays: 200, paid: 195, credit: 175, missing: false });
  assert.equal(productLinesCredit(p, ['li-a', 'li-x']).credit, null);
  assert.equal(productLinesCredit(p, ['li-a', 'li-x']).missing, true);
  assert.equal(productLinesCredit(null, ['li-a']).missing, true, 'no preview: nothing can be valued');
  assert.deepEqual(productLinesCredit(p, []), { todays: 0, paid: 0, credit: 0, missing: false });
  assert.deepEqual(componentCredit(p, 'li-ab', 'p-a', 2), { todays: 200, paid: 150, credit: 150 });
  assert.equal(componentCredit(p, 'li-ab', 'p-a', 3), null);
  assert.equal(componentCredit(p, 'li-ab', 'p-z', 1), null);
});

test('the page says which figure counts', () => {
  assert.equal(creditBasisText({ todays: 100, paid: 75, credit: 75 }),
    "Counts for what was paid (S$75.00), which is less than today's price (S$100.00).");
  assert.equal(creditBasisText({ todays: 80, paid: 100, credit: 80 }),
    "Counts for today's price (S$80.00), which is less than what was paid (S$100.00).");
  assert.equal(creditBasisText({ todays: 100, paid: 100, credit: 100 }),
    "Counts for S$100.00: today's price and what was paid are the same.");
  assert.equal(creditBasisText({ todays: 100, paid: 0, credit: 0 }), 'It was free, so it gives no credit.');
  assert.equal(creditBasisText({ todays: null, paid: 50, credit: null }), 'No price at this store, so it cannot be valued here.');
  assert.equal(creditBasisText(null), '');
  // one item of a bundle: its share of what the bundle was paid
  assert.equal(creditBasisText({ todays: 100, paid: 50, credit: 50 }, true),
    "Counts for its share of what the bundle was paid (S$50.00), which is less than today's price (S$100.00).");
  assert.equal(creditBasisText({ todays: 100, paid: 200, credit: 100 }, true),
    "Counts for today's price (S$100.00), which is less than its share of what the bundle was paid (S$200.00).");
  // several lines: one cheaper today (100 paid, 60 today), one bought at less
  // (50 paid, 100 today): each counts for its own lower figure, 110 in all
  assert.equal(creditBasisText({ todays: 160, paid: 150, credit: 110 }),
    'Each item counts for the lower of its own two figures: S$110.00 in all.');
  assert.equal(creditBasisText({ todays: 100, paid: 100, credit: 100 }, true),
    "Counts for S$100.00: today's price and its share of what the bundle was paid are the same.");
  assert.equal(creditBasisText({ todays: 100, paid: 0, credit: 0 }, true), 'The bundle was free, so it gives no credit.');
});

test('an exchange is dated by its exchange date, else the Singapore day it was saved', () => {
  assert.equal(exchangeDay({ exchange_date: '2026-10-05', created_at: '2026-10-08T03:00:00Z' }), '2026-10-05');
  // 01:30 on 9 Oct in Singapore is still 8 Oct in UTC
  assert.equal(exchangeDay({ exchange_date: null, created_at: '2026-10-08T17:30:00Z' }), '2026-10-09');
  assert.equal(exchangeDay({}), '');
  assert.equal(displayDay('2026-10-09'), '9 Oct 2026');
  assert.equal(displayDay('2026-13-01'), '');
  assert.equal(displayDay(''), '');
});

test('the instalment label is the last Instalment row with money and a method', () => {
  const rows = [
    { payment_method_id: 'cash', amount: 10 },
    { payment_method_id: 'instalment', amount: 50, instalment: { method_id: 'card', months: 6 } },
    { payment_method_id: 'instalment', amount: 0, instalment: { method_id: 'atome', months: 3 } },
  ];
  assert.deepEqual(instalmentLabelFrom(rows, 'instalment'), { method_id: 'card', months: 6 });
  assert.deepEqual(instalmentLabelFrom([...rows, { payment_method_id: 'instalment', amount: 5, instalment: { method_id: 'grab', months: '12' } }], 'instalment'),
    { method_id: 'grab', months: 12 });
  assert.equal(instalmentLabelFrom([{ payment_method_id: 'cash', amount: 10 }], 'instalment'), null);
  assert.equal(instalmentLabelFrom([{ payment_method_id: 'instalment', amount: 10, instalment: { method_id: '', months: 6 } }], 'instalment'), null);
  assert.equal(instalmentLabelFrom(null, 'instalment'), null);
});

test('424: an exchange is dated from the 1st of this month, never before the original sale', () => {
  // the original sale's day: its invoice date, else the Singapore day it was made
  assert.equal(saleDay({ business_date: '2026-10-06', created_at: '2026-10-08T03:00:00Z' }), '2026-10-06');
  assert.equal(saleDay({ business_date: null, created_at: '2026-10-08T17:30:00Z' }), '2026-10-09');
  assert.equal(saleDay(null), '');
  // the earliest day: the 1st of this month, or the sale's day if later
  assert.equal(exchangeDateFloor('2026-10-09', '2026-09-28'), '2026-10-01');
  assert.equal(exchangeDateFloor('2026-10-09', '2026-10-06'), '2026-10-06');
  assert.equal(exchangeDateFloor('2026-10-09', ''), '2026-10-01');
  assert.equal(exchangeDateFloor('2026-11-01', '2026-10-30'), '2026-11-01');
  // what is refused, and why
  assert.equal(exchangeDateProblem('', '2026-10-09', '2026-10-06'), null);
  assert.equal(exchangeDateProblem('2026-10-07', '2026-10-09', '2026-10-06'), null);
  assert.equal(exchangeDateProblem('2026-10-09', '2026-10-09', '2026-10-06'), null);
  assert.equal(exchangeDateProblem('2026-10-10', '2026-10-09', '2026-10-06'), 'An exchange cannot be dated in the future.');
  assert.equal(exchangeDateProblem('2026-09-30', '2026-10-09', '2026-09-28'),
    'An exchange can be dated from the 1st of this month (1 Oct 2026) at the earliest. An earlier month may already be in Xero.');
  assert.equal(exchangeDateProblem('2026-10-05', '2026-10-09', '2026-10-06'),
    'An exchange cannot be dated before the original sale (6 Oct 2026).');
  assert.equal(exchangeDateProblem('2026-10-31', '2026-11-01', '2026-10-30'),
    'An exchange can be dated from the 1st of this month (1 Nov 2026) at the earliest. An earlier month may already be in Xero.');
  assert.equal(exchangeDateProblem('9/10/2026', '2026-10-09', ''), 'Choose a valid exchange date.');
  // the line under the date says which day the sale counts on
  assert.equal(exchangeDateHint('2026-10-07', '2026-10-09'),
    'This exchange counts on 7 Oct 2026 in the sales reports, commission and Xero, not on the day you save it.');
  assert.equal(exchangeDateHint('2026-10-09', '2026-10-09'),
    'The replacement sale counts on this date in the sales reports, commission and Xero.');
  assert.equal(exchangeDateHint('', '2026-10-09'),
    'The replacement sale counts on this date in the sales reports, commission and Xero.');
});
