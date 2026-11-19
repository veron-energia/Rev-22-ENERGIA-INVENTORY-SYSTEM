// 529 (security audit of 17 Nov 2026, M3; the user, 19 Nov 2026: "Refuse odd input"): the /r/ page checks the
// name and email with the database's own rule before it calls, and shows the database's refusals.
//
//   R  The rule (src/lib/referral/signupInput.mjs), both ways: real-world names are accepted (apostrophes,
//      hyphens, digits, accents, Chinese and Burmese script, exactly 100 characters); a name longer than 100
//      characters (first and last together), one with a web address ('://', 'www.' in any case), '<', '>' or a
//      control character is refused; the email may be blank, one typed must look like name@domain.tld and be at
//      most 254 characters. The same cases run against the database in referral-limits-529.sql.
//   M  The messages are 529's, word for word, and the page's limits are the rule's.
//   P  The page: maxLength on the name and email fields; an odd name or email is refused on the page with the
//      message, and nothing is sent; what is sent is what was checked (trimmed); the database's own refusals
//      (529's limits) show as its message.
//
// Every name, email and phone is invented (@example.invalid, ACMA's fictional +61 2 5550 numbers).
//
// Run: node --test scripts/affiliate-signup/tests/referral-input-529.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';
import { setupDom, REPO, driver } from '../../ui/page-harness.mjs';
import * as rules from '../../../src/lib/referral/signupInput.mjs';

const read = p => readFileSync(new URL(`../../../${p}`, import.meta.url), 'utf8');
const MIGRATION = 'supabase/529_the_referral_page_limits_each_sender_and_all_links.sql';

// [first, last, expected message or null]
const NAMES = [
  ["Siobhan", "O'Brien", null], ['Mary-Jane', 'Tan-Lim', null], ['Ah Kow 2', 'Lee', null], ['José', 'Muñoz', null],
  ['陈大文', '', null], ['မောင်မောင်', 'ထွန်း', null], ['Nguyễn', 'Văn An', null], ['Ann', 'Lee (Mrs)', null],
  ['A'.repeat(49), 'B'.repeat(50), null], ['A'.repeat(100), '', null], ['  Ann  ', '  Lee  ', null],
  ['陈'.repeat(100), '', null], ['Dr. Ann', 'St. Clair', null], ['Ann', 'www', null], ['Ann', 'wwwLee', null],
  ['A'.repeat(50), 'B'.repeat(50), rules.NAME_TOO_LONG], ['A'.repeat(101), '', rules.NAME_TOO_LONG],
  ['陈'.repeat(101), '', rules.NAME_TOO_LONG],
  ['Ann', 'https://spam.example.invalid', rules.NAME_HAS_WEB_ADDRESS], ['Visit www.example.invalid', '', rules.NAME_HAS_WEB_ADDRESS],
  ['WWW.EXAMPLE.INVALID', 'Lee', rules.NAME_HAS_WEB_ADDRESS], ['ftp://x', '', rules.NAME_HAS_WEB_ADDRESS],
  ['<b>Ann</b>', '', rules.NAME_HAS_ODD_CHARACTERS], ['Ann', 'Lee >', rules.NAME_HAS_ODD_CHARACTERS],
  ['Ann\tLee', '', rules.NAME_HAS_ODD_CHARACTERS], ['Ann\nLee', '', rules.NAME_HAS_ODD_CHARACTERS],
  ['Ann\u0085', 'Lee', rules.NAME_HAS_ODD_CHARACTERS], ['Ann\u007f', '', rules.NAME_HAS_ODD_CHARACTERS],
  ['Ann\u001b[31m', '', rules.NAME_HAS_ODD_CHARACTERS],
];
// [email, expected message or null]
const EMAILS = [
  [null, null], ['', null], ['   ', null], ['ann.lee@example.invalid', null], ['Ann.Lee+promo@Example.Invalid', null],
  ['  ann@example.invalid  ', null], ['a_b-c@sub.example.invalid', null], ["o'brien@example.invalid", null],
  ['ann@xn--example.invalid', null], ['陈@例子.invalid', null], ['a@b.co', null],
  [`${'a'.repeat(64)}@${'b'.repeat(181)}.invalid`, null],
  [`${'a'.repeat(64)}@${'b'.repeat(182)}.invalid`, rules.EMAIL_TOO_LONG],
  ['ann', rules.EMAIL_NOT_AN_EMAIL], ['ann@example', rules.EMAIL_NOT_AN_EMAIL], ['ann@example.c', rules.EMAIL_NOT_AN_EMAIL],
  ['@example.invalid', rules.EMAIL_NOT_AN_EMAIL], ['ann@@example.invalid', rules.EMAIL_NOT_AN_EMAIL],
  ['ann@.example.invalid', rules.EMAIL_NOT_AN_EMAIL], ['ann@example..invalid', rules.EMAIL_NOT_AN_EMAIL],
  ['ann@example.invalid.', rules.EMAIL_NOT_AN_EMAIL], ['ann lee@example.invalid', rules.EMAIL_NOT_AN_EMAIL],
  ['<ann@example.invalid>', rules.EMAIL_NOT_AN_EMAIL], ['ann@exa\tmple.invalid', rules.EMAIL_NOT_AN_EMAIL],
  ['ann@example.invalid\n', rules.EMAIL_NOT_AN_EMAIL], ['Ann <ann@example.invalid>', rules.EMAIL_NOT_AN_EMAIL],
];

