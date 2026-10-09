// 414: what the pages show and check for a deduction marked as settled: the
// Mark as settled form's rules (said as the server says them), how it was
// settled in plain words, what the settlements still counting come to, the
// export, the Dashboard's unpaid commission and the portal's settled figure.
// Every name and amount is invented.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
const compiled = await build({ stdin: { contents: "export * from './src/lib/affiliatePayoutPresentation';export * from './src/lib/affiliatePortalFigures';", resolveDir: process.cwd() }, bundle: true, write: false, format: 'esm' });
const { SETTLEMENT_METHODS, settlementMethodLabel, settlementFormError, settlementsInForce, settledTotal, settlementInRange,
  settlementExportColumns, dashboardCommissionFigures, settledFigure, earningsFigures, sgDate, longDate, firstPaidPayoutDate } =
  await import('data:text/javascript;base64,' + Buffer.from(compiled.outputFiles[0].text).toString('base64'));

const form = (over = {}) => ({ method: 'paid_outside_app', amount: '555.27', date: '2026-10-09', note: 'Settled outside the app', ...over });
const settlement = (over = {}) => ({ id: 's1', referrer_customer_id: 'a', amount: 100, settled_on: '2026-10-01', method: 'paid_back', note: 'n',
  created_by: 'o', created_by_name: 'Owner One', created_at: '2026-10-01T02:00:00Z', voided_at: null, voided_by: null, void_reason: null, ...over });

test('how it was settled: the three choices the Owner named, in plain words', () => {
  assert.deepEqual(SETTLEMENT_METHODS.map(m => m.label), ['Paid back to us', 'Written off', 'Paid off outside the app']);
  assert.deepEqual(SETTLEMENT_METHODS.map(m => m.value), ['paid_back', 'written_off', 'paid_outside_app']);
  assert.equal(settlementMethodLabel('paid_outside_app'), 'Paid off outside the app');
  assert.equal(settlementMethodLabel('something_else'), 'something_else');
});

test('the form: how, an amount above 0 and at most the deduction, a date not in the future, a note', () => {
  assert.equal(settlementFormError(form(), 555.27, '2026-10-09'), '', 'the production case is accepted as it is');
  assert.equal(settlementFormError(form({ method: '' }), 555.27, '2026-10-09'), 'Choose how it was settled.');
  assert.equal(settlementFormError(form({ amount: '0' }), 555.27, '2026-10-09'), 'Enter an amount above S$0.00 with at most two decimal places.');
  assert.equal(settlementFormError(form({ amount: '1.005' }), 555.27, '2026-10-09'), 'Enter an amount above S$0.00 with at most two decimal places.');
  assert.equal(settlementFormError(form({ amount: '-5' }), 555.27, '2026-10-09'), 'Enter an amount above S$0.00 with at most two decimal places.');
  assert.equal(settlementFormError(form({ amount: '' }), 555.27, '2026-10-09'), 'Enter an amount above S$0.00 with at most two decimal places.');
  assert.equal(settlementFormError(form({ amount: '555.28' }), 555.27, '2026-10-09'), 'Enter at most S$555.27, what this affiliate owes back.');
  assert.equal(settlementFormError(form({ amount: '100' }), 555.27, '2026-10-09'), '', 'part of it may be settled');
  assert.equal(settlementFormError(form({ date: '2026-10-10' }), 555.27, '2026-10-09'), 'Enter the date it was settled. It cannot be after today in Singapore.');
  assert.equal(settlementFormError(form({ date: '' }), 555.27, '2026-10-09'), 'Enter the date it was settled. It cannot be after today in Singapore.');
  assert.equal(settlementFormError(form({ note: '   ' }), 555.27, '2026-10-09'), 'A note is required: say how and why it was settled.');
  assert.equal(settlementFormError(form({ note: 'x'.repeat(2001) }), 555.27, '2026-10-09'), 'The note is too long (2,000 characters at most).');
  assert.equal(settlementFormError(form(), 0, '2026-10-09'), 'Enter at most S$0.00, what this affiliate owes back.', 'nothing owed back: nothing to settle');
});

