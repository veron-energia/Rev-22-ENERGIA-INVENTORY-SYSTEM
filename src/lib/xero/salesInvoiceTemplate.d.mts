export const XERO_SALES_INVOICE_HEADERS: string[];
export const XERO_MANDATORY_HEADERS: string[];
export function csvCell(value: unknown): string;
export function toXeroCsv(rows: Record<string, unknown>[], headers?: string[]): string;
export function findMissingMandatory(
  rows: Record<string, unknown>[],
  headers?: string[],
): { row: number; field: string }[];
export function xeroCsvFilename(scope: string, from: string, to: string): string;
