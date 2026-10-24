// An affiliate sign-up with the email or phone of an existing affiliate is sent
// to Sign in (466; the Owner, 24 Oct 2026), the pages rendered for real
// against a fake backend: the real Join and Login pages under a router.
//
//   R  Create Account answered "affiliate_exists" (the phone of one affiliate,
//      of several, or another email of hers) or "email_in_use": the page goes
//      straight to /affiliate/login, which says why on top (with the masked
//      login email when the server gave one), fills in the email only when
//      it was that email (email_in_use), and nothing signs in or is made.
//      An older sign-up function's email_in_use (no "matched") reads the
//      same. Signing in from there goes on as usual.
//   W  The words come from the page's own copy and fixed codes: a server
//      message is not shown on the Sign in page, a hint that is not the mask
//      is left out (no markup), and the address bar cannot put a message or a
//      hint there; router state of the wrong shape shows nothing.
//   O  Any other answer (rate limited, a field refused) stays on the form.
//   A  The message is an alert (a screen reader says it on arrival), and
//      "Reset password" sits under the message, not beside it (one child in
//      the .alert flex row).
//   B  Back from Sign in brings the Join form back as it was typed (name,
//      phone, email, and the address's query), without the passwords or the
//      terms tick; sending it again sends the same details.
//
// Every name, phone and email is invented (ACMA fictional numbers, @example.com).
// Run: node --test scripts/affiliate-signup/tests/existing-affiliate-pages-466.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { setupDom, bundle, fakeSupabase, driver, tokenWith } from '../../ui/page-harness.mjs';

const dom = setupDom('https://energia.invalid/affiliate/join');
const mod = await bundle(`
  import React from 'react';
  export { default as AffiliateJoinPage } from './src/pages/AffiliateJoinPage';
  export { default as AffiliateLoginPage } from './src/pages/AffiliateLoginPage';
  export { AuthProvider } from './src/context/AuthContext';
  export { MemoryRouter, Routes, Route, useLocation, useNavigate } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };`);
const { React, AffiliateJoinPage, AffiliateLoginPage, AuthProvider, MemoryRouter, Routes, Route, useLocation, useNavigate } = mod;
const d = driver(mod, dom);
const h = React.createElement;
after(async () => { await d.unmount(); dom.window.close(); });

const UID = '00000000-0000-4000-8000-000000000466';
const EMAIL = 'ava-466@example.com';
const PASSWORD = 'a-long-password-466';

/** The portal's routes, with stand-ins for the pages these tests do not open. */
function app(start) {
  const Where = () => {
    const loc = useLocation();
    return h('output', { 'data-where': loc.pathname, 'data-search': loc.search });
  };
  // The browser's Back button.
  const Back = () => {
    const nav = useNavigate();
    return h('button', { type: 'button', 'aria-label': 'Browser back', onClick: () => nav(-1) }, '<');
  };
  return h(MemoryRouter, { initialEntries: [start] },
    h(AuthProvider, null,
      h(Where),
      h(Back),
      h(Routes, null,
        h(Route, { path: '/affiliate/join', element: h(AffiliateJoinPage) }),
        h(Route, { path: '/affiliate/login', element: h(AffiliateLoginPage) }),
        h(Route, { path: '/affiliate/verify', element: h('p', null, 'VERIFY PAGE') }),
        h(Route, { path: '/affiliate/forgot-password', element: h('p', null, 'FORGOT PAGE') }),
        h(Route, { path: '/affiliate/dashboard', element: h('p', null, 'DASHBOARD') }))));
}
const where = () => document.querySelector('[data-where]')?.getAttribute('data-where');
const search = () => document.querySelector('[data-where]')?.getAttribute('data-search');

/** What the sign-up function answers with a status and body, as functions.invoke reports a non-2xx. */
const answer = (status, body) => () => (status >= 200 && status < 300
  ? { data: body, error: null }
  : { data: null, error: { context: new Response(JSON.stringify(body), { status }) } });

