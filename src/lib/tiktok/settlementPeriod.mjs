// TikTok settlement periods.
//
// A reporting month ends on the LAST WEDNESDAY of that month, and starts the day
// after the previous month's last Wednesday. Both displayed dates are inclusive,
// and consecutive periods therefore tile the calendar with no gap and no overlap
// — which is the point: every settled transaction lands in exactly one month.
//
//   August 2026     30 Jul – 26 Aug
//   September 2026  27 Aug – 30 Sep      (September ends ON a Wednesday)
//   October 2026     1 Oct – 28 Oct      (so October starts on the 1st)
//
// September shows why the rule is written as "the day after the previous
// period's end" rather than "the previous month's last Thursday": when a month
// ends on a Wednesday the naive reading would overlap the neighbouring period.
//
// All arithmetic is done on a plain year/month/day triple using UTC helpers, so
// nothing here depends on the machine's timezone or on Date string parsing.
// Singapore has been UTC+8 with no daylight saving since 1982, so a Singapore
// calendar day is a fixed 8-hour offset — see `sgtDayRange` for the boundary
// used when filtering timestamps.

const SGT_OFFSET_MINUTES = 8 * 60;

const daysInMonth = (y, m) => new Date(Date.UTC(y, m, 0)).getUTCDate();
const dayOfWeek = (y, m, d) => new Date(Date.UTC(y, m - 1, d)).getUTCDay();
const WEDNESDAY = 3;

/** The last Wednesday of a month, as {y, m, d}. */
export function lastWednesday(year, month) {
  const last = daysInMonth(year, month);
  const back = (dayOfWeek(year, month, last) - WEDNESDAY + 7) % 7;
  return { y: year, m: month, d: last - back };
}

/** The settlement period for a reporting month: inclusive {start, end}. */
export function settlementPeriod(year, month) {
  const end = lastWednesday(year, month);
  const prevYear = month === 1 ? year - 1 : year;
  const prevMonth = month === 1 ? 12 : month - 1;
  const prevEnd = lastWednesday(prevYear, prevMonth);
  // The day after the previous period's end. Going through Date handles the
  // month and year rollover, including 31 Dec -> 1 Jan and 28/29 Feb.
  const next = new Date(Date.UTC(prevEnd.y, prevEnd.m - 1, prevEnd.d + 1));
  return {
    start: { y: next.getUTCFullYear(), m: next.getUTCMonth() + 1, d: next.getUTCDate() },
    end,
  };
}

/** {y,m,d} as YYYY-MM-DD. */
export const toIsoDate = ({ y, m, d }) =>
  `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

/**
 * The half-open instant range covering a period in Singapore time:
 * from the start of the first day, up to but NOT including the start of the day
 * after the last day.
 *
 * Half-open on purpose. A closed range written as `<= 23:59:59` silently drops
 * anything in the final second, and one written against a timestamp with
 * sub-second precision drops more than that.
 */
export function periodInstantRange(year, month) {
  const { start, end } = settlementPeriod(year, month);
  const startUtc = Date.UTC(start.y, start.m - 1, start.d) - SGT_OFFSET_MINUTES * 60_000;
  const endUtc = Date.UTC(end.y, end.m - 1, end.d + 1) - SGT_OFFSET_MINUTES * 60_000;
  return { startInclusive: new Date(startUtc), endExclusive: new Date(endUtc) };
}

/** Human label, e.g. "30 Jul – 26 Aug 2026 (SGT)". */
export function periodLabel(year, month) {
  const { start, end } = settlementPeriod(year, month);
  const mon = i => ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][i - 1];
  const left = `${start.d} ${mon(start.m)}${start.y !== end.y ? ` ${start.y}` : ''}`;
  return `${left} – ${end.d} ${mon(end.m)} ${end.y} (SGT)`;
}

/**
 * The Singapore calendar day a source value falls on, as YYYY-MM-DD.
 *
 * The export is stamped UTC+8 and writes times without an offset, so a bare
 * "2026/08/01" or "2026/08/01 13:45:02" is Singapore wall time and its date is
 * simply the date as written — no conversion, and deliberately no `new Date(s)`,
 * whose behaviour on non-ISO strings is engine-dependent.
 *
 * A value that DOES carry an explicit offset is converted properly, because then
 * the instant is unambiguous and the Singapore date may differ from the date as
 * written.
 *
 * Returns null for anything unparseable, so the caller can put the row on a
 * review list rather than guessing a month for it.
 */
export function settledDateSgt(value) {
  if (value === null || value === undefined) return null;

  // A real Date (a cell read with cellDates) is an instant: convert.
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : utcInstantToSgtDate(value.getTime());
  }

  const s = String(value).trim();
  if (s === '' || s === '/' || s === '-') return null;

  // Explicit offset, e.g. 2026-08-01T05:45:02+08:00 or ...Z
  if (/[Zz]$|[+-]\d{2}:?\d{2}$/.test(s)) {
    const t = Date.parse(s);
    return Number.isNaN(t) ? null : utcInstantToSgtDate(t);
  }

  // Offset-free: the date as written is already the Singapore date.
  const m = /^(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})/.exec(s);
  if (!m) return null;
  const [, y, mo, d] = m;
  const year = Number(y), month = Number(mo), day = Number(d);
  if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month)) return null;
  return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

function utcInstantToSgtDate(ms) {
  const shifted = new Date(ms + SGT_OFFSET_MINUTES * 60_000);
  return `${shifted.getUTCFullYear()}-${String(shifted.getUTCMonth() + 1).padStart(2, '0')}-${String(shifted.getUTCDate()).padStart(2, '0')}`;
}

/** Is a Singapore calendar date inside the reporting month's period? */
export function isInPeriod(isoDate, year, month) {
  if (!isoDate) return false;
  const { start, end } = settlementPeriod(year, month);
  return isoDate >= toIsoDate(start) && isoDate <= toIsoDate(end);
}

/** The reporting month a settled date belongs to, as {year, month}. */
export function reportingMonthFor(isoDate) {
  if (!isoDate) return null;
  const [y, m] = isoDate.split('-').map(Number);
  // A date at the very start of a month can belong to the previous reporting
  // month, and one near the end can belong to the next; check the neighbours.
  for (const [cy, cm] of [[y, m], nextMonth(y, m), prevMonth(y, m)]) {
    if (isInPeriod(isoDate, cy, cm)) return { year: cy, month: cm };
  }
  return null;
}
const nextMonth = (y, m) => (m === 12 ? [y + 1, 1] : [y, m + 1]);
const prevMonth = (y, m) => (m === 1 ? [y - 1, 12] : [y, m - 1]);
