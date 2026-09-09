// The unlimited-therapy expiry rules, one test per rule in the specification.
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  baseExpiry, adjustedExpiry, calendarDaysRemaining, periodStatus,
  nextConsecutiveStart, isSunday, isDateOnly, addDays,
} from '../../../src/lib/therapy/expiry.mjs';

const H = (date, extra = {}) => ({ date, kind: 'public_holiday', name: 'Test holiday', ...extra });
const C = (date, extra = {}) => ({ date, kind: 'closure', name: 'Company closure', ...extra });

test('expiry is inclusive: the last usable day, matching therapy_expiry()', () => {
  // start + interval - 1 day. One month from 15 Jan ends on 14 Feb.
  assert.equal(baseExpiry('2026-01-15', 1), '2026-02-14');
  assert.equal(baseExpiry('2026-01-01', 12), '2026-12-31');
});

test('calendar months, not 30-day blocks, and month ends clamp', () => {
  assert.equal(baseExpiry('2026-01-31', 1), '2026-02-27');   // 28 Feb, minus a day
  assert.equal(baseExpiry('2026-03-31', 1), '2026-04-29');
  assert.equal(baseExpiry('2026-02-28', 1), '2026-03-27');
});

test('leap years', () => {
  assert.equal(baseExpiry('2024-01-31', 1), '2024-02-28');   // 29 Feb, minus a day
  assert.equal(baseExpiry('2024-02-29', 12), '2025-02-27');
  assert.equal(baseExpiry('2024-02-29', 1), '2024-03-28');
  assert.equal(isDateOnly('2026-02-29'), false, '2026 is not a leap year');
});

test('an ordinary Sunday earns nothing, and expiry is not nudged off a Sunday', () => {
  const start = '2026-01-05';                                 // Monday
  const base = baseExpiry(start, 1);                          // 2026-02-04
  const r = adjustedExpiry({ activationDate: start, months: 1, closures: [] });
  assert.equal(r.adjustedExpiry, base);
  assert.equal(r.addedDays, 0);

  // A period that lands on a Sunday stays on that Sunday.
  const sun = adjustedExpiry({ activationDate: '2026-01-08', months: 1, closures: [] });
  assert.equal(sun.adjustedExpiry, '2026-02-07');
  const onSunday = adjustedExpiry({ activationDate: '2026-01-09', months: 1, closures: [] });
  assert.ok(isSunday(onSunday.adjustedExpiry), 'this case ends on a Sunday');
  assert.equal(onSunday.adjustedExpiry, onSunday.baseExpiry, 'and it is left there');
});

test('a Monday-to-Saturday holiday adds exactly one day', () => {
  const r = adjustedExpiry({
    activationDate: '2026-01-05', months: 1,
    closures: [H('2026-01-15')],                              // Thursday
  });
  assert.equal(r.baseExpiry, '2026-02-04');
  assert.equal(r.adjustedExpiry, '2026-02-05');
  assert.equal(r.addedDays, 1);
  assert.deepEqual(r.appliedDates.map(a => a.date), ['2026-01-15']);
});

test('a Sunday holiday and a Sunday closure add nothing', () => {
  const r = adjustedExpiry({
    activationDate: '2026-01-05', months: 1,
    closures: [H('2026-01-11'), C('2026-01-18')],             // both Sundays
  });
  assert.equal(r.addedDays, 0);
  assert.equal(r.adjustedExpiry, r.baseExpiry);
  assert.equal(r.ignoredSundays.length, 2, 'and they are reported, not hidden');
});

test('a holiday that is also a company closure counts once', () => {
  const r = adjustedExpiry({
    activationDate: '2026-01-05', months: 1,
    closures: [H('2026-01-15'), C('2026-01-15')],
  });
  assert.equal(r.addedDays, 1);
  assert.equal(r.appliedDates.length, 1);
  assert.equal(r.appliedDates[0].sources.length, 2, 'both records are kept for the explanation');
});

test('duplicate closure records for the same date count once', () => {
  const r = adjustedExpiry({
    activationDate: '2026-01-05', months: 1,
    closures: [C('2026-01-15'), C('2026-01-15'), C('2026-01-15')],
  });
  assert.equal(r.addedDays, 1);
});

test('a substitute holiday on the Monday is its own eligible date', () => {
  // Vesak Day 2026 falls on Sunday 31 May; the observed day is Monday 1 June.
  // The Sunday earns nothing and the Monday earns one day — two records, one day.
  const r = adjustedExpiry({
    activationDate: '2026-05-04', months: 1,
    closures: [H('2026-05-31', { name: 'Vesak Day' }),
               H('2026-06-01', { name: 'Vesak Day (observed)', observed_for: '2026-05-31' })],
  });
  assert.equal(r.addedDays, 1);
  assert.deepEqual(r.appliedDates.map(a => a.date), ['2026-06-01']);
});

