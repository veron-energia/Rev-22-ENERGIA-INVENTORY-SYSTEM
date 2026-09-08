// Financial classification and the reported figures.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  toCents, formatCents, CATEGORY, classifyTransaction, rowEffect, summarise,
} from '../../../src/lib/tiktok/classification.mjs';
import { settledDateSgt, isInPeriod } from '../../../src/lib/tiktok/settlementPeriod.mjs';

const fixture = JSON.parse(readFileSync(new URL('./fixtures/settlement-sample.json', import.meta.url)));
const rows = fixture.rows.map(r => ({ ...r, settled: settledDateSgt(r.orderSettledTime) }));

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

test('amounts parse to exact cents, sign preserved', () => {
  assert.equal(toCents('141.12'), 14112);
  assert.equal(toCents('-23.32'), -2332);
  assert.equal(toCents('1,234.56'), 123456);
  assert.equal(toCents('SGD 12.30'), 1230);
  assert.equal(toCents('(5.00)'), -500);        // accounting parentheses
  assert.equal(toCents(0), 0);
  assert.equal(toCents('0'), 0);
  assert.equal(toCents(''), 0);
  assert.equal(toCents('/'), 0);
  assert.equal(toCents(null), 0);
  assert.equal(toCents('rubbish'), 0);
});

test('cent arithmetic does not drift where floats would', () => {
  // 0.1 + 0.2 !== 0.3 in binary floating point; in cents it is exact.
  assert.equal(toCents('0.1') + toCents('0.2'), toCents('0.3'));
  let sum = 0;
  for (let i = 0; i < 1000; i++) sum += toCents('0.07');
  assert.equal(formatCents(sum), '70.00');
});

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

test('advertising payments are expense, not fee or revenue', () => {
  assert.equal(classifyTransaction('GMV payment for TikTok Ads'), CATEGORY.AD_EXPENSE);
  assert.equal(classifyTransaction('Payment for TikTok Ads'), CATEGORY.AD_EXPENSE);
});

test('an advertising payment coming back is a reversal, reducing cost', () => {
  assert.equal(classifyTransaction('GMV payment for TikTok Ads', { adjustmentCents: 5000 }),
    CATEGORY.EXPENSE_REVERSAL);
  // A reversal reduces expense rather than adding to it.
  const e = rowEffect({ transactionType: 'GMV payment for TikTok Ads', adjustmentAmount: '50.00' });
  assert.equal(e.expense, -5000, 'a positive adjustment must reduce expense');
});

test('a commission that merely mentions Ads is still a fee, not advertising', () => {
  // "Affiliate Shop Ads commission" is commission on a sale. Matching on the
  // word "ads" would move real commission into advertising spend and overstate it.
  assert.equal(classifyTransaction('Affiliate Shop Ads commission'), CATEGORY.FEE);
  assert.equal(classifyTransaction('Affiliate Partner shop ads commission'), CATEGORY.FEE);
});

test('balance movements are neither income nor expense', () => {
  for (const t of ['Withdrawal', 'Transfer to bank account', 'Payout', 'Reserve hold',
                   'Reserve release', 'Loan repayment', 'Financing advance', 'Deposit']) {
    assert.equal(classifyTransaction(t), CATEGORY.BALANCE_MOVEMENT, t);
  }
  const e = rowEffect({ transactionType: 'Withdrawal', adjustmentAmount: '-500.00',
                        totalSettlementAmount: '-500.00' });
  assert.deepEqual([e.revenue, e.fee, e.expense], [0, 0, 0],
    'a withdrawal must not be counted as an expense');
});

test('an undocumented type is flagged, never folded into a total', () => {
  assert.equal(classifyTransaction('Mystery adjustment 47'), CATEGORY.UNKNOWN);
  assert.equal(classifyTransaction(''), CATEGORY.UNKNOWN);
  const t = summarise([{ transactionType: 'Mystery adjustment 47', adjustmentAmount: '-99.00' }]);
  assert.equal(t.expense, 0);
  assert.equal(t.review.length, 1, 'must appear for review');
});

// ---------------------------------------------------------------------------
// Per-row effect
// ---------------------------------------------------------------------------

test('revenue is taken once and refunds are not subtracted again', () => {
  // Total Revenue in this export is already net of the customer refund.
  const e = rowEffect({
    transactionType: 'Order', totalRevenue: '141.12', totalFees: '-23.32',
    refundSubtotalAfterSellerDiscounts: '-50.00',
  });
  assert.equal(e.revenue, 14112, 'the refund column must not be subtracted a second time');
  assert.equal(e.fee, 2332, 'a signed deduction becomes a positive cost');
});

test('a fully refunded order contributes zero revenue, not negative', () => {
  const e = rowEffect({ transactionType: 'Order', totalRevenue: '0', totalFees: '0',
                        refundSubtotalAfterSellerDiscounts: '-88.00' });
  assert.equal(e.revenue, 0);
});

test('a fee rebate reduces cost rather than adding another charge', () => {
  const e = rowEffect({ transactionType: 'Order', totalRevenue: '0', totalFees: '12.50' });
  assert.equal(e.fee, -1250, 'Math.abs on every row would turn this rebate into a charge');
});

