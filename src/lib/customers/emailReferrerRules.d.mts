/** True for an Owner or Manager (not the old Admin role), as is_owner_or_manager() (528). */
export function isOwnerOrManagerRole(role: string | null | undefined): boolean;
/** True when the email as it will be stored (trimmed, blank as none) differs (528). */
export function emailChanged(before: string | null | undefined, after: string | null | undefined): boolean;
/** The Singapore date (YYYY-MM-DD) of a moment, or null. */
export function sgYmd(ts: string | Date | null | undefined): string | null;
/** True when the customer was made before today in Singapore (an unknown date counts as before). */
export function madeBeforeTodaySg(createdAt: string | Date | null | undefined, now?: Date): boolean;
/** True when this role may add a missing referrer to a customer made at createdAt (528). */
export function mayAddReferrer(role: string | null | undefined, createdAt: string | Date | null | undefined, now?: Date): boolean;
/** True when this role may change the email of a customer who is (or not) an affiliate or a portal login (528). */
export function mayChangeEmail(role: string | null | undefined, affiliateOrPortal: boolean | null | undefined): boolean;
/** True when this role may change the affiliate on an invoice already made (528). */
export function mayChangeInvoiceAffiliate(role: string | null | undefined): boolean;
export const EMAIL_LOCKED_HINT: string;
export const REFERRER_LOCKED_HINT: string;
export const INVOICE_AFFILIATE_LOCKED_HINT: string;
