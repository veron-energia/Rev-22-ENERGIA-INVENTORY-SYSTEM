// The app shell, rendered for real against a fake backend (429:
// ADMIN-AUTH-8, -14, -18, CUSTOMERS-M2).
//
//   * signing in shows the loader until the account is read, not "Account
//     setup needed"; the hourly token refresh does not read it again; a
//     background re-read that fails keeps the page; the setup card has Try
//     again; a failed re-read of a login with no staff or affiliate account
//     yet (onboarding, a pending invitee) shows the connection error, not
//     the verify page or "deactivated";
//   * the menu: aria-expanded on its button, inert while the drawer is shut
//     (only on a narrow screen), Health Surveys hidden for Inventory Managers;
//   * a page file gone after a deploy: the page alone shows "A newer version of
//     the app is ready" with Reload, the menu stays, and another page starts
//     afresh; the app reloads itself once, never in a loop;
//   * vercel.json no longer answers a missing /assets file with the app.
// Every name and address is made up.
//
// Run: node --test scripts/ui/tests/app-shell.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { setupDom, bundle, fakeSupabase, driver } from '../page-harness.mjs';

const dom = setupDom();
let drawer = true;
dom.window.matchMedia = () => ({ matches: drawer, addEventListener() {}, removeEventListener() {} });
const mod = await bundle(`
  import React from 'react';
  import { Navigate, useNavigate } from 'react-router-dom';
  import { useAuth } from './src/context/AuthContext';
  // As App.tsx routes /login: a signed-in session goes on to the dashboard.
  export function LoginRoute() {
    const { session } = useAuth();
    return session ? React.createElement(Navigate, { to: '/', replace: true })
                   : React.createElement('div', { id: 'login' }, 'sign in');
  }
  // As AffiliateVerifyPage ends onboarding: read the account again, then go on.
  export function Verify() {
    const { refreshProfile } = useAuth();
    const nav = useNavigate();
    const go = async () => { await refreshProfile(); nav('/affiliate/dashboard', { replace: true }); };
    return React.createElement('div', { id: 'verify' },
      React.createElement('button', { onClick: () => void go() }, 'Finish onboarding'));
  }
  export { AuthProvider } from './src/context/AuthContext';
  export { Protected, AffiliateProtected } from './src/components/RouteGuards';
  export { ErrorBoundary } from './src/components/ErrorBoundary';
  export * as stale from './src/lib/staleChunks';
  export { MemoryRouter, Routes, Route } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`);
const { React, AuthProvider, Protected, MemoryRouter, Routes, Route, stale } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });
const h = React.createElement;

const SESSION = { access_token: 'x.y.z', user: { id: 'u-stf', email: 'sara@sig.invalid' } };
const profile = (role = 'staff') => ({ id: 'u-stf', full_name: 'Sara Test', role, is_active: true, email: 'sara@sig.invalid',
  invitation_status: 'accepted', deleted_at: null });
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };

function Boom() { throw new Error('Failed to fetch dynamically imported module: https://energia.invalid/assets/UsersPage-old.js'); }
function app(sb, { start = '/' } = {}) {
  globalThis.__supabase = sb;
  return h(AuthProvider, null, h(MemoryRouter, { initialEntries: [start] }, h(Routes, null,
    h(Route, { path: '/login', element: h(mod.LoginRoute) }),
    h(Route, { path: '/', element: h(Protected, null, h('div', { id: 'page' }, 'the dashboard')) }),
    h(Route, { path: '/users', element: h(Protected, null, h(Boom)) }))));
}
const backend = (role, over = {}) => fakeSupabase({
  tables: { profiles: [profile(role)], user_store_assignments: [], ...over.tables }, fail: over.fail ?? {}, gate: over.gate ?? {},
});
const profileReads = sb => sb.calls.filter(c => c.table === 'profiles' && c.op === 'select').length;

test('signing in shows the loader while the account is read, not "Account setup needed"', async () => {
  const sb = backend('staff');
  await d.mount(app(sb));
  assert.ok(document.getElementById('login'), 'no session: the sign-in page');
  const slow = deferred();
  sb.gate.profiles = slow.promise;
  await mod.act(async () => { sb.emit('SIGNED_IN', SESSION); });
  await d.tick(3);
  // Signed in, on the dashboard's route, with the account still being read.
  assert.ok(!document.getElementById('login'));
  assert.ok(!d.text().includes('Account setup needed'), 'the setup card does not flash (before 429 it did)');
  assert.ok(d.text().includes('Loading…'), 'the loader shows meanwhile');
  slow.resolve(); delete sb.gate.profiles;
  await d.tick();
  assert.ok(document.getElementById('page'), d.text());
});

