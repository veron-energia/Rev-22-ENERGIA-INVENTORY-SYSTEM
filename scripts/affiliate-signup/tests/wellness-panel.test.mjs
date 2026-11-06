// The animated wellness panel of the affiliate Sign in and Join pages (6 Nov
// 2026): the real pages rendered against a fake backend, and the stylesheet read
// as text. What only a browser can tell (the layout, the motion itself, the
// keyboard) is in wellness-panel-browser.mjs.
//
//   C  The words: each page has its headline and line, and keeps its own form
//      title, line, fields and links; the panel says nothing else (no number,
//      no result, no claim), and Join alone names the three services.
//   A  Screen readers and the keyboard: every picture is hidden and cannot take
//      focus; the form comes first in the page; the panel's one control is a
//      plain button.
//   P  Pause and Resume: the panel's state and the button's words change, the
//      choice is remembered, and a browser that refuses storage still works.
//   F  The form is untouched: its messages stay inside it, the control leaves
//      what was typed alone, the signed-in notice and the terms link are there.
//   S  Scope: only Sign in and Join ask for the panel; another page using the
//      shell renders as before. Every selector and animation name is the
//      panel's own. Motion only without a reduced-motion request, slow, and of
//      transform, opacity or a dash alone. Pictures never take a click, and
//      nothing here reads or writes anything but its own remembered choice.
//
// Every email is invented (@example.com).
// Run: node --test scripts/affiliate-signup/tests/wellness-panel.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { setupDom, bundle, fakeSupabase, driver, REPO } from '../../ui/page-harness.mjs';

const dom = setupDom('https://energia.invalid/affiliate/login');
const mod = await bundle(`
  import React from 'react';
  export { default as AffiliateJoinPage } from './src/pages/AffiliateJoinPage';
  export { default as AffiliateLoginPage } from './src/pages/AffiliateLoginPage';
  export { default as AffiliateForgotPasswordPage } from './src/pages/AffiliateForgotPasswordPage';
  export { MemoryRouter, Routes, Route } from 'react-router-dom';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };`, { stubAuth: true });
const { React, AffiliateJoinPage, AffiliateLoginPage, AffiliateForgotPasswordPage, MemoryRouter, Routes, Route } = mod;
const d = driver(mod, dom);
const h = React.createElement;
after(async () => { await d.unmount(); dom.window.close(); });

const read = file => readFileSync(new URL(file, `file://${REPO}`), 'utf8');
const KEY = 'energia_aff_wellness_paused';

async function open(path, { session = null, supabase = {} } = {}) {
  globalThis.__auth = { session };
  globalThis.__supabase = fakeSupabase(supabase);
  localStorage.removeItem(KEY);
  await d.mount(h(MemoryRouter, { initialEntries: [path] },
    h(Routes, null,
      h(Route, { path: '/affiliate/login', element: h(AffiliateLoginPage) }),
      h(Route, { path: '/affiliate/join', element: h(AffiliateJoinPage) }),
      h(Route, { path: '/affiliate/forgot-password', element: h(AffiliateForgotPasswordPage) }))));
}
const panel = () => document.querySelector('aside.aff-wellness');
const form = () => document.querySelector('main.aff-wellness-form');
const inForm = text => (form().textContent.includes(text));

test('C1 Sign in: its headline and line, and the form as it was', async () => {
  await open('/affiliate/login');
  assert.equal(panel().querySelector('h2').textContent, 'Welcome back to Energia.');
  assert.equal(panel().querySelector('.aff-wellness-support').textContent, 'Sign in to your affiliate portal.');
  assert.equal(form().querySelector('h2').textContent, 'Affiliate Login');
  assert.ok(inForm('Sign in to your Energia Affiliate portal'));
  assert.ok(d.labelled('Email') && d.labelled('Password'));
  assert.ok(d.button('Sign In', form()));
  assert.deepEqual([...form().querySelectorAll('a')].map(a => a.getAttribute('href')), ['/affiliate/forgot-password', '/affiliate/join']);
});

