// Unlimited-therapy expiry: calendar months, then replacement days for
// closures that fall inside the period.
//
// Mirrored by migration 220 in SQL. A database test asserts the two agree on
// every case in the fixture, because one rule with two implementations drifts
// unless something compares them.
//
// Dates are handled as 'YYYY-MM-DD' strings throughout and never as Date
// instances carrying a time. A business date in this system is a Singapore
// calendar day (public.sg_today()), and turning one into a timestamp is how a
// date silently moves by one day. Day-of-week is the only calculation that
// needs arithmetic, and it is done at UTC noon so no timezone can shift it.

/** The convention, stated once: expiry is the LAST day the benefit can be used. */
export const EXPIRY_IS_INCLUSIVE = true;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

export function isDateOnly(s) {
  if (typeof s !== 'string' || !DATE_RE.test(s)) return false;
  // Date.parse rolls 2026-02-29 forward into March rather than rejecting it, so
  // the only reliable check is that the date survives a round trip unchanged.
  const t = Date.parse(`${s}T12:00:00Z`);
  return !Number.isNaN(t) && new Date(t).toISOString().slice(0, 10) === s;
}

function assertDate(s, label) {
  if (!isDateOnly(s)) throw new TypeError(`${label} must be a YYYY-MM-DD date, got ${JSON.stringify(s)}`);
  return s;
}

/** Days since epoch for a date-only string. Noon UTC keeps it away from every boundary. */
function dayNumber(s) {
  // floor, not round: noon is half a day past midnight, and rounding that up
  // shifts every date forward by one.
  return Math.floor(Date.parse(`${s}T12:00:00Z`) / 86400000);
}

function fromDayNumber(n) {
  return new Date(n * 86400000 + 43200000).toISOString().slice(0, 10);
}

export function addDays(date, n) {
  return fromDayNumber(dayNumber(assertDate(date, 'date')) + n);
}

/** 0 = Sunday … 6 = Saturday, matching PostgreSQL's extract(dow). */
export function dayOfWeek(date) {
  return new Date(`${assertDate(date, 'date')}T12:00:00Z`).getUTCDay();
}

export const isSunday = date => dayOfWeek(date) === 0;

/**
 * Calendar-month expiry, inclusive — the existing convention, unchanged:
 * `p_start + make_interval(months => n) - interval '1 day'`.
 *
 * Calendar months, not 30-day blocks: 31 Jan + 1 month is 28 Feb (29 in a leap
 * year), because PostgreSQL clamps a month addition to the end of the month and
 * this mirrors it rather than reimplementing it.
 */
