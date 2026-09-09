export type FrequencyKind = 'per_day' | 'per_week' | 'per_month' | 'per_hours' | 'unrestricted';
export interface FrequencyRule { kind: FrequencyKind; max_per_period?: number; interval_hours?: number; }
export interface FrequencyCheck {
  allowed: boolean; reason: string | null; nextAllowedAt: string | null; countedInPeriod: number;
}
export const FREQUENCY_KINDS: FrequencyKind[];
export function sgtDate(value: string | number | Date): string;
export function sgtWeekKey(value: string | number | Date): string;
export function sgtMonthKey(value: string | number | Date): string;
export function describeFrequency(rule: FrequencyRule | null | undefined): string;
export function validateFrequency(rule: unknown): { ok: true } | { ok: false; message: string };
export function checkFrequency(args: { rule: FrequencyRule; at: string | number | Date; history?: (string | number | Date)[] }): FrequencyCheck;
export function checkServices(args: {
  services: { id: string; frequency_rule: FrequencyRule }[];
  at: string | number | Date;
  historyByService?: Record<string, (string | number | Date)[]>;
}): Record<string, FrequencyCheck>;
