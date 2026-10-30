// A customer's cal.com booking on the Downline and on the affiliate portal's
// My Network (480, the Owner, 29 Oct 2026). The database decides which
// booking a row shows and its state (calcom_customer_bookings: the next one
// from today in Singapore, else the last one; 'came' when that day has a
// visit by the visit rule or a settled purchase at the Adelphi centre, else
// 'miss'; 'none'); these helpers only word it, so both screens and the
// export say the same thing.

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
// Numbers only: words from Intl differ between engines ("Sep" or "Sept").
const SG_PARTS = new Intl.DateTimeFormat('en-US', {
  timeZone: 'Asia/Singapore', year: 'numeric', month: 'numeric', day: 'numeric',
  hour: 'numeric', minute: 'numeric', hourCycle: 'h23',
});

/** A booking's start in Singapore as its day ("Sat 31 Oct 2026") and time ("2:00 pm"); null when it is no moment. */
export function bookingParts(ts) {
  const t = Date.parse(String(ts ?? ''));
  if (!Number.isFinite(t)) return null;
  const parts = SG_PARTS.formatToParts(new Date(t));
  const n = type => Number(parts.find(p => p.type === type)?.value);
  const y = n('year'), m = n('month'), d = n('day'), h = n('hour') % 24, min = n('minute');
  // The weekday of that Singapore date (the calendar's, whatever the device's zone).
  const wd = WEEKDAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
  return { day: `${wd} ${d} ${MONTHS[m - 1]} ${y}`, time: `${h % 12 || 12}:${String(min).padStart(2, '0')} ${h < 12 ? 'am' : 'pm'}` };
}

/** A booking's start as Singapore shows it: "Sat 31 Oct 2026, 2:00 pm"; '' when it is no moment. */
export function bookingWhen(ts) {
  const p = bookingParts(ts);
  return p ? `${p.day}, ${p.time}` : '';
}

/** The export's word for each state. */
export const BOOKING_STATUS_LABELS = { upcoming: 'Upcoming', came: 'Came', miss: 'Miss', none: 'No booking' };

/**
 * What a row shows: its state ('upcoming', 'came', 'miss', 'none', or
 * 'unknown' when the row has no booking_state: a database before 480), the
 * date and time ('' for none; also as day and time, so a narrow column can
 * put the time under the day), and the export's status word ('' unknown).
 */
export function bookingView(row) {
  const state = row && Object.prototype.hasOwnProperty.call(BOOKING_STATUS_LABELS, row.booking_state) ? row.booking_state : 'unknown';
  const parts = state === 'unknown' || state === 'none' ? null : bookingParts(row.booking_at);
  return { state, text: parts ? `${parts.day}, ${parts.time}` : '', day: parts?.day ?? '', time: parts?.time ?? '',
           label: BOOKING_STATUS_LABELS[state] ?? '' };
}