test('the hourly token refresh does not read the account again; a failed background re-read keeps the page', async () => {
  const sb = backend('staff');
  sb.auth.session = SESSION;
  await d.mount(app(sb));
  assert.ok(document.getElementById('page'));
  const reads = profileReads(sb);
  await mod.act(async () => { sb.emit('TOKEN_REFRESHED', SESSION); });
  await d.tick();
  assert.equal(profileReads(sb), reads, 'not read again on a token refresh');
  sb.fail.profiles = 'Failed to fetch';
  await mod.act(async () => { sb.emit('SIGNED_IN', SESSION); });   // a tab coming back into view
  await d.tick();
  assert.ok(profileReads(sb) > reads, 'read again in the background');
  assert.ok(document.getElementById('page'), 'the page stays (before 429 it became "Account setup needed")');
  assert.ok(!d.text().includes('Account setup needed'));
});

test('a first read that fails shows the setup card with Try again, which reads again', async () => {
  const sb = backend('staff', { fail: { profiles: 'Failed to fetch' } });
  sb.auth.session = SESSION;
  await d.mount(app(sb));
  assert.ok(d.text().includes('Account setup needed') && d.text().includes('could not reach the server'));
  sb.fail.profiles = undefined;
  await d.click(d.button('Try again'));
  assert.ok(document.getElementById('page'), d.text());
});

test('a login with no account yet whose re-read fails shows the error, not the verify page', async () => {
  const AFF = { access_token: 'x.y.z', user: { id: 'u-new', email: 'new@sig.invalid' } };
  const sb = fakeSupabase({ tables: { profiles: [], affiliate_accounts: [], user_store_assignments: [] } });
  sb.auth.session = AFF;
  globalThis.__supabase = sb;
  await d.mount(h(AuthProvider, null, h(MemoryRouter, { initialEntries: ['/affiliate/verify'] }, h(Routes, null,
    h(Route, { path: '/affiliate/verify', element: h(mod.Verify) }),
    h(Route, { path: '/affiliate/dashboard', element: h(mod.AffiliateProtected, null, h('div', { id: 'dash' }, 'the portal')) })))));
  assert.ok(document.getElementById('verify'), 'loaded as neither: onboarding');
  // Onboarding finished on the server; reading the account again hits a blip.
  sb.fail.profiles = 'Failed to fetch';
  await d.click(d.button('Finish onboarding'));
  assert.ok(!document.getElementById('verify'), 'not sent back to verify (before the fix it was)');
  assert.ok(d.text().includes('Could not load your account') && d.text().includes('could not reach the server'), d.text());
  // Try again, with the connection back and the account now made, opens the portal.
  sb.fail.profiles = undefined;
  sb.tables.affiliate_accounts.push({ id: 'aa-1', auth_user_id: 'u-new', customer_id: 'c-1', affiliate_id: null, status: 'claimed' });
  await d.click(d.button('Try again'));
  assert.ok(document.getElementById('dash'), d.text());
});

test('a pending invitee whose re-read fails is told the connection failed, not "deactivated"', async () => {
  const pending = { ...profile('staff'), is_active: false, invitation_status: 'pending' };
  const sb = backend('staff', { tables: { profiles: [pending] } });
  sb.auth.session = SESSION;
  await d.mount(app(sb));
  assert.ok(d.text().includes('Your account has been deactivated'), 'before accepting: switched off');
  // The invitation is accepted on the server; reading the account again fails.
  pending.is_active = true; pending.invitation_status = 'accepted';
  sb.fail.profiles = 'Failed to fetch';
  await d.click(d.button('Try again'));
  assert.ok(d.text().includes('could not reach the server'), d.text());
  assert.ok(!d.text().includes('deactivated'), 'the old "deactivated" is not kept (before the fix it was)');
  sb.fail.profiles = undefined;
  await d.click(d.button('Try again'));
  assert.ok(document.getElementById('page'), d.text());
});

test('the menu: aria-expanded, inert while the drawer is shut, and never inert on a wide screen', async () => {
  drawer = true;
  const sb = backend('staff');
  sb.auth.session = SESSION;
  await d.mount(app(sb));
  const menu = d.button('Menu');
  const aside = document.getElementById('app-sidebar');
  assert.equal(menu.getAttribute('aria-expanded'), 'false');
  assert.equal(menu.getAttribute('aria-controls'), 'app-sidebar');
  assert.ok(aside.hasAttribute('inert'), 'a shut drawer cannot be reached by keyboard');
  await d.click(menu);
  assert.equal(menu.getAttribute('aria-expanded'), 'true');
  assert.ok(!aside.hasAttribute('inert'));
  drawer = false;
  await d.mount(app(sb));
  assert.ok(!document.getElementById('app-sidebar').hasAttribute('inert'), 'the wide menu is always usable');
  drawer = true;
});

