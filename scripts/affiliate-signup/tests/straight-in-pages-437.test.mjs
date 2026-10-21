// Affiliate sign-up goes straight in (437; the Owner's decisions of 20 Oct
// 2026), the pages rendered for real against a fake backend: the real
// AuthProvider, the real portal guard, and the real Join, Verify, Login and
// Account pages under a router.
//
//   J  Create Account: the sign-up function answers "created", the page signs
//      in with the password typed, /affiliate/verify finishes the sign-up with
//      the details the account holds, and the person lands on the dashboard.
//      No email is waited for.
//   U  An address that already has a login: the page says so, with Sign in and
//      Reset password, and does not sign in. An older sign-up function's
//      "submitted": the old "check your email" screen.
//   G  The portal guard: a signed-in login with no affiliate account (someone
//      stuck after signing up) is taken through /affiliate/verify, which
//      finishes the sign-up without asking again for details, to the
//      dashboard. The login page sends such a login there too, and explains a
//      login that is not switched on yet.
//   A  The Account page: "Not verified" with Send verification email, which
//      asks auth-resend-verification for the affiliate's own address; the
//      verification link (a session from an emailed link) marks the email
//      verified and lands on the Account page with "Verified". Before 437 the
//      page shows no badge.
//   S  A browser still signed in as staff: the Join page says Create Account
//      signs that login out, signs it out on this device only, and the new
//      affiliate lands on the dashboard (never the staff screen, which comes
//      from the server's STAFF_ACCOUNT alone).
//   F  A link that could not verify the email lands on the Account page,
//      which says so; a page with no session asks the person to sign in; the
//      Account page re-reads after Send (verified elsewhere: says so) and says
//      when the status could not be read, with Try again; the login page
//      sends the sign-up link again for a login not switched on. A device
//      clock a few minutes slow still counts a fresh link.
//
// Every name, phone and email is invented (ACMA fictional numbers, @example.com).
// Run: node --test scripts/affiliate-signup/tests/straight-in-pages-437.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, fakeSupabase, driver, tokenWith } from '../../ui/page-harness.mjs';

const dom = setupDom('https://energia.invalid/affiliate/join');
const mod = await bundle(`
  import React from 'react';
  export { default as AffiliateJoinPage } from './src/pages/AffiliateJoinPage';
  export { default as AffiliateVerifyPage } from './src/pages/AffiliateVerifyPage';
  export { default as AffiliateLoginPage } from './src/pages/AffiliateLoginPage';
  export { default as AffiliateAccountPage } from './src/pages/AffiliateAccountPage';
  export { AffiliateProtected } from './src/components/RouteGuards';
  export { AuthProvider } from './src/context/AuthContext';
  export { sessionFromEmailLink } from './src/lib/affiliateEmail';
  export { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };`);
const { React, AffiliateJoinPage, AffiliateVerifyPage, AffiliateLoginPage, AffiliateAccountPage, AffiliateProtected,
  AuthProvider, MemoryRouter, Routes, Route, useLocation, sessionFromEmailLink } = mod;
const d = driver(mod, dom);
const h = React.createElement;
after(async () => { await d.unmount(); dom.window.close(); });

const UID = '00000000-0000-4000-8000-000000000437';
const EMAIL = 'ada-437@example.com';
const STAFF_UID = '00000000-0000-4000-8000-000000000999';
const STAFF_EMAIL = 'sam-staff-437@example.com';

/** The routes the portal has, with a stand-in dashboard and the place shown. */
function app(start) {
  const Where = () => h('output', { 'data-where': useLocation().pathname });
  return h(MemoryRouter, { initialEntries: [start] },
    h(AuthProvider, null,
      h(Where),
      h(Routes, null,
        h(Route, { path: '/affiliate/join', element: h(AffiliateJoinPage) }),
        h(Route, { path: '/affiliate/login', element: h(AffiliateLoginPage) }),
        h(Route, { path: '/affiliate/verify', element: h(AffiliateVerifyPage) }),
        h(Route, { path: '/affiliate/forgot-password', element: h('p', null, 'FORGOT PAGE') }),
        h(Route, { path: '/affiliate/dashboard', element: h(AffiliateProtected, null, h('p', null, 'DASHBOARD')) }),
        h(Route, { path: '/affiliate/account', element: h(AffiliateProtected, null, h(AffiliateAccountPage)) }),
        h(Route, { path: '/', element: h('p', null, 'STAFF APP') }))));
}
const where = () => document.querySelector('[data-where]')?.getAttribute('data-where');

