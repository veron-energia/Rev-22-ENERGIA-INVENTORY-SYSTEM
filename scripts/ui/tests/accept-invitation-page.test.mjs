// The invitation page, rendered for real against a fake backend (429).
//
//   * a member of staff who was removed and is invited again opens a recovery
//     link for their old login, which is confirmed and was never marked as
//     invited: they get the password form (the page showed only "You are
//     signed in as ..." with a sign-out button, and the single-use link was
//     then spent);
//   * the page does not judge a link's age by the device clock: a session
//     opened from an emailed link asks the server, and gets the form when the
//     server says the invitation is pending;
//   * 18 Oct 2026 (the Owner: "30 minutes, like reset links"): a pending
//     invitation whose link was opened over 30 minutes ago gets "This
//     invitation link has expired. Ask for a new invitation." and Go to sign
//     in, with no form, on arrival or when the password is sent;
//   * a password sign-in gets the warning, with or without the invited mark
//     (the server refuses such a session too), and can sign out;
//   * the server's refusal of a session not from the link is shown;
//   * the form shows only when the server says the login has a pending
//     invitation. A login with none (a member of staff or an affiliate who
//     opened a reset link), or a used one, is sent to sign in or reset
//     instead, and no password is sent. A cancelled, unfinished or
//     wrong-address invitation gets the server's words and "Go to sign in"
//     only: a reset link cannot open a closed login.
// Every name and address is made up.
//
// Run: node --test scripts/ui/tests/accept-invitation-page.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, fakeSupabase, driver, tokenWith } from '../page-harness.mjs';

const dom = setupDom();
const mod = await bundle(`
  import React from 'react';
  export { default as AcceptInvitationPage } from './src/pages/AcceptInvitationPage';
  export { signedInFromEmailLink } from './src/lib/resetSession';
  export { MemoryRouter, Routes, Route } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`, { stubAuth: true });
const { React, MemoryRouter, Routes, Route } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });

const h = React.createElement;
const now = () => Math.floor(Date.now() / 1000);
const EMAIL = 'returning.staff@sig.invalid';
// A session as supabase-js holds it: its token says how it signed in.
const session = (method, ago = 60) => ({
  access_token: tokenWith({ sub: 'u1', amr: [{ method, timestamp: now() - ago }] }),
  user: { id: 'u1', email: EMAIL },
});
// The login Supabase Auth returns: confirmed, and (unless given) never marked
// as invited, as a removed member of staff's old login is.
const login = (meta = { full_name: 'Returning Staff' }) => ({
  id: 'u1', email: EMAIL, email_confirmed_at: '2026-01-05T02:00:00Z', user_metadata: meta,
});

async function open(sb, user, { strict = false } = {}) {
  sb.auth.getUser = async () => ({ data: { user } });
  globalThis.__supabase = sb;
  let refreshed = 0;
  globalThis.__auth = { refreshProfile: async () => { refreshed++; } };
  const app = h(MemoryRouter, { initialEntries: ['/accept-invitation'] },
    h(Routes, null,
      h(Route, { path: '/accept-invitation', element: h(mod.AcceptInvitationPage) }),
      h(Route, { path: '/login', element: h('div', { id: 'landed' }, '/login') }),
      h(Route, { path: '/', element: h('div', { id: 'landed' }, '/') })));
  // The app runs in StrictMode (src/main.tsx): effects mount, unmount and mount again.
  await d.mount(strict ? h(React.StrictMode, null, app) : app);
  return { refreshed: () => refreshed };
}
// The server's answers. `check` is the page's first question; `accept` is the password.
const PENDING = { data: { ok: true, pending: true }, error: null };
const refusal = (status, body) => ({ data: null, error: { context: new Response(JSON.stringify(body), { status }) } });
const server = (check, accept = { data: { ok: true, role: 'staff' }, error: null }) =>
  ({ invoke: { 'auth-accept-invitation': body => (body?.check ? (typeof check === 'function' ? check() : check) : accept) } });
const asked = sb => sb.calls.filter(c => c.fn === 'auth-accept-invitation').map(c => c.body);
const passwordFields = () => document.querySelectorAll('input[type="password"]').length;
const warned = () => d.text().includes(`You are signed in as ${EMAIL}`);

test('a removed member of staff invited again, from the recovery link: the password form, not the warning', async () => {
  const sb = fakeSupabase(server(PENDING));
  sb.auth.session = session('otp');
  const page = await open(sb, login());
  assert.ok(!warned(), 'no "You are signed in as" warning');
  assert.equal(passwordFields(), 2, 'Choose a password and Confirm password are there');
  assert.ok(d.text().includes('Choose a password'));
  assert.ok(d.text().includes(EMAIL), 'the page says which account it is');
  await d.setValue(d.labelled('Choose a password'), 'a-new-password-429');
  await d.setValue(d.labelled('Confirm password'), 'a-new-password-429');
  await d.submit(document.querySelector('form'));
  assert.deepEqual(asked(sb), [{ check: true }, { password: 'a-new-password-429' }],
    'asked about the invitation first, then sent the password');
  assert.ok(d.text().includes('Your account is ready'));
  assert.equal(page.refreshed(), 1, 'the account is read again once switched on');
});

