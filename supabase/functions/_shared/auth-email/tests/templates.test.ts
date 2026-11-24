// Templates: escaping, header safety, and what the notification deliberately
// does not contain.

import { assert, assertEquals, assertFalse, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  SUBJECTS, escapeHtml, headerSafe, formatWhen,
  renderVerifySignup, renderVerifyCode, renderPasswordRecovery, renderPasswordChanged, renderUserInvitation,
  renderDetailsCode, renderDetailsChanged,
} from '../templates.ts';
import { ACTION_LINK, VERIFY_CODE } from './support.ts';

Deno.test('subjects are exactly the agreed wording', () => {
  assertEquals(SUBJECTS.verify_signup, 'Verify Your Energia Affiliate Account');
  assertEquals(SUBJECTS.verify_code, 'Your Energia Verification Code');
  assertEquals(SUBJECTS.password_recovery, 'Reset Your Energia Password');
  assertEquals(SUBJECTS.password_changed, 'Your Energia Password Was Changed');
});

Deno.test('a name carrying markup cannot become markup', () => {
  // The invitation is the one email that names a person: the name staff typed.
  const email = renderUserInvitation('<img src=x onerror="alert(1)">', ACTION_LINK);
  assertFalse(email.html.includes('<img'), 'raw tag must not survive');
  assertFalse(email.html.includes('onerror="'), 'raw attribute must not survive');
  assertStringIncludes(email.html, '&lt;img');
  assertEquals(escapeHtml(`<&>"'`), '&lt;&amp;&gt;&quot;&#39;');
});

Deno.test('a name carrying a newline cannot inject a header', () => {
  assertEquals(headerSafe('Ada\r\nBcc: victim@example.com'), 'Ada Bcc: victim@example.com');
  const email = renderUserInvitation('Ada\r\nBcc: victim@example.com', ACTION_LINK);
  assertFalse(email.subject.includes('\n'));
  assertFalse(email.subject.includes('\r'));
  // The greeting is one line: nothing in it can start a new header downstream.
  const greeting = email.text.split('\n')[0];
  assertFalse(greeting.includes('\r'));
});

Deno.test('both emails carry the action link in HTML and plain text', () => {
  for (const email of [renderVerifySignup('Ada', ACTION_LINK), renderPasswordRecovery('Ada', ACTION_LINK)]) {
    assertStringIncludes(email.html, escapeHtml(ACTION_LINK));
    assertStringIncludes(email.text, ACTION_LINK);
    assert(email.text.length > 80, 'plain-text alternative must be real text');
    assertStringIncludes(email.html, 'Rev 22 Global Energia');
  }
});

