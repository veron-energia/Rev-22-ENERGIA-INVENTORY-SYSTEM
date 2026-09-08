export interface Ymd { y: number; m: number; d: number }
export interface Period { start: Ymd; end: Ymd }
export function lastWednesday(year: number, month: number): Ymd;
export function settlementPeriod(year: number, month: number): Period;
export function toIsoDate(ymd: Ymd): string;
export function periodInstantRange(year: number, month: number): { startInclusive: Date; endExclusive: Date };
export function periodLabel(year: number, month: number): string;
export function settledDateSgt(value: unknown): string | null;
export function isInPeriod(isoDate: string | null, year: number, month: number): boolean;
export function reportingMonthFor(isoDate: string | null): { year: number; month: number } | null;