test('C2 Join: its headline and line, and the form as it was', async () => {
  await open('/affiliate/join');
  assert.equal(panel().querySelector('h2').textContent, 'Share wellness. Grow together.');
  assert.equal(panel().querySelector('.aff-wellness-support').textContent, 'Become part of the Energia affiliate community.');
  assert.equal(form().querySelector('h2').textContent, 'Become an Energia Affiliate');
  assert.ok(inForm('Create your affiliate account'));
  assert.ok(inForm('Already an Energia customer? Use this form with the phone number Energia has for you'));
  for (const label of ['First Name', 'Last Name', 'Email', 'Password', 'Confirm Password']) assert.ok(d.labelled(label), label);
  assert.ok(form().querySelector('.phone-input select, select'), 'the phone country list is there');
  assert.ok(d.button('Create Account', form()));
  const terms = form().querySelector('a[data-link="terms"]');
  assert.equal(terms.getAttribute('href'), '/affiliate/rules');
  assert.equal(terms.getAttribute('target'), '_blank');
  assert.ok(form().querySelector('input[type="checkbox"]'));
});

test('C3 the panel says nothing else: no number, no result, no claim', async () => {
  await open('/affiliate/join');
  assert.deepEqual([...panel().querySelectorAll('.aff-wellness-caption')].map(c => c.textContent),
    ['Power Recharge Therapy', 'Power Foot Detox Therapy', 'AcuGraph Energy Analysis']);
  assert.equal(panel().textContent,
    'Share wellness. Grow together.Become part of the Energia affiliate community.'
    + 'Power Recharge TherapyPower Foot Detox TherapyAcuGraph Energy AnalysisPause animation');
  assert.ok(panel().querySelector('.aff-wellness-people'), 'Join has the connected people');
  await open('/affiliate/login');
  assert.equal(panel().textContent, 'Welcome back to Energia.Sign in to your affiliate portal.Pause animation');
  assert.equal(panel().querySelector('.aff-wellness-people'), null, 'Sign in is quieter');
});

test('C4 Sign in is the quieter version of the same three scenes', async () => {
  const count = () => ({
    scenes: panel().querySelectorAll('.aff-wellness-tile svg').length,
    moving: panel().querySelectorAll('.aff-wellness-ring, .aff-wellness-ripple, .aff-wellness-bubble, .aff-wellness-bar, .aff-wellness-person, .aff-wellness-link').length,
  });
  await open('/affiliate/join');
  const join = count();
  await open('/affiliate/login');
  const login = count();
  assert.equal(join.scenes, 3);
  assert.equal(login.scenes, 3);
  assert.ok(login.moving < join.moving / 2, `Sign in moves ${login.moving} parts, Join ${join.moving}`);
});

for (const path of ['/affiliate/login', '/affiliate/join']) {
  test(`A1 ${path}: pictures are hidden from screen readers, cannot take focus, and hold no text`, async () => {
    await open(path);
    const svgs = [...panel().querySelectorAll('svg')];
    assert.ok(svgs.length >= 4);
    for (const svg of svgs) {
      assert.equal(svg.getAttribute('aria-hidden'), 'true');
      if (!svg.closest('button')) assert.equal(svg.getAttribute('focusable'), 'false');
      assert.equal(svg.querySelector('text, title, a'), null);
    }
  });

  test(`A2 ${path}: the form comes first; the panel is named by its headline and has one plain button`, async () => {
    await open(path);
    assert.ok(form().compareDocumentPosition(panel()) & dom.window.Node.DOCUMENT_POSITION_FOLLOWING);
    assert.equal(panel().getAttribute('aria-labelledby'), panel().querySelector('h2').id);
    const controls = panel().querySelectorAll('a, button, input, select, textarea, [tabindex]');
    assert.equal(controls.length, 1);
    assert.equal(controls[0].getAttribute('type'), 'button');
  });
}

