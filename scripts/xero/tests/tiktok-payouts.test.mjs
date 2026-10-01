// TikTok's Wednesday payouts as Xero Sales Invoice rows (src/lib/xero/tiktokPayouts.mjs).
// Amounts and dates are invented.
//
// Run: node --test scripts/xero/tests/tiktok-payouts.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { XERO_SALES_INVOICE_HEADERS, toXeroCsv } from '../../../src/lib/xero/salesInvoiceTemplate.mjs';
import {
  TIKTOK_XERO_CONTACT, buildTikTokPayoutRows, dayLabel, formatCents, neededCodes, planTikTokPayouts, sgd,
  tiktokXeroFilename, toCents, weekLabel, xeroDate,
} from '../../../src/lib/xero/tiktokPayouts.mjs';

const week = (payout_date, week_start, extra = {}) => ({
  payout_date, week_start, week_end: payout_date, finished: true, row_count: 3,
  revenue: 0, fee: 0, expense: 0, payout: 0, tiktok_net: 0,
  unknown_count: 0, balance_movement_count: 0, other_currency_count: 0, left_out_count: 0, left_out_settlement: 0,
  uncovered_days: [], ...extra,
});
// September 2026: Wednesdays 2, 9, 16, 23 and 30 Sep.
const september = (over = {}) => ({
  year: 2026, month: 9, period_start: '2026-08-27', period_end: '2026-09-30', today: '2026-10-01', timezone: 'Asia/Singapore',
  undated_count: 0, income: 251, month_income: 251,
  weeks: [
    week('2026-09-02', '2026-08-27', { revenue: 150, fee: 30, payout: 120, tiktok_net: 120 }),
    week('2026-09-09', '2026-09-03', { revenue: 30, fee: 6, expense: 50, payout: -26, tiktok_net: -26 }),
    week('2026-09-16', '2026-09-10', { revenue: 190, fee: 41, payout: 149, tiktok_net: 149 }),
    week('2026-09-23', '2026-09-17', { row_count: 1, tiktok_net: -5, unknown_count: 1 }),
    week('2026-09-30', '2026-09-24', { revenue: 10, fee: 2, payout: 8, tiktok_net: 8, left_out_count: 1, left_out_settlement: 12 }),
  ],
  ...over,
});
const CODES = { salesCode: '1011', feesCode: '6100', adsCode: '6200', taxType: 'No Tax (0%)' };
const byNumber = rows => {
  const out = {};
  for (const r of rows) (out[r['*InvoiceNumber']] ??= []).push(r);
  return out;
};

test('amounts are whole cents, exactly', () => {
  assert.equal(toCents(70.6), 7060);
  assert.equal(toCents('-26.00'), -2600);
  assert.equal(toCents(0.1 + 0.2), 30);
  assert.equal(toCents('-0.00'), 0);
  assert.equal(formatCents(-2600), '-26.00');
  assert.equal(formatCents(5), '0.05');
  assert.equal(sgd(-2600), '-S$26.00');
  assert.equal(sgd(1250), 'S$12.50');
  assert.throws(() => toCents('1.234'), /invalid amount/);
  assert.throws(() => toCents('abc'), /invalid amount/);
});

test('dates: the Wednesday, its week, and Xero\'s DD/MM/YYYY', () => {
  assert.equal(dayLabel('2026-09-02'), 'Wed 2 Sep');
  assert.equal(weekLabel({ week_start: '2026-08-27', week_end: '2026-09-02' }), 'Thu 27 Aug – Wed 2 Sep 2026');
  assert.equal(xeroDate('2026-09-02'), '02/09/2026');
  assert.throws(() => xeroDate('2026-02-30'), /invalid date/);
  assert.equal(tiktokXeroFilename(2026, 9), 'xero-tiktok-payouts-2026-09.csv');
});

test('each finished Wednesday with money can go out; the rest say why not', () => {
  const plan = planTikTokPayouts(september({
    weeks: [...september().weeks.slice(0, 4), week('2026-09-30', '2026-09-24', { finished: false, revenue: 10, fee: 2, payout: 8, tiktok_net: 8 })],
    income: 251, month_income: 251,
  }));
  assert.deepEqual(plan.weeks.map(w => w.status), ['export', 'export', 'export', 'nothing', 'not_finished']);
  assert.deepEqual(plan.exportable.map(w => w.payout_date), ['2026-09-02', '2026-09-09', '2026-09-16']);
  assert.equal(plan.exportCents, 24300);
  assert.equal(plan.monthIncomeCents, 25100, 'the month\'s Total Income comes from month_income, not from the weeks');
  assert.deepEqual(plan.weeks[4].warnings, [], 'a week that is not over is not checked yet');
});