export function baseExpiry(activationDate, months) {
  assertDate(activationDate, 'activationDate');
  const m = Number(months);
  if (!Number.isInteger(m) || m <= 0) return null;

  const [y, mo, d] = activationDate.split('-').map(Number);
  const targetMonth = mo - 1 + m;
  const year = y + Math.floor(targetMonth / 12);
  const month = targetMonth % 12;
  const lastDayOfTarget = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const day = Math.min(d, lastDayOfTarget);          // clamp, as PostgreSQL does
  const sameDayNextPeriod = `${String(year).padStart(4, '0')}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  return addDays(sameDayNextPeriod, -1);             // inclusive: the day before
}

/**
 * The other convention in this system, and the reason there are two.
 *
 * Purchased therapy computes its expiry with membership_expiry(); Legacy
 * qualification uses therapy_expiry(). They agree everywhere except a start on
 * 29 February whose anniversary clamps to the 28th:
 *
 *   therapy    2024-02-29 + 12 months -> 2025-02-27
 *   membership 2024-02-29 + 12 months -> 2025-02-28
 *
 * membership_expiry treats the clamped 28 February as the full period and does
 * not subtract a day. Customers hold live entitlements computed both ways, so
 * neither can be quietly replaced by the other; the convention travels with the
 * entitlement and the closure extension is applied on top of whichever base it
 * was granted under.
 */
export function membershipBaseExpiry(activationDate, months) {
  const m = Number(months);
  if (!isDateOnly(activationDate) || !Number.isInteger(m) || m <= 0) return null;
  const anniversary = addDays(baseExpiry(activationDate, m), 1);
  const startsOn29Feb = activationDate.slice(5) === '02-29';
  const clampedTo28Feb = anniversary.slice(5) === '02-28';
  return startsOn29Feb && clampedTo28Feb ? anniversary : baseExpiry(activationDate, m);
}

/** 'purchased' | 'legacy' — the base for an entitlement of that kind. */
export function baseExpiryFor(convention, activationDate, months) {
  return convention === 'purchased'
    ? membershipBaseExpiry(activationDate, months)
    : baseExpiry(activationDate, months);
}

/**
 * Which closure dates earn a replacement day.
 *
 * A Sunday earns nothing — the business is closed on Sundays anyway, so a
 * holiday falling on one takes nothing away that has to be given back. This is
 * also why expiry is NOT nudged off a Sunday: Sundays are part of the calendar
 * month that was sold, not days owed back.
 */
export function isEligibleClosureDate(date) {
  return !isSunday(date);
}

/**
 * Adjusted expiry, and the dates that justify it.
 *
 * Closures are counted inside [activation, expiry] inclusive, deduplicated by
 * date, and each eligible one pushes the expiry out by a day. Pushing the
 * expiry out can bring further closures into range, so it repeats until the
 * result stops moving.
 *
 * Always computed from the base expiry and the calendar — never by extending an
 * already-extended date — so running it twice gives the same answer. That is
 * what makes recalculation safe to re-run after a calendar correction.
 *
 * @param {object} args
 * @param {string} args.activationDate    'YYYY-MM-DD'
 * @param {number} args.months            calendar months sold
 * @param {Array<{date: string, kind?: string, name?: string, country?: string|null}>} args.closures
 * @param {'legacy'|'purchased'} [args.convention]  which base-expiry rule applies
 * @returns {{ baseExpiry: string|null, adjustedExpiry: string|null, addedDays: number,
 *             appliedDates: Array<object>, ignoredSundays: Array<object>, iterations: number }}
 */
export function adjustedExpiry({ activationDate, months, closures = [], convention = 'legacy' }) {
  const base = baseExpiryFor(convention, activationDate, months);
  if (base === null) {
    return { baseExpiry: null, adjustedExpiry: null, addedDays: 0, appliedDates: [], ignoredSundays: [], iterations: 0 };
  }

  // One record per date. Two closures on the same day — a public holiday that
  // is also a company closure, or the same date entered twice — are one day off,
  // so they earn one replacement day, not two.
  const byDate = new Map();
  for (const c of closures) {
    const date = typeof c === 'string' ? c : c?.date;
    if (!isDateOnly(date)) continue;
    if (!byDate.has(date)) byDate.set(date, { date, sources: [] });
    byDate.get(date).sources.push(typeof c === 'string' ? { date } : c);
  }
  const dates = [...byDate.keys()].sort();

  const applied = new Set();
  let expiry = base;
  let iterations = 0;
  for (;;) {
    iterations++;
    const newly = dates.filter(d =>
      !applied.has(d) && d >= activationDate && d <= expiry && isEligibleClosureDate(d));
    if (newly.length === 0) break;
    for (const d of newly) applied.add(d);
    expiry = addDays(expiry, newly.length);
    if (iterations > 3660) throw new Error('closure extension did not converge');  // ~10 years of closures
  }

  const appliedDates = [...applied].sort().map(d => byDate.get(d));
  const ignoredSundays = dates
    .filter(d => d >= activationDate && d <= expiry && isSunday(d))
    .map(d => byDate.get(d));

  return {
    baseExpiry: base,
    adjustedExpiry: expiry,
    addedDays: applied.size,
    appliedDates,
    ignoredSundays,
    iterations,
  };
}

/**
 * Calendar days remaining, inclusive of today and of the expiry date.
 *
 * Deliberately named for what it is. It is not appointments, sessions or
 * guaranteed visits — the package is a period of access, and nothing here
 * knows how many times anyone will come in.
 */
export function calendarDaysRemaining(expiryDate, today) {
  assertDate(today, 'today');
  if (!isDateOnly(expiryDate)) return null;
  if (expiryDate < today) return 0;
  return dayNumber(expiryDate) - dayNumber(today) + 1;
}

/** 'active' | 'scheduled' | 'expired', from dates alone. */
export function periodStatus({ activationDate, expiryDate, today }) {
  assertDate(today, 'today');
  if (!isDateOnly(activationDate)) return 'pending';
  if (activationDate > today) return 'scheduled';
  if (isDateOnly(expiryDate) && expiryDate < today) return 'expired';
  return 'active';
}

/**
 * Where a consecutive package should start: the day after the latest adjusted
 * expiry a customer already holds. Never overlaps by default; staff can still
 * choose a date explicitly.
 */
export function nextConsecutiveStart(existingAdjustedExpiries, earliest) {
  assertDate(earliest, 'earliest');
  const latest = existingAdjustedExpiries.filter(isDateOnly).sort().pop();
  if (!latest) return earliest;
  const dayAfter = addDays(latest, 1);
  return dayAfter > earliest ? dayAfter : earliest;
}
