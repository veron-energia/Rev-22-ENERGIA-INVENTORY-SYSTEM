// The Commissions page's Balances tab filters (the Owner, 27 Oct 2026): a
// status (All, Unpaid, Partly paid, Paid) and a commission month (All months,
// each month that has rows, newest first, and Date needs review). They choose
// which rows are shown and exported; no figure is worked out differently.
//
// The helpers in src/lib/affiliatePayoutPresentation.ts, bundled with esbuild.
// Every amount below is invented.
//
// Run: node --test scripts/commissions/tests/balances-filters-presentation.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const compiled = await build({ stdin: { contents: "export * from './src/lib/affiliatePayoutPresentation';", resolveDir: REPO }, bundle: true, write: false, format: 'esm' });
const {
  balanceRemaining, balanceStatus, BALANCE_STATUS_FILTERS, BALANCE_MONTH_ALL, BALANCE_MONTH_NONE, balanceMonth, commissionMonthLabel,
  balanceMonthOptions, balanceMatches, filterBalances, payableInView, monthKey,
} = await import('data:text/javascript;base64,' + Buffer.from(compiled.outputFiles[0].text).toString('base64'));

const row = (referrer, month, earned, adjustments, paid, extra = {}) =>
  ({ referrer, month, earned, adjustments, paid, balance: +(earned + adjustments - paid).toFixed(2), review_reason: null, settled: 0, ...extra });

// Seven months: Alpha unpaid / partly paid / paid; Bravo owes 20.00 back in
// October (paid) and is owed 40.00 for September (unpaid); Charlie has a row
// with no month and a partly paid row under review.
const ROWS = [
  row('ref-a', '2026-10-01', 100, 0, 0),
  row('ref-a', '2026-09-01', 200, 0, 50),
  row('ref-a', '2026-08-01', 80, 0, 80),
  row('ref-b', '2026-10-01', 50, -10, 60),
  row('ref-b', '2026-09-01', 40, 0, 0),
  row('ref-c', null, 30, 0, 0, { review_reason: 'Commission date is missing. Review the original invoice before recording a payout.' }),
  row('ref-c', '2026-07-01', 90, 0, 30, { review_reason: 'Payout allocation needs review.' }),
];
const ids = rows => rows.map(g => `${g.referrer}/${(g.month ?? 'none').slice(0, 7)}`);

test('the four status choices, in the order the Owner named them', () => {
  assert.deepEqual(BALANCE_STATUS_FILTERS.map(o => o.label), ['All', 'Unpaid', 'Partly paid', 'Paid']);
  assert.deepEqual(BALANCE_STATUS_FILTERS.map(o => o.value), ['all', 'unpaid', 'partly_paid', 'paid']);
});

test('Remaining is the balance never below 0, as the table shows it', () => {
  assert.equal(balanceRemaining({ balance: 150 }), 150);
  assert.equal(balanceRemaining({ balance: '150.00' }), 150);
  assert.equal(balanceRemaining({ balance: -20 }), 0, 'what is owed back is not remaining');
  assert.equal(balanceRemaining({ balance: 0 }), 0);
  assert.equal(balanceRemaining({ balance: null }), 0);
});

test('a month by its numbers: Unpaid, Partly paid, Paid', () => {
  assert.equal(balanceStatus({ paid: 0, balance: 100 }), 'unpaid', 'nothing paid, something remaining');
  assert.equal(balanceStatus({ paid: '0.00', balance: '0.01' }), 'unpaid', 'one cent remaining is something remaining');
  assert.equal(balanceStatus({ paid: 50, balance: 150 }), 'partly_paid', 'something paid, something remaining');
  assert.equal(balanceStatus({ paid: '0.01', balance: '99.99' }), 'partly_paid');
  assert.equal(balanceStatus({ paid: 80, balance: 0 }), 'paid', 'nothing left');
  assert.equal(balanceStatus({ paid: 60, balance: -20 }), 'paid', 'a month the affiliate owes money back on: Remaining is 0');
  assert.equal(balanceStatus({ paid: 0, balance: 0 }), 'paid', 'nothing earned and nothing paid: nothing left');
  assert.equal(balanceStatus({ paid: 0, balance: -5 }), 'paid', 'a take-back with no payout: Remaining is 0');
  assert.equal(balanceStatus({ paid: 10, balance: 0.004 }), 'paid', 'less than a cent shows as S$0.00, so nothing left');
  // A settled deduction (414) is already in the balance: a month settled to 0 is Paid.
  assert.equal(balanceStatus({ paid: 300, balance: 0, settled: 120 }), 'paid');
});

test('a review reason or a missing month does not change how a row is classified', () => {
  assert.equal(balanceStatus(ROWS[5]), 'unpaid', 'Charlie, no month, under review, nothing paid');
  assert.equal(balanceStatus(ROWS[6]), 'partly_paid', 'Charlie, July, under review, part paid');
  assert.deepEqual(ROWS.map(balanceStatus), ['unpaid', 'partly_paid', 'paid', 'paid', 'unpaid', 'unpaid', 'partly_paid']);
});

