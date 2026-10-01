// TikTok's bank payouts as Xero Sales Invoice rows (src/lib/xero/tiktokPayouts.mjs).
// Amounts, dates and Reference IDs are invented.
//
// Run: node --test scripts/xero/tests/tiktok-payouts.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { XERO_SALES_INVOICE_HEADERS, toXeroCsv } from '../../../src/lib/xero/salesInvoiceTemplate.mjs';
import {
  TIKTOK_XERO_CONTACT, buildBankPayoutRows, dayLabel, formatCents, planBankPayouts, sgd,
  tiktokXeroFilename, toCents, weekLabel, xeroDate,
} from '../../../src/lib/xero/tiktokPayouts.mjs';

const payout = (paid_on, wednesday, amount, extra = {}) => {
  const start = new Date(`${wednesday}T00:00:00Z`); start.setUTCDate(start.getUTCDate() - 6);
  return { reference_id: `REF-${paid_on}`, paid_on, amount, status: 'Transferred', transferred: true,
    file_name: 'income_20260908.xlsx', disagreeing: [],
    wednesday, week_start: start.toISOString().slice(0, 10), app_payout: amount, app_rows: 3,
    uncovered_days: [], left_out_count: 0, ...extra };
};
const september = (over = {}) => ({
  from: '2026-09-01', to: '2026-09-30', today: '2026-10-01', timezone: 'Asia/Singapore',
  payouts: [
    payout('2026-09-02', '2026-09-02', 713),
    payout('2026-09-09', '2026-09-09', 61.97),
    payout('2026-09-16', '2026-09-16', 624.4),
  ],
  wednesdays_without_payout: [],
  ...over,
});

test('amounts are whole cents, exactly', () => {
  assert.equal(toCents(70.6), 7060);
  assert.equal(toCents('-26.00'), -2600);
  assert.equal(toCents(0.1 + 0.2), 30);
  assert.equal(toCents('-0.00'), 0);
  assert.equal(formatCents(-2600), '-26.00');
  assert.equal(sgd(-2600), '-S$26.00');
  assert.equal(sgd(71300), 'S$713.00');
  assert.throws(() => toCents('1.234'), /invalid amount/);
});

test('dates: the day, its week, and Xero\'s DD/MM/YYYY', () => {
  assert.equal(dayLabel('2026-09-02'), 'Wed 2 Sep');
  assert.equal(weekLabel({ week_start: '2026-08-27', week_end: '2026-09-02' }), 'Thu 27 Aug – Wed 2 Sep 2026');
  assert.equal(xeroDate('2026-09-02'), '02/09/2026');
  assert.throws(() => xeroDate('2026-02-30'), /invalid date/);
  assert.equal(tiktokXeroFilename('2026-09-01', '2026-09-30'), 'xero-tiktok-payouts-2026-09-01-to-2026-09-30.csv');
});

test('one invoice per payout, one line for what TikTok paid, on the one account code', () => {
  const { rows, headers, payouts, totalCents } = buildBankPayoutRows(planBankPayouts(september()), ' 1011 ', 'No Tax (0%)');
  assert.deepEqual([payouts, totalCents], [3, 139937]);
  assert.deepEqual(headers, XERO_SALES_INVOICE_HEADERS);
  assert.deepEqual(rows[0], {
    '*ContactName': TIKTOK_XERO_CONTACT, '*InvoiceNumber': 'TT-PAYOUT-2026-09-02', Reference: 'TikTok REF-2026-09-02',
    '*InvoiceDate': '02/09/2026', '*DueDate': '02/09/2026', '*Description': 'TikTok payout, settled Thu 27 Aug – Wed 2 Sep 2026',
    '*Quantity': 1, '*UnitAmount': '713.00', '*AccountCode': '1011', '*TaxType': 'No Tax (0%)', TaxAmount: 0, Currency: 'SGD',
  });
  assert.deepEqual(rows.map(r => r['*UnitAmount']), ['713.00', '61.97', '624.40']);
  const csv = toXeroCsv(rows, headers).split('\r\n').filter(Boolean);
  assert.equal(csv.length, 4);
  assert.equal(csv[0], XERO_SALES_INVOICE_HEADERS.join(','));
});

test('a payout matching the app\'s figure needs no warning; one that differs says by how much and why it may', () => {
  assert.deepEqual(planBankPayouts(september()).warnings, []);
  const plan = planBankPayouts(september({ payouts: [
    payout('2026-09-09', '2026-09-09', 50, { app_payout: 60 }),
    payout('2026-09-16', '2026-09-16', 20, { app_payout: 30, uncovered_days: ['2026-09-15', '2026-09-16'], left_out_count: 2 }),
  ] }));
  assert.equal(plan.exportable.length, 2, 'they are still exported, for what TikTok paid');
  assert.deepEqual(plan.warnings, [
    "Wed 9 Sep: TikTok paid S$50.00, but the app's settled lines for Thu 3 Sep – Wed 9 Sep 2026 come to S$60.00 (for example, a negative week before it that TikTok took from this payout). The invoice uses what TikTok paid.",
    "Wed 16 Sep: TikTok paid S$20.00, but the app's settled lines for Thu 10 Sep – Wed 16 Sep 2026 come to S$30.00 (no imported file reaches Tue 15 Sep, Wed 16 Sep; 2 lines were left out at confirmation). The invoice uses what TikTok paid.",
  ]);
});

