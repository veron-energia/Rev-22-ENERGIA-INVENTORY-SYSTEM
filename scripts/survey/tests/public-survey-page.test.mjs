// Behaviour tests for the public health-survey page: unsaved-changes
// protection, inline validation + focus-to-first-error, failed-submit data
// retention, server-error routing, and successful-submit teardown.
//
// These are JSDOM tests. Real browser navigation / focus / scroll / touch and
// signature drawing are covered by the manual checklist, not here.
//
// Run: node --test scripts/survey/tests/public-survey-page.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

// JSDOM globals must exist before react-dom is loaded, or it falls back to its
// legacy IE input polyfill and blows up on focus/blur.
const dom = new JSDOM('<!doctype html><html><body></body></html>', { url: 'https://example.test/survey/tok' });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
dom.window.Element.prototype.scrollIntoView = function () {};
dom.window.requestAnimationFrame = fn => setTimeout(() => fn(Date.now()), 0);
globalThis.requestAnimationFrame = dom.window.requestAnimationFrame;
dom.window.matchMedia = dom.window.matchMedia || (() => ({ matches: false, addEventListener() {}, removeEventListener() {}, addListener() {}, removeListener() {} }));
if (!globalThis.navigator) globalThis.navigator = dom.window.navigator;

const React = (await import('react')).default;
const { act } = await import('react');
const { createRoot } = await import('react-dom/client');
const { Simulate } = await import('react-dom/test-utils');

const require = createRequire(import.meta.url);
const dir = await mkdtemp(join(tmpdir(), 'energia-survey-page-'));

const STUBS = {
  'rrd': 'export const useParams = () => ({ token: "tok" });',
  'sb': 'export const supabase = new Proxy({}, { get: (_t, p) => globalThis.__SB__[p] });',
  'pdf': 'export const buildSurveyPdf = () => "JVBER";',
  'types': 'export {};',
  'css': '',
  'lucide': `
    import React from 'react';
    const Icon = (p) => React.createElement('span', { 'aria-hidden': 'true' });
    export const Leaf = Icon, CheckCircle2 = Icon, AlertTriangle = Icon, RefreshCw = Icon,
      Eraser = Icon, X = Icon, Check = Icon, Info = Icon;`,
  'sign': `
    import React from 'react';
    export default function SignaturePad(props) {
      return React.createElement('button', {
        type: 'button', id: 'stub-sign',
        onClick: () => props.onChange('data:image/png;base64,SIG'),
      }, 'sign');
    }`,
};