test('the month a row is for, and how the filter names it', () => {
  assert.equal(balanceMonth({ month: '2026-10-01' }), '2026-10');
  assert.equal(balanceMonth({ month: null }), null);
  assert.equal(balanceMonth({ month: '' }), null, 'an empty month is a row with no month, as the table shows it');
  assert.equal(commissionMonthLabel('2026-10'), 'Oct 2026');
  assert.equal(commissionMonthLabel('2027-01'), 'Jan 2027');
  assert.equal(commissionMonthLabel('2026-12'), 'Dec 2026');
  assert.equal(commissionMonthLabel('2026-13'), '2026-13', 'anything else as it came');
});

test('the month choices: All months, each month with rows newest first, then Date needs review', () => {
  assert.deepEqual(balanceMonthOptions(ROWS), [
    { value: BALANCE_MONTH_ALL, label: 'All months' },
    { value: '2026-10', label: 'Oct 2026' },
    { value: '2026-09', label: 'Sep 2026' },
    { value: '2026-08', label: 'Aug 2026' },
    { value: '2026-07', label: 'Jul 2026' },
    { value: BALANCE_MONTH_NONE, label: 'Date needs review' },
  ]);
  // Across a year end, newest first; Date needs review only when a row has no month.
  assert.deepEqual(balanceMonthOptions([{ month: '2025-12-01' }, { month: '2026-01-01' }, { month: '2025-12-01' }]).map(o => o.label),
    ['All months', 'Jan 2026', 'Dec 2025']);
  assert.deepEqual(balanceMonthOptions([]), [{ value: BALANCE_MONTH_ALL, label: 'All months' }]);
  assert.deepEqual(balanceMonthOptions([{ month: null }]).map(o => o.label), ['All months', 'Date needs review']);
  for (const o of balanceMonthOptions(ROWS).slice(1, -1)) assert.match(o.value, /^\d{4}-\d{2}$/, 'a month choice cannot be mistaken for All or Date needs review');
});

test('status and month together; All and All shows every row in the order it came', () => {
  const f = (status, month) => ids(filterBalances(ROWS, { status, month }));
  assert.deepEqual(filterBalances(ROWS, { status: 'all', month: BALANCE_MONTH_ALL }), ROWS);
  assert.deepEqual(f('unpaid', BALANCE_MONTH_ALL), ['ref-a/2026-10', 'ref-b/2026-09', 'ref-c/none']);
  assert.deepEqual(f('partly_paid', BALANCE_MONTH_ALL), ['ref-a/2026-09', 'ref-c/2026-07']);
  assert.deepEqual(f('paid', BALANCE_MONTH_ALL), ['ref-a/2026-08', 'ref-b/2026-10']);
  assert.deepEqual(f('all', '2026-10'), ['ref-a/2026-10', 'ref-b/2026-10']);
  assert.deepEqual(f('unpaid', '2026-09'), ['ref-b/2026-09']);
  assert.deepEqual(f('paid', '2026-10'), ['ref-b/2026-10'], 'Bravo owes 20.00 back in October: Paid');
  assert.deepEqual(f('all', BALANCE_MONTH_NONE), ['ref-c/none']);
  assert.deepEqual(f('partly_paid', BALANCE_MONTH_NONE), []);
  assert.deepEqual(f('unpaid', '2026-08'), []);
  assert.deepEqual(f('all', '2026-06'), [], 'a month with no rows shows none');
  assert.equal(balanceMatches(ROWS[0], { status: 'unpaid', month: '2026-10' }), true);
  assert.equal(balanceMatches(ROWS[0], { status: 'paid', month: '2026-10' }), false);
  // Every row is in exactly one status.
  const counts = ['unpaid', 'partly_paid', 'paid'].map(s => filterBalances(ROWS, { status: s, month: BALANCE_MONTH_ALL }).length);
  assert.equal(counts.reduce((a, b) => a + b, 0), ROWS.length);
});

test('Payable now in view adds up the shown rows\' Payable now, to the cent', () => {
  const payable = new Map([
    [monthKey(ROWS[0]), 100], [monthKey(ROWS[1]), 150], [monthKey(ROWS[2]), 0],
    [monthKey(ROWS[3]), 0], [monthKey(ROWS[4]), 20], [monthKey(ROWS[5]), 0], [monthKey(ROWS[6]), 0],
  ]);
  assert.equal(payableInView(ROWS, payable), 270);
  assert.equal(payableInView(filterBalances(ROWS, { status: 'unpaid', month: BALANCE_MONTH_ALL }), payable), 120);
  assert.equal(payableInView(filterBalances(ROWS, { status: 'all', month: '2026-09' }), payable), 170);
  assert.equal(payableInView([], payable), 0);
  assert.equal(payableInView([ROWS[0]], new Map()), 0, 'a row with no Payable now counts as 0');
  const tenths = [row('x', '2026-01-01', 0.1, 0, 0), row('x', '2026-02-01', 0.2, 0, 0)];
  assert.equal(payableInView(tenths, new Map([[monthKey(tenths[0]), 0.1], [monthKey(tenths[1]), 0.2]])), 0.3, 'in cents, not 0.30000000000000004');
});
