// The sign-in and password pages, rendered for real against a fake backend
// (429: ADMIN-AUTH-9, -16, -18).
//
//   * a reset email that could not be handed over keeps the form, the reason
//     and the Send button (it said "Check your email");
//   * the reset pages take a new password straight away only from a session
//     that came from the email link a few minutes ago; any other session must
//     give the current password, is told whose account it is, and can sign
//     out; with no session the link has expired (the affiliate page had no
//     check at all);
//   * a page opened from the email link takes the new password even when the
//     device clock is wrong or the reset page loaded after Supabase's event;
//     a typed #type=recovery alone does not;
//   * wherever the current password is asked, "Request a new link" signs out
//     and goes to the forgot-password page (an old link was a dead end);
//   * the affiliate Account page asks for the current password;
//   * labels name their fields; Not Found goes to the dashboard.
// Every name and address is made up.
//
// Run: node --test scripts/ui/tests/password-pages.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { setupDom, bundle, fakeSupabase, driver, tokenWith } from '../page-harness.mjs';

const dom = setupDom();
const mod = await bundle(`
  import React from 'react';
  export { default as ForgotPasswordPage } from './src/pages/ForgotPasswordPage';
  export { default as AffiliateForgotPasswordPage } from './src/pages/AffiliateForgotPasswordPage';
  export { default as ResetPasswordPage } from './src/pages/ResetPasswordPage';
  export { default as AffiliateResetPasswordPage } from './src/pages/AffiliateResetPasswordPage';
  export { default as LoginPage } from './src/pages/LoginPage';
  export { default as NotFoundPage } from './src/pages/NotFoundPage';
  export { cameFromEmailLink, emailLinkInAddress, openedFromEmailLink } from './src/lib/resetSession';
  export { MemoryRouter, Routes, Route } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`, { stubAuth: true });
const { React, MemoryRouter, Routes, Route } = mod;
const d = driver(mod, dom);
// The same pages, loaded as an app opened from an email link: the address
// carries the link's #fragment when the app starts (Supabase clears it later).
dom.window.location.hash = '#access_token=a.b.c&expires_in=3600&refresh_token=r&token_type=bearer&type=recovery';
const fromLinkMod = await bundle(`
  import React from 'react';
  export { default as ResetPasswordPage } from './src/pages/ResetPasswordPage';
  export { default as AffiliateResetPasswordPage } from './src/pages/AffiliateResetPasswordPage';
  export { openedFromEmailLink } from './src/lib/resetSession';
  export { MemoryRouter, Routes, Route } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`, { stubAuth: true });
dom.window.location.hash = '';
const dl = driver(fromLinkMod, dom);
after(async () => { await d.unmount(); await dl.unmount(); dom.window.close(); });

const h = React.createElement;
const now = () => Math.floor(Date.now() / 1000);
const session = (method, ago = 60) => ({
  access_token: tokenWith({ sub: 'u1', amr: [{ method, timestamp: now() - ago }] }),
  user: { id: 'u1', email: 'sara@sig.invalid' },
});
// Renders `page` at `path`, with the pages it may move to marked by their path.
async function at(path, page, sb) {
  await dl.unmount();
  globalThis.__supabase = sb;
  globalThis.__auth = { signIn: async () => ({ error: null }), session: sb.auth.session };
  await d.mount(h(MemoryRouter, { initialEntries: [path] },
    h(Routes, null,
      h(Route, { path, element: page }),
      ...['/', '/login', '/forgot-password', '/affiliate/dashboard', '/affiliate/login', '/affiliate/forgot-password']
        .filter(p => p !== path).map(p => h(Route, { key: p, path: p, element: h('div', { id: 'landed' }, p) })))));
}
const landed = () => document.getElementById('landed')?.textContent ?? null;
// As `at`, for the pages of the app opened from an email link.
async function atFromLink(path, name, sb) {
  await d.unmount();
  const x = fromLinkMod.React.createElement;
  globalThis.__supabase = sb;
  globalThis.__auth = { session: sb.auth.session };
  await dl.mount(x(fromLinkMod.MemoryRouter, { initialEntries: [path] },
    x(fromLinkMod.Routes, null,
      x(fromLinkMod.Route, { path, element: x(fromLinkMod[name]) }),
      ...['/', '/forgot-password', '/affiliate/dashboard', '/affiliate/forgot-password']
        .filter(p => p !== path).map(p => x(fromLinkMod.Route, { key: p, path: p, element: x('div', { id: 'landed' }, p) })))));
}
const changeBodies = sb => sb.calls.filter(c => c.fn === 'auth-change-password').map(c => c.body);

