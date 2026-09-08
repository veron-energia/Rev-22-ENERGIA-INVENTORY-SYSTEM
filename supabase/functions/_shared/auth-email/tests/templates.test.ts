// Templates: escaping, header safety, and what the notification deliberately
// does not contain.

import { assert, assertEquals, assertFalse, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  SUBJECTS, escapeHtml, headerSafe, formatWhen,
  renderVerifySignup, renderPasswordRecovery, renderPasswordChanged,
} from '../templates.ts';
import { ACTION_LINK } from './support.ts';

Deno.test('subjects are exactly the agreed wording', () => {
  assertEquals(SUBJECTS.verify_signup, 'Verify Your Energia Affiliate Account');
  assertEquals(SUBJECTS.password_recovery, 'Reset Your Energia Password');
  assertEquals(SUBJECTS.password_changed, 'Your Energia Password Was Changed');
});

Deno.test('a name carrying markup cannot become markup', () => {
  const email = renderVerifySignup('<img src=x onerror="alert(1)">', ACTION_LINK);
  assertFalse(email.html.includes('<img'), 'raw tag must not survive');
  assertFalse(email.html.includes('onerror="'), 'raw attribute must not survive');
  assertStringIncludes(email.html, '&lt;img');
  assertEquals(escapeHtml(`<&>"'`), '&lt;&amp;&gt;&quot;&#39;');
});

Deno.test('a name carrying a newline cannot inject a header', () => {
  assertEquals(headerSafe('Ada\r\nBcc: victim@example.com'), 'Ada Bcc: victim@example.com');
  const email = renderVerifySignup('Ada\r\nBcc: victim@example.com', ACTION_LINK);
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
  const email = renderPasswordChanged('Ada', '2026-09-08T04:05:06.000Z', 'stanley@rev22.com.sg');
  assertFalse(email.html.includes('/auth/v1/verify'), 'nothing to click means nothing to phish');
  assertFalse(email.html.includes('token'));
  assertFalse(email.text.includes('http://'));
  // The only link is a mailto for reporting it, which is the point of the email.
  assertStringIncludes(email.html, 'mailto:stanley@rev22.com.sg');
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
