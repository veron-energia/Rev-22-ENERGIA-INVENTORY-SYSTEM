// Callback allowlisting, and the check that a generated link is really ours.

import { assert, assertEquals, assertFalse } from 'jsr:@std/assert@1';
import { CALLBACK_PATHS, callbackBaseFor, callbackUrl, isTrustedActionLink } from '../redirects.ts';
import { APP_URL, SUPABASE_URL, testConfig, ACTION_LINK } from './support.ts';

Deno.test('flows map to the production callbacks', () => {
  const config = testConfig();
  assertEquals(callbackUrl(config, 'affiliate_signup', null), `${APP_URL}/affiliate/verify`);
  assertEquals(callbackUrl(config, 'affiliate_recovery', null), `${APP_URL}/affiliate/reset-password`);
  assertEquals(callbackUrl(config, 'staff_recovery', null), `${APP_URL}/reset-password`);
  assertEquals(callbackUrl(config, 'user_invitation', null), `${APP_URL}/accept-invitation`);
  // The count is asserted so a speculative callback cannot be added quietly.
  // Four now: internal invitations landed one, and it has a route to match.
  assertEquals(Object.keys(CALLBACK_PATHS).length, 4, 'no speculative callbacks');
});

Deno.test('an unlisted origin cannot nominate itself as the callback', () => {
  const config = testConfig();
  for (const origin of [
    'https://evil.example',
    `${APP_URL}.evil.example`,
    'https://rev-22-energia-inventory-system.vercel.app.evil.example',
    'null',
  ]) {
    assertEquals(callbackBaseFor(config, origin), APP_URL, `must fall back for ${origin}`);
  }
});

Deno.test('a separately configured test origin is honoured', () => {
  const staging = 'https://staging.energia.test';
  const config = testConfig({ callbackBaseUrls: [APP_URL, staging] });
  assertEquals(callbackBaseFor(config, staging), staging);
  assertEquals(callbackBaseFor(config, `${staging}/`), staging, 'trailing slash is not a different origin');
  assertEquals(callbackBaseFor(config, 'https://other.test'), APP_URL);
});

Deno.test('only a link on this project\'s Auth origin is trusted', () => {
  const config = testConfig();
  assert(isTrustedActionLink(ACTION_LINK, config));
  for (const bad of [
    `https://evil.example/auth/v1/verify?token=x`,
    `http://project.supabase.co/auth/v1/verify?token=x`,   // not https
    `${SUPABASE_URL}.evil.example/auth/v1/verify`,
    `javascript:alert(1)`,
    `${SUPABASE_URL}/auth/v1/verify?token=x"><script>`,
    `${SUPABASE_URL}/auth/v1/verify\r\nBcc: victim@example.com`,
    '', null, undefined, 42,
    `${SUPABASE_URL}/${'x'.repeat(4000)}`,
  ]) assertFalse(isTrustedActionLink(bad, config), `should reject ${String(bad).slice(0, 60)}`);
});