test('P1 Pause and Resume change the panel and the words', async () => {
  await open('/affiliate/login');
  assert.equal(panel().hasAttribute('data-paused'), false);
  await d.click(d.button('Pause animation', panel()));
  assert.equal(panel().hasAttribute('data-paused'), true);
  assert.equal(localStorage.getItem(KEY), '1');
  await d.click(d.button('Resume animation', panel()));
  assert.equal(panel().hasAttribute('data-paused'), false);
  assert.equal(localStorage.getItem(KEY), '0');
  assert.ok(d.button('Pause animation', panel()));
});

test('P2 going to the other page keeps someone\'s pause', async () => {
  await open('/affiliate/login');
  await d.click(d.button('Pause animation', panel()));
  await d.click(form().querySelector('a[href="/affiliate/join"]'));
  assert.equal(panel().querySelector('h2').textContent, 'Share wellness. Grow together.');
  assert.equal(panel().hasAttribute('data-paused'), true);
  assert.ok(d.button('Resume animation', panel()));
});

test('P3 a browser that refuses storage still shows the panel and pauses it', async () => {
  const storage = Object.getPrototypeOf(localStorage);
  const { getItem, setItem } = storage;
  const refuse = () => { throw new Error('storage is off'); };
  await open('/affiliate/login');
  storage.getItem = refuse; storage.setItem = refuse;
  try {
    globalThis.__auth = { session: null };
    await d.mount(h(MemoryRouter, { initialEntries: ['/affiliate/login'] }, h(AffiliateLoginPage)));
    assert.ok(panel());
    await d.click(d.button('Pause animation', panel()));
    assert.equal(panel().hasAttribute('data-paused'), true);
  } finally { storage.getItem = getItem; storage.setItem = setItem; }
});

test('F1 Join\'s messages stay in the form, and nothing is sent', async () => {
  await open('/affiliate/join');
  await d.click(d.button('Create Account', form()));
  const alert = form().querySelector('[role="alert"]');
  assert.equal(alert.textContent, 'Please fill in your name, phone and email.');
  assert.equal(panel().querySelector('[role="alert"]'), null);
  assert.deepEqual(globalThis.__supabase.calls, []);
});

test('F2 Sign in\'s error stays in the form', async () => {
  const auth = {
    getSession: async () => ({ data: { session: null } }),
    signInWithPassword: async () => ({ data: {}, error: { message: 'Invalid login credentials' } }),
  };
  await open('/affiliate/login', { supabase: { auth } });
  await d.setValue(d.labelled('Email'), 'ada.preview@example.com');
  await d.click(d.button('Sign In', form()));
  assert.equal(form().querySelector('[role="alert"]').textContent, 'Invalid login credentials');
  assert.equal(panel().querySelector('[role="alert"]'), null);
});

test('F3 the control leaves what was typed alone', async () => {
  await open('/affiliate/join');
  await d.setValue(d.labelled('Email'), 'ada.preview@example.com');
  await d.setValue(d.labelled('First Name'), 'Ada');
  await d.click(d.button('Pause animation', panel()));
  assert.equal(d.labelled('Email').value, 'ada.preview@example.com');
  assert.equal(d.labelled('First Name').value, 'Ada');
  assert.deepEqual(globalThis.__supabase.calls, []);
});

test('F4 Join still says who is signed in here', async () => {
  await open('/affiliate/join', { session: { user: { email: 'ada.preview@example.com' } } });
  assert.match(form().querySelector('[data-note="signed-in-elsewhere"]').textContent, /signed in as ada\.preview@example\.com/);
});

test('S1 another page on the shell renders as before: the centered card alone', async () => {
  await open('/affiliate/forgot-password');
  assert.equal(document.querySelector('[class*="aff-wellness"]'), null);
  assert.equal(document.querySelector('main'), null);
  const page = document.querySelector('.portal-auth');
  assert.equal(page.getAttribute('style').replace(/\s/g, ''),
    'min-height:100vh;background:var(--bg);display:flex;align-items:center;justify-content:center;padding:16px;');
});

