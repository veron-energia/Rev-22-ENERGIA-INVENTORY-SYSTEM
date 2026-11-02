// What the /r/ page tells a person before they register through an affiliate's link, under the Phone field and above
// the button (484, push #2; the Owner, 1 Nov 2026). It is a notice, not consent: no tick box and no "agree". The
// affiliate who invited them sees, in My Network, their name, bookings and visits and spend, and their phone number
// only when they registered under this notice (484 records that: affiliate_referral_signup_with_notice); never their
// email.
//
// REFERRAL_NOTICE_VERSION names this exact wording, in both its forms (with the inviter's first name, and
// without). The database records a sign-up as told only for a version that 484's
// affiliate_referral_signup_with_notice lists (c_notices), so a new wording is a new version, listed by a
// migration first. The page test pins each version's wording
// (scripts/affiliate-signup/tests/referral-notice.test.mjs).

export const REFERRAL_NOTICE_VERSION = 'r-page-2026-11';

/**
 * The notice, naming the inviter by the first name public_affiliate_referral_info gives (affiliate_name),
 * trimmed; "the person who invited you" when there is none: null, blank, not text, or still loading.
 */
export function referralNotice(affiliateName) {
  const first = typeof affiliateName === 'string' ? affiliateName.trim() : '';
  const who = first ? `${first}, who invited you,` : 'the person who invited you';
  return `When you register, ${who} will be able to see your name, phone number, bookings and visits, and how much `
    + 'you spend with Energia, in their Energia affiliate account, so they can help you with your visit. '
    + 'They never see your email. If you would rather they did not see your number, tell Energia and we will hide it.';
}
