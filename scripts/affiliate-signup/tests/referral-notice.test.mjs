// 484, push #2 (the Owner, 1 Nov 2026, Q1): the /r/ page tells a person, under each card's Phone field and above its
// button, what the affiliate who invited them will see, and tells the database which notice it showed, rendered for
// real against a fake backend.
//
//   T  The wording, word for word: with the inviter's first name (public_affiliate_referral_info's affiliate_name,
//      trimmed) and without it (none, blank, not text, or still loading). One version names both forms, and its
//      md5 is pinned, so a changed wording without a new version fails. 484's affiliate_referral_signup_with_notice
//      lists that version (c_notices), so the database records the sign-up as told, and the newest migration that
//      defines it takes exactly the seven keys the page sends (a key it lacks would be a silent PGRST202 fallback).
//   P  Where it is: in both form cards, right after the Phone field and before the error line and the button. The
//      button's aria-describedby is the notice, and data-notice is the version. It can be seen, with the page's own
//      stylesheet applied: nothing hides it (hidden, aria-hidden, display, visibility, opacity, also on an
//      ancestor), at least 12px, contrast at least 4.5:1; no rule naming .rl-notice hides or shrinks it, @media
//      included. It is a notice, not consent: no tick box anywhere and no "agree".
//   S  The sign-up: exactly the six keys it always sent, plus p_notice (the version), to
//      affiliate_referral_signup_with_notice, also with the unnamed notice and while the link is still being
//      checked. Only on PGRST202 (a database without 484: not applied yet, or undone once the API has reloaded its
//      schema cache) do the same six keys go to affiliate_referral_signup. Every other error shows as before
//      (phoneErrorMessage), with no second call. "Already registered" stays on the page, and a new registration goes
//      to the booking page (referralBookingUrl).
//
// The page is bundled with esbuild and mounted in jsdom. Only the Supabase client is stubbed, and
// referralBookingUrl is wrapped: it records the booking address and hands the page '#booking', so the page's
// navigation stays a hash change in jsdom. Every name, email and phone is invented (@example.invalid, ACMA's
// fictional +61 2 5550 numbers).
//
// Run: node --test scripts/affiliate-signup/tests/referral-notice.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { setupDom, REPO, driver } from '../../ui/page-harness.mjs';
import { REFERRAL_NOTICE_VERSION, referralNotice } from '../../../src/lib/referral/notice.mjs';
import { referralBookingUrl } from '../../../src/lib/referral/bookingLink.mjs';
import { phoneErrorMessage } from '../../../src/lib/customer-phones/normalize.mjs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const md5 = s => createHash('md5').update(s).digest('hex');

// The Owner's two texts (1 Nov 2026, Q1), word for word; {First} is the inviter's first name.
const OWNER_NAMED = 'When you register, {First}, who invited you, will be able to see your name, phone number, bookings and '
  + 'visits, and how much you spend with Energia, in their Energia affiliate account, so they can help you with your visit. '
  + 'They never see your email. If you would rather they did not see your number, tell Energia and we will hide it.';
const OWNER_UNNAMED = 'When you register, the person who invited you will be able to see your name, phone number, bookings and '
  + 'visits, and how much you spend with Energia, in their Energia affiliate account, so they can help you with your visit. '
  + 'They never see your email. If you would rather they did not see your number, tell Energia and we will hide it.';
const named = first => OWNER_NAMED.replace('{First}', first);

// Each version's wording, pinned: the md5 of its named form (with "{First}") and its unnamed form, one per line. A
// changed wording fails here until it gets a NEW version, with a new entry here (never edit an existing one), and
// 484's c_notices (or a later migration's) lists that version before the page sends it.
const WORDINGS = { 'r-page-2026-11': 'be79d8633770ee5017e9c4e849f4cb9b' };
const MIGRATION = 'supabase/484_affiliate_network_shows_tier1_phone.sql';
const SIX = ['p_code', 'p_email', 'p_first_name', 'p_honeypot', 'p_last_name', 'p_phone'];
const SEVEN = [...SIX, 'p_notice'].sort();

