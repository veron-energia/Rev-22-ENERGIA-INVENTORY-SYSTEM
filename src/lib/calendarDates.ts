/** Calendar dates remain date-only; timestamps use an explicitly chosen zone. */
export function calendarDate(value: string | Date | null | undefined, timeZone?: string): string {
  if (!value) return '';
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const check = new Date(value + 'T00:00:00Z');
    return Number.isFinite(check.getTime()) && check.toISOString().slice(0, 10) === value ? value : '';
  }
  const date = value instanceof Date ? value : new Date(value);
  if (!Number.isFinite(date.getTime())) return '';
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
}
export function calendarDateInRange(value: string | Date | null | undefined, from: string, to: string, timeZone?: string): boolean {
  if (!from && !to) return true;
  const date = calendarDate(value, timeZone);
  return Boolean(date && (!from || date >= from) && (!to || date <= to));
}