test('advertising in two columns is counted once', () => {
  // The payment appears in BOTH Total settlement amount and Adjustment amount.
  const t = summarise([{
    transactionType: 'GMV payment for TikTok Ads',
    totalRevenue: '0', totalFees: '0',
    adjustmentAmount: '-283.30', totalSettlementAmount: '-283.30',
  }]);
  assert.equal(formatCents(t.expense), '283.30');
  assert.equal(t.revenue, 0);
  assert.equal(t.fee, 0, 'not also counted as a fee');
  assert.equal(formatCents(t.tiktokNetSettlement), '-283.30', 'source total kept for reconciliation');
});

// ---------------------------------------------------------------------------
// The documented sample
// ---------------------------------------------------------------------------

const expect = (t, [n, rev, fee, settle, exp, inc]) => {
  assert.equal(t.rows, n, 'row count');
  assert.equal(formatCents(t.revenue), rev, 'revenue');
  assert.equal(formatCents(t.fee), fee, 'fee');
  assert.equal(formatCents(t.settlement), settle, 'settlement');
  assert.equal(formatCents(t.expense), exp, 'expense');
  assert.equal(formatCents(t.income), inc, 'income');
};

test('the sample has 44 rows, 24 sales and 20 advertising payments', () => {
  assert.equal(rows.length, 44);
  const t = summarise(rows);
  assert.equal(t.byCategory[CATEGORY.SALE], 24);
  assert.equal(t.byCategory[CATEGORY.AD_EXPENSE], 20);
  assert.equal(t.review.length, 0);
  assert.equal(rows.filter(r => !r.settled).length, 0);
});

test('August 2026 acceptance totals', () => {
  expect(summarise(rows.filter(r => isInPeriod(r.settled, 2026, 8))),
    [30, '2770.17', '596.73', '2173.44', '565.35', '1608.09']);
});

test('September 2026 acceptance totals', () => {
  expect(summarise(rows.filter(r => isInPeriod(r.settled, 2026, 9))),
    [14, '1979.51', '317.63', '1661.88', '886.91', '774.97']);
});

test('whole-file acceptance totals, and the periods sum to them', () => {
  const all = summarise(rows);
  expect(all, [44, '4749.68', '914.36', '3835.32', '1452.26', '2383.06']);
  const aug = summarise(rows.filter(r => isInPeriod(r.settled, 2026, 8)));
  const sep = summarise(rows.filter(r => isInPeriod(r.settled, 2026, 9)));
  assert.equal(aug.rows + sep.rows, all.rows, 'every row lands in exactly one period');
  assert.equal(aug.revenue + sep.revenue, all.revenue);
  assert.equal(aug.expense + sep.expense, all.expense);
});

test('the independent column checks hold', () => {
  const sum = k => rows.reduce((a, r) => a + toCents(r[k]), 0);
  assert.equal(formatCents(sum('subtotalAfterSellerDiscounts')), '5205.67');
  assert.equal(formatCents(sum('refundSubtotalAfterSellerDiscounts')), '-455.99');
  assert.equal(formatCents(sum('totalRevenue')), '4749.68');
  assert.equal(formatCents(sum('totalFees')), '-914.36');
  assert.equal(formatCents(sum('adjustmentAmount')), '-1452.26');
  assert.equal(formatCents(sum('totalSettlementAmount')), '2383.06');
  // Revenue reconciles to gross sales plus the signed refund.
  assert.equal(sum('subtotalAfterSellerDiscounts') + sum('refundSubtotalAfterSellerDiscounts'),
    sum('totalRevenue'));
});

test('Income reconciles to TikTok\'s exported net settlement for this file', () => {
  const t = summarise(rows);
  assert.equal(t.income, t.tiktokNetSettlement);
  assert.equal(formatCents(t.income), '2383.06');
  // But Settlement deliberately does NOT: ours is struck before expenses.
  assert.notEqual(t.settlement, t.tiktokNetSettlement);
  assert.equal(formatCents(t.settlement), '3835.32');
});

test('both legitimate rows sharing one Order ID are kept', () => {
  const counts = new Map();
  for (const r of rows) counts.set(r.orderId, (counts.get(r.orderId) ?? 0) + 1);
  const repeated = [...counts].filter(([, n]) => n > 1);
  assert.equal(repeated.length, 1, 'the sample has exactly one repeated id');
  const [id] = repeated[0];
  const pair = rows.filter(r => r.orderId === id);
  assert.equal(pair.length, 2);
  assert.equal(pair[0].orderSettledTime, pair[1].orderSettledTime, 'same settled date');
  const amounts = pair.map(r => formatCents(toCents(r.totalRevenue))).sort();
  assert.deepEqual(amounts, ['141.12', '310.46'], 'different valid amounts');
  const t = summarise(pair);
  assert.equal(formatCents(t.revenue), '451.58', 'both must count');
  assert.equal(formatCents(t.settlement), '377.34');
});

test('identifiers stay strings and survive beyond 2^53', () => {
  for (const r of rows) {
    assert.equal(typeof r.orderId, 'string');
    assert.equal(r.orderId, String(r.orderId).trim());
  }
  const long = rows.find(r => r.orderId.length >= 19);
  assert.ok(long, 'the sample has 19-digit ids');
  assert.ok(Number(long.orderId) > Number.MAX_SAFE_INTEGER,
    'these ids cannot round-trip through a JS number');
});
