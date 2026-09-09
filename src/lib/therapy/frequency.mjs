// How often a customer may have one therapy service.
//
// Mirrored by migration 240 in SQL. A database test asserts the two agree,
// because one rule with two implementations drifts unless something compares
// them.
//
// Two things this deliberately does NOT do:
//
//   * It does not decide when the next appointment is. It answers "given this
//     history, is this moment allowed", and the history is passed in. There is
//     no appointment table yet, so a function that went looking for one would
//     be inventing an answer.
//   * It does not apply across services. Power Recharge does not block Foot
//     Detox: the limit is per customer AND per service, and every function here
//     takes a single service's history.
//
// Calendar rules are Singapore calendar boundaries — a day is midnight to
// midnight in Asia/Singapore, a week is Monday to Sunday, a month is the 1st to
// the last date. Hourly rules are start-time to start-time and take no notice of
// calendar boundaries at all.

/** The rule kinds a service can carry. */
export const FREQUENCY_KINDS = ['per_day', 'per_week', 'per_month', 'per_hours', 'unrestricted'];

const SGT_OFFSET_MINUTES = 8 * 60;      // Asia/Singapore has no daylight saving

function assertInstant(value, label) {
  // A number is accepted because this function's own return value is epoch
  // milliseconds, and the period helpers below are called with instants that
  // have already been through here. Rejecting it made every calendar-period
  // rule throw while the hourly one worked.
  const t = typeof value === 'number' ? value
          : value instanceof Date ? value.getTime()
          : Date.parse(String(value));
  if (!Number.isFinite(t)) throw new TypeError(`${label} must be a date or an ISO timestamp`);
  return t;
}

/**
 * The Singapore wall-clock fields of an instant.
 *
 * Singapore is a fixed +08:00 with no daylight saving, so shifting the instant
 * and reading it in UTC gives the local calendar date without a timezone
 * database — and without the class of bug where a boundary moves twice a year.
 */
function sgtParts(instant) {
  const shifted = new Date(instant + SGT_OFFSET_MINUTES * 60000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    weekday: shifted.getUTCDay(),          // 0 = Sunday
    iso: shifted.toISOString().slice(0, 10),
  };
}

/** 'YYYY-MM-DD' for the Singapore day an instant falls in. */
export function sgtDate(value) {
  return sgtParts(assertInstant(value, 'value')).iso;
}

/** The Monday-based week key, so Monday and the following Sunday share one. */
export function sgtWeekKey(value) {
  const p = sgtParts(assertInstant(value, 'value'));
  // getUTCDay() gives 0 for Sunday; shift so Monday starts the week.
  const daysSinceMonday = (p.weekday + 6) % 7;
  const monday = new Date(Date.parse(`${p.iso}T00:00:00Z`) - daysSinceMonday * 86400000);
  return monday.toISOString().slice(0, 10);
}

/** 'YYYY-MM' for the Singapore calendar month. */
export function sgtMonthKey(value) {
  const p = sgtParts(assertInstant(value, 'value'));
  return `${p.year}-${String(p.month).padStart(2, '0')}`;
}

/**
 * Describe a rule in a sentence, for the interface to show beside the
 * structured fields. Structured is what the system enforces; this is what a
 * person reads.
 */
export function describeFrequency(rule) {
  if (!rule || rule.kind === 'unrestricted') return 'No frequency limit.';
  const n = Number(rule.max_per_period ?? 1);
  const times = n === 1 ? 'once' : `${n} times`;
  switch (rule.kind) {
    case 'per_day':   return `At most ${times} per calendar day (Singapore, midnight to midnight).`;
    case 'per_week':  return `At most ${times} per calendar week (Singapore, Monday to Sunday).`;
    case 'per_month': return `At most ${times} per calendar month (Singapore, 1st to the last date).`;
    case 'per_hours': {
      const h = Number(rule.interval_hours ?? 0);
      return `At most ${times} every ${h} hour${h === 1 ? '' : 's'}, measured from the start of the previous session.`;
    }
    default: return 'Frequency rule not recognised.';
  }
}

