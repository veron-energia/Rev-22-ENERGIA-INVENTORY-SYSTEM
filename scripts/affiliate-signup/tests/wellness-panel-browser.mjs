// The animated wellness panel of the affiliate Sign in and Join pages (6 Nov
// 2026), measured in Chrome with the app's real stylesheets. The real pages are
// mounted with the Supabase client and the signed-in user stubbed, and every
// network request is blocked, so no account can be made.
//
//   L  Layout, from a small phone to a wide screen: no sideways scroll; the
//      panel and the form never overlap; two columns from 900px with the panel
//      on the left, under the form below that; the first field is near the top
//      on a phone; the long Join page scrolls to its end, on a short laptop
//      screen too, and nothing shifts while the page settles.
//   C  Clicks: every field and button answers at its own centre, and a point on
//      a picture never lands on the picture.
//   M  Motion: everything moving is inside the panel, slow, endless, and only
//      transform, opacity or a dash; Sign in moves fewer parts, more slowly.
//      Pause stops it where it is, Resume goes on, a reload remembers it, and
//      it rests while the panel is off-screen.
//   R  Reduced motion: nothing runs, the picture is complete (all three scenes,
//      their rings, ripples, bubbles and bars showing), and there is no control
//      to find.
//   K  The keyboard: the form comes first, then its links, then the control,
//      which shows its focus and answers Space and Enter. The panel's words are
//      readable (4.5:1 or better against the panel's darkest background).
//   V  The form's own states, in place: the wrong password, a sign-up not
//      switched on, each of Join's messages, showing a password, Signing in…,
//      the phone's country, the signed-in notice, the terms box in its row.
//
// Every email and phone is invented (@example.com, an ACMA fictional mobile number).
//
// Usage: node scripts/affiliate-signup/tests/wellness-panel-browser.mjs [folder for screenshots]
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { mkdir } from 'node:fs/promises';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/Users/shinthantaungstanley/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');

const SHOTS = process.argv[2] || '.commission-test/wellness-panel';
await mkdir(SHOTS, { recursive: true });

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      import { createRoot } from 'react-dom/client';
      import { BrowserRouter, Routes, Route } from 'react-router-dom';
      import './src/styles/globals.css';
      import AffiliateLoginPage from './src/pages/AffiliateLoginPage';
      import AffiliateJoinPage from './src/pages/AffiliateJoinPage';
      createRoot(document.getElementById('root')).render(
        <BrowserRouter><Routes>
          <Route path="/affiliate/login" element={<AffiliateLoginPage />} />
          <Route path="/affiliate/join" element={<AffiliateJoinPage />} />
          <Route path="*" element={<p>Elsewhere</p>} />
        </Routes></BrowserRouter>);`,
    loader: 'tsx', resolveDir: process.cwd(),
  },
  bundle: true, write: false, format: 'iife', jsx: 'automatic', outdir: '.commission-test/browser', logLevel: 'error',
  loader: { '.css': 'css' },
  define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{"DEV":false,"VITE_SUPABASE_URL":"x","VITE_SUPABASE_ANON_KEY":"x"}' },
  plugins: [{ name: 'offline', setup(b) {
    b.onResolve({ filter: /(^|\/)lib\/supabase$|^\.\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      const wait = () => new Promise(r => setTimeout(r, window.__wait ?? 0));
      export const supabase = {
        auth: {
          signInWithPassword: async () => { window.__signIns = (window.__signIns ?? 0) + 1; await wait();
            return { data: {}, error: window.__unconfirmed ? { code: 'email_not_confirmed', message: 'Email not confirmed' } : { message: 'Invalid login credentials' } }; },
        },
        functions: { invoke: async fn => { (window.__invoked ??= []).push(fn); await wait(); return { data: null, error: { message: 'stub' } }; } },
      };` }));
    b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
    b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const useAuth = () => ({ session: window.__signedIn ? { user: { email: 'ada.preview@example.com' } } : null });
      export const AuthProvider = ({ children }) => children;` }));
  } }],
});
const js = built.outputFiles.find(f => f.path.endsWith('.js')).text;
const css = built.outputFiles.find(f => f.path.endsWith('.css')).text.replace(/^@import.*$/gm, '');

let failures = 0;
function check(ok, message) {
  if (ok) console.log(`  ok    ${message}`);
  else { failures += 1; console.log(`  FAIL  ${message}`); }
}

const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' });

/** The page in a fresh browser profile, with everything off the page itself blocked. */
async function open(path, { width = 1280, height = 800, reducedMotion = 'no-preference', init, touch = false } = {}) {
  const context = await browser.newContext({ viewport: { width, height }, reducedMotion, hasTouch: touch });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error' && !/ERR_FAILED/.test(m.text())) errors.push(m.text()); });
  await page.route('**/*', route => (route.request().resourceType() === 'document'
    ? route.fulfill({ contentType: 'text/html', body: `<!doctype html><html><head><style>${css}</style></head><body><div id="root"></div><script>${js.replace(/<\/script>/g, '<\\/script>')}</script></body></html>` })
    : route.abort()));
  await page.addInitScript(() => {
    window.__shift = 0;
    new PerformanceObserver(list => { for (const e of list.getEntries()) if (!e.hadRecentInput) window.__shift += e.value; }).observe({ type: 'layout-shift', buffered: true });
  });
  if (init) await page.addInitScript(init);
  await page.goto(`http://energia.invalid/affiliate/${path}`);
  await page.waitForSelector('.aff-wellness');
  return { page, context, errors };
}

