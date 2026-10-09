// 410: what the Commissions page and the affiliate portal show once an
// affiliate's months are netted: never a negative Unpaid, the deduction still
// to be recovered, and what may be paid for each month now.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
const compiled = await build({ stdin: { contents: "export * from './src/lib/affiliatePayoutPresentation';export * from './src/lib/affiliatePortalFigures';", resolveDir: process.cwd() }, bundle: true, write: false, format: 'esm' });
const { owedSplit, referrerBalancesFrom, referrerBalances, monthPayable, monthKey, remainingPayable, deductionsOutstanding,
  earningsFigures, statusLabel } = await import('data:text/javascript;base64,' + Buffer.from(compiled.outputFiles[0].text).toString('base64'));

const month = (referrer, m, balance, extra = {}) => ({ referrer, month: m, earned: Math.max(balance, 0), adjustments: Math.min(balance, 0), paid: 0, balance, review_reason: null, ...extra });

test('a negative net is a deduction, never a negative Unpaid', () => {
  assert.deepEqual(owedSplit(-555.27), { unpaid: 0, deduction: 555.27 });
  assert.deepEqual(owedSplit('44.73'), { unpaid: 44.73, deduction: 0 });
  assert.deepEqual(owedSplit(0), { unpaid: 0, deduction: 0 });
  assert.deepEqual(owedSplit(null), { unpaid: 0, deduction: 0 });
});

test('the production case: -562.35 in September and +7.08 in October leaves nothing payable', () => {
  const groups = [month('a', '2026-10-01', 7.08), month('a', '2026-09-01', -562.35)];
  const refs = referrerBalances(groups, null);
  assert.deepEqual(refs.get('a'), { referrer: 'a', owed: -555.27, unpaid: 0, deduction: 555.27, payable: 0 });
  const pay = monthPayable(groups, refs);
  assert.equal(pay.get(monthKey(groups[0])), 0, 'October is not payable while 555.27 is owed back');
  assert.equal(remainingPayable(refs), 0);
  assert.deepEqual(deductionsOutstanding(refs), { count: 1, total: 555.27 });
});

test('payable goes to the oldest months first and adds up to the affiliate total', () => {
  const groups = [month('b', '2026-10-01', -50), month('b', '2020-10-01', 60), month('b', '2020-09-01', 30)];
  const refs = referrerBalances(groups, null);
  assert.equal(refs.get('b').payable, 40);
  const pay = monthPayable(groups, refs);
  assert.equal(pay.get('b/2020-09-01'), 30);
  assert.equal(pay.get('b/2020-10-01'), 10);
  assert.equal(pay.get('b/2026-10-01'), 0);
});

test('a month under review counts only when negative; a month with no date pays nothing', () => {
  const groups = [month('c', '2020-07-01', 100), month('c', '2020-08-01', 30, { review_reason: 'Historical payout allocations need review' }),
                  month('c', null, 20)];
  const [r] = referrerBalancesFrom(groups);
  assert.deepEqual(r, { referrer: 'c', owed: 150, unpaid: 150, deduction: 0, payable: 100 });
  const pay = monthPayable(groups, referrerBalances(groups, null));
  assert.equal(pay.get('c/2020-07-01'), 100);
  assert.equal(pay.get('c/2020-08-01'), 0);
  assert.equal(pay.get('c/'), 0);
  const negReview = referrerBalancesFrom([month('d', '2020-07-01', 100), month('d', '2020-08-01', -30, { review_reason: 'review' })]);
  assert.equal(negReview[0].payable, 70, 'a negative month under review still reduces what is payable');
});

test('the server\'s figures are used when it sends them (410)', () => {
  const groups = [month('e', '2020-01-01', 10, { payable: 4, referrer_owed: 4, referrer_payable: 4, referrer_deduction: 0 })];
  const refs = referrerBalances(groups, [{ referrer: 'e', owed: '4.00', unpaid: '4.00', deduction: '0', payable: '4.00' }]);
  assert.equal(refs.get('e').payable, 4);
  assert.equal(monthPayable(groups, refs).get('e/2020-01-01'), 4);
  assert.equal(remainingPayable(refs), 4);
});

test('sums are exact to the cent', () => {
  const groups = [month('f', '2020-01-01', 0.1), month('f', '2020-02-01', 0.2), month('g', '2020-01-01', 0.7)];
  const refs = referrerBalances(groups, null);
  assert.equal(remainingPayable(refs), 1);
});

test('the portal: Unpaid never negative, the deduction shown; older servers too', () => {
  assert.deepEqual(earningsFigures({ unpaid: 0, deduction: 555.27 }), { unpaid: 0, deduction: 555.27 });
  assert.deepEqual(earningsFigures({ unpaid: -555.27 }), { unpaid: 0, deduction: 555.27 }, 'before 410 the server sent a negative unpaid');
  assert.deepEqual(earningsFigures({ unpaid: '25.00' }), { unpaid: 25, deduction: 0 });
  assert.deepEqual(earningsFigures(null), { unpaid: 0, deduction: 0 });
});

test('blocked commission is labelled Blocked, partly paid as such (AFFILIATES-3)', () => {
  assert.equal(statusLabel('blocked').label, 'Blocked');
  assert.equal(statusLabel('cancelled').label, 'Blocked');
  assert.equal(statusLabel('partially_paid').label, 'Partly paid');
  assert.equal(statusLabel('reversed').label, 'Reversed');
  assert.equal(statusLabel('earned').label, 'Unpaid');
});
