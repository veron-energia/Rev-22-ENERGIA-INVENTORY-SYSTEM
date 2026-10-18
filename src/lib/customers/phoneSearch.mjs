/**
 * A phone typed the way people write it (418, CUSTOMERS-11).
 *
 * Phones are stored as +<digits>, so "9123 4567", "+65 9123 4567" or
 * "(+65) 9123-4567" found nobody when matched as typed, and staff then made
 * a second record. The same rule as search_customers and
 * customer_survey_overview in the database:
 *   * a search made only of phone characters (digits, spaces, "+", "-",
 *     ".", brackets) with 4 digits or more also matches on its digits;
 *   * "+65" followed by 8 digits also matches the 8 digits alone (a number
 *     stored without its country code).
 * A search with letters in it is matched as typed, nothing more.
 */
const PHONE_CHARACTERS = /^[0-9+().\s-]+$/;

/** The digits to match, or null when the search is not a phone. */
export function phoneSearchDigits(term) {
  const t = String(term ?? '').trim();
  if (!t || !PHONE_CHARACTERS.test(t)) return null;
  const digits = t.replace(/[^0-9]/g, '');
  if (digits.length < 4) return null;
  const national = /^65[0-9]{8}$/.test(digits) ? digits.slice(2) : null;
  return { digits, national };
}

/** The extra PostgREST or() conditions for a phone search, e.g.
 *  ['phone.ilike.%91234567%']. Empty when the search is not a phone. */
export function phoneSearchFilters(term) {
  const p = phoneSearchDigits(term);
  if (!p) return [];
  const out = [`phone.ilike.%${p.digits}%`];
  if (p.national) out.push(`phone.ilike.%${p.national}%`);
  return out;
}