test('what to read first: missing days, left-out lines, unknown types, balance moves, other currencies, TikTok\'s own total, an empty week, undated lines', () => {
  const plan = planTikTokPayouts(september({
    undated_count: 2,
    weeks: [
      week('2026-09-02', '2026-08-27', { revenue: 150, fee: 30, payout: 120, tiktok_net: 90, other_currency_count: 1,
        balance_movement_count: 1, uncovered_days: ['2026-08-27', '2026-08-28'] }),
      week('2026-09-09', '2026-09-03', { row_count: 0, uncovered_days: ['2026-09-03'] }),
      ...september().weeks.slice(2),
    ],
  }));
  const w = Object.fromEntries(plan.weeks.map(x => [x.payout_date, x.warnings]));
  assert.ok(w['2026-09-02'].some(t => t.startsWith('No imported file reaches Thu 27 Aug, Fri 28 Aug. If TikTok settled anything on those days')));
  assert.ok(w['2026-09-02'].some(t => t.startsWith('1 line moves money in or out of the TikTok balance')));
  assert.ok(w['2026-09-02'].some(t => t === '1 line is not in SGD.'));
  assert.ok(w['2026-09-02'].some(t => t.startsWith("TikTok's own total for these lines is S$90.00, not S$120.00")));
  assert.deepEqual(w['2026-09-09'], ['No settled lines were imported for this week. If TikTok paid out, import its file first.'],
    'an empty week says so once, not also which days are missing');
  assert.ok(w['2026-09-23'].some(t => t.startsWith('1 line has a TikTok type the app does not know')));
  assert.ok(w['2026-09-23'].some(t => t.startsWith("TikTok's own total for these lines is -S$5.00")));
  assert.ok(w['2026-09-30'].some(t => t.startsWith('1 settled line was left out at confirmation (S$12.00)')));
  assert.deepEqual(plan.monthWarnings, ['2 counted settled lines have no settled date, so they are in no week.']);
});

test('a negative week says what TikTok does with it, and the next week warns its deposit may be less', () => {
  const plan = planTikTokPayouts(september());
  const w = Object.fromEntries(plan.weeks.map(x => [x.payout_date, x.warnings]));
  assert.ok(w['2026-09-09'].some(t => t.startsWith('This week is negative (-S$26.00): TikTok pays nothing this Wednesday and takes S$26.00 from a later payout')
    && t.includes('credit note TT-PAYOUT-2026-09-09-CN')));
  assert.ok(w['2026-09-16'].some(t => t.startsWith('TikTok takes the S$26.00 of Wed 9 Sep from a payout from here on')));
  assert.ok(!w['2026-09-02'].some(t => t.includes('negative')));
});

test('a week whose lines do not add up to its payout is refused', () => {
  assert.throws(() => planTikTokPayouts(september({ weeks: [week('2026-09-02', '2026-08-27', { revenue: 150, fee: 30, payout: 121 })] })),
    /Wed 2 Sep does not add up/);
});

test('one invoice per Wednesday: sales, less fees, less ads, totalling the payout', () => {
  const plan = planTikTokPayouts(september());
  const { rows, weeks, documents, creditNotes, total } = buildTikTokPayoutRows(plan, CODES);
  assert.deepEqual([weeks, documents, creditNotes, total], [4, 5, 1, '251.00']);
  const docs = byNumber(rows);
  assert.deepEqual(Object.keys(docs), ['TT-PAYOUT-2026-09-02', 'TT-PAYOUT-2026-09-09', 'TT-PAYOUT-2026-09-09-CN', 'TT-PAYOUT-2026-09-16', 'TT-PAYOUT-2026-09-30']);
  assert.deepEqual(docs['TT-PAYOUT-2026-09-02'].map(r => [r['*UnitAmount'], r['*AccountCode']]), [['150.00', '1011'], ['-30.00', '6100']],
    'a positive week is one invoice; a line of 0.00 is left out');
  const first = docs['TT-PAYOUT-2026-09-16'][0];
  assert.deepEqual({
    contact: first['*ContactName'], date: first['*InvoiceDate'], due: first['*DueDate'], ref: first.Reference,
    qty: first['*Quantity'], tax: first['*TaxType'], taxAmount: first.TaxAmount, currency: first.Currency,
  }, { contact: TIKTOK_XERO_CONTACT, date: '16/09/2026', due: '16/09/2026', ref: 'TikTok payout Wed 16 Sep 2026',
    qty: 1, tax: 'No Tax (0%)', taxAmount: 0, currency: 'SGD' });
  assert.equal(first['*Description'], 'TikTok sales (revenue after discounts and refunds), settled Thu 10 Sep – Wed 16 Sep 2026');
  assert.equal(docs['TT-PAYOUT-2026-09-16'][1]['*Description'], "TikTok fees, commissions and shipping (TikTok's Total Fees), settled Thu 10 Sep – Wed 16 Sep 2026");
});