/** A rule is only usable if it says something complete. */
export function validateFrequency(rule) {
  if (!rule || typeof rule !== 'object') return { ok: false, message: 'A frequency rule is required.' };
  if (!FREQUENCY_KINDS.includes(rule.kind)) {
    return { ok: false, message: 'Choose how often this service may be taken.' };
  }
  if (rule.kind === 'unrestricted') return { ok: true };

  const n = Number(rule.max_per_period ?? 1);
  if (!Number.isInteger(n) || n < 1 || n > 100) {
    return { ok: false, message: 'The number of times per period must be a whole number of at least 1.' };
  }
  if (rule.kind === 'per_hours') {
    const h = Number(rule.interval_hours);
    if (!Number.isFinite(h) || h <= 0 || h > 8760) {
      return { ok: false, message: 'Enter the number of hours between sessions, for example 5.' };
    }
  }
  return { ok: true };
}

/**
 * May this customer take this service at `at`, given their history of it?
 *
 * @param {object} args
 * @param {object} args.rule       the service's frequency rule
 * @param {string|Date} args.at    the proposed session start
 * @param {Array<string|Date>} args.history  previous session STARTS for this
 *        customer and THIS service only. Order does not matter.
 * @returns {{allowed: boolean, reason: string|null, nextAllowedAt: string|null,
 *            countedInPeriod: number}}
 */
export function checkFrequency({ rule, at, history = [] }) {
  const valid = validateFrequency(rule);
  if (!valid.ok) {
    // An unusable rule is not permission. Saying "allowed" here would turn a
    // configuration mistake into unlimited access.
    return { allowed: false, reason: valid.message, nextAllowedAt: null, countedInPeriod: 0 };
  }
  if (rule.kind === 'unrestricted') {
    return { allowed: true, reason: null, nextAllowedAt: null, countedInPeriod: 0 };
  }

  const when = assertInstant(at, 'at');
  const past = history
    .map(h => assertInstant(h, 'history entry'))
    .filter(t => t <= when)          // a future booking does not limit an earlier one
    .sort((a, b) => a - b);

  const max = Number(rule.max_per_period ?? 1);

  if (rule.kind === 'per_hours') {
    const hours = Number(rule.interval_hours);
    const windowMs = hours * 3600000;
    // Start to start, as the rule says — the previous session's duration is not
    // part of it.
    const inWindow = past.filter(t => when - t < windowMs);
    if (inWindow.length < max) {
      return { allowed: true, reason: null, nextAllowedAt: null, countedInPeriod: inWindow.length };
    }
    const blocking = inWindow[inWindow.length - max];
    return {
      allowed: false,
      reason: `Only ${max} session${max === 1 ? '' : 's'} every ${hours} hours. `
            + `The last one started at ${new Date(blocking).toISOString()}.`,
      nextAllowedAt: new Date(blocking + windowMs).toISOString(),
      countedInPeriod: inWindow.length,
    };
  }

  const keyOf = rule.kind === 'per_day' ? sgtDate
              : rule.kind === 'per_week' ? sgtWeekKey
              : sgtMonthKey;
  const periodKey = keyOf(when);
  const inPeriod = past.filter(t => keyOf(t) === periodKey);

  if (inPeriod.length < max) {
    return { allowed: true, reason: null, nextAllowedAt: null, countedInPeriod: inPeriod.length };
  }
  const label = rule.kind === 'per_day' ? 'day' : rule.kind === 'per_week' ? 'week' : 'month';
  return {
    allowed: false,
    reason: `Already taken ${inPeriod.length} time${inPeriod.length === 1 ? '' : 's'} this calendar ${label} `
          + `(Singapore), and the limit is ${max}.`,
    // The next period begins the moment this one ends; the caller can compute
    // the exact instant from the calendar, and stating a wrong one here would be
    // worse than stating none.
    nextAllowedAt: null,
    countedInPeriod: inPeriod.length,
  };
}

/**
 * The same question for several services at once — the shape a booking screen
 * will want.
 *
 * History is keyed by service id, so one service's sessions can never restrict
 * another's. That separation is the point: two different therapies on one day
 * is normal.
 */
export function checkServices({ services, at, historyByService = {} }) {
  const out = {};
  for (const service of services) {
    out[service.id] = checkFrequency({
      rule: service.frequency_rule,
      at,
      history: historyByService[service.id] ?? [],
    });
  }
  return out;
}
