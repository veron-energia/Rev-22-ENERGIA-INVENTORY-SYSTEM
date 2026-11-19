/** The longest name (first and last together, in characters) and email the /r/ page accepts (529). */
export const NAME_MAX: number;
export const EMAIL_MAX: number;
/** The database's messages (529), word for word. */
export const NAME_TOO_LONG: string;
export const NAME_HAS_WEB_ADDRESS: string;
export const NAME_HAS_ODD_CHARACTERS: string;
export const EMAIL_TOO_LONG: string;
export const EMAIL_NOT_AN_EMAIL: string;
/** The name as the database builds it: first + ' ' + last, spaces trimmed from both ends. */
export function signupName(first: unknown, last: unknown): string;
/** What is wrong with the name, as the database says it, or null. */
export function nameProblem(first: unknown, last: unknown): string | null;
/** What is wrong with the email, as the database says it, or null (a blank email is fine). */
export function emailProblem(email: unknown): string | null;
/** The first thing to fix (the name, then the email), or null. */
export function signupInputProblem(first: unknown, last: unknown, email: unknown): string | null;