test('the page does not judge the link\'s age by the device clock: it asks the server, and a pending answer gives the form', async () => {
  for (const [method, ago] of [['recovery', 60], ['invite', 60], ['magiclink', 60], ['otp', 3 * 86400], ['otp', -2 * 3600]]) {
    const sb = fakeSupabase(server(PENDING));
    sb.auth.session = session(method, ago);
    await open(sb, login());
    assert.ok(!warned() && passwordFields() === 2, `${method}, ${ago} seconds ago`);
    assert.deepEqual(asked(sb), [{ check: true }], `${method}, ${ago} seconds ago: the server was asked`);
  }
  assert.equal(mod.signedInFromEmailLink(session('password').access_token), false);
  assert.equal(mod.signedInFromEmailLink('not-a-token'), false);
});

test('a password sign-in of a confirmed login gets the warning and a way to sign out, with no form', async () => {
  for (const meta of [{ full_name: 'Returning Staff' }, { full_name: 'Someone', invited_to: 'energia_internal' }]) {
    const sb = fakeSupabase();
    sb.auth.session = session('password');
    await open(sb, login(meta));
    assert.ok(warned(), `warned (${JSON.stringify(meta)})`);
    assert.equal(passwordFields(), 0, 'no password form');
    assert.deepEqual(asked(sb), [], 'nothing asked or sent');
    await d.click(d.button('Sign out and open the invitation again'));
    assert.ok(sb.calls.some(c => c.auth === 'signOut'), 'signed out');
    assert.ok(d.text().includes('This invitation link has expired or has already been used'));
  }
});

test('the server refusing a session that did not come from the link is shown, not swallowed', async () => {
  const notFromLink = { error: 'unauthorized', reason: 'not_from_link',
                        message: 'Open the invitation link from your email to finish setting up.' };
  const sb = fakeSupabase(server(PENDING, refusal(401, notFromLink)));
  sb.auth.session = session('otp');
  await open(sb, login());
  await d.setValue(d.labelled('Choose a password'), 'a-new-password-429');
  await d.setValue(d.labelled('Confirm password'), 'a-new-password-429');
  await d.submit(document.querySelector('form'));
  assert.ok(d.text().includes('Open the invitation link from your email to finish setting up.'));
  assert.equal(passwordFields(), 0);
});

test('a login with no invitation (a reset link, however old) gets no form: sign in or reset instead', async () => {
  const notInvited = { error: 'not_activated', reason: 'not_invited', message: 'There is no invitation for this account.' };
  for (const [method, ago] of [['recovery', 3 * 86400], ['recovery', 60], ['magiclink', 600]]) {
    const sb = fakeSupabase(server(refusal(403, notInvited)));
    sb.auth.session = session(method, ago);
    await open(sb, login());
    assert.equal(passwordFields(), 0, `no password form (${method}, ${ago}s)`);
    assert.ok(d.text().includes('There is no invitation for this account.'));
    assert.ok(d.text().includes('If you already have an account, sign in. If you forgot your password, ask for a reset link.'));
    assert.equal(d.text().split('If you already have an account').length, 2, 'the advice is given once, not twice');
    const links = [...document.querySelectorAll('a')].map(a => a.getAttribute('href'));
    assert.ok(links.includes('/login') && links.includes('/forgot-password') && links.includes('/affiliate/login'), links.join(' '));
    assert.deepEqual(asked(sb), [{ check: true }], 'only asked; no password sent');
  }
});

test('an affiliate signed in from a reset link is sent to sign in, not shown the form', async () => {
  const sb = fakeSupabase(server(refusal(403, { error: 'not_activated', reason: 'not_invited',
    message: 'There is no invitation for this account.' })));
  sb.auth.session = { access_token: tokenWith({ sub: 'a1', amr: [{ method: 'recovery', timestamp: now() - 7200 }] }),
                      user: { id: 'a1', email: 'an.affiliate@example.com' } };
  await open(sb, { id: 'a1', email: 'an.affiliate@example.com', email_confirmed_at: '2026-02-01T02:00:00Z', user_metadata: {} });
  assert.equal(passwordFields(), 0);
  assert.ok(d.text().includes('Affiliates:'));
  assert.deepEqual(asked(sb), [{ check: true }]);
});

test('a cancelled or used invitation shows the server\'s words and no form', async () => {
  for (const [reason, message] of [['cancelled', 'This invitation was cancelled and can no longer be used.'],
                                   ['already_accepted', 'This invitation has already been used. Sign in with your password.']]) {
    const sb = fakeSupabase(server(refusal(403, { error: 'not_activated', reason, message })));
    sb.auth.session = session('invite');
    await open(sb, login({ full_name: 'Someone', invited_to: 'energia_internal' }));
    assert.equal(passwordFields(), 0, reason);
    assert.ok(d.text().includes(message), reason);
    assert.deepEqual(asked(sb), [{ check: true }]);
  }
});