test('S2 only Sign in and Join ask for the panel, Join on each of its screens', () => {
  const asks = file => (read(file).match(/wellness="(\w+)"/g) ?? []);
  assert.deepEqual(asks('src/pages/AffiliateLoginPage.tsx'), ['wellness="login"']);
  assert.deepEqual(asks('src/pages/AffiliateJoinPage.tsx'), ['wellness="join"', 'wellness="join"', 'wellness="join"']);
  for (const file of ['AffiliateForgotPasswordPage', 'AffiliateResetPasswordPage', 'AffiliateVerifyPage']) {
    assert.deepEqual(asks(`src/pages/${file}.tsx`), [], file);
  }
  assert.deepEqual(asks('src/components/RouteGuards.tsx'), []);
});

/** The stylesheet as rules, each with the at-rules around it. */
function rules(css) {
  const out = [];
  const walk = (text, at) => {
    let i = 0;
    while (i < text.length) {
      const open = text.indexOf('{', i);
      if (open < 0) break;
      const head = text.slice(i, open).trim();
      let depth = 1, j = open + 1;
      for (; j < text.length && depth; j++) { if (text[j] === '{') depth++; else if (text[j] === '}') depth--; }
      const body = text.slice(open + 1, j - 1);
      if (head.startsWith('@media')) walk(body, [...at, head]);
      else out.push({ head, body: body.trim(), at });
      i = j;
    }
  };
  walk(css.replace(/\/\*[\s\S]*?\*\//g, ''), []);
  return out;
}
const CSS = rules(read('src/components/affiliate-wellness.css'));

test('S3 every selector and animation name is the panel\'s own', () => {
  assert.ok(CSS.length > 30);
  for (const { head } of CSS) {
    if (head.startsWith('@keyframes')) { assert.match(head, /^@keyframes aff-wellness-/); continue; }
    for (const selector of head.split(',')) assert.match(selector.trim(), /^\.aff-wellness/, selector);
  }
});

test('S4 motion only without a reduced-motion request, slow, and of transform, opacity or a dash alone', () => {
  const moving = CSS.filter(r => /(^|\s)animation(-name)?:/.test(r.body));
  assert.ok(moving.length >= 8);
  for (const { head, body, at } of moving) {
    assert.deepEqual(at, ['@media (prefers-reduced-motion: no-preference)'], head);
    assert.match(body, /infinite/, head);
    const seconds = Number(body.match(/calc\(([\d.]+)s/)?.[1]);
    assert.ok(seconds >= 5, `${head}: ${seconds}s`);
  }
  assert.ok(!CSS.some(r => /(^|\s)transition/.test(r.body)), 'no transition that a reduced-motion request would miss');
  for (const { head, body } of CSS.filter(r => r.head.startsWith('@keyframes'))) {
    for (const prop of [...body.matchAll(/([a-z-]+):/g)].map(m => m[1])) assert.ok(['transform', 'opacity', 'stroke-dashoffset'].includes(prop), `${head}: ${prop}`);
  }
  const still = CSS.filter(r => r.at.includes('@media (prefers-reduced-motion: reduce)'));
  assert.deepEqual(still.map(r => [r.head, r.body]), [['.aff-wellness-toggle', 'display: none;']], 'a still picture has nothing to pause');
});

test('S5 the pictures never take a click', () => {
  for (const name of ['.aff-wellness-svg', '.aff-wellness-people']) {
    assert.match(CSS.find(r => r.head === name).body, /pointer-events: none/, name);
  }
});

test('S6 presentation alone: the panel and its scenes read and write nothing but the remembered pause', () => {
  const panelSource = read('src/components/AffiliateWellnessPanel.tsx');
  const scenes = read('src/components/AffiliateWellnessScenes.tsx');
  const imports = source => [...source.matchAll(/from '([^']+)'|import '([^']+)'/g)].map(m => m[1] ?? m[2]);
  assert.deepEqual(imports(panelSource), ['react', 'lucide-react', './AffiliateWellnessScenes', './affiliate-wellness.css']);
  assert.deepEqual(imports(scenes), ['react']);
  assert.doesNotMatch(panelSource + scenes, /supabase|fetch\(|useAuth|navigate|location\./i);
  assert.match(scenes, /'#0ABAB5'/, 'Tiffany Blue is the accent');
});