test('R: names, both ways', () => {
  for (const [first, last, want] of NAMES) {
    assert.equal(rules.nameProblem(first, last), want, `${JSON.stringify(first)} ${JSON.stringify(last)}`);
  }
  assert.equal(rules.signupName('  Ann ', ' Lee  '), 'Ann   Lee', 'first + space + last, only the ends trimmed');
  assert.equal(rules.signupName(null, undefined), '');
  assert.equal(rules.nameProblem('', ''), null, 'a blank name is the page\'s own check ("Please enter your name.")');
});

test('R: emails, both ways', () => {
  for (const [email, want] of EMAILS) assert.equal(rules.emailProblem(email), want, JSON.stringify(email));
});

test('R: the name is checked before the email, as in the database', () => {
  assert.equal(rules.signupInputProblem('<Ann>', 'Lee', 'not-an-email'), rules.NAME_HAS_ODD_CHARACTERS);
  assert.equal(rules.signupInputProblem('Ann', 'Lee', 'not-an-email'), rules.EMAIL_NOT_AN_EMAIL);
  assert.equal(rules.signupInputProblem('Ann', 'Lee', null), null);
});

test('M: the messages are 529\'s, word for word, and the limits are 100 and 254', () => {
  const sql = read(MIGRATION);
  for (const k of ['NAME_TOO_LONG', 'NAME_HAS_WEB_ADDRESS', 'NAME_HAS_ODD_CHARACTERS', 'EMAIL_TOO_LONG', 'EMAIL_NOT_AN_EMAIL']) {
    assert.ok(sql.includes(`'${rules[k].replace(/'/g, "''")}'`), `${k} is in ${MIGRATION}`);
  }
  assert.equal(rules.NAME_MAX, 100);
  assert.equal(rules.EMAIL_MAX, 254);
  assert.match(sql, /char_length\(v_name\) > 100/);
  assert.match(sql, /char_length\(btrim\(p_email\)\) > 254/);
});

// The page, bundled and mounted in jsdom with the Supabase client stubbed (as referral-notice.test.mjs does).
const dom = setupDom('https://energia.invalid/');
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
  } }],
});
const mod = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const { React, ReferralSignupPage, MemoryRouter, Routes, Route } = mod;
const d = driver(mod, dom);
const h = React.createElement;
after(async () => { await d.unmount(); dom.window.close(); });