test('a negative week: its positive lines stay on the invoice, its negative lines make the credit note, and together they are the payout', () => {
  const { rows } = buildTikTokPayoutRows(planTikTokPayouts(september()), CODES);
  const docs = byNumber(rows);
  assert.deepEqual(docs['TT-PAYOUT-2026-09-09'].map(r => [r['*UnitAmount'], r['*AccountCode']]), [['30.00', '1011']]);
  assert.deepEqual(docs['TT-PAYOUT-2026-09-09-CN'].map(r => [r['*UnitAmount'], r['*AccountCode'], r['*Description']]), [
    ['-6.00', '6100', "TikTok fees, commissions and shipping (TikTok's Total Fees), settled Thu 3 Sep – Wed 9 Sep 2026"],
    ['-50.00', '6200', 'TikTok ads and subscriptions (GMV Pay), settled Thu 3 Sep – Wed 9 Sep 2026'],
  ]);
  const sum = rs => rs.reduce((s, r) => s + toCents(r['*UnitAmount']), 0);
  assert.equal(sum(docs['TT-PAYOUT-2026-09-09']) + sum(docs['TT-PAYOUT-2026-09-09-CN']), -2600);
  // A negative week with nothing positive is only a credit note.
  const onlyAds = planTikTokPayouts(september({ weeks: [week('2026-09-02', '2026-08-27', { expense: 20, payout: -20, tiktok_net: -20 })], month_income: -20 }));
  assert.deepEqual(Object.keys(byNumber(buildTikTokPayoutRows(onlyAds, CODES).rows)), ['TT-PAYOUT-2026-09-02-CN']);
});

test('a fee reversal week: the fees line is positive', () => {
  const plan = planTikTokPayouts(september({ weeks: [week('2026-09-02', '2026-08-27', { revenue: 0, fee: -4, payout: 4, tiktok_net: 4 })], month_income: 4 }));
  const { rows } = buildTikTokPayoutRows(plan, CODES);
  assert.deepEqual(rows.map(r => [r['*InvoiceNumber'], r['*UnitAmount'], r['*AccountCode']]), [['TT-PAYOUT-2026-09-02', '4.00', '6100']]);
});

test('only the chosen Wednesdays go out', () => {
  const plan = planTikTokPayouts(september());
  const { rows, weeks, total } = buildTikTokPayoutRows(plan, CODES, ['2026-09-16', '2026-09-23', '2026-09-30']);
  assert.deepEqual([weeks, total], [2, '157.00'], 'a week that cannot go out (23 Sep) is ignored even if chosen');
  assert.deepEqual(Object.keys(byNumber(rows)), ['TT-PAYOUT-2026-09-16', 'TT-PAYOUT-2026-09-30']);
  assert.deepEqual(buildTikTokPayoutRows(plan, CODES, []).rows, []);
});

test('an account code is needed only for the lines that go out, and the tax rate always', () => {
  const plan = planTikTokPayouts(september());
  assert.deepEqual(neededCodes(plan), ['salesCode', 'feesCode', 'adsCode']);
  assert.deepEqual(neededCodes(plan, ['2026-09-02']), ['salesCode', 'feesCode'], 'no ads that week');
  assert.doesNotThrow(() => buildTikTokPayoutRows(plan, { ...CODES, adsCode: '' }, ['2026-09-02']));
  assert.throws(() => buildTikTokPayoutRows(plan, { ...CODES, adsCode: '  ' }), /account code for TikTok ads/);
  assert.throws(() => buildTikTokPayoutRows(plan, { ...CODES, feesCode: '' }), /account code for TikTok fees/);
  assert.throws(() => buildTikTokPayoutRows(plan, { ...CODES, taxType: '' }), /tax rate/);
});

test('nothing to export when no Wednesday is over', () => {
  const plan = planTikTokPayouts(september({ weeks: september().weeks.map(w => ({ ...w, finished: false })) }));
  assert.equal(plan.exportable.length, 0);
  assert.deepEqual(buildTikTokPayoutRows(plan, CODES).rows, []);
});

test('the CSV is the Sales Invoice template, column for column', () => {
  const { rows, headers } = buildTikTokPayoutRows(planTikTokPayouts(september()), CODES);
  assert.deepEqual(headers, XERO_SALES_INVOICE_HEADERS);
  const csv = toXeroCsv(rows, headers).split('\r\n');
  assert.equal(csv[0], XERO_SALES_INVOICE_HEADERS.join(','));
  assert.equal(csv.filter(Boolean).length, 1 + rows.length);
  assert.ok(csv[1].startsWith('TikTok Shop,,,,,,,,,,TT-PAYOUT-2026-09-02,TikTok payout Wed 2 Sep 2026,02/09/2026,02/09/2026,,,'));
});