const dom = setupDom('https://energia.invalid/');
// The page's own stylesheet (the bundle loads CSS as empty), so getComputedStyle answers for what hides the notice.
const pageCss = dom.window.document.createElement('style');
pageCss.textContent = read('src/styles/referral-landing.css');
dom.window.document.head.appendChild(pageCss);
const realBookingLink = fileURLToPath(new URL('../../../src/lib/referral/bookingLink.mjs', import.meta.url));
const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      export { default as ReferralSignupPage } from './src/pages/ReferralSignupPage';
      export { MemoryRouter, Routes, Route } from 'react-router-dom';
      export { createRoot } from 'react-dom/client';
      export { act } from 'react';
      export { React };`,
    loader: 'tsx', resolveDir: REPO,
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
  loader: { '.css': 'empty' }, logLevel: 'silent',
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{"DEV":false,"VITE_SUPABASE_URL":"x","VITE_SUPABASE_ANON_KEY":"x"}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$|^\.\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const supabase = { rpc: (...a) => globalThis.__backend.rpc(...a) };' }));
    // The page's own import of bookingLink.mjs only; the wrapper below imports the real file.
    b.onResolve({ filter: /(^|\/)lib\/referral\/bookingLink\.mjs$/ }, a => (a.namespace === 'stub' ? undefined : { path: 'bookingLink', namespace: 'stub' }));
    b.onLoad({ filter: /^bookingLink$/, namespace: 'stub' }, () => ({ loader: 'js', resolveDir: REPO, contents: `
      import * as real from ${JSON.stringify(realBookingLink)};
      export const REFERRAL_BOOKING_PAGE = real.REFERRAL_BOOKING_PAGE;
      export const referralBookingPrefix = real.referralBookingPrefix;
      export function referralBookingUrl(booking) {
        globalThis.__bookings.push({ booking: { ...booking }, url: real.referralBookingUrl(booking) });
        return '#booking';
      }` }));
  } }],
});
const mod = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { React, ReferralSignupPage, MemoryRouter, Routes, Route } = mod;
const d = driver(mod, dom);
const h = React.createElement;
after(async () => { await d.unmount(); dom.window.close(); });

const CODE = 'T484NOTE';
const REGISTERED = { data: { ok: true, outcome: 'registered', message: 'Registration successful.', affiliate_label: 'Jane Fixture' }, error: null };
const EXISTING = { data: { ok: true, outcome: 'already_registered',
  message: 'This phone number is already registered with Energia, so no new registration was created. Nothing about your existing record has changed.' }, error: null };
// What PostgREST answers for a function its schema cache does not have (a database without 484).
const NOT_FOUND = fn => ({ data: null, error: { code: 'PGRST202', details: null, hint: null,
  message: `Could not find the function public.${fn} in the schema cache` } });
const failure = (code, message) => ({ data: null, error: code === undefined ? { message } : { code, details: null, hint: null, message } });

/**
 * A backend for the page's three signed-out calls. `info` is public_affiliate_referral_info's answer (held until
 * `infoGate` resolves, when given); `signup[name]` answers each sign-up function, and a function with no answer
 * is one the database does not have (PGRST202). Every call is recorded with a copy of its arguments.
 */
function backend({ info = { valid: true, accepting: true, affiliate_name: 'Jane' }, infoGate = null, signup = {} } = {}) {
  const b = { calls: [] };
  b.rpc = async (name, args) => {
    b.calls.push({ name, args: structuredClone(args) });
    await Promise.resolve();
    if (name === 'public_affiliate_referral_info') {
      if (infoGate) await infoGate;
      return { data: structuredClone(info), error: null };
    }
    return structuredClone(signup[name] ?? NOT_FOUND(name));
  };
  return b;
}
const signups = () => globalThis.__backend.calls.filter(c => c.name.startsWith('affiliate_referral_signup'));

async function open(b) {
  globalThis.__backend = b;
  globalThis.__bookings = [];
  dom.window.history.replaceState(null, '', '/');
  await d.mount(h(MemoryRouter, { initialEntries: [`/r/${CODE}`] },
    h(Routes, null, h(Route, { path: '/r/:referralCode', element: h(ReferralSignupPage) }))));
}
const cards = () => [...document.querySelectorAll('.rl-form-card')];
const notices = () => [...document.querySelectorAll('.rl-notice')];
const ctaOf = card => card.querySelector('button.rl-cta');
/** Type into the top card (both cards share the page's state). */
async function fill({ first = 'Ada', last = 'Fixture', email = 'ada.fixture@example.invalid', phone = '+61 2 5550 9301' } = {}) {
  const card = cards()[0];
  await d.setValue(card.querySelector('input[id$="-first"]'), first);
  await d.setValue(card.querySelector('input[id$="-last"]'), last);
  await d.setValue(card.querySelector('input[id$="-email"]'), email);
  await d.setValue(card.querySelector('.phone-input input'), phone);
}
const errorText = () => [...document.querySelectorAll('.rl-error')].map(e => e.textContent);
const TYPED = { p_code: CODE, p_first_name: 'Ada', p_last_name: 'Fixture', p_phone: '+61255509301', p_email: 'ada.fixture@example.invalid', p_honeypot: null };

const rgb = s => { const m = /^rgba?\((\d+), (\d+), (\d+)(?:, ([\d.]+))?\)$/.exec(s);
  return m && (m[4] === undefined || Number(m[4]) === 1) ? m.slice(1, 4).map(Number) : null; };
const luminance = c => c.map(v => v / 255).map(v => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4))
  .reduce((a, v, i) => a + v * [0.2126, 0.7152, 0.0722][i], 0);
/** The notice can be seen and is read out: nothing hides it, at least 12px, contrast at least 4.5:1. */
function checkVisible(label, notice) {
  assert.ok(!notice.closest('[hidden], [aria-hidden="true"]'), `${label}: not hidden or aria-hidden, nor inside one`);
  for (let e = notice; e; e = e.parentElement) {
    const s = dom.window.getComputedStyle(e);
    assert.notEqual(s.display, 'none', `${label}: displayed (${e.className || e.tagName})`);
    assert.equal(s.visibility, 'visible', `${label}: visible (${e.className || e.tagName})`);
    assert.ok(s.opacity === '' || Number(s.opacity) === 1, `${label}: opaque (${e.className || e.tagName})`);
  }
  const s = dom.window.getComputedStyle(notice);
  assert.match(s.fontSize, /^\d+(\.\d+)?px$/, `${label}: a size in px`);
  assert.ok(parseFloat(s.fontSize) >= 12, `${label}: at least 12px (${s.fontSize})`);
  let bg = null;
  for (let e = notice; e && !bg; e = e.parentElement) bg = rgb(dom.window.getComputedStyle(e).backgroundColor);
  const fg = rgb(s.color);
  assert.ok(fg && bg, `${label}: an opaque text colour on a background`);
  const [hi, lo] = [luminance(fg), luminance(bg)].sort((a, b) => b - a);
  assert.ok((hi + 0.05) / (lo + 0.05) >= 4.5, `${label}: contrast ${((hi + 0.05) / (lo + 0.05)).toFixed(2)}:1, at least 4.5:1`);
}

/** Both cards: the Phone field, then the notice, then (when there is one) the error line, then the button. */
function checkPlacement(label, text, { error = null } = {}) {
  assert.equal(cards().length, 2, `${label}: two form cards`);
  assert.equal(notices().length, 2, `${label}: one notice in each card`);
  for (const [i, idp] of [[0, 'rl-top'], [1, 'rl-end']]) {
    const card = cards()[i];
    const notice = card.querySelector('.rl-notice');
    assert.ok(notice, `${label}: the ${idp} card has the notice`);
    assert.equal(notice.tagName, 'P', `${label}: a plain paragraph`);
    assert.equal(notice.id, `${idp}-notice`, `${label}: its id`);
    assert.equal(document.querySelectorAll(`[id="${notice.id}"]`).length, 1, `${label}: the id is the page's only one`);
    assert.equal(notice.getAttribute('data-notice'), REFERRAL_NOTICE_VERSION, `${label}: data-notice is the version`);
    assert.equal(notice.textContent, text, `${label}: the ${idp} card's text`);
    checkVisible(`${label}: the ${idp} card`, notice);
    const phoneField = notice.previousElementSibling;
    assert.ok(phoneField?.classList.contains('rl-field') && phoneField.querySelector('.phone-input'), `${label}: right after the Phone field`);
    assert.match(phoneField.querySelector('label').textContent, /^Phone/);
    const cta = ctaOf(card);
    if (error === null) assert.equal(notice.nextElementSibling, cta, `${label}: directly before the button`);
    else {
      const line = notice.nextElementSibling;
      assert.ok(line?.classList.contains('rl-error'), `${label}: the error line comes after the notice`);
      assert.equal(line.textContent, error);
      assert.equal(line.nextElementSibling, cta, `${label}: then the button`);
    }
    assert.equal(cta.getAttribute('aria-describedby'), notice.id, `${label}: the ${idp} button is described by its notice`);
  }
}

