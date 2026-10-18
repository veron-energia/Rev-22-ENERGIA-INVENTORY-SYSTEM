// Sorting the rows of an Excel export by one of its columns (the shared
// ExcelExport). Kept free of React so it can be tested with the Node runner.
//
// Values are compared by what they are, not by their text:
//   * numbers as numbers, so "10" comes after "9" (thousands commas allowed);
//   * dates as dates. A date written day first, as the sheets write it
//     ("12/08/2026", en-GB, with or without a time after it), is read day
//     first: 12 August, never 8 December (427: the Customers Special Export
//     sorted by Date of Birth came out scrambled). An ISO date is read as one;
//   * anything else as text, with the numbers inside it in order ("Item 2"
//     before "Item 10").
// Blanks always go to the bottom, whichever way the sort runs, so a missing
// value never buries real data at the top of the sheet.

const DAY_FIRST = /^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:,?\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$/;

/** A day-first date ("12/08/2026", "12/08/2026, 14:05:00") as a time, or null. */
export function dayFirstTime(value) {
  const m = DAY_FIRST.exec(String(value ?? '').trim());
  if (!m) return null;
  const [, d, mo, y, h = '0', mi = '0', s = '0'] = m;
  const t = Date.UTC(Number(y), Number(mo) - 1, Number(d), Number(h), Number(mi), Number(s));
  const back = new Date(t);
  // 31/02/2026 is not a date; it must not roll over into March.
  if (back.getUTCFullYear() !== Number(y) || back.getUTCMonth() !== Number(mo) - 1 || back.getUTCDate() !== Number(d)) return null;
  return t;
}

const isBlank = v => v === null || v === undefined || v === '';

function asNumber(v) {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  const s = String(v).replace(/[,\s]/g, '');
  if (s === '') return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

function asTime(v) {
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v.getTime();
  const dayFirst = dayFirstTime(v);
  if (dayFirst !== null) return dayFirst;
  // Anything else the Date parser reads (an ISO date, a timestamp, a device
  // date with AM/PM), as before.
  const t = new Date(String(v)).getTime();
  return Number.isNaN(t) ? null : t;
}

/** How two non-blank values compare, ascending. */
export function compareExportValues(a, b) {
  const an = asNumber(a), bn = asNumber(b);
  if (an !== null && bn !== null) return an - bn;
  const at = asTime(a), bt = asTime(b);
  if (at !== null && bt !== null) return at - bt;
  return String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: 'base' });
}

/**
 * The rows in the order of valueOf(row), ascending or descending, blanks last.
 * Rows that compare equal keep their order on screen. Returns a new array.
 */
export function sortExportRows(rows, valueOf, dir = 'asc') {
  const sign = dir === 'desc' ? -1 : 1;
  return (rows ?? [])
    .map((row, i) => ({ row, i, v: valueOf(row) }))
    .sort((x, y) => {
      const xb = isBlank(x.v), yb = isBlank(y.v);
      if (xb || yb) return xb === yb ? x.i - y.i : xb ? 1 : -1;
      return sign * compareExportValues(x.v, y.v) || x.i - y.i;
    })
    .map(x => x.row);
}
