export function dayFirstTime(value: unknown): number | null;
export function compareExportValues(a: unknown, b: unknown): number;
export function sortExportRows<T>(
  rows: T[],
  valueOf: (row: T) => string | number | Date | null | undefined,
  dir?: 'asc' | 'desc',
): T[];
