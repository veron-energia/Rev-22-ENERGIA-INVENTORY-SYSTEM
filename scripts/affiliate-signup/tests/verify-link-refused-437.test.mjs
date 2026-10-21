// An emailed link Supabase refused (437): the app is opened at
// /affiliate/verify with "#error=...&error_code=otp_expired" (the link
// expired, or was already used). Supabase keeps the session already in the
// browser, so without reading the address the page would carry on as an
// ordinary visit and the person would never learn the link failed.
//
//   R1 The verify page says the link expired or was used, with Sign in and Go
//      to Account; it finishes no sign-up and verifies nothing.
//   R2 It says so once: a later visit (after signing in) is an ordinary one.
//
// The app reads the address once, as it starts (src/lib/affiliateEmail.ts,
// imported by App.tsx), so this file opens jsdom at that address before the
// pages are bundled. Every name and email is invented.
// Run: node --test scripts/affiliate-signup/tests/verify-link-refused-437.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, fakeSupabase, driver, tokenWith } from '../../ui/page-harness.mjs';

const dom = setupDom('https://energia.invalid/affiliate/verify#error=access_denied&error_code=otp_expired'
  + '&error_description=Email+link+is+invalid+or+has+expired');
const mod = await bundle(`
  import React from 'react';
  export { default as AffiliateVerifyPage } from './src/pages/AffiliateVerifyPage';
  export { AuthProvider } from './src/context/AuthContext';
  export { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };`);
const { React, AffiliateVerifyPage, AuthProvider, MemoryRouter, Routes, Route, useLocation } = mod;
const d = driver(mod, dom);
const h = React.createElement;
after(async () => { await d.unmount(); dom.window.close(); });

const UID = '00000000-0000-4000-8000-000000000438';
function app() {
  const Where = () => h('output', { 'data-where': useLocation().pathname });
  return h(MemoryRouter, { initialEntries: ['/affiliate/verify'] },
    h(AuthProvider, null, h(Where),
      h(Routes, null,
        h(Route, { path: '/affiliate/verify', element: h(AffiliateVerifyPage) }),
        h(Route, { path: '/affiliate/dashboard', element: h('p', null, 'DASHBOARD') }),
        h(Route, { path: '/affiliate/login', element: h('p', null, 'LOGIN PAGE') }))));
}
function backend() {
  const client = fakeSupabase({
    tables: { profiles: [], affiliate_accounts: [] },
    rpc: {
      complete_affiliate_onboarding: () => ({ status: 'active', customer_id: 'cust-1', referral_code: 'T437BEN', already: false, email_verified: false }),
      confirm_affiliate_email: () => ({ verified: true, already: false }),
    },
  });
  // The password session the browser already had (Supabase keeps it when a link fails).
  client.auth.session = {
    access_token: tokenWith({ sub: UID, role: 'authenticated', amr: [{ method: 'password', timestamp: Math.floor(Date.now() / 1000) - 600 }] }),
    user: { id: UID, email: 'ben-437@example.com', user_metadata: { first_name: 'Ben', last_name: 'Testlink', phone: '+61491573770' } },
  };
  globalThis.__supabase = client;
  return client;
}
const rpcs = (client, name) => client.calls.filter(c => c.rpc === name);

test('R1: a refused link is said, with Sign in and Go to Account; nothing is finished or verified', async () => {
  const client = backend();
  await d.mount(app());
  await d.tick(15);
  assert.match(document.querySelector('[data-state="link-refused"]')?.textContent ?? '',
    /This link has expired or was already used\. Sign in and send a new one from your Account page\./);
  const links = [...document.querySelectorAll('a')].map(a => [a.textContent, a.getAttribute('href')]);
  assert.deepEqual(links, [['Sign in', '/affiliate/login'], ['Go to Account', '/affiliate/account']]);
  assert.equal(rpcs(client, 'complete_affiliate_onboarding').length, 0);
  assert.equal(rpcs(client, 'confirm_affiliate_email').length, 0);
  assert.equal(document.querySelector('[data-where]')?.getAttribute('data-where'), '/affiliate/verify');
});

test('R2: once said, a later visit to the verify page is an ordinary one', async () => {
  const client = backend();
  await d.mount(app());
  await d.tick(20);
  assert.equal(document.querySelector('[data-state="link-refused"]'), null);
  assert.equal(rpcs(client, 'complete_affiliate_onboarding').length, 1);
  assert.equal(document.querySelector('[data-where]')?.getAttribute('data-where'), '/affiliate/dashboard');
});