test('T: the two texts, word for word as the Owner chose them, and the version that names them', () => {
  assert.equal(REFERRAL_NOTICE_VERSION, 'r-page-2026-11');
  assert.equal(referralNotice('Jane'), named('Jane'));
  assert.equal(referralNotice('  Jane \n'), named('Jane'), 'the first name, trimmed');
  assert.equal(referralNotice('Mei-Ling'), named('Mei-Ling'));
  assert.equal(referralNotice('{First}'), OWNER_NAMED);
  for (const none of [undefined, null, '', '   ', ' \t\n ', 0, 42, true, false, {}, ['Jane'], { first: 'Jane' }]) {
    assert.equal(referralNotice(none), OWNER_UNNAMED, `no name: ${JSON.stringify(none)}`);
  }
  for (const text of [OWNER_NAMED, OWNER_UNNAMED]) assert.doesNotMatch(text, /agree|consent|tick/i, 'a notice, not consent');
});

test('T: each version\'s wording is pinned, so a changed wording needs a new version', () => {
  const wording = `${referralNotice('{First}')}\n${referralNotice(null)}`;
  assert.equal(wording, `${OWNER_NAMED}\n${OWNER_UNNAMED}`);
  assert.ok(Object.hasOwn(WORDINGS, REFERRAL_NOTICE_VERSION), `${REFERRAL_NOTICE_VERSION}: a version whose wording is not pinned here`);
  assert.equal(md5(wording), WORDINGS[REFERRAL_NOTICE_VERSION], `the wording of ${REFERRAL_NOTICE_VERSION} changed: give it a new version`);
  // referral_phone_notices.notice_version's check (484), so the database can store it.
  assert.match(REFERRAL_NOTICE_VERSION, /^[a-z0-9][a-z0-9._-]{0,39}$/);
});

