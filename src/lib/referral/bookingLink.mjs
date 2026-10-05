// Where a new registration through an affiliate's referral link goes to book
// (392). The Owner chose, on 5 Oct 2026, to send it straight to cal.com's free
// giveaway with the person's details filled in and the referrer in the hidden
// `affiliate` question. That event type's "Calendar event name" starts with
// {affiliate}, so the appointment reads "(Jane Tan) John Lim +65…".
//
// The value carries its own trailing space because the title template has none
// between {affiliate} and {Scheduler}: a booking without a referrer keeps
// exactly the title it always had. name, email, WhatsApp-Number and
// smsReminderNumber are the questions public.ads_booking_link already fills for
// TikTok leads.
import { isValidE164 } from '../customer-phones/normalize.mjs';

export const REFERRAL_BOOKING_PAGE = 'https://cal.com/energia/free';

/** "(Jane Tan) " for a referrer label, or '' when there is nothing to print. */
export function referralBookingPrefix(label) {
  const name = String(label ?? '').replace(/[()[\]{}$]/g, '').replace(/\s+/g, ' ').trim();
  return name ? `(${name}) ` : '';
}

/** The booking page with whatever is known filled in. */
export function referralBookingUrl({ firstName, lastName, email, phone, affiliateLabel } = {}) {
  const params = [];
  const add = (key, value) => { if (value) params.push(`${key}=${encodeURIComponent(value)}`); };
  add('name', [firstName, lastName].map(s => String(s ?? '').trim()).filter(Boolean).join(' '));
  add('email', String(email ?? '').trim());
  const e164 = String(phone ?? '').trim();
  if (isValidE164(e164)) {
    add('WhatsApp-Number', e164);
    add('smsReminderNumber', e164);
  }
  add('affiliate', referralBookingPrefix(affiliateLabel));
  return params.length ? `${REFERRAL_BOOKING_PAGE}?${params.join('&')}` : REFERRAL_BOOKING_PAGE;
}
