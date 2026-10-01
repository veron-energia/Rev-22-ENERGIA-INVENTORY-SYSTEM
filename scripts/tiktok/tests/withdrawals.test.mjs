// TikTok's "Withdrawal records" sheet, read from the income export
// (src/lib/tiktok/withdrawals.mjs). Reference IDs, amounts and the bank
// account below are invented.
//
// Run: node --test scripts/tiktok/tests/withdrawals.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { describeWithdrawals, readWithdrawalRecords } from '../../../src/lib/tiktok/withdrawals.mjs';

const HEADERS = ['Transaction type', 'Reference ID', 'Request time', 'Amount', 'Status', 'Success time', 'Bank account'];
const orderDetails = { name: 'Order details', grid: [['Order/Adjustment ID', 'Transaction type', 'Total settlement amount'], ['5800000000000001', 'Order', '80']] };
const withdrawals = { name: 'Withdrawal records', grid: [
  HEADERS,
  ['Payments', '3600000000000000001', '2026/09/02', '-713', 'Transferred', '2026/09/02', 'DBS ****1234'],
  ['Earnings', '3600000000000000002', '2026/09/01', '96.5', 'Transferred', '2026/09/01', ''],
  ['GMV Pay Deduction', '3600000000000000003', '2026/09/01', '-20', 'Transferred', '2026/09/01', ''],
  ['', '', '', '', '', '', ''],
  ['Payments', '', '2026/09/09', '-5', 'Transferred', '2026/09/09', ''],
] };

test('the sheet is found by its headers, and its rows are read as text without the bank account', () => {
  const found = readWithdrawalRecords([orderDetails, { name: 'Reports', grid: [['Total', '1']] }, withdrawals], 'Order details');
  assert.equal(found.sheetName, 'Withdrawal records');
  assert.deepEqual(found.rows, [
    { transaction_type: 'Payments', reference_id: '3600000000000000001', request_time: '2026/09/02', amount: '-713', status: 'Transferred', success_time: '2026/09/02' },
    { transaction_type: 'Earnings', reference_id: '3600000000000000002', request_time: '2026/09/01', amount: '96.5', status: 'Transferred', success_time: '2026/09/01' },
    { transaction_type: 'GMV Pay Deduction', reference_id: '3600000000000000003', request_time: '2026/09/01', amount: '-20', status: 'Transferred', success_time: '2026/09/01' },
  ], 'blank rows and rows without a Reference ID are left out; the long Reference ID keeps every digit');
  assert.ok(!JSON.stringify(found.rows).includes('1234'), 'the bank account is never read');
});

test('headers can sit below a title row and carry odd spacing', () => {
  const found = readWithdrawalRecords([{ name: 'Sheet3', grid: [['Withdrawal records'], [' Transaction  type', 'Reference ID', 'Amount', 'Success time']].concat([['Payments', '1', '-1', '2026/09/02']]) }]);
  assert.deepEqual(found.rows, [{ transaction_type: 'Payments', reference_id: '1', amount: '-1', success_time: '2026/09/02' }]);
});

test('no Withdrawal records sheet: nothing, and the settled lines sheet is never read as one', () => {
  assert.equal(readWithdrawalRecords([orderDetails]), null);
  assert.equal(readWithdrawalRecords([withdrawals], 'Withdrawal records'), null, 'the sheet already used for the settled lines is skipped');
});

test('what the file brought, in words', () => {
  const found = readWithdrawalRecords([withdrawals]);
  assert.equal(describeWithdrawals(found.rows), '1 payout and 2 other balance records');
  assert.equal(describeWithdrawals([]), '0 payouts and 0 other balance records');
});
