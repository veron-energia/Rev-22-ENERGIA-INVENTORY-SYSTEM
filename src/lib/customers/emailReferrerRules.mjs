// 528 (security audit of 17 Nov 2026, M11; the user, 19 Nov 2026): who changes a customer's
// email and referrer, and the affiliate on an invoice already made. The database decides
// (update_customer, update_survey_particulars_v2, set_invoice_affiliate; and
// customer_is_affiliate_or_portal_login says which customers are affiliates or have a portal
// login); these only decide what the pages offer, so a refusal is rare and, when it comes, is
// shown in the server's own words.
//
//   * Every change of a customer's email needs a reason, as a phone change does. Staff change a
//     plain customer's; an affiliate's, or a portal login's, only an Owner or Manager changes.
//   * Staff add a missing referrer on the day the customer is made (the Singapore date); to a
//     customer made before today only an Owner or Manager adds one.
//   * Only an Owner or Manager changes the affiliate on an invoice already made. Staff choose it
//     while making the invoice.
// "An Owner or Manager" is an Owner or a Manager; the old Admin role is not one (as
// is_owner_or_manager() in the database).

const OWNER_OR_MANAGER = Object.freeze(['owner', 'manager']);

/** True for an Owner or Manager: the roles these rules let through. */
export function isOwnerOrManagerRole(role) {
  return OWNER_OR_MANAGER.includes(String(role ?? ''));
}

const tidy = v => {
  const s = v == null ? '' : String(v).trim();
  return s === '' ? null : s;
};

/** True when the email as it will be stored (trimmed, blank as none) differs. */
export function emailChanged(before, after) {
  return tidy(before) !== tidy(after);
}

const SG_YMD = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Singapore', year: 'numeric', month: '2-digit', day: '2-digit' });

/** The Singapore date (YYYY-MM-DD) of a moment, or null. */
export function sgYmd(ts) {
  const t = ts instanceof Date ? ts.getTime() : Date.parse(String(ts ?? ''));
  return Number.isFinite(t) ? SG_YMD.format(new Date(t)) : null;
}

/** True when the customer was made before today in Singapore (an unknown date counts as before). */
export function madeBeforeTodaySg(createdAt, now = new Date()) {
  const made = sgYmd(createdAt);
  return made === null || made < sgYmd(now);
}

/** True when this role may add a missing referrer to a customer made at createdAt. */
export function mayAddReferrer(role, createdAt, now = new Date()) {
  return isOwnerOrManagerRole(role) || !madeBeforeTodaySg(createdAt, now);
}

/** True when this role may change the email of a customer who is (or not) an affiliate or a portal login. */
export function mayChangeEmail(role, affiliateOrPortal) {
  return isOwnerOrManagerRole(role) || affiliateOrPortal !== true;
}

/** True when this role may change the affiliate on an invoice already made. */
export function mayChangeInvoiceAffiliate(role) {
  return isOwnerOrManagerRole(role);
}

/** What the pages say beside what they lock. */
export const EMAIL_LOCKED_HINT = 'Only an Owner or Manager can change this email: this customer is an affiliate or has a portal login.';
export const REFERRER_LOCKED_HINT = 'This customer was added before today, so only an Owner or Manager can add their referrer. Ask one to add it.';
export const INVOICE_AFFILIATE_LOCKED_HINT = 'Only an Owner or Manager can change the affiliate after the invoice is made.';