test('T: 484\'s affiliate_referral_signup_with_notice lists the version (c_notices)', () => {
  assert.ok(existsSync(new URL(`../../../${MIGRATION}`, import.meta.url)),
    `${MIGRATION} is not in this tree: push #2 goes out after 484 is applied and committed`);
  const sql = read(MIGRATION);
  const lists = [...sql.matchAll(/c_notices\s+constant\s+text\[\]\s*:=\s*array\[([^\]]*)\]/gi)]
    .map(m => [...m[1].matchAll(/'+([^',]+)'+/g)].map(v => v[1]));
  assert.ok(lists.length > 0, `${MIGRATION}: no c_notices list (the notice versions the database accepts)`);
  for (const list of lists) assert.ok(list.includes(REFERRAL_NOTICE_VERSION), `c_notices lists ${REFERRAL_NOTICE_VERSION}: [${list.join(', ')}]`);
});

test('T: the newest migration that defines affiliate_referral_signup_with_notice takes the page\'s seven keys, only p_honeypot defaulted', () => {
  const defs = readdirSync(new URL('../../../supabase/', import.meta.url)).filter(f => /^\d+_.+\.sql$/.test(f))
    .sort((a, b) => parseInt(a, 10) - parseInt(b, 10) || a.localeCompare(b))
    .flatMap(f => [...read(`supabase/${f}`).matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.affiliate_referral_signup_with_notice\s*\(([^)]*)\)/gi)]
      .map(m => ({ f, params: m[1].split(',').map(p => p.trim().split(/\s+/)) })));
  assert.ok(defs.length > 0, 'no migration defines affiliate_referral_signup_with_notice');
  const { f, params } = defs.at(-1);
  assert.deepEqual(params.map(p => p[0]).sort(), SEVEN, `${f}: the wrapper's parameters are the keys the page sends`);
  assert.deepEqual(params.filter(p => p.some(w => /^default$/i.test(w))).map(p => p[0]), ['p_honeypot'], `${f}: only p_honeypot has a default`);
});

test('P: both cards carry the notice right after Phone and right before the button, which it describes', async () => {
  await open(backend());
  checkPlacement('named', named('Jane'));
  assert.equal(ctaOf(cards()[0]).disabled, false, 'the button needs nothing ticked');
  // Pressed with nothing typed: the error line sits between the notice and the button, in both cards.
  await d.click(ctaOf(cards()[1]));
  checkPlacement('with an error', named('Jane'), { error: 'Please enter your name.' });
  assert.equal(signups().length, 0, 'nothing is sent');
});