for (const [name, path, flow] of [['ForgotPasswordPage', '/forgot-password', 'staff'],
                                  ['AffiliateForgotPasswordPage', '/affiliate/forgot-password', 'affiliate']]) {
  test(`${name}: an email that could not be handed over keeps the form, the reason and the button`, async () => {
    const sb = fakeSupabase({ invoke: { 'auth-request-recovery': () => ({ data: { ok: true, status: 'not_sent' }, error: null }) } });
    await at(path, h(mod[name]), sb);
    await d.setValue(document.querySelector('input[type="email"]'), 'sara@sig.invalid');
    const send = [...document.querySelectorAll('button')].find(b => /Send/i.test(b.textContent));
    if (document.querySelector('form')) await d.submit(document.querySelector('form')); else await d.click(send);
    assert.equal(sb.calls.filter(c => c.fn === 'auth-request-recovery')[0].body.flow, flow);
    assert.ok(!d.text().includes('Check your email'), 'not told to check their email');
    assert.ok([...document.querySelectorAll('[role="alert"]')].some(a => a.textContent.includes('We could not hand your email')));
    const again = [...document.querySelectorAll('button')].find(b => /Send/i.test(b.textContent));
    assert.ok(again && !again.disabled, 'Send is there to try again');
  });
}

test('ForgotPasswordPage: an email handed over still says to check the inbox', async () => {
  const sb = fakeSupabase({ invoke: { 'auth-request-recovery': () => ({ data: { ok: true, status: 'submitted' }, error: null }) } });
  await at('/forgot-password', h(mod.ForgotPasswordPage), sb);
  await d.setValue(d.labelled('Email'), 'sara@sig.invalid');
  await d.submit(document.querySelector('form'));
  assert.ok(d.text().includes('Check your email'));
});

test('ResetPasswordPage: from the email link a moment ago, the new password is enough', async () => {
  const sb = fakeSupabase();
  sb.auth.session = session('recovery');
  await at('/reset-password', h(mod.ResetPasswordPage), sb);
  assert.equal(d.labelled('Current Password'), null, 'no current password asked');
  assert.ok(d.text().includes('sara@sig.invalid'), 'it says whose account');
  await d.setValue(d.labelled('New Password'), 'a-new-password-1');
  await d.setValue(d.labelled('Confirm Password'), 'a-new-password-1');
  sb.invokeHandlers['auth-change-password'] = () => ({ data: { ok: true, password_changed: true }, error: null });
  await d.submit(document.querySelector('form'));
  assert.deepEqual(changeBodies(sb), [{ password: 'a-new-password-1' }]);
  assert.equal(landed(), '/');
});

test('ResetPasswordPage: someone already signed in must give the current password, sees whose it is, and can sign out', async () => {
  const sb = fakeSupabase();
  sb.auth.session = session('password', 3600);
  await at('/reset-password', h(mod.ResetPasswordPage), sb);
  assert.ok(d.text().includes('Change the password for sara@sig.invalid'), d.text());
  const current = d.labelled('Current Password');
  assert.ok(current, 'the current password is asked');
  await d.setValue(d.labelled('New Password'), 'a-new-password-1');
  await d.setValue(d.labelled('Confirm Password'), 'a-new-password-1');
  await d.submit(document.querySelector('form'));
  assert.equal(changeBodies(sb).length, 0, 'not sent without the current password');
  assert.ok(document.querySelector('[role="alert"]').textContent.includes('Enter your current password.'));
  await d.setValue(current, 'the-old-one');
  sb.invokeHandlers['auth-change-password'] = () => ({ data: null,
    error: { context: new Response(JSON.stringify({ error: 'current_password_wrong', message: 'That is not your current password.' }), { status: 400 }) } });
  await d.submit(document.querySelector('form'));
  assert.deepEqual(changeBodies(sb).at(-1), { password: 'a-new-password-1', current_password: 'the-old-one' });
  assert.ok(document.querySelector('[role="alert"]').textContent.includes('That is not your current password.'));
  await d.click(d.button('Sign out'));
  assert.ok(sb.calls.some(c => c.auth === 'signOut'));
  assert.equal(landed(), '/login');
});

test('ResetPasswordPage: when the server wants the current password after all, the page asks for it', async () => {
  const sb = fakeSupabase({ invoke: { 'auth-change-password': () => ({ data: null,
    error: { context: new Response(JSON.stringify({ error: 'current_password_required', message: 'Enter your current password to change it.' }), { status: 400 }) } }) } });
  sb.auth.session = session('recovery');
  await at('/reset-password', h(mod.ResetPasswordPage), sb);
  await d.setValue(d.labelled('New Password'), 'a-new-password-1');
  await d.setValue(d.labelled('Confirm Password'), 'a-new-password-1');
  await d.submit(document.querySelector('form'));
  assert.ok(d.labelled('Current Password'), 'the current password field appears');
  assert.ok(d.text().includes('Enter your current password to change it.'));
});

