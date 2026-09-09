export const EXPIRY_IS_INCLUSIVE: true;
export interface ClosureDate { date: string; kind?: string; name?: string; country?: string | null; [k: string]: unknown; }
export interface AppliedClosure { date: string; sources: ClosureDate[]; }
export interface AdjustedExpiry {
  baseExpiry: string | null; adjustedExpiry: string | null; addedDays: number;
  appliedDates: AppliedClosure[]; ignoredSundays: AppliedClosure[]; iterations: number;
}
export function isDateOnly(s: unknown): s is string;
export function addDays(date: string, n: number): string;
export function dayOfWeek(date: string): number;
export function isSunday(date: string): boolean;
export function baseExpiry(activationDate: string, months: number): string | null;
export function isEligibleClosureDate(date: string): boolean;
export function adjustedExpiry(args: { activationDate: string; months: number; closures?: (ClosureDate | string)[]; convention?: 'legacy' | 'purchased' }): AdjustedExpiry;
export function calendarDaysRemaining(expiryDate: string | null, today: string): number | null;
export function periodStatus(args: { activationDate: string | null; expiryDate: string | null; today: string }): 'pending' | 'scheduled' | 'active' | 'expired';
export function nextConsecutiveStart(existingAdjustedExpiries: (string | null)[], earliest: string): string;
export function membershipBaseExpiry(activationDate: string, months: number): string | null;
export function baseExpiryFor(convention: 'legacy' | 'purchased', activationDate: string, months: number): string | null;
