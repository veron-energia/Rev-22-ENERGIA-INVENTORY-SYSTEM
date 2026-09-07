export interface PhoneInspection { normalized: string | null; country: string | null; status: string; reason: string; candidates: string[]; }
export function inspectPhone(original: string | null | undefined, countryHint?: string | null): PhoneInspection;
export function isValidE164(value: string): boolean;
export function normalizeName(value: string | null | undefined): string;
export function matchCustomers(rows: { phone: string; full_name: string; deleted_at?: string | null }[], phone: string, name: string): { status: string; matches: object[] };
export const PHONE_LIMIT_MESSAGE: string;
export function phoneErrorMessage(message: string): string;