await build({
  entryPoints: ['src/pages/PublicSurveyPage.tsx'],
  outfile: join(dir, 'page.mjs'),
  bundle: true, format: 'esm', platform: 'node', jsx: 'automatic',
  plugins: [{
    name: 'stubs',
    setup(b) {
      b.onResolve({ filter: /^react(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
      b.onResolve({ filter: /^react-dom(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
      b.onResolve({ filter: /^react-router-dom$/ }, () => ({ path: 'rrd', namespace: 's' }));
      b.onResolve({ filter: /^lucide-react$/ }, () => ({ path: 'lucide', namespace: 's' }));
      b.onResolve({ filter: /\.css$/ }, () => ({ path: 'css', namespace: 's' }));
      b.onResolve({ filter: /\/lib\/supabase$/ }, () => ({ path: 'sb', namespace: 's' }));
      b.onResolve({ filter: /\/lib\/surveyPdf$/ }, () => ({ path: 'pdf', namespace: 's' }));
      b.onResolve({ filter: /\/components\/SignaturePad$/ }, () => ({ path: 'sign', namespace: 's' }));
      b.onResolve({ filter: /\/types$/ }, () => ({ path: 'types', namespace: 's' }));
      b.onLoad({ filter: /.*/, namespace: 's' }, a => ({ contents: STUBS[a.path], loader: 'jsx' }));
    },
  }],
});
const { default: PublicSurveyPage } = await import(pathToFileURL(join(dir, 'page.mjs')).href);

const SOURCES = [
  { id: 's1', label: 'Facebook', requires_details: false },
  { id: 's2', label: 'A friend', requires_details: true },
  { id: 's3', label: 'Roadshow / Event', requires_details: false },
];

function makeSupabase({ linkInfo, submit } = {}) {
  return {
    rpc: async (name, params) => {
      if (name === 'survey_link_info') return { data: linkInfo ?? { valid: true, store_name: 'Test Store', event_name: null } };
      if (name === 'active_customer_source_options') return { data: SOURCES };
      if (name === 'submit_health_survey') return submit ? submit(params) : { data: { survey_no: 'HS-OK' } };
      return { data: null };
    },
    from: () => {
      const chain = { select: () => chain, eq: () => chain, order: () => Promise.resolve({ data: [] }) };
      return chain;
    },
  };
}

async function mount(sbOpts) {
  globalThis.__SB__ = makeSupabase(sbOpts);
  const node = document.createElement('div');
  document.body.appendChild(node);
  const root = createRoot(node);
  await act(async () => { root.render(React.createElement(PublicSurveyPage)); });
  await act(async () => { await new Promise(r => setTimeout(r, 5)); });
  const $ = sel => node.querySelector(sel);
  const $all = sel => [...node.querySelectorAll(sel)];
  return {
    node, $, $all,
    text: () => node.textContent,
    async change(sel, value) {
      await act(async () => { Simulate.change($(sel), { target: { value } }); });
    },
    async click(sel) {
      await act(async () => { Simulate.click($(sel)); });
      await act(async () => { await new Promise(r => setTimeout(r, 5)); });
    },
    async submitForm() {
      // jsdom does not turn a submit-button click into a submit event.
      await act(async () => { Simulate.submit(node.querySelector('form')); });
      await act(async () => { await new Promise(r => setTimeout(r, 10)); });
    },
    beforeUnloadPrevented() {
      const e = new dom.window.Event('beforeunload', { cancelable: true });
      dom.window.dispatchEvent(e);
      return e.defaultPrevented;
    },
    async fillValid() {
      await this.change('#sv-first-name', 'Jamie');
      await this.change('.phone-input select', 'SG');
      await this.change('.phone-input input', '91234567');
      await this.change('#sv-email', 'jamie@example.com');
      await this.change('#sv-source', 's1');
      await this.click('#stub-sign');
    },
    close() { act(() => root.unmount()); node.remove(); },
  };
}

test('untouched form does not arm the leave warning', async () => {
  const ui = await mount();
  try {
    assert.ok(/New Customer Form/.test(ui.text()));
    assert.equal(ui.beforeUnloadPrevented(), false);
  } finally { ui.close(); }
});

test('typing in any field arms the leave warning; clearing it disarms', async () => {
  const ui = await mount();
  try {
    await ui.change('#sv-first-name', 'Jamie');
    assert.equal(ui.beforeUnloadPrevented(), true);
    await ui.change('#sv-first-name', '');
    assert.equal(ui.beforeUnloadPrevented(), false);
  } finally { ui.close(); }
});

test('signature (via its onChange) also arms the warning', async () => {
  const ui = await mount();
  try {
    await ui.click('#stub-sign');
    assert.equal(ui.beforeUnloadPrevented(), true);
  } finally { ui.close(); }
});

test('submit with an empty form shows inline errors and focuses the first one', async () => {
  const ui = await mount();
  try {
    await ui.submitForm();
    const errs = ui.$all('.survey-field-error');
    assert.ok(errs.length >= 4, `expected several inline errors, got ${errs.length}`);
    assert.equal(document.activeElement?.id, 'sv-first-name');
    assert.ok(/highlighted field/.test(ui.text()));
    // Nothing was submitted.
    assert.ok(!/Thank you/.test(ui.text()));
  } finally { ui.close(); }
});

test('correcting the first error moves focus to the next, not back again', async () => {
  const ui = await mount();
  try {
    await ui.submitForm();
    assert.equal(document.activeElement?.id, 'sv-first-name');
    await ui.change('#sv-first-name', 'Jamie');
    // first_name error clears live, without stealing focus back
    assert.equal(ui.$('#err-first-name'), null);
    assert.equal(document.activeElement?.id, 'sv-first-name');
    await ui.submitForm();
    assert.equal(document.activeElement?.id, 'sv-phone');
  } finally { ui.close(); }
});

test('conditional source-details error routes to the details input', async () => {
  const ui = await mount();
  try {
    await ui.fillValid();
    await ui.change('#sv-source', 's2'); // "A friend" -> requires details
    await ui.submitForm();
    assert.ok(ui.$('#err-source-details'), 'inline error beside the details input');
    assert.equal(document.activeElement?.id, 'sv-source-details');
  } finally { ui.close(); }
});

test('failed submit keeps every answer and the signature, and shows a message near Submit', async () => {
  const ui = await mount({ submit: () => ({ error: { message: 'could not connect to database xyz' } }) });
  try {
    await ui.fillValid();
    await ui.submitForm();
    assert.equal(ui.$('#sv-first-name').value, 'Jamie');
    assert.equal(ui.$('#sv-email').value, 'jamie@example.com');
    assert.ok(ui.$('.survey-form-error'), 'a form-level error is shown');
    assert.ok(!/xyz/.test(ui.text()), 'raw DB text is not exposed');
    assert.ok(!/Thank you/.test(ui.text()));
  } finally { ui.close(); }
});

test('existing-survey error is shown near identity with staff guidance', async () => {
  const ui = await mount({ submit: () => ({ error: { message: 'HEALTH_SURVEY_ALREADY_EXISTS' } }) });
  try {
    await ui.fillValid();
    await ui.submitForm();
    const alert = ui.$('.survey-identity-alert');
    assert.ok(alert);
    assert.ok(/consultant/i.test(alert.textContent));
  } finally { ui.close(); }
});

test('phone capacity error is shown beside the phone field', async () => {
  const ui = await mount({ submit: () => ({ error: { message: 'CUSTOMER_PHONE_LIMIT: belongs to 3 customers' } }) });
  try {
    await ui.fillValid();
    await ui.submitForm();
    assert.ok(/3 non-deleted customers/.test(ui.$('#err-phone')?.textContent ?? ''));
  } finally { ui.close(); }
});

test('successful submit shows the reference and removes the leave warning', async () => {
  const ui = await mount({ submit: () => ({ data: { survey_no: 'HS-20260908-abcdef' } }) });
  try {
    await ui.fillValid();
    assert.equal(ui.beforeUnloadPrevented(), true);
    await ui.submitForm();
    assert.ok(/Thank you/.test(ui.text()));
    assert.ok(/HS-20260908-abcdef/.test(ui.text()));
    assert.equal(ui.beforeUnloadPrevented(), false);
  } finally { ui.close(); }
});

test('event-linked survey link hides the "how did you hear" question', async () => {
  const ui = await mount({ linkInfo: { valid: true, store_name: 'Roadshow Store', event_name: 'Expo 2026' } });
  try {
    assert.equal(ui.$('#sv-source'), null);
    await ui.change('#sv-first-name', 'Sam');
    await ui.change('.phone-input select', 'SG');
    await ui.change('.phone-input input', '91234567');
    await ui.change('#sv-email', 'sam@example.com');
    await ui.click('#stub-sign');
    await ui.submitForm();
    assert.ok(/Thank you/.test(ui.text()));
  } finally { ui.close(); }
});

test('invalid link shows the unavailable screen', async () => {
  const ui = await mount({ linkInfo: { valid: false, reason: 'This survey link has expired.' } });
  try {
    assert.ok(/Survey unavailable/.test(ui.text()));
    assert.ok(/expired/.test(ui.text()));
  } finally { ui.close(); }
});

test.after(async () => { dom.window.close(); await rm(dir, { recursive: true, force: true }); });
