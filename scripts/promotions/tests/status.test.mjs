// Where a promotion stands on a given Singapore day (SALES-EXTRAS-9).
//
// Run: node --test scripts/promotions/tests/status.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { promotionStatus, promotionOnSale, promotionStatusBadge, displayDateOnly }
  from '../../../src/lib/promotions/status.mjs';

const TODAY = '2026-10-09';

test('switched on and in its dates: Active, both end days included', () => {
  assert.equal(promotionStatus({ is_active: true }, TODAY), 'Active');
  assert.equal(promotionStatus({ is_active: true, start_date: '2026-10-09', end_date: '2026-10-09' }, TODAY), 'Active');
  assert.equal(promotionStatus({ is_active: true, start_date: '2026-07-01', end_date: null }, TODAY), 'Active');
  assert.ok(promotionOnSale({ is_active: true, end_date: '2026-10-31' }, TODAY));
});

test('past its end date: Ended (the 12 September bundles that ended on 1 Oct)', () => {
  const sept = { is_active: true, start_date: '2026-07-01', end_date: '2026-10-01' };
  assert.equal(promotionStatus(sept, TODAY), 'Ended');
  assert.equal(promotionOnSale(sept, TODAY), false);
  // on the last day it is still on sale
  assert.equal(promotionStatus(sept, '2026-10-01'), 'Active');
});

test('before its start date: Not started', () => {
  const later = { is_active: true, start_date: '2026-11-01', end_date: '2026-11-30' };
  assert.equal(promotionStatus(later, TODAY), 'Not started');
  assert.equal(promotionOnSale(later, TODAY), false);
});

test('switched off or deleted: Inactive, whatever its dates', () => {
  assert.equal(promotionStatus({ is_active: false, end_date: '2026-10-01' }, TODAY), 'Inactive');
  assert.equal(promotionStatus({ is_active: true, deleted_at: '2026-10-02T00:00:00Z' }, TODAY), 'Inactive');
  assert.equal(promotionStatus(null, TODAY), 'Inactive');
});

test('badges and dates', () => {
  assert.equal(promotionStatusBadge('Active'), 'badge-success');
  assert.equal(promotionStatusBadge('Ended'), 'badge-danger');
  assert.equal(promotionStatusBadge('Not started'), 'badge-accent');
  assert.equal(promotionStatusBadge('Inactive'), 'badge-muted');
  // a date-only value is shown as it is, never shifted by a time zone
  assert.equal(displayDateOnly('2026-10-01'), '01/10/2026');
  assert.equal(displayDateOnly(null), '');
  assert.equal(displayDateOnly('not a date'), '');
});
