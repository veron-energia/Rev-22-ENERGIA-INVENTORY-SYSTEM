export const REFERRAL_BOOKING_PAGE: string;
export function referralBookingPrefix(label: string | null | undefined): string;
export interface ReferralBooking {
  firstName?: string | null;
  lastName?: string | null;
  email?: string | null;
  /** E.164, as PhoneInput hands it back. */
  phone?: string | null;
  /** affiliate_label from affiliate_referral_signup's reply. */
  affiliateLabel?: string | null;
}
export function referralBookingUrl(booking?: ReferralBooking): string;
/** 549: cal.com's page to move a booking (by its cal.com uid); null without one. */
export function calcomRescheduleUrl(uid: string | null | undefined): string | null;
/** 549: cal.com's page to cancel a booking (by its cal.com uid); null without one. */
export function calcomCancelUrl(uid: string | null | undefined): string | null;
