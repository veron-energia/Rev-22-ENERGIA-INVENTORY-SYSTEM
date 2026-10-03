export const FOC_SNAPSHOT_DAYS: number;
export function focWindowStart(today: string, days?: number): string | null;
export function focReasonLabel(reason: string | null | undefined): string;
/** A row of report_foc_lines, as far as the Dashboard reads it. */
export interface FocLine { store_id?: string | null; foc_value?: number | string | null; foc_reason?: string | null }
export interface FocSnapshot {
  total: number;
  lineCount: number;
  stores: { name: string; value: number }[];
  reasons: { label: string; count: number }[];
}
export function focSnapshot(lines: readonly FocLine[] | null | undefined,
  storeNames: Map<string, string> | Record<string, string> | null | undefined, top?: number): FocSnapshot;