/**
 * A backend: Supabase Auth with listeners (a sign-in tells the app, as
 * supabase-js does), the tables the app reads, and the server functions.
 */
function backend({ signedIn = false, amr = 'password', meta = {}, signup, verifiedAt = null, hasAccount = false,
  staff = false, fail = {}, confirm, resend } = {}) {
  const listeners = [];
  const session = () => ({
    access_token: tokenWith({ sub: UID, role: 'authenticated', amr: [{ method: amr, timestamp: Math.floor(Date.now() / 1000) - 60 }] }),
    user: { id: UID, email: EMAIL, user_metadata: meta },
  });
  // A member of staff still signed in in this browser.
  const staffSession = () => ({
    access_token: tokenWith({ sub: STAFF_UID, role: 'authenticated', amr: [{ method: 'password', timestamp: Math.floor(Date.now() / 1000) - 600 }] }),
    user: { id: STAFF_UID, email: STAFF_EMAIL, user_metadata: {} },
  });
  const auth = {
    session: staff ? staffSession() : signedIn ? session() : null,
    getSession: async () => ({ data: { session: auth.session } }),
    onAuthStateChange: cb => { listeners.push(cb); return { data: { subscription: { unsubscribe() {} } } }; },
    signInWithPassword: async ({ email, password }) => {
      client.calls.push({ auth: 'signIn', email, password });
      if (auth.failSignIn) return { data: {}, error: auth.failSignIn };
      auth.session = session();
      listeners.forEach(l => l('SIGNED_IN', auth.session));
      return { data: { user: auth.session.user, session: auth.session }, error: null };
    },
    signOut: async opts => { client.calls.push({ auth: 'signOut', opts }); auth.session = null; listeners.forEach(l => l('SIGNED_OUT', null)); return {}; },
    refreshSession: async () => ({ data: {} }),
  };
  const account = () => ({ id: 'acct-1', auth_user_id: UID, customer_id: 'cust-1', affiliate_id: 'aff-1', status: 'claimed', email_verified_at: verifiedAt });
  const client = fakeSupabase({
    auth, fail,
    tables: {
      profiles: staff ? [{ id: STAFF_UID, full_name: 'Sam Staffperson', email: STAFF_EMAIL, role: 'staff', is_active: true }] : [],
      affiliate_accounts: hasAccount ? [account()] : [],
    },
    rpc: {
      complete_affiliate_onboarding: args => {
        const already = client.tables.affiliate_accounts.length > 0;
        if (!already) client.tables.affiliate_accounts.push(account());
        return { status: 'active', customer_id: 'cust-1', referral_code: 'T437ADA', already, new_customer: false, email_verified: false };
      },
      confirm_affiliate_email: confirm ?? (() => {
        const row = client.tables.affiliate_accounts[0];
        const already = !!row.email_verified_at;
        row.email_verified_at ??= '2026-10-21T02:00:00Z';
        return { verified: true, already };
      }),
      affiliate_portal_me: () => ({ customer_id: 'cust-1', name: 'Ada Testlovelace', email: EMAIL, referral_code: 'T437ADA',
        status: 'active', joined_at: '2026-10-21T02:00:00Z', account_status: 'claimed', direct_referrals: 0 }),
    },
    invoke: {
      'auth-signup-request': signup ?? (() => ({ data: { ok: true, status: 'created', request_id: 'r1' }, error: null })),
      'auth-resend-verification': resend ?? (() => ({ data: { ok: true, status: 'submitted', request_id: 'r2' }, error: null })),
    },
  });
  globalThis.__supabase = client;
  return client;
}
const rpcs = (client, name) => client.calls.filter(c => c.rpc === name);

async function fillJoin() {
  const inputs = [...document.querySelectorAll('input')];
  await d.setValue(inputs[0], 'Ada');
  await d.setValue(inputs[1], 'Testlovelace');
  await d.setValue(document.querySelector('input[type="tel"]'), '+61 491 570 737');
  await d.setValue(document.querySelector('input[type="email"]'), EMAIL);
  const pw = [...document.querySelectorAll('input[type="password"]')];
  await d.setValue(pw[0], 'a-long-password-437');
  await d.setValue(pw[1], 'a-long-password-437');
  await d.toggle(document.querySelector('input[type="checkbox"]'));
}