test('Health Surveys is hidden for Inventory Managers and shown to Staff', async () => {
  const links = () => [...document.querySelectorAll('#app-sidebar a')].map(a => a.textContent.trim());
  const staff = backend('staff'); staff.auth.session = SESSION;
  await d.mount(app(staff));
  assert.ok(links().includes('Health Surveys'));
  const inv = backend('inventory_manager'); inv.auth.session = SESSION;
  await d.mount(app(inv));
  assert.ok(links().length > 0 && !links().includes('Health Surveys'), links().join(','));
});

test('a page file gone after a deploy: the page says so with Reload, the menu stays, another page starts afresh', async () => {
  const sb = backend('owner');
  sb.auth.session = SESSION;
  await d.mount(app(sb, { start: '/users' }));
  assert.ok(d.text().includes('A newer version of the app is ready'), d.text());
  // Work saved on another page is not lost; the card must not say otherwise.
  assert.ok(d.text().includes('Anything you saved before is kept.'));
  assert.ok(!d.text().includes('Nothing has been saved'));
  assert.ok(d.button('Reload page'));
  assert.ok(document.getElementById('app-sidebar'), 'the menu stays');
  await d.click([...document.querySelectorAll('#app-sidebar a')].find(a => a.textContent.trim() === 'Dashboard'));
  assert.ok(document.getElementById('page'), 'another page starts afresh');
  assert.ok(!d.text().includes('A newer version'));
});

test('the app reloads itself once for a new build, never in a loop', () => {
  const fake = () => {
    const store = new Map(); let reloads = 0; const listeners = {};
    return {
      sessionStorage: { getItem: k => store.get(k) ?? null, setItem: (k, v) => store.set(k, v) },
      location: { reload: () => { reloads++; } },
      addEventListener: (t, f) => { listeners[t] = f; },
      fire(t, e) { listeners[t]?.(e); },
      get reloads() { return reloads; },
    };
  };
  const w = fake();
  assert.equal(stale.reloadForNewVersion(w, 1_000_000), true);
  assert.equal(stale.reloadForNewVersion(w, 1_005_000), false, 'not again within a few seconds');
  assert.equal(stale.reloadForNewVersion(w, 1_011_000), true, 'later, a new deploy may reload again');
  assert.equal(w.reloads, 2);
  const noStorage = { ...fake(), sessionStorage: { getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); } } };
  assert.equal(stale.reloadForNewVersion(noStorage), false, 'no storage: no unguarded reload');
  const v = fake();
  stale.reloadOnStaleChunks(v);
  let prevented = false;
  v.fire('vite:preloadError', { preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
  assert.equal(v.reloads, 1);
  assert.equal(stale.isChunkLoadError(new TypeError('Failed to fetch dynamically imported module: x.js')), true);
  assert.equal(stale.isChunkLoadError(new Error('Importing a module script failed.')), true);
  assert.equal(stale.isChunkLoadError(new Error('x is not a function')), false);
});

test('a page file that fails once is fetched again; any other error is shown as it was', async () => {
  let n = 0;
  const Page = stale.lazyPage(async () => {
    n++;
    if (n === 1) throw new TypeError('Failed to fetch dynamically imported module: page.js');
    return { default: () => h('div', { id: 'lazy' }, 'loaded') };
  });
  await d.mount(h(React.Suspense, { fallback: h('div', null, 'loading') }, h(Page)));
  await d.tick();
  assert.ok(document.getElementById('lazy'), 'loaded on the second try');
  assert.equal(n, 2);
  const Broken = stale.lazyPage(async () => { throw new Error('x is not a function'); });
  await d.mount(h(mod.ErrorBoundary, null, h(React.Suspense, { fallback: h('div', null, 'loading') }, h(Broken))));
  await d.tick();
  assert.ok(d.text().includes('Something went wrong') && d.text().includes('x is not a function'));
});

test('vercel.json sends every page to the app, but not a missing /assets file', () => {
  const config = JSON.parse(readFileSync('vercel.json', 'utf8'));
  assert.equal(config.rewrites.length, 1);
  const { source, destination } = config.rewrites[0];
  assert.equal(destination, '/index.html');
  const re = new RegExp(`^${source}$`);
  for (const p of ['/', '/users', '/affiliate/dashboard', '/survey/abc', '/reset-password']) assert.ok(re.test(p), p);
  for (const p of ['/assets/UsersPage-abc123.js', '/assets/index-xyz.css']) assert.ok(!re.test(p), p);
});

test('main.tsx installs the reload, and App.tsx loads every page through lazyPage', () => {
  assert.match(readFileSync('src/main.tsx', 'utf8'), /reloadOnStaleChunks\(\);/);
  const app = readFileSync('src/App.tsx', 'utf8');
  assert.doesNotMatch(app, /React\.lazy\(/);
  assert.ok((app.match(/= lazyPage\(\(\) => import\(/g) ?? []).length >= 40);
  assert.match(app, /<ErrorBoundary resetKey=\{location\.pathname\}>/);
});
