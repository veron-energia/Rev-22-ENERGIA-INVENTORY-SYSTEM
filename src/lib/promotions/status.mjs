// Where a promotion stands on a given day (SALES-EXTRAS-9, 9 Oct 2026).
//
// The server sells a promotion only while it is switched on, from its start
// date to its end date (Singapore dates, both days included: sg_today() in
// exchange_bundle_quote and, after B02, at the till). The pages say the same:
// the Promotions list shows Ended and Not started instead of a bare "Active",
// and the pickers offer only what can be sold today.
//
// Dates are 'YYYY-MM-DD' strings, compared as text; `today` is the Singapore
// date (singaporeToday()).

/** 'Active', 'Ended', 'Not started' or 'Inactive' (switched off). */
export function promotionStatus(p, today) {
  if (!p || p.is_active === false || p.deleted_at) return 'Inactive';
  const day = String(today ?? '').slice(0, 10);
  const start = p.start_date ? String(p.start_date).slice(0, 10) : '';
  const end = p.end_date ? String(p.end_date).slice(0, 10) : '';
  if (start && day && day < start) return 'Not started';
  if (end && day && day > end) return 'Ended';
  return 'Active';
}

/** True when the promotion can be sold today. */
export function promotionOnSale(p, today) {
  return promotionStatus(p, today) === 'Active';
}

/** The badge class for a status. */
export function promotionStatusBadge(status) {
  switch (status) {
    case 'Active': return 'badge-success';
    case 'Not started': return 'badge-accent';
    case 'Ended': return 'badge-danger';
    default: return 'badge-muted';
  }
}

/** A date-only 'YYYY-MM-DD' as 'DD/MM/YYYY', without passing through a time zone. */
export function displayDateOnly(value) {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value ?? ''));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : '';
}