test('J: Create Account signs in with the password typed and lands on the dashboard, with no email to wait for', async () => {
  const client = backend();
  await d.mount(app('/affiliate/join'));
  await fillJoin();
  await d.click(d.button('Create Account'));
  await d.tick(20);
  const signup = client.calls.find(c => c.fn === 'auth-signup-request');
  assert.deepEqual(signup.body, { first_name: 'Ada', last_name: 'Testlovelace', phone: '+61491570737', email: EMAIL,
    password: 'a-long-password-437', terms_accepted: true });
  assert.deepEqual(client.calls.filter(c => c.auth === 'signIn').map(c => [c.email, c.password]), [[EMAIL, 'a-long-password-437']]);
  assert.equal(rpcs(client, 'complete_affiliate_onboarding').length >= 1, true, 'the sign-up is finished by the server');
  assert.deepEqual(rpcs(client, 'complete_affiliate_onboarding')[0].args,
    { p_first_name: 'Ada', p_last_name: 'Testlovelace', p_phone: '+61491570737', p_agree: true },
    'with the details just typed (none asked again)');
  assert.equal(where(), '/affiliate/dashboard');
  assert.match(d.text(), /DASHBOARD/);
  assert.doesNotMatch(d.text(), /check your email|verification link/i);
  assert.equal(client.calls.filter(c => c.fn === 'auth-resend-verification').length, 0, 'no email is asked for');
  assert.equal(rpcs(client, 'confirm_affiliate_email').length, 0, 'a password session does not verify the email');
});

test('U: an address that already has a login is told so, with Sign in and Reset password, and nothing signs in', async () => {
  const client = backend({ signup: () => ({ data: null, error: { context: new Response(JSON.stringify({
    error: 'email_in_use', message: 'This email already has an Energia login. Sign in, or reset your password if you have forgotten it.' }), { status: 409 }) } }) });
  await d.mount(app('/affiliate/join'));
  await fillJoin();
  await d.click(d.button('Create Account'));
  const box = document.querySelector('[data-state="email-in-use"]');
  assert.ok(box, 'the email-in-use message shows');
  assert.match(box.textContent, /already has an Energia login/);
  const links = [...box.querySelectorAll('a')].map(a => [a.textContent, a.getAttribute('href')]);
  assert.deepEqual(links, [['Sign in', '/affiliate/login'], ['Reset password', '/affiliate/forgot-password']]);
  assert.equal(client.calls.filter(c => c.auth === 'signIn').length, 0);
  assert.equal(where(), '/affiliate/join');
});

test('U: an older sign-up function ("submitted") still gets the old check-your-email screen', async () => {
  backend({ signup: () => ({ data: { ok: true, status: 'submitted', request_id: 'r0' }, error: null }) });
  await d.mount(app('/affiliate/join'));
  await fillJoin();
  await d.click(d.button('Create Account'));
  assert.match(d.text(), /Check your email, or sign in/);
});

test('J: a login made but not signed in (a connection blip) is told to sign in, not to wait', async () => {
  const client = backend();
  client.auth.failSignIn = { message: 'Failed to fetch' };
  await d.mount(app('/affiliate/join'));
  await fillJoin();
  await d.click(d.button('Create Account'));
  assert.match(d.text(), /Your account is ready/);
  assert.ok([...document.querySelectorAll('a')].some(a => a.getAttribute('href') === '/affiliate/login'));
});

test('G: a signed-in login with no affiliate account (stuck after signing up) is let in through the guard, without being asked again', async () => {
  const client = backend({ signedIn: true, meta: { first_name: 'Stu', last_name: 'Teststuck', phone: '+61491577644' } });
  await d.mount(app('/affiliate/dashboard'));
  await d.tick(20);
  assert.equal(where(), '/affiliate/dashboard');
  assert.match(d.text(), /DASHBOARD/);
  assert.deepEqual(rpcs(client, 'complete_affiliate_onboarding')[0].args,
    { p_first_name: 'Stu', p_last_name: 'Teststuck', p_phone: '+61491577644', p_agree: true });
  assert.doesNotMatch(d.text(), /Confirm your details|Identity verification needed/);
});