test('the date: not before 1 Jan 2020, nor before the affiliate\'s first payout, said as the server says it', () => {
  assert.equal(settlementFormError(form({ date: '2019-12-31' }), 555.27, '2026-10-09'), 'Enter the date it was settled. It cannot be before 1 Jan 2020.');
  assert.equal(settlementFormError(form({ date: '2020-01-01' }), 555.27, '2026-10-09'), '');
  assert.equal(settlementFormError(form({ date: '2026-10-01' }), 555.27, '2026-10-09', '2026-10-02'),
    'The date it was settled cannot be before the first payout to this affiliate, on 2 Oct 2026.');
  assert.equal(settlementFormError(form({ date: '2026-10-02' }), 555.27, '2026-10-09', '2026-10-02'), '', 'the day of the first payout is accepted');
  assert.equal(settlementFormError(form({ date: '2026-10-01' }), 555.27, '2026-10-09', null), '', 'no payout listed: the server decides');
  const payouts = [
    { referrer_customer_id: 'a', status: 'paid', payment_date: '2026-10-06' },
    { referrer_customer_id: 'a', status: 'paid', payment_date: '2026-10-02' },
    { referrer_customer_id: 'a', status: 'superseded', payment_date: '2026-09-01' },
    { referrer_customer_id: 'b', status: 'paid', payment_date: '2026-08-01' },
  ];
  assert.equal(firstPaidPayoutDate(payouts, 'a'), '2026-10-02', 'the earliest payout still paid');
  assert.equal(firstPaidPayoutDate(payouts, 'c'), null);
  assert.equal(longDate('2026-10-02'), '2 Oct 2026');
  assert.equal(longDate('2020-01-01'), '1 Jan 2020');
  assert.equal(sgDate('2026-10-09'), '09/10/2026', 'as en-SG shows a date');
  assert.equal(sgDate('2026-10-09'), new Date('2026-10-09T00:00:00+08:00').toLocaleDateString('en-SG', { timeZone: 'Asia/Singapore' }));
  assert.equal(sgDate(''), '');
});

test('a voided settlement no longer counts', () => {
  const list = [settlement(), settlement({ id: 's2', amount: '55.27' }), settlement({ id: 's3', amount: 400, voided_at: '2026-10-02T00:00:00Z' }),
                settlement({ id: 's4', referrer_customer_id: 'b', amount: 10 })];
  assert.deepEqual(settlementsInForce(list, 'a').map(s => s.id), ['s1', 's2']);
  assert.equal(settledTotal(list, 'a'), 155.27);
  assert.equal(settledTotal(list), 165.27);
  assert.equal(settledTotal([], 'a'), 0);
  assert.equal(settlementInRange(settlement(), '2026-10-01', '2026-10-31'), true);
  assert.equal(settlementInRange(settlement(), '2026-10-02', ''), false);
});

test('the export names how, the note, who and whether it was voided', () => {
  const cols = settlementExportColumns(id => (id === 'a' ? 'Alpha Affiliate' : 'Name unavailable'));
  const row = Object.fromEntries(cols.map(c => [c.header, c.value(settlement({ voided_at: '2026-10-02T00:00:00Z', void_reason: 'Wrong affiliate' }))]));
  assert.deepEqual(row, { 'Settlement ID': 's1', 'Date settled': '2026-10-01', Affiliate: 'Alpha Affiliate', 'Affiliate ID': 'a', Amount: 100,
    How: 'Paid back to us', Note: 'n', 'Recorded by': 'Owner One', Status: 'Voided', 'Void reason': 'Wrong affiliate' });
});

test('the Dashboard: what affiliates are owed, as the Commissions page nets it; the old sum only before 414', () => {
  assert.deepEqual(dashboardCommissionFigures({ unpaid_commission: '737.03', commission_deductions: '555.27' }, 96.62),
    { unpaid: 737.03, deductions: 555.27, fromServer: true });
  assert.deepEqual(dashboardCommissionFigures({ unpaid_commission: 737.03, commission_deductions: 0 }, 96.62),
    { unpaid: 737.03, deductions: 0, fromServer: true });
  assert.deepEqual(dashboardCommissionFigures({ today_sales: 5 }, 96.62), { unpaid: 96.62, deductions: 0, fromServer: false }, 'before 414');
  assert.deepEqual(dashboardCommissionFigures(null, 0), { unpaid: 0, deductions: 0, fromServer: false });
});

test('the portal: the amount settled only, so Lifetime - Paid + settled = Unpaid - Deduction', () => {
  const summary = { lifetime: 814.75, paid: 1370.02, unpaid: 0, deduction: 0, settled: 555.27 };
  assert.equal(settledFigure(summary), 555.27);
  assert.deepEqual(earningsFigures(summary), { unpaid: 0, deduction: 0 });
  assert.equal(Math.round((summary.lifetime - summary.paid + settledFigure(summary)) * 100) / 100, 0);
  assert.equal(settledFigure({ unpaid: 5 }), 0, 'before 414 nothing is sent');
  assert.equal(settledFigure(null), 0);
});
