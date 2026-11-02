/** The version that names the /r/ notice's wording (both forms); 484's affiliate_referral_signup_with_notice lists it. */
export const REFERRAL_NOTICE_VERSION: string;
/** The notice, naming the inviter by their first name (trimmed), or "the person who invited you" when there is none. */
export function referralNotice(affiliateName?: unknown): string;
