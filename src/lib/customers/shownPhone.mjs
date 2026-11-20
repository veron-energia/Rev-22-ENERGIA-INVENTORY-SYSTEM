/**
 * The phone to show beside a customer's name (the user, 20 Nov 2026: the
 * Invoices list and the invoice show it), or null when there is none to show.
 *
 * A customer's phone is required and unique, so customers brought over from
 * the old system without a usable number carry a placeholder instead, such
 * as "LEGACY-NO-PHONE-CUST-123456", "LEGACY-DUP-PHONE-CUST-…" or
 * "LEGACY-INVALID-PHONE-CUST-…". Those are not numbers anyone can call, so
 * they are not shown; nor are the "no phone" forms sendDoc's whatsappNumber
 * already treats as missing. A real number is shown as stored.
 */
const PLACEHOLDER = /^(LEGACY[- ]|NO[- ]?PHONE\b|N\/?A$|[-—]+$)/i;

/** The stored phone, trimmed, or null when it is missing or a placeholder. */
export function shownPhone(raw) {
  const s = String(raw ?? '').trim();
  if (!s || PLACEHOLDER.test(s)) return null;
  return s;
}