const rect = (page, selector) => page.evaluate(s => {
  const r = document.querySelector(s).getBoundingClientRect();
  return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height };
}, selector);
const running = page => page.evaluate(() => {
  const all = document.getAnimations();
  return { total: all.length, running: all.filter(a => a.playState === 'running').length, paused: all.filter(a => a.playState === 'paused').length };
});

// ═════ L Layout ═════
console.log('L Layout');
for (const path of ['login', 'join']) {
  for (const [width, height] of [[320, 568], [360, 740], [390, 844], [768, 1024], [899, 900], [900, 700], [1024, 768], [1280, 720], [1366, 650], [1536, 864], [1920, 1080]]) {
    const { page, context, errors } = await open(path, { width, height });
    const panel = await rect(page, '.aff-wellness');
    const form = await rect(page, '.aff-wellness-form');
    const overlap = panel.left < form.right && form.left < panel.right && panel.top < form.bottom && form.top < panel.bottom;
    const first = await rect(page, '.aff-wellness-form input');
    const tall = await page.evaluate(() => ({ sideways: document.documentElement.scrollWidth - window.innerWidth,
      page: document.documentElement.scrollHeight, view: window.innerHeight }));
    const where = width >= 900 ? panel.right <= form.left && panel.left >= 0 : form.bottom <= panel.top;
    const phoneOk = width >= 900 || first.top < 260 || path === 'join' && first.top < 420;
    // To the very end of the page: the whole panel can be seen, by scrolling alone.
    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    await page.waitForTimeout(50);
    const end = await rect(page, '.aff-wellness');
    const bottomOk = end.bottom <= height + 0.5;
    const shift = await page.evaluate(() => window.__shift);
    check(tall.sideways <= 0 && !overlap && where && phoneOk && bottomOk && shift === 0 && errors.length === 0,
      `${path} at ${width}x${height}: ${width >= 900 ? 'panel left of the form' : 'form above the panel'}, no overlap, no sideways scroll, first field at ${Math.round(first.top)}px, panel reachable (page ${tall.page}px), shift ${shift}${errors.length ? `, errors: ${errors.join('; ')}` : ''}`);
    await context.close();
  }
}

// ═════ C Clicks ═════
console.log('C Clicks');
for (const path of ['login', 'join']) {
  for (const [width, height] of [[1280, 900], [390, 844]]) {
    const { page, context } = await open(path, { width, height });
    const answers = await page.evaluate(() => [...document.querySelectorAll('.aff-wellness-form input, .aff-wellness-form select, .aff-wellness-form button, .aff-wellness-toggle')].map(el => {
      el.scrollIntoView({ block: 'center' });
      const r = el.getBoundingClientRect();
      const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      return { ok: el === hit || el.contains(hit), what: el.tagName + (el.type ? `[${el.type}]` : '') };
    }));
    const pictures = await page.evaluate(() => [...document.querySelectorAll('.aff-wellness svg:not(.lucide)')].map(svg => {
      svg.scrollIntoView({ block: 'center' });
      const r = svg.getBoundingClientRect();
      const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
      return !hit.closest('svg:not(.lucide)');
    }));
    check(answers.every(a => a.ok) && answers.length >= 4, `${path} at ${width}: all ${answers.length} controls answer at their centres`);
    check(pictures.every(Boolean) && pictures.length >= 3, `${path} at ${width}: a point on any of its ${pictures.length} pictures passes through it`);
    await context.close();
  }
}