test('a payout not transferred is not exported, and says so', () => {
  const plan = planBankPayouts(september({ payouts: [payout('2026-09-23', '2026-09-23', 15, { status: 'Processing', transferred: false })] }));
  assert.equal(plan.exportable.length, 0);
  assert.deepEqual(plan.warnings, ['Wed 23 Sep: a TikTok payout of S$15.00 is "Processing", not transferred, so it is not exported.']);
});

test('a Wednesday with no payout imported is a warning: the app\'s figure for it, or the days no file reaches', () => {
  const plan = planBankPayouts(september({ wednesdays_without_payout: [
    { wednesday: '2026-09-09', week_start: '2026-09-03', app_payout: 61.97, app_rows: 2, uncovered_days: ['2026-09-09'] },
    { wednesday: '2026-09-16', week_start: '2026-09-10', app_payout: 0, app_rows: 0,
      uncovered_days: ['2026-09-10', '2026-09-11', '2026-09-12', '2026-09-13', '2026-09-14', '2026-09-15', '2026-09-16'] },
    { wednesday: '2026-09-23', week_start: '2026-09-17', app_payout: 0, app_rows: 2, uncovered_days: [], left_out_count: 2 },
    { wednesday: '2026-09-30', week_start: '2026-09-24', app_payout: 242.97, app_rows: 4, uncovered_days: [] },
  ] }));
  assert.deepEqual(plan.warnings, [
    "Wed 9 Sep: no TikTok payout has been imported, but the app's settled lines for Thu 3 Sep – Wed 9 Sep 2026 come to S$61.97 (no imported file reaches Wed 9 Sep). Import the TikTok income export that covers it, then export again.",
    'Wed 16 Sep: no TikTok payout has been imported, and no imported file reaches Thu 10 Sep – Wed 16 Sep 2026. Import the TikTok income export that covers it, then export again.',
    'Wed 23 Sep: no TikTok payout has been imported, and 2 lines were left out at confirmation. Import the TikTok income export that covers it, then export again.',
    "Wed 30 Sep: no TikTok payout has been imported, but the app's settled lines for Thu 24 Sep – Wed 30 Sep 2026 come to S$242.97. Import the TikTok income export that covers it, then export again.",
  ]);
});

test('a payout with no date is in no export, and says so; every payout is counted', () => {
  const plan = planBankPayouts(september({ undated_payout_count: 2 }));
  assert.equal(plan.payoutCount, 3);
  assert.deepEqual(plan.warnings, ['2 TikTok payouts in the imported files have no date, so they are in no export: check them in TikTok Seller Center.']);
  assert.deepEqual(planBankPayouts(september({ undated_payout_count: 1 })).warnings,
    ['1 TikTok payout in the imported files has no date, so it is in no export: check it in TikTok Seller Center.']);
});

test('a payout two imported files disagree on is not exported, and both files are named', () => {
  const plan = planBankPayouts(september({ payouts: [
    payout('2026-09-02', '2026-09-02', 713, { reference_id: 'R1', file_name: 'income_20260908.xlsx',
      disagreeing: [{ amount: 7130, file_name: 'income_20260929.xlsx' }] }),
    payout('2026-09-09', '2026-09-09', 61.97),
  ] }));
  assert.deepEqual(plan.exportable.map(p => p.paid_on), ['2026-09-09']);
  assert.deepEqual(plan.warnings, ['Wed 2 Sep: imported TikTok files disagree on payout R1: S$713.00 in "income_20260908.xlsx", but S$7130.00 in "income_20260929.xlsx". It is not exported: check it in TikTok Seller Center and enter it in Xero by hand.']);
});

test('a payout on another day keeps its own date; two on one day get distinct numbers', () => {
  const plan = planBankPayouts(september({ payouts: [
    payout('2026-09-17', '2026-09-16', 30, { reference_id: 'R1' }),
    payout('2026-09-17', '2026-09-16', 5, { reference_id: 'R2', app_payout: 30 }),
  ] }));
  const { rows } = buildBankPayoutRows(plan, '1011', 'No Tax (0%)');
  assert.deepEqual(rows.map(r => [r['*InvoiceNumber'], r['*InvoiceDate'], r.Reference]),
    [['TT-PAYOUT-2026-09-17', '17/09/2026', 'TikTok R1'], ['TT-PAYOUT-2026-09-17-2', '17/09/2026', 'TikTok R2']]);
  assert.equal(rows[0]['*Description'], 'TikTok payout, settled Thu 10 Sep – Wed 16 Sep 2026');
});

test('the account code and tax rate are required', () => {
  const plan = planBankPayouts(september());
  assert.throws(() => buildBankPayoutRows(plan, '', 'No Tax (0%)'), /account code and tax rate/);
  assert.throws(() => buildBankPayoutRows(plan, '1011', '  '), /account code and tax rate/);
});
