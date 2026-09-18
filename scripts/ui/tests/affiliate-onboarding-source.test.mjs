/**
 * Affiliate onboarding no longer depends on the browser remembering the form.
 *
 * Source assertions for the client side of 333: the verify page reads the
 * account's own details before this browser's copy, treats DETAILS_REQUIRED
 * as "ask", and the portal guard offers a retry on a failed lookup instead of
 * sending an existing affiliate to the details form. And the signup QR is no
 * longer hidden from staff.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const verify = read('src/pages/AffiliateVerifyPage.tsx');
const app = read('src/App.tsx');
const affiliates = read('src/pages/AffiliatesPage.tsx');

test('the verify page takes the details from the account before the browser', () => {
  const meta = verify.indexOf('user_metadata');
  const local = verify.indexOf("localStorage.getItem(ONBOARDING_KEY)");
  assert.ok(meta > 0 && local > meta, 'user_metadata must be consulted before localStorage');
  assert.match(verify, /pick\(meta\.first_name, saved\?\.first\)/, 'the account copy takes precedence');
});

test('only typed details are pre-checked in the browser; the server decides the rest', () => {
  assert.match(verify, /if \(typed && \(!first\.trim\(\) \|\| !isPhoneValid\(phone\)\)\)/,
    'an automatic attempt must reach the server even with partial details');
  assert.match(verify, /DETAILS_REQUIRED/, 'the server refusal must map to the details form');
  assert.match(verify, /complete\(f\.first, f\.last, f\.phone, true\)/, 'the manual form is the typed path');
});

test('a failed account lookup offers a retry, not the details form', () => {
  const guard = app.slice(app.indexOf('const AffiliateProtected'), app.indexOf('const AppRoutes'));
  assert.match(guard, /actorType !== 'affiliate' && error/, 'the error case must be handled first');
  assert.match(guard, /Try again/, 'a retry must be offered');
  assert.ok(guard.indexOf('&& error') < guard.indexOf('<Navigate to="/affiliate/verify"'), 'the retry must come before the redirect');
});

test('staff can show the affiliate signup QR', () => {
  assert.doesNotMatch(affiliates, /canManage && <button[^>]*>[^<]*<QrCode[^>]*\/> Affiliate Signup QR/, 'the signup QR is still gated');
  assert.match(affiliates, /Affiliate Signup QR<\/button>/, 'the button is still there');
});