function backend(answer) {
  const b = { calls: [] };
  b.rpc = async (name, args) => {
    b.calls.push({ name, args: structuredClone(args) });
    await Promise.resolve();
    if (name === 'public_affiliate_referral_info') return { data: { valid: true, accepting: true, affiliate_name: 'Jane' }, error: null };
    return structuredClone(answer);
  };
  return b;
}
const signups = () => globalThis.__backend.calls.filter(c => c.name.startsWith('affiliate_referral_signup'));
async function open(b) {
  globalThis.__backend = b;
  await d.mount(h(MemoryRouter, { initialEntries: ['/r/T529CODE'] },
    h(Routes, null, h(Route, { path: '/r/:referralCode', element: h(ReferralSignupPage) }))));
}
const cards = () => [...document.querySelectorAll('.rl-form-card')];
async function fill({ first = 'Ada', last = 'Fixture', email = 'ada.fixture@example.invalid', phone = '+61 2 5550 9301' } = {}) {
  const card = cards()[0];
  await d.setValue(card.querySelector('input[id$="-first"]'), first);
  await d.setValue(card.querySelector('input[id$="-last"]'), last);
  await d.setValue(card.querySelector('input[id$="-email"]'), email);
  await d.setValue(card.querySelector('.phone-input input'), phone);
}
const press = () => d.click(cards()[0].querySelector('button.rl-cta'));
const errorText = () => [...document.querySelectorAll('.rl-error')].map(e => e.textContent);
const REFUSED = message => ({ data: { ok: false, message }, error: null });

test('P: the name and email fields carry the rule\'s limits, in both cards', async () => {
  await open(backend(REFUSED('x')));
  for (const card of cards()) {
    assert.equal(card.querySelector('input[id$="-first"]').maxLength, 100);
    assert.equal(card.querySelector('input[id$="-last"]').maxLength, 100);
    assert.equal(card.querySelector('input[id$="-email"]').maxLength, 254);
  }
});

test('P: an odd name or email is refused on the page with the database\'s message, and nothing is sent', async () => {
  const cases = [
    [{ first: 'Ann', last: 'https://spam.example.invalid' }, rules.NAME_HAS_WEB_ADDRESS],
    [{ first: '<script>' }, rules.NAME_HAS_ODD_CHARACTERS],
    [{ first: 'A'.repeat(60), last: 'B'.repeat(60) }, rules.NAME_TOO_LONG],
    [{ email: 'not-an-email' }, rules.EMAIL_NOT_AN_EMAIL],
    [{ email: 'ann@example' }, rules.EMAIL_NOT_AN_EMAIL],
  ];
  for (const [typed, message] of cases) {
    await open(backend(REFUSED('should not be called')));
    await fill(typed);
    await press();
    assert.deepEqual(errorText(), Array(2).fill(message), JSON.stringify(typed));
    assert.equal(signups().length, 0, `${JSON.stringify(typed)}: nothing sent`);
    assert.equal(cards()[0].querySelector('button.rl-cta').disabled, false, 'the button stays usable');
  }
});

test('P: a real-world name and a blank email go through, trimmed, as checked', async () => {
  await open(backend(REFUSED('Registrations are very busy right now. Please try again in an hour, or contact Energia.')));
  await fill({ first: "  Siobhan  ", last: "O'Brien-陈 ", email: '   ' });
  await press();
  const calls = signups();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].args.p_first_name, 'Siobhan');
  assert.equal(calls[0].args.p_last_name, "O'Brien-陈");
  assert.equal(calls[0].args.p_email, null);
});

test('P: the database\'s own refusals (529\'s limits) show as its message', async () => {
  for (const message of [
    'Too many registration attempts from this connection. Please try again in an hour, or contact Energia.',
    'Registrations are very busy right now. Please try again in an hour, or contact Energia.',
    'Too many registration attempts for this phone number. Please wait 10 minutes or contact Energia.',
    rules.EMAIL_NOT_AN_EMAIL,
  ]) {
    assert.ok(read(MIGRATION).includes(message.replace(/'/g, "''")), `529 says: ${message}`);
    await open(backend(REFUSED(message)));
    await fill();
    await press();
    assert.equal(signups().length, 1);
    assert.deepEqual(errorText(), Array(2).fill(message));
  }
});

test('the source: the page uses the rule module before it calls', () => {
  const page = read('src/pages/ReferralSignupPage.tsx');
  assert.match(page, /from '\.\.\/lib\/referral\/signupInput\.mjs'/);
  const check = page.indexOf('signupInputProblem(args.p_first_name, args.p_last_name, args.p_email)');
  assert.ok(check > 0 && check < page.indexOf("supabase.rpc('affiliate_referral_signup_with_notice'"), 'checked before the call');
});