Deno.test('the copy-paste fallback link is escaped once, not twice', () => {
  // The href can be wrong-looking and still work; the visible line cannot. It is
  // what somebody copies when the button fails, so a stray &amp; in the middle
  // of it hands them a broken URL at exactly the wrong moment.
  for (const email of [renderVerifySignup('Ada', ACTION_LINK), renderPasswordRecovery('Ada', ACTION_LINK)]) {
    assertFalse(email.html.includes('&amp;amp;'), 'the link must not be double-escaped');
    // Strip the tags and un-escape once: what is left must be the link itself.
    const visible = email.html
      .replace(/<[^>]*>/g, '')
      .replace(/&amp;/g, '&').replace(/&#39;/g, "'").replace(/&quot;/g, '"');
    assertStringIncludes(visible, ACTION_LINK);
    assertStringIncludes(email.text, ACTION_LINK);
  }
});

Deno.test('templates are inline-styled and phone-width', () => {
  const email = renderVerifySignup('Ada', ACTION_LINK);
  assertFalse(email.html.includes('<style'), 'a <style> block is stripped by too many clients');
  assertStringIncludes(email.html, 'style="');
  assertStringIncludes(email.html, 'max-width:560px');
});

Deno.test('the password-changed notice carries no link and no token', () => {
  const email = renderPasswordChanged('Ada', '2026-09-08T04:05:06.000Z', 'info@rev22.com.sg');
  assertFalse(email.html.includes('/auth/v1/verify'), 'nothing to click means nothing to phish');
  assertFalse(email.html.includes('token'));
  assertFalse(email.text.includes('http://'));
  // The only link is a mailto for reporting it, which is the point of the email.
  assertStringIncludes(email.html, 'mailto:info@rev22.com.sg');
  assertStringIncludes(email.text, '2026-09-08 04:05 UTC');
});

Deno.test('an unreadable timestamp degrades to wording, not to "Invalid Date"', () => {
  assertEquals(formatWhen('not-a-date'), 'recently');
  assertStringIncludes(renderPasswordChanged('Ada', 'nonsense', 'a@b.co').text, 'recently');
});

Deno.test('a missing name produces a greeting, not "Hi undefined"', () => {
  assertStringIncludes(renderVerifySignup('', ACTION_LINK).text, 'Hi,');
  assertStringIncludes(renderPasswordRecovery('   ', ACTION_LINK).text, 'Hi,');
});

Deno.test('M6: the Account page verification email carries the code and no link that verifies', () => {
  const email = renderVerifyCode(VERIFY_CODE);
  assertEquals(email.subject, 'Your Energia Verification Code');
  for (const part of [email.html, email.text]) {
    assertStringIncludes(part, VERIFY_CODE);
    assertStringIncludes(part, 'Enter this code on the Account page within 15 minutes');
    assertStringIncludes(part, 'Energia staff will never ask you for this code.');
    assertStringIncludes(part, 'If you did not create an Energia affiliate account, ignore this email.');
    assertFalse(/https?:\/\//.test(part), 'no link in the code email');
    assertFalse(part.includes('/auth/v1/verify'));
  }
  assertFalse(email.html.includes('<a '), 'nothing to click');
});

Deno.test('M6: only six digits are printed as a code, anything else is dropped', () => {
  const email = renderVerifyCode('<b>1</b>');
  assertFalse(email.html.includes('<b>1</b>'));
  assertFalse(email.text.includes('<b>'));
});

Deno.test('492: the emails an affiliate gets speak as Energia, never "we", "our" or "us"', () => {
  const emails = {
    verify_signup: renderVerifySignup('Ada', ACTION_LINK), verify_code: renderVerifyCode(VERIFY_CODE),
    password_recovery: renderPasswordRecovery('Ada', ACTION_LINK),
    password_changed: renderPasswordChanged('Ada', '2026-11-03T04:00:00Z', 'info@example.com'),
    details_code: renderDetailsCode('482913', 'current'),
    details_changed: renderDetailsChanged({ phone: '+61255500101' }, '2026-11-03T04:00:00Z', 'info@example.com'),
  };
  for (const [name, email] of Object.entries(emails)) {
    for (const part of [email.html.replace(/<[^>]+>/g, ' '), email.text]) {
      assertFalse(/\b(we|our|ours|us)\b/i.test(part), `${name}: ${part}`);
    }
  }
  assertStringIncludes(emails.password_recovery.text, 'Energia received a request to reset the password for your account.');
  for (const name of ['password_changed', 'details_changed'] as const) {
    assertStringIncludes(emails[name].text, 'If it was not you, please contact Energia straight away at info@example.com.');
    assertStringIncludes(emails[name].html, 'please contact Energia straight away');
  }
});

Deno.test('M6: no email but an invitation carries a typed name: the greeting is "Hi,"', () => {
  const typed = 'Mallory Typedname';
  const emails = [
    renderVerifySignup(typed, ACTION_LINK), renderPasswordRecovery(typed, ACTION_LINK),
    renderPasswordChanged(typed, '2026-11-03T04:00:00Z', 'info@example.com'),
    renderVerifyCode(VERIFY_CODE), renderDetailsCode('482913', 'current'),
    renderDetailsChanged({ phone: '+61491570101' }, '2026-11-03T04:00:00Z', 'info@example.com'),
  ];
  for (const email of emails) {
    assertFalse(email.html.includes(typed) || email.text.includes(typed), email.subject);
    assertEquals(email.text.split('\n')[0], 'Hi,', email.subject);
    assertStringIncludes(email.html, 'Hi,</p>');
  }
  // The invitation names the person staff typed on Users & Roles.
  assertStringIncludes(renderUserInvitation(typed, ACTION_LINK).text, `Hi ${typed},`);
});