test('ResetPasswordPage: from the link, on a device whose clock is a few minutes slow, the new password is enough', async () => {
  const sb = fakeSupabase();
  sb.auth.session = session('recovery', -120);   // the link's time is two minutes ahead of this device
  await at('/reset-password', h(mod.ResetPasswordPage), sb);
  assert.ok(!d.labelled('Current Password'), 'no current password asked (before the fix it was)');
  assert.ok(d.labelled('New Password'));
});

for (const [name, path, home] of [['ResetPasswordPage', '/reset-password', '/'],
                                  ['AffiliateResetPasswordPage', '/affiliate/reset-password', '/affiliate/dashboard']]) {
  test(`${name}: opened from the email link, a fast device clock or a missed event does not ask for the current password`, async () => {
    assert.equal(fromLinkMod.openedFromEmailLink, true, 'the link was noted as the app started');
    const sb = fakeSupabase({ invoke: { 'auth-change-password': () => ({ data: { ok: true, password_changed: true }, error: null }) } });
    sb.auth.session = session('recovery', 31 * 60);   // the device clock is 31 minutes fast
    await atFromLink(path, name, sb);
    assert.ok(!d.labelled('Current Password'), 'no current password asked (before the fix it was)');
    await d.setValue(d.labelled('New Password'), 'a-new-password-1');
    await d.setValue(d.labelled('Confirm Password'), 'a-new-password-1');
    const form = document.querySelector('form');
    if (form) await d.submit(form); else await d.click(d.button('Save Password'));
    assert.deepEqual(changeBodies(sb), [{ password: 'a-new-password-1' }], 'the server decides');
    assert.equal(landed(), home);
  });

  test(`${name}: a typed #type=recovery with an ordinary session still asks for the current password`, async () => {
    const sb = fakeSupabase();
    sb.auth.session = session('password', 3600);
    await atFromLink(path, name, sb);
    assert.ok(d.labelled('Current Password'), 'the session did not come from an email link');
  });
}

for (const [name, path, forgot] of [['ResetPasswordPage', '/reset-password', '/forgot-password'],
                                    ['AffiliateResetPasswordPage', '/affiliate/reset-password', '/affiliate/forgot-password']]) {
  test(`${name}: a link opened too long ago asks for the current password and offers a new link`, async () => {
    // The server's answer for a link opened too long ago (auth-change-password).
    const tooOld = 'The email link you signed in with was opened more than 30 minutes ago. Enter your current password, or request a new link.';
    const sb = fakeSupabase({ invoke: { 'auth-change-password': () => ({ data: null,
      error: { context: new Response(JSON.stringify({ error: 'current_password_required', message: tooOld }), { status: 400 }) } }) } });
    sb.auth.session = session('recovery');
    await at(path, h(mod[name]), sb);
    await d.setValue(d.labelled('New Password'), 'a-new-password-1');
    await d.setValue(d.labelled('Confirm Password'), 'a-new-password-1');
    const form = document.querySelector('form');
    if (form) await d.submit(form); else await d.click(d.button('Save Password'));
    assert.ok(d.labelled('Current Password'), 'the current password is asked');
    assert.ok([...document.querySelectorAll('[role="alert"]')].some(a => a.textContent.includes(tooOld)), 'the reason is shown');
    assert.ok(d.text().includes('Forgot your current password?'), d.text());
    await d.click(d.button('Request a new link'));
    assert.ok(sb.calls.some(c => c.auth === 'signOut'), 'signed out first');
    assert.equal(landed(), forgot);
  });

  test(`${name}: someone signed in is offered a new link too`, async () => {
    const sb = fakeSupabase();
    sb.auth.session = session('password', 3600);
    await at(path, h(mod[name]), sb);
    assert.ok(d.labelled('Current Password'));
    await d.click(d.button('Request a new link'));
    assert.equal(landed(), forgot);
  });
}

test('ResetPasswordPage: with no session, the link has expired', async () => {
  const sb = fakeSupabase();
  await at('/reset-password', h(mod.ResetPasswordPage), sb);
  assert.ok(d.text().includes('This password reset link has expired'));
  assert.equal(document.querySelector('form'), null);
});

