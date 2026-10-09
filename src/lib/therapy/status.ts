// A therapy entitlement's status by its dates (410), as the page shows it.
//
// The stored status is refreshed every night just after midnight in Singapore
// (cron job 'therapy-status-refresh'), and every check on the server reads
// the dates themselves (purchased_therapy_status_on). The page does the same,
// so a unit whose start date has come is never offered Claim, Reschedule or
// Refund as if it had not started, even before that night's refresh.
// Dates are 'YYYY-MM-DD' Singapore calendar days, compared as strings.

export interface PurchasedDates {
  status: string;
  activation_date?: string | null;
  expiry_date?: string | null;
  activation_deadline?: string | null;
}

/** Mirrors public.purchased_therapy_status_on(status, activation, expiry, deadline, today). */
export function purchasedStatusOn(e: PurchasedDates, today: string): string {
  const act = e.activation_date || null, exp = e.expiry_date || null, deadline = e.activation_deadline || null;
  if (e.status === 'scheduled' && act && act <= today) return exp && exp < today ? 'expired' : 'active';
  if (e.status === 'active' && exp && exp < today) return 'expired';
  if ((e.status === 'pending_activation' || e.status === 'scheduled') && !act && deadline && deadline < today) return 'expired';
  return e.status;
}

export interface LegacyDates { status: string; activation_date?: string | null; expiry_date?: string | null }

/** Mirrors public.refresh_legacy_therapy_statuses(): a start reached is
 *  active, an expiry passed is expired. Unclaimed entitlements keep their
 *  status (the page says when their deadline has passed). */
export function legacyStatusOn(e: LegacyDates, today: string): string {
  const act = e.activation_date || null, exp = e.expiry_date || null;
  let st = e.status;
  if (st === 'scheduled' && act && act <= today) st = 'active';
  if ((st === 'active' || st === 'scheduled') && exp && exp < today) st = 'expired';
  return st;
}