test('a closure uncovered by the extension extends it again, until stable', () => {
  // Base expiry 4 Feb. The 15 Jan holiday pushes it to the 5th; the 5th is
  // itself a closure, which pushes it to the 6th.
  const r = adjustedExpiry({
    activationDate: '2026-01-05', months: 1,
    closures: [H('2026-01-15'), C('2026-02-05')],
  });
  assert.equal(r.baseExpiry, '2026-02-04');
  assert.equal(r.adjustedExpiry, '2026-02-06');
  assert.equal(r.addedDays, 2);
  assert.ok(r.iterations > 1, 'it took more than one pass');
});

test('recalculation is idempotent — the same input never adds the days twice', () => {
  const args = {
    activationDate: '2026-01-05', months: 1,
    closures: [H('2026-01-15'), C('2026-02-05'), H('2026-01-11')],
  };
  const a = adjustedExpiry(args);
  const b = adjustedExpiry(args);
  const c = adjustedExpiry({ ...args, closures: [...args.closures].reverse() });
  assert.equal(a.adjustedExpiry, b.adjustedExpiry);
  assert.equal(a.adjustedExpiry, c.adjustedExpiry, 'and does not depend on input order');

  // Feeding the adjusted expiry back in as if it were a new base would double
  // count; the function is defined from the base, so this cannot happen.
  assert.equal(a.baseExpiry, '2026-02-04');
});

test('closures outside the period are ignored', () => {
  const r = adjustedExpiry({
    activationDate: '2026-01-05', months: 1,
    closures: [H('2026-01-01'), H('2026-03-10')],
  });
  assert.equal(r.addedDays, 0);
});

test('a closure on the activation day itself counts', () => {
  const r = adjustedExpiry({
    activationDate: '2026-01-05', months: 1, closures: [H('2026-01-05')],
  });
  assert.equal(r.addedDays, 1);
});

test('calendar days remaining is inclusive of today and of the expiry day', () => {
  assert.equal(calendarDaysRemaining('2026-01-10', '2026-01-10'), 1, 'the last day still counts');
  assert.equal(calendarDaysRemaining('2026-01-10', '2026-01-01'), 10);
  assert.equal(calendarDaysRemaining('2026-01-01', '2026-01-10'), 0, 'never negative');
  assert.equal(calendarDaysRemaining(null, '2026-01-10'), null);
});

test('status comes from the dates alone', () => {
  const today = '2026-06-15';
  assert.equal(periodStatus({ activationDate: '2026-07-01', expiryDate: '2026-07-31', today }), 'scheduled');
  assert.equal(periodStatus({ activationDate: '2026-06-01', expiryDate: '2026-06-30', today }), 'active');
  assert.equal(periodStatus({ activationDate: '2026-06-15', expiryDate: '2026-06-15', today }), 'active');
  assert.equal(periodStatus({ activationDate: '2026-01-01', expiryDate: '2026-01-31', today }), 'expired');
  assert.equal(periodStatus({ activationDate: null, expiryDate: null, today }), 'pending');
});

test('a consecutive package starts the day after the latest adjusted expiry', () => {
  assert.equal(nextConsecutiveStart(['2026-02-06', '2026-01-10'], '2026-01-01'), '2026-02-07');
  assert.equal(nextConsecutiveStart([], '2026-01-01'), '2026-01-01');
  assert.equal(nextConsecutiveStart(['2025-01-01'], '2026-01-01'), '2026-01-01',
    'an expiry already in the past does not push the start backwards');
  assert.equal(nextConsecutiveStart([null, '2026-03-01'], '2026-01-01'), '2026-03-02');
});

test('date arithmetic survives month, year and epoch boundaries', () => {
  assert.equal(addDays('2026-12-31', 1), '2027-01-01');
  assert.equal(addDays('2027-01-01', -1), '2026-12-31');
  assert.equal(addDays('2024-02-28', 1), '2024-02-29');
  assert.equal(addDays('1970-01-01', 0), '1970-01-01');
});

test('there is one calendar-month convention, and 29 February follows it', () => {
  // membership_expiry() would make this 2025-02-28. It is not installed — Phase
  // 19 dropped it and migration 72 moved purchased therapy onto therapy_expiry —
  // so the single rule applies to purchased and Legacy alike.
  assert.equal(baseExpiry('2024-02-29', 12), '2025-02-27');
  assert.equal(baseExpiry('2024-02-29', 1), '2024-03-28');
  assert.equal(baseExpiry('2023-03-01', 12), '2024-02-29', 'a leap day can be the last day');
});

test('the closure extension is applied on top of that one base', () => {
  const closures = [{ date: '2024-06-03' }];          // a Monday inside the period
  const r = adjustedExpiry({ activationDate: '2024-02-29', months: 12, closures });
  assert.equal(r.baseExpiry, '2025-02-27');
  assert.equal(r.addedDays, 1);
  assert.equal(r.adjustedExpiry, '2025-02-28');
});
