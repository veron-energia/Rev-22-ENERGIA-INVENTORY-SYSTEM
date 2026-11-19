// 529 (security audit of 17 Nov 2026, M3; the user, 19 Nov 2026: "Refuse odd input"): the name
// and email the /r/ page sends. The database decides (affiliate_referral_signup refuses them with
// these very messages, and records the try); the page checks the same rule before it calls, so
// a person is told what to fix at once. This only stops what the database would refuse.
//
//   * The name is the first and last name together, as the database builds it: first + ' ' +
//     last, with spaces trimmed from both ends (btrim). At most 100 characters (counted as the
//     database counts them, by code point); no web address ('://' or 'www.', in any case); no '<',
//     '>' or control characters (U+0000-U+001F, U+007F-U+009F). Apostrophes, hyphens, digits and
//     every script (Chinese, Burmese, ...) are fine.
//   * The email may be left out (blank or only spaces). One typed, with spaces trimmed from both
//     ends, is at most 254 characters and looks like name@domain.tld: one '@', something before
//     it, a domain of dot-separated parts after it, the last at least 2 characters; no spaces,
//     '<', '>' or control characters anywhere.
//
// The messages are the database's, word for word (the node test compares them with 529's text).

export const NAME_MAX = 100;
export const EMAIL_MAX = 254;

export const NAME_TOO_LONG = 'Please shorten your name: your first and last name together can be at most 100 characters.';
export const NAME_HAS_WEB_ADDRESS = 'Please enter just your name, without a web address.';
export const NAME_HAS_ODD_CHARACTERS = 'Please enter your name without the characters < and > or other special characters.';
export const EMAIL_TOO_LONG = 'Please enter an email address of at most 254 characters, or leave the email blank.';
export const EMAIL_NOT_AN_EMAIL = 'Please check your email address: it should look like name@example.com. Or leave the email blank.';

const ODD = /[<>\u0000-\u001f\u007f-\u009f]/u;
const PART = '[^@ .<>\\u0000-\\u001f\\u007f-\\u009f]';
const EMAIL = new RegExp(`^[^@ <>\\u0000-\\u001f\\u007f-\\u009f]+@${PART}+(\\.${PART}+)*\\.${PART}{2,}$`, 'u');

const text = v => (v == null ? '' : String(v));
/** Spaces (only U+0020) trimmed from both ends, as the database's btrim does. */
const trimSpaces = s => s.replace(/^ +| +$/g, '');
const length = s => [...s].length;

/** The name as the database builds it: first + ' ' + last, spaces trimmed from both ends. */
export function signupName(first, last) {
  return trimSpaces(`${text(first)} ${text(last)}`);
}

/** What is wrong with the name, as the database says it, or null. A blank name is the page's own check. */
export function nameProblem(first, last) {
  const name = signupName(first, last);
  if (length(name) > NAME_MAX) return NAME_TOO_LONG;
  if (name.includes('://') || name.toLowerCase().includes('www.')) return NAME_HAS_WEB_ADDRESS;
  if (ODD.test(name)) return NAME_HAS_ODD_CHARACTERS;
  return null;
}

/** What is wrong with the email, as the database says it, or null (a blank email is fine). */
export function emailProblem(email) {
  const e = trimSpaces(text(email));
  if (e === '') return null;
  if (length(e) > EMAIL_MAX) return EMAIL_TOO_LONG;
  if (!EMAIL.test(e.toLowerCase())) return EMAIL_NOT_AN_EMAIL;
  return null;
}

/** The first thing to fix, in the database's order (the name, then the email), or null. */
export function signupInputProblem(first, last, email) {
  return nameProblem(first, last) ?? emailProblem(email);
}
