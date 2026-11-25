/**
 * Who may change commission rates, as migration 535 decides it in the
 * database (security audit of 17 Nov 2026, finding M12; the user's decisions
 * of 24 Nov 2026). The pages use these only to show a form read-only, disable
 * a box and say why, and to stop a value the server would refuse before it is
 * sent; the database checks every change again and its message is still shown
 * when a refusal gets through (another tab, stale data).
 *
 *   1. Only an Owner changes the four affiliate commission rates (the
 *      Commissions page's Rates window). An Admin is not an Owner. Managers
 *      still see the rates.
 *   2. An invoice keeps the rates it first earned at: a rate change applies to
 *      invoices that first earn commission after it (the page says so).
 *   3. A credit package's or premium bundle's own rates (Tier 1, Tier 2, Staff
 *      commission) are none, or 0 to 100, and only an Owner sets or changes
 *      them. A Manager still edits everything else, and their save sends the
 *      three rates back as stored.
 */
import type { UserRole } from '../../types';

/** 535 (M12): the sentences the database refuses with. The role ones are code 42501. */
export const COMMISSION_RATE_MESSAGES = {
  ratesOwnerOnly: 'Only an Owner can change the commission rates.',
  ownRatesOwnerOnly: "Only an Owner can set a package's or bundle's own commission rates.",
  tier1Range: "A package's or bundle's Tier 1 rate must be between 0 and 100.",
  tier2Range: "A package's or bundle's Tier 2 rate must be between 0 and 100.",
  staffRange: "A package's or bundle's Staff commission rate must be between 0 and 100.",
} as const;

/** Shorter notes for beside a read-only form or a disabled box. */
export const COMMISSION_RATE_NOTES = {
  ownRatesReadOnly: 'Only an Owner sets these rates.',
  keptRates: 'Applies to invoices that first earn commission from now on. An invoice that has already earned keeps the rates it earned at, also when it is corrected, reconciled or paid in instalments.',
} as const;

/** 535 (M12, 24 Nov 2026) rule 1: changing the four affiliate commission rates. */
export const canChangeCommissionRates = (role?: UserRole | null): boolean => role === 'owner';

/** 535 (M12, 24 Nov 2026) rule 3: setting or changing a package's or bundle's own rates. */
export const canSetOwnCommissionRates = (role?: UserRole | null): boolean => role === 'owner';

/** A package's or bundle's own rates as the form holds them: text, '' for none. */
export type OwnRatesDraft = { tier1_rate: string; tier2_rate: string; staff_commission_rate: string };
export const OWN_RATE_KEYS = ['tier1_rate', 'tier2_rate', 'staff_commission_rate'] as const;
const RANGE_MESSAGE: Record<(typeof OWN_RATE_KEYS)[number], string> = {
  tier1_rate: COMMISSION_RATE_MESSAGES.tier1Range,
  tier2_rate: COMMISSION_RATE_MESSAGES.tier2Range,
  staff_commission_rate: COMMISSION_RATE_MESSAGES.staffRange,
};

/** The text of a stored own rate for the form: '' for none. */
export const ownRateText = (v: unknown): string => (v === null || v === undefined || v === '' ? '' : String(v));

/** What the form sends for an own rate: null for a blank box, else the number. */
export const ownRateValue = (t: string | null | undefined): number | null => {
  const s = (t ?? '').trim();
  return s === '' ? null : Number(s);
};

/** 535 (M12) rule 3: the first box outside 0 to 100 (or not a number), with the
 *  server's sentence; null when every box is blank or within 0 to 100. */
export function ownRatesError(d: OwnRatesDraft): string | null {
  for (const k of OWN_RATE_KEYS) {
    const v = ownRateValue(d[k]);
    if (v !== null && (!Number.isFinite(v) || v < 0 || v > 100)) return RANGE_MESSAGE[k];
  }
  return null;
}
