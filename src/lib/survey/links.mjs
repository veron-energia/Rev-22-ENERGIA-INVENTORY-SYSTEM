// QR survey links: dates in Singapore time, and what the list calls a link.
//
// CUSTOMERS-7: the New QR Link window took the date chosen as midnight UTC,
// which is 8am in Singapore, so a link "expiring" on a day stopped working
// at 8am that day. The date chosen is now the last day the link works, to
// the end of that day in Singapore. The server (survey_link_info and
// submit_health_survey) compares expires_at with now(), so nothing else
// changes.

const SG = 'Asia/Singapore';

/** The end of a Singapore day ('YYYY-MM-DD') as an ISO instant, or null. */
export function linkExpiryFromDay(day) {
  const d = String(day ?? '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return null;
  const t = new Date(`${d}T23:59:59.999+08:00`);
  return Number.isNaN(t.getTime()) ? null : t.toISOString();
}

/** A date or time shown as dd/mm/yyyy in Singapore time ('—' when empty). */
export function sgDate(value) {
  if (!value) return '—';
  const t = new Date(value);
  if (Number.isNaN(t.getTime())) return '—';
  return t.toLocaleDateString('en-GB', { timeZone: SG });
}

/** A time shown as dd/mm/yyyy, hh:mm in Singapore time ('—' when empty). */
export function sgDateTime(value) {
  if (!value) return '—';
  const t = new Date(value);
  if (Number.isNaN(t.getTime())) return '—';
  return t.toLocaleString('en-GB', { timeZone: SG, dateStyle: 'short', timeStyle: 'short' });
}

/** A date-only value ('YYYY-MM-DD', a date of birth) as dd/mm/yyyy, never shifted by time zone. */
export function plainDate(value) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value ?? ''));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : '—';
}

/** 'expired' once past its last moment, else 'active' or 'inactive'. */
export function linkStatus(link, now = new Date()) {
  if (link?.expires_at && new Date(link.expires_at).getTime() < now.getTime()) return 'expired';
  return link?.is_active ? 'active' : 'inactive';
}