test('G: the login page sends a login with no affiliate account to finish its sign-up, and explains one not switched on yet', async () => {
  let client = backend({ meta: { first_name: 'Stu', last_name: 'Teststuck', phone: '+61491577644' } });
  await d.mount(app('/affiliate/login'));
  await d.setValue(document.querySelector('input[type="email"]'), EMAIL);
  await d.setValue(document.querySelector('input[type="password"]'), 'a-long-password-437');
  await d.click(d.button('Sign In'));
  await d.tick(20);
  assert.equal(where(), '/affiliate/dashboard');
  client = backend();
  client.auth.failSignIn = { message: 'Email not confirmed', code: 'email_not_confirmed' };
  await d.mount(app('/affiliate/login'));
  await d.setValue(document.querySelector('input[type="email"]'), EMAIL);
  await d.setValue(document.querySelector('input[type="password"]'), 'a-long-password-437');
  await d.click(d.button('Sign In'));
  assert.match(d.text(), /not switched on yet\. Open the link we emailed you, or send it again below/);
  assert.doesNotMatch(d.text(), /waiting to be switched on/);
  await d.click(d.button('Send the sign-up link again'));
  assert.deepEqual(client.calls.filter(c => c.fn === 'auth-resend-verification').map(c => c.body), [{ email: EMAIL }]);
  assert.match(document.querySelector('[data-state="not-confirmed"] [role="status"]')?.textContent ?? '', /a new link is on its way/);
});

test('A: the Account page shows "Not verified" and sends the verification email to the affiliate\'s own address', async () => {
  const client = backend({ signedIn: true, hasAccount: true });
  await d.mount(app('/affiliate/account'));
  await d.tick(10);
  const badge = document.querySelector('[data-email-verified]');
  assert.equal(badge?.getAttribute('data-email-verified'), 'no');
  assert.equal(badge.textContent, 'Not verified');
  const section = document.querySelector('[data-section="verify-email"]');
  assert.match(section.textContent, /work the same until then/);
  await d.click(d.button('Send verification email', section));
  assert.deepEqual(client.calls.filter(c => c.fn === 'auth-resend-verification').map(c => c.body), [{ email: EMAIL }]);
  assert.match(section.textContent, /verification link is on its way/);
});

test('A: the verification link signs in at /affiliate/verify, marks the email verified and lands on the Account page', async () => {
  const client = backend({ signedIn: true, hasAccount: true, amr: 'magiclink' });
  await d.mount(app('/affiliate/verify'));
  await d.tick(20);
  assert.equal(rpcs(client, 'confirm_affiliate_email').length, 1);
  assert.equal(where(), '/affiliate/account');
  assert.equal(document.querySelector('[data-email-verified]')?.textContent, 'Verified');
  assert.match(document.querySelector('[data-note="email-verified"]')?.textContent ?? '', /Your email is verified/);
  assert.equal(document.querySelector('[data-section="verify-email"]'), null, 'no button once verified');
});

test('A: before 437 is on the server the Account page shows no badge and no button', async () => {
  const client = backend({ signedIn: true, hasAccount: true });
  // The column is not there: a read that asks for it fails (only that read).
  const realFrom = client.from;
  client.from = table => {
    const q = realFrom(table);
    const realSelect = q.select.bind(q);
    q.select = cols => {
      if (String(cols).includes('email_verified_at')) {
        q.exec = async () => ({ data: null, error: { message: 'column affiliate_accounts.email_verified_at does not exist' } });
      }
      return realSelect(cols);
    };
    return q;
  };
  await d.mount(app('/affiliate/account'));
  await d.tick(10);
  assert.equal(document.querySelector('[data-email-verified]'), null);
  assert.equal(document.querySelector('[data-section="verify-email"]'), null);
});

test('S: a browser still signed in as staff: Create Account says so, signs that login out here only, and lands the new affiliate on the dashboard', async () => {
  const client = backend({ staff: true });
  await d.mount(app('/affiliate/join'));
  await d.tick(10);
  assert.match(document.querySelector('[data-note="signed-in-elsewhere"]')?.textContent ?? '',
    /This browser is signed in as sam-staff-437@example\.com\. Creating an affiliate account here signs that login out\./);
  await fillJoin();
  await d.click(d.button('Create Account'));
  await d.tick(20);
  const auths = client.calls.filter(c => c.auth).map(c => c.auth);
  assert.deepEqual(auths, ['signOut', 'signIn'], 'the staff login is signed out first, then the new one signs in');
  assert.deepEqual(client.calls.find(c => c.auth === 'signOut').opts, { scope: 'local' }, 'on this device only');
  assert.equal(rpcs(client, 'complete_affiliate_onboarding').length, 1);
  assert.equal(where(), '/affiliate/dashboard');
  assert.doesNotMatch(d.text(), /signed in as staff/i);
});

