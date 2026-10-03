// The Dashboard's FOC card: the FOC value given in the last 30 days, with its
// biggest stores and most-used reasons, all read from the same rows of
// report_foc_lines(p_from, p_to, p_store_id) so the parts add up to the total.
//
// Each row carries store_id (not a name), foc_value (the value given free) and
// foc_reason as foc_reason_resolve wrote it: the reason's label, then " — "
// and the note when there is one, or a free-text reason on its own.

export const FOC_SNAPSHOT_DAYS = 30;

/** The first day of the window ending on `today` (YYYY-MM-DD), `days` days long, today included. */
export function focWindowStart(today, days = FOC_SNAPSHOT_DAYS) {
  const d = new Date(`${today}T00:00:00Z`);
  if (!Number.isFinite(d.getTime())) return null;
  d.setUTCDate(d.getUTCDate() - (days - 1));
  return d.toISOString().slice(0, 10);
}

/** The reason's label, without the note staff added after it. */
export function focReasonLabel(reason) {
  const text = String(reason ?? '').trim();
  if (!text) return 'No reason';
  const cut = text.indexOf(' — ');
  return cut > 0 ? text.slice(0, cut) : text;
}

const cents = n => Math.round(Number(n || 0) * 100);

/**
 * @param lines rows of report_foc_lines
 * @param storeNames store id -> name (a Map or a plain object)
 * @param top how many stores and reasons to list
 */
export function focSnapshot(lines, storeNames, top = 2) {
  const nameOf = id => (storeNames instanceof Map ? storeNames.get(id) : storeNames?.[id]) ?? 'Other store';
  const byStore = new Map();
  const byReason = new Map();
  let total = 0;
  for (const l of lines ?? []) {
    const v = cents(l.foc_value);
    total += v;
    const store = nameOf(l.store_id);
    byStore.set(store, (byStore.get(store) ?? 0) + v);
    const label = focReasonLabel(l.foc_reason);
    byReason.set(label, (byReason.get(label) ?? 0) + 1);
  }
  const stores = [...byStore].map(([name, v]) => ({ name, value: v / 100 }))
    .sort((a, b) => b.value - a.value || a.name.localeCompare(b.name)).slice(0, top);
  const reasons = [...byReason].map(([label, count]) => ({ label, count }))
    .sort((a, b) => b.count - a.count || a.label.localeCompare(b.label)).slice(0, top);
  return { total: total / 100, lineCount: (lines ?? []).length, stores, reasons };
}