// ═════ M Motion ═════
console.log('M Motion');
const motion = async path => {
  const { page, context, errors } = await open(path);
  const seen = await page.evaluate(() => document.getAnimations().map(a => {
    const timing = a.effect.getComputedTiming();
    const props = [...new Set(a.effect.getKeyframes().flatMap(k => Object.keys(k)))].filter(k => !['offset', 'computedOffset', 'easing', 'composite'].includes(k));
    return { inPanel: !!a.effect.target.closest('.aff-wellness-art, .aff-wellness-people'), duration: timing.duration, endless: timing.iterations === Infinity, props };
  }));
  await context.close();
  return { seen, errors };
};
const joinMotion = await motion('join');
const loginMotion = await motion('login');
for (const [name, { seen, errors }] of [['join', joinMotion], ['login', loginMotion]]) {
  check(seen.length > 0 && seen.every(a => a.inPanel), `${name}: ${seen.length} animations, every one in the panel's pictures`);
  check(seen.every(a => a.endless && a.duration >= 5000), `${name}: all endless and slow (shortest ${Math.min(...seen.map(a => a.duration)) / 1000}s)`);
  check(seen.every(a => a.props.every(p => ['transform', 'opacity', 'strokeDashoffset'].includes(p))), `${name}: only transform, opacity and a dash move`);
  check(errors.length === 0, `${name}: nothing in the console`);
}
const shortest = list => Math.min(...list.map(a => a.duration));
check(loginMotion.seen.length < joinMotion.seen.length / 2 && shortest(loginMotion.seen) > shortest(joinMotion.seen),
  `Sign in is quieter: ${loginMotion.seen.length} parts against ${joinMotion.seen.length}, and slower`);

{
  const { page, context } = await open('login');
  const times = () => page.evaluate(() => document.getAnimations().map(a => a.currentTime));
  check((await running(page)).running > 0, 'runs at first');
  await page.getByRole('button', { name: 'Pause animation' }).click();
  // A CSS pause holds from the next frame on (each animation's `ready`), not from the click.
  await page.evaluate(() => Promise.all(document.getAnimations().map(x => x.ready)));
  const a = await times();
  await page.waitForTimeout(300);
  const b = await times();
  const state = await running(page);
  check(state.paused === state.total && state.total > 0 && a.every((t, i) => t === b[i]), `Pause stops all ${state.total} where they are`);
  await page.screenshot({ path: `${SHOTS}/login-paused-desktop.png` });
  await page.reload();
  await page.waitForSelector('.aff-wellness');
  const again = await running(page);
  check(again.paused === again.total && await page.getByRole('button', { name: 'Resume animation' }).isVisible(), 'a reload remembers the pause');
  await page.getByRole('link', { name: 'Create an account' }).click();
  await page.waitForSelector('.aff-wellness--join');
  const joined = await running(page);
  check(joined.paused === joined.total, 'going to Join keeps it paused');
  await page.getByRole('button', { name: 'Resume animation' }).click();
  const c = await running(page);
  check(c.running === c.total, 'Resume goes on');
  await context.close();
}
{
  const { page, context } = await open('join', { width: 390, height: 844 });
  await page.waitForTimeout(100);
  const top = await running(page);
  check(top.running === 0 && top.paused === top.total && top.total > 0, `on a phone, off-screen under the form, all ${top.total} rest`);
  await page.locator('.aff-wellness').scrollIntoViewIfNeeded();
  await page.waitForTimeout(150);
  const shown = await running(page);
  check(shown.running === shown.total, 'scrolled into view, they run');
  await context.close();
}

