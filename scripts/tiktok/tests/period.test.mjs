// Settlement periods: the last-Wednesday rule, and the Singapore day boundary.
//
//   npm run test:tiktok

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  lastWednesday, settlementPeriod, toIsoDate, periodInstantRange, periodLabel,
  settledDateSgt, isInPeriod, reportingMonthFor,
} from '../../../src/lib/tiktok/settlementPeriod.mjs';

const range = (y, m) => `${toIsoDate(settlementPeriod(y, m).start)}..${toIsoDate(settlementPeriod(y, m).end)}`;

test('the three documented examples', () => {
  assert.equal(range(2026, 8), '2026-07-30..2026-08-26');
  assert.equal(range(2026, 9), '2026-08-27..2026-09-30');
  assert.equal(range(2026, 10), '2026-10-01..2026-10-28');
});

test('a month ending ON a Wednesday does not overlap the next period', () => {
  // September 2026 ends on Wednesday 30 September, so October must start on the
  // 1st. Reading the rule as "the previous month's last Thursday" would start
  // October on 24 September and double-count a week.
  assert.equal(toIsoDate(settlementPeriod(2026, 9).end), '2026-09-30');
  assert.equal(toIsoDate(settlementPeriod(2026, 10).start), '2026-10-01');
});

test('consecutive periods tile the calendar with no gap and no overlap', () => {
  let prevEnd = null;
  for (let y = 2024; y <= 2030; y++) {
    for (let m = 1; m <= 12; m++) {
      const { start, end } = settlementPeriod(y, m);
      assert.ok(toIsoDate(start) <= toIsoDate(end), `${y}-${m} start after end`);
      if (prevEnd) {
        const dayAfter = new Date(Date.UTC(prevEnd.y, prevEnd.m - 1, prevEnd.d + 1));
        const expected = `${dayAfter.getUTCFullYear()}-${String(dayAfter.getUTCMonth() + 1).padStart(2, '0')}-${String(dayAfter.getUTCDate()).padStart(2, '0')}`;
        assert.equal(toIsoDate(start), expected, `gap or overlap before ${y}-${m}`);
      }
      prevEnd = end;
    }
  }
});

test('every period ends on a Wednesday, in its own month', () => {
  for (let y = 2024; y <= 2030; y++) {
    for (let m = 1; m <= 12; m++) {
      const e = settlementPeriod(y, m).end;
      assert.equal(new Date(Date.UTC(e.y, e.m - 1, e.d)).getUTCDay(), 3, `${y}-${m} not a Wednesday`);
      assert.equal(e.m, m, `${y}-${m} ended outside its month`);
    }
  }
});

test('year transitions', () => {
  // January's period reaches back into the previous December.
  const jan = settlementPeriod(2027, 1);
  assert.equal(jan.start.y, 2026);
  assert.equal(jan.start.m, 12);
  assert.equal(toIsoDate(settlementPeriod(2026, 12).end), '2026-12-30');
  assert.equal(toIsoDate(jan.start), '2026-12-31');
});

test('leap and non-leap February', () => {
  assert.equal(lastWednesday(2028, 2).d, 23);              // 2028 is a leap year
  assert.equal(toIsoDate(settlementPeriod(2028, 2).end), '2028-02-23');
  assert.equal(toIsoDate(settlementPeriod(2027, 2).end), '2027-02-24');
  // 29 February must be reachable as a period boundary when it is a Wednesday.
  assert.equal(new Date(Date.UTC(2028, 1, 29)).getUTCDay(), 2);
});

test('four- and five-Wednesday months', () => {
  // A month starting on a Wednesday has five of them.
  assert.equal(new Date(Date.UTC(2026, 6, 1)).getUTCDay(), 3);   // 1 Jul 2026 is a Wednesday
  assert.equal(lastWednesday(2026, 7).d, 29);
  assert.equal(lastWednesday(2026, 2).d, 25);                     // four Wednesdays
});

test('the instant range is half-open on the Singapore day boundary', () => {
  const { startInclusive, endExclusive } = periodInstantRange(2026, 8);
  // 30 Jul 2026 00:00 SGT is 29 Jul 16:00 UTC.
  assert.equal(startInclusive.toISOString(), '2026-07-29T16:00:00.000Z');
  // Exclusive end is the start of 27 Aug SGT, so 23:59:59.999 on the 26th is in.
  assert.equal(endExclusive.toISOString(), '2026-08-26T16:00:00.000Z');
  const lastMoment = new Date(endExclusive.getTime() - 1);
  assert.ok(lastMoment < endExclusive);
  assert.ok(new Date('2026-08-26T15:59:59.999Z') < endExclusive, 'end of the last day is included');
  assert.ok(new Date('2026-08-26T16:00:00.000Z') >= endExclusive, 'the next day is excluded');
});

test('a timezone-free value is read as Singapore wall time', () => {
  assert.equal(settledDateSgt('2026/08/01'), '2026-08-01');
  assert.equal(settledDateSgt('2026-08-01'), '2026-08-01');
  assert.equal(settledDateSgt('2026/08/01 23:45:02'), '2026-08-01');
  // The export is stamped UTC+8, so no shifting happens and the date stands.
  assert.equal(settledDateSgt('2026/08/01 00:15:00'), '2026-08-01');
});

test('a value with an explicit offset is converted, not taken literally', () => {
  // 26 Aug 17:00 UTC is already 27 Aug in Singapore, so it belongs to September.
  assert.equal(settledDateSgt('2026-08-26T17:00:00Z'), '2026-08-27');
  assert.equal(settledDateSgt('2026-08-26T16:00:00+00:00'), '2026-08-27');
  assert.equal(settledDateSgt('2026-08-27T00:30:00+08:00'), '2026-08-27');
  assert.equal(isInPeriod(settledDateSgt('2026-08-26T17:00:00Z'), 2026, 9), true);
  assert.equal(isInPeriod(settledDateSgt('2026-08-26T17:00:00Z'), 2026, 8), false);
});

test('unusable settled dates return null rather than a guess', () => {
  for (const bad of [null, undefined, '', '  ', '/', '-', 'n/a', 'pending', '2026/13/01', '2026/02/30', 'not a date']) {
    assert.equal(settledDateSgt(bad), null, `should reject ${JSON.stringify(bad)}`);
  }
});

test('a Date instance is treated as an instant', () => {
  assert.equal(settledDateSgt(new Date('2026-08-26T17:00:00Z')), '2026-08-27');
  assert.equal(settledDateSgt(new Date('invalid')), null);
});

test('a settled date maps back to exactly one reporting month', () => {
  assert.deepEqual(reportingMonthFor('2026-07-30'), { year: 2026, month: 8 });
  assert.deepEqual(reportingMonthFor('2026-08-26'), { year: 2026, month: 8 });
  assert.deepEqual(reportingMonthFor('2026-08-27'), { year: 2026, month: 9 });
  assert.deepEqual(reportingMonthFor('2026-09-30'), { year: 2026, month: 9 });
  assert.deepEqual(reportingMonthFor('2026-10-01'), { year: 2026, month: 10 });
  assert.equal(reportingMonthFor(null), null);
});

test('the label states the range and the timezone', () => {
  assert.equal(periodLabel(2026, 8), '30 Jul – 26 Aug 2026 (SGT)');
  assert.equal(periodLabel(2027, 1), '31 Dec 2026 – 27 Jan 2027 (SGT)');
});