function backend(signup, { hasAccount = true } = {}) {
  const listeners = [];
  const session = () => ({
    access_token: tokenWith({ sub: UID, role: 'authenticated', amr: [{ method: 'password', timestamp: Math.floor(Date.now() / 1000) }] }),
    user: { id: UID, email: EMAIL, user_metadata: {} },
  });
  const auth = {
    session: null,
    getSession: async () => ({ data: { session: auth.session } }),
    onAuthStateChange: cb => { listeners.push(cb); return { data: { subscription: { unsubscribe() {} } } }; },
    signInWithPassword: async ({ email, password }) => {
      client.calls.push({ auth: 'signIn', email, password });
      auth.session = session();
      listeners.forEach(l => l('SIGNED_IN', auth.session));
      return { data: { user: auth.session.user, session: auth.session }, error: null };
    },
    signOut: async () => { auth.session = null; listeners.forEach(l => l('SIGNED_OUT', null)); return {}; },
    refreshSession: async () => ({ data: {} }),
  };
  const client = fakeSupabase({
    auth,
    tables: {
      profiles: [],
      affiliate_accounts: hasAccount ? [{ id: 'acct-466', auth_user_id: UID, customer_id: 'cust-466', affiliate_id: 'aff-466', status: 'claimed' }] : [],
    },
    rpc: { complete_affiliate_onboarding: () => ({ status: 'active', customer_id: 'cust-466', already: false }) },
    invoke: { 'auth-signup-request': signup },
  });
  globalThis.__supabase = client;
  return client;
}
const made = client => ({
  signIns: client.calls.filter(c => c.auth === 'signIn').length,
  onboarding: client.calls.filter(c => c.rpc === 'complete_affiliate_onboarding').length,
});

async function fillJoin(email = EMAIL) {
  const inputs = [...document.querySelectorAll('input')];
  await d.setValue(inputs[0], 'Ava');
  await d.setValue(inputs[1], 'Testaffiliate');
  await d.setValue(document.querySelector('input[type="tel"]'), '+61 491 570 471');
  await d.setValue(document.querySelector('input[type="email"]'), email);
  const pw = [...document.querySelectorAll('input[type="password"]')];
  await d.setValue(pw[0], PASSWORD);
  await d.setValue(pw[1], PASSWORD);
  await d.toggle(document.querySelector('input[type="checkbox"]'));
}
const notice = () => document.querySelector('[data-state="signup-existing"]');
const emailField = () => document.querySelector('input[type="email"]');

test('R: the phone of one existing affiliate: straight to Sign in, with her masked login email, nothing filled in, nothing made', async () => {
  const client = backend(answer(409, { error: 'affiliate_exists', matched: 'phone', email_hint: 's•••@rev22.com.sg',
    message: 'This phone number already has an Energia affiliate account, which signs in with s•••@rev22.com.sg. Sign in with that email, or reset your password if you have forgotten it.',
    request_id: 'r1' }));
  await d.mount(app('/affiliate/join'));
  await fillJoin('someone-new-466@example.com');
  await d.click(d.button('Create Account'));
  assert.equal(where(), '/affiliate/login');
  assert.equal(notice()?.getAttribute('data-reason'), 'affiliate_phone');
  assert.equal(notice().querySelector('p').textContent,
    'This phone number already has an Energia affiliate account, which signs in with s•••@rev22.com.sg. Sign in with that email, or reset your password if you have forgotten it.');
  assert.equal(emailField().value, '', 'the email typed is not filled in (it is not her login)');
  assert.ok([...notice().querySelectorAll('a')].some(a => a.textContent.trim() === 'Reset password' && a.getAttribute('href') === '/affiliate/forgot-password'));
  assert.deepEqual(made(client), { signIns: 0, onboarding: 0 });
  // The message is above the form.
  const first = document.querySelector('[data-state="signup-existing"], input[type="email"]');
  assert.equal(first, notice());
});

test('A: the message is an alert, and "Reset password" sits under the message (one child in the .alert row)', async () => {
  for (const body of [
    { error: 'affiliate_exists', matched: 'phone', email_hint: 's•••@rev22.com.sg', message: 'x', request_id: 'r1' },
    { error: 'affiliate_exists', matched: 'email', message: 'x', request_id: 'r3' },
    { error: 'email_in_use', matched: 'email', message: 'x', request_id: 'r4' },
  ]) {
    backend(answer(409, body));
    await d.mount(app('/affiliate/join'));
    await fillJoin('someone-new-466@example.com');
    await d.click(d.button('Create Account'));
    assert.equal(where(), '/affiliate/login');
    assert.equal(notice().getAttribute('role'), 'alert', 'announced on arrival');
    assert.ok(notice().classList.contains('alert'));
    assert.equal(notice().children.length, 1, 'one child in the flex row');
    const inner = notice().children[0];
    assert.deepEqual([...inner.children].map(c => c.tagName), ['P', 'A']);
    assert.equal(inner.style.flex, '1 1 0%');
    assert.equal(inner.querySelector('a').textContent.trim(), 'Reset password');
  }
});

