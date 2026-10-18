/** The digits to match, or null when the search is not a phone (418). */
export function phoneSearchDigits(term: string | null | undefined): { digits: string; national: string | null } | null;
/** The extra PostgREST or() conditions for a phone search; empty when it is not a phone. */
export function phoneSearchFilters(term: string | null | undefined): string[];