// ═════ R Reduced motion ═════
console.log('R Reduced motion');
for (const [path, width, height] of [['join', 1280, 900], ['login', 1280, 800], ['join', 390, 844], ['login', 390, 844]]) {
  const { page, context, errors } = await open(path, { width, height, reducedMotion: 'reduce' });
  const state = await page.evaluate(() => {
    const shown = s => [...document.querySelectorAll(s)];
    const visible = el => { const c = getComputedStyle(el); const r = el.getBoundingClientRect(); return c.display !== 'none' && c.visibility !== 'hidden' && Number(c.opacity) > 0 && r.width > 0 && r.height > 0; };
    return {
      animations: document.getAnimations().length,
      scenes: shown('.aff-wellness-tile svg').filter(visible).length,
      parts: Object.fromEntries(['.aff-wellness-ring', '.aff-wellness-ripple', '.aff-wellness-bubble', '.aff-wellness-bar'].map(s => [s, [shown(s).length, shown(s).filter(visible).length]])),
      toggle: getComputedStyle(document.querySelector('.aff-wellness-toggle')).display,
    };
  });
  check(state.animations === 0, `${path} at ${width}: nothing runs`);
  check(state.scenes === 3 && Object.values(state.parts).every(([all, seen]) => all > 0 && all === seen),
    `${path} at ${width}: a complete picture: ${Object.entries(state.parts).map(([k, [, seen]]) => `${seen} ${k.replace('.aff-wellness-', '')}s`).join(', ')}`);
  check(state.toggle === 'none' && errors.length === 0, `${path} at ${width}: no control to find`);
  await page.screenshot({ path: `${SHOTS}/${path}-reduced-${width < 900 ? 'mobile' : 'desktop'}.png`, fullPage: true });
  await context.close();
}

// ═════ K The keyboard ═════
console.log('K The keyboard');
async function tabOrder(page, count) {
  const order = [];
  for (let i = 0; i < count; i++) {
    await page.keyboard.press('Tab');
    order.push(await page.evaluate(() => {
      const el = document.activeElement;
      const label = el.id ? document.querySelector(`label[for="${el.id}"]`)?.textContent : null;
      return label ?? el.getAttribute('aria-label') ?? el.textContent?.trim() ?? el.tagName;
    }));
  }
  return order;
}
{
  const { page, context } = await open('login');
  const order = await tabOrder(page, 7);
  const want = ['Email', 'Password', 'Show password', 'Sign In', 'Forgot password?', 'Create an account', 'Pause animation'];
  check(JSON.stringify(order) === JSON.stringify(want), `Sign in: ${order.join(' > ')}`);
  const ring = await page.evaluate(() => { const c = getComputedStyle(document.activeElement); return `${c.outlineStyle} ${c.outlineWidth}`; });
  check(ring === 'solid 2px', `the control shows its focus (${ring})`);
  await page.screenshot({ path: `${SHOTS}/login-focus-desktop.png` });
  await page.keyboard.press('Space');
  check(await page.evaluate(() => document.activeElement.textContent.trim()) === 'Resume animation' && (await running(page)).running === 0, 'Space pauses, and focus stays');
  await page.keyboard.press('Enter');
  check(await page.evaluate(() => document.activeElement.textContent.trim()) === 'Pause animation' && (await running(page)).paused === 0, 'Enter resumes');
  await context.close();
}
{
  const { page, context } = await open('join');
  const order = await tabOrder(page, 14);
  // The terms box has its name from the label around it, read here as ''.
  const want = ['First Name', 'Last Name', 'Country calling code', 'Phone Number', 'Email', 'Password', 'Show password', 'Confirm Password', 'Show password',
    '', 'Energia Affiliate terms', 'Create Account', 'Sign in', 'Pause animation'];
  check(JSON.stringify(order) === JSON.stringify(want), `Join: ${order.join(' > ')}`);
  await context.close();
}

{
  const { page, context } = await open('join');
  const ratios = await page.evaluate(() => {
    const parts = c => c.match(/[\d.]+/g).slice(0, 3).map(Number);
    const light = ([r, g, b]) => { const f = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; }; return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b); };
    const against = light([0xf8, 0xf7, 0xf2]);
    return ['.aff-wellness-headline', '.aff-wellness-accent', '.aff-wellness-support', '.aff-wellness-caption', '.aff-wellness-toggle'].map(s => {
      const l = light(parts(getComputedStyle(document.querySelector(s)).color));
      return { s, ratio: Math.round(((against + 0.05) / (l + 0.05)) * 100) / 100 };
    });
  });
  check(ratios.every(r => r.ratio >= 4.5), `readable: ${ratios.map(r => `${r.s.replace('.aff-wellness-', '')} ${r.ratio}:1`).join(', ')}`);
  await context.close();
}

