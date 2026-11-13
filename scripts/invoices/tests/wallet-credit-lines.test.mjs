// Wallet credit as a line under Discount on an invoice's copies and screen
// (the user's answers, 13 Nov 2026): src/lib/invoices/walletCreditLines.mjs.
//
// The customers, invoices and amounts are invented.
//
// Run: node --test scripts/invoices/tests/wallet-credit-lines.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { walletCredit, walletLineLabel, PACKAGE_LINE_LABELS } from '../../../src/lib/invoices/walletCreditLines.mjs';

const METHODS = {
  cash: { name: 'Cash', is_wallet_credit: false },
  paynow: { name: 'PayNow', is_wallet_credit: false },
  'pk-paid': { name: 'Wallet — Credit Package Paid', is_wallet_credit: true, wallet_category: 'paid', wallet_source: 'credit_package' },
  'pk-bonus': { name: 'Wallet — Credit Package Bonus', is_wallet_credit: true, wallet_category: 'bonus', wallet_source: 'credit_package' },
  'pb-paid': { name: 'Wallet — Premium Bundle Paid', is_wallet_credit: true, wallet_category: 'paid', wallet_source: 'premium_bundle' },
  'pb-bonus': { name: 'Wallet — Premium Bundle Bonus', is_wallet_credit: true, wallet_category: 'bonus', wallet_source: 'premium_bundle' },
  'other-paid': { name: 'Wallet — Paid Credit', is_wallet_credit: true, wallet_category: 'paid', wallet_source: null },
  legacy: { name: 'Wallet — Legacy Credit', is_wallet_credit: true, wallet_category: 'legacy', wallet_source: null },
};
let n = 0;
const pay = (method, amount, extra = {}) => ({ id: `p${++n}`, payment_method_id: method, amount, entry_kind: 'receipt', ...extra });
// The label each payment row prints (the page's paymentLabel): the method's name and, for a method naming no
// source, the source of its credit in brackets.
const rowLabel = (p, brackets = {}) => `${METHODS[p.payment_method_id].name}${brackets[p.id] ?? ''}`;
const run = (payments, extra = {}) => walletCredit({
  payments,
  isWallet: p => !!METHODS[p.payment_method_id]?.is_wallet_credit,
  lineLabel: p => walletLineLabel(rowLabel(p, extra.brackets), METHODS[p.payment_method_id]),
  refunds: 'refunds' in extra ? extra.refunds : [],
  refunded: extra.refunded ?? 0,
  total: extra.total,
  day: at => `day(${at})`,
});

test("the user's example: S$327 all from Credit Package credit prints the credit's line and Total S$0.00", () => {
  const w = run([pay('pk-paid', '327.00')], { total: '327.00' });
  assert.deepEqual(w.lines, [{ label: 'Wallet — Credit Package', amount: 327, returned: [] }]);
  assert.equal(w.credit, 327);
  assert.equal(w.totalLeft, 0);
  assert.deepEqual(w.moneyPayments, []);
  assert.equal(w.moneyPaid, 0);
  assert.equal(w.moneyRefunded, 0);
});

test('part credit, part money: Total is what the credit left, and only the money is a payment row', () => {
  const card = pay('paynow', 127);
  const w = run([pay('pk-paid', 200), card], { total: 327 });
  assert.deepEqual(w.lines.map(l => [l.label, l.amount]), [['Wallet — Credit Package', 200]]);
  assert.equal(w.totalLeft, 127);
  assert.deepEqual(w.moneyPayments, [card]);
  assert.equal(w.moneyPaid, 127);
});

test("a package's Paid and Bonus credit add together; each package is its own line, in the order paid", () => {
  const w = run([pay('pb-paid', 100), pay('pk-paid', 300), pay('pk-bonus', 27.5), pay('pb-bonus', 10)], { total: 437.5 });
  assert.deepEqual(w.lines.map(l => [l.label, l.amount]), [['Wallet — Premium Bundle', 110], ['Wallet — Credit Package', 327.5]]);
  assert.equal(w.credit, 437.5);
  assert.equal(w.totalLeft, 0);
});

test('other wallet methods keep their own name, brackets included (cash, Legacy and Paid Credit on one invoice)', () => {
  const cash = pay('cash', '2349.50');
  const legacy = pay('legacy', '2527.50');
  const other = pay('other-paid', '3994.00');
  const w = run([cash, legacy, other], { total: '8871.00', brackets: { [other.id]: ' (Premium Bundle)' } });
  assert.deepEqual(w.lines.map(l => [l.label, l.amount]), [['Wallet — Legacy Credit', 2527.5], ['Wallet — Paid Credit (Premium Bundle)', 3994]]);
  assert.equal(w.totalLeft, 2349.5);
  assert.deepEqual(w.moneyPayments, [cash]);
  assert.equal(walletLineLabel('Wallet — Paid Credit', METHODS['other-paid']), 'Wallet — Paid Credit');
  assert.equal(walletLineLabel('Wallet — Credit Package Bonus', METHODS['pk-bonus']), PACKAGE_LINE_LABELS.credit_package);
  assert.equal(walletLineLabel(null, null), '');
});