test('P: while the link is being checked, and with no first name, the notice says "the person who invited you"', async () => {
  let release;
  const gate = new Promise(r => { release = r; });
  await open(backend({ infoGate: gate }));
  assert.ok(document.body.textContent.includes('Claim My FREE Energia Giveaway Bundle'), 'the form is on screen while loading');
  checkPlacement('loading', OWNER_UNNAMED);
  release();
  await d.tick();
  checkPlacement('loaded', named('Jane'));

  for (const name of [null, '', '   ', 42, ['Jane']]) {
    await open(backend({ info: { valid: true, accepting: true, affiliate_name: name } }));
    checkPlacement(`affiliate_name ${JSON.stringify(name)}`, OWNER_UNNAMED);
  }
  await open(backend({ info: { valid: true, accepting: true } }));
  checkPlacement('no affiliate_name', OWNER_UNNAMED);
  await open(backend({ info: { valid: true, accepting: true, affiliate_name: '  Ravi  ' } }));
  checkPlacement('a padded name', named('Ravi'));
});

test('P: no rule in referral-landing.css naming .rl-notice hides or shrinks it, also under @media (jsdom ignores @media)', () => {
  const css = read('src/styles/referral-landing.css').replace(/\/\*[\s\S]*?\*\//g, '');
  const bodies = [...css.matchAll(/([^{}]*\.rl-notice\b[^{}]*)\{([^{}]*)\}/g)].map(m => m[2]);
  assert.ok(bodies.length > 0, 'the .rl-notice rule is there');
  for (const b of bodies) assert.doesNotMatch(b, /display\s*:\s*none|visibility\s*:\s*(hidden|collapse)|opacity\s*:\s*0*(\.\d+)?\s*(;|$)|font-size\s*:\s*(0|([0-9]|1[01])(\.\d+)?px)\s*(;|$)/i);
});

test('P: a notice, not consent: no tick box anywhere and no "agree"', async () => {
  await open(backend());
  assert.equal(document.querySelectorAll('input[type="checkbox"], [role="checkbox"]').length, 0);
  assert.doesNotMatch(document.body.textContent, /agree|consent/i);
  for (const n of notices()) assert.equal(n.querySelectorAll('input, label, button, a').length, 0, 'just text');
});

test('S: the six keys it always sent plus p_notice go to affiliate_referral_signup_with_notice, and a new registration goes to the booking page', async () => {
  await open(backend({ signup: { affiliate_referral_signup_with_notice: REGISTERED, affiliate_referral_signup: REGISTERED } }));
  await fill({ first: ' Ada ', last: 'Fixture ' });
  await d.click(ctaOf(cards()[0]));
  const calls = signups();
  assert.deepEqual(calls.map(c => c.name), ['affiliate_referral_signup_with_notice'], 'one call, to the function that records the notice');
  assert.deepEqual(Object.keys(calls[0].args).sort(), SEVEN, 'exactly seven keys');
  assert.deepEqual(calls[0].args, { ...TYPED, p_notice: REFERRAL_NOTICE_VERSION });
  // As typed: the names untrimmed (referralBookingUrl trims them), the phone as PhoneInput hands it back.
  const booking = { firstName: ' Ada ', lastName: 'Fixture ', email: 'ada.fixture@example.invalid', phone: '+61255509301', affiliateLabel: 'Jane Fixture' };
  assert.deepEqual(globalThis.__bookings, [{ booking, url: referralBookingUrl(booking) }], 'the booking page, as before');
  assert.equal(dom.window.location.hash, '#booking', 'the page went where referralBookingUrl said');
  assert.equal(ctaOf(cards()[0]).textContent, 'Registering…', 'busy on the way out');
  assert.equal(errorText().length, 0);

  // The end card, a blank email and a filled honeypot: as before (a null email, the honeypot sent as typed).
  await open(backend({ signup: { affiliate_referral_signup_with_notice: REGISTERED } }));
  await fill({ email: '   ' });
  await d.setValue(document.querySelector('input[aria-hidden="true"][tabindex="-1"]'), 'filled-by-a-bot');
  await d.click(ctaOf(cards()[1]));
  assert.deepEqual(signups().map(c => c.args), [{ ...TYPED, p_email: null, p_honeypot: 'filled-by-a-bot', p_notice: REFERRAL_NOTICE_VERSION }]);
});

test('S: the unnamed notice, and the notice while the link is being checked, are sent as told too', async () => {
  await open(backend({ info: { valid: true, accepting: true, affiliate_name: null }, signup: { affiliate_referral_signup_with_notice: REGISTERED } }));
  checkPlacement('no name', OWNER_UNNAMED);
  await fill();
  await d.click(ctaOf(cards()[0]));
  assert.deepEqual(signups().map(c => [c.name, c.args]), [['affiliate_referral_signup_with_notice', { ...TYPED, p_notice: REFERRAL_NOTICE_VERSION }]]);
  let release;
  const gate = new Promise(r => { release = r; });
  await open(backend({ infoGate: gate, signup: { affiliate_referral_signup_with_notice: REGISTERED } }));
  checkPlacement('loading', OWNER_UNNAMED);
  await fill();
  await d.click(ctaOf(cards()[1]));
  assert.deepEqual(signups().map(c => [c.name, c.args]), [['affiliate_referral_signup_with_notice', { ...TYPED, p_notice: REFERRAL_NOTICE_VERSION }]]);
  release();
  await d.tick();
});

test('S: a database without 484 (PGRST202): the same six keys go to affiliate_referral_signup, once', async () => {
  await open(backend({ signup: { affiliate_referral_signup: REGISTERED } }));
  await fill();
  await d.click(ctaOf(cards()[0]));
  const calls = signups();
  assert.deepEqual(calls.map(c => c.name), ['affiliate_referral_signup_with_notice', 'affiliate_referral_signup']);
  assert.deepEqual(calls[0].args, { ...TYPED, p_notice: REFERRAL_NOTICE_VERSION });
  assert.deepEqual(Object.keys(calls[1].args).sort(), SIX, 'exactly the six keys, no p_notice');
  assert.deepEqual(calls[1].args, TYPED);
  assert.equal(globalThis.__bookings.length, 1, 'registered: to the booking page');
  assert.equal(globalThis.__bookings[0].booking.affiliateLabel, 'Jane Fixture');
  assert.equal(dom.window.location.hash, '#booking');

  // The fallback's own answers, as the page always took them.
  await open(backend({ signup: { affiliate_referral_signup: EXISTING } }));
  await fill();
  await d.click(ctaOf(cards()[1]));
  assert.equal(signups().length, 2);
  assert.ok(document.body.textContent.includes('You are already registered'));
  assert.ok(document.body.textContent.includes(EXISTING.data.message));
  assert.equal(globalThis.__bookings.length, 0);

  await open(backend({ signup: { affiliate_referral_signup: failure('P0001', 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.') } }));
  await fill();
  await d.click(ctaOf(cards()[0]));
  assert.equal(signups().length, 2);
  assert.deepEqual(errorText(), Array(2).fill('Please confirm the phone country and enter a valid international phone number.'));
  assert.equal(ctaOf(cards()[0]).disabled, false, 'the button is back');

  // Neither function there (a database too old for /r/): the old function's own PGRST202 is shown, nothing more.
  await open(backend());
  await fill();
  await d.click(ctaOf(cards()[0]));
  assert.deepEqual(signups().map(c => c.name), ['affiliate_referral_signup_with_notice', 'affiliate_referral_signup']);
  assert.equal(errorText()[0], NOT_FOUND('affiliate_referral_signup').error.message);
});

test('S: every other error shows as before, with no second call', async () => {
  const cases = [
    [failure('P0001', 'CUSTOMER_PHONE_REVIEW: Enter a valid international phone number.'), 'Please confirm the phone country and enter a valid international phone number.'],
    [failure('P0001', 'CUSTOMER_PHONE_LIMIT: this phone number already belongs to 3 customers.'),
      'This phone number already belongs to 3 non-deleted customers across Energia. Enter a different valid number.'],
    [failure('P0001', 'AMBIGUOUS_CUSTOMER_MATCH: more than one customer.'),
      'More than one customer has this phone number and name. Ask staff to verify and select the correct customer record.'],
    [failure('PGRST203', 'Could not choose the best candidate function between: public.affiliate_referral_signup_with_notice(...)'), null],
    [failure('42883', 'function public.affiliate_referral_signup(text, text, text, text, text, text) does not exist'), null],
    [failure('42501', 'permission denied for function affiliate_referral_signup_with_notice'), null],
    [failure('', 'TypeError: Failed to fetch'), null],
    [failure(undefined, 'FetchError: the network is down'), null],
    // Not PGRST202, whatever the message says.
    [failure('pgrst202', 'Could not find the function public.affiliate_referral_signup_with_notice in the schema cache'), null],
  ];
  for (const [answer, shown] of cases) {
    const label = `${answer.error.code ?? '(no code)'}: ${answer.error.message}`;
    await open(backend({ signup: { affiliate_referral_signup_with_notice: answer, affiliate_referral_signup: REGISTERED } }));
    await fill();
    await d.click(ctaOf(cards()[0]));
    assert.deepEqual(signups().map(c => c.name), ['affiliate_referral_signup_with_notice'], `${label}: no second call`);
    assert.deepEqual(errorText(), Array(2).fill(shown ?? answer.error.message), `${label}: shown as before`);
    assert.equal(errorText()[0], phoneErrorMessage(answer.error.message), `${label}: through phoneErrorMessage`);
    assert.equal(globalThis.__bookings.length, 0, `${label}: not registered`);
    assert.equal(ctaOf(cards()[0]).textContent, 'YES! I WANT THIS FREE BUNDLE', `${label}: the button is back`);
    checkPlacement(label, named('Jane'), { error: shown ?? answer.error.message });
  }

  // A refusal in the answer (ok: false) is shown too, also with no second call.
  await open(backend({ signup: { affiliate_referral_signup_with_notice: { data: { ok: false, message: 'This link is not accepting registrations.' }, error: null } } }));
  await fill();
  await d.click(ctaOf(cards()[0]));
  assert.equal(signups().length, 1);
  assert.deepEqual(errorText(), Array(2).fill('This link is not accepting registrations.'));
});

test('S: someone already registered stays on the page and is told nothing changed', async () => {
  await open(backend({ signup: { affiliate_referral_signup_with_notice: EXISTING } }));
  await fill();
  await d.click(ctaOf(cards()[0]));
  assert.equal(signups().length, 1);
  assert.ok(document.body.textContent.includes('You are already registered'));
  assert.ok(document.body.textContent.includes(EXISTING.data.message));
  assert.equal(globalThis.__bookings.length, 0, 'not sent to book');
  assert.equal(dom.window.location.hash, '');
});

test('S: a name and a valid phone are still checked first, and nothing is sent without them', async () => {
  await open(backend({ signup: { affiliate_referral_signup_with_notice: REGISTERED } }));
  await fill({ first: '  ' });
  await d.click(ctaOf(cards()[0]));
  assert.deepEqual(errorText(), Array(2).fill('Please enter your name.'));
  await fill({ phone: '+61 2 5550' });
  await d.click(ctaOf(cards()[0]));
  assert.deepEqual(errorText(), Array(2).fill('Please enter a valid mobile/phone number.'));
  assert.equal(signups().length, 0);
});

test('the source: both functions are called by name (the permission check reads them), the fallback on PGRST202 alone', () => {
  const page = read('src/pages/ReferralSignupPage.tsx');
  assert.match(page, /from '\.\.\/lib\/referral\/notice\.mjs'/);
  // scripts/permissions/client-rpcs-are-granted.mjs finds the functions the app calls with this pattern.
  const RPC_CALLER = /(?:(?<!\badmin)\.rpc|\bcallerRpc)\(\s*'([a-z0-9_]+)'/g;
  assert.deepEqual([...page.matchAll(RPC_CALLER)].map(m => m[1]).sort(),
    ['affiliate_referral_signup', 'affiliate_referral_signup_with_notice', 'public_affiliate_referral_info']);
  assert.match(page, /supabase\.rpc\('affiliate_referral_signup_with_notice', \{ \.\.\.args, p_notice: REFERRAL_NOTICE_VERSION \}\)/);
  assert.match(page, /if \(error\?\.code === 'PGRST202'\) \(\{ data, error \} = await supabase\.rpc\('affiliate_referral_signup', args\)\);/);
  assert.equal(page.match(/PGRST202/g).length, 2, 'the one condition (and its comment)');
});
