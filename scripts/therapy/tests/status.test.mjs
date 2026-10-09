// 410: a therapy entitlement's status by its dates, as the Therapy page shows
// it. The same cases as scripts/therapy/tests/status-refresh.sql section 3
// (purchased_therapy_status_on), so the page and the server cannot drift.
import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
const compiled = await build({ stdin: { contents: "export * from './src/lib/therapy/status';", resolveDir: process.cwd() }, bundle: true, write: false, format: 'esm' });
const { purchasedStatusOn, legacyStatusOn } = await import('data:text/javascript;base64,' + Buffer.from(compiled.outputFiles[0].text).toString('base64'));

const d = '2026-10-09';
const P = (status, activation_date, expiry_date, activation_deadline) => purchasedStatusOn({ status, activation_date, expiry_date, activation_deadline }, d);

test('a scheduled start already reached has started (UTP-0000010: 2 Oct, still "scheduled" on 9 Oct)', () => {
  assert.equal(P('scheduled', '2026-10-02', '2027-04-08', '2027-09-08'), 'active');
  assert.equal(P('scheduled', '2026-10-09', '2027-04-08', '2027-09-08'), 'active', 'a start today has started');
  assert.equal(P('scheduled', '2026-10-10', '2027-04-08', '2027-09-08'), 'scheduled');
});

test('an expiry passed has ended, also for a start never refreshed', () => {
  assert.equal(P('scheduled', '2026-01-01', '2026-10-08', '2027-01-01'), 'expired');
  assert.equal(P('active', '2026-01-01', '2026-10-09', '2027-01-01'), 'active', 'the expiry is the last day it can be used');
  assert.equal(P('active', '2026-01-01', '2026-10-08', '2027-01-01'), 'expired');
  assert.equal(P('active', '2026-10-01', null, '2027-01-01'), 'active', 'a unit taken as vouchers has no expiry');
});

test('never started by the deadline has expired; closed stays closed', () => {
  assert.equal(P('pending_activation', null, null, '2026-10-09'), 'pending_activation');
  assert.equal(P('pending_activation', null, null, '2026-10-08'), 'expired');
  assert.equal(P('scheduled', null, null, '2026-10-08'), 'expired', 'rescheduled without a start date');
  assert.equal(P('scheduled', null, null, '2026-10-09'), 'scheduled');
  assert.equal(P('cancelled', '2026-01-01', '2026-02-01', '2026-03-01'), 'cancelled');
  assert.equal(P('refunded', null, null, '2026-03-01'), 'refunded');
  assert.equal(P('expired', null, null, '2026-03-01'), 'expired');
});

test('Legacy: a start reached is active, an expiry passed is expired (LEG-0000081 ends 13 Oct)', () => {
  assert.equal(legacyStatusOn({ status: 'active', activation_date: '2026-07-14', expiry_date: '2026-10-13' }, '2026-10-13'), 'active');
  assert.equal(legacyStatusOn({ status: 'active', activation_date: '2026-07-14', expiry_date: '2026-10-13' }, '2026-10-14'), 'expired');
  assert.equal(legacyStatusOn({ status: 'scheduled', activation_date: '2026-10-06', expiry_date: '2027-01-05' }, d), 'active');
  assert.equal(legacyStatusOn({ status: 'pending_activation', activation_date: null, expiry_date: null }, d), 'pending_activation');
});