test('S: the staff screen comes from the server (STAFF_ACCOUNT), not from what the app last knew', async () => {
  const client = backend({ signedIn: true, fail: { complete_affiliate_onboarding:
    'STAFF_ACCOUNT: This is a staff login, so it cannot also be an affiliate account.' } });
  await d.mount(app('/affiliate/verify'));
  await d.tick(20);
  assert.equal(rpcs(client, 'complete_affiliate_onboarding').length, 1, 'the server is asked');
  assert.match(d.text(), /You are signed in as staff/);
  assert.equal(where(), '/affiliate/verify');
});

test('F: a link that could not verify the email lands on the Account page, which says so and offers a new one', async () => {
  const client = backend({ signedIn: true, hasAccount: true, amr: 'magiclink',
    confirm: () => ({ verified: false, reason: 'not_from_email_link' }) });
  await d.mount(app('/affiliate/verify'));
  await d.tick(20);
  assert.equal(rpcs(client, 'confirm_affiliate_email').length, 1);
  assert.equal(where(), '/affiliate/account');
  assert.equal(document.querySelector('[data-email-verified]')?.textContent, 'Not verified');
  const section = document.querySelector('[data-section="verify-email"]');
  assert.match(section?.querySelector('[data-note="verify-failed"]')?.textContent ?? '', /We could not verify your email from that link\. Send a new one\./);
  assert.ok(d.button('Send verification email', section));
});

test('F: a verify page with no session asks the person to sign in (not to edit their details)', async () => {
  const client = backend();
  await d.mount(app('/affiliate/verify'));
  await d.tick(10);
  assert.match(document.querySelector('[data-state="signed-out"]')?.textContent ?? '', /Sign in to finish setting up/);
  assert.ok([...document.querySelectorAll('a')].some(a => a.textContent === 'Sign in' && a.getAttribute('href') === '/affiliate/login'));
  assert.equal(d.button('Edit name or phone number'), undefined);
  assert.equal(rpcs(client, 'complete_affiliate_onboarding').length, 0);
});

test('F: Send on a stale Account page, the email verified meanwhile: says so, and shows Verified', async () => {
  const client = backend({ signedIn: true, hasAccount: true, resend: () => {
    client.tables.affiliate_accounts[0].email_verified_at = '2026-10-21T04:00:00Z';   // verified in another tab
    return { data: { ok: true, status: 'submitted', request_id: 'r3' }, error: null };
  } });
  await d.mount(app('/affiliate/account'));
  await d.tick(10);
  assert.equal(document.querySelector('[data-email-verified]')?.textContent, 'Not verified');
  await d.click(d.button('Send verification email', document.querySelector('[data-section="verify-email"]')));
  await d.tick(5);
  assert.equal(document.querySelector('[data-email-verified]')?.textContent, 'Verified');
  assert.match(document.querySelector('[data-note="email-verified"]')?.textContent ?? '', /Your email is already verified\./);
  assert.doesNotMatch(d.text(), /on its way/);
});

test('F: a status read that fails is said, with Try again', async () => {
  const client = backend({ signedIn: true, hasAccount: true });
  const realFrom = client.from;
  let failures = 1;
  client.from = table => {
    const q = realFrom(table);
    const realSelect = q.select.bind(q);
    q.select = cols => {
      if (String(cols).includes('email_verified_at') && failures > 0) {
        failures -= 1;
        q.exec = async () => ({ data: null, error: { message: 'Failed to fetch' } });
      }
      return realSelect(cols);
    };
    return q;
  };
  await d.mount(app('/affiliate/account'));
  await d.tick(10);
  assert.match(document.querySelector('[data-email-verified="error"]')?.textContent ?? '', /Could not check your email status\./);
  await d.click(d.button('Try again'));
  await d.tick(5);
  assert.equal(document.querySelector('[data-email-verified]')?.textContent, 'Not verified');
});

test('F: a fresh link counts on a device whose clock is a few minutes slow; an old one or a password does not', () => {
  const now = 1_800_000_000;
  const t = (method, at) => tokenWith({ sub: UID, amr: [{ method, timestamp: at }] });
  assert.equal(sessionFromEmailLink(t('magiclink', now + 180), now), true, 'opened now, the device 3 minutes slow');
  assert.equal(sessionFromEmailLink(t('magiclink', now - 5 * 60), now), true);
  assert.equal(sessionFromEmailLink(t('magiclink', now + 15 * 60), now), false, 'not from far in the future');
  assert.equal(sessionFromEmailLink(t('magiclink', now - 60 * 60), now), false, 'not an hour ago');
  assert.equal(sessionFromEmailLink(t('password', now), now), false);
});