// ═════ V The form's own states ═════
console.log('V The form\'s own states');
const inForm = (page, locator) => page.locator('.aff-wellness-form').locator(locator);
{
  const { page, context } = await open('login', { init: () => { window.__wait = 300; } });
  await page.getByLabel('Email').fill('ada.preview@example.com');
  await page.getByLabel('Password', { exact: true }).fill('not-the-password');
  await page.getByRole('button', { name: 'Show password' }).click();
  check(await page.getByLabel('Password', { exact: true }).getAttribute('type') === 'text', 'showing the password works');
  await page.getByRole('button', { name: 'Hide password' }).click();
  await page.getByRole('button', { name: 'Sign In' }).click();
  check(await page.getByRole('button', { name: 'Signing in…' }).isVisible(), 'Signing in… while it waits');
  await inForm(page, '[role="alert"]').waitFor();
  check(await inForm(page, '[role="alert"]').innerText() === 'Invalid login credentials', 'the wrong password is told, in the card');
  check(await page.getByLabel('Email').inputValue() === 'ada.preview@example.com' && await page.evaluate(() => window.__signIns) === 1, 'what was typed stays; one sign-in was tried');
  await page.screenshot({ path: `${SHOTS}/login-error-desktop.png` });
  await context.close();
}
{
  const { page, context } = await open('login', { init: () => { window.__unconfirmed = true; } });
  await page.getByLabel('Email').fill('ada.preview@example.com');
  await page.getByLabel('Password', { exact: true }).fill('not-the-password');
  await page.getByLabel('Password', { exact: true }).press('Enter');
  await page.getByRole('button', { name: 'Send the sign-up link again' }).waitFor();
  check(true, 'Enter signs in; a sign-up not switched on can have its link sent again');
  await context.close();
}
{
  const { page, context } = await open('join', { width: 390, height: 844, init: () => { window.__signedIn = true; } });
  const say = async () => inForm(page, '[role="alert"]').innerText();
  const send = () => page.getByRole('button', { name: 'Create Account' }).click();
  await send();
  check(await say() === 'Please fill in your name, phone and email.', 'Join with nothing filled: told in the card');
  await page.getByLabel('First Name').fill('Ada');
  await page.getByLabel('Email').fill('ada.preview@example.com');
  await page.getByPlaceholder('Phone number').fill('123');
  await send();
  check(await say() === 'Enter a valid international phone number.', 'a phone that cannot be right: told');
  const countries = await page.locator('.aff-wellness-form select').first().locator('option').count();
  check(countries > 100, `the phone's country list is there (${countries} countries)`);
  await page.locator('.aff-wellness-form select').first().selectOption('AU');
  await page.getByPlaceholder('Phone number').fill('491570156');
  await page.getByLabel('Password', { exact: true }).fill('short');
  await send();
  check(await say() === 'Password must be at least 8 characters.', 'a short password: told');
  await page.getByLabel('Password', { exact: true }).fill('a-long-password');
  await page.getByLabel('Confirm Password').fill('a-different-password');
  await send();
  check(await say() === 'Passwords do not match.', 'passwords that differ: told');
  await page.getByLabel('Confirm Password').fill('a-long-password');
  await send();
  check(await say() === 'Please agree to the Affiliate terms to continue.', 'terms not ticked: told');
  check(await page.evaluate(() => window.__invoked ?? []).then(i => i.length === 0), 'none of those sent anything');
  check(await inForm(page, '[data-note="signed-in-elsewhere"]').isVisible(), 'the signed-in notice shows');
  const box = await rect(page, '.aff-wellness-form input[type="checkbox"]');
  const words = await rect(page, '.aff-wellness-form label:has(input[type="checkbox"]) span');
  check(box.width < 24 && words.left - box.right < 16, `the terms box sits beside its words (box ${Math.round(box.width)}px wide)`);
  await page.screenshot({ path: `${SHOTS}/join-error-mobile.png`, fullPage: true });
  await page.getByRole('link', { name: 'Energia Affiliate terms' }).waitFor();
  await page.locator('.aff-wellness-form input[type="checkbox"]').check();
  await send();
  await inForm(page, '[role="alert"]').waitFor();
  check((await page.evaluate(() => window.__invoked)).join() === 'auth-signup-request', 'all filled: the one sign-up request goes to the stub, as before');
  await context.close();
}

// ═════ Pictures for the report ═════
for (const [name, path, width, height, full] of [
  ['login-desktop', 'login', 1280, 800, false], ['join-desktop', 'join', 1280, 900, false],
  ['login-mobile', 'login', 390, 844, true], ['join-mobile', 'join', 390, 844, true],
]) {
  const { page, context } = await open(path, { width, height, reducedMotion: 'no-preference' });
  await page.locator('.aff-wellness').scrollIntoViewIfNeeded();
  await page.waitForTimeout(200);
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: full });
  await context.close();
}

await browser.close();
if (failures) { console.log(`\n${failures} check(s) failed`); process.exit(1); }
console.log('\nAll wellness panel checks passed.');