test('a cancelled, unfinished or wrong-address invitation: the server\'s words and Go to sign in only, no reset link', async () => {
  for (const [reason, message] of [['cancelled', 'This invitation was cancelled and can no longer be used.'],
                                   ['not_set_up', 'This invitation was not finished. Ask whoever invited you to send it again.'],
                                   ['wrong_account', 'This invitation was sent to a different address.'],
                                   ['expired', 'This invitation is no longer valid.']]) {
    const sb = fakeSupabase(server(refusal(403, { error: 'not_activated', reason, message })));
    sb.auth.session = session('invite');
    await open(sb, login({ full_name: 'Someone', invited_to: 'energia_internal' }));
    assert.equal(passwordFields(), 0, reason);
    assert.ok(d.text().includes(message), reason);
    const links = [...document.querySelectorAll('a')].map(a => a.getAttribute('href'));
    assert.deepEqual(links, ['/login'], `${reason}: ${links.join(' ')}`);
    assert.ok(!d.text().includes('If you already have an account'), reason);
    assert.ok(!d.text().includes('Reset my password'), reason);
  }
  // A used invitation: the person has an account, so sign in or reset helps.
  const sb = fakeSupabase(server(refusal(403, { error: 'not_activated', reason: 'already_accepted',
    message: 'This invitation has already been used. Sign in with your password.' })));
  sb.auth.session = session('invite');
  await open(sb, login({ full_name: 'Someone', invited_to: 'energia_internal' }));
  const links = [...document.querySelectorAll('a')].map(a => a.getAttribute('href'));
  assert.ok(links.includes('/login') && links.includes('/forgot-password'), links.join(' '));
});

const LINK_EXPIRED = { error: 'not_activated', reason: 'link_expired',
                       message: 'This invitation link has expired. Ask for a new invitation.' };
const onlySignIn = (label) => {
  const links = [...document.querySelectorAll('a')].map(a => a.getAttribute('href'));
  assert.deepEqual(links, ['/login'], `${label}: ${links.join(' ')}`);
  assert.ok(!d.text().includes('If you already have an account'), label);
  assert.ok(!d.text().includes('Reset my password'), label);
};

test('a pending invitation whose link was opened over 30 minutes ago: the expiry words and Go to sign in, no form', async () => {
  for (const [method, ago] of [['invite', 31 * 60], ['recovery', 2 * 3600], ['otp', 3 * 86400]]) {
    const sb = fakeSupabase(server(refusal(403, LINK_EXPIRED)));
    sb.auth.session = session(method, ago);
    await open(sb, login({ full_name: 'Someone', invited_to: 'energia_internal' }));
    assert.equal(passwordFields(), 0, `no password form (${method}, ${ago}s)`);
    assert.ok(d.text().includes('This invitation link has expired. Ask for a new invitation.'), `${method}, ${ago}s`);
    onlySignIn(`${method}, ${ago}s`);
    assert.deepEqual(asked(sb), [{ check: true }], 'only asked; no password sent');
  }
});

test('the link passes 30 minutes while the form is open: the password is refused and the form gives way to the expiry words', async () => {
  const sb = fakeSupabase(server(PENDING, refusal(403, LINK_EXPIRED)));
  sb.auth.session = session('invite', 29 * 60);
  const page = await open(sb, login());
  assert.equal(passwordFields(), 2, 'the form, while the server says the invitation is pending');
  await d.setValue(d.labelled('Choose a password'), 'a-new-password-429');
  await d.setValue(d.labelled('Confirm password'), 'a-new-password-429');
  await d.submit(document.querySelector('form'));
  assert.deepEqual(asked(sb), [{ check: true }, { password: 'a-new-password-429' }]);
  assert.equal(passwordFields(), 0, 'no form once the server says the link has expired');
  assert.ok(d.text().includes('This invitation link has expired. Ask for a new invitation.'));
  assert.ok(!d.text().includes('Your account is ready'));
  onlySignIn('after the password was refused');
  assert.equal(page.refreshed(), 0, 'nothing was switched on');
});

test('if the invitation cannot be checked, no form; Try again asks once more', async () => {
  let calls = 0;
  const sb = fakeSupabase(server(() => (++calls === 1
    ? refusal(503, { error: 'temporarily_unavailable', message: 'We could not check your invitation just now. Please try again shortly.' })
    : PENDING)));
  sb.auth.session = session('invite');
  await open(sb, login());
  assert.equal(passwordFields(), 0);
  assert.ok(d.text().includes('We could not check your invitation just now.'));
  await d.click(d.button('Try again'));
  assert.equal(passwordFields(), 2, 'the form, once the server says the invitation is pending');
});

test('in StrictMode, as the app runs, the server\'s answer still reaches the page', async () => {
  const sb = fakeSupabase(server(PENDING));
  sb.auth.session = session('invite');
  await open(sb, login(), { strict: true });
  assert.equal(passwordFields(), 2, 'the form, not stuck on "Checking your invitation"');
});