test('no wallet credit, or all of it reversed: null, and the invoice shows as before', () => {
  assert.equal(run([pay('cash', 50)], { total: 50 }), null);
  assert.equal(run([], { total: 50 }), null);
  // A wallet payment corrected to cash: the reversal cancels it.
  const first = pay('pk-paid', 80);
  const w = run([first, pay('pk-paid', 80, { entry_kind: 'correction_reversal', corrects_payment_id: first.id }),
    pay('cash', 80, { entry_kind: 'correction_replacement' })], { total: 80 });
  assert.equal(w, null);
});

test('a corrected wallet amount counts net; the money rows are only the money, reversals as they are', () => {
  const first = pay('pk-paid', 300);
  const back = pay('pk-paid', 300, { entry_kind: 'correction_reversal', corrects_payment_id: first.id });
  const again = pay('pk-paid', 250, { entry_kind: 'correction_replacement' });
  const cash = pay('cash', 50);
  const w = run([first, back, again, cash], { total: 300 });
  assert.deepEqual(w.lines.map(l => [l.label, l.amount]), [['Wallet — Credit Package', 250]]);
  assert.equal(w.totalLeft, 50);
  assert.deepEqual(w.moneyPayments, [cash]);
});

test('credit refunded back to the wallet is a note under its own line, with its day; the line keeps the credit used', () => {
  // S$921 from Credit Package credit, then S$327 of it back into the wallet.
  const used = pay('pk-paid', '921.00');
  const w = run([used], { total: '921.00', refunded: '327.00',
    refunds: [{ payment_id: used.id, amount: '327.00', credit_returned: '327.00', created_at: '2026-11-11T06:34:36Z' }] });
  assert.deepEqual(w.lines, [{ label: 'Wallet — Credit Package', amount: 921, returned: ['S$327.00 returned to wallet day(2026-11-11T06:34:36Z)'] }]);
  assert.equal(w.totalLeft, 0);
  assert.equal(w.moneyRefunded, 0, 'credit put back is not money refunded');
});

test('each refund finds the line of the payment it went back to; earliest first; a missing payment uses the first line', () => {
  const pk = pay('pk-paid', 100), other = pay('other-paid', 60);
  const w = run([pk, other], { total: 160, refunded: 70, refunds: [
    { payment_id: other.id, amount: 40, credit_returned: 40, created_at: '2026-11-12T01:00:00Z' },
    { payment_id: other.id, amount: 10, credit_returned: 10, created_at: '2026-11-10T01:00:00Z' },
    { payment_id: 'gone', amount: 20, credit_returned: 20, created_at: '2026-11-11T01:00:00Z' },
  ] });
  assert.deepEqual(w.lines.map(l => [l.label, l.returned]), [
    ['Wallet — Credit Package', ['S$20.00 returned to wallet day(2026-11-11T01:00:00Z)']],
    ['Wallet — Paid Credit', ['S$10.00 returned to wallet day(2026-11-10T01:00:00Z)', 'S$40.00 returned to wallet day(2026-11-12T01:00:00Z)']],
  ]);
});

test('money refunded is only what did not go back to the wallet', () => {
  const pk = pay('pk-paid', 100), cash = pay('cash', 200);
  const w = run([pk, cash], { total: 300, refunded: 150, refunds: [
    { payment_id: cash.id, amount: 120, credit_returned: 0, created_at: '2026-11-12T01:00:00Z' },
    { payment_id: pk.id, amount: 30, credit_returned: 30, created_at: '2026-11-12T02:00:00Z' },
  ] });
  assert.equal(w.moneyPaid, 200);
  assert.equal(w.moneyRefunded, 120);
  assert.equal(w.totalLeft, 200);
});

test("refunds that could not be read, when money went back: null, so the copies don't guess", () => {
  assert.equal(run([pay('pk-paid', 100)], { total: 100, refunds: null, refunded: 30 }), null);
  // Nothing refunded: the refunds don't matter.
  const w = run([pay('pk-paid', 100)], { total: 100, refunds: null, refunded: 0 });
  assert.deepEqual(w.lines.map(l => [l.label, l.amount, l.returned]), [['Wallet — Credit Package', 100, []]]);
});

test('Total never goes below nothing, and cents never drift', () => {
  // Credit beyond the total (a correction lowered it): Total S$0.00, the Refund due row says the rest.
  assert.equal(run([pay('pk-paid', 350)], { total: 300 }).totalLeft, 0);
  const many = Array.from({ length: 10 }, () => pay('pk-paid', '0.10'));
  const w = run([...many, pay('cash', '0.07')], { total: '1.07' });
  assert.equal(w.credit, 1);
  assert.equal(w.totalLeft, 0.07);
  assert.equal(w.moneyPaid, 0.07);
});