test('B: Back from Sign in brings the form back as typed, without the passwords or the terms tick', async () => {
  let n = 0;
  const bodies = [];
  const client = backend(body => {
    bodies.push(body);
    n += 1;
    return n === 1
      ? answer(409, { error: 'affiliate_exists', matched: 'phone', email_hint: 's•••@rev22.com.sg', message: 'x', request_id: 'r6' })()
      : answer(429, { error: 'rate_limited', message: 'Too many attempts just now. Please try again in about 7 minutes.', retry_after_seconds: 420 })();
  });
  await d.mount(app('/affiliate/join?utm_source=t466'));
  await fillJoin('someone-new-466@example.com');
  await d.click(d.button('Create Account'));
  assert.equal(where(), '/affiliate/login');
  await d.click(d.button('Browser back'));
  assert.equal(where(), '/affiliate/join');
  assert.equal(search(), '?utm_source=t466', 'the address the person came from is kept');
  const inputs = [...document.querySelectorAll('input')];
  assert.equal(inputs[0].value, 'Ava');
  assert.equal(inputs[1].value, 'Testaffiliate');
  assert.match(document.querySelector('input[type="tel"]').value, /491 570 471/);
  assert.equal(emailField().value, 'someone-new-466@example.com');
  assert.deepEqual([...document.querySelectorAll('input[type="password"]')].map(i => i.value), ['', ''], 'no password kept');
  assert.equal(document.querySelector('input[type="checkbox"]').checked, false, 'the terms are agreed again');
  // Sent again (passwords and terms given again): the same details.
  const pw = [...document.querySelectorAll('input[type="password"]')];
  await d.setValue(pw[0], PASSWORD);
  await d.setValue(pw[1], PASSWORD);
  await d.toggle(document.querySelector('input[type="checkbox"]'));
  await d.click(d.button('Create Account'));
  assert.equal(bodies.length, 2);
  assert.deepEqual(bodies[1], bodies[0]);
  assert.equal(where(), '/affiliate/join');
  assert.deepEqual(made(client), { signIns: 0, onboarding: 0 });
  // Nothing is kept in the address bar.
  assert.doesNotMatch(search(), /someone|Ava|491/);
});

test('B: a draft of the wrong shape in the history entry fills in nothing it should not', async () => {
  backend(answer(200, {}));
  await d.mount(app({ pathname: '/affiliate/join', state: { joinDraft: { first: 7, last: { x: 1 }, email: 'x'.repeat(400), password: 'secret-466', confirm: 'secret-466' } } }));
  const inputs = [...document.querySelectorAll('input')];
  assert.equal(inputs[0].value, '');
  assert.equal(inputs[1].value, '');
  assert.equal(emailField().value.length, 254);
  assert.deepEqual([...document.querySelectorAll('input[type="password"]')].map(i => i.value), ['', '']);
});

test('R: a phone several affiliates share: no hint, sign in with the email they used', async () => {
  backend(answer(409, { error: 'affiliate_exists', matched: 'phone', message: 'x', request_id: 'r2' }));
  await d.mount(app('/affiliate/join'));
  await fillJoin('someone-new-466@example.com');
  await d.click(d.button('Create Account'));
  assert.equal(where(), '/affiliate/login');
  assert.equal(notice().querySelector('p').textContent,
    'This phone number already has an Energia affiliate account. Sign in with the email you used for it, or reset your password if you have forgotten it.');
  assert.equal(emailField().value, '');
});

test('R: another email of an affiliate (her record\'s): Sign in, with the hint, nothing filled in', async () => {
  backend(answer(409, { error: 'affiliate_exists', matched: 'email', email_hint: 'a•••@example.com', message: 'x', request_id: 'r3' }));
  await d.mount(app('/affiliate/join'));
  await fillJoin('ava-record-466@example.com');
  await d.click(d.button('Create Account'));
  assert.equal(where(), '/affiliate/login');
  assert.equal(notice()?.getAttribute('data-reason'), 'affiliate_email');
  assert.equal(notice().querySelector('p').textContent,
    'This email is already on an Energia affiliate account, which signs in with a•••@example.com. Sign in with that email, or reset your password if you have forgotten it.');
  assert.equal(emailField().value, '');
});