test('AffiliateResetPasswordPage: no session, a session from the link, and someone signed in', async () => {
  const none = fakeSupabase();
  await at('/affiliate/reset-password', h(mod.AffiliateResetPasswordPage), none);
  assert.ok(d.text().includes('This password reset link has expired'), 'before 429 it showed the form with no session');

  const link = fakeSupabase({ invoke: { 'auth-change-password': () => ({ data: { ok: true, password_changed: true }, error: null }) } });
  link.auth.session = session('recovery');
  await at('/affiliate/reset-password', h(mod.AffiliateResetPasswordPage), link);
  assert.equal(d.labelled('Current Password'), null);
  await d.setValue(d.labelled('New Password'), 'a-new-password-1');
  await d.setValue(d.labelled('Confirm Password'), 'a-new-password-1');
  await d.click(d.button('Save Password'));
  assert.deepEqual(changeBodies(link), [{ password: 'a-new-password-1' }]);
  assert.equal(landed(), '/affiliate/dashboard');

  const signedIn = fakeSupabase();
  signedIn.auth.session = session('password', 7200);
  await at('/affiliate/reset-password', h(mod.AffiliateResetPasswordPage), signedIn);
  assert.ok(d.text().includes('Change the password for sara@sig.invalid'));
  assert.ok(d.labelled('Current Password'));
  assert.ok(d.button('Sign out'));
});

test('the affiliate Account page asks for the current password', () => {
  const src = readFileSync('src/pages/AffiliateAccountPage.tsx', 'utf8');
  assert.match(src, /if \(!current\) \{ setPwMsg\('Enter your current password\.'\); return; \}/);
  assert.match(src, /await changePassword\(pw, current\)/);
  assert.match(src, /htmlFor="account-current-password"/);
});

test('cameFromEmailLink reads the token as the server does, with room for a slow device clock', () => {
  const { cameFromEmailLink } = mod;
  const t = (method, ago) => tokenWith({ amr: [{ method, timestamp: now() - ago }] });
  assert.equal(cameFromEmailLink(t('recovery', 60)), true);
  assert.equal(cameFromEmailLink(t('magiclink', 60)), true);
  assert.equal(cameFromEmailLink(t('recovery', 31 * 60)), false);
  // A device clock a few minutes slow sees the link's time ahead of its own.
  assert.equal(cameFromEmailLink(t('recovery', -120)), true);
  assert.equal(cameFromEmailLink(t('recovery', -9 * 60)), true);
  assert.equal(cameFromEmailLink(t('recovery', -11 * 60)), false);
  assert.equal(cameFromEmailLink(t('password', 5)), false);
  assert.equal(cameFromEmailLink(null), false);
  assert.equal(cameFromEmailLink('not.a-token'), false);
  const { emailLinkInAddress } = mod;
  assert.equal(emailLinkInAddress('#access_token=a&refresh_token=r&type=recovery'), true);
  assert.equal(emailLinkInAddress('#type=invite&access_token=a'), true);
  assert.equal(emailLinkInAddress('#access_token=a&type=magiclink'), true);
  assert.equal(emailLinkInAddress('#access_token=a&type=signup'), false);
  assert.equal(emailLinkInAddress('#access_token=a&type=recoveryx'), false);
  assert.equal(emailLinkInAddress(''), false);
  assert.equal(mod.openedFromEmailLink, false, 'an app opened without a link');
});

test('App.tsx loads the email-link check with the app, not with the reset pages', () => {
  assert.match(readFileSync('src/App.tsx', 'utf8'), /^import '\.\/lib\/resetSession';$/m);
});

test('the sign-in page\'s labels name their fields', async () => {
  const sb = fakeSupabase();
  await at('/login', h(mod.LoginPage), sb);
  assert.equal(d.labelled('Email')?.type, 'email');
  assert.equal(d.labelled('Password')?.getAttribute('autocomplete'), 'current-password');
});

test('the affiliate pages\' labels name their fields', async () => {
  const sb = fakeSupabase();
  await at('/affiliate/forgot-password', h(mod.AffiliateForgotPasswordPage), sb);
  assert.equal(d.labelled('Email')?.type, 'email');
});

test('Not Found goes to the dashboard (or to sign in), never back out of the app', async () => {
  const sb = fakeSupabase();
  globalThis.__supabase = sb;
  globalThis.__auth = { session: { user: { id: 'u1' } } };
  await d.mount(h(MemoryRouter, { initialEntries: ['/nowhere'] }, h(Routes, null,
    h(Route, { path: '/', element: h('div', { id: 'landed' }, '/') }),
    h(Route, { path: '*', element: h(mod.NotFoundPage) }))));
  await d.click(d.button('Go to dashboard'));
  assert.equal(landed(), '/');
  globalThis.__auth = { session: null };
  await d.mount(h(MemoryRouter, { initialEntries: ['/nowhere'] }, h(Routes, null,
    h(Route, { path: '/login', element: h('div', { id: 'landed' }, '/login') }),
    h(Route, { path: '*', element: h(mod.NotFoundPage) }))));
  await d.click(d.button('Go to sign in'));
  assert.equal(landed(), '/login');
});