test('R: email_in_use (466\'s, and an older sign-up function\'s without "matched"): Sign in with the email filled in, then signing in goes on as usual', async () => {
  for (const body of [
    { error: 'email_in_use', matched: 'email', message: 'This email already has an Energia login. Sign in, or reset your password if you have forgotten it.', request_id: 'r4' },
    { error: 'email_in_use', message: 'This email already has an Energia login. Sign in, or reset your password if you have forgotten it.' },
  ]) {
    const client = backend(answer(409, body));
    await d.mount(app('/affiliate/join'));
    await fillJoin();
    await d.click(d.button('Create Account'));
    assert.equal(where(), '/affiliate/login');
    assert.equal(notice()?.getAttribute('data-reason'), 'email_in_use');
    assert.equal(notice().querySelector('p').textContent,
      'This email already has an Energia login. Sign in, or reset your password if you have forgotten it.');
    assert.equal(emailField().value, EMAIL, 'the email is filled in');
    assert.equal(document.querySelector('input[type="password"]').value, '', 'the password is never carried over');
    assert.deepEqual(made(client), { signIns: 0, onboarding: 0 });
    await d.setValue(document.querySelector('input[type="password"]'), PASSWORD);
    await d.click(d.button('Sign In'));
    await d.tick(10);
    assert.deepEqual(client.calls.filter(c => c.auth === 'signIn').map(c => c.email), [EMAIL]);
    assert.equal(where(), '/affiliate/dashboard');
  }
});

test('W: the Sign in page shows its own words: not the server\'s message, and not a hint that is not the mask', async () => {
  for (const [hint, words] of [
    ['<img src=x onerror=alert(1)>', 'This phone number already has an Energia affiliate account. Sign in with the email you used for it, or reset your password if you have forgotten it.'],
    ['sam@example.com', 'This phone number already has an Energia affiliate account. Sign in with the email you used for it, or reset your password if you have forgotten it.'],
  ]) {
    backend(answer(409, { error: 'affiliate_exists', matched: 'phone', email_hint: hint, message: 'HACKED: call 0000', request_id: 'r5' }));
    await d.mount(app('/affiliate/join'));
    await fillJoin('someone-new-466@example.com');
    await d.click(d.button('Create Account'));
    assert.equal(where(), '/affiliate/login');
    assert.equal(notice().querySelector('p').textContent, words);
    assert.doesNotMatch(d.text(), /HACKED|sam@example\.com/);
    assert.equal(document.querySelector('img'), null, 'no markup');
  }
});

test('W: the address bar cannot put a message or a hint on the Sign in page; state of the wrong shape shows nothing', async () => {
  backend(answer(200, {}));
  await d.mount(app('/affiliate/login?reason=affiliate_phone&email_hint=s%E2%80%A2%E2%80%A2%E2%80%A2%40evil.example&message=Call%20us&email=victim%40example.com'));
  assert.equal(notice(), null);
  assert.equal(emailField().value, '');
  assert.doesNotMatch(d.text(), /Call us|evil\.example/);
  for (const state of [
    null, 'affiliate_phone', { reason: 'affiliate_phone' }, { signupRefused: { reason: 'free text' } },
    { signupRefused: { reason: 'Call us on 0000', emailHint: 's•••@example.com' } },
  ]) {
    await d.mount(app({ pathname: '/affiliate/login', state }));
    assert.equal(notice(), null, JSON.stringify(state));
  }
  // A hint is shown only for an affiliate's email or phone; the email is filled in only for email_in_use.
  await d.mount(app({ pathname: '/affiliate/login', state: { signupRefused: { reason: 'email_in_use', emailHint: 's•••@example.com', email: EMAIL } } }));
  assert.doesNotMatch(notice().textContent, /s•••@example\.com/);
  assert.equal(emailField().value, EMAIL);
  await d.mount(app({ pathname: '/affiliate/login', state: { signupRefused: { reason: 'affiliate_phone', emailHint: 's•••@example.com', email: EMAIL } } }));
  assert.match(notice().textContent, /which signs in with s•••@example\.com/);
  assert.equal(emailField().value, '');
  await d.mount(app({ pathname: '/affiliate/login', state: { signupRefused: { reason: 'email_in_use', emailHint: null, email: `${'x'.repeat(250)}@example.com` } } }));
  assert.equal(emailField().value, '', 'an email longer than an address can be is not filled in');
});

test('O: any other answer stays on the form, as before', async () => {
  backend(answer(429, { error: 'rate_limited', message: 'Too many attempts just now. Please try again in about 7 minutes.', retry_after_seconds: 420 }));
  await d.mount(app('/affiliate/join'));
  await fillJoin();
  await d.click(d.button('Create Account'));
  assert.equal(where(), '/affiliate/join');
  assert.match(d.text(), /Too many attempts just now/);
  backend(answer(409, { error: 'affiliate_exists', matched: 'name', message: 'Not a known match' }));
  await d.mount(app('/affiliate/join'));
  await fillJoin();
  await d.click(d.button('Create Account'));
  assert.equal(where(), '/affiliate/join', 'an answer of the wrong shape is not a redirect');
  assert.equal(notice(), null);
});
